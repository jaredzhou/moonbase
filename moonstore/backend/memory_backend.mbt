// MemoryBackend — in-memory StorageBackend implementation for testing.

///|
struct FileMeta {
  contentType : String
  cacheControl : String
}

///|
struct MultiPartState {
  contentType : String
  cacheControl : String
  parts : Map[Int, Bytes]
}

///|
/// In-memory file storage for testing. Keys are "bucket/key".
pub(all) struct MemoryBackend {
  mut files : Map[String, Bytes]
  mut metadata : Map[String, FileMeta]
  mut multiparts : Map[String, MultiPartState]
}

///|
pub fn MemoryBackend::new() -> MemoryBackend {
  MemoryBackend::{ files: Map([]), metadata: Map([]), multiparts: Map([]) }
}

///|
fn MemoryBackend::file_key(
  _self : MemoryBackend,
  bucket : String,
  key : String,
) -> String {
  bucket + "/" + key
}

///|
fn MemoryBackend::check_key(
  _self : MemoryBackend,
  key : String,
) -> Unit raise BackendError {
  if key.length() > 1024 {
    raise KeyTooLong("key exceeds 1024 bytes")
  }
}

///|
fn compute_etag(data : Bytes) -> String {
  data.length().to_int64().to_string()
}

// ---------------------------------------------------------------------------
// Core operations
// ---------------------------------------------------------------------------

///|
pub impl StorageBackend for MemoryBackend with fn headObject(
  self : MemoryBackend,
  bucket : String,
  key : String,
) -> ObjectMetadata raise BackendError {
  self.check_key(key)
  let fk = self.file_key(bucket, key)
  match self.metadata.get(fk) {
    Some(m) => {
      let data = self.files.get(fk).unwrap_or(b"")
      ObjectMetadata::{
        cacheControl: m.cacheControl,
        contentLength: data.length().to_int64(),
        size: data.length().to_int64(),
        mimetype: m.contentType,
        eTag: compute_etag(data),
      }
    }
    None => raise NotFound("object not found: \{bucket}/\{key}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn getObject(
  self : MemoryBackend,
  bucket : String,
  key : String,
  _headers : CacheHeaders?,
) -> GetObjectResult raise BackendError {
  self.check_key(key)
  let fk = self.file_key(bucket, key)
  let data = match self.files.get(fk) {
    Some(d) => d
    None => raise NotFound("object not found: \{bucket}/\{key}")
  }
  let meta = match self.metadata.get(fk) {
    Some(m) => m
    None =>
      FileMeta::{
        contentType: "application/octet-stream",
        cacheControl: "no-cache",
      }
  }
  GetObjectResult::{
    body: data,
    metadata: ObjectMetadata::{
      cacheControl: meta.cacheControl,
      contentLength: data.length().to_int64(),
      size: data.length().to_int64(),
      mimetype: meta.contentType,
      eTag: compute_etag(data),
    },
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn uploadObject(
  self : MemoryBackend,
  bucket : String,
  key : String,
  body : Bytes,
  contentType : String,
  cacheControl : String,
) -> ObjectMetadata raise BackendError {
  self.check_key(key)
  let fk = self.file_key(bucket, key)
  self.files.set(fk, body)
  self.metadata.set(fk, FileMeta::{ contentType, cacheControl })
  ObjectMetadata::{
    cacheControl,
    contentLength: body.length().to_int64(),
    size: body.length().to_int64(),
    mimetype: contentType,
    eTag: compute_etag(body),
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn deleteObject(
  self : MemoryBackend,
  bucket : String,
  key : String,
) -> Unit raise BackendError {
  let fk = self.file_key(bucket, key)
  self.files.remove(fk)
  self.metadata.remove(fk)
}

///|
pub impl StorageBackend for MemoryBackend with fn deleteObjects(
  self : MemoryBackend,
  bucket : String,
  keys : Array[String],
) -> Unit raise BackendError {
  for key in keys {
    let fk = self.file_key(bucket, key)
    self.files.remove(fk)
    self.metadata.remove(fk)
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn copyObject(
  self : MemoryBackend,
  bucket : String,
  source : String,
  destination : String,
) -> CopyObjectResult raise BackendError {
  self.check_key(destination)
  let src_k = self.file_key(bucket, source)
  let data = match self.files.get(src_k) {
    Some(d) => d
    None => raise NotFound("source not found: \{bucket}/\{source}")
  }
  let meta = match self.metadata.get(src_k) {
    Some(m) => m
    None =>
      FileMeta::{
        contentType: "application/octet-stream",
        cacheControl: "no-cache",
      }
  }
  let dst_k = self.file_key(bucket, destination)
  self.files.set(dst_k, data)
  self.metadata.set(dst_k, meta)
  CopyObjectResult::{ eTag: compute_etag(data) }
}

///|
pub impl StorageBackend for MemoryBackend with fn listObjects(
  self : MemoryBackend,
  bucket : String,
  prefix : String?,
  limit : Int?,
  nextToken : String?,
) -> ListObjectsResult raise BackendError {
  let bucket_prefix = bucket + "/"
  let result : Array[ObjectKey] = []
  let start = match nextToken {
    Some(t) => t
    None => ""
  }
  let mut found_start = start == ""
  let mut count = 0

  for k, data in self.files {
    if !k.has_prefix(bucket_prefix) {
      continue
    }
    let key = k[bucket_prefix.length():].to_owned()
    match prefix {
      Some(p) => if !key.has_prefix(p) { continue }
      None => ()
    }
    if !found_start {
      if key == start {
        found_start = true
      }
      continue
    }
    match limit {
      Some(lim) => if count >= lim { break }
      None => ()
    }
    result.push(ObjectKey::{ name: key, size: data.length().to_int64() })
    count = count + 1
  }

  ListObjectsResult::{ keys: result, nextToken: None }
}

// ---------------------------------------------------------------------------
// Multipart upload
// ---------------------------------------------------------------------------

///|
pub impl StorageBackend for MemoryBackend with fn createMultiPartUpload(
  self : MemoryBackend,
  bucket : String,
  key : String,
  contentType : String,
  cacheControl : String,
) -> String raise BackendError {
  self.check_key(key)
  let id = bucket + "/" + key + "/" + "upload-" + contentType
  self.multiparts.set(id, MultiPartState::{
    contentType,
    cacheControl,
    parts: Map([]),
  })
  id
}

///|
pub impl StorageBackend for MemoryBackend with fn uploadPart(
  self : MemoryBackend,
  _bucket : String,
  _key : String,
  uploadId : String,
  partNumber : Int,
  body : Bytes,
) -> UploadPartResult raise BackendError {
  match self.multiparts.get(uploadId) {
    Some(state) => {
      state.parts.set(partNumber, body)
      UploadPartResult::{ e_tag: Some(compute_etag(body)) }
    }
    None => raise NotFound("upload not found: \{uploadId}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn completeMultipartUpload(
  self : MemoryBackend,
  bucket : String,
  key : String,
  uploadId : String,
  parts : Array[UploadPart],
) -> CompleteUploadResult raise BackendError {
  let state = match self.multiparts.get(uploadId) {
    Some(s) => s
    None => raise NotFound("upload not found: \{uploadId}")
  }
  // Collect parts and concatenate
  let merged = merge_parts(state, parts)
  let fk = self.file_key(bucket, key)
  let etag_val = compute_etag(merged)
  self.files.set(fk, merged)
  self.metadata.set(fk, FileMeta::{
    contentType: state.contentType,
    cacheControl: state.cacheControl,
  })
  self.multiparts.remove(uploadId)
  CompleteUploadResult::{
    e_tag: Some(etag_val),
    location: bucket + "/" + key,
    bucket,
    version: "1",
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn abortMultipartUpload(
  self : MemoryBackend,
  _bucket : String,
  _key : String,
  uploadId : String,
) -> Unit raise BackendError {
  self.multiparts.remove(uploadId)
}

///|
pub impl StorageBackend for MemoryBackend with fn close(self : MemoryBackend) -> Unit {
  self.files = Map([])
}

///|
/// Concatenate parts into a single Bytes.
fn merge_parts(state : MultiPartState, part_list : Array[UploadPart]) -> Bytes {
  let buf = @buffer.Buffer::Buffer()
  for p in part_list {
    match state.parts.get(p.part_number) {
      Some(data) => buf.write_bytes(data)
      None => ()
    }
  }
  buf.to_bytes()
}
