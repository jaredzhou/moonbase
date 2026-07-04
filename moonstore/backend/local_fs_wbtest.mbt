// Whitebox tests for LocalFS backend.

///|
test "LocalFS backend upload and get" {
  let base = "/tmp/moonbase_test/"
  let backend = LocalFSBackend::new(base)
  let _ = backend.uploadObject(
    "test-bucket", "data.txt", b"hello fs", "application/octet-stream", "no-cache",
  ) catch {
    _ => abort("upload failed")
  }
  @debug.assert_eq(true, exists(backend, "test-bucket", "data.txt"))
  let result = backend.getObject("test-bucket", "data.txt", None) catch {
    _ => abort("get failed")
  }
  @debug.assert_eq(result.body, b"hello fs")
}

///|
test "LocalFS backend delete" {
  let base = "/tmp/moonbase_test/"
  let backend = LocalFSBackend::new(base)
  let _ = backend.uploadObject(
    "test", "tmp.txt", b"x", "application/octet-stream", "no-cache",
  ) catch {
    _ => abort("upload failed")
  }
  backend.deleteObject("test", "tmp.txt") catch {
    _ => abort("delete failed")
  }
  @debug.assert_eq(false, exists(backend, "test", "tmp.txt"))
}

///|
test "LocalFS backend nested path" {
  let base = "/tmp/moonbase_test/"
  let backend = LocalFSBackend::new(base)
  let _ = backend.uploadObject(
    "avatars", "public/img.png", b"png data", "image/png", "no-cache",
  ) catch {
    _ => abort("upload failed")
  }
  let result = backend.getObject("avatars", "public/img.png", None) catch {
    _ => abort("get failed")
  }
  @debug.assert_eq(result.body, b"png data")
}
