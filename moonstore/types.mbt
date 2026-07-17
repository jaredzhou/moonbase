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
pub impl @pony.ToApiError for StorageError with fn to_api_error(
  self : StorageError,
) -> @pony.ApiError {
  match self {
    NotFound(m) => @pony.ApiError::new(@pony.not_found, m)
    AlreadyExists(m) => @pony.ApiError::new(@pony.already_exists, m)
    NotEmpty(m) => @pony.ApiError::new(@pony.failed_precondition, m)
    Forbidden(m) => @pony.ApiError::new(@pony.permission_denied, m)
    InvalidInput(m) => @pony.ApiError::new(@pony.invalid_argument, m)
    BackendError(m) => @pony.ApiError::new(@pony.internal, m)
    RepoError(m) => @pony.ApiError::new(@pony.internal, m)
  }
}

///|
/// Convert a `StorageError` to a pony `ApiError`.
/// Kept for backward compatibility — delegates to the `ToApiError` trait.
pub fn to_api_error(e : StorageError) -> @pony.ApiError {
  @pony.ToApiError::to_api_error(e)
}

///|
/// A storage bucket — independent container for objects.
pub(all) struct Bucket {
  id : String
  name : String
  owner : String
  owner_id : String
  public : Bool
  file_size_limit : Int64?
  allowed_mime_types : Array[String]?
  created_at : @time.Datetime
  updated_at : @time.Datetime
} derive(Debug, Eq, ToJson)

///|
/// Typed system metadata for a stored object.
pub(all) struct StorageMetadata {
  size : Int64
  mimetype : String
  cache_control : String?
} derive(Debug, Eq, ToJson)

///|
/// A stored object (file) within a bucket.
pub(all) struct Object {
  id : String?
  name : String
  bucket_id : String
  owner : String
  owner_id : String
  version : String
  metadata : StorageMetadata
  user_metadata : Json
  created_at : @time.Datetime
  updated_at : @time.Datetime?
  last_accessed_at : @time.Datetime?
} derive(Debug, Eq, ToJson)

// ---------------------------------------------------------------------------
// Repo traits
// ---------------------------------------------------------------------------

///|
/// Pluggable bucket metadata storage.
pub(open) trait BucketRepo {
  fn get(Self, id : String) -> Bucket? raise Error
  fn list(Self) -> Array[Bucket] raise Error
  fn insert(Self, bucket : Bucket) -> Unit raise Error
  fn update(Self, id : String, bucket : Bucket) -> Unit raise Error
  fn delete(Self, id : String) -> Unit raise Error
}

///|
pub fn[T : BucketRepo] list(backend : T) -> Array[Bucket] raise Error {
  backend.list()
}

///|
pub fn[T : BucketRepo] insert(backend : T, bucket : Bucket) -> Unit raise Error {
  backend.insert(bucket)
}

///|
pub fn[T : BucketRepo] update(
  backend : T,
  id : String,
  bucket : Bucket,
) -> Unit raise Error {
  backend.update(id, bucket)
}

///|
/// Pluggable object metadata storage.
pub(open) trait ObjectRepo {
  fn get(Self, bucket_id : String, name : String) -> Object? raise Error
  fn list(
    Self,
    bucket_id : String,
    prefix : String?,
    limit : Int?,
    offset : Int?,
  ) -> Array[Object] raise Error
  fn insert(Self, obj : Object) -> Unit raise Error
  fn delete(Self, bucket_id : String, name : String) -> Unit raise Error
  fn delete_batch(Self, bucket_id : String, names : Array[String]) -> Unit raise Error
}
