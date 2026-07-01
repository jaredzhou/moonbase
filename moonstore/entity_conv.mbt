// Entity conversion — Bucket and Object to Cedar entity representations.

///|
/// Convert a Bucket to a (EntityUID, Entity) pair for Cedar authorization.
pub fn bucket_to_entity(bucket : Bucket) -> (@ast.EntityUID, @ast.Entity) {
  let euid = @ast.EntityUID::{ type_: "Bucket", id: bucket.id }
  let attrs = Map([
    ("owner", @ast.Value::String(bucket.owner)),
    ("owner_id", @ast.Value::String(bucket.owner_id)),
    ("public", @ast.Value::Bool(bucket.public)),
  ])
  let parents = [@ast.EntityUID::{ type_: "Application", id: "Storage" }]
  (euid, @ast.Entity::{ uid: euid, attrs, tags: Map([]), parents })
}

///|
/// Extract the folder name from an object path.
/// e.g. "public/avatar.png" -> "public", "readme.txt" -> ""
fn folder_from_name(name : String) -> String {
  let len = name.length()
  for i = len - 1; i >= 0; i = i - 1 {
    if name[i] == '/' {
      return name[:i].to_owned()
    }
  }
  ""
}

///|
/// Convert an Object to a (EntityUID, Entity) pair for Cedar authorization.
pub fn object_to_entity(obj : Object) -> (@ast.EntityUID, @ast.Entity) {
  let euid = @ast.EntityUID::{
    type_: "Object",
    id: match obj.id {
      Some(id) => id
      None => obj.bucket_id + "/" + obj.name
    },
  }
  let folder = folder_from_name(obj.name)
  let attrs = Map([
    ("bucket_id", @ast.Value::String(obj.bucket_id)),
    ("owner", @ast.Value::String(obj.owner)),
    ("owner_id", @ast.Value::String(obj.owner_id)),
    ("name", @ast.Value::String(obj.name)),
    ("size", @ast.Value::Long(obj.metadata.size)),
    ("mimetype", @ast.Value::String(obj.metadata.mimetype)),
    ("folder", @ast.Value::String(folder)),
  ])
  let parents = [@ast.EntityUID::{ type_: "Bucket", id: obj.bucket_id }]
  (euid, @ast.Entity::{ uid: euid, attrs, tags: Map([]), parents })
}
