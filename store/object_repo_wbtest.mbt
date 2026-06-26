// Whitebox tests for ObjectRepo trait and MemoryObjectRepo implementation.

///|
test "MemoryObjectRepo insert and get" {
  let repo = MemoryObjectRepo::new()
  let obj = Object::{
    id: Some("uuid-1"),
    name: "public/avatar.png",
    bucket_id: "avatars",
    owner: "alice",
    owner_id: "user-1",
    version: "1",
    metadata: StorageMetadata::{
      size: 1024, mimetype: "image/png", cache_control: None,
    },
    user_metadata: Json::object(Map([])),
    created_at: "2024-01-01T00:00:00Z",
    updated_at: None,
    last_accessed_at: None,
  }
  repo.insert(obj)
  let found = repo.get("avatars", "public/avatar.png")
  @debug.assert_eq(true, found is Some(_))
  @debug.assert_eq(found.unwrap().metadata.size, 1024)
}

///|
test "MemoryObjectRepo list with prefix" {
  let repo = MemoryObjectRepo::new()
  let mk_obj = fn(name : String) -> Object {
    Object::{
      id: Some("id-" + name),
      name,
      bucket_id: "avatars",
      owner: "u", owner_id: "u-1", version: "1",
      metadata: StorageMetadata::{ size: 0, mimetype: "", cache_control: None },
      user_metadata: Json::object(Map([])),
      created_at: "", updated_at: None, last_accessed_at: None,
    }
  }
  repo.insert(mk_obj("public/a.png"))
  repo.insert(mk_obj("public/b.png"))
  repo.insert(mk_obj("private/x.png"))
  let result = repo.list("avatars", Some("public/"), None, None)
  @debug.assert_eq(result.length(), 2)
}

///|
test "MemoryObjectRepo delete and delete_batch" {
  let repo = MemoryObjectRepo::new()
  let mk_obj = fn(name : String) -> Object {
    Object::{
      id: Some("id-" + name),
      name,
      bucket_id: "avatars",
      owner: "u", owner_id: "u-1", version: "1",
      metadata: StorageMetadata::{ size: 0, mimetype: "", cache_control: None },
      user_metadata: Json::object(Map([])),
      created_at: "", updated_at: None, last_accessed_at: None,
    }
  }
  repo.insert(mk_obj("a.txt"))
  repo.insert(mk_obj("b.txt"))
  repo.insert(mk_obj("c.txt"))

  repo.delete("avatars", "a.txt")
  @debug.assert_eq(true, repo.get("avatars", "a.txt") is None)

  repo.delete_batch("avatars", ["b.txt", "c.txt"])
  @debug.assert_eq(true, repo.get("avatars", "b.txt") is None)
  @debug.assert_eq(true, repo.get("avatars", "c.txt") is None)
}

///|
test "MemoryObjectRepo get non-existent" {
  let repo = MemoryObjectRepo::new()
  @debug.assert_eq(true, repo.get("avatars", "nope.txt") is None)
}
