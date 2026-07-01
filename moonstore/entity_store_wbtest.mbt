// Whitebox tests for CompositeEntityStore and RequestEntityStore.

///|
/// CompositeEntityStore: entity placed only in persisted is found via fallback.
test "CompositeEntityStore falls back from memory to persisted" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(true))]),
    tags: Map([]),
    parents: [],
  }
  // Put in persisted only
  pers.entities.set(euid, entity)
  let composite = CompositeEntityStore::new(mem.entities, pers.entities)
  let found = composite.get_entity(euid)
  assert_true(found is Some(_))
  @debug.assert_eq(found, Some(entity))
}

///|
/// CompositeEntityStore: when both stores have the same EUID, memory wins.
test "CompositeEntityStore prefers memory over persisted" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let mem_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(true))]),
    tags: Map([]),
    parents: [],
  }
  let pers_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("public", @ast.Value::Bool(false))]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, mem_entity)
  pers.entities.set(euid, pers_entity)
  let composite = CompositeEntityStore::new(mem.entities, pers.entities)
  let found = composite.get_entity(euid)
  assert_true(found is Some(_))
  match found {
    Some(e) =>
      match e.attrs.get("public") {
        Some(@ast.Value::Bool(b)) => assert_true(b)
        _ => abort("unexpected attr")
      }
    _ => abort("unexpected")
  }
}

///|
/// RequestEntityStore: overlay entity shadows the backing store's entity.
test "RequestEntityStore overlay takes priority" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let mem_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("name", @ast.Value::String("from-mem"))]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, mem_entity)
  let composite = CompositeEntityStore::new(mem.entities, pers.entities)
  let req_store = RequestEntityStore::new(composite)

  let overlay_entity = @ast.Entity::{
    uid: euid,
    attrs: Map([("name", @ast.Value::String("from-overlay"))]),
    tags: Map([]),
    parents: [],
  }
  req_store.add_entity(euid, overlay_entity)

  let found = req_store.get_entity(euid)
  match found {
    Some(e) =>
      match e.attrs.get("name") {
        Some(@ast.Value::String(s)) => @debug.assert_eq(s, "from-overlay")
        _ => abort("unexpected attr")
      }
    _ => abort("unexpected")
  }
}

///|
/// RequestEntityStore: when overlay is empty, falls through to backing.
test "RequestEntityStore falls through to backing" {
  let mem = @mooncedar.new_map_store()
  let pers = @mooncedar.new_map_store()
  let euid = @ast.EntityUID::{ type_: "Bucket", id: "test" }
  let entity = @ast.Entity::{
    uid: euid,
    attrs: Map([]),
    tags: Map([]),
    parents: [],
  }
  mem.entities.set(euid, entity)
  let composite = CompositeEntityStore::new(mem.entities, pers.entities)
  let req_store = RequestEntityStore::new(composite)

  let found = req_store.get_entity(euid)
  assert_true(found is Some(_))
}
