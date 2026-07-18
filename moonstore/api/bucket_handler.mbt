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
pub fn build_bucket_routes(
  router : @pony.Router,
  storage : @moonstore.Storage,
) -> Unit raise @pony.RouterError {
  router.add(@pony.HttpMethod::Post, "/bucket/", create_bucket_handler(storage))
  router.add(@pony.HttpMethod::Get, "/bucket/", list_buckets_handler(storage))
  router.add(
    @pony.HttpMethod::Get,
    "/bucket/{bucketId}",
    get_bucket_handler(storage),
  )
  router.add(
    @pony.HttpMethod::Put,
    "/bucket/{bucketId}",
    update_bucket_handler(storage),
  )
  router.add(
    @pony.HttpMethod::Delete,
    "/bucket/{bucketId}",
    delete_bucket_handler(storage),
  )
  router.add(
    @pony.HttpMethod::Post,
    "/bucket/{bucketId}/empty",
    empty_bucket_handler(storage),
  )
}

///|
/// Extract authenticated user from X-User header.
fn extract_user(ctx : @pony.Context) -> String raise @moonstore.StorageError {
  (ctx.header("X-User") : String) catch {
    _ => raise @moonstore.Forbidden("missing X-User header")
  }
}

///|
/// Convert StorageError to an HTTP error response.
async fn error_to_ctx(ctx : @pony.Context, e : @moonstore.StorageError) -> Unit {
  ctx.reply_error(e)
}

///|
/// POST /bucket/ — create a new bucket
fn create_bucket_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let body : CreateBucketBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    let bucket = storage.create_bucket(user, @moonstore.CreateBucketInput::{
      name: body.name,
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(bucket)
  })
}

///|
/// GET /bucket/ — list all buckets
fn list_buckets_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let buckets = storage.list_buckets(user) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(buckets)
  })
}

///|
/// GET /bucket/:bucketId — get a single bucket
fn get_bucket_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let id : String = ctx.param("bucketId") catch {
      e => {
        ctx.reply_error(e)
        return
      }
    }
    let bucket = storage.get_bucket(user, id) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(bucket)
  })
}

///|
/// PUT /bucket/:bucketId — update a bucket
fn update_bucket_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let id : String = ctx.param("bucketId") catch {
      e => {
        ctx.reply_error(e)
        return
      }
    }
    let body : UpdateBucketBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    let bucket = storage.update_bucket(user, id, @moonstore.UpdateBucketInput::{
      public: body.public,
      file_size_limit: body.file_size_limit,
      allowed_mime_types: body.allowed_mime_types,
    }) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(bucket)
  })
}

///|
/// DELETE /bucket/:bucketId — delete a bucket (must be empty)
fn delete_bucket_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let id : String = ctx.param("bucketId") catch {
      e => {
        ctx.reply_error(e)
        return
      }
    }
    let _ = storage.delete_bucket(user, id) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}

///|
/// POST /bucket/:bucketId/empty — delete all objects in a bucket
fn empty_bucket_handler(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = extract_user(ctx) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    let id : String = ctx.param("bucketId") catch {
      e => {
        ctx.reply_error(e)
        return
      }
    }
    let _ = storage.empty_bucket(user, id) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}
