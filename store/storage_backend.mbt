// StorageBackend trait — pluggable file storage backend.
// The MemoryBackend impl provides an in-memory file store for testing.

///|
/// Pluggable backend for storing/retrieving file bytes.
pub(open) trait StorageBackend {
  put(Self, bucket_id : String, name : String, data : Bytes) -> Unit raise StorageError
  get(Self, bucket_id : String, name : String) -> Bytes raise StorageError
  delete(Self, bucket_id : String, name : String) -> Unit raise StorageError
  exists(Self, bucket_id : String, name : String) -> Bool
}

///|
pub fn[T: StorageBackend] put(
  backend: T,
  bucket_id : String,
  name : String,
  data : Bytes,
) -> Unit raise StorageError {
  backend.put(bucket_id, name, data)
}

///|
pub fn[T: StorageBackend] get(
  backend: T,
  bucket_id : String,
  name : String,
) -> Bytes raise StorageError {
  backend.get(bucket_id, name)
}

///|
pub fn[T: StorageBackend] delete(
  backend: T,
  bucket_id : String,
  name : String,
) -> Unit raise StorageError {
  backend.delete(bucket_id, name)
}

///|
pub fn[T: StorageBackend] exists(
  backend: T,
  bucket_id : String,
  name : String,
) -> Bool {
  backend.exists(bucket_id, name)
}

// ---------------------------------------------------------------------------
// MemoryBackend — in-memory StorageBackend for testing
// ---------------------------------------------------------------------------

///|
/// In-memory file storage for testing. Keys are "bucket_id/name".
pub(all) struct MemoryBackend {
  mut files : Map[String, Bytes]
}

///|
pub fn MemoryBackend::new() -> MemoryBackend {
  MemoryBackend::{ files: Map([]) }
}

///|
fn key(bucket_id : String, name : String) -> String {
  bucket_id + "/" + name
}

///|
pub impl StorageBackend for MemoryBackend with fn put(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
  data : Bytes,
) -> Unit raise StorageError {
  self.files.set(key(bucket_id, name), data)
}

///|
pub impl StorageBackend for MemoryBackend with fn get(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Bytes raise StorageError {
  let k = key(bucket_id, name)
  match self.files.get(k) {
    Some(data) => data
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn delete(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Unit raise StorageError {
  let k = key(bucket_id, name)
  match self.files.get(k) {
    Some(_) => {
      self.files.remove(k)
    }
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn exists(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Bool {
  self.files.get(key(bucket_id, name)) is Some(_)
}
