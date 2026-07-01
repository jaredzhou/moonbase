// Storage service — main entry point.
// Starts an HTTP server with bucket and object routes.

///|
async fn main {
  let bucket_repo = @repo.MemoryBucketRepo::new()
  let object_repo = @repo.MemoryObjectRepo::new()
  let backend = @backend.MemoryBackend::new()
  let authorizer = @moonstore.Authorizer::new(
    @moonstore.CompositeEntityStore::new(Map([]), Map([])),
    @mooncedar.parse_policies("permit(principal,action,resource);") catch {
      _ => panic()
    },
  )

  let storage = @moonstore.Storage::new(
    backend, bucket_repo, object_repo, authorizer,
  )

  let router = @pony.Router::Router()
  @api.build_bucket_routes(router, storage) catch {
    e => {
      println("failed to register bucket routes: \{e}")
      panic()
    }
  }
  @api.build_object_routes(router, storage) catch {
    e => {
      println("failed to register object routes: \{e}")
      panic()
    }
  }

  println("moonstore starting on 0.0.0.0:3000")
  @pony.start("0.0.0.0:3000", router)
}
