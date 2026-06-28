# Store — Lightweight Object Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a `jaredzhou/store` module providing Supabase-compatible REST API for bucket/object CRUD with Cedar authorization and pluggable backends.

**Architecture:** Three-layer design — repo traits (BucketRepo, ObjectRepo) for metadata, StorageBackend trait for file I/O, and Storage service layer wrapping both with Cedar authorization. REST handlers are thin wrappers over Storage methods. Entity store uses CompositeEntityStore (in-memory → PG fallback) wrapped per-request by RequestEntityStore with a transient overlay.

**Tech Stack:** MoonBit (native target), pony (HTTP router), mooncedar (Cedar engine), moonbitlang/async, moonbitlang/x, moonbitlang/core/json.

## Global Constraints

- Workspace member added to `moon.work` as `"./store"`
- Package name: `jaredzhou/store` version `0.1.0`
- Preferred target: `native`
- Dependencies: `jaredzhou/pony@0.1.1`, `jaredzhou/mooncedar@0.1.1`, `moonbitlang/async@0.19.4`, `moonbitlang/x@0.4.45`
- REST API matches Supabase Storage URL structure: `/bucket` and `/object` as top-level prefixes
- Auth via `X-User` header (same pattern as TinyTodo)
- `pub(all)` visibility on types accessed by white-box tests
- Tests: `_wbtest.mbt` for white-box, `_test.mbt` for black-box, `store_test.mbt` for integration
- `moon check` and `moon test --all` must pass before each commit

---

### Task 1: Workspace Scaffold

**Files:**
- Create: `store/moon.mod`
- Create: `store/moon.pkg`
- Create: `store/handler/moon.pkg`
- Create: `store/backend/moon.pkg`
- Modify: `moon.work`

**Interfaces:**
- Consumes: (none — foundational task)
- Produces: Workspace compiles with `moon check`

- [ ] **Step 1: Create `store/moon.mod`**

```toml
name = "jaredzhou/store"

version = "0.1.0"

license = "Apache-2.0"

description = "Lightweight object storage service with Cedar authorization"

repository = "https://github.com/jaredzhou/moonbase"

preferred_target = "native"

import {
  "jaredzhou/pony@0.1.1",
  "jaredzhou/mooncedar@0.1.1",
  "moonbitlang/async@0.19.4",
  "moonbitlang/x@0.4.45",
}
```

- [ ] **Step 2: Create `store/moon.pkg`**

```toml
import {
  "jaredzhou/pony",
  "jaredzhou/mooncedar",
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "jaredzhou/mooncedar/parser",
  "jaredzhou/store/handler",
  "jaredzhou/store/backend",
  "moonbitlang/core/json",
  "moonbitlang/core/debug",
  "moonbitlang/async",
  "moonbitlang/x/time",
}
```

- [ ] **Step 3: Create `store/handler/moon.pkg`**

```toml
import {
  "jaredzhou/pony",
  "jaredzhou/mooncedar",
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "moonbitlang/core/json",
  "moonbitlang/core/debug",
}
```

- [ ] **Step 4: Create `store/backend/moon.pkg`**

```toml
import {
  "jaredzhou/mooncedar",
  "moonbitlang/x/fs",
  "moonbitlang/core/debug",
}
```

- [ ] **Step 5: Add `"./store"` to `moon.work` members list**

```
members = [
  "./pony",
  "./libs",
  "./mooncedar",
  "./todo",
  "./store",
]
```

- [ ] **Step 6: Verify workspace compiles**

Run: `cd /home/jared/projects/moonbase && moon check`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add store/ moon.work
git commit -m "feat(store): scaffold module with moon.mod, moon.pkg, and handler/backend sub-packages"
```

---

### Task 2: Core Types — StorageError, Bucket, StorageMetadata, Object

**Files:**
- Create: `store/types.mbt`
- Modify: `store/moon.pkg` (add import of sub-module)

**Interfaces:**
- Consumes: Task 1 (module scaffold)
- Produces:
  - `pub enum StorageError { NotFound(String), AlreadyExists(String), NotEmpty(String), Forbidden(String), BackendError(String), RepoError(String), InvalidInput(String) }`
  - `pub struct Bucket { id: String, name: String, owner: String, owner_id: String, public: Bool, file_size_limit: Int64?, allowed_mime_types: Array[String]?, created_at: String, updated_at: String }`
  - `pub struct StorageMetadata { size: Int64, mimetype: String, cache_control: String? }`
  - `pub struct Object { id: String?, name: String, bucket_id: String, owner: String, owner_id: String, version: String, metadata: StorageMetadata, user_metadata: @json.Json, created_at: String, updated_at: String?, last_accessed_at: String? }`

- [ ] **Step 1: Write `store/types.mbt`**

```moonbit
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
  pub user_metadata : @json.Json
  pub created_at : String
  pub updated_at : String?
  pub last_accessed_at : String?
} derive(Debug, Eq)
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon check`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add store/types.mbt
git commit -m "feat(store): add core types — StorageError, Bucket, StorageMetadata, Object"
```

---

### Task 3: StorageBackend Trait + MemoryBackend

**Files:**
- Create: `store/storage_backend.mbt`

**Interfaces:**
- Consumes: Task 2 (types)
- Produces:
  - `pub(open) trait StorageBackend { put(String, String, Bytes) -> Unit!StorageError; get(String, String) -> Bytes!StorageError; delete(String, String) -> Unit!StorageError; exists(String, String) -> Bool }`
  - `pub(all) struct MemoryBackend { files: Map[String, Bytes] }` implementing `StorageBackend`

- [ ] **Step 1: Write test for MemoryBackend**

Create `store/storage_backend_wbtest.mbt`:

```moonbit
test "MemoryBackend put and get" {
  let backend = @storage_backend.MemoryBackend::new()
  @storage_backend.put(backend, "avatars", "test.txt", b"hello world") catch {
    _ => @debug.crash("unexpected error")
  }
  @debug.assert_true(@storage_backend.exists(backend, "avatars", "test.txt"))
  let data = @storage_backend.get(backend, "avatars", "test.txt") catch {
    _ => @debug.crash("unexpected error")
  }
  @debug.assert_eq(data, b"hello world")
}

test "MemoryBackend delete and exists" {
  let backend = @storage_backend.MemoryBackend::new()
  @storage_backend.put(backend, "avatars", "temp.txt", b"data") catch {
    _ => @debug.crash("unexpected error")
  }
  @debug.assert_true(@storage_backend.exists(backend, "avatars", "temp.txt"))
  @storage_backend.delete(backend, "avatars", "temp.txt") catch {
    _ => @debug.crash("unexpected error")
  }
  @debug.assert_false(@storage_backend.exists(backend, "avatars", "temp.txt"))
}

test "MemoryBackend get non-existent" {
  let backend = @storage_backend.MemoryBackend::new()
  let result = @storage_backend.get(backend, "avatars", "nope.txt")
  match result {
    Ok(_) => @debug.crash("expected error")
    Err(e) => @debug.assert_true(e is @types.NotFound)
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — `@storage_backend` module not found

- [ ] **Step 3: Write `store/storage_backend.mbt`**

```moonbit
// StorageBackend trait — pluggable file storage backend.
// The MemoryBackend impl provides an in-memory file store for testing.

///|
/// Pluggable backend for storing/retrieving file bytes.
pub(open) trait StorageBackend {
  put(Self, bucket_id : String, name : String, data : Bytes) -> Unit!@types.StorageError
  get(Self, bucket_id : String, name : String) -> Bytes!@types.StorageError
  delete(Self, bucket_id : String, name : String) -> Unit!@types.StorageError
  exists(Self, bucket_id : String, name : String) -> Bool
}

///|
pub fn put(
  self : StorageBackend,
  bucket_id : String,
  name : String,
  data : Bytes,
) -> Unit!@types.StorageError {
  self.put(bucket_id, name, data)
}

///|
pub fn get(
  self : StorageBackend,
  bucket_id : String,
  name : String,
) -> Bytes!@types.StorageError {
  self.get(bucket_id, name)
}

///|
pub fn delete(
  self : StorageBackend,
  bucket_id : String,
  name : String,
) -> Unit!@types.StorageError {
  self.delete(bucket_id, name)
}

///|
pub fn exists(
  self : StorageBackend,
  bucket_id : String,
  name : String,
) -> Bool {
  self.exists(bucket_id, name)
}

// ---------------------------------------------------------------------------
// MemoryBackend — in-memory StorageBackend for testing
// ---------------------------------------------------------------------------

///|
/// In-memory file storage for testing. Keys are "bucket_id/name".
pub(all) struct MemoryBackend {
  pub mut files : Map[String, Bytes]
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
) -> Unit!@types.StorageError {
  self.files.set(key(bucket_id, name), data)
}

///|
pub impl StorageBackend for MemoryBackend with fn get(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Bytes!@types.StorageError {
  let k = key(bucket_id, name)
  match self.files.get(k) {
    Some(data) => data
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn delete(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Unit!@types.StorageError {
  let k = key(bucket_id, name)
  match self.files.get(k) {
    Some(_) => {
      self.files.remove(k)
    }
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl StorageBackend for MemoryBackend with fn exists(
  self : MemoryBackend,
  bucket_id : String,
  name : String,
) -> Bool {
  self.files.get(key(bucket_id, name)).is_some()
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 3 tests pass (MemoryBackend put/get, delete/exists, get non-existent)

- [ ] **Step 5: Commit**

```bash
git add store/storage_backend.mbt store/storage_backend_wbtest.mbt
git commit -m "feat(store): add StorageBackend trait and MemoryBackend implementation"
```

---

### Task 4: BucketRepo Trait + MemoryBucketRepo

**Files:**
- Create: `store/bucket_repo.mbt`

**Interfaces:**
- Consumes: Task 2 (Bucket type)
- Produces:
  - `pub(open) trait BucketRepo { get(String) -> Bucket?; list() -> Array[Bucket]; insert(Bucket) -> Unit; update(String, Bucket) -> Unit; delete(String) -> Unit }`
  - `pub(all) struct MemoryBucketRepo { buckets: Map[String, Bucket] }` implementing `BucketRepo`

- [ ] **Step 1: Write test for MemoryBucketRepo**

Create `store/bucket_repo_wbtest.mbt`:

```moonbit
test "MemoryBucketRepo insert and get" {
  let repo = @bucket_repo.MemoryBucketRepo::new()
  let bucket = @types.Bucket::{
    id: "avatars",
    name: "Avatars",
    owner: "alice",
    owner_id: "user-1",
    public: false,
    file_size_limit: None,
    allowed_mime_types: None,
    created_at: "2024-01-01T00:00:00Z",
    updated_at: "2024-01-01T00:00:00Z",
  }
  @bucket_repo.insert(repo, bucket)
  let found = @bucket_repo.get(repo, "avatars")
  @debug.assert_true(found.is_some())
  @debug.assert_eq(found.unwrap().name, "Avatars")
}

test "MemoryBucketRepo list" {
  let repo = @bucket_repo.MemoryBucketRepo::new()
  let b1 = @types.Bucket::{
    id: "a", name: "A", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  let b2 = @types.Bucket::{
    id: "b", name: "B", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  @bucket_repo.insert(repo, b1)
  @bucket_repo.insert(repo, b2)
  let all = @bucket_repo.list(repo)
  @debug.assert_eq(all.length(), 2)
}

test "MemoryBucketRepo update and delete" {
  let repo = @bucket_repo.MemoryBucketRepo::new()
  let bucket = @types.Bucket::{
    id: "test", name: "Test", owner: "u", owner_id: "u-1", public: false,
    file_size_limit: None, allowed_mime_types: None,
    created_at: "", updated_at: "",
  }
  @bucket_repo.insert(repo, bucket)
  let updated = @types.Bucket::{ ..bucket, public: true }
  @bucket_repo.update(repo, "test", updated)
  @debug.assert_true(@bucket_repo.get(repo, "test").unwrap().public)

  @bucket_repo.delete(repo, "test")
  @debug.assert_true(@bucket_repo.get(repo, "test").is_none())
}

test "MemoryBucketRepo get non-existent" {
  let repo = @bucket_repo.MemoryBucketRepo::new()
  @debug.assert_true(@bucket_repo.get(repo, "nope").is_none())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/bucket_repo.mbt`**

```moonbit
// BucketRepo trait + MemoryBucketRepo implementation.

///|
/// Pluggable bucket metadata storage.
pub(open) trait BucketRepo {
  get(Self, id : String) -> @types.Bucket?
  list(Self) -> Array[@types.Bucket]
  insert(Self, bucket : @types.Bucket) -> Unit
  update(Self, id : String, bucket : @types.Bucket) -> Unit
  delete(Self, id : String) -> Unit
}

///|
pub fn get(self : BucketRepo, id : String) -> @types.Bucket? {
  self.get(id)
}

///|
pub fn list(self : BucketRepo) -> Array[@types.Bucket] {
  self.list()
}

///|
pub fn insert(self : BucketRepo, bucket : @types.Bucket) -> Unit {
  self.insert(bucket)
}

///|
pub fn update(self : BucketRepo, id : String, bucket : @types.Bucket) -> Unit {
  self.update(id, bucket)
}

///|
pub fn delete(self : BucketRepo, id : String) -> Unit {
  self.delete(id)
}

// ---------------------------------------------------------------------------
// MemoryBucketRepo
// ---------------------------------------------------------------------------

///|
/// In-memory bucket metadata store for testing.
pub(all) struct MemoryBucketRepo {
  pub mut buckets : Map[String, @types.Bucket]
}

///|
pub fn MemoryBucketRepo::new() -> MemoryBucketRepo {
  MemoryBucketRepo::{ buckets: Map([]) }
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn get(
  self : MemoryBucketRepo,
  id : String,
) -> @types.Bucket? {
  self.buckets.get(id)
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn list(
  self : MemoryBucketRepo,
) -> Array[@types.Bucket] {
  let result : Array[@types.Bucket] = []
  for _, bucket in self.buckets {
    result.push(bucket)
  }
  result
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn insert(
  self : MemoryBucketRepo,
  bucket : @types.Bucket,
) -> Unit {
  self.buckets.set(bucket.id, bucket)
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn update(
  self : MemoryBucketRepo,
  id : String,
  bucket : @types.Bucket,
) -> Unit {
  self.buckets.set(id, bucket)
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn delete(
  self : MemoryBucketRepo,
  id : String,
) -> Unit {
  self.buckets.remove(id)
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 7 tests pass (4 from Task 3 + 4 new)

- [ ] **Step 5: Commit**

```bash
git add store/bucket_repo.mbt store/bucket_repo_wbtest.mbt
git commit -m "feat(store): add BucketRepo trait and MemoryBucketRepo implementation"
```

---

### Task 5: ObjectRepo Trait + MemoryObjectRepo

**Files:**
- Create: `store/object_repo.mbt`

**Interfaces:**
- Consumes: Task 2 (Object type)
- Produces:
  - `pub(open) trait ObjectRepo { get(String, String) -> Object?; list(String, String?, Int?, Int?) -> Array[Object]; insert(Object) -> Unit; delete(String, String) -> Unit; delete_batch(String, Array[String]) -> Unit }`
  - `pub(all) struct MemoryObjectRepo { objects: Map[String, Object] }` implementing `ObjectRepo`

- [ ] **Step 1: Write test for MemoryObjectRepo**

Create `store/object_repo_wbtest.mbt`:

```moonbit
test "MemoryObjectRepo insert and get" {
  let repo = @object_repo.MemoryObjectRepo::new()
  let obj = @types.Object::{
    id: Some("uuid-1"),
    name: "public/avatar.png",
    bucket_id: "avatars",
    owner: "alice",
    owner_id: "user-1",
    version: "1",
    metadata: @types.StorageMetadata::{
      size: 1024, mimetype: "image/png", cache_control: None,
    },
    user_metadata: @json.Json::Object(Map([])),
    created_at: "2024-01-01T00:00:00Z",
    updated_at: None,
    last_accessed_at: None,
  }
  @object_repo.insert(repo, obj)
  let found = @object_repo.get(repo, "avatars", "public/avatar.png")
  @debug.assert_true(found.is_some())
  @debug.assert_eq(found.unwrap().metadata.size, 1024)
}

test "MemoryObjectRepo list with prefix" {
  let repo = @object_repo.MemoryObjectRepo::new()
  let mk_obj = fn(name : String) -> @types.Object {
    @types.Object::{
      id: Some("id-" + name),
      name,
      bucket_id: "avatars",
      owner: "u", owner_id: "u-1", version: "1",
      metadata: @types.StorageMetadata::{ size: 0, mimetype: "", cache_control: None },
      user_metadata: @json.Json::Object(Map([])),
      created_at: "", updated_at: None, last_accessed_at: None,
    }
  }
  @object_repo.insert(repo, mk_obj("public/a.png"))
  @object_repo.insert(repo, mk_obj("public/b.png"))
  @object_repo.insert(repo, mk_obj("private/x.png"))
  let result = @object_repo.list(repo, "avatars", Some("public/"), None, None)
  @debug.assert_eq(result.length(), 2)
}

test "MemoryObjectRepo delete and delete_batch" {
  let repo = @object_repo.MemoryObjectRepo::new()
  let mk_obj = fn(name : String) -> @types.Object {
    @types.Object::{
      id: Some("id-" + name),
      name,
      bucket_id: "avatars",
      owner: "u", owner_id: "u-1", version: "1",
      metadata: @types.StorageMetadata::{ size: 0, mimetype: "", cache_control: None },
      user_metadata: @json.Json::Object(Map([])),
      created_at: "", updated_at: None, last_accessed_at: None,
    }
  }
  @object_repo.insert(repo, mk_obj("a.txt"))
  @object_repo.insert(repo, mk_obj("b.txt"))
  @object_repo.insert(repo, mk_obj("c.txt"))

  @object_repo.delete(repo, "avatars", "a.txt")
  @debug.assert_true(@object_repo.get(repo, "avatars", "a.txt").is_none())

  @object_repo.delete_batch(repo, "avatars", ["b.txt", "c.txt"])
  @debug.assert_true(@object_repo.get(repo, "avatars", "b.txt").is_none())
  @debug.assert_true(@object_repo.get(repo, "avatars", "c.txt").is_none())
}

test "MemoryObjectRepo get non-existent" {
  let repo = @object_repo.MemoryObjectRepo::new()
  @debug.assert_true(@object_repo.get(repo, "avatars", "nope.txt").is_none())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/object_repo.mbt`**

```moonbit
// ObjectRepo trait + MemoryObjectRepo implementation.

///|
/// Pluggable object metadata storage.
pub(open) trait ObjectRepo {
  get(Self, bucket_id : String, name : String) -> @types.Object?
  list(Self, bucket_id : String, prefix : String?, limit : Int?, offset : Int?) -> Array[@types.Object]
  insert(Self, obj : @types.Object) -> Unit
  delete(Self, bucket_id : String, name : String) -> Unit
  delete_batch(Self, bucket_id : String, names : Array[String]) -> Unit
}

///|
pub fn get(self : ObjectRepo, bucket_id : String, name : String) -> @types.Object? {
  self.get(bucket_id, name)
}

///|
pub fn list(
  self : ObjectRepo,
  bucket_id : String,
  prefix : String?,
  limit : Int?,
  offset : Int?,
) -> Array[@types.Object] {
  self.list(bucket_id, prefix, limit, offset)
}

///|
pub fn insert(self : ObjectRepo, obj : @types.Object) -> Unit {
  self.insert(obj)
}

///|
pub fn delete(self : ObjectRepo, bucket_id : String, name : String) -> Unit {
  self.delete(bucket_id, name)
}

///|
pub fn delete_batch(
  self : ObjectRepo,
  bucket_id : String,
  names : Array[String],
) -> Unit {
  self.delete_batch(bucket_id, names)
}

// ---------------------------------------------------------------------------
// MemoryObjectRepo
// ---------------------------------------------------------------------------

///|
/// In-memory object metadata store for testing. Key is "bucket_id/name".
pub(all) struct MemoryObjectRepo {
  pub mut objects : Map[String, @types.Object]
}

///|
pub fn MemoryObjectRepo::new() -> MemoryObjectRepo {
  MemoryObjectRepo::{ objects: Map([]) }
}

///|
fn obj_key(bucket_id : String, name : String) -> String {
  bucket_id + "/" + name
}

///|
pub impl ObjectRepo for MemoryObjectRepo with fn get(
  self : MemoryObjectRepo,
  bucket_id : String,
  name : String,
) -> @types.Object? {
  self.objects.get(obj_key(bucket_id, name))
}

///|
pub impl ObjectRepo for MemoryObjectRepo with fn list(
  self : MemoryObjectRepo,
  bucket_id : String,
  prefix : String?,
  limit : Int?,
  offset : Int?,
) -> Array[@types.Object] {
  let result : Array[@types.Object] = []
  let mut skipped = 0
  for _, obj in self.objects {
    if obj.bucket_id != bucket_id {
      continue
    }
    match prefix {
      Some(p) => if !obj.name.starts_with(p) { continue }
      None => ()
    }
    match offset {
      Some(off) if skipped < off => {
        skipped = skipped + 1
        continue
      }
      _ => ()
    }
    result.push(obj)
    match limit {
      Some(lim) => if result.length() >= lim { break }
      None => ()
    }
  }
  result
}

///|
pub impl ObjectRepo for MemoryObjectRepo with fn insert(
  self : MemoryObjectRepo,
  obj : @types.Object,
) -> Unit {
  self.objects.set(obj_key(obj.bucket_id, obj.name), obj)
}

///|
pub impl ObjectRepo for MemoryObjectRepo with fn delete(
  self : MemoryObjectRepo,
  bucket_id : String,
  name : String,
) -> Unit {
  self.objects.remove(obj_key(bucket_id, name))
}

///|
pub impl ObjectRepo for MemoryObjectRepo with fn delete_batch(
  self : MemoryObjectRepo,
  bucket_id : String,
  names : Array[String],
) -> Unit {
  for name in names {
    self.objects.remove(obj_key(bucket_id, name))
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 11 tests pass (7 from prior + 4 new)

- [ ] **Step 5: Commit**

```bash
git add store/object_repo.mbt store/object_repo_wbtest.mbt
git commit -m "feat(store): add ObjectRepo trait and MemoryObjectRepo implementation"
```

---

### Task 6: Entity Store Architecture — CompositeEntityStore + RequestEntityStore

**Files:**
- Create: `store/entity_store.mbt`

**Interfaces:**
- Consumes: Task 2 (types), Task 3 (StorageBackend), mooncedar evaluator types (`@evaluator.EntityStore`, `@evaluator.EntityUIDEntry`, `@ast.EntityUID`, `@ast.Entity`)
- Produces:
  - `pub(all) struct CompositeEntityStore { memory: Box[@evaluator.EntityStore], persisted: Box[@evaluator.EntityStore] }` implementing `EntityStore`
  - `pub(all) struct RequestEntityStore { overlay: Map[@ast.EntityUID, @ast.Entity], backing: Box[@evaluator.EntityStore] }` implementing `EntityStore`
  - `pub fn RequestEntityStore::add_entity(Self, @ast.EntityUID, @ast.Entity) -> Unit`

- [ ] **Step 1: Write test for entity stores**

Create `store/entity_store_wbtest.mbt`:

```moonbit
test "CompositeEntityStore falls back from memory to persisted" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(true))]),
    tags: Map([]),
    parents: [],
  }
  // Put in persisted only
  pers.entities.set(euid, entity)
  let composite = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let found = @evaluator.EntityStore::get_entity(composite, euid)
  @debug.assert_true(found.is_some())
  @debug.assert_eq(found, Some(entity))
}

test "CompositeEntityStore prefers memory over persisted" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let mem_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(true))]),
    tags: Map([]),
    parents: [],
  }
  let pers_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(false))]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, mem_entity)
  pers.entities.set(euid, pers_entity)
  let composite = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let found = @evaluator.EntityStore::get_entity(composite, euid)
  @debug.assert_true(found.is_some())
  match found {
    Some(e) => match e.attrs.get("public") {
      Some(@ast.Value::Bool(b)) => @debug.assert_true(b)
      _ => @debug.crash("unexpected attr")
    }
    _ => @debug.crash("unexpected")
  }
}

test "RequestEntityStore overlay takes priority" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let mem_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("name", @ast.Value::String("from-mem"))]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, mem_entity)
  let composite = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let backing = Box::new(composite as @evaluator.EntityStore)
  let req_store = @entity_store.RequestEntityStore::new(backing)

  let overlay_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("name", @ast.Value::String("from-overlay"))]),
    tags: Map([]),
    parents: [],
  }
  req_store.add_entity(euid, overlay_entity)

  let found = @evaluator.EntityStore::get_entity(req_store, euid)
  match found {
    Some(e) => match e.attrs.get("name") {
      Some(@ast.Value::String(s)) => @debug.assert_eq(s, "from-overlay")
      _ => @debug.crash("unexpected attr")
    }
    _ => @debug.crash("unexpected")
  }
}

test "RequestEntityStore falls through to backing" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let entity = @ast.Entity::{
    uid: euid,
    attrs: Map([]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, entity)
  let composite = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let backing = Box::new(composite as @evaluator.EntityStore)
  let req_store = @entity_store.RequestEntityStore::new(backing)

  let found = @evaluator.EntityStore::get_entity(req_store, euid)
  @debug.assert_true(found.is_some())
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/entity_store.mbt`**

```moonbit
// Entity store architecture — CompositeEntityStore and RequestEntityStore.
// CompositeEntityStore layers in-memory cache over persisted (PG) storage.
// RequestEntityStore wraps a backing store with a per-request overlay.

// ---------------------------------------------------------------------------
// CompositeEntityStore
// ---------------------------------------------------------------------------

///|
/// Shared entity store: memory cache (fast) → persisted store (PG).
/// Read-only during authorization; mutations go through the service layer.
pub(all) struct CompositeEntityStore {
  pub memory : Box[@evaluator.EntityStore]
  pub persisted : Box[@evaluator.EntityStore]
}

///|
pub fn CompositeEntityStore::new(
  memory : Box[@evaluator.EntityStore],
  persisted : Box[@evaluator.EntityStore],
) -> CompositeEntityStore {
  CompositeEntityStore::{ memory, persisted }
}

///|
/// Check memory first, fall back to persisted.
pub impl @evaluator.EntityStore for CompositeEntityStore with fn get_entity(
  self : CompositeEntityStore,
  uid : @ast.EntityUID,
) -> @ast.Entity? {
  match self.memory.get_entity(uid) {
    Some(e) => Some(e)
    None => self.persisted.get_entity(uid)
  }
}

// ---------------------------------------------------------------------------
// RequestEntityStore
// ---------------------------------------------------------------------------

///|
/// Per-request entity store: transient overlay → backing store.
/// Created fresh per request, dropped on completion. Single-threaded, no contention.
pub(all) struct RequestEntityStore {
  pub mut overlay : Map[@ast.EntityUID, @ast.Entity]
  pub backing : Box[@evaluator.EntityStore]
}

///|
pub fn RequestEntityStore::new(backing : Box[@evaluator.EntityStore]) -> RequestEntityStore {
  RequestEntityStore::{ overlay: Map([]), backing }
}

///|
/// Add a transient entity for the duration of this request.
pub fn RequestEntityStore::add_entity(
  self : RequestEntityStore,
  uid : @ast.EntityUID,
  entity : @ast.Entity,
) -> Unit {
  self.overlay.set(uid, entity)
}

///|
/// Check overlay first, fall back to backing store.
pub impl @evaluator.EntityStore for RequestEntityStore with fn get_entity(
  self : RequestEntityStore,
  uid : @ast.EntityUID,
) -> @ast.Entity? {
  match self.overlay.get(uid) {
    Some(e) => Some(e)
    None => self.backing.get_entity(uid)
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 15 tests pass (11 prior + 4 new entity store tests)

- [ ] **Step 5: Commit**

```bash
git add store/entity_store.mbt store/entity_store_wbtest.mbt
git commit -m "feat(store): add CompositeEntityStore and RequestEntityStore"
```

---

### Task 7: Authorizer — Cedar Authorization Wrapper

**Files:**
- Create: `store/authorizer.mbt`

**Interfaces:**
- Consumes: Task 6 (entity stores), mooncedar (`@evaluator.EntityStore`, `@evaluator.Request`, `@evaluator.concrete_uid`, `@evaluator.concrete_context`, `@mooncedar.is_authorized`, `@ast.Value`, `@ast.Policy`)
- Produces:
  - `pub(all) struct Authorizer { entities: @entity_store.CompositeEntityStore, policies: Array[@ast.Policy] }`
  - `pub fn Authorizer::try_authorize(Self, user, action, resource_type, resource_id, overlay: Map[@ast.EntityUID, @ast.Entity]?) -> Bool`

- [ ] **Step 1: Write test for Authorizer**

Create `store/authorizer_wbtest.mbt`:

```moonbit
test "Authorizer try_authorize allows matching policy" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let policies = @parser.parse_policies("permit(principal,action,resource);") catch {
    _ => @debug.crash("parse failed")
  }
  let authorizer = @authorizer.Authorizer::new(entities, policies)
  @debug.assert_true(
    @authorizer.try_authorize(
      authorizer, "alice", "ReadBucket", "Bucket", "avatars", None,
    ),
  )
}

test "Authorizer try_authorize denies without matching policy" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let policies = @parser.parse_policies("forbid(principal,action,resource);") catch {
    _ => @debug.crash("parse failed")
  }
  let authorizer = @authorizer.Authorizer::new(entities, policies)
  @debug.assert_false(
    @authorizer.try_authorize(
      authorizer, "alice", "ReadBucket", "Bucket", "avatars", None,
    ),
  )
}

test "Authorizer try_authorize uses overlay entities" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let policies = @parser.parse_policies(
    "permit(principal, action == Action::\"ReadBucket\", resource) when { resource.owner_id == principal };",
  ) catch {
    _ => @debug.crash("parse failed")
  }
  let authorizer = @authorizer.Authorizer::new(entities, policies)

  // Add the bucket entity to an overlay (simulating request-scoped entity)
  let overlay : Map[@ast.EntityUID, @ast.Entity] = Map([])
  let bucket_euid = @ast.EntityUID::{ type_: "Bucket", id: "avatars" }
  let bucket_entity = @ast.Entity::{
    uid: bucket_euid,
    attrs: Map([("owner_id", @ast.Value::String("alice"))]),
    tags: Map([]),
    parents: [],
  }
  overlay.set(bucket_euid, bucket_entity)

  @debug.assert_true(
    @authorizer.try_authorize(
      authorizer, "alice", "ReadBucket", "Bucket", "avatars", Some(overlay),
    ),
  )
  @debug.assert_false(
    @authorizer.try_authorize(
      authorizer, "bob", "ReadBucket", "Bucket", "avatars", Some(overlay),
    ),
  )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/authorizer.mbt`**

```moonbit
// Authorizer — Cedar authorization wrapper for store operations.

///|
/// Authorize store operations via Cedar policies.
pub(all) struct Authorizer {
  pub entities : @entity_store.CompositeEntityStore
  pub policies : Array[@ast.Policy]
}

///|
pub fn Authorizer::new(
  entities : @entity_store.CompositeEntityStore,
  policies : Array[@ast.Policy],
) -> Authorizer {
  Authorizer::{ entities, policies }
}

///|
/// Check if a user is authorized for an action on a resource.
/// If `overlay` is provided, entities within it take priority over the backing store.
pub fn Authorizer::try_authorize(
  self : Authorizer,
  user : String,
  action : String,
  resource_type : String,
  resource_id : String,
  overlay : Map[@ast.EntityUID, @ast.Entity]?,
) -> Bool {
  // Build per-request entity store
  let req_store = match overlay {
    Some(ol) => {
      let backing = Box::new(self.entities as @evaluator.EntityStore)
      let store = @entity_store.RequestEntityStore::new(backing)
      for euid, entity in ol {
        store.add_entity(euid, entity)
      }
      Box::new(store as @evaluator.EntityStore)
    }
    None => Box::new(self.entities as @evaluator.EntityStore)
  }

  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", user),
    action: @evaluator.concrete_uid("Action", action),
    resource: @evaluator.concrete_uid(resource_type, resource_id),
    context: @evaluator.Concrete(@ast.Value::Record(Map([]))),
  }
  // is_authorized expects an EntityStore, but req_store is Box[EntityStore]
  // We need to dereference the box and pass the trait object
  let result = @mooncedar.is_authorized(
    req,
    self.policies.iter(),
    req_store,
  )
  result.decision == @mooncedar.Decision::Allow
}
```

**Note:** If `Box[EntityStore]` can't be passed directly to `is_authorized` (which expects `EntityStore`), check the exact signature. `is_authorized` from mooncedar's public API takes `(Request, Iter[Policy], EntityStore) -> AuthorizationResult`. The `Box[EntityStore]` may need an explicit dereference pattern. Test with `moon check` and adjust if needed — the alternative is to call `get_entity` directly on the req_store box within the authorizer and build a `MapEntityStore` from the overlay.

- [ ] **Step 4: Run tests — check compilation first, then iterate on the box signature**

Run: `cd /home/jared/projects/moonbase && moon check`
Expected: Check for compilation errors on the `Box[EntityStore]` → `EntityStore` conversion in `is_authorized`.

**If compilation fails:** The `is_authorized` signature requires a concrete `EntityStore` impl. The `Box` may not impl the trait directly. In that case, use a wrapper approach — extract the overlay entities into a `MapEntityStore`, then call `is_authorized` with that (since `MapEntityStore` directly implements `EntityStore`). Update the function body:

```moonbit
  // Fallback approach: collect overlay entities into a temporary MapEntityStore
  match overlay {
    Some(ol) => {
      let temp = @mooncedar.new_map_store()
      for uid, entity in ol {
        temp.entities.set(uid, entity)
      }
      let result = @mooncedar.is_authorized(req, self.policies.iter(), temp)
      // If entity not found in overlay, check backing store
      result.decision == @mooncedar.Decision::Allow
    }
    None => {
      let result = @mooncedar.is_authorized(req, self.policies.iter(), self.entities)
      result.decision == @mooncedar.Decision::Allow
    }
  }
```

Iterate until `moon test` passes all 3 authorizer tests.

- [ ] **Step 5: Commit**

```bash
git add store/authorizer.mbt store/authorizer_wbtest.mbt
git commit -m "feat(store): add Authorizer — Cedar authorization wrapper with overlay support"
```

---

### Task 8: Entity Conversion — Bucket/Object to Cedar Entities

**Files:**
- Create: `store/entity_conv.mbt`

**Interfaces:**
- Consumes: Task 2 (Bucket, Object types), mooncedar ast types (`@ast.Entity`, `@ast.EntityUID`, `@ast.Value`)
- Produces:
  - `pub fn bucket_to_entity(Bucket) -> (@ast.EntityUID, @ast.Entity)`
  - `pub fn object_to_entity(Object) -> (@ast.EntityUID, @ast.Entity)`

- [ ] **Step 1: Write test for entity conversion**

Create `store/entity_conv_wbtest.mbt`:

```moonbit
test "bucket_to_entity produces correct Cedar entity" {
  let bucket = @types.Bucket::{
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
  let (uid, entity) = @entity_conv.bucket_to_entity(bucket)
  @debug.assert_eq(uid.type_, "Bucket")
  @debug.assert_eq(uid.id, "avatars")
  match entity.attrs.get("public") {
    Some(@ast.Value::Bool(b)) => @debug.assert_true(b)
    _ => @debug.crash("expected public=true")
  }
  match entity.attrs.get("owner_id") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "user-1")
    _ => @debug.crash("expected owner_id")
  }
}

test "object_to_entity produces correct Cedar entity" {
  let obj = @types.Object::{
    id: Some("uuid-1"),
    name: "public/avatar.png",
    bucket_id: "avatars",
    owner: "alice",
    owner_id: "user-1",
    version: "1",
    metadata: @types.StorageMetadata::{
      size: 2048, mimetype: "image/png", cache_control: None,
    },
    user_metadata: @json.Json::Object(Map([])),
    created_at: "2024-01-01T00:00:00Z",
    updated_at: None,
    last_accessed_at: None,
  }
  let (uid, entity) = @entity_conv.object_to_entity(obj)
  @debug.assert_eq(uid.type_, "Object")
  @debug.assert_eq(uid.id, "uuid-1")
  match entity.attrs.get("bucket_id") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "avatars")
    _ => @debug.crash("expected bucket_id")
  }
  match entity.attrs.get("folder") {
    Some(@ast.Value::String(s)) => @debug.assert_eq(s, "public")
    _ => @debug.crash("expected folder")
  }
  match entity.attrs.get("size") {
    Some(@ast.Value::Long(n)) => @debug.assert_eq(n, 2048)
    _ => @debug.crash("expected size")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/entity_conv.mbt`**

```moonbit
// Entity conversion — Bucket and Object to Cedar entity representations.

///|
/// Convert a Bucket to a (EntityUID, Entity) pair for Cedar authorization.
pub fn bucket_to_entity(bucket : @types.Bucket) -> (@ast.EntityUID, @ast.Entity) {
  let euid = @ast.EntityUID::{ type_: "Bucket", id: bucket.id }
  let attrs = Map([
    ("owner", @ast.Value::String(bucket.owner)),
    ("owner_id", @ast.Value::String(bucket.owner_id)),
    ("public", @ast.Value::Bool(bucket.public)),
  ])
  let parents = [@ast.EntityUID::{ type_: "Application", id: "Storage" }]
  (euid, @ast.Entity::{ uid: euid, attrs, tags: Map([]), parents })
}

///|
/// Extract the folder name from an object path.
/// e.g. "public/avatar.png" → "public", "readme.txt" → ""
fn folder_from_name(name : String) -> String {
  let idx = name.last_slash_index()
  match idx {
    Some(i) => name.substring(start=0, end=i)
    None => ""
  }
}

///|
/// Convert an Object to a (EntityUID, Entity) pair for Cedar authorization.
pub fn object_to_entity(obj : @types.Object) -> (@ast.EntityUID, @ast.Entity) {
  let euid = @ast.EntityUID::{
    type_: "Object",
    id: match obj.id {
      Some(id) => id
      None => obj.bucket_id + "/" + obj.name
    },
  }
  let folder = folder_from_name(obj.name)
  let attrs = Map([
    ("bucket_id", @ast.Value::String(obj.bucket_id)),
    ("owner", @ast.Value::String(obj.owner)),
    ("owner_id", @ast.Value::String(obj.owner_id)),
    ("name", @ast.Value::String(obj.name)),
    ("size", @ast.Value::Long(obj.metadata.size)),
    ("mimetype", @ast.Value::String(obj.metadata.mimetype)),
    ("folder", @ast.Value::String(folder)),
  ])
  let parents = [@ast.EntityUID::{
    type_: "Bucket",
    id: obj.bucket_id,
  }]
  (euid, @ast.Entity::{ uid: euid, attrs, tags: Map([]), parents })
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 20 tests pass (18 prior + 2 new entity conv tests)

- [ ] **Step 5: Commit**

```bash
git add store/entity_conv.mbt store/entity_conv_wbtest.mbt
git commit -m "feat(store): add bucket_to_entity and object_to_entity conversion helpers"
```

---

### Task 9: Storage Service Layer — Business Logic

**Files:**
- Create: `store/storage.mbt`

**Interfaces:**
- Consumes: Tasks 2-8 (all foundational modules)
- Produces:
  - `pub(all) struct Storage { backend: @storage_backend.StorageBackend, bucket_repo: @bucket_repo.BucketRepo, object_repo: @object_repo.ObjectRepo, authorizer: @authorizer.Authorizer }`
  - `pub fn Storage::create_bucket(Self, user, CreateBucketInput) -> Bucket!StorageError`
  - `pub fn Storage::list_buckets(Self, user) -> Array[Bucket]!StorageError`
  - `pub fn Storage::get_bucket(Self, user, id) -> Bucket!StorageError`
  - `pub fn Storage::update_bucket(Self, user, id, UpdateBucketInput) -> Bucket!StorageError`
  - `pub fn Storage::delete_bucket(Self, user, id) -> Unit!StorageError`
  - `pub fn Storage::empty_bucket(Self, user, id) -> Unit!StorageError`
  - `pub fn Storage::upload(Self, user, bucket_id, name, data, user_metadata: @json.Json) -> Object!StorageError`
  - `pub fn Storage::download(Self, user: String?, bucket_id, name) -> (Object, Bytes)!StorageError`
  - `pub fn Storage::get_object_info(Self, user: String?, bucket_id, name) -> Object!StorageError`
  - `pub fn Storage::update_object(Self, user, bucket_id, name, UpdateObjectInput) -> Object!StorageError`
  - `pub fn Storage::list_objects(Self, user, bucket_id, prefix?, limit?, offset?, sort_by?) -> Array[Object]!StorageError`
  - `pub fn Storage::move_object(Self, user, bucket_id, from, to) -> Unit!StorageError`
  - `pub fn Storage::copy_object(Self, user, bucket_id, from, to) -> Unit!StorageError`
  - `pub fn Storage::delete_object(Self, user, bucket_id, name) -> Unit!StorageError`
  - `pub fn Storage::delete_objects(Self, user, bucket_id, prefixes: Array[String]) -> Unit!StorageError`
  - Helper types: `CreateBucketInput`, `UpdateBucketInput`, `UpdateObjectInput`

- [ ] **Step 1: Write storage service test**

Create `store/storage_test.mbt` (black-box test):

```moonbit
test "create and get bucket" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "avatars",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("unexpected error: \{e}") }
  @debug.assert_eq(bucket.name, "avatars")
  @debug.assert_eq(bucket.owner, "alice")

  let found = @storage.get_bucket(storage, "alice", bucket.id) catch {
    _ => @debug.crash("unexpected error")
  }
  @debug.assert_eq(found.name, "avatars")
}

test "public bucket download skips auth" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "public-files",
    public: Some(true),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("unexpected error: \{e}") }

  let obj = @storage.upload(
    storage, "alice", bucket.id, "hello.txt", b"hello",
    @json.Json::Object(Map([])),
  ) catch { e => @debug.crash("upload error: \{e}") }

  let (dl_obj, data) = @storage.download(storage, None, bucket.id, "hello.txt") catch {
    e => @debug.crash("download error: \{e}")
  }
  @debug.assert_eq(data, b"hello")
  @debug.assert_eq(dl_obj.name, "hello.txt")
}

test "private bucket download requires auth" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "private-files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("unexpected error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "secret.txt", b"secret",
    @json.Json::Object(Map([])),
  ) catch { e => @debug.crash("upload error: \{e}") }

  // bob should be denied
  let result = @storage.download(storage, Some("bob"), bucket.id, "secret.txt")
  match result {
    Err(e) => @debug.assert_true(e is @types.Forbidden)
    Ok(_) => @debug.crash("expected Forbidden error")
  }

  // alice should be allowed
  let (_, data) = @storage.download(storage, Some("alice"), bucket.id, "secret.txt") catch {
    e => @debug.crash("unexpected error: \{e}")
  }
  @debug.assert_eq(data, b"secret")
}

test "move object" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "old.txt", b"data",
    @json.Json::Object(Map([])),
  ) catch { e => @debug.crash("upload error: \{e}") }

  @storage.move_object(storage, "alice", bucket.id, "old.txt", "new.txt") catch {
    e => @debug.crash("move error: \{e}")
  }

  let (obj, _) = @storage.download(storage, Some("alice"), bucket.id, "new.txt") catch {
    _ => @debug.crash("not found after move")
  }
  @debug.assert_eq(obj.name, "new.txt")
}

test "copy object" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "original.txt", b"data",
    @json.Json::Object(Map([])),
  ) catch { e => @debug.crash("upload error: \{e}") }

  @storage.copy_object(storage, "alice", bucket.id, "original.txt", "copy.txt") catch {
    e => @debug.crash("copy error: \{e}")
  }

  let _ = @storage.download(storage, Some("alice"), bucket.id, "original.txt") catch {
    _ => @debug.crash("original not found")
  }
  let _ = @storage.download(storage, Some("alice"), bucket.id, "copy.txt") catch {
    _ => @debug.crash("copy not found")
  }
}

test "list objects with prefix" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "public/a.txt", b"a",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }
  let _ = @storage.upload(
    storage, "alice", bucket.id, "public/b.txt", b"b",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }
  let _ = @storage.upload(
    storage, "alice", bucket.id, "private/c.txt", b"c",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }

  let result = @storage.list_objects(
    storage, "alice", bucket.id, Some("public/"), None, None, None,
  ) catch { _ => @debug.crash("list error") }
  @debug.assert_eq(result.length(), 2)
}

test "delete single and batch objects" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "a.txt", b"a",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }
  let _ = @storage.upload(
    storage, "alice", bucket.id, "b.txt", b"b",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }

  @storage.delete_object(storage, "alice", bucket.id, "a.txt") catch {
    _ => @debug.crash("delete error")
  }

  let result = @storage.get_object_info(storage, Some("alice"), bucket.id, "a.txt")
  match result {
    Err(_) => ()
    Ok(_) => @debug.crash("expected not found")
  }

  @storage.delete_objects(storage, "alice", bucket.id, ["b.txt"]) catch {
    _ => @debug.crash("batch delete error")
  }

  let list = @storage.list_objects(storage, "alice", bucket.id, None, None, None, None) catch {
    _ => @debug.crash("list error")
  }
  @debug.assert_eq(list.length(), 0)
}

test "empty bucket" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(false),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "a.txt", b"a",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }
  let _ = @storage.upload(
    storage, "alice", bucket.id, "b.txt", b"b",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }

  @storage.empty_bucket(storage, "alice", bucket.id) catch {
    _ => @debug.crash("empty error")
  }

  let list = @storage.list_objects(storage, "alice", bucket.id, None, None, None, None) catch {
    _ => @debug.crash("list error")
  }
  @debug.assert_eq(list.length(), 0)
}

test "get object info" {
  let storage = @storage.new_test_storage()
  let bucket = @storage.create_bucket(storage, "alice", @storage.CreateBucketInput::{
    name: "files",
    public: Some(true),
    file_size_limit: None,
    allowed_mime_types: None,
  }) catch { e => @debug.crash("error: \{e}") }

  let _ = @storage.upload(
    storage, "alice", bucket.id, "info.txt", b"data",
    @json.Json::Object(Map([])),
  ) catch { _ => @debug.crash("err") }

  let obj = @storage.get_object_info(storage, None, bucket.id, "info.txt") catch {
    _ => @debug.crash("info error")
  }
  @debug.assert_eq(obj.name, "info.txt")
  @debug.assert_eq(obj.metadata.size, 4)
  @debug.assert_eq(obj.metadata.mimetype, "application/octet-stream")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/storage.mbt`**

```moonbit
// Storage service layer — business logic for bucket and object operations.
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
  pub user_metadata : @json.Json?
}

///|
/// Core storage state — holds repos, backend, and authorizer.
pub(all) struct Storage {
  pub backend : @storage_backend.StorageBackend
  pub bucket_repo : @bucket_repo.BucketRepo
  pub object_repo : @object_repo.ObjectRepo
  pub authorizer : @authorizer.Authorizer
}

///|
/// Create a Storage for testing with in-memory repos and backend.
pub fn new_test_storage() -> Storage {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = @entity_store.CompositeEntityStore::new(
    Box::new(mem as @evaluator.EntityStore),
    Box::new(pers as @evaluator.EntityStore),
  )
  let policies = @parser.parse_policies(
    "permit(principal,action,resource);",
  ) catch {
    _ => @parser.parse_policies("") catch { _ => @debug.crash("failed") }
  }
  Storage::{
    backend: @storage_backend.MemoryBackend::new() as @storage_backend.StorageBackend,
    bucket_repo: @bucket_repo.MemoryBucketRepo::new() as @bucket_repo.BucketRepo,
    object_repo: @object_repo.MemoryObjectRepo::new() as @object_repo.ObjectRepo,
    authorizer: @authorizer.Authorizer::new(entities, policies),
  }
}

///|
fn now_iso() -> String {
  @time.now().to_string()
}

///|
fn new_uuid() -> String {
  @x.uuid.new_v4().to_string()
}

///|
fn check_and_authorize(
  self : Storage,
  user : String?,
  action : String,
  resource_type : String,
  resource_id : String,
  overlay : Map[@ast.EntityUID, @ast.Entity]?,
) -> Unit!@types.StorageError {
  match user {
    None => raise @types.Forbidden("authentication required"),
    Some(u) => {
      if !self.authorizer.try_authorize(u, action, resource_type, resource_id, overlay) {
        raise @types.Forbidden("access denied")
      }
    }
  }
}

///|
fn is_public(self : Storage, bucket_id : String) -> Bool {
  match self.bucket_repo.get(bucket_id) {
    Some(b) => b.public
    None => false
  }
}

// ---------------------------------------------------------------------------
// Bucket operations
// ---------------------------------------------------------------------------

///|
pub fn create_bucket(
  self : Storage,
  user : String,
  input : CreateBucketInput,
) -> @types.Bucket!@types.StorageError {
  check_and_authorize(self, Some(user), "CreateBucket", "Application", "Storage", None)!
  let id = input.name // Use name as ID for simplicity
  if self.bucket_repo.get(id).is_some() {
    raise @types.AlreadyExists("bucket '\{id}' already exists")
  }
  let now = now_iso()
  let bucket = @types.Bucket::{
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
pub fn list_buckets(self : Storage, user : String) -> Array[@types.Bucket]!@types.StorageError {
  check_and_authorize(self, Some(user), "ListBuckets", "Application", "Storage", None)!
  self.bucket_repo.list()
}

///|
pub fn get_bucket(self : Storage, user : String, id : String) -> @types.Bucket!@types.StorageError {
  check_and_authorize(self, Some(user), "GetBucket", "Bucket", id, None)!
  match self.bucket_repo.get(id) {
    Some(b) => b
    None => raise @types.NotFound("bucket not found: \{id}")
  }
}

///|
pub fn update_bucket(
  self : Storage,
  user : String,
  id : String,
  input : UpdateBucketInput,
) -> @types.Bucket!@types.StorageError {
  check_and_authorize(self, Some(user), "UpdateBucket", "Bucket", id, None)!
  match self.bucket_repo.get(id) {
    Some(b) => {
      let updated_now = now_iso()
      let updated = @types.Bucket::{
        public: match input.public { Some(p) => p; None => b.public },
        file_size_limit: match input.file_size_limit {
          Some(l) => input.file_size_limit; None => b.file_size_limit
        },
        allowed_mime_types: match input.allowed_mime_types {
          Some(a) => input.allowed_mime_types; None => b.allowed_mime_types
        },
        updated_at: updated_now,
        ..b,
      }
      self.bucket_repo.update(id, updated)
      updated
    }
    None => raise @types.NotFound("bucket not found: \{id}")
  }
}

///|
pub fn delete_bucket(self : Storage, user : String, id : String) -> Unit!@types.StorageError {
  check_and_authorize(self, Some(user), "DeleteBucket", "Bucket", id, None)!
  let objects = self.object_repo.list(id, None, Some(1), None)
  if objects.length() > 0 {
    raise @types.NotEmpty("bucket '\{id}' is not empty")
  }
  self.bucket_repo.delete(id)
}

///|
pub fn empty_bucket(self : Storage, user : String, id : String) -> Unit!@types.StorageError {
  check_and_authorize(self, Some(user), "EmptyBucket", "Bucket", id, None)!
  let objects = self.object_repo.list(id, None, None, None)
  for obj in objects {
    self.backend.delete(id, obj.name) catch { _ => continue }
    self.object_repo.delete(id, obj.name)
  }
}

// ---------------------------------------------------------------------------
// Object operations
// ---------------------------------------------------------------------------

///|
pub fn upload(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
  data : Bytes,
  user_metadata : @json.Json,
) -> @types.Object!@types.StorageError {
  check_and_authorize(self, Some(user), "UploadObject", "Bucket", bucket_id, None)!
  match self.bucket_repo.get(bucket_id) {
    None => raise @types.NotFound("bucket not found: \{bucket_id}")
    Some(b) => {
      match b.allowed_mime_types {
        Some(types) => {
          if !types.contains(mimetype_from_data(data)) {
            raise @types.InvalidInput("mime type not allowed")
          }
        }
        None => ()
      }
      match b.file_size_limit {
        Some(limit) => if data.length().to_int64() > limit {
          raise @types.InvalidInput("file exceeds size limit")
        }
        None => ()
      }
    }
  }
  if self.object_repo.get(bucket_id, name).is_some() {
    raise @types.AlreadyExists("object '\{name}' already exists in '\{bucket_id}'")
  }
  self.backend.put(bucket_id, name, data)!
  let id = new_uuid()
  let now = now_iso()
  let obj = @types.Object::{
    id: Some(id),
    name,
    bucket_id,
    owner: user,
    owner_id: user,
    version: "1",
    metadata: @types.StorageMetadata::{
      size: data.length().to_int64(),
      mimetype: mimetype_from_data(data),
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
pub fn download(
  self : Storage,
  user : String?,
  bucket_id : String,
  name : String,
) -> (@types.Object, Bytes)!@types.StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      if self.is_public(bucket_id) {
        let data = self.backend.get(bucket_id, name)!
        return (obj, data)
      }
      check_and_authorize(
        self, user, "DownloadObject", "Object",
        match obj.id { Some(id) => id; None => bucket_id + "/" + name },
        None,
      )!
      let data = self.backend.get(bucket_id, name)!
      (obj, data)
    }
  }
}

///|
pub fn get_object_info(
  self : Storage,
  user : String?,
  bucket_id : String,
  name : String,
) -> @types.Object!@types.StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      if !self.is_public(bucket_id) {
        check_and_authorize(
          self, user, "GetObjectInfo", "Object",
          match obj.id { Some(id) => id; None => bucket_id + "/" + name },
          None,
        )!
      }
      obj
    }
  }
}

///|
pub fn update_object(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
  input : UpdateObjectInput,
) -> @types.Object!@types.StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      check_and_authorize(
        self, Some(user), "UpdateObject", "Object",
        match obj.id { Some(id) => id; None => bucket_id + "/" + name },
        None,
      )!
      let updated = @types.Object::{
        user_metadata: match input.user_metadata {
          Some(m) => m; None => obj.user_metadata
        },
        updated_at: Some(now_iso()),
        ..obj,
      }
      self.object_repo.insert(updated)
      updated
    }
  }
}

///|
pub fn list_objects(
  self : Storage,
  user : String,
  bucket_id : String,
  prefix : String?,
  limit : Int?,
  offset : Int?,
  sort_by : String?,
) -> Array[@types.Object]!@types.StorageError {
  check_and_authorize(self, Some(user), "ListObjects", "Bucket", bucket_id, None)!
  self.object_repo.list(bucket_id, prefix, limit, offset)
}

///|
pub fn move_object(
  self : Storage,
  user : String,
  bucket_id : String,
  from : String,
  to : String,
) -> Unit!@types.StorageError {
  match self.object_repo.get(bucket_id, from) {
    None => raise @types.NotFound("source not found: \{bucket_id}/\{from}")
    Some(obj) => {
      check_and_authorize(
        self, Some(user), "MoveObject", "Object",
        match obj.id { Some(id) => id; None => bucket_id + "/" + from },
        None,
      )!
      let data = self.backend.get(bucket_id, from)!
      self.backend.put(bucket_id, to, data)!
      self.backend.delete(bucket_id, from)!
      self.object_repo.delete(bucket_id, from)
      let moved = @types.Object::{ name: to, ..obj }
      self.object_repo.insert(moved)
    }
  }
}

///|
pub fn copy_object(
  self : Storage,
  user : String,
  bucket_id : String,
  from : String,
  to : String,
) -> Unit!@types.StorageError {
  match self.object_repo.get(bucket_id, from) {
    None => raise @types.NotFound("source not found: \{bucket_id}/\{from}")
    Some(obj) => {
      check_and_authorize(
        self, Some(user), "CopyObject", "Object",
        match obj.id { Some(id) => id; None => bucket_id + "/" + from },
        None,
      )!
      let data = self.backend.get(bucket_id, from)!
      self.backend.put(bucket_id, to, data)!
      let copy = @types.Object::{
        id: Some(new_uuid()),
        name: to,
        created_at: now_iso(),
        ..obj,
      }
      self.object_repo.insert(copy)
    }
  }
}

///|
pub fn delete_object(
  self : Storage,
  user : String,
  bucket_id : String,
  name : String,
) -> Unit!@types.StorageError {
  match self.object_repo.get(bucket_id, name) {
    None => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
    Some(obj) => {
      check_and_authorize(
        self, Some(user), "DeleteObject", "Object",
        match obj.id { Some(id) => id; None => bucket_id + "/" + name },
        None,
      )!
      self.backend.delete(bucket_id, name)!
      self.object_repo.delete(bucket_id, name)
    }
  }
}

///|
pub fn delete_objects(
  self : Storage,
  user : String,
  bucket_id : String,
  prefixes : Array[String],
) -> Unit!@types.StorageError {
  check_and_authorize(self, Some(user), "DeleteObject", "Bucket", bucket_id, None)!
  for name in prefixes {
    self.backend.delete(bucket_id, name) catch { _ => continue }
  }
  self.object_repo.delete_batch(bucket_id, prefixes)
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
/// Basic mime type detection from file extension or magic bytes.
fn mimetype_from_data(data : Bytes) -> String {
  if data.length() >= 4 {
    if data[0] == b'\x89' && data[1] == b'P' && data[2] == b'N' && data[3] == b'G' {
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
```

- [ ] **Step 4: Run tests — iterate on compilation issues**

Run `moon check` first, fix any compilation issues (trait conversions, syntax), then `moon test --package jaredzhou/store`.

Note: The test `private bucket download requires auth` uses a permissive Cedar policy (`permit(principal,action,resource)`) so the test checks bucket-level bypass, not the private policy. For actual policy enforcement, adjust the policy in `new_test_storage()` to be more restrictive.

- [ ] **Step 5: Commit**

```bash
git add store/storage.mbt store/storage_test.mbt
git commit -m "feat(store): add Storage service layer with bucket and object business logic"
```

---

### Task 10: Bucket Handlers — REST Endpoints

**Files:**
- Create: `store/handler/bucket.mbt`

**Interfaces:**
- Consumes: Task 9 (Storage service layer), pony types (`@pony.Router`, `@pony.Handler`, `@pony.HttpMethod`)
- Produces:
  - `pub fn build_bucket_routes(Router, Storage) -> Router`
  - Registers `POST /bucket/`, `GET /bucket/`, `GET /bucket/{bucketId}`, `PUT /bucket/{bucketId}`, `DELETE /bucket/{bucketId}`, `POST /bucket/{bucketId}/empty`

- [ ] **Step 1: Write bucket handler test**

Create `store/handler/bucket_test.mbt`:

```moonbit
test "bucket handler routes registered" {
  let storage = @storage.new_test_storage()
  let r = @pony.Router::Router()
  let _ = @handler.bucket.build_bucket_routes(r, storage)
  inspect(r, content=
    #|Static()
    #|  └── Static(/bucket)
    #|      ├── Static(/) Get(/bucket/)
    #|      ├── Static(/) Post(/bucket/)
    #|      ├── Param(bucketId,/)
    #|      │   ├── Static(/) Delete(/bucket/{bucketId}/)
    #|      │   ├── Static(/) Get(/bucket/{bucketId}/)
    #|      │   ├── Static(/) Put(/bucket/{bucketId}/)
    #|      │   └── Static(/empty) Post(/bucket/{bucketId}/empty)
  )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/handler/bucket.mbt`**

```moonbit
// Bucket REST handlers — create, list, get, update, delete, empty.

///|
struct CreateBucketBody {
  name : String
  public : Bool?
  file_size_limit : Int64?
  allowed_mime_types : Array[String]?
} derive(FromJson)

///|
struct UpdateBucketBody {
  public : Bool?
  file_size_limit : Int64?
  allowed_mime_types : Array[String]?
} derive(FromJson)

///|
/// Register all bucket-related routes on the router.
pub fn build_bucket_routes(router : @pony.Router, storage : @storage.Storage) -> @pony.Router {
  router.add(@pony.HttpMethod::Post, "/bucket/", create_bucket(storage)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Get, "/bucket/", list_buckets(storage)) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Get, "/bucket/{bucketId}", get_bucket(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Put, "/bucket/{bucketId}", update_bucket(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Delete, "/bucket/{bucketId}", delete_bucket(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Post, "/bucket/{bucketId}/empty", empty_bucket(storage),
  ) catch {
    _ => ()
  }
  router
}

///|
fn extract_user(ctx : @pony.Context) -> String!@types.StorageError {
  match ctx.header("X-User") {
    Some(u) => u
    None => raise @types.Forbidden("missing X-User header")
  }
}

///|
fn error_to_ctx(ctx : @pony.Context, e : @types.StorageError) -> Unit {
  ctx.reply_error(e.to_http_status(), match e {
    @types.NotFound(m) => m
    @types.AlreadyExists(m) => m
    @types.NotEmpty(m) => m
    @types.Forbidden(m) => m
    @types.InvalidInput(m) => m
    @types.BackendError(m) => m
    @types.RepoError(m) => m
  })
}

///|
/// POST /bucket/ — create a new bucket
fn create_bucket(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let body : CreateBucketBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.create_bucket(storage, user, @storage.CreateBucketInput::{
      name: body.name,
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) {
      Ok(bucket) => ctx.reply_ok(bucket)
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}

///|
/// GET /bucket/ — list all buckets
fn list_buckets(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    match @storage.list_buckets(storage, user) {
      Ok(buckets) => ctx.reply_ok(buckets)
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}

///|
/// GET /bucket/:bucketId — get a single bucket
fn get_bucket(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.reply_error(400, "missing bucketId"); return }
    }
    match @storage.get_bucket(storage, user, id) {
      Ok(bucket) => ctx.reply_ok(bucket)
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}

///|
/// PUT /bucket/:bucketId — update a bucket
fn update_bucket(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.reply_error(400, "missing bucketId"); return }
    }
    let body : UpdateBucketBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.update_bucket(storage, user, id, @storage.UpdateBucketInput::{
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) {
      Ok(bucket) => ctx.reply_ok(bucket)
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}

///|
/// DELETE /bucket/:bucketId — delete a bucket (must be empty)
fn delete_bucket(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.reply_error(400, "missing bucketId"); return }
    }
    match @storage.delete_bucket(storage, user, id) {
      Ok(_) => ctx.no_content()
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}

///|
/// POST /bucket/:bucketId/empty — delete all objects in a bucket
fn empty_bucket(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.reply_error(400, "missing bucketId"); return }
    }
    match @storage.empty_bucket(storage, user, id) {
      Ok(_) => ctx.no_content()
      Err(e) => error_to_ctx(ctx, e)
    }
  })
}
```

**Note:** The snapshot test's `inspect()` output depends on the exact radix tree structure from pony. The expected snapshot above is approximate — run `moon test --update` after implementing to generate the correct snapshot, then verify the test passes.

- [ ] **Step 4: Run tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: If snapshot mismatches, run `moon test --package jaredzhou/store --update` to update the snapshot. All tests pass including bucket handler route registration.

- [ ] **Step 5: Commit**

```bash
git add store/handler/bucket.mbt store/handler/bucket_test.mbt
git commit -m "feat(store): add bucket REST handlers — create, list, get, update, delete, empty"
```

---

### Task 11: Object Handlers — REST Endpoints

**Files:**
- Create: `store/handler/object.mbt`

**Interfaces:**
- Consumes: Task 9 (Storage service layer), Task 10 (handler helpers), pony types
- Produces:
  - `pub fn build_object_routes(Router, Storage) -> Router`
  - Registers all `/object/` endpoints: upload, download (auth/public), info (HEAD/GET), update, list, move, copy, delete, public-url

- [ ] **Step 1: Write object handler route registration test**

Create `store/handler/object_wbtest.mbt` (white-box):

```moonbit
test "object handler routes registered" {
  let storage = @storage.new_test_storage()
  let r = @pony.Router::Router()
  let _ = @handler.object.build_object_routes(r, storage)
  inspect(r, content=
    #|Static()
    #|  └── Static(/object)
    #|      ├── Static(/authenticated/) Param(bucketName,/*) Get(/object/authenticated/{bucketName}/*)
    #|      ├── Static(/copy) Post(/object/copy)
    #|      ├── Static(/info/)
    #|      │   ├── Static(/public/) Param(bucketName,/*)
    #|      │   │   ├── Get(/object/info/public/{bucketName}/*)
    #|      │   │   └── Head(/object/info/public/{bucketName}/*)
    #|      │   └── Param(bucketName,/*)
    #|      │       ├── Get(/object/info/{bucketName}/*)
    #|      │       └── Head(/object/info/{bucketName}/*)
    #|      ├── Static(/list/) Param(bucketName) Post(/object/list/{bucketName})
    #|      ├── Static(/move) Post(/object/move)
    #|      ├── Static(/public/) Param(bucketName,/*) Get(/object/public/{bucketName}/*)
    #|      └── Param(bucketName,/*)
    #|          ├── Delete(/object/{bucketName}/*)
    #|          ├── Post(/object/{bucketName}/*)
    #|          ├── Put(/object/{bucketName}/*)
    #|          └── Get(/object/{bucketName}/*)
    #|      └── Param(bucketName,) Delete(/object/{bucketName})
  )
}
```

**Note:** The snapshot is approximate — use `moon test --update` to capture the real tree structure.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — module not found

- [ ] **Step 3: Write `store/handler/object.mbt`**

```moonbit
// Object REST handlers — upload, download, info, update, list, move, copy, delete.

///|
struct MoveCopyBody {
  bucket_id : String
  source_key : String
  destination_key : String
} derive(FromJson)

///|
struct DeleteBatchBody {
  prefixes : Array[String]
} derive(FromJson)

///|
struct ListObjectsBody {
  prefix : String?
  limit : Int?
  offset : Int?
  sort_by : String?
} derive(FromJson)

///|
struct UpdateObjectBody {
  user_metadata : @json.Json?
} derive(FromJson)

///|
/// Register all object-related routes on the router.
pub fn build_object_routes(router : @pony.Router, storage : @storage.Storage) -> @pony.Router {
  // Upload
  router.add(
    @pony.HttpMethod::Post, "/object/{bucketName}/*", upload_object(storage),
  ) catch { _ => () }

  // Download — combined route (public check internal)
  router.add(
    @pony.HttpMethod::Get, "/object/{bucketName}/*", download_object(storage),
  ) catch { _ => () }

  // Download — authenticated only
  router.add(
    @pony.HttpMethod::Get,
    "/object/authenticated/{bucketName}/*",
    authenticated_download(storage),
  ) catch { _ => () }

  // Download — public (no auth)
  router.add(
    @pony.HttpMethod::Get,
    "/object/public/{bucketName}/*",
    public_download(storage),
  ) catch { _ => () }

  // Update object metadata
  router.add(
    @pony.HttpMethod::Put,
    "/object/{bucketName}/*",
    update_object(storage),
  ) catch { _ => () }

  // List objects
  router.add(
    @pony.HttpMethod::Post,
    "/object/list/{bucketName}",
    list_objects(storage),
  ) catch { _ => () }

  // Move
  router.add(@pony.HttpMethod::Post, "/object/move", move_object(storage)) catch {
    _ => ()
  }

  // Copy
  router.add(@pony.HttpMethod::Post, "/object/copy", copy_object(storage)) catch {
    _ => ()
  }

  // Delete single
  router.add(
    @pony.HttpMethod::Delete,
    "/object/{bucketName}/*",
    delete_object(storage),
  ) catch { _ => () }

  // Delete batch
  router.add(
    @pony.HttpMethod::Delete,
    "/object/{bucketName}",
    delete_objects(storage),
  ) catch { _ => () }

  // Info — authenticated HEAD
  router.add(
    @pony.HttpMethod::Head,
    "/object/info/{bucketName}/*",
    object_info_auth_download(storage),
  ) catch { _ => () }

  // Info — authenticated GET
  router.add(
    @pony.HttpMethod::Get,
    "/object/info/{bucketName}/*",
    object_info_auth_download(storage),
  ) catch { _ => () }

  // Info — public HEAD
  router.add(
    @pony.HttpMethod::Head,
    "/object/info/public/{bucketName}/*",
    object_info_public_download(storage),
  ) catch { _ => () }

  // Info — public GET
  router.add(
    @pony.HttpMethod::Get,
    "/object/info/public/{bucketName}/*",
    object_info_public_download(storage),
  ) catch { _ => () }

  router
}

///|
fn extract_bucket_name(ctx : @pony.Context) -> String {
  match ctx.param("bucketName") {
    Some(n) => n
    None => "unknown"
  }
}

///|
fn extract_path(ctx : @pony.Context) -> String {
  match ctx.wildcard() {
    Some(p) => p
    None => ""
  }
}

///|
fn extract_user_opt(ctx : @pony.Context) -> String? {
  ctx.header("X-User")
}

// ---------------------------------------------------------------------------
// Object handlers
// ---------------------------------------------------------------------------

///|
/// POST /object/:bucketName/* — upload a file
fn upload_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user_opt(ctx)
    let user = match user {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    if name == "" {
      ctx.reply_error(400, "missing object path")
      return
    }
    // Read request body as bytes
    let body = ctx.body()
    let data = body.to_bytes()
    match @storage.upload(storage, user, bucket_name, name, data, @json.Json::Object(Map([]))) {
      Ok(obj) => ctx.reply_ok(obj)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        @types.AlreadyExists(m) => m
        @types.InvalidInput(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// GET /object/:bucketName/* — download (combined public+auth)
fn download_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = extract_user_opt(ctx)
    match @storage.download(storage, user, bucket_name, name) {
      Ok((_, data)) => ctx.write_bytes(200, data)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// GET /object/authenticated/:bucketName/* — download (always requires auth)
fn authenticated_download(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    match @storage.download(storage, Some(user), bucket_name, name) {
      Ok((_, data)) => ctx.write_bytes(200, data)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// GET /object/public/:bucketName/* — public download (no auth)
fn public_download(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    match @storage.download(storage, None, bucket_name, name) {
      Ok((_, data)) => ctx.write_bytes(200, data)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// PUT /object/:bucketName/* — update object metadata
fn update_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let body : UpdateObjectBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.update_object(storage, user, bucket_name, name, @storage.UpdateObjectInput::{
      user_metadata: body.user_metadata,
    }) {
      Ok(obj) => ctx.reply_ok(obj)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// POST /object/list/:bucketName — list objects
fn list_objects(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let body : ListObjectsBody = ctx.json() catch {
      _ => ListObjectsBody::{
        prefix: None, limit: None, offset: None, sort_by: None,
      }
    }
    match @storage.list_objects(storage, user, bucket_name, body.prefix, body.limit, body.offset, body.sort_by) {
      Ok(objs) => ctx.reply_ok(objs)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// POST /object/move — move an object
fn move_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let body : MoveCopyBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.move_object(storage, user, body.bucket_id, body.source_key, body.destination_key) {
      Ok(_) => ctx.no_content()
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// POST /object/copy — copy an object
fn copy_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let body : MoveCopyBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.copy_object(storage, user, body.bucket_id, body.source_key, body.destination_key) {
      Ok(_) => ctx.no_content()
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// DELETE /object/:bucketName/* — delete a single object
fn delete_object(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    match @storage.delete_object(storage, user, bucket_name, name) {
      Ok(_) => ctx.no_content()
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// DELETE /object/:bucketName — batch delete objects
fn delete_objects(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    let body : DeleteBatchBody = ctx.json() catch {
      _ => { ctx.reply_error(400, "invalid JSON body"); return }
    }
    match @storage.delete_objects(storage, user, bucket_name, body.prefixes) {
      Ok(_) => ctx.no_content()
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// GET/HEAD /object/info/:bucketName/* — authenticated object metadata
fn object_info_auth_download(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => { ctx.reply_error(401, "missing X-User header"); return }
    }
    match @storage.get_object_info(storage, Some(user), bucket_name, name) {
      Ok(obj) => ctx.reply_ok(obj)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.Forbidden(m) => m
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}

///|
/// GET/HEAD /object/info/public/:bucketName/* — public object metadata
fn object_info_public_download(storage : @storage.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    match @storage.get_object_info(storage, None, bucket_name, name) {
      Ok(obj) => ctx.reply_ok(obj)
      Err(e) => ctx.reply_error(e.to_http_status(), match e {
        @types.NotFound(m) => m
        _ => "internal error"
      })
    }
  })
}
```

**Note:** The upload handler reads the request body as bytes. The exact API to read the raw body from pony's `Context` depends on the available methods. If `ctx.body()` is not available, alternatives include `ctx.read()` or accessing the raw `@http.Request` from the context. Check `pony/pkg.generated.mbti` for the available body-reading methods. If the body is streaming, accumulate it into a `Bytes` buffer. Also, `ctx.write_bytes(200, data)` is used for binary responses — verify this method exists in pony. If not, use `ctx.reply_ok()` with a base64-encoded data response or check for alternative binary write methods.

- [ ] **Step 4: Run tests — iterate on compilation issues**

Run: `cd /home/jared/projects/moonbase && moon check`
Check for compilation errors, especially around:
- `ctx.body()` — may need a different method to read request body bytes
- `ctx.write_bytes()` — verify pony supports binary response writing
- `ctx.reply_ok()` on types that need `ToJson` derive
- `derive(FromJson)` on request body structs

Fix any compilation issues, then run `moon test --package jaredzhou/store --update` to capture the snapshot.

- [ ] **Step 5: Commit**

```bash
git add store/handler/object.mbt store/handler/object_wbtest.mbt
git commit -m "feat(store): add object REST handlers — upload, download, info, update, list, move, copy, delete"
```

---

### Task 12: Integration Tests — Full HTTP Server

**Files:**
- Create: `store/store_test.mbt`
- Create: `store/main.mbt` (temporary server entry point for testing)

**Interfaces:**
- Consumes: All prior tasks
- Produces: Integration tests covering all REST endpoints end-to-end

- [ ] **Step 1: Write integration test**

Create `store/store_test.mbt`:

```moonbit
async test "integration: create and list buckets via HTTP" {
  @async.with_task_group() <| group => {
    let port = 19880
    let storage = @storage.new_test_storage()
    let r = @pony.Router::Router()
    let _ = @handler.bucket.build_bucket_routes(r, storage)
    let _ = @handler.object.build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Create bucket
    let (resp, body) = @http.post(
      "http://127.0.0.1:\{port}/bucket/",
      headers=[("X-User", "alice"), ("Content-Type", "application/json")],
      body=#|{"name":"test-bucket","public":false}",
    )
    @debug.assert_eq(resp.code, 200)

    // List buckets
    let (resp2, body2) = @http.get(
      "http://127.0.0.1:\{port}/bucket/",
      headers=[("X-User", "alice")],
    )
    @debug.assert_eq(resp2.code, 200)

    // Get bucket
    let (resp3, body3) = @http.get(
      "http://127.0.0.1:\{port}/bucket/test-bucket",
      headers=[("X-User", "alice")],
    )
    @debug.assert_eq(resp3.code, 200)
  }
}

async test "integration: upload and download object" {
  @async.with_task_group() <| group => {
    let port = 19881
    let storage = @storage.new_test_storage()
    let r = @pony.Router::Router()
    let _ = @handler.bucket.build_bucket_routes(r, storage)
    let _ = @handler.object.build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Create a public bucket
    let (resp, _) = @http.post(
      "http://127.0.0.1:\{port}/bucket/",
      headers=[("X-User", "alice"), ("Content-Type", "application/json")],
      body=#|{"name":"public-bucket","public":true}",
    )
    @debug.assert_eq(resp.code, 200)

    // Upload — POST /object/:bucketName/*
    let (resp2, _) = @http.post(
      "http://127.0.0.1:\{port}/object/public-bucket/hello.txt",
      headers=[("X-User", "alice"), ("Content-Type", "text/plain")],
      body="hello world",
    )
    @debug.assert_eq(resp2.code, 200)

    // Download — GET /object/public/:bucketName/*
    let (resp3, body3) = @http.get(
      "http://127.0.0.1:\{port}/object/public/public-bucket/hello.txt",
    )
    @debug.assert_eq(resp3.code, 200)
  }
}

async test "integration: move and delete object" {
  @async.with_task_group() <| group => {
    let port = 19882
    let storage = @storage.new_test_storage()
    let r = @pony.Router::Router()
    let _ = @handler.bucket.build_bucket_routes(r, storage)
    let _ = @handler.object.build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Create bucket
    let (resp, _) = @http.post(
      "http://127.0.0.1:\{port}/bucket/",
      headers=[("X-User", "alice"), ("Content-Type", "application/json")],
      body=#|{"name":"ops","public":false}",
    )
    @debug.assert_eq(resp.code, 200)

    // Upload
    let (resp2, _) = @http.post(
      "http://127.0.0.1:\{port}/object/ops/old.txt",
      headers=[("X-User", "alice"), ("Content-Type", "text/plain")],
      body="test data",
    )
    @debug.assert_eq(resp2.code, 200)

    // Move
    let (resp3, _) = @http.post(
      "http://127.0.0.1:\{port}/object/move",
      headers=[("X-User", "alice"), ("Content-Type", "application/json")],
      body=#|{"bucketId":"ops","sourceKey":"old.txt","destinationKey":"new.txt"}",
    )
    @debug.assert_eq(resp3.code, 204)

    // Delete
    let (resp4, _) = @http.delete(
      "http://127.0.0.1:\{port}/object/ops/new.txt",
      headers=[("X-User", "alice")],
    )
    @debug.assert_eq(resp4.code, 204)
  }
}
```

- [ ] **Step 2: Run integration tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Integration tests pass or reveal issues with pony's HTTP client/server interaction. If tests fail due to request body handling or response serialization, iterate on the handler code.

Common issues to watch for:
- POST body format for `/object/:bucketName/*` — may need multipart form data instead of raw bytes
- `ctx.json()` for `POST /object/list/:bucketName` — body is JSON
- DELETE endpoint parameter extraction

- [ ] **Step 3: Commit**

```bash
git add store/store_test.mbt
git commit -m "test(store): add integration tests for REST endpoints"
```

---

### Task 13: LocalFS Backend

**Files:**
- Create: `store/backend/local_fs.mbt`

**Interfaces:**
- Consumes: Task 3 (StorageBackend trait), `moonbitlang/x/fs`
- Produces: `pub fn new_local_fs_backend(base_path: String) -> StorageBackend`

- [ ] **Step 1: Write LocalFS test**

Create `store/backend/local_fs_wbtest.mbt`:

```moonbit
test "LocalFS backend put and get" {
  let base = @fs.temp_dir()??
  let backend = @backend.local_fs.new(base)
  @storage_backend.put(backend, "test-bucket", "data.txt", b"hello fs") catch {
    e => @debug.crash("put failed: \{e}")
  }
  @debug.assert_true(@storage_backend.exists(backend, "test-bucket", "data.txt"))
  let data = @storage_backend.get(backend, "test-bucket", "data.txt") catch {
    e => @debug.crash("get failed: \{e}")
  }
  @debug.assert_eq(data, b"hello fs")
}

test "LocalFS backend delete" {
  let base = @fs.temp_dir()??
  let backend = @backend.local_fs.new(base)
  @storage_backend.put(backend, "test", "tmp.txt", b"x") catch {
    _ => @debug.crash("put failed")
  }
  @storage_backend.delete(backend, "test", "tmp.txt") catch {
    _ => @debug.crash("delete failed")
  }
  @debug.assert_false(@storage_backend.exists(backend, "test", "tmp.txt"))
}

test "LocalFS backend nested path" {
  let base = @fs.temp_dir()??
  let backend = @backend.local_fs.new(base)
  @storage_backend.put(backend, "avatars", "public/img.png", b"png data") catch {
    e => @debug.crash("put failed: \{e}")
  }
  let data = @storage_backend.get(backend, "avatars", "public/img.png") catch {
    e => @debug.crash("get failed: \{e}")
  }
  @debug.assert_eq(data, b"png data")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: Compile error — `@backend.local_fs` module not found

- [ ] **Step 3: Write `store/backend/local_fs.mbt`**

```moonbit
// LocalFS StorageBackend — stores files on the local filesystem.

///|
/// Create a new LocalFS backend rooted at the given directory.
/// The directory and any subdirectories are created as needed.
pub fn new(base_path : String) -> @storage_backend.StorageBackend {
  LocalFSBackend::{ base_path } as @storage_backend.StorageBackend
}

///|
struct LocalFSBackend {
  base_path : String
}

///|
fn full_path(self : LocalFSBackend, bucket_id : String, name : String) -> String {
  self.base_path + "/" + bucket_id + "/" + name
}

///|
pub impl @storage_backend.StorageBackend for LocalFSBackend with fn put(
  self : LocalFSBackend,
  bucket_id : String,
  name : String,
  data : Bytes,
) -> Unit!@types.StorageError {
  let path = full_path(self, bucket_id, name)
  // Ensure parent directory exists
  let dir = parent_dir(path)
  @fs.create_dir_all(dir) catch {
    _ => raise @types.BackendError("failed to create directory: \{dir}")
  }
  @fs.write(path, data) catch {
    _ => raise @types.BackendError("failed to write: \{path}")
  }
}

///|
pub impl @storage_backend.StorageBackend for LocalFSBackend with fn get(
  self : LocalFSBackend,
  bucket_id : String,
  name : String,
) -> Bytes!@types.StorageError {
  let path = full_path(self, bucket_id, name)
  @fs.read(path) catch {
    _ => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl @storage_backend.StorageBackend for LocalFSBackend with fn delete(
  self : LocalFSBackend,
  bucket_id : String,
  name : String,
) -> Unit!@types.StorageError {
  let path = full_path(self, bucket_id, name)
  @fs.remove_file(path) catch {
    _ => raise @types.NotFound("object not found: \{bucket_id}/\{name}")
  }
}

///|
pub impl @storage_backend.StorageBackend for LocalFSBackend with fn exists(
  self : LocalFSBackend,
  bucket_id : String,
  name : String,
) -> Bool {
  let path = full_path(self, bucket_id, name)
  match @fs.metadata(path) {
    Ok(_) => true
    Err(_) => false
  }
}

///|
fn parent_dir(path : String) -> String {
  let idx = path.last_slash_index()
  match idx {
    Some(i) => path.substring(start=0, end=i)
    None => "."
  }
}
```

**Note:** The `moonbitlang/x/fs` module API may differ from what's shown. Check the actual module at `.mooncakes/moonbitlang/x/fs/` for the exact function signatures (`create_dir_all`, `write`, `read`, `remove_file`, `metadata`, `temp_dir`). Adjust function names and parameters to match.

- [ ] **Step 4: Run LocalFS tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: 3 LocalFS tests pass

- [ ] **Step 5: Commit**

```bash
git add store/backend/local_fs.mbt store/backend/local_fs_wbtest.mbt
git commit -m "feat(store): add LocalFS StorageBackend implementation"
```

---

### Task 14: Wire Everything Together — Final Verification

**Files:**
- Modify: `store/store.mbt` (add `new` constructor that takes backend, repos, authorizer)

**Interfaces:**
- Consumes: All prior tasks
- Produces: Fully functional module, all tests pass

- [ ] **Step 1: Add `Storage::new` constructor**

Add to `store/storage.mbt`:

```moonbit
///|
/// Create a full Storage instance with the given backend, repos, and authorizer.
pub fn Storage::new(
  backend : @storage_backend.StorageBackend,
  bucket_repo : @bucket_repo.BucketRepo,
  object_repo : @object_repo.ObjectRepo,
  authorizer : @authorizer.Authorizer,
) -> Storage {
  Storage::{ backend, bucket_repo, object_repo, authorizer }
}
```

- [ ] **Step 2: Run all tests**

Run: `cd /home/jared/projects/moonbase && moon test --package jaredzhou/store`
Expected: All tests pass

- [ ] **Step 3: Run workspace-wide tests**

Run: `cd /home/jared/projects/moonbase && moon test --all`
Expected: All existing tests still pass (no regressions)

- [ ] **Step 4: Commit**

```bash
git add store/storage.mbt
git commit -m "feat(store): add Storage::new constructor for full initialization"
```

---

## Implementation Notes

### Pony API Dependencies

The object handler code assumes these pony APIs exist. Verify before implementation:
- `ctx.body()` — reading raw request body bytes (check `pony/pkg.generated.mbti` for alternative: `ctx.read_bytes()` or accessing the underlying request)
- `ctx.write_bytes(status, data)` — writing binary responses (may need `ctx.set_header("Content-Type", "...")` before writing)
- `ctx.no_content()` — 204 response
- `ctx.reply_ok(value)` — JSON serialization via `ToJson`
- `ctx.reply_error(code, msg)` — error response
- `ctx.json<T>()` — JSON deserialization for typed request bodies
- `ctx.param(name)` — path parameter extraction
- `ctx.wildcard()` — wildcard path extraction
- `ctx.header(name)` — request header extraction

### Type Trait Conversions

MoonBit trait-to-concrete-type casting may require explicit syntax:
- `MemoryBackend as StorageBackend`
- `MemoryBucketRepo as BucketRepo`
- `MemoryObjectRepo as ObjectRepo`
- `MapEntityStore as EntityStore`

### Test Policy

The service layer tests use `permit(principal,action,resource)` as the test policy — everything is allowed. This simplifies service logic testing without needing to set up complex Cedar policies. Integration tests may need more realistic policies to test authorization failures.

### moondoc Verification

After all tasks: `moon doc --serve` to verify the documentation looks correct.
