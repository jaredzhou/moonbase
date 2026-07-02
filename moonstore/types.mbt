// Core types and traits for the store module.

///|
/// Error type for storage operations.
pub(all) suberror StorageError {
  NotFound(String)
  AlreadyExists(String)
  NotEmpty(String)
  Forbidden(String)
  BackendError(String)
  RepoError(String)
  InvalidInput(String)
} derive(Debug)

///|
/// Map StorageError to an HTTP status code.
pub fn StorageError::to_http_status(self : StorageError) -> Int {
  match self {
    NotFound(_) => 404
    AlreadyExists(_) => 409
    NotEmpty(_) => 409
    Forbidden(_) => 403
    InvalidInput(_) => 400
    BackendError(_) => 500
    RepoError(_) => 500
  }
}

///|
/// A storage bucket — independent container for objects.
pub(all) struct Bucket {
  pub id : String
  pub name : String
  pub owner : String
  pub owner_id : String
  pub public : Bool
  pub file_size_limit : Int64?
  pub allowed_mime_types : Array[String]?
  pub created_at : @time.Datetime
  pub updated_at : @time.Datetime
} derive(Debug, Eq, ToJson)

///|
/// Typed system metadata for a stored object.
pub(all) struct StorageMetadata {
  pub size : Int64
  pub mimetype : String
  pub cache_control : String?
} derive(Debug, Eq, ToJson)

///|
/// A stored object (file) within a bucket.
pub(all) struct Object {
  pub id : String?
  pub name : String
  pub bucket_id : String
  pub owner : String
  pub owner_id : String
  pub version : String
  pub metadata : StorageMetadata
  pub user_metadata : Json
  pub created_at : @time.Datetime
  pub updated_at : @time.Datetime?
  pub last_accessed_at : @time.Datetime?
} derive(Debug, Eq, ToJson)

// ---------------------------------------------------------------------------
// Repo traits
// ---------------------------------------------------------------------------

///|
/// Pluggable bucket metadata storage.
pub(open) trait BucketRepo {
  fn get(Self, id : String) -> Bucket?
  fn list(Self) -> Array[Bucket]
  fn insert(Self, bucket : Bucket) -> Unit
  fn update(Self, id : String, bucket : Bucket) -> Unit
  fn delete(Self, id : String) -> Unit
}

///|
pub fn[T : BucketRepo] list(backend : T) -> Array[Bucket] {
  backend.list()
}

///|
pub fn[T : BucketRepo] insert(backend : T, bucket : Bucket) -> Unit {
  backend.insert(bucket)
}

///|
pub fn[T : BucketRepo] update(
  backend : T,
  id : String,
  bucket : Bucket,
) -> Unit {
  backend.update(id, bucket)
}

///|
/// Pluggable object metadata storage.
pub(open) trait ObjectRepo {
  fn get(Self, bucket_id : String, name : String) -> Object?
  fn list(
    Self,
    bucket_id : String,
    prefix : String?,
    limit : Int?,
    offset : Int?,
  ) -> Array[Object]
  fn insert(Self, obj : Object) -> Unit
  fn delete(Self, bucket_id : String, name : String) -> Unit
  fn delete_batch(Self, bucket_id : String, names : Array[String]) -> Unit
}
