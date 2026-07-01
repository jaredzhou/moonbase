// MemoryObjectRepo — in-memory ObjectRepo implementation.

///|
/// In-memory object metadata store for testing. Key is "bucket_id/name".
pub(all) struct MemoryObjectRepo {
  pub mut objects : Map[String, @moonstore.Object]
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
pub impl @moonstore.ObjectRepo for MemoryObjectRepo with fn get(
  self : MemoryObjectRepo,
  bucket_id : String,
  name : String,
) -> @moonstore.Object? {
  self.objects.get(obj_key(bucket_id, name))
}

///|
pub impl @moonstore.ObjectRepo for MemoryObjectRepo with fn list(
  self : MemoryObjectRepo,
  bucket_id : String,
  prefix : String?,
  limit : Int?,
  offset : Int?,
) -> Array[@moonstore.Object] {
  let result : Array[@moonstore.Object] = []
  let mut skipped = 0
  for _, obj in self.objects {
    if obj.bucket_id != bucket_id {
      continue
    }
    match prefix {
      Some(p) => if !obj.name.has_prefix(p) { continue }
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
pub impl @moonstore.ObjectRepo for MemoryObjectRepo with fn insert(
  self : MemoryObjectRepo,
  obj : @moonstore.Object,
) -> Unit {
  self.objects.set(obj_key(obj.bucket_id, obj.name), obj)
}

///|
pub impl @moonstore.ObjectRepo for MemoryObjectRepo with fn delete(
  self : MemoryObjectRepo,
  bucket_id : String,
  name : String,
) -> Unit {
  self.objects.remove(obj_key(bucket_id, name))
}

///|
pub impl @moonstore.ObjectRepo for MemoryObjectRepo with fn delete_batch(
  self : MemoryObjectRepo,
  bucket_id : String,
  names : Array[String],
) -> Unit {
  for name in names {
    self.objects.remove(obj_key(bucket_id, name))
  }
}
