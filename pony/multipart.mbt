// multipart.mbt — multipart/form-data parsing
//
// Relevant specifications:
//   RFC 7578       Returning Values from Forms: multipart/form-data
//   RFC 2046 §5.1  Multipart Media Type — boundary delimiter syntax
//   RFC 2183 §2    Content-Disposition — filename parameter
//
// ============================================================================
// Quick Start
// ============================================================================
//
// The simplest way to handle a multipart file upload is through
// `Context::parse_multipart_form`.  Behind the scenes it:
//
//   1. Parses the raw body into memory  (sync)
//   2. Spills files that exceed `max_memory` to temp disk  (async)
//   3. Cleans up temp files when the request finishes  (async)
//
// ```moonbit nocheck
// fn upload_handler : Handler = async fn(ctx) {
//   // Step 1 — parse the multipart body (default 32 MiB memory threshold).
//   // Raises MultipartError if the body is malformed or missing a boundary.
//   ctx.parse_multipart_form(max_memory=64 * 1024 * 1024)!  // 64 MiB
//
//   // Step 2 — read regular form fields via ctx.form().
//   // After parsing, form() bridges to the multipart fields automatically.
//   let username = ctx.form("username").unwrap_or("anonymous")
//   let title    = ctx.form("title").unwrap_or("")
//
//   // Step 3 — access uploaded files.
//   match ctx.form_file("avatar") {
//     Some(file) => {
//       let header = file.header()          // FileHeader { filename, size, … }
//       let data   = file.bytes()           // Bytes — reads from disk if needed
//
//       // … save to storage, resize, etc. …
//       println("received \{header.filename} (\{header.size} bytes)")
//       println("content type: \{header.content_type.unwrap_or("unknown")}")
//     }
//     None => ctx.write_text(400, "avatar is required")
//   }
//
//   // Step 4 — access multiple files under the same field name.
//   for doc in ctx.form_files("attachments") {
//     println("attachment: \{doc.header().filename}")
//   }
//
//   // Step 5 — respond.  Temp files are cleaned up automatically
//   // by the framework after the handler returns.
//   ctx.response_ok({"user": username, "title": title})
// }
// ```
//
// ============================================================================
// How a multipart body looks on the wire
// ============================================================================
//
// Client sends a POST with `Content-Type: multipart/form-data; boundary=----Boundary`.
// The body is a sequence of parts separated by boundary delimiters:
//
//   ------Boundary\r\n                                    ← part separator
//   Content-Disposition: form-data; name="username"\r\n   ← part header
//   \r\n                                                   ← blank line
//   alice\r\n                                              ← part body
//   ------Boundary\r\n                                    ← next separator
//   Content-Disposition: form-data; name="avatar"; filename="cat.png"\r\n
//   Content-Type: image/png\r\n
//   \r\n
//   <binary PNG data>\r\n
//   ------Boundary--\r\n                                   ← final delimiter
//
// Each part is:
//   • A boundary line: `--` followed by the boundary value.
//   • MIME headers (Content-Disposition is required; Content-Type is optional).
//   • A blank line (empty `\r\n`).
//   • The body content.
//
// The final delimiter appends `--` after the boundary value.
//
// ============================================================================
// Architecture
// ============================================================================
//
// The module is split into three layers to keep the parsing synchronous
// and testable while still supporting async disk I/O for large files:
//
//   Layer                     Async?   Purpose
//   ────────────────────────  ───────  ──────────────────────────
//   parse_multipart(..)       sync     Pure in‑memory parsing.
//                                      All file content stays in RAM.
//                                      ✅ callable from test functions.
//
//   MultipartForm::           async    Walk every file; when its size
//     spill_large_files_to_disk         exceeds max_memory, write it
//                                      to a unique temp file under the
//                                      temp directory.
//
//   Context::                 async    Orchestrator: parse → spill →
//     parse_multipart_form              store on context → auto‑cleanup.
//
// Context::parse_multipart_form is the public entry point.  Every
// file is first buffered in memory by parse_multipart, then
// spill_large_files_to_disk moves oversized ones to disk in a second
// pass.  This two‑phase approach keeps the parser pure and testable
// while deferring I/O to the async runtime.

/// Default memory threshold: 32 MiB.
/// Files larger than this are written to temporary disk files
/// (via `MultipartForm::spill_to_disk`).
pub let default_max_memory : Int64 = 32 * 1024 * 1024

/// Errors that may occur during multipart parsing.
pub(all) suberror MultipartError {
  MissingBoundary
  MissingName
  MalformedBody(String)
  FileTooLarge(String, Int64)
  FileIOError(String)
} derive(Debug)

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Metadata for a single uploaded file.
/// Fields mirror Go's `mime/multipart.FileHeader`.
pub(all) struct FileHeader {
  /// Original filename from the `Content-Disposition` header.
  filename : String
  /// Uncompressed size in bytes.
  size : Int64
  /// MIME type from the part header, e.g. `"image/png"`.
  content_type : String?
  /// Raw MIME part headers (canonical keys).
  header : Map[String, String]
}

/// Where the uploaded file content lives.
enum FileBackend {
  Memory(Bytes)
  Disk(String)  // path to temporary file
}

/// An uploaded file, as parsed from a multipart/form-data request.
pub(all) struct UploadedFile {
  header : FileHeader
  backend : FileBackend
}

/// Return the file's metadata (filename, size, content type, headers).
pub fn UploadedFile::header(self : UploadedFile) -> FileHeader {
  self.header
}

/// Read the entire file content as `Bytes`.
///
/// * For files that fit in memory: returns immediately.
/// * For files spilled to disk: reads from the temp file.
///
/// Must be called from an `async` context.
pub async fn UploadedFile::bytes(self : UploadedFile) -> Bytes {
  match self.backend {
    Memory(b) => b
    Disk(path) => @fs.read_file(path).binary()
  }
}

// ---------------------------------------------------------------------------
// Internal form container
// ---------------------------------------------------------------------------

/// Accumulator for a parsed multipart form.
/// Holds both regular fields (via `Values`) and file uploads.
struct MultipartForm {
  values : Values
  files : Map[String, Array[UploadedFile]]
}

fn MultipartForm::new() -> MultipartForm {
  { values: Values::new(), files: {} }
}

fn MultipartForm::field_value(self : MultipartForm, key : String) -> String? {
  self.values.get(key)
}

fn MultipartForm::file_of(self : MultipartForm, key : String) -> UploadedFile? {
  match self.files.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

fn MultipartForm::files_of(self : MultipartForm, key : String) -> Array[UploadedFile] {
  self.files.get(key).unwrap_or([])
}

/// Walk every file field and, when its size exceeds `max_memory`,
/// write it to a unique temp file under `temp_dir`.
///
/// Must be called from an `async` context (typically inside
/// `Context::parse_multipart_form`).
async fn MultipartForm::spill_large_files_to_disk(
  self : MultipartForm,
  max_memory : Int64,
  temp_dir : String,
) -> Unit {
  for field_name, file_arr in self.files{
    let new_files = Array::new()
    for file in file_arr {
      match file.backend {
        Memory(b) if b.length().to_int64() > max_memory => {
          let path = "\{temp_dir}/pony-multipart-\{random_hex(8)}"
          @fs.write_file(path, b, create_mode=CreateNew) catch { _ => () }
          new_files.push(UploadedFile::{ header: file.header, backend: Disk(path) })
        }
        _ => new_files.push(file)
      }
    }
    self.files[field_name] = new_files
  }
}

/// Remove every temporary disk file held by this form.
/// Safe to call when no disk files exist (no-op).
async fn MultipartForm::cleanup(self : MultipartForm) -> Unit {
  for _, file_arr in self.files {
    for file in file_arr {
      match file.backend {
        Disk(path) => @fs.remove(path) catch { _ => () }
        Memory(_) => ()
      }
    }
  }
}

// ============================================================================
// Parsing helpers
// ============================================================================

// -- boundary extraction -----------------------------------------------

/// Extract the boundary string from a `Content-Type` header value.
///
/// ## Example
/// ```
/// "multipart/form-data; boundary=----WebKit"  →  "----WebKit"
/// "multipart/form-data; boundary=\"--abc\""   →  "--abc"
/// ```
fn boundary_from(content_type : String) -> String raise {
  let lower = content_type.to_lower()

  // Find "boundary=" (case-insensitive)
  let prefix = "boundary="
  let mut idx : Int = -1
  for i in 0..<=(lower.length() - prefix.length()) {
    if lower[i:].has_prefix(prefix) {
      idx = i
      break
    }
  }

  let boundary = match idx {
    -1 => raise MultipartError::MissingBoundary
    i => {
      let rest : String = content_type[i + prefix.length():].to_owned()
      if rest.has_prefix("\"") {
        // Quoted: "----foo" → ----foo
        let inner = rest[1:].to_owned()
        match find_closing_quote(inner) {
          Some(end) => inner[:end].to_owned()
          None => inner
        }
      } else {
        // Unquoted: take until ; or space
        let end = find_terminator(rest)
        rest[:end].to_owned()
      }
    }
  }

  guard boundary.length() > 0 else {
    raise MultipartError::MissingBoundary
  }
  boundary
}

/// Return the index of the first `"` in `s`, or `None`.
fn find_closing_quote(s : String) -> Int? {
  for i in 0..<s.length() {
    if s[i] == '"' {
      return Some(i)
    }
  }
  None
}

/// Return the index of the first `;` or ` ` in `s`, or `s.length()` if none found.
fn find_terminator(s : String) -> Int {
  for i in 0..<s.length() {
    if s[i] == ';' || s[i] == ' ' {
      return i
    }
  }
  s.length()
}

/// Return the index of the first `:` in `s`, or `-1` if none found.
fn find_colon(s : String) -> Int {
  for i in 0..<s.length() {
    if s[i] == ':' {
      return i
    }
  }
  -1
}

// -- byte-level primitives ---------------------------------------------

/// Return the first byte-index at which `needle` appears in `haystack`,
/// beginning the search at `start`. Returns `-1` when not found.
///
/// Analogous to Go's `bytes.Index`.
fn index_of_bytes(
  haystack : BytesView,
  needle : Bytes,
  start : Int,
) -> Int {
  let h_len = haystack.length()
  let n_len = needle.length()
  guard n_len > 0 && n_len <= h_len else {
    return -1
  }
  for i in start..<=(h_len - n_len) {
    let mut ok = true
    for j in 0..<n_len {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  -1
}

/// Read one line delimited by `\r\n` or `\n`.
///
/// Returns `Some((line_start, line_end, next_offset))`,
/// or `None` when `offset` is past the end of `data`.
fn read_line(
  data : BytesView,
  offset : Int,
) -> (Int, Int, Int)? {
  guard offset < data.length() else {
    return None
  }
  for i in offset..<data.length() {
    if data[i] == b'\r' && i + 1 < data.length() && data[i + 1] == b'\n' {
      return Some((offset, i, i + 2))
    }
    if data[i] == b'\n' {
      return Some((offset, i, i + 1))
    }
  }
  // No line terminator — the remainder is the last line
  Some((offset, data.length(), data.length()))
}

/// Decode a byte range as a Unicode string.
/// Only safe when the bytes are ASCII-compatible (e.g. MIME headers).
fn ascii_bytes_to_string(data : BytesView, start : Int, end : Int) -> String {
  data[start:end].to_owned().to_unchecked_string()
}

// -- part header parsing -----------------------------------------------

/// Parse MIME part headers from a byte slice.
///
/// Returns `(headers, body_offset)` where `body_offset` is the position
/// immediately after the blank line that terminates the headers.
fn read_part_headers(
  data : BytesView,
  offset : Int,
) -> (Map[String, String], Int) raise {
  let headers : Map[String, String] = {}
  let mut pos = offset

  while pos < data.length() {
    let line = match read_line(data, pos) {
      Some(l) => l
      None => raise MultipartError::MalformedBody("part headers")
    }
    let (line_start, line_end, next_pos) = line
    pos = next_pos

    // Empty line = end of headers
    guard line_start != line_end else {
      return (headers, pos)
    }

    let line_str = ascii_bytes_to_string(data, line_start, line_end)

    // Split on first colon: "Key: Value"
    let colon = find_colon(line_str)
    guard colon >= 0 else {
      raise MultipartError::MalformedBody("part header: \{line_str}")
    }

    let key = line_str[:colon].trim().to_owned()
    let value = line_str[colon + 1:].trim().to_owned()
    headers[key] = value
  }

  raise MultipartError::MalformedBody("no blank line found")
}

/// Split a `Content-Disposition` value into `(name, filename?)`.
///
/// ## Example
/// ```
/// "form-data; name=\"field1\"; filename=\"doc.txt\"" → ("field1", Some("doc.txt"))
/// ```
fn split_content_disposition(cd_value : String) -> (String, String?) {
  let mut name : String? = None
  let mut filename : String? = None
  for part in cd_value.split(";") {
    let trimmed = part.trim()
    guard !(trimmed.has_prefix("name=")) else {
      name = Some(unquote_mime_value(trimmed["name=".length():].to_owned()))
      continue
    }
    guard !(trimmed.has_prefix("filename=")) else {
      filename = Some(unquote_mime_value(trimmed["filename=".length():].to_owned()))
    }
  }
  (name.unwrap_or(""), filename)
}

/// Strip surrounding double quotes from a MIME parameter value.
///
/// ## Example
/// `"\"hello\""` → `"hello"`    `"plain"` → `"plain"`
fn unquote_mime_value(raw : String) -> String {
  let s = raw.trim()
  guard s.length() >= 2 && s[0] == '"' && s[s.length() - 1] == '"' else {
    return s.to_owned()
  }
  s[1:s.length() - 1].to_owned()
}

// -- part decoding -----------------------------------------------------

/// Decode one multipart part (headers + body) and add it to `form`.
fn decode_part(
  part_data : BytesView,
  form : MultipartForm,
) -> Unit raise {
  let (part_headers, body_offset) = read_part_headers(part_data, 0)

  let cd = match part_headers.get("Content-Disposition") {
    Some(v) => v
    None => raise MultipartError::MalformedBody("missing Content-Disposition")
  }

  let (name, filename) = split_content_disposition(cd)

  guard name.length() > 0 else {
    raise MultipartError::MissingName
  }

  let content_type = part_headers.get("Content-Type")
  let body = part_data[body_offset:]

  match filename {
    Some(fname) if fname.length() > 0 => {
      let file_body = body.to_owned()
      let file_size = file_body.length().to_int64()
      let file_header = FileHeader::{
        filename: fname,
        size: file_size,
        content_type,
        header: part_headers,
      }

      // Always buffer in memory first.
      // Large files are spilled to disk later via spill_large_files_to_disk().
      form.files
        .get_or_init(name, () => [])
        .push(UploadedFile::{ header: file_header, backend: Memory(file_body) })
    }
    _ => {
      // Regular form field (no filename)
      let field_text = ascii_bytes_to_string(body, 0, body.length())
      form.values.0.get_or_init(name, () => []).push(field_text)
    }
  }
}

/// Generate a random hex string of `n` digits.
fn random_hex(n : Int) -> String {
  let r = @random.Rand::new()
  let hex = "0123456789abcdef"
  let buf = @buffer.Buffer::Buffer()
  for _ in 0..<n {
    buf.write_byte(hex[r.int(limit=16)].to_byte())
  }
  buf.to_bytes().to_unchecked_string()
}

// ============================================================================
// Main entry point
// ============================================================================

/// Parse a `multipart/form-data` request body.
///
/// * `body`       — raw request body bytes.
/// * `content_type` — `Content-Type` header value (determines the boundary).
///
/// Returns a `MultipartForm` with all parsed fields and files.
/// All file content is held **in memory** at this stage.
/// Callers should subsequently invoke `MultipartForm::spill_large_files_to_disk`
/// (from an `async` context) to move large files to temporary disk storage.
///
/// ## Panics / errors
/// Raises `MultipartError` when the body is malformed, the boundary is
/// missing, or a part is missing a required `name`.
fn parse_multipart(
  body : Bytes,
  content_type : String,
) -> MultipartForm raise {
  let boundary = boundary_from(content_type)
  let boundary_marker = b"--" + boundary.to_bytes()
  let view = body[:]
  let form = MultipartForm::new()

  // Skip to the first boundary
  let mut pos = index_of_bytes(view, boundary_marker, 0)
  guard pos >= 0 else {
    raise MultipartError::MalformedBody("boundary not found")
  }
  pos = pos + boundary_marker.length()

  while pos < view.length() {
    // Skip the line terminator following the boundary line
    match view[pos] {
      b'\r' if pos + 1 < view.length() && view[pos + 1] == b'\n' => pos = pos + 2
      b'\n' => pos = pos + 1
      _ => ()
    }

    // Final boundary? (trailing "--")
    guard !(pos + 1 < view.length() && view[pos] == b'-' && view[pos + 1] == b'-') else {
      break
    }

    // Locate the next boundary
    let next = index_of_bytes(view, boundary_marker, pos)
    guard next >= 0 else {
      break
    }

    // Content ends before the trailing CRLF of the previous line
    let content_end = match view[next - 1] {
      b'\n' if next >= 2 && view[next - 2] == b'\r' => next - 2
      b'\n' => next - 1
      _ => next
    }

    let part_bytes = view[pos:content_end].to_owned()
    decode_part(part_bytes[:], form)

    pos = next + boundary_marker.length()

    // Trailing "--" after boundary?
    guard !(pos + 1 < view.length() && view[pos] == b'-' && view[pos + 1] == b'-') else {
      break
    }
  }

  form
}
