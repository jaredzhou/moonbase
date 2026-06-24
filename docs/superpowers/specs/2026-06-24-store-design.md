# Store — Lightweight Object Storage Service

## Overview

`store` is a lightweight object storage module for moonbase, modeled after Supabase Storage. It provides bucket management, file upload/download, and fine-grained access control via Cedar authorization. The module exposes a REST API via pony and is designed to be composable with future unified auth and a form engine for file/image field support.

## Scope (v1)

### In scope
- **Bucket CRUD:** create, list, get, update, delete, empty
- **Object CRUD:** upload, download, get info, list (prefix/limit/offset), move, copy, update, delete (single + batch)
- **Public buckets:** fast-path access for `DownloadObject` and `ListObjects` on `public: true` buckets
- **REST API aligned with Supabase Storage** — `/bucket` and `/object` as top-level prefixes
- **Cedar authorization:** per-operation policy checks via mooncedar, with per-request entity overlays
- **Pluggable backends:** `StorageBackend` trait for file storage, `BucketRepo` / `ObjectRepo` traits for metadata persistence
- **Service layer:** `Storage` struct encapsulates business logic; handlers are thin wrappers

### Out of scope (v2+)
- Signed URLs (`createSignedUrl`, `createSignedUploadUrl`)
- Image transformation (resize, compress, convert)
- TUS resumable upload protocol
- S3-compatible API
- CDN integration

## Module Structure

```
store/
  moon.mod               # jaredzhou/store
  moon.pkg               # root re-exports, public API
  types.mbt              # Bucket, Object, StorageMetadata, StorageError
  storage_backend.mbt    # StorageBackend trait
  bucket_repo.mbt        # BucketRepo trait + MemoryBucketRepo impl
  object_repo.mbt        # ObjectRepo trait + MemoryObjectRepo impl
  entity_store.mbt       # CompositeEntityStore, RequestEntityStore
  authorizer.mbt         # Authorizer struct (Cedar wrapper)
  storage.mbt            # Storage service layer (business logic)
  handler/
    moon.pkg
    bucket.mbt           # bucket CRUD handlers
    object.mbt           # object CRUD handlers
  backend/
    moon.pkg
    local_fs.mbt         # LocalFS StorageBackend impl
  store_test.mbt         # integration tests (HTTP server)
  handler/
    bucket_wbtest.mbt
    object_wbtest.mbt
  backend/
    local_fs_wbtest.mbt
```

### Dependencies (`moon.mod`)

```toml
name = "jaredzhou/store"
version = "0.1.0"
preferred_target = "native"
import {
  "jaredzhou/pony@0.1.1",
  "jaredzhou/mooncedar@0.1.1",
  "moonbitlang/async@0.19.4",
  "moonbitlang/x@0.4.45",
}
```

## Data Model

### Bucket

```moonbit
pub struct Bucket {
  id: String                    // unique identifier (slug, e.g. "avatars")
  name: String                  // display name
  owner: String                 // owner display name (required)
  owner_id: String              // owner UUID (required, for Cedar policies)
  public: Bool                  // fast-path public access
  file_size_limit: Int64?       // max file size in bytes, null = unlimited
  allowed_mime_types: Array[String]?  // null = allow all
  created_at: String            // ISO 8601
  updated_at: String            // ISO 8601
}
```

### StorageMetadata

```moonbit
pub struct StorageMetadata {
  size: Int64                   // file size in bytes (required)
  mimetype: String              // content type, e.g. "image/png" (required)
  cache_control: String?        // optional CDN/cache hint
}
```

### Object

```moonbit
pub struct Object {
  id: String?                   // UUID, auto-generated on upload
  name: String                  // path within bucket, e.g. "public/avatar.png" (required)
  bucket_id: String             // parent bucket id
  owner: String                 // owner display name (required)
  owner_id: String              // owner UUID (required, for Cedar policies)
  version: String               // object version (required)
  metadata: StorageMetadata     // typed system metadata (required)
  user_metadata: @json.Json     // user-defined metadata, default {} (required)
  created_at: String            // ISO 8601
  updated_at: String?           // ISO 8601
  last_accessed_at: String?     // ISO 8601
}
```

### Entity Conversion (Cedar)

All Bucket and Object structs have corresponding Cedar entity representations used for authorization.

**Bucket entities:**
- Type: `Bucket`
- Attributes: `owner: String`, `owner_id: String`, `public: Bool`

**Object entities:**
- Type: `Object`
- Attributes: `bucket_id: String`, `owner: String`, `owner_id: String`, `name: String`, `size: Int64`, `mimetype: String`, `folder: String`

The `folder` attribute is derived from `name` (e.g. `name = "public/avatar.png"` → `folder = "public"`), enabling folder-level Cedar policies.

## Repo Traits

### BucketRepo

```moonbit
pub(open) trait BucketRepo {
  get(id: String) -> Bucket?
  list() -> Array[Bucket]
  insert(bucket: Bucket) -> Unit
  update(id: String, bucket: Bucket) -> Unit
  delete(id: String) -> Unit
}
```

### ObjectRepo

```moonbit
pub(open) trait ObjectRepo {
  get(bucket_id: String, name: String) -> Object?
  list(bucket_id: String, prefix: String?, limit: Int?, offset: Int?) -> Array[Object]
  insert(obj: Object) -> Unit
  delete(bucket_id: String, name: String) -> Unit
  delete_batch(bucket_id: String, names: Array[String]) -> Unit
}
```

### StorageBackend

```moonbit
pub(open) trait StorageBackend {
  put(bucket_id: String, name: String, data: Bytes) -> Unit!StorageError
  get(bucket_id: String, name: String) -> Bytes!StorageError
  delete(bucket_id: String, name: String) -> Unit!StorageError
  exists(bucket_id: String, name: String) -> Bool
}
```

### Testing Implementations

```moonbit
pub struct MemoryBucketRepo { buckets: Map[String, Bucket] }  // impl BucketRepo
pub struct MemoryObjectRepo { objects: Map[String, Object] }  // impl ObjectRepo
pub struct MemoryBackend { files: Map[String, Bytes] }  // impl StorageBackend
```

## Entity Store Architecture

### CompositeEntityStore

A shared, layered entity store combining an in-memory cache with a persisted backend. Used across all requests.

```moonbit
pub struct CompositeEntityStore {
  memory: Box[EntityStore]       // concurrency-safe in-memory cache
  persisted: Box[EntityStore]    // Postgres-backed (or other persisted store)
}

impl EntityStore for CompositeEntityStore {
  get_entity(self, euid: EntityUID) -> Entity? {
    self.memory.get_entity(euid).or(self.persisted.get_entity(euid))
  }
}
```

Concurrency: `memory` handles its own concurrency safety internally. `persisted` (Postgres) is inherently safe for concurrent reads. `CompositeEntityStore` itself is read-only during authorizations — entity mutations go through the service layer, which updates both layers atomically.

### RequestEntityStore

A per-request entity store wrapping a `CompositeEntityStore` with a transient overlay. Created fresh for each request, dropped when the request completes.

```moonbit
pub struct RequestEntityStore {
  overlay: Map[EntityUID, Entity]   // request-scoped, single-threaded
  backing: Box[EntityStore]        // CompositeEntityStore
}

impl EntityStore for RequestEntityStore {
  get_entity(self, euid: EntityUID) -> Entity? {
    self.overlay.get(euid).or(self.backing.get_entity(euid))
  }
}

pub fn RequestEntityStore::add_entity(self, euid: EntityUID, entity: Entity) -> Unit {
  self.overlay.set(euid, entity)
}
```

Concurrency: `overlay` is single-request, no contention. `backing` is shared but read-only during authorization. Safe by construction.

## Authorizer

```moonbit
pub struct Authorizer {
  entities: CompositeEntityStore
  policies: Array[@mooncedar.Policy]
}

pub fn Authorizer::try_authorize(
  self,
  user: String,                // principal from X-User header
  action: String,              // Cedar action name
  resource_type: String,       // "Application", "Bucket", or "Object"
  resource_id: String,         // entity id
  overlay: Map[EntityUID, Entity]?  // optional per-request transient entities
) -> Bool
```

Internally, `try_authorize` creates a `RequestEntityStore` wrapping `self.entities` with the optional overlay, then calls `@mooncedar.is_authorized`.

## Cedar Authorization Model

### Entity Types

| Entity | Attributes |
|--------|-----------|
| `Application::"Storage"` | (none) |
| `Bucket::"{id}"` | `owner`, `owner_id`, `public` |
| `Object::"{id}"` | `bucket_id`, `owner`, `owner_id`, `name`, `size`, `mimetype`, `folder` |

### Actions

| Operation | Cedar Action |
|-----------|-------------|
| Create bucket | `CreateBucket` |
| Get bucket | `GetBucket` |
| List buckets | `ListBuckets` |
| Update bucket | `UpdateBucket` |
| Delete bucket | `DeleteBucket` |
| Empty bucket | `EmptyBucket` |
| Upload object | `UploadObject` |
| Download object | `DownloadObject` |
| Get object info | `GetObjectInfo` |
| List objects | `ListObjects` |
| Move object | `MoveObject` |
| Copy object | `CopyObject` |
| Update object | `UpdateObject` |
| Delete object | `DeleteObject` |

### Public Bucket Fast Path

Buckets with `public: true` skip Cedar evaluation for `DownloadObject` and `ListObjects`. All other operations (upload, move, copy, delete) still require authorization even on public buckets.

### Example Policies

```
// Anyone can create buckets
permit(principal, action == Action::"CreateBucket", resource == Application::"Storage");

// Bucket owner has full control over their bucket
permit(principal, action, resource)
when { resource.owner_id == principal };

// Anyone can read from public buckets
permit(principal, action in [Action::"DownloadObject", Action::"ListObjects"], resource)
when { resource in Bucket && resource.public == true };
```

## Storage Service Layer

`Storage` is the business logic layer. Handlers are thin wrappers that extract from `Context` and delegate to `Storage`.

```moonbit
pub struct Storage {
  backend: StorageBackend
  bucket_repo: BucketRepo
  object_repo: ObjectRepo
  authorizer: Authorizer
}
```

### Public API

```moonbit
// Bucket operations (all require authorization)
pub fn Storage::create_bucket(self, user: String, input: CreateBucketInput) -> Bucket!StorageError
pub fn Storage::list_buckets(self, user: String) -> Array[Bucket]!StorageError
pub fn Storage::get_bucket(self, user: String, id: String) -> Bucket!StorageError
pub fn Storage::update_bucket(self, user: String, id: String, input: UpdateBucketInput) -> Bucket!StorageError
pub fn Storage::delete_bucket(self, user: String, id: String) -> Unit!StorageError
pub fn Storage::empty_bucket(self, user: String, id: String) -> Unit!StorageError

// Object operations
pub fn Storage::upload(self, user: String, bucket_id: String, name: String, data: Bytes, user_metadata: @json.Json) -> Object!StorageError
pub fn Storage::download(self, user: String?, bucket_id: String, name: String) -> (Object, Bytes)!StorageError  // user=None for public
pub fn Storage::get_object_info(self, user: String?, bucket_id: String, name: String) -> Object!StorageError
pub fn Storage::update_object(self, user: String, bucket_id: String, name: String, input: UpdateObjectInput) -> Object!StorageError
pub fn Storage::list_objects(self, user: String, bucket_id: String, prefix: String?, limit: Int?, offset: Int?, sort_by: String?) -> Array[Object]!StorageError
pub fn Storage::move_object(self, user: String, bucket_id: String, from: String, to: String) -> Unit!StorageError
pub fn Storage::copy_object(self, user: String, bucket_id: String, from: String, to: String) -> Unit!StorageError
pub fn Storage::delete_object(self, user: String, bucket_id: String, name: String) -> Unit!StorageError
pub fn Storage::delete_objects(self, user: String, bucket_id: String, prefixes: Array[String]) -> Unit!StorageError
```

### Internal Flow (download example)

1. Handler extracts `user` (optional), `bucket_id` (from `bucketName` param), `name` (from wildcard `*`) from pony Context
2. Handler calls `storage.download(user, bucket_id, name)`
3. `download` checks bucket `public` flag:
   - If public: fetches from backend directly (no auth needed; `user` may be `None`)
   - If private: validates `user` is present, builds request overlay with object entity, calls `authorizer.try_authorize`
4. If authorized: fetches bytes from `backend.get(bucket_id, name)`
5. Returns `(Object, Bytes)` or `StorageError`

## REST API

Aligned with the Supabase Storage API structure. Auth is via `X-User` header (same pattern as TinyTodo).

### Bucket Routes (prefix: `/bucket`)

| Method | Path | Auth | Body / Notes |
|--------|------|------|-------------|
| `POST` | `/bucket/` | Required | `{name, public?, file_size_limit?, allowed_mime_types?}` |
| `GET` | `/bucket/` | Required | Returns `Array[Bucket]` |
| `GET` | `/bucket/{bucketId}` | Required | Returns single `Bucket` |
| `PUT` | `/bucket/{bucketId}` | Required | Full update `{name, public?, file_size_limit?, allowed_mime_types?}` |
| `DELETE` | `/bucket/{bucketId}` | Required | Bucket must be empty |
| `POST` | `/bucket/{bucketId}/empty` | Required | Delete all objects in bucket |

### Object Routes (prefix: `/object`)

| Method | Path | Auth | Body / Notes |
|--------|------|------|-------------|
| `POST` | `/object/{bucketName}/*` | Required | Multipart form upload |
| `GET` | `/object/{bucketName}/*` | Public-aware | Download (public buckets skip auth) |
| `GET` | `/object/authenticated/{bucketName}/*` | Required | Download (always requires auth) |
| `PUT` | `/object/{bucketName}/*` | Required | Update object metadata |
| `POST` | `/object/list/{bucketName}` | Required | Body: `{prefix?, limit?, offset?, sortBy?}` |
| `POST` | `/object/move` | Required | Body: `{bucketId, sourceKey, destinationKey}` |
| `POST` | `/object/copy` | Required | Body: `{bucketId, sourceKey, destinationKey}` |
| `DELETE` | `/object/{bucketName}/*` | Required | Delete single object |
| `DELETE` | `/object/{bucketName}` | Required | Batch delete. Body: `{prefixes: ["path1", "path2"]}` |
| `GET` | `/object/public/{bucketName}/*` | None | Public download (fast path) |
| `HEAD` | `/object/info/{bucketName}/*` | Required | Object metadata (HEAD) |
| `GET` | `/object/info/{bucketName}/*` | Required | Object metadata (GET) |
| `HEAD` | `/object/info/public/{bucketName}/*` | None | Public object metadata (HEAD) |
| `GET` | `/object/info/public/{bucketName}/*` | None | Public object metadata (GET) |

**Download routing note:** `GET /object/{bucketName}/*` acts as a combined endpoint — it checks bucket publicity internally and skips auth for public buckets. `GET /object/authenticated/{bucketName}/*` always requires auth for callers who want to enforce it explicitly. `GET /object/public/{bucketName}/*` is the unauthenticated fast path.

## Error Handling

```moonbit
pub enum StorageError {
  NotFound(String)                // bucket or object not found
  AlreadyExists(String)           // bucket name or object path conflict
  NotEmpty(String)                // attempt to delete non-empty bucket
  Forbidden(String)               // Cedar authorization denied
  BackendError(String)            // StorageBackend failure (disk full, I/O error, etc.)
  RepoError(String)               // metadata repo failure
  InvalidInput(String)            // bad name, empty file, oversized, disallowed mime type
}
```

HTTP status mapping (in handler layer):
- `NotFound` → 404
- `AlreadyExists` → 409
- `NotEmpty` → 409
- `Forbidden` → 403
- `InvalidInput` → 400
- `BackendError`, `RepoError` → 500

## Testing Strategy

Following established project conventions:

| Type | File | Scope |
|------|------|-------|
| White-box unit | `store/*_wbtest.mbt` | Repos, Authorizer, entity conversion, LocalFS backend |
| Black-box unit | `store/*_test.mbt` | `Storage` service layer using mock repos + memory backend |
| Integration | `store/store_test.mbt` | Full HTTP server via pony, all REST endpoints |
| Snapshot | various | `inspect()` on routing trees, entity serialization |

Mock implementations (`MemoryBucketRepo`, `MemoryObjectRepo`, `MemoryBackend`) enable fast, deterministic tests without PG or filesystem dependencies.

## Concurrency Model

- `CompositeEntityStore`: `memory` layer is internally concurrency-safe; `persisted` (PG) is safe for concurrent reads. The store is read-only during authorizations.
- `RequestEntityStore`: per-request, single-threaded overlay. No contention. Dropped on request completion.
- `Storage`: holds shared repos and authorizer. Each handler method operates independently; repo implementations manage their own concurrency safety.
- `StorageBackend`: trait methods are synchronous; backends manage their own concurrent writes.
