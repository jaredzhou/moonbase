// StorageBackend trait, error type, and supporting types.
// Models the Supabase StorageBackendAdapter interface.

///|
/// Object metadata returned by head / upload operations.
pub(all) struct ObjectMetadata {
  cacheControl : String
  contentLength : Int64
  size : Int64
  mimetype : String
  eTag : String
}

///|
/// Full object response (metadata + body).
pub(all) struct GetObjectResult {
  metadata : ObjectMetadata
  body : Bytes
}

///|
/// Conditional cache headers for getObject.
pub(all) struct CacheHeaders {
  ifModifiedSince : String?
  ifNoneMatch : String?
  range : String?
}

///|
/// Single entry in a listObjects response.
pub(all) struct ObjectKey {
  name : String
  size : Int64
}

///|
/// Result of a listObjects call.
pub(all) struct ListObjectsResult {
  keys : Array[ObjectKey]
  nextToken : String?
}

///|
/// Result of a copyObject call.
pub(all) struct CopyObjectResult {
  eTag : String
}

///|
/// A part descriptor for multipart completion.
pub(all) struct UploadPart {
  e_tag : String?
  part_number : Int
}

///|
/// Result of a single part upload.
pub(all) struct UploadPartResult {
  e_tag : String?
}

///|
/// Result of completing a multipart upload.
pub(all) struct CompleteUploadResult {
  e_tag : String?
  location : String
  bucket : String
  version : String
}

///|
/// Errors that a StorageBackend implementation may raise.
pub(all) suberror BackendError {
  NotFound(String)
  WriteError(String)
  ReadError(String)
  KeyTooLong(String)
  InvalidKey(String)
} derive(Debug)

///|
/// Pluggable backend for storing/retrieving objects.
///
/// Implementations include MemoryBackend (in-memory, for testing),
/// LocalFSBackend (local filesystem), and future S3 / GCS backends.
pub(open) trait StorageBackend {
  /// Return metadata for an object without fetching its body.
  fn headObject(Self, bucket : String, key : String) -> ObjectMetadata raise BackendError

  /// Fetch an object's metadata and body, with optional cache / range headers.
  fn getObject(Self, bucket : String, key : String, headers : CacheHeaders?) -> GetObjectResult raise BackendError

  /// Upload an object. The backend computes its own eTag.
  fn uploadObject(
    Self,
    bucket : String,
    key : String,
    body : Bytes,
    contentType : String,
    cacheControl : String,
  ) -> ObjectMetadata raise BackendError

  /// Delete a single object (no-op if not found).
  fn deleteObject(Self, bucket : String, key : String) -> Unit raise BackendError

  /// Delete multiple objects at once.
  fn deleteObjects(Self, bucket : String, keys : Array[String]) -> Unit raise BackendError

  /// Server-side copy from `source` to `destination` within the same bucket.
  fn copyObject(Self, bucket : String, source : String, destination : String) -> CopyObjectResult raise BackendError

  /// List objects in a bucket with optional prefix, limit, and pagination token.
  fn listObjects(
    Self,
    bucket : String,
    prefix : String?,
    limit : Int?,
    nextToken : String?,
  ) -> ListObjectsResult raise BackendError

  // -----------------------------------------------------------------------
  // Multipart upload — for streaming large files without buffering.
  // -----------------------------------------------------------------------

  /// Start a multipart upload, returning an upload id.
  fn createMultiPartUpload(
    Self,
    bucket : String,
    key : String,
    contentType : String,
    cacheControl : String,
  ) -> String raise BackendError

  /// Upload a single numbered part.
  fn uploadPart(
    Self,
    bucket : String,
    key : String,
    uploadId : String,
    partNumber : Int,
    body : Bytes,
  ) -> UploadPartResult raise BackendError

  /// Finalise a multipart upload by assembling the given parts.
  fn completeMultipartUpload(
    Self,
    bucket : String,
    key : String,
    uploadId : String,
    parts : Array[UploadPart],
  ) -> CompleteUploadResult raise BackendError

  /// Cancel an in-progress multipart upload and clean up partial data.
  fn abortMultipartUpload(
    Self,
    bucket : String,
    key : String,
    uploadId : String,
  ) -> Unit raise BackendError

  /// Release any resources held by the backend (connections, file handles, …).
  fn close(Self) -> Unit
}

///|
/// Trait extension — convenience helpers.
pub fn[T : StorageBackend] exists(
  backend : T,
  bucket : String,
  key : String,
) -> Bool {
  try {
    let _ = backend.headObject(bucket, key)
    true
  } catch {
    _ => false
  }
}
