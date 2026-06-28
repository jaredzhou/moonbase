# Pony Multipart File Upload

## Summary

Add `multipart/form-data` support to the Pony HTTP framework, modeled after Go's `net/http` `ParseMultipartForm` / `FormFile` API. Supports mixed file + form field uploads with memory buffering up to a configurable threshold, spilling to temporary disk files for large files.

## Motivation

Pony currently supports `application/x-www-form-urlencoded` (`ctx.form()`) and JSON (`ctx.json()`). Adding multipart support is the last major missing piece for standard HTTP form handling, enabling file uploads alongside regular form fields.

## Type Additions

### `FileHeader` (public)

Metadata for a single uploaded file. Modeled on Go's `mime/multipart.FileHeader`.

```moonbit
pub(all) struct FileHeader {
  filename : String
  size : Int64
  content_type : String?
  header : Map[String, String]
}
```

- `filename` — original filename from `Content-Disposition`
- `size` — uncompressed byte count
- `content_type` — MIME type from part header (e.g. `"image/png"`)
- `header` — raw MIME part headers (e.g. `"Content-Disposition"`, `"Content-Transfer-Encoding"`). Uses `Map[String, String]` consistent with `Context.req_headers`.

### `UploadedFile` (public)

Wraps an uploaded file's metadata and its backing data (memory or disk). Exposes content via a reader.

```moonbit
pub(all) struct UploadedFile {
  header : FileHeader
}
```

Internal storage (not exported):
```moonbit
enum UploadedFileData {
  InMemory(Bytes)      // <= max_memory threshold
  OnDisk(String)       // path to temporary file
}
```

Methods:

| Method | Signature | Description |
|--------|-----------|-------------|
| `header` | `(Self) -> FileHeader` | Get file metadata |
| `open` | `(Self) -> @io.Reader!String` | Open a reader for file content (memory → BytesReader, disk → open fs handle) |
| `close` | `(Self) -> Unit` | Release resources (delete temp file if OnDisk) |

### `MultipartForm` (internal)

```moonbit
struct MultipartForm {
  values : Values           // regular form fields, same Values type used by form_values
  files : Map[String, Array[UploadedFile]]
}

fn MultipartForm::value(self : MultipartForm, key : String) -> String? {
  self.values.get(key)
}
```

## Context API Changes

### New field on `Context`

```moonbit
mut multipart_form : MultipartForm?
```

### New methods

#### `parse_multipart_form`

```moonbit
let default_max_memory : Int64 = 32 * 1024 * 1024  // 32 MiB

// Parse multipart/form-data body. max_memory controls the byte threshold
// at which file parts spill from memory to temp files on disk.
// Regular (non-file) form fields are always buffered in memory.
//
// After this call:
//   - ctx.form("field") returns values from multipart fields
//   - ctx.form_file("key") returns uploaded files
//
// Errors: missing Content-Type boundary, malformed multipart body, disk I/O errors.
pub async fn Context::parse_multipart_form(
  self : Context,
  max_memory~ : Int64 = default_max_memory
) -> Unit!String
```

**Behavior:**
1. Extract `boundary` from `Content-Type` header (`multipart/form-data; boundary=...`)
2. Stream-read the body using the boundary delimiter
3. For each part:
   - Parse MIME part headers
   - If `Content-Disposition` has `filename` → file field:
     - Buffer in memory until total accumulated + this part exceeds `max_memory`
     - If threshold exceeded → create temp file in OS temp dir with pattern `pony-multipart-{random}`, flush buffer, stream rest to file
     - Store `UploadedFile` in `multipart_form.files[key]`
   - If no filename → regular form field:
     - Accumulate in memory, store in `multipart_form.values`
4. Store result in `self.multipart_form`

#### `form_file`

```moonbit
// Returns the first uploaded file for key, or None if not found.
pub fn Context::form_file(self : Context, key : String) -> UploadedFile?
```

#### `form_files`

```moonbit
// Returns all uploaded files for key (useful for multi-file uploads).
pub fn Context::form_files(self : Context, key : String) -> Array[UploadedFile]
```

#### `cleanup`

```moonbit
// Release all resources held by the multipart form (deletes temp files).
// Called automatically by Server after the handler returns.
pub fn Context::cleanup(self : Context) -> Unit
```

### Modified method: `form`

```moonbit
pub async fn Context::form(self : Context, key : String) -> String? {
  // If multipart was parsed, read from its Values
  if self.multipart_form is Some(mf) {
    return mf.value(key)
  }
  // Fallback: existing urlencoded lazy-parse behavior
  if self.form_values is None {
    let body_text = self.req_body.read_all().text()
    self.form_values = Some(parse_query(body_text))
  }
  self.form_values.unwrap().get(key)
}
```

## Server Integration

`Server::start` is updated to call `ctx.cleanup()` after the handler returns, before moving to the next request. This ensures temp files are always cleaned up even if the handler forgets to call `close()` explicitly.

## Temp File Management

- Temp files stored in OS temporary directory (e.g. `/tmp` on Linux/macOS)
- Filename pattern: `pony-multipart-{random_hex}`
- Cleaned up via `UploadedFile::close()` or `Context::cleanup()`
- If cleanup fails (process crash), files are left in temp dir for OS-level cleanup on reboot

## File Organization

| File | Responsibility |
|------|---------------|
| `multipart.mbt` | `FileHeader`, `UploadedFile`, `UploadedFileData`, `MultipartForm`, boundary extraction, part parsing, temp file I/O |
| `multipart_wbtest.mbt` | Whitebox tests: boundary parsing, memory/disk threshold, form field extraction, malformed input, header parsing |
| `pony.mbt` | Context: new field, `parse_multipart_form`, `form_file`, `form_files`, `cleanup`; `form()` modification; `Server::start` cleanup hook |
| `pony_test.mbt` | Blackbox integration tests: full multipart upload (file + fields), multi-file upload, file with no filename (form field), missing boundary, empty file |

## Error Handling

| Error | Condition |
|-------|-----------|
| `"missing Content-Type boundary"` | No `boundary=` in Content-Type, or Content-Type is not multipart/form-data |
| `"malformed multipart body"` | Bad boundary delimiter, truncated part, or invalid part header |
| `"failed to read request body: …"` | I/O error on req_body |
| `"failed to write temp file: …"` | Disk I/O error when spilling to disk |

## Edge Cases

- **Empty file**: Accepted, `size` = 0, user gets empty bytes/reader
- **Missing filename**: Treated as a regular form field (not a file)
- **Multiple files with same field name**: All stored in `form_files(key)`, `form_file(key)` returns the first
- **Body already read**: `form()` or `json()` consuming the body before `parse_multipart_form` is user error — body can only be read once. `parse_multipart_form` consumes `req_body` fully.

## Usage Example

```moonbit
fn upload_handler : Handler = async fn(ctx) {
  // Parse multipart form with 64 MiB memory threshold
  ctx.parse_multipart_form!(max_memory=64 * 1024 * 1024)

  let username = ctx.form("username").unwrap_or("anonymous")
  let avatar = ctx.form_file("avatar")
  let files = ctx.form_files("docs")  // multiple files under "docs" key

  match avatar {
    Some(f) => {
      let reader = f.open()!
      let header = f.header()
      println("uploaded: \{header.filename}, size: \{header.size}")
      // ... read and process ...
      reader.close()
    }
    None => ctx.write_text(400, "avatar is required")
  }

  ctx.reply_ok({"user": username, "files": files.length()})
}
```

## Out of Scope

- Content-Type sniffing / MIME type detection from file bytes
- Chunked upload / resumable uploads
- Upload progress callbacks
- Per-file size limits (only total memory threshold)
- Streaming parts to user callback (whole-file buffering only)
