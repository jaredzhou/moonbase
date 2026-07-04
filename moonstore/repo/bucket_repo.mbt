// MemoryBucketRepo — in-memory BucketRepo implementation.

///|
/// In-memory bucket metadata store for testing.
pub(all) struct MemoryBucketRepo {
  pub mut buckets : Map[String, @moonstore.Bucket]
}

///|
pub fn MemoryBucketRepo::new() -> MemoryBucketRepo {
  MemoryBucketRepo::{ buckets: Map([]) }
}

///|
pub impl @moonstore.BucketRepo for MemoryBucketRepo with fn get(
  self : MemoryBucketRepo,
  id : String,
) -> @moonstore.Bucket? raise Error {
  self.buckets.get(id)
}

///|
pub impl @moonstore.BucketRepo for MemoryBucketRepo with fn list(
  self : MemoryBucketRepo,
) -> Array[@moonstore.Bucket] raise Error {
  let result : Array[@moonstore.Bucket] = []
  for _, bucket in self.buckets {
    result.push(bucket)
  }
  result
}

///|
pub impl @moonstore.BucketRepo for MemoryBucketRepo with fn insert(
  self : MemoryBucketRepo,
  bucket : @moonstore.Bucket,
) -> Unit raise Error {
  self.buckets.set(bucket.id, bucket)
}

///|
pub impl @moonstore.BucketRepo for MemoryBucketRepo with fn update(
  self : MemoryBucketRepo,
  id : String,
  bucket : @moonstore.Bucket,
) -> Unit raise Error {
  self.buckets.set(id, bucket)
}

///|
pub impl @moonstore.BucketRepo for MemoryBucketRepo with fn delete(
  self : MemoryBucketRepo,
  id : String,
) -> Unit raise Error {
  self.buckets.remove(id)
}
