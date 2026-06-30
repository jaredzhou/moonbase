// Whitebox tests for StorageBackend + MemoryBackend.

///|
test "MemoryBackend put and get" {
  let backend = MemoryBackend::new()
  put(backend, "avatars", "test.txt", b"hello world") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(true, exists(backend, "avatars", "test.txt"))
  let data = get(backend, "avatars", "test.txt") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(data, b"hello world")
}

///|
test "MemoryBackend delete and exists" {
  let backend = MemoryBackend::new()
  put(backend, "avatars", "temp.txt", b"data") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(true, exists(backend, "avatars", "temp.txt"))
  delete(backend, "avatars", "temp.txt") catch {
    _ => abort("unexpected error")
  }
  @debug.assert_eq(false, exists(backend, "avatars", "temp.txt"))
}

///|
test "MemoryBackend get non-existent" {
  let backend = MemoryBackend::new()
  let got_error = try {
    let _ = get(backend, "avatars", "nope.txt")
    false
  } catch {
    NotFound(_) => true
    _ => false
  }
  @debug.assert_eq(true, got_error)
}
