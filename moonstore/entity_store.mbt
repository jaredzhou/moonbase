// Entity store architecture -- CompositeEntityStore and RequestEntityStore.
// CompositeEntityStore layers in-memory cache over persisted (PG) storage.
// RequestEntityStore wraps a backing store with a per-request overlay.
//
// NOTE: MoonBit 0.10 does not support Box[Trait] for dynamic dispatch.
// Instead, CompositeEntityStore holds two Map[@ast.EntityUID, @ast.Entity]
// directly, and RequestEntityStore uses generics (type parameter B) to wrap
// any EntityStore-implementing backing store.

// ---------------------------------------------------------------------------
// CompositeEntityStore
// ---------------------------------------------------------------------------

///|
/// Shared entity store: memory cache (fast) to persisted store (PG).
/// Read-only during authorization; mutations go through the service layer.
pub(all) struct CompositeEntityStore {
  memory : Map[@ast.EntityUID, @ast.Entity]
  persisted : Map[@ast.EntityUID, @ast.Entity]
}

///|
pub fn CompositeEntityStore::new(
  memory : Map[@ast.EntityUID, @ast.Entity],
  persisted : Map[@ast.EntityUID, @ast.Entity],
) -> CompositeEntityStore {
  CompositeEntityStore::{ memory, persisted }
}

///|
/// Check memory first, fall back to persisted.
pub impl @evaluator.EntityStore for CompositeEntityStore with fn get_entity(
  self : CompositeEntityStore,
  uid : @ast.EntityUID,
) -> @ast.Entity? {
  match self.memory.get(uid) {
    Some(e) => Some(e)
    None => self.persisted.get(uid)
  }
}

// ---------------------------------------------------------------------------
// RequestEntityStore
// ---------------------------------------------------------------------------

///|
/// Per-request entity store: transient overlay to backing store.
/// Created fresh per request, dropped on completion. Single-threaded, no contention.
pub(all) struct RequestEntityStore[B] {
  mut overlay : Map[@ast.EntityUID, @ast.Entity]
  backing : B
}

///|
pub fn[B] RequestEntityStore::new(backing : B) -> RequestEntityStore[B] {
  RequestEntityStore::{ overlay: Map([]), backing }
}

///|
/// Add a transient entity for the duration of this request.
pub fn[B] RequestEntityStore::add_entity(
  self : RequestEntityStore[B],
  uid : @ast.EntityUID,
  entity : @ast.Entity,
) -> Unit {
  self.overlay.set(uid, entity)
}

///|
/// Check overlay first, fall back to backing store.
pub impl[B : @evaluator.EntityStore] @evaluator.EntityStore for RequestEntityStore[
  B,
] with fn get_entity(self : RequestEntityStore[B], uid : @ast.EntityUID) -> @ast.Entity? {
  match self.overlay.get(uid) {
    Some(e) => Some(e)
    None => self.backing.get_entity(uid)
  }
}
