// Whitebox tests for Authorizer -- Cedar authorization wrapper.

///|
test "Authorizer try_authorize allows matching policy" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = CompositeEntityStore::new(mem.entities, pers.entities)
  let policies = @parser.parse_policies("permit(principal,action,resource);") catch {
    _ => abort("parse failed")
  }
  let authorizer = Authorizer::new(entities, policies)
  assert_true(
    authorizer.try_authorize("alice", "ReadBucket", "Bucket", "avatars", None),
  )
}

///|
test "Authorizer try_authorize denies without matching policy" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = CompositeEntityStore::new(mem.entities, pers.entities)
  let policies = @parser.parse_policies("forbid(principal,action,resource);") catch {
    _ => abort("parse failed")
  }
  let authorizer = Authorizer::new(entities, policies)
  assert_false(
    authorizer.try_authorize("alice", "ReadBucket", "Bucket", "avatars", None),
  )
}

///|
test "Authorizer try_authorize uses overlay entities" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let entities = CompositeEntityStore::new(mem.entities, pers.entities)

  let policies = @parser.parse_policies(
    "permit(principal, action == Action::\"ReadBucket\", resource) when { resource.owner == principal };",
  ) catch {
    _ => abort("parse failed")
  }
  let authorizer = Authorizer::new(entities, policies)

  // Add the bucket entity to an overlay (simulating request-scoped entity)
  let overlay : Map[@ast.EntityUID, @ast.Entity] = Map([])
  let bucket_euid = @ast.EntityUID::{ type_: "Bucket", id: "avatars" }
  let user_alice = @ast.EntityUID::{ type_: "User", id: "alice" }
  let bucket_entity = @ast.Entity::{
    uid: bucket_euid,
    attrs: Map([("owner", @ast.Value::EntityUID(user_alice))]),
    tags: Map([]),
    parents: [],
  }
  overlay.set(bucket_euid, bucket_entity)

  assert_true(
    authorizer.try_authorize(
      "alice", "ReadBucket", "Bucket", "avatars", Some(overlay),
    ),
  )
  assert_false(
    authorizer.try_authorize(
      "bob", "ReadBucket", "Bucket", "avatars", Some(overlay),
    ),
  )
}
