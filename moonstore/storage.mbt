// Storage service layer -- business logic for bucket and object operations.
// Handlers delegate to Storage methods, which handle auth, validation, and repo/backend calls.

///|
/// Input for creating a bucket.
pub(all) struct CreateBucketInput {
  pub name : String
  pub public : Bool?
  pub file_size_limit : Int64?
  pub allowed_mime_types : Array[String]?
}

///|
/// Input for updating a bucket.
pub(all) struct UpdateBucketInput {
  pub public : Bool?
  pub file_size_limit : Int64?
  pub allowed_mime_types : Array[String]?
}

///|
/// Input for updating object metadata.
pub(all) struct UpdateObjectInput {
  pub user_metadata : Json?
}

///|
/// Core storage state -- holds repos, backend, and authorizer.
/// Uses trait references (&StorageBackend, &BucketRepo, &ObjectRepo) for pluggable implementations.
pub(all) struct Storage {
  pub backend : &@backend.StorageBackend
  pub bucket_repo : &BucketRepo
  pub object_repo : &ObjectRepo
  pub authorizer : Authorizer
}

///|
/// Create a new Storage with the given backend, repos, and authorizer.
pub fn Storage::new(
  backend : &@backend.StorageBackend,
  bucket_repo : &BucketRepo,
  object_repo : &ObjectRepo,
  authorizer : Authorizer,
) -> Storage {
  Storage::{ backend, bucket_repo, object_repo, authorizer }
}

///|
let uuid_counter : Ref[Int64] = { val: 0L }

///|
/// Returns the current UTC time.
fn now() -> @time.Datetime {
  @time.now()
}

///|
/// Generates a new unique identifier as a UUID string.
/// Currently derived from the current timestamp plus an in-memory counter.
fn new_uuid() -> String {
  let millis = @time.now().to_unix() * 1000L
  let count = uuid_counter.val
  uuid_counter.val = count + 1L
  let hex = millis.to_string(radix=16).pad_start(16, '0') +
    count.to_string(radix=16).pad_start(16, '0')
  try! @uuid.from_hex(hex).to_string()
}

///|
fn Storage::check_and_authorize(
  self : Storage,
  user : String?,
  action : String,
  resource_type : String,
  resource_id : String,
  overlay : Map[@ast.EntityUID, @ast.Entity]?,
) -> Unit raise StorageError {
  match user {
    None => raise Forbidden("authentication required")
    Some(u) =>
      if !self.authorizer.try_authorize(
          u, action, resource_type, resource_id, overlay,
        ) {
        raise Forbidden("access denied")
      }
  }
}

///|
fn Storage::is_public(self : Storage, bucket_id : String) -> Bool {
  match self.bucket_repo.get(bucket_id) {
    Some(b) => b.public
    None => false
  }
}

// ---------------------------------------------------------------------------
// Bucket operations
// ---------------------------------------------------------------------------

///|
pub fn Storage::create_bucket(
  self : Storage,
  user : String,
  input : CreateBucketInput,
) -> Bucket raise StorageError {
  self.check_and_authorize(
    Some(user),
    "CreateBucket",
    "Application",
    "Storage",
    None,
  )
  let id = input.name
  if self.bucket_repo.get(id) is Some(_) {
    raise AlreadyExists("bucket '\{id}' already exists")
  }
  let now = now()
  let bucket = Bucket::{
    id,
    name: input.name,
    owner: user,
    owner_id: user,
    public: input.public.unwrap_or(false),
    file_size_limit: input.file_size_limit,
    allowed_mime_types: input.allowed_mime_types,
    created_at: now,
    updated_at: now,
  }
  self.bucket_repo.insert(bucket)
  bucket
}

///|
pub fn Storage::list_buckets(
  self : Storage,
  user : String,
) -> Array[Bucket] raise StorageError {
  self.check_and_authorize(
    Some(user),
    "ListBuckets",
    "Application",
    "Storage",
    None,
  )
  self.bucket_repo.list()
}

///|
pub fn Storage::get_bucket(
  self : Storage,
  user : String,
  id : String,
) -> Bucket raise StorageError {
  self.check_and_authorize(Some(user), "GetBucket", "Bucket", id, None)
  match self.bucket_repo.get(id) {
    Some(b) => b
    None => raise NotFound("bucket not found: \{id}")
  }
}

///|
pub fn Storage::update_bucket(
  self : Storage,
  user : String,
  id : String,
  input : UpdateBucketInput,
) -> Bucket raise StorageError {
  self.check_and_authorize(Some(user), "UpdateBucket", "Bucket", id, None)
  match self.bucket_repo.get(id) {
    Some(b) => {
      let updated_now = now()
      let updated = Bucket::{
        ..b,
        public: match input.public {
          Some(p) => p
          None => b.public
        },
        file_size_limit: match input.file_size_limit {
          Some(_) => input.file_size_limit
          None => b.file_size_limit
        },
        allowed_mime_types: match input.allowed_mime_types {
          Some(_) => input.allowed_mime_types
          None => b.allowed_mime_types
        },
        updated_at: updated_now,
      }
      self.bucket_repo.update(id, updated)
      updated
    }
    None => raise NotFound("bucket not found: \{id}")
  }
}

///|
pub fn Storage::delete_bucket(
  self : Storage,
  user : String,
  id : String,
) -> Unit raise StorageError {
  self.check_and_authorize(Some(user), "DeleteBucket", "Bucket", id, None)
  let objects = self.object_repo.list(id, None, Some(1), None)
  if objects.length() > 0 {
    raise NotEmpty("bucket '\{id}' is not empty")
  }
  self.bucket_repo.delete(id)
}

///|
pub fn Storage::empty_bucket(
  self : Storage,
  user : String,
  id : String,
) -> Unit raise StorageError {
  self.check_and_authorize(Some(user), "EmptyBucket", "Bucket", id, None)
  let objects = self.object_repo.list(id, None, None, None)
  for obj in objects {
    self.backend.deleteObject(id, obj.name) catch {
      _ => continue
    }
    self.object_repo.delete(id, obj.name)
  }
}

// ---------------------------------------------------------------------------
// Object operations
// ---------------------------------------------------------------------------

///|
pub fn Storage::upload(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
  data : Bytes,
  user_metadata : Json,
) -> Object raise StorageError {
  self.check_and_authorize(
    Some(user),
    "UploadObject",
    "Bucket",
    bucket_id,
    None,
  )
  match self.bucket_repo.get(bucket_id) {
    None => raise NotFound("bucket not found: \{bucket_id}")
    Some(b) => {
      match b.allowed_mime_types {
        Some(types) => {
          let mime = mimetype_from_data(data)
          if !types.contains(mime) {
            raise InvalidInput("mime type not allowed")
          }
        }
        None => ()
      }
      match b.file_size_limit {
        Some(limit) =>
          if data.length().to_int64() > limit {
            raise InvalidInput("file exceeds size limit")
          }
        None => ()
      }
    }
  }
  if self.object_repo.get(bucket_id, name) is Some(_) {
    raise AlreadyExists("object '\{name}' already exists in '\{bucket_id}'")
  }
  let mime = mimetype_from_data(data)
  let _ = self.backend.uploadObject(bucket_id, name, data, mime, "no-cache") catch {
    e => raise from_backend_error(e)
  }
  let id = new_uuid()
  let now = now()
  let obj = Object::{
    id: Some(id),
    name,
    bucket_id,
    owner: user,
    owner_id: user,
    version: "1",
    metadata: StorageMetadata::{
      size: data.length().to_int64(),
      mimetype: mime,
      cache_control: None,
    },
    user_metadata,
    created_at: now,
    updated_at: None,
    last_accessed_at: None,
  }
  self.object_repo.insert(obj)
  obj
}

///|
pub fn Storage::download(
  self : Storage,
  user : String?,
  bucket_id : String,
  name : String,
) -> (Object, Bytes) raise StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      if self.is_public(bucket_id) {
        let result = self.backend.getObject(bucket_id, name, None) catch {
          e => raise from_backend_error(e)
        }
        return (obj, result.body)
      }
      self.check_and_authorize(
        user,
        "DownloadObject",
        "Object",
        match obj.id {
          Some(id) => id
          None => bucket_id + "/" + name
        },
        None,
      )
      let result = self.backend.getObject(bucket_id, name, None) catch {
        e => raise from_backend_error(e)
      }
      (obj, result.body)
    }
  }
}

///|
pub fn Storage::get_object_info(
  self : Storage,
  user : String?,
  bucket_id : String,
  name : String,
) -> Object raise StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      if !self.is_public(bucket_id) {
        self.check_and_authorize(
          user,
          "GetObjectInfo",
          "Object",
          match obj.id {
            Some(id) => id
            None => bucket_id + "/" + name
          },
          None,
        )
      }
      obj
    }
  }
}

///|
pub fn Storage::update_object(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
  input : UpdateObjectInput,
) -> Object raise StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      self.check_and_authorize(
        Some(user),
        "UpdateObject",
        "Object",
        match obj.id {
          Some(id) => id
          None => bucket_id + "/" + name
        },
        None,
      )
      let updated = Object::{
        ..obj,
        user_metadata: match input.user_metadata {
          Some(m) => m
          None => obj.user_metadata
        },
        updated_at: Some(now()),
      }
      self.object_repo.insert(updated)
      updated
    }
  }
}

///|
pub fn Storage::list_objects(
  self : Storage,
  user : String,
  bucket_id : String,
  prefix : String?,
  limit : Int?,
  offset : Int?,
  sort_by : String?,
) -> Array[Object] raise StorageError {
  self.check_and_authorize(Some(user), "ListObjects", "Bucket", bucket_id, None)
  self.object_repo.list(bucket_id, prefix, limit, offset)
}

///|
pub fn Storage::move_object(
  self : Storage,
  user : String,
  bucket_id : String,
  from : String,
  to : String,
) -> Unit raise StorageError {
  match self.object_repo.get(bucket_id, from) {
    None => raise NotFound("source not found: \{bucket_id}/\{from}")
    Some(obj) => {
      self.check_and_authorize(
        Some(user),
        "MoveObject",
        "Object",
        match obj.id {
          Some(id) => id
          None => bucket_id + "/" + from
        },
        None,
      )
      let result = self.backend.getObject(bucket_id, from, None) catch {
        e => raise from_backend_error(e)
      }
      let data = result.body
      let mime = result.metadata.mimetype
      let _ = self.backend.uploadObject(bucket_id, to, data, mime, "no-cache") catch {
        e => raise from_backend_error(e)
      }
      self.backend.deleteObject(bucket_id, from) catch {
        e => raise from_backend_error(e)
      }
      self.object_repo.delete(bucket_id, from)
      let moved = Object::{ ..obj, name: to }
      self.object_repo.insert(moved)
    }
  }
}

///|
pub fn Storage::copy_object(
  self : Storage,
  user : String,
  bucket_id : String,
  from : String,
  to : String,
) -> Unit raise StorageError {
  match self.object_repo.get(bucket_id, from) {
    None => raise NotFound("source not found: \{bucket_id}/\{from}")
    Some(obj) => {
      self.check_and_authorize(
        Some(user),
        "CopyObject",
        "Object",
        match obj.id {
          Some(id) => id
          None => bucket_id + "/" + from
        },
        None,
      )
      let _ = self.backend.copyObject(bucket_id, from, to) catch {
        e => raise from_backend_error(e)
      }
      let copy = Object::{
        ..obj,
        id: Some(new_uuid()),
        name: to,
        created_at: now(),
      }
      self.object_repo.insert(copy)
    }
  }
}

///|
pub fn Storage::delete_object(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
) -> Unit raise StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      self.check_and_authorize(
        Some(user),
        "DeleteObject",
        "Object",
        match obj.id {
          Some(id) => id
          None => bucket_id + "/" + name
        },
        None,
      )
      self.backend.deleteObject(bucket_id, name) catch {
        e => raise from_backend_error(e)
      }
      self.object_repo.delete(bucket_id, name)
    }
  }
}

///|
pub fn Storage::delete_objects(
  self : Storage,
  user : String,
  bucket_id : String,
  prefixes : Array[String],
) -> Unit raise StorageError {
  self.check_and_authorize(
    Some(user),
    "DeleteObject",
    "Bucket",
    bucket_id,
    None,
  )
  for name in prefixes {
    self.backend.deleteObject(bucket_id, name) catch {
      _ => continue
    }
  }
  self.object_repo.delete_batch(bucket_id, prefixes)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Convert a BackendError to a StorageError.
fn from_backend_error(e : @backend.BackendError) -> StorageError {
  match e {
    @backend.NotFound(m) => NotFound(m)
    @backend.WriteError(m) => BackendError(m)
    @backend.ReadError(m) => BackendError(m)
    @backend.KeyTooLong(m) => InvalidInput(m)
    @backend.InvalidKey(m) => InvalidInput(m)
  }
}

///|
/// Basic mime type detection from magic bytes.
fn mimetype_from_data(data : Bytes) -> String {
  if data.length() >= 4 {
    if data[0] == b'\x89' &&
      data[1] == b'P' &&
      data[2] == b'N' &&
      data[3] == b'G' {
      return "image/png"
    }
  }
  if data.length() >= 2 {
    if data[0] == b'\xFF' && data[1] == b'\xD8' {
      return "image/jpeg"
    }
  }
  "application/octet-stream"
}
