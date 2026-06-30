// Whitebox tests for LocalFS backend.

///|
test "LocalFS backend put and get" {
  let base = "/tmp/moonbase_test/"
  let backend = @backend.new(base)
  put(backend, "test-bucket", "data.txt", b"hello fs") catch {
    _ => abort("put failed")
  }
  @debug.assert_eq(true, exists(backend, "test-bucket", "data.txt"))
  let data = get(backend, "test-bucket", "data.txt") catch {
    _ => abort("get failed")
  }
  @debug.assert_eq(data, b"hello fs")
}

///|
test "LocalFS backend delete" {
  let base = "/tmp/moonbase_test/"
  let backend = @backend.new(base)
  put(backend, "test", "tmp.txt", b"x") catch {
    _ => abort("put failed")
  }
  delete(backend, "test", "tmp.txt") catch {
    _ => abort("delete failed")
  }
  @debug.assert_eq(false, exists(backend, "test", "tmp.txt"))
}

///|
test "LocalFS backend nested path" {
  let base = "/tmp/moonbase_test/"
  let backend = @backend.new(base)
  put(backend, "avatars", "public/img.png", b"png data") catch {
    _ => abort("put failed")
  }
  let data = get(backend, "avatars", "public/img.png") catch {
    _ => abort("get failed")
  }
  @debug.assert_eq(data, b"png data")
}
