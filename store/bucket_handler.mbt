// Bucket REST handlers — create, list, get, update, delete, empty.
// These handlers transform HTTP requests into Storage service calls.

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
pub fn build_bucket_routes(router : @pony.Router, storage : Storage) -> @pony.Router {
  router.add(@pony.HttpMethod::Post, "/bucket/", create_bucket_handler(storage)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Get, "/bucket/", list_buckets_handler(storage)) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Get, "/bucket/{bucketId}", get_bucket_handler(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Put, "/bucket/{bucketId}", update_bucket_handler(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Delete, "/bucket/{bucketId}", delete_bucket_handler(storage),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Post, "/bucket/{bucketId}/empty", empty_bucket_handler(storage),
  ) catch {
    _ => ()
  }
  router
}

///|
/// Extract authenticated user from X-User header.
fn extract_user(ctx : @pony.Context) -> String!StorageError {
  match ctx.header("X-User") {
    Some(u) => u
    None => raise Forbidden("missing X-User header")
  }
}

///|
/// Convert StorageError to an HTTP error response.
async fn error_to_ctx(ctx : @pony.Context, e : StorageError) -> Unit {
  ctx.response_error(e.to_http_status(), match e {
    NotFound(m) => m
    AlreadyExists(m) => m
    NotEmpty(m) => m
    Forbidden(m) => m
    InvalidInput(m) => m
    BackendError(m) => m
    RepoError(m) => m
  })
}

///|
/// POST /bucket/ — create a new bucket
fn create_bucket_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let body : CreateBucketBody = ctx.json() catch {
      _ => { ctx.response_error(400, "invalid JSON body"); return }
    }
    let bucket = storage.create_bucket(user, CreateBucketInput::{
      name: body.name,
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.response_ok(bucket)
  })
}

///|
/// GET /bucket/ — list all buckets
fn list_buckets_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let buckets = storage.list_buckets(user) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.response_ok(buckets)
  })
}

///|
/// GET /bucket/:bucketId — get a single bucket
fn get_bucket_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.response_error(400, "missing bucketId"); return }
    }
    let bucket = storage.get_bucket(user, id) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.response_ok(bucket)
  })
}

///|
/// PUT /bucket/:bucketId — update a bucket
fn update_bucket_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.response_error(400, "missing bucketId"); return }
    }
    let body : UpdateBucketBody = ctx.json() catch {
      _ => { ctx.response_error(400, "invalid JSON body"); return }
    }
    let bucket = storage.update_bucket(user, id, UpdateBucketInput::{
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.response_ok(bucket)
  })
}

///|
/// DELETE /bucket/:bucketId — delete a bucket (must be empty)
fn delete_bucket_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.response_error(400, "missing bucketId"); return }
    }
    let _ = storage.delete_bucket(user, id) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.no_content()
  })
}

///|
/// POST /bucket/:bucketId/empty — delete all objects in a bucket
fn empty_bucket_handler(storage : Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    let id = match ctx.param("bucketId") {
      Some(id) => id
      None => { ctx.response_error(400, "missing bucketId"); return }
    }
    let _ = storage.empty_bucket(user, id) catch {
      e => { error_to_ctx(ctx, e); return }
    }
    ctx.no_content()
  })
}
