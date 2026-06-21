// Authorizer whitebox tests — evaluate, reauthorize, concretize, is_authorized.

///|
fn entity(
  uid : @ast.EntityUID,
  attrs : Map[String, @ast.Value],
  tags : Map[String, @ast.Value],
  parents : Array[@ast.EntityUID],
) -> @ast.Entity {
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
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let answer = evaluate(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(1, answer.satisfied.length())
  @debug.assert_eq(0, answer.residuals.length())
  @debug.assert_eq(0, answer.errors.length())
}

///|
test "evaluate: residual policy captured" {
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
        body: @ast.unknown("x"),
      },
    ],
  }
  let answer = evaluate(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(0, answer.satisfied.length())
  @debug.assert_eq(1, answer.residuals.length())
  @debug.assert_eq(0, answer.errors.length())
}

///|
test "evaluate: unknown PARC captured as residual" {
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.EntityUIDEntry::Unknown(@ast.EntityType("User")),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer = evaluate(req, [p].iter(), empty_store())
  @debug.assert_eq(0, answer.satisfied.length())
  @debug.assert_eq(1, answer.residuals.length())
  @debug.assert_eq(0, answer.errors.length())
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
        body: @ast.unknown("x"),
      },
    ],
  }
  let result = is_authorized(empty_req(), [p].iter(), empty_store())
  @debug.assert_eq(true, result.decision == Decision::Deny)
}

// ---------------------------------------------------------------------------
// reauthorize tests
// ---------------------------------------------------------------------------

///|
test "reauthorize: residual policy resolves with more entities" {
  let e1 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice")))
  let e2 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins")))
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
        body: @ast.Expr::BinaryApp(@ast.BinaryOp::In_, e1, e2),
      },
    ],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer1 = evaluate(req, [p].iter(), empty_store())
  @debug.assert_eq(0, answer1.satisfied.length())
  @debug.assert_eq(1, answer1.residuals.length())

  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store2 = @evaluator.MapEntityStore::{
    entities: Map([(uid("User", "alice"), ent)]),
  }
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  @debug.assert_eq(1, answer2.satisfied.length())
  @debug.assert_eq(0, answer2.residuals.length())

  let result = answer2.concretize()
  @debug.assert_eq(true, result.decision == Decision::Allow)
}

///|
test "reauthorize: still residual if entity still missing" {
  let e1 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice")))
  let e2 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins")))
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
        body: @ast.Expr::BinaryApp(@ast.BinaryOp::In_, e1, e2),
      },
    ],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer1 = evaluate(req, [p].iter(), empty_store())
  @debug.assert_eq(1, answer1.residuals.length())

  let answer2 = answer1.reauthorize(req, empty_store(), Map([]))
  @debug.assert_eq(1, answer2.residuals.length())
  @debug.assert_eq(0, answer2.satisfied.length())

  @debug.assert_eq(true, answer2.concretize().decision == Decision::Deny)
}

///|
test "reauthorize: satisfied from prior round carries forward" {
  let satisfied_p = @ast.Policy::{
    id: "satisfied",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [],
  }
  let residual_p = @ast.Policy::{
    id: "residual",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::BinaryApp(
          @ast.BinaryOp::In_,
          @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
          @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins"))),
        ),
      },
    ],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer1 = evaluate(req, [satisfied_p, residual_p], empty_store())
  @debug.assert_eq(1, answer1.satisfied.length())
  @debug.assert_eq(1, answer1.residuals.length())

  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store2 = @evaluator.MapEntityStore::{
    entities: Map([(uid("User", "alice"), ent)]),
  }
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  @debug.assert_eq(2, answer2.satisfied.length())
  @debug.assert_eq(0, answer2.residuals.length())

  @debug.assert_eq(true, answer2.concretize().decision == Decision::Allow)
}

///|
test "reauthorize: residual forbid resolves to satisfied forbid" {
  let e1 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice")))
  let e2 = @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins")))
  let p = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Forbid,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::BinaryApp(@ast.BinaryOp::In_, e1, e2),
      },
    ],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer1 = evaluate(req, [p].iter(), empty_store())
  @debug.assert_eq(1, answer1.residuals.length())

  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store2 = @evaluator.MapEntityStore::{
    entities: Map([(uid("User", "alice"), ent)]),
  }
  let answer2 = answer1.reauthorize(req, store2, Map([]))
  @debug.assert_eq(1, answer2.satisfied.length())
  @debug.assert_eq(0, answer2.residuals.length())

  @debug.assert_eq(true, answer2.concretize().decision == Decision::Deny)
}

///|
test "reauthorize: unknown resolved by mapping becomes concrete" {
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
        body: @ast.unknown("flag"),
      },
    ],
  }
  let req = empty_req()
  let answer1 = evaluate(req, [p].iter(), empty_store())
  @debug.assert_eq(1, answer1.residuals.length())

  let mapping = Map([("flag", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(req, empty_store(), mapping)
  @debug.assert_eq(1, answer2.satisfied.length())
  @debug.assert_eq(0, answer2.residuals.length())

  @debug.assert_eq(true, answer2.concretize().decision == Decision::Allow)
}

///|
test "reauthorize: mapping false + entity expansion combined" {
  let p1 = @ast.Policy::{
    id: "p1",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.unknown("x"),
      },
    ],
  }
  let p2 = @ast.Policy::{
    id: "p2",
    effect: @ast.PolicyEffect::Permit,
    annotations: [],
    principal: @ast.ScopeConstraint::All,
    action: @ast.ScopeConstraint::All,
    resource: @ast.ScopeConstraint::All,
    conditions: [
      @ast.Condition::{
        kind: @ast.ConditionKind::When,
        body: @ast.Expr::BinaryApp(
          @ast.BinaryOp::In_,
          @ast.Expr::Lit(@ast.Literal::EntityUID(uid("User", "alice"))),
          @ast.Expr::Lit(@ast.Literal::EntityUID(uid("Team", "admins"))),
        ),
      },
    ],
  }
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "v"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let answer1 = evaluate(req, [p1, p2], empty_store())
  @debug.assert_eq(2, answer1.residuals.length())

  let ent = entity(uid("User", "alice"), Map([]), Map([]), [
    uid("Team", "admins"),
  ])
  let store2 = @evaluator.MapEntityStore::{
    entities: Map([(uid("User", "alice"), ent)]),
  }
  let mapping = Map([("x", @ast.Value::Bool(true))])
  let answer2 = answer1.reauthorize(req, store2, mapping)
  @debug.assert_eq(2, answer2.satisfied.length())
  @debug.assert_eq(0, answer2.residuals.length())

  @debug.assert_eq(true, answer2.concretize().decision == Decision::Allow)
}
