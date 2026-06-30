// BucketRepo trait + MemoryBucketRepo implementation.

///|
/// Pluggable bucket metadata storage.
pub(open) trait BucketRepo {
  get(Self, id : String) -> Bucket?
  list(Self) -> Array[Bucket]
  insert(Self, bucket : Bucket) -> Unit
  update(Self, id : String, bucket : Bucket) -> Unit
  delete(Self, id : String) -> Unit
}

///|
pub fn[T: BucketRepo] list(backend : T) -> Array[Bucket] {
  backend.list()
}

///|
pub fn[T: BucketRepo] insert(backend : T, bucket : Bucket) -> Unit {
  backend.insert(bucket)
}

///|
pub fn[T: BucketRepo] update(backend : T, id : String, bucket : Bucket) -> Unit {
  backend.update(id, bucket)
}

// ---------------------------------------------------------------------------
// MemoryBucketRepo
// ---------------------------------------------------------------------------

///|
/// In-memory bucket metadata store for testing.
pub(all) struct MemoryBucketRepo {
  pub mut buckets : Map[String, Bucket]
}

///|
pub fn MemoryBucketRepo::new() -> MemoryBucketRepo {
  MemoryBucketRepo::{ buckets: Map([]) }
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn get(
  self : MemoryBucketRepo,
  id : String,
) -> Bucket? {
  self.buckets.get(id)
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn list(
  self : MemoryBucketRepo,
) -> Array[Bucket] {
  let result : Array[Bucket] = []
  for _, bucket in self.buckets {
    result.push(bucket)
  }
  result
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn insert(
  self : MemoryBucketRepo,
  bucket : Bucket,
) -> Unit {
  self.buckets.set(bucket.id, bucket)
}

///|
pub impl BucketRepo for MemoryBucketRepo with fn update(
  self : MemoryBucketRepo,
  id : String,
  bucket : Bucket,
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
