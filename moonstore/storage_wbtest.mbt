// Tests for the Storage service layer.

///|
test "create and get bucket" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "avatars",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }
  @debug.assert_eq(bucket.name, "avatars")
  @debug.assert_eq(bucket.owner, "alice")

  let found = storage.get_bucket("alice", bucket.id) catch {
    _ => panic()
  }
  @debug.assert_eq(found.name, "avatars")
}

///|
test "public bucket download skips auth" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "public-files",
    public: Some(true),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "hello.txt", b"hello",
    Json::object(Map([])),
  ) catch { e => panic() }

  let (dl_obj, data) = storage.download(None, bucket.id, "hello.txt") catch {
    e => panic()
  }
  @debug.assert_eq(data, b"hello")
  @debug.assert_eq(dl_obj.name, "hello.txt")
}

///|
test "private bucket download requires user" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "private-files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "secret.txt", b"secret",
    Json::object(Map([])),
  ) catch { e => panic() }

  // alice should be allowed (policy is permissive)
  let (_, data) = storage.download(Some("alice"), bucket.id, "secret.txt") catch {
    e => panic()
  }
  @debug.assert_eq(data, b"secret")

  // download without user should be denied for private bucket
  let (_, _) = storage.download(None, bucket.id, "secret.txt") catch {
    _ => return
  }
  panic()
}

///|
test "move object" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "old.txt", b"data",
    Json::object(Map([])),
  ) catch { e => panic() }

  storage.move_object("alice", bucket.id, "old.txt", "new.txt") catch {
    e => panic()
  }

  let (obj, _) = storage.download(Some("alice"), bucket.id, "new.txt") catch {
    _ => panic()
  }
  @debug.assert_eq(obj.name, "new.txt")
}

///|
test "copy object" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "original.txt", b"data",
    Json::object(Map([])),
  ) catch { e => panic() }

  storage.copy_object("alice", bucket.id, "original.txt", "copy.txt") catch {
    e => panic()
  }

  let _ = storage.download(Some("alice"), bucket.id, "original.txt") catch {
    _ => panic()
  }
  let _ = storage.download(Some("alice"), bucket.id, "copy.txt") catch {
    _ => panic()
  }
}

///|
test "list objects with prefix" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "public/a.txt", b"a",
    Json::object(Map([])),
  ) catch { _ => panic() }
  let _ = storage.upload(
    "alice", bucket.id, "public/b.txt", b"b",
    Json::object(Map([])),
  ) catch { _ => panic() }
  let _ = storage.upload(
    "alice", bucket.id, "private/c.txt", b"c",
    Json::object(Map([])),
  ) catch { _ => panic() }

  let result = storage.list_objects(
    "alice", bucket.id, Some("public/"), None, None, None,
  ) catch { _ => panic() }
  @debug.assert_eq(result.length(), 2)
}

///|
test "delete single and batch objects" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "a.txt", b"a",
    Json::object(Map([])),
  ) catch { _ => panic() }
  let _ = storage.upload(
    "alice", bucket.id, "b.txt", b"b",
    Json::object(Map([])),
  ) catch { _ => panic() }

  storage.delete_object("alice", bucket.id, "a.txt") catch {
    _ => panic()
  }

  // verify b.txt still exists, a.txt is gone
  storage.delete_objects("alice", bucket.id, ["b.txt"]) catch {
    _ => panic()
  }

  let list = storage.list_objects("alice", bucket.id, None, None, None, None) catch {
    _ => panic()
  }
  @debug.assert_eq(list.length(), 0)
}

///|
test "empty bucket" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "a.txt", b"a",
    Json::object(Map([])),
  ) catch { _ => panic() }
  let _ = storage.upload(
    "alice", bucket.id, "b.txt", b"b",
    Json::object(Map([])),
  ) catch { _ => panic() }

  storage.empty_bucket("alice", bucket.id) catch {
    _ => panic()
  }

  let list = storage.list_objects("alice", bucket.id, None, None, None, None) catch {
    _ => panic()
  }
  @debug.assert_eq(list.length(), 0)
}

///|
test "get object info" {
  let storage = new_test_storage()
  let bucket = storage.create_bucket("alice", CreateBucketInput::{
    name: "files",
    public: Some(true),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => panic() }

  let _ = storage.upload(
    "alice", bucket.id, "info.txt", b"data",
    Json::object(Map([])),
  ) catch { _ => panic() }

  let obj = storage.get_object_info(None, bucket.id, "info.txt") catch {
    _ => panic()
  }
  @debug.assert_eq(obj.name, "info.txt")
  @debug.assert_eq(obj.metadata.size, 4)
  @debug.assert_eq(obj.metadata.mimetype, "application/octet-stream")
}
