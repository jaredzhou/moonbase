// Constructor helpers for building a Storage with concrete implementations.

///|
/// Create a new Storage with in-memory repos and backend.
pub fn new_storage() -> @moonstore.Storage {
  let entities = @moonstore.CompositeEntityStore::new(Map([]), Map([]))
  let policies = @parser.parse_policies("permit(principal,action,resource);") catch {
    _ => @parser.parse_policies("") catch { _ => panic() }
  }
  @moonstore.Storage::{
    backend: @backend.MemoryBackend::new(),
    bucket_repo: MemoryBucketRepo::new(),
    object_repo: MemoryObjectRepo::new(),
    authorizer: @moonstore.Authorizer::new(entities, policies),
  }
}
