// Whitebox tests for BucketRepo + MemoryBucketRepo.

///|
test "MemoryBucketRepo insert and get" {
  let repo = MemoryBucketRepo::new()
  let bucket = Bucket::{
    id: "avatars",
    name: "Avatars",
    owner: "alice",
    owner_id: "user-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
  }
  insert(repo, bucket)
  let found = get(repo, "avatars")
  @debug.assert_true(found.is_some())
  @debug.assert_eq(found.unwrap().name, "Avatars")
}

///|
test "MemoryBucketRepo list" {
  let repo = MemoryBucketRepo::new()
  let b1 = Bucket::{
    id: "a", name: "A", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  let b2 = Bucket::{
    id: "b", name: "B", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  insert(repo, b1)
  insert(repo, b2)
  let all = list(repo)
  @debug.assert_eq(all.length(), 2)
}

///|
test "MemoryBucketRepo update and delete" {
  let repo = MemoryBucketRepo::new()
  let bucket = Bucket::{
    id: "test", name: "Test", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  insert(repo, bucket)
  let updated = Bucket::{ ..bucket, public: true }
  update(repo, "test", updated)
  @debug.assert_true(get(repo, "test").unwrap().public)

  delete(repo, "test")
  @debug.assert_true(get(repo, "test").is_none())
}

///|
test "MemoryBucketRepo get non-existent" {
  let repo = MemoryBucketRepo::new()
  @debug.assert_true(get(repo, "nope").is_none())
}
