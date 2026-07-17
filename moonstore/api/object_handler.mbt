// Object REST handlers -- upload, download, info, update, list, move, copy, delete.
// Routes are ordered: specific paths first, wildcard `{bucketName}/*` last.

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
  user_metadata : Json?
} derive(FromJson)

///|
/// Register all object-related routes on the router.
/// Specific routes are registered BEFORE wildcard routes.
pub fn build_object_routes(
  router : @pony.Router,
  storage : @moonstore.Storage,
) -> Unit raise @pony.RouterError {
  // Download -- authenticated only
  router.add(
    @pony.HttpMethod::Get,
    "/object/authenticated/{bucketName}/*",
    authenticated_download(storage),
  )

  // Download -- public (no auth)
  router.add(
    @pony.HttpMethod::Get,
    "/object/public/{bucketName}/*",
    public_download(storage),
  )

  // Info -- authenticated HEAD
  router.add(
    @pony.HttpMethod::Head,
    "/object/info/{bucketName}/*",
    object_info_auth(storage),
  )

  // Info -- authenticated GET
  router.add(
    @pony.HttpMethod::Get,
    "/object/info/{bucketName}/*",
    object_info_auth(storage),
  )

  // Info -- public HEAD
  router.add(
    @pony.HttpMethod::Head,
    "/object/info/public/{bucketName}/*",
    object_info_public(storage),
  )

  // Info -- public GET
  router.add(
    @pony.HttpMethod::Get,
    "/object/info/public/{bucketName}/*",
    object_info_public(storage),
  )

  // List objects
  router.add(
    @pony.HttpMethod::Post,
    "/object/list/{bucketName}",
    list_objects(storage),
  )

  // Move
  router.add(@pony.HttpMethod::Post, "/object/move", move_object(storage))

  // Copy
  router.add(@pony.HttpMethod::Post, "/object/copy", copy_object(storage))

  // Delete batch (no wildcard -- exact match)
  router.add(
    @pony.HttpMethod::Delete,
    "/object/{bucketName}",
    delete_objects(storage),
  )

  // Upload (wildcard)
  router.add(
    @pony.HttpMethod::Post,
    "/object/{bucketName}/*",
    upload_object(storage),
  )

  // Download combined (wildcard)
  router.add(
    @pony.HttpMethod::Get,
    "/object/{bucketName}/*",
    download_object(storage),
  )

  // Update object metadata (wildcard)
  router.add(
    @pony.HttpMethod::Put,
    "/object/{bucketName}/*",
    update_object(storage),
  )

  // Delete single (wildcard)
  router.add(
    @pony.HttpMethod::Delete,
    "/object/{bucketName}/*",
    delete_object(storage),
  )
}

///|
fn extract_bucket_name(ctx : @pony.Context) -> String {
  match ctx.try_param("bucketName") {
    Some(n) => n
    None => "unknown"
  }
}

///|
fn extract_path(ctx : @pony.Context) -> String {
  match ctx.try_wildcard() {
    Some(p) => p
    None => ""
  }
}

///|
fn extract_user_opt(ctx : @pony.Context) -> String? {
  ctx.try_header("X-User")
}

// ---------------------------------------------------------------------------
// Object handlers
// ---------------------------------------------------------------------------

///|
/// POST /object/{bucketName}/* -- upload a file
fn upload_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    if name == "" {
      ctx.reply_error(
        @pony.ApiError::new(@pony.invalid_argument, "missing object path"),
      )
      return
    }
    // Read request body as raw bytes
    let body = ctx.req_body.read_all()
    let data = body.binary()
    let obj = storage.upload(
      user,
      bucket_name,
      name,
      data,
      Json::object(Map([])),
    ) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(obj)
  })
}

///|
/// GET /object/{bucketName}/* -- download (combined public+auth)
fn download_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = extract_user_opt(ctx)
    let (_, data) = storage.download(user, bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.write_bytes(200, data)
  })
}

///|
/// GET /object/authenticated/{bucketName}/* -- download (always requires auth)
fn authenticated_download(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let (_, data) = storage.download(Some(user), bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.write_bytes(200, data)
  })
}

///|
/// GET /object/public/{bucketName}/* -- public download (no auth)
fn public_download(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let (_, data) = storage.download(None, bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.write_bytes(200, data)
  })
}

///|
/// PUT /object/{bucketName}/* -- update object metadata
fn update_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let body : UpdateObjectBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    let obj = storage.update_object(user, bucket_name, name, @moonstore.UpdateObjectInput::{
      user_metadata: body.user_metadata,
    }) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(obj)
  })
}

///|
/// POST /object/list/{bucketName} -- list objects
fn list_objects(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let body : ListObjectsBody = ctx.json() catch {
      _ =>
        ListObjectsBody::{
          prefix: None,
          limit: None,
          offset: None,
          sort_by: None,
        }
    }
    let objs = storage.list_objects(
      user,
      bucket_name,
      body.prefix,
      body.limit,
      body.offset,
      body.sort_by,
    ) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(objs)
  })
}

///|
/// POST /object/move -- move an object
fn move_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let body : MoveCopyBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    storage.move_object(
      user,
      body.bucket_id,
      body.source_key,
      body.destination_key,
    ) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}

///|
/// POST /object/copy -- copy an object
fn copy_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let body : MoveCopyBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    storage.copy_object(
      user,
      body.bucket_id,
      body.source_key,
      body.destination_key,
    ) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}

///|
/// DELETE /object/{bucketName}/* -- delete a single object
fn delete_object(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    storage.delete_object(user, bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}

///|
/// DELETE /object/{bucketName} -- batch delete objects
fn delete_objects(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let body : DeleteBatchBody = ctx.json() catch {
      _ => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.invalid_argument, "invalid JSON body"),
        )
        return
      }
    }
    storage.delete_objects(user, bucket_name, body.prefixes) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.no_content()
  })
}

///|
/// GET|HEAD /object/info/{bucketName}/* -- authenticated object metadata
fn object_info_auth(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let user = match extract_user_opt(ctx) {
      Some(u) => u
      None => {
        ctx.reply_error(
          @pony.ApiError::new(@pony.unauthenticated, "missing X-User header"),
        )
        return
      }
    }
    let obj = storage.get_object_info(Some(user), bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(obj)
  })
}

///|
/// GET|HEAD /object/info/public/{bucketName}/* -- public object metadata
fn object_info_public(storage : @moonstore.Storage) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let bucket_name = extract_bucket_name(ctx)
    let name = extract_path(ctx)
    let obj = storage.get_object_info(None, bucket_name, name) catch {
      e => {
        error_to_ctx(ctx, e)
        return
      }
    }
    ctx.reply_ok(obj)
  })
}
