// Whitebox tests for entity conversion helpers.

///|
test "bucket_to_entity produces correct Cedar entity" {
  let bucket = Bucket::{
    id: "avatars",
    name: "Avatars",
    owner: "alice",
    owner_id: "user-1",
    public: true,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
  }
  let (uid, entity) = bucket_to_entity(bucket)
  @debug.assert_eq(uid.type_, "Bucket")
  @debug.assert_eq(uid.id, "avatars")
  match entity.attrs.get("public") {
    Some(@ast.Value::Bool(b)) => assert_true(b)
    _ => abort("expected public=true")
  }
  match entity.attrs.get("owner_id") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "user-1")
    _ => abort("expected owner_id")
  }
}

///|
test "object_to_entity produces correct Cedar entity" {
  let obj = Object::{
    id: Some("uuid-1"),
    name: "public/avatar.png",
    bucket_id: "avatars",
    owner: "alice",
    owner_id: "user-1",
    version: "1",
    metadata: StorageMetadata::{
      size: 2048,
      mimetype: "image/png",
      cache_control: None,
    },
    user_metadata: Json::object(Map([])),
    created_at: "2024-01-01T00:00:00Z",
    updated_at: None,
    last_accessed_at: None,
  }
  let (uid, entity) = object_to_entity(obj)
  @debug.assert_eq(uid.type_, "Object")
  @debug.assert_eq(uid.id, "uuid-1")
  match entity.attrs.get("bucket_id") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "avatars")
    _ => abort("expected bucket_id")
  }
  match entity.attrs.get("folder") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "public")
    _ => abort("expected folder")
  }
  match entity.attrs.get("size") {
    Some(@ast.Value::Long(n)) => @debug.assert_eq(n, 2048)
    _ => abort("expected size")
  }
}
