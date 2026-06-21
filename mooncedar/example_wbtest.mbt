// Example tests — matching cedar-go: policy + entities from strings → authorize.

///|
test "example: parse policy + entities from strings, authorize → Allow" {
  let policy_src =
    #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");
  let entities_src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]

  let policies = @parser.parse_policies(policy_src)
  let store : @evaluator.MapEntityStore = @json.from_json(
    @json.parse(entities_src),
  )

  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let result = is_authorized(req, policies.iter(), store)
  @debug.assert_eq(Decision::Allow, result.decision)
  @debug.assert_eq(1, result.determining_policies.length())
}

///|
test "example: resource not in hierarchy — Deny" {
  let policy_src =
    #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");
  let entities_src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"other_album"}]}]

  let store : @evaluator.MapEntityStore = @json.from_json(
    @json.parse(entities_src),
  )

  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let result = is_authorized(
    req,
    @parser.parse_policies(policy_src).iter(),
    store,
  )
  @debug.assert_eq(Decision::Deny, result.decision)
}

///|
test "example: forbid overrides permit" {
  let src =
    #|permit (principal,action,resource);forbid(principal,action,resource);
  let policies = @parser.parse_policies(src)
  let store = @evaluator.new_map_store()
  let result = is_authorized(empty_req(), policies.iter(), store)
  @debug.assert_eq(Decision::Deny, result.decision)
}
