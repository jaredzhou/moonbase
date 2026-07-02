// Whitebox tests for BucketRepo + MemoryBucketRepo.

///|
test "MemoryBucketRepo insert and get" {
  let repo = MemoryBucketRepo::new()
  let bucket = @moonstore.Bucket::{
    id: "avatars",
    name: "Avatars",
    owner: "alice",
    owner_id: "user-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: @time.Datetime::from_unix_millis(1704067200000L),
    updated_at: @time.Datetime::from_unix_millis(1704067200000L),
  }
  repo.insert(bucket)
  let found = repo.get("avatars")
  @debug.assert_eq(true, found is Some(_))
  @debug.assert_eq(found.unwrap().name, "Avatars")
}

///|
test "MemoryBucketRepo list" {
  let repo = MemoryBucketRepo::new()
  let b1 = @moonstore.Bucket::{
    id: "a",
    name: "A",
    owner: "u",
    owner_id: "u-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: @time.Datetime::from_unix_millis(0L),
    updated_at: @time.Datetime::from_unix_millis(0L),
  }
  let b2 = @moonstore.Bucket::{
    id: "b",
    name: "B",
    owner: "u",
    owner_id: "u-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: @time.Datetime::from_unix_millis(0L),
    updated_at: @time.Datetime::from_unix_millis(0L),
  }
  repo.insert(b1)
  repo.insert(b2)
  let all = repo.list()
  @debug.assert_eq(all.length(), 2)
}

///|
test "MemoryBucketRepo update and delete" {
  let repo = MemoryBucketRepo::new()
  let bucket = @moonstore.Bucket::{
    id: "test",
    name: "Test",
    owner: "u",
    owner_id: "u-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: @time.Datetime::from_unix_millis(0L),
    updated_at: @time.Datetime::from_unix_millis(0L),
  }
  repo.insert(bucket)
  let updated = @moonstore.Bucket::{ ..bucket, public: true }
  repo.update("test", updated)
  @debug.assert_eq(true, repo.get("test").unwrap().public)

  repo.delete("test")
  @debug.assert_eq(true, repo.get("test") is None)
}

///|
test "MemoryBucketRepo get non-existent" {
  let repo = MemoryBucketRepo::new()
  @debug.assert_eq(true, repo.get("nope") is None)
}
