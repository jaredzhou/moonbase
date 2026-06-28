// multipart_wbtest.mbt — whitebox tests for multipart parsing
//
// Tested against:
//   RFC 7578 §4.2   Multipart body parts
//   RFC 7578 §4.3   Content-Disposition header
//   RFC 7578 §4.4   Content-Type boundary parameter
//   RFC 2046 §5.1   Multipart Media Type — boundary delimiter syntax
//   RFC 2183 §2     Content-Disposition field — filename parameter

// ============================================================================
// Spec: RFC 2046 §5.1 — boundary delimiter
// ============================================================================
// The boundary delimiter line consists of two hyphens followed by the
// boundary parameter value. The final delimiter has two additional hyphens.
//   --boundary         → part separator
//   --boundary--       → end marker

/// Spec: [RFC 2046 §5.1] Quoted boundary values are properly unwrapped.
test "boundary_from unwraps quoted boundary" {
  let result = boundary_from("multipart/form-data; boundary=\"----foo\"")
  @debug.assert_eq(result, "----foo")
}

/// Spec: [RFC 2046 §5.1] Unquoted boundary values are extracted as-is.
test "boundary_from handles unquoted boundary" {
  let result = boundary_from("multipart/form-data; boundary=----bar")
  @debug.assert_eq(result, "----bar")
}

// ============================================================================
// Spec: RFC 2046 §5.1 — byte-level primitives
// ============================================================================

/// Spec: [RFC 2046 §5.1] A part boundary marker `--boundary` must be
/// locatable within the body bytes.
test "index_of_bytes locates substring" {
  let data = b"abc---def---ghi"
  let pos = index_of_bytes(data[:], b"---", 0)
  @debug.assert_eq(pos, 3)
}

/// Spec: [RFC 2046 §5.1] The search respects a start offset so we can
/// find subsequent boundary markers after the first.
test "index_of_bytes finds second occurrence" {
  let data = b"abc---def---ghi"
  let pos = index_of_bytes(data[:], b"---", 4)
  @debug.assert_eq(pos, 9)
}

/// Spec: [RFC 2046 §5.1] Each part header line and the blank separator
/// line must be terminated by CRLF (`\r\n`).
test "read_line recognizes CRLF terminator" {
  let data = b"hello\r\nworld"
  let result = read_line(data[:], 0)
  match result {
    Some((0, 5, 7)) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq("unexpected", "read_line result")
  }
}

// ============================================================================
// Spec: RFC 2183 §2, RFC 7578 §4.3 — Content-Disposition parameters
// ============================================================================
// MIME parameters in Content-Disposition may be quoted or unquoted.
//   Content-Disposition: form-data; name="field1"
//   Content-Disposition: form-data; name="file1"; filename="test.txt"

/// Spec: [RFC 2183 §2] Quoted parameter values are unescaped.
test "unquote_mime_value strips surrounding quotes" {
  let result = unquote_mime_value("\"value\"")
  @debug.assert_eq(result, "value")
}

/// Spec: [RFC 2183 §2] Unquoted parameter values are left alone.
test "unquote_mime_value passes through unquoted text" {
  let result = unquote_mime_value("plain")
  @debug.assert_eq(result, "plain")
}

/// Spec: [RFC 7578 §4.3] The `name` parameter identifies the form field.
test "split_content_disposition extracts name parameter" {
  let (name, filename) = split_content_disposition("form-data; name=\"field1\"")
  @debug.assert_eq(name, "field1")
  @debug.assert_eq(filename is None, true)
}

/// Spec: [RFC 7578 §4.3] The `filename` parameter (when present) identifies
/// the original file name.
test "split_content_disposition extracts filename parameter" {
  let (name, filename) = split_content_disposition("form-data; name=\"file1\"; filename=\"test.txt\"")
  @debug.assert_eq(name, "file1")
  match filename {
    Some(f) => @debug.assert_eq(f, "test.txt")
    None => @debug.assert_eq("missing", "filename")
  }
}

// ============================================================================
// Spec: RFC 7578 §4.2 — MultipartForm structure
// ============================================================================
// A parsed multipart form contains regular form fields (Values) and
// file uploads (UploadedFile entries), keyed by their `name`.

/// Spec: [RFC 7578 §4.2] An empty form has no values and no files.
test "MultipartForm new is empty" {
  let form = MultipartForm::new()
  @debug.assert_eq(form.field_value("any") is None, true)
  @debug.assert_eq(form.file_of("any") is None, true)
  @debug.assert_eq(form.files_of("any").length(), 0)
}
