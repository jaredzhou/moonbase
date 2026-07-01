// Tests for bucket REST handlers — verifies route registration.

///|
test "bucket handler routes registered" {
  let entities = @moonstore.CompositeEntityStore::new(Map([]), Map([]))
  let authorizer = @moonstore.Authorizer::new(entities, [])
  let storage = @moonstore.Storage::new(
    @backend.MemoryBackend::new(),
    @repo.MemoryBucketRepo::new(),
    @repo.MemoryObjectRepo::new(),
    authorizer,
  )
  let r = @pony.Router::Router()
  let _ = build_bucket_routes(r, storage)
  inspect(
    r,
    content=(
      #|Static()
      #|    └── Static(/bucket/) Post(/bucket/) Get(/bucket/)
      #|        p── Param(bucketId,/) Get(/bucket/{bucketId}) Put(/bucket/{bucketId}) Delete(/bucket/{bucketId})
      #|            └── Static(/empty) Post(/bucket/{bucketId}/empty)
      #|
    ),
  )
}
