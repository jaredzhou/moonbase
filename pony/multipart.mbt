// multipart.mbt
// Multipart form data parsing for HTTP file uploads.

/// Default memory threshold: 32 MiB.
pub let default_max_memory : Int64 = 32 * 1024 * 1024

/// Error type for multipart parsing failures.
pub(all) suberror MultipartError {
  MissingBoundary
  MissingName
  MalformedBody(String)
  FileTooLarge(String, Int64)
  FileIOError(String)
} derive(Debug)

/// Metadata for a single uploaded file.
pub(all) struct FileHeader {
  filename : String
  size : Int64
  content_type : String?
  header : Map[String, String]
}

/// Storage backend — memory or temp file on disk.
enum UploadedFileData {
  InMemory(Bytes)
  OnDisk(String) // path to temporary file
}

/// An uploaded file from a multipart/form-data request.
pub(all) struct UploadedFile {
  header : FileHeader
  data : UploadedFileData
}

/// Return the file's metadata.
pub fn UploadedFile::header(self : UploadedFile) -> FileHeader {
  self.header
}

/// Read the full file content as bytes.
/// Works for both in-memory and on-disk files.
pub async fn UploadedFile::bytes(self : UploadedFile) -> Bytes {
  match self.data {
    InMemory(b) => b
    OnDisk(path) => @fs.read_file(path).binary()
  }
}

// ---------------------------------------------------------------------------
// Internal form storage
// ---------------------------------------------------------------------------

struct MultipartForm {
  values : Values
  files : Map[String, Array[UploadedFile]]
}

fn MultipartForm::new() -> MultipartForm {
  { values: Values::new(), files: {} }
}

fn MultipartForm::value(self : MultipartForm, key : String) -> String? {
  self.values.get(key)
}

fn MultipartForm::file(self : MultipartForm, key : String) -> UploadedFile? {
  match self.files.get(key) {
    Some(arr) if arr.length() > 0 => Some(arr[0])
    _ => None
  }
}

fn MultipartForm::file_all(self : MultipartForm, key : String) -> Array[UploadedFile] {
  self.files.get(key).unwrap_or([])
}

/// Move files exceeding `max_memory` from memory to temporary disk files.
/// Must be called from an async context (typically Context::parse_multipart_form).
async fn MultipartForm::spill_to_disk(
  self : MultipartForm,
  max_memory : Int64,
  temp_dir : String,
) -> Unit {
  for k, file_arr in self.files {
    let new_files : Array[UploadedFile] = []
    for i = 0; i < file_arr.length(); i = i + 1 {
      let f = file_arr[i]
      match f.data {
        InMemory(b) if b.length().to_int64() > max_memory => {
          let rand_hex = generate_random_hex(8)
          let path = temp_dir + "/pony-multipart-\{rand_hex}"
          @fs.write_file(path, b, create_mode=CreateNew) catch { _ => () }
          new_files.push(UploadedFile::{ header: f.header, data: OnDisk(path) })
        }
        _ => new_files.push(f)
      }
    }
    self.files[k] = new_files
  }
}

async fn MultipartForm::cleanup(self : MultipartForm) -> Unit {
  for _, file_arr in self.files {
    for f in file_arr {
      match f.data {
        OnDisk(path) => @fs.remove(path) catch { _ => () }
        InMemory(_) => ()
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Boundary extraction
// ---------------------------------------------------------------------------

fn extract_boundary(content_type : String) -> String raise {
  let lower = content_type.to_lower()
  let prefix = "boundary="
  let mut idx : Int = -1
  for i = 0; i + prefix.length() <= lower.length(); i = i + 1 {
    if lower[i:].has_prefix(prefix) {
      idx = i
      break
    }
  }
  guard idx >= 0 else {
    raise MultipartError::MissingBoundary
  }
  let rest = content_type[idx + prefix.length():]
  let boundary = if rest[0] == '"' {
    let mut end = 1
    for j = 1; j < rest.length(); j = j + 1 {
      if rest[j] == '"' {
        end = j
        break
      }
    }
    rest[1:end]
  } else {
    let mut end = rest.length()
    for j = 0; j < rest.length(); j = j + 1 {
      if rest[j] == ';' || rest[j] == ' ' {
        end = j
        break
      }
    }
    rest[:end]
  }
  let boundary = boundary.to_owned()
  if boundary.length() == 0 {
    raise MultipartError::MissingBoundary
  }
  boundary
}

// ---------------------------------------------------------------------------
// Byte-level helpers
// ---------------------------------------------------------------------------

fn find_bytes(
  haystack : BytesView,
  needle : Bytes,
  start : Int,
) -> Int {
  let h_len = haystack.length()
  let n_len = needle.length()
  if n_len == 0 || n_len > h_len {
    return -1
  }
  for i = start; i <= h_len - n_len; i = i + 1 {
    let mut ok = true
    for j = 0; j < n_len; j = j + 1 {
      if haystack[i + j] != needle[j] {
        ok = false
        break
      }
    }
    if ok {
      return i
    }
  }
  return -1
}

fn read_line(
  data : BytesView,
  offset : Int,
) -> (Int, Int, Int)? {
  if offset >= data.length() {
    return None
  }
  for i = offset; i < data.length(); i = i + 1 {
    if data[i] == b'\r' && i + 1 < data.length() && data[i + 1] == b'\n' {
      return Some((offset, i, i + 2))
    }
    if data[i] == b'\n' {
      return Some((offset, i, i + 1))
    }
  }
  Some((offset, data.length(), data.length()))
}

fn bytes_to_string(data : BytesView, start : Int, end : Int) -> String {
  data[start:end].to_owned().to_unchecked_string()
}

// ---------------------------------------------------------------------------
// Part header parsing
// ---------------------------------------------------------------------------

fn parse_part_headers(
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
    let (start, end, next_pos) = line
    pos = next_pos
    if start == end {
      return (headers, pos)
    }
    let line_str = bytes_to_string(data, start, end)

    let mut colon : Int = -1
    for i = 0; i < line_str.length(); i = i + 1 {
      if line_str[i] == ':' {
        colon = i
        break
      }
    }
    guard colon >= 0 else {
      raise MultipartError::MalformedBody("part header: \{line_str}")
    }
    let key = line_str[:colon].trim().to_owned()
    let value = line_str[colon + 1:].trim().to_owned()
    headers[key] = value
  }
  raise MultipartError::MalformedBody("no blank line found in part headers")
}

fn parse_content_disposition(
  cd_value : String,
) -> (String, String?) {
  let mut name : String? = None
  let mut filename : String? = None
  let parts = cd_value.split(";")
  for part in parts {
    let trimmed = part.trim()
    if trimmed.has_prefix("name=") {
      name = Some(extract_header_param(trimmed["name=".length():].to_owned()))
    } else if trimmed.has_prefix("filename=") {
      filename = Some(extract_header_param(trimmed["filename=".length():].to_owned()))
    }
  }
  (name.unwrap_or(""), filename)
}

fn extract_header_param(raw : String) -> String {
  let s = raw.trim()
  if s.length() >= 2 && s[0] == '"' && s[s.length() - 1] == '"' {
    s[1:s.length() - 1].to_owned()
  } else {
    s.to_owned()
  }
}

// ---------------------------------------------------------------------------
// Part parsing
// ---------------------------------------------------------------------------

fn parse_part(
  part_data : BytesView,
  form : MultipartForm,
) -> Unit raise {
  let (part_headers, body_offset) = parse_part_headers(part_data, 0)

  let cd = match part_headers.get("Content-Disposition") {
    Some(v) => v
    None => raise MultipartError::MalformedBody("missing Content-Disposition")
  }

  let (name, filename) = parse_content_disposition(cd)

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

      // Always store in memory first; large files spilled to disk
      // by MultipartForm::spill_to_disk() which runs in an async context.
      let file = UploadedFile::{
        header: file_header,
        data: InMemory(file_body),
      }

      form.files.get_or_init(name, () => []).push(file)
    }
    _ => {
      let body_str = bytes_to_string(body, 0, body.length())
      let form_vals = form.values.0
      form_vals.get_or_init(name, () => []).push(body_str)
    }
  }
}

/// Generate a random hex string of n characters.
fn generate_random_hex(n : Int) -> String {
  let r = @random.Rand::new()
  let hex_chars = "0123456789abcdef"
  let buf = @buffer.Buffer::Buffer()
  for _ in 0..<n {
    let idx = r.int(limit=16)
    buf.write_byte(hex_chars[idx].to_byte())
  }
  buf.to_bytes().to_unchecked_string()
}

// ---------------------------------------------------------------------------
// Main parsing entry point
// ---------------------------------------------------------------------------

fn parse_multipart_body(
  body : Bytes,
  content_type : String,
) -> MultipartForm raise {
  let boundary = extract_boundary(content_type)
  let boundary_marker = b"--" + boundary.to_bytes()

  let view = body[:]
  let form = MultipartForm::new()

  let mut pos = find_bytes(view, boundary_marker, 0)
  guard pos >= 0 else {
    raise MultipartError::MalformedBody("boundary not found")
  }

  pos = pos + boundary_marker.length()

  while pos < view.length() {
    if view[pos] == b'\r' && pos + 1 < view.length() && view[pos + 1] == b'\n' {
      pos = pos + 2
    } else if view[pos] == b'\n' {
      pos = pos + 1
    }

    if pos + 1 < view.length() && view[pos] == b'-' && view[pos + 1] == b'-' {
      break
    }

    let next = find_bytes(view, boundary_marker, pos)
    if next < 0 {
      break
    }

    let content_end = if next >= 2 && view[next - 2] == b'\r' && view[next - 1] == b'\n' {
      next - 2
    } else if next >= 1 && view[next - 1] == b'\n' {
      next - 1
    } else {
      next
    }

    let part_bytes = view[pos:content_end].to_owned()
    parse_part(part_bytes[:], form)

    pos = next + boundary_marker.length()

    if pos + 1 < view.length() && view[pos] == b'-' && view[pos + 1] == b'-' {
      break
    }
  }

  form
}
