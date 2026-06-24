// Core types for the store module — Bucket, Object, StorageMetadata, StorageError.

///|
/// Error type for storage operations.
pub(all) enum StorageError {
  NotFound(String)
  AlreadyExists(String)
  NotEmpty(String)
  Forbidden(String)
  BackendError(String)
  RepoError(String)
  InvalidInput(String)
} derive(Debug, Eq)

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
  pub created_at : String
  pub updated_at : String
} derive(Debug, Eq)

///|
/// Typed system metadata for a stored object.
pub(all) struct StorageMetadata {
  pub size : Int64
  pub mimetype : String
  pub cache_control : String?
} derive(Debug, Eq)

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
  pub created_at : String
  pub updated_at : String?
  pub last_accessed_at : String?
} derive(Debug, Eq)
