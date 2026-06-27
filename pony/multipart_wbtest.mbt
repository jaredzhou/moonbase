// multipart_wbtest.mbt
// Whitebox tests for multipart form parsing.

test "extract_boundary unwraps quoted boundary" {
  let result = extract_boundary("multipart/form-data; boundary=\"----foo\"")
  @debug.assert_eq(result, "----foo")
}

test "extract_boundary handles unquoted boundary" {
  let result = extract_boundary("multipart/form-data; boundary=----bar")
  @debug.assert_eq(result, "----bar")
}

test "find_bytes locates substring" {
  let data = b"abc---def---ghi"
  let pos = find_bytes(data[:], b"---", 0)
  @debug.assert_eq(pos, 3)
}

test "find_bytes finds second occurrence" {
  let data = b"abc---def---ghi"
  let pos = find_bytes(data[:], b"---", 4)
  @debug.assert_eq(pos, 9)
}

test "read_line with CRLF" {
  let data = b"hello\r\nworld"
  let result = read_line(data[:], 0)
  match result {
    Some((0, 5, 7)) => @debug.assert_eq(true, true)
    _ => @debug.assert_eq("unexpected", "read_line result")
  }
}

test "extract_header_param strips quotes" {
  let result = extract_header_param("\"value\"")
  @debug.assert_eq(result, "value")
}

test "extract_header_param passes through unquoted" {
  let result = extract_header_param("plain")
  @debug.assert_eq(result, "plain")
}

test "parse_content_disposition extracts name" {
  let (name, filename) = parse_content_disposition("form-data; name=\"field1\"")
  @debug.assert_eq(name, "field1")
  @debug.assert_eq(filename is None, true)
}

test "parse_content_disposition extracts filename" {
  let (name, filename) = parse_content_disposition("form-data; name=\"file1\"; filename=\"test.txt\"")
  @debug.assert_eq(name, "file1")
  match filename {
    Some(f) => @debug.assert_eq(f, "test.txt")
    None => @debug.assert_eq("missing", "filename")
  }
}
