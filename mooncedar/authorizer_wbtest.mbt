// Authorizer whitebox tests — evaluate, reauthorize, concretize, is_authorized.

///|
fn entity(
  uid : @ast.EntityUID,
  raw_attrs : Map[String, @ast.Value],
  raw_tags : Map[String, @ast.Value],
  parents : Array[@ast.EntityUID],
) -> @ast.Entity {
  let attrs : Map[String, @ast.PartialValue] = Map([])
  for key, val in raw_attrs {
    attrs.set(key, @ast.PartialValue::Value(val))
  }
  let tags : Map[String, @ast.PartialValue] = Map([])
  for key, val in raw_tags {
    tags.set(key, @ast.PartialValue::Value(val))
  }
  @ast.Entity::{ uid, attrs, tags, parents }
}

///|
fn empty_store() -> @evaluator.MapEntityStore {
  @evaluator.MapEntityStore::{ entities: Map([]) }
}

///|
fn empty_req() -> @evaluator.Request {
  @evaluator.Request::{
    principal: @evaluator.EntityUIDEntry::Concrete(@ast.EntityUID::{
      type_: "",
      id: "",
    }),
    action: @evaluator.EntityUIDEntry::Concrete(@ast.EntityUID::{
      type_: "",
      id: "",
    }),
    resource: @evaluator.EntityUIDEntry::Concrete(@ast.EntityUID::{
      type_: "",
      id: "",
    }),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
}

///|
fn uid(type_ : String, id : String) -> @ast.EntityUID {
  @ast.EntityUID::{ type_, id }
}

// ---------------------------------------------------------------------------
// is_authorized tests
// ---------------------------------------------------------------------------

///|
test "is_authorized: single permit" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let result = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Allow)
}

///|
test "is_authorized: single forbid" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Forbid,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let result = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

///|
test "is_authorized: no policies — Deny" {
  let result = is_authorized(empty_req(), [].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

///|
test "is_authorized: permit + forbid — Deny wins" {
  let permit_p = @ast.Policy::{
    id: "allow",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let forbid_p = @ast.Policy::{
    id: "deny",
    effect: @ast.PolicyEffect::Forbid,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let result = is_authorized(
    empty_req(),
    [permit_p, forbid_p].iter(),
    empty_store(),
  )
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

///|
test "is_authorized: unrelated policies" {
  let p1 = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::Eq(uid("X", "x")),
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let result = is_authorized(empty_req(), [p1].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

///|
test "is_authorized: condition error captured" {
  let p = @ast.Policy::{
    id: "bad",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::ExtensionApp(
          @ast.Name::{ ns: ["ip"], name: "parse" },
          [@ast.Expr::Lit(@ast.Literal::String("x"))],
        ),
      },
    ],
  }
  let result = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
  @debug.assert_eq(1, result.errors.length())
}

///|
test "is_authorized: equivalent to evaluate + concretize" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let via_evaluate = evaluate(empty_req(), [p].iter(), empty_store()).concretize()
  let via_direct = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, via_evaluate.decision == via_direct.decision)
}

// ---------------------------------------------------------------------------
// evaluate tests
// ---------------------------------------------------------------------------

///|
test "evaluate: no residuals in concrete policies" {
  let p = @ast.default().with_id("p1").permit().when_(@ast.Expr::Lit(@ast.Literal::Bool(true)))
  let answer = evaluate(empty_req(), [p].iter(), empty_store())
  assert_true(answer.satisfied is [satisfied] && satisfied.policy_id == "p1")
}
  

///|
test "evaluate: residual policy captured" {
  let p = @ast.default().with_id("p1").permit().when_(@ast.expr_unknown("x"))
  let answer = evaluate(empty_req(), [p].iter(), empty_store())
  assert_true(answer.residuals is [residual] && residual.expr is @ast.Expr::Unknown("x", _) )
}

///|
test "evaluate: unknown PARC captured as residual" {
  let p = @ast.default().with_id("p1").permit()
      .principal_eq("User", "alice")
      .action_eq("Action", "v")
      .resource_eq("Photo", "x")

   
  let req = @evaluator.Request::{
    principal: @evaluator.unknown_uid("User"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer = evaluate(req, [p].iter(), empty_store())
  guard answer.residuals is [residual] else {
    return
  }
  assert_true(residual.expr is @ast.Expr::BinaryApp(Eq, left, right) &&
    left is @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(EntityType("User")))) &&
    right is @ast.Expr::Lit(@ast.Literal::EntityUID(uuid)) && uuid == uid("User", "alice") 
  )
}

// ---------------------------------------------------------------------------
// concretize tests
// ---------------------------------------------------------------------------

///|
test "concretize: residual policies produce Deny" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.expr_unknown("x"),
      },
    ],
  }
  let result = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

// ---------------------------------------------------------------------------
// reauthorize tests — organized by the 5 Unknown sources (partial_source.md)
// ---------------------------------------------------------------------------
//
// Sources of Unknown:
//   1. Request (PARC):   principal/action/resource/context as Unknown
//   2. Context attrs:    individual context attribute values
//   3. Policy expr:      explicit unknown("name") in policy conditions
//   4. Entity missing:   entity not found in store during partial eval
//   5. Entity attrs:     entity exists but attr/tag value is Residual(Unknown)
//
// Each test: evaluate → show residual shape → reauthorize → assert outcome

// ---------------------------------------------------------------------------
// Category 1: Request (PARC) unknown
// ---------------------------------------------------------------------------

///|
test "reauthorize cat1: unknown principal resolved by mapping" {
  let policies = @parser.parse_policies(
    #|permit(principal == User::"alice", action, resource);
  )
  let req = @evaluator.Request::{
    principal: @evaluator.unknown_uid("User"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let store = empty_store()

  // First evaluation: unknown principal produces scope residual
  let answer1 = evaluate(req, policies.iter(), store)
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::Eq, left, right) &&
    left is @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(EntityType("User")))) &&
    right is @ast.Expr::Lit(@ast.Literal::EntityUID(uuid)) &&
    uuid == uid("User", "alice")
  )

  // Reauthorize: mapping replaces "principal" unknown
  let mapping = Map([("principal", @ast.Value::EntityUID(uid("User", "alice")))])
  let answer2 = answer1.reauthorize(req, store, mapping)
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "policy")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

///|
test "reauthorize cat1: unknown principal not resolved" {
  let policies = @parser.parse_policies(
    #|permit(principal == User::"alice", action, resource);
  )
  let req = @evaluator.Request::{
    principal: @evaluator.unknown_uid("User"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let answer1 = evaluate(req, policies.iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::Eq, left, right) &&
    left is @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(EntityType("User")))) &&
    right is @ast.Expr::Lit(@ast.Literal::EntityUID(uuid)) &&
    uuid == uid("User", "alice")
  )

  // Reauthorize with empty mapping → principal stays unknown
  let answer2 = answer1.reauthorize(req, empty_store(), Map([]))
  guard answer2.residuals is [r2] else { return }
  assert_true(
    r2.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::Eq, left2, right2) &&
    left2 is @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(EntityType("User")))) &&
    right2 is @ast.Expr::Lit(@ast.Literal::EntityUID(uuid2)) &&
    uuid2 == uid("User", "alice")
  )
  assert_true(answer2.satisfied is [])
  assert_true(answer2.concretize().decision == Decision::Deny)
}

// ---------------------------------------------------------------------------
// Category 2: Context attribute unknown
// ---------------------------------------------------------------------------

///|
test "reauthorize cat2: unknown context attr resolved by mapping" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_context().access("is_admin"))
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Partial(
      @ast.expr_record([("is_admin", @ast.Expr::Unknown("c", None))]),
    ),
  }

  // context.is_admin → records attribute "c" is unknown → residual
  let answer1 = evaluate(req, [p].iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(r1.expr is @ast.Expr::Unknown("c", None))

  // Reauthorize: mapping resolves "c" → true
  let mapping = Map([("c", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(req, empty_store(), mapping)
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "p1")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

///|
/// Context 被 Unknown 的情况（不可投影）。
/// context.is_admin 的 residual 是 GetAttr(Unknown("context"), "is_admin") ——
/// 整体未知没有字段可以"投影"，residual 保留整个 GetAttr 结构。
/// 字段级 mapping {"c" → true} 无法命中（residual 里没有 Unknown("c") 节点）。
test "reauthorize cat2: full context unknown — field mapping cannot resolve" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_context().access("is_admin"))
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Unknown,
  }

  // context 整体未知 → GetAttr(Unknown("context"), "is_admin")
  let answer1 = evaluate(req, [p].iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::GetAttr(
      @ast.Expr::Unknown("context", None),
      "is_admin",
    )
  )

  // 字段级 mapping → 命中不了
  let mapping = Map([("c", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(req, empty_store(), mapping)
  guard answer2.residuals is [r2] else { return }
  assert_true(
    r2.expr is @ast.Expr::GetAttr(
      @ast.Expr::Unknown("context", None),
      "is_admin",
    )
  )
  assert_true(answer2.satisfied is [])
}

///|
/// context 整体未知时，用 context 级 mapping 替换整个 Unknown("context") 节点。
/// {"context" → Record({"is_admin": true})} → 成功替换并解析。
test "reauthorize cat2: full context unknown — resolved by context-level mapping" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_context().access("is_admin"))
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Unknown,
  }

  let answer1 = evaluate(req, [p].iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::GetAttr(
      @ast.Expr::Unknown("context", None),
      "is_admin",
    )
  )

  // 替换整个 Unknown("context") 节点 → Record({"is_admin": true})
  let mapping = Map([
    ("context", @ast.Value::Record(
      Map([("is_admin", @ast.Value::Bool(true))]),
    )),
  ])
  let answer2 = answer1.reauthorize(req, empty_store(), mapping)
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "p1")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

///|
/// 访问 context 中不存在的 key → EntityNotFound error。
/// Context 是 Partial({"is_admin": unknown("c")})，策略引用 context.foo。
test "reauthorize cat2: nonexistent context key → error" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_context().access("foo"))
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Partial(
      @ast.expr_record([("is_admin", @ast.Expr::Unknown("c", None))]),
    ),
  }

  // foo 不在 context record 中 → EntityNotFound error
  let answer1 = evaluate(req, [p].iter(), empty_store())
  assert_true(answer1.residuals is [])
  assert_true(answer1.satisfied is [])
  guard answer1.errors is [err] else { return }
  assert_true(err.policy_id == "p1")
}

// ---------------------------------------------------------------------------
// Category 3: Policy expression unknown("name")
// ---------------------------------------------------------------------------

///|
test "reauthorize cat3: unknown resolved by mapping" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_unknown("flag"))

  let answer1 = evaluate(empty_req(), [p].iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  // residual is the unknown("flag") from the condition body
  assert_true(r1.expr is @ast.Expr::Unknown("flag", None))

  let mapping = Map([("flag", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(empty_req(), empty_store(), mapping)
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "p1")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

///|
test "reauthorize cat3: unknown not in mapping stays residual" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(@ast.expr_unknown("flag"))

  let answer1 = evaluate(empty_req(), [p].iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(r1.expr is @ast.Expr::Unknown("flag", None))

  // Reauthorize with empty mapping → unknown stays
  let answer2 = answer1.reauthorize(empty_req(), empty_store(), Map([]))
  guard answer2.residuals is [r2] else { return }
  assert_true(r2.expr is @ast.Expr::Unknown("flag", None))
  assert_true(answer2.satisfied is [])
  assert_true(answer2.concretize().decision == Decision::Deny)
}

// ---------------------------------------------------------------------------
// Category 4: Entity missing
// ---------------------------------------------------------------------------

///|
test "reauthorize cat4: in resolves with added entity" {
  let policies = @parser.parse_policies(
    (
      #|permit(principal, action, resource) when { User::"alice" in Team::"admins" };
    )
  )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  // Empty store → entity not found → in expression stays as residual
  let answer1 = evaluate(req, policies.iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child, parent) &&
    child is @ast.Expr::Lit(@ast.Literal::EntityUID(cu)) &&
    cu == uid("User", "alice") &&
    parent is @ast.Expr::Lit(@ast.Literal::EntityUID(pu)) &&
    pu == uid("Team", "admins")
  )

  // Reauthorize: store now has User::"alice" as child of Team::"admins"
  let store2 : @evaluator.MapEntityStore = @json.from_json(@json.parse(
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[{"type":"Team","id":"admins"}]}]
  ))
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "policy")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

///|
test "reauthorize cat4: still residual if entity still missing" {
  let policies = @parser.parse_policies(
    #|permit(principal, action, resource) when { User::"alice" in Team::"admins" };
  )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let answer1 = evaluate(req, policies.iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child, parent) &&
    child is @ast.Expr::Lit(@ast.Literal::EntityUID(cu)) &&
    cu == uid("User", "alice") &&
    parent is @ast.Expr::Lit(@ast.Literal::EntityUID(pu)) &&
    pu == uid("Team", "admins")
  )

  // Reauthorize with empty store → entity still missing → residual persists
  let answer2 = answer1.reauthorize(req, empty_store(), Map([]))
  guard answer2.residuals is [r2] else { return }
  assert_true(
    r2.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child2, parent2) &&
    child2 is @ast.Expr::Lit(@ast.Literal::EntityUID(cu2)) &&
    cu2 == uid("User", "alice") &&
    parent2 is @ast.Expr::Lit(@ast.Literal::EntityUID(pu2)) &&
    pu2 == uid("Team", "admins")
  )
  assert_true(answer2.satisfied is [])
  assert_true(answer2.concretize().decision == Decision::Deny)
}

///|
test "reauthorize cat4: forbid resolves to deny" {
  let policies = @parser.parse_policies(
    #|forbid(principal, action, resource) when { User::"alice" in Team::"admins" };
  )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let answer1 = evaluate(req, policies.iter(), empty_store())
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child, parent) &&
    child is @ast.Expr::Lit(@ast.Literal::EntityUID(cu)) &&
    cu == uid("User", "alice") &&
    parent is @ast.Expr::Lit(@ast.Literal::EntityUID(pu)) &&
    pu == uid("Team", "admins")
  )

  // Reauthorize: entity resolved → forbidden action → AuthorizeDeny
  let store2 : @evaluator.MapEntityStore = @json.from_json(@json.parse(
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[{"type":"Team","id":"admins"}]}]
  ))
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "policy")
  assert_true(answer2.concretize().decision == Decision::Deny)
}

///|
test "reauthorize cat4: satisfied carries forward" {
  let p_sat = @ast.default().with_id("sat").permit()
  let p_res = @ast.default().with_id("res").permit().when_(
    @ast.expr_euid("User", "alice").in_(@ast.expr_euid("Team", "admins")),
  )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  // First eval: one satisfied (no conditions), one residual (entity missing)
  let answer1 = evaluate(req, [p_sat, p_res], empty_store())
  assert_true(answer1.satisfied is [s] && s.policy_id == "sat")
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child, parent) &&
    child is @ast.Expr::Lit(@ast.Literal::EntityUID(cu)) &&
    cu == uid("User", "alice") &&
    parent is @ast.Expr::Lit(@ast.Literal::EntityUID(pu)) &&
    pu == uid("Team", "admins")
  )

  // Reauthorize: residual resolves → two satisfied
  let store2 : @evaluator.MapEntityStore = @json.from_json(@json.parse(
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[{"type":"Team","id":"admins"}]}]
  ))
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  assert_true(answer2.residuals is [])
  guard answer2.satisfied is [s1, s2] else { return }
  assert_true(s1.policy_id == "sat" && s2.policy_id == "res")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

// ---------------------------------------------------------------------------
// Category 5: Entity attr value unknown
// ---------------------------------------------------------------------------

///|
test "reauthorize cat5: entity attr unknown resolved by mapping" {
  let p = @ast.default()
    .with_id("p1")
    .permit()
    .when_(
      @ast.expr_principal().access("members").eq(
        @ast.expr_euid("UserGroup", "1"),
      ),
    )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("Project", "moonbase"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  // Entity exists but "members" attr value is unknown
  let ent = @ast.Entity::{
    uid: uid("Project", "moonbase"),
    attrs: Map([
      ("members", @ast.PartialValue::Residual(
        @ast.Expr::Unknown("partial_members", None),
      )),
    ]),
    tags: Map([]),
    parents: [],
  }
  let store = @evaluator.MapEntityStore::{
    entities: Map([(uid("Project", "moonbase"), ent)]),
  }

  // principal.members resolves to unknown("partial_members") → residual
  let answer1 = evaluate(req, [p].iter(), store)
  guard answer1.residuals is [r1] else { return }
  assert_true(
    r1.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::Eq, left, right) &&
    left is @ast.Expr::Unknown("partial_members", None) &&
    right is @ast.Expr::Lit(@ast.Literal::EntityUID(uuid)) &&
    uuid == uid("UserGroup", "1")
  )

  // Reauthorize: mapping resolves "partial_members" → UserGroup::"1"
  let mapping = Map([
    ("partial_members", @ast.Value::EntityUID(uid("UserGroup", "1"))),
  ])
  let answer2 = answer1.reauthorize(req, store, mapping)
  assert_true(answer2.residuals is [])
  assert_true(answer2.satisfied is [s] && s.policy_id == "p1")
  assert_true(answer2.concretize().decision == Decision::Allow)
}

// ---------------------------------------------------------------------------
// Combined: multiple unknown sources
// ---------------------------------------------------------------------------

///|
test "reauthorize combined: mapping + entity expansion" {
  let p1 = @ast.default().with_id("p1").permit().when_(@ast.expr_unknown("x"))
  let p2 = @ast.default().with_id("p2").permit().when_(
    @ast.expr_euid("User", "alice").in_(@ast.expr_euid("Team", "admins")),
  )
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  // First eval: policy unknown("x") + entity missing → two residuals
  let answer1 = evaluate(req, [p1, p2], empty_store())
  guard answer1.residuals is [r1, r2] else { return }
  // r1: category 3 — unknown("x") from policy condition
  assert_true(r1.expr is @ast.Expr::Unknown("x", None))
  // r2: category 4 — entity missing → in expression as residual
  assert_true(
    r2.expr is @ast.Expr::BinaryApp(@ast.BinaryOp::In_, child, parent) &&
    child is @ast.Expr::Lit(@ast.Literal::EntityUID(cu)) &&
    cu == uid("User", "alice") &&
    parent is @ast.Expr::Lit(@ast.Literal::EntityUID(pu)) &&
    pu == uid("Team", "admins")
  )

  // Reauthorize: mapping resolves unknown("x") + entity store resolves in
  let store2 : @evaluator.MapEntityStore = @json.from_json(@json.parse(
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[{"type":"Team","id":"admins"}]}]
  ))
  let mapping = Map([("x", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(req, store2, mapping)
  assert_true(answer2.residuals is [])
  guard answer2.satisfied is [s1, s2] else { return }
  assert_true(s1.policy_id == "p1" && s2.policy_id == "p2")
  assert_true(answer2.concretize().decision == Decision::Allow)
}
