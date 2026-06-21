// Authorization wrapper — builds Cedar requests and calls mooncedar.

///|
/// Error raised by authorize_or_fail when access is denied.
pub(all) suberror AccessDenied { AccessDenied(String) } derive(Debug)

///|
/// Check if the given user is authorized to perform an action on a resource.
/// Returns true if authorized, false if denied.
pub fn try_authorize(
  user : String,
  action_type : String,
  action_id : String,
  resource_type : String,
  resource_id : String,
  state : @store.ServerState,
) -> Bool {
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", user),
    action: @evaluator.concrete_uid(action_type, action_id),
    resource: @evaluator.concrete_uid(resource_type, resource_id),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let result = @mooncedar.is_authorized(req, state.policies.iter(), state.entities)
  result.decision == @mooncedar.Decision::Allow
}

///|
/// Authorize or raise a string error message.
pub fn authorize_or_fail(
  user : String,
  action_type : String,
  action_id : String,
  resource_type : String,
  resource_id : String,
  state : @store.ServerState,
) -> Unit raise AccessDenied {
  if !try_authorize(user, action_type, action_id, resource_type, resource_id, state) {
    raise AccessDenied("403: access denied")
  }
}
