// LocalFS backend — stores files on the local filesystem.

///|
pub(all) struct LocalFSBackend {
  base_path : String
}

///|
/// Create a new LocalFS backend rooted at the given directory.
pub fn LocalFSBackend::new(base_path : String) -> LocalFSBackend {
  LocalFSBackend::{ base_path, }
}

// ---------------------------------------------------------------------------
// Path helpers
// ---------------------------------------------------------------------------

///|
/// Build the full filesystem path for a (bucket_id, key) pair.
pub fn full_path(
  base_path : String,
  bucket_id : String,
  key : String,
) -> String {
  base_path + "/" + bucket_id + "/" + key
}

///|
/// Create a directory and all missing parent directories.
pub fn create_dir_all(path : String) -> Unit {
  if @fs.path_exists(path) {
    return
  }
  let dir_path : @path.Path = path
  let parent = @path.Path::dirname(dir_path).to_string()
  if parent != "" && parent != path {
    create_dir_all(parent)
  }
  @fs.create_dir(path) catch {
    _ => ()
  }
}

///|
/// Return the parent directory of the given path.
pub fn parent_dir(path : String) -> String {
  let p : @path.Path = path
  @path.Path::dirname(p).to_string()
}

///|
fn is_regular_file(path : String) -> Bool {
  try @fs.path_exists(path) && !@fs.is_dir(path) catch {
    _ => false
  }
}

// ---------------------------------------------------------------------------
// StorageBackend trait impl
// ---------------------------------------------------------------------------

///|
pub impl StorageBackend for LocalFSBackend with fn headObject(
  self : LocalFSBackend,
  bucket : String,
  key : String,
) -> ObjectMetadata raise BackendError {
  let path = full_path(self.base_path, bucket, key)
  if !is_regular_file(path) {
    raise NotFound("object not found: \{bucket}/\{key}")
  }
  let data = @fs.read_file_to_bytes(path) catch {
    _ => raise ReadError("failed to read: \{path}")
  }
  ObjectMetadata::{
    cacheControl: "no-cache",
    contentLength: data.length().to_int64(),
    size: data.length().to_int64(),
    mimetype: "application/octet-stream",
    eTag: data.length().to_int64().to_string(),
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn getObject(
  self : LocalFSBackend,
  bucket : String,
  key : String,
  _headers : CacheHeaders?,
) -> GetObjectResult raise BackendError {
  let path = full_path(self.base_path, bucket, key)
  if !is_regular_file(path) {
    raise NotFound("object not found: \{bucket}/\{key}")
  }
  let data = @fs.read_file_to_bytes(path) catch {
    _ => raise ReadError("failed to read: \{path}")
  }
  GetObjectResult::{
    body: data,
    metadata: ObjectMetadata::{
      cacheControl: "no-cache",
      contentLength: data.length().to_int64(),
      size: data.length().to_int64(),
      mimetype: "application/octet-stream",
      eTag: data.length().to_int64().to_string(),
    },
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn uploadObject(
  self : LocalFSBackend,
  bucket : String,
  key : String,
  body : Bytes,
  contentType : String,
  cacheControl : String,
) -> ObjectMetadata raise BackendError {
  let path = full_path(self.base_path, bucket, key)
  let dir = parent_dir(path)
  create_dir_all(dir)
  @fs.write_bytes_to_file(path, body) catch {
    _ => raise WriteError("failed to write: \{path}")
  }
  ObjectMetadata::{
    cacheControl,
    contentLength: body.length().to_int64(),
    size: body.length().to_int64(),
    mimetype: contentType,
    eTag: body.length().to_int64().to_string(),
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn deleteObject(
  self : LocalFSBackend,
  bucket : String,
  key : String,
) -> Unit raise BackendError {
  let path = full_path(self.base_path, bucket, key)
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn deleteObjects(
  self : LocalFSBackend,
  bucket : String,
  keys : Array[String],
) -> Unit raise BackendError {
  for key in keys {
    let path = full_path(self.base_path, bucket, key)
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn copyObject(
  self : LocalFSBackend,
  bucket : String,
  source : String,
  destination : String,
) -> CopyObjectResult raise BackendError {
  let src = full_path(self.base_path, bucket, source)
  if !is_regular_file(src) {
    raise NotFound("source not found: \{bucket}/\{source}")
  }
  let dst = full_path(self.base_path, bucket, destination)
  let dir = parent_dir(dst)
  create_dir_all(dir)
  let data = @fs.read_file_to_bytes(src) catch {
    _ => raise ReadError("failed to read: \{src}")
  }
  @fs.write_bytes_to_file(dst, data) catch {
    _ => raise WriteError("failed to write: \{dst}")
  }
  CopyObjectResult::{ eTag: data.length().to_int64().to_string() }
}

///|
pub impl StorageBackend for LocalFSBackend with fn listObjects(
  _self : LocalFSBackend,
  _bucket : String,
  _prefix : String?,
  _limit : Int?,
  _nextToken : String?,
) -> ListObjectsResult raise BackendError {
  ListObjectsResult::{ keys: [], nextToken: None }
}

///|
pub impl StorageBackend for LocalFSBackend with fn createMultiPartUpload(
  _self : LocalFSBackend,
  bucket : String,
  key : String,
  contentType : String,
  _cacheControl : String,
) -> String raise BackendError {
  bucket + "/" + key + "/upload-" + contentType
}

///|
pub impl StorageBackend for LocalFSBackend with fn uploadPart(
  self : LocalFSBackend,
  _bucket : String,
  _key : String,
  uploadId : String,
  partNumber : Int,
  body : Bytes,
) -> UploadPartResult raise BackendError {
  let part_path = self.base_path +
    "/multiparts/" +
    uploadId +
    "/part-" +
    partNumber.to_string()
  create_dir_all(parent_dir(part_path))
  @fs.write_bytes_to_file(part_path, body) catch {
    _ => raise WriteError("failed to write part")
  }
  UploadPartResult::{ e_tag: Some(body.length().to_int64().to_string()) }
}

///|
pub impl StorageBackend for LocalFSBackend with fn completeMultipartUpload(
  self : LocalFSBackend,
  bucket : String,
  key : String,
  uploadId : String,
  parts : Array[UploadPart],
) -> CompleteUploadResult raise BackendError {
  let multipart_dir = self.base_path + "/multiparts/" + uploadId
  let buf = @buffer.Buffer::Buffer()
  for p in parts {
    let part_path = multipart_dir + "/part-" + p.part_number.to_string()
    let data = @fs.read_file_to_bytes(part_path) catch {
      _ => raise NotFound("part not found")
    }
    buf.write_bytes(data)
  }
  let merged = buf.to_bytes()
  let path = full_path(self.base_path, bucket, key)
  create_dir_all(parent_dir(path))
  @fs.write_bytes_to_file(path, merged) catch {
    _ => raise WriteError("failed to write: \{path}")
  }
  CompleteUploadResult::{
    e_tag: Some(merged.length().to_int64().to_string()),
    location: bucket + "/" + key,
    bucket,
    version: "1",
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn abortMultipartUpload(
  self : LocalFSBackend,
  _bucket : String,
  _key : String,
  uploadId : String,
) -> Unit raise BackendError {
  let multipart_dir = self.base_path + "/multiparts/" + uploadId
  @fs.remove_file(multipart_dir) catch {
    _ => ()
  }
}

///|
pub impl StorageBackend for LocalFSBackend with fn close(_self : LocalFSBackend) -> Unit {

}
