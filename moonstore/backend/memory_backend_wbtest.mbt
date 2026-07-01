// Whitebox tests for StorageBackend + MemoryBackend.

///|
test "MemoryBackend upload and get" {
  let backend = MemoryBackend::new()
  let _ = backend.uploadObject(
    "avatars", "test.txt", b"hello world", "text/plain", "no-cache",
  ) catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(true, exists(backend, "avatars", "test.txt"))
  let result = backend.getObject("avatars", "test.txt", None) catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(result.body, b"hello world")
}

///|
test "MemoryBackend delete and exists" {
  let backend = MemoryBackend::new()
  let _ = backend.uploadObject(
    "avatars", "temp.txt", b"data", "text/plain", "no-cache",
  ) catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(true, exists(backend, "avatars", "temp.txt"))
  backend.deleteObject("avatars", "temp.txt") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(false, exists(backend, "avatars", "temp.txt"))
}

///|
test "MemoryBackend get non-existent" {
  let backend = MemoryBackend::new()
  let got_error = try {
    let _ = backend.getObject("avatars", "nope.txt", None)
    false
  } catch {
    NotFound(_) => true
    _ => false
  }
  @debug.assert_eq(true, got_error)
}
