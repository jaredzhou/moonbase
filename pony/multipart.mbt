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
/// ## Examples
/// ```
/// "multipart/form-data; boundary=----WebKit"  →  "----WebKit"
/// "multipart/form-data; boundary=\"--abc\""   →  "--abc"
/// "multipart/form-data; charset=utf-8; boundary=foo" → "foo"
/// ```
///
/// ## How it works
///
/// 1. Do a case‑insensitive search for `"boundary="` in the header value
///    (using a lowercased copy).  RFC 2046 says the parameter name is
///    case‑insensitive.
///
/// 2. Extract the value portion **from the original string** so the
///    boundary itself retains its original case.  RFC 2046 §5.1.1 says
///    boundary values ARE case‑sensitive.
///
/// 3. Peel off optional surrounding double‑quotes and trailing `;`
///    / whitespace via a functional `for` loop with `continue`/`break`.
fn boundary_from(content_type : String) -> String raise {
  let lower = content_type.to_lower()
  let prefix = "boundary="

  // Find "boundary=" position (case‑insensitive, via lowercased copy)
  let bp_pos = lower.find(prefix)
  guard bp_pos is Some(pos) else {
    raise MultipartError::MissingBoundary
  }

  let rest = content_type[pos + prefix.length():]
  // Quoted: value between quotes is the pure boundary.
  // Unquoted: trim whitespace,  ';' if present.
  match rest {
    [] => raise MultipartError::MissingBoundary
    ['"', ..inner, '"'] => inner.to_owned()
    _ => rest.trim(chars = "; ").to_owned() 
  }
}

// -- byte-level primitives ---------------------------------------------

/// Advance one line from `data`.
///
/// Returns `Some((line, rest))` where `line` is the content before the
/// Decode bytes as a UTF-8 string.
fn to_utf8_string(data : BytesView) -> String {
  @utf8.decode_lossy(data.to_owned())
}

// -- part header parsing -----------------------------------------------

/// Parse MIME part headers from `data`.
///
/// Returns `(headers, rest)` where `rest` is the bytes immediately
/// after the blank line that terminates the headers (i.e. the body).
fn read_part_headers(
  data : BytesView,
) -> (Map[String, String], BytesView) raise {
  let headers : Map[String, String] = {}

  for rest = data {
    match rest {
      [..b"\r\n", ..rest] | [..b"\n", ..rest] => return (headers, rest)
      _ => {
        let (line_end, skip) = match rest.find(b"\r\n") {
          Some(pos) => (pos, 2)
          None => match rest.find(b"\n") {
            Some(pos) => (pos, 1)
            None => raise MultipartError::MalformedBody("part header: no CRLF")
          }
        }

        let line_str = to_utf8_string(rest[:line_end])
        guard line_str.find(":") is Some(colon) else {
          raise MultipartError::MalformedBody("part header: \{line_str}")
        }

        let key = line_str[:colon].trim().to_owned()
        let value = line_str[colon + 1:].trim().to_owned()
        headers[key] = value
        continue rest[line_end + skip:]
      }
    }
  } nobreak {
    raise MultipartError::MalformedBody("no blank line found")
  }
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
fn next_part(
  part_data : BytesView,
  form : MultipartForm,
) -> Unit raise {
  let (part_headers, body) = read_part_headers(part_data)

  let cd = match part_headers.get("Content-Disposition") {
    Some(v) => v
    None => raise MultipartError::MalformedBody("missing Content-Disposition")
  }

  let (name, filename) = split_content_disposition(cd)

  guard name.length() > 0 else {
    raise MultipartError::MissingName
  }

  let content_type = part_headers.get("Content-Type")

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
      let field_text = to_utf8_string(body)
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
  let delimiter = (b"--" + @utf8.encode(boundary))[:]
  let final_delimiter = (b"--" + @utf8.encode(boundary) + b"--")[:]
  let form = MultipartForm::new()

  // Skip preamble — seek to the first `--boundary`
  let rest = match body[:].find(delimiter) {
    Some(pos) => body[pos:]
    None => raise MultipartError::MalformedBody("boundary not found")
  }

  for rest = rest {
    let (delim, rest) = next_boundary(rest)
    match delim {
      d if d == final_delimiter => break
      d if d == delimiter => {
        let (part, rest) = cut_part(rest, delimiter)
        next_part(part, form)
        continue rest
      }
      _ => raise MultipartError::MalformedBody("missing boundary")
    }
  }

  form
}

/// Extract the boundary line from the front of `data` and skip its CRLF.
fn next_boundary(data : BytesView) -> (BytesView, BytesView) {
  let line_end = match data.find(b"\r\n") {
    Some(pos) => pos
    None => data.length()
  }
  let delim = data[:line_end]
  let after = if data[line_end:].has_prefix(b"\r\n") {
    data[line_end + 2:]
  } else if data[line_end:].has_prefix(b"\n") {
    data[line_end + 1:]
  } else {
    data[line_end:]
  }
  (delim, after)
}

/// Cut the part content from `data` up to the next `marker`.
fn cut_part(data : BytesView, marker : BytesView) -> (BytesView, BytesView) raise {
  match data.find(marker) {
    Some(pos) => {
      let content = data[:pos]
      let part = if content.has_suffix(b"\r\n") {
        content[:content.length() - 2]
      } else if content.has_suffix(b"\n") {
        content[:content.length() - 1]
      } else {
        content
      }
      (part, data[pos:])
    }
    None => raise MultipartError::MalformedBody("missing boundary")
  }
}

// ============================================================================
// Streaming multipart reader
// ============================================================================

/// Chunk size for streaming reads (8 KiB).
let stream_chunk_size : Int = 8192

/// Streaming multipart reader — yields parts without buffering the
/// entire body.  File data is streamed in chunks: small files stay
/// in memory, large ones spill to temporary disk files.
struct MultipartReader {
  source : &@io.Reader
  delimiter : Bytes          // "--boundary"
  mut lookback : @buffer.Buffer
  mut done : Bool
}

fn MultipartReader::new(source : &@io.Reader, boundary : String) -> MultipartReader {
  let delim = b"--" + @utf8.encode(boundary)
  {
    source,
    delimiter: delim,
    lookback: @buffer.Buffer::Buffer(),
    done: false,
  }
}

/// Produce the next part from the stream.
///
/// Returns `Some((headers, UploadedFile))` or `None` when the final
/// boundary is consumed.
///
/// * Form fields (no filename): body is `Memory(Bytes)` — decode with `to_utf8_string`.
/// * Files: body is `Memory(Bytes)` or `Disk(path)` per `max_memory`.
///
/// The first call skips any preamble bytes before the initial `--boundary`.
async fn MultipartReader::next_part(
  self : MultipartReader,
  max_memory : Int64,
  temp_dir : String,
) -> (Map[String, String], UploadedFile)? {
  guard self.done is false else {
    return None
  }

  // -- Read headers until blank line ------------------------------------
  let headers : Map[String, String] = {}
  while true {
    let line = match self.source.read_until("\r\n") {
      Some(s) => s
      None => break
    }
    guard line.length() > 0 else {
      break
    }
    guard line.find(":") is Some(colon) else { continue }
    let key = line[:colon].trim().to_owned()
    let value = line[colon + 1:].trim().to_owned()
    headers[key] = value
  }

  let content_type = headers.get("Content-Type")

  // -- Drain body streamingly --------------------------------------------
  let accum = BodyAccum::new(max_memory, temp_dir)

  while self.done is false {
    let chunk = self.source.read_some(max_len=stream_chunk_size)
    match chunk {
      Some(data) => {
        // Merge lookback + new data for boundary scan
        let buf = if self.lookback.length() == 0 {
          data
        } else {
          let lb = self.lookback.to_bytes()
          self.lookback = @buffer.Buffer::Buffer()
          let m = @buffer.Buffer::Buffer()
          m.write_bytes(lb)
          m.write_bytes(data)
          m.to_bytes()
        }
        match buf[:].find(self.delimiter[:]) {
          Some(pos) => {
            let body_end = if pos >= 2 && buf[pos - 2] == b'\r' && buf[pos - 1] == b'\n' {
              pos - 2
            } else if pos >= 1 && buf[pos - 1] == b'\n' {
              pos - 1
            } else {
              pos
            }
            if body_end > 0 {
              accum.append(buf[0:body_end].to_owned())
            }
            let after = buf[pos + self.delimiter.length():]
            if after.has_prefix(b"--") { self.done = true }
            break
          }
          None => {
            let keep = self.delimiter.length() + 2
            if buf.length() > keep {
              accum.append(buf[0:buf.length() - keep].to_owned())
              self.lookback.write_bytes(buf[buf.length() - keep:])
            } else {
              self.lookback.write_bytes(buf)
            }
          }
        }
      }
      None => break
    }
  }

  // Flush any remaining lookback bytes
  if self.lookback.length() > 0 {
    accum.append(self.lookback.to_bytes())
    self.lookback = @buffer.Buffer::Buffer()
  }

  let backend = accum.finish()
  Some((headers, UploadedFile::{
    header: FileHeader::{ filename: "", size: accum.total, content_type, header: headers },
    backend,
  }))
}

/// Match body data to memory or disk.  Spills when total exceeds
/// `max_memory`.  Call `append()` for each chunk, then `finish()`.
struct BodyAccum {
  mut buf : @buffer.Buffer
  mut total : Int64
  mut disk_path : String
  mut disk_file : @fs.File?
  max_memory : Int64
  temp_dir : String
}

fn BodyAccum::new(max_memory : Int64, temp_dir : String) -> BodyAccum {
  {
    buf: @buffer.Buffer::Buffer(),
    total: 0,
    disk_path: "",
    disk_file: None,
    max_memory,
    temp_dir,
  }
}

async fn BodyAccum::append(self : BodyAccum, data : Bytes) -> Unit {
  let inc = data.length().to_int64()
  self.total = self.total + inc

  if self.disk_path.length() > 0 || self.total > self.max_memory {
    if self.disk_path.length() == 0 {
      let path = "\{self.temp_dir}/pony-multipart-\{random_hex(8)}"
      self.disk_file = Some(@fs.create(path) catch { _ => return })
      self.disk_file.unwrap().write(self.buf.to_bytes()[:]) |> ignore
      self.buf = @buffer.Buffer::Buffer()
      self.disk_path = path
    }
    match self.disk_file {
      Some(f) => f.write(data[:]) |> ignore
      _ => ()
    }
  } else {
    self.buf.write_bytes(data)
  }
}

fn BodyAccum::finish(self : BodyAccum) -> FileBackend {
  if self.disk_path.length() > 0 {
    match self.disk_file {
      Some(f) => f.close()
      _ => ()
    }
    Disk(self.disk_path)
  } else {
    Memory(self.buf.to_bytes())
  }
}
