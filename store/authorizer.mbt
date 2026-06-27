// Authorizer -- Cedar authorization wrapper for store operations.

///|
/// Authorize store operations via Cedar policies.
pub(all) struct Authorizer {
  pub entities : CompositeEntityStore
  pub policies : Array[@ast.Policy]
}

///|
pub fn Authorizer::new(
  entities : CompositeEntityStore,
  policies : Array[@ast.Policy],
) -> Authorizer {
  Authorizer::{ entities, policies }
}

///|
/// Check if a user is authorized for an action on a resource.
/// If `overlay` is provided, entities within it take priority over the backing store.
pub fn Authorizer::try_authorize(
  self : Authorizer,
  user : String,
  action : String,
  resource_type : String,
  resource_id : String,
  overlay : Map[@ast.EntityUID, @ast.Entity]?,
) -> Bool {
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", user),
    action: @evaluator.concrete_uid("Action", action),
    resource: @evaluator.concrete_uid(resource_type, resource_id),
    context: @evaluator.Concrete(@ast.Value::Record(Map([]))),
  }

  match overlay {
    Some(ol) => {
      // Build a per-request entity store with overlay priority
      let req_store = RequestEntityStore::new(self.entities)
      for euid, entity in ol {
        req_store.add_entity(euid, entity)
      }
      let result = @mooncedar.is_authorized(req, self.policies.iter(), req_store)
      result.decision == @mooncedar.Decision::Allow
    }
    None => {
      let result = @mooncedar.is_authorized(
        req,
        self.policies.iter(),
        self.entities,
      )
      result.decision == @mooncedar.Decision::Allow
    }
  }
}
