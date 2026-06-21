---
name: using-mooncedar
description: Use when integrating Cedar authorization into a MoonBit project with mooncedar — setting up dependencies, writing policies, building entity stores, calling the authorizer, or implementing custom EntityStore backends
---

# Using MoonCedar — Integration Checklist

## Overview

MoonCedar is a Cedar policy engine for MoonBit. Integrate it to add policy-based authorization to any MoonBit project. The API surface is three concepts: **Policies** (what you check), **EntityStore** (who/what exists + hierarchy), and **Request** (what's happening now).

## Quick Reference

| Step | File/Action | Key Types |
|------|-----------|-----------|
| 1. Dependency | `moon.mod.json` add `"jaredzhou/mooncedar"` | — |
| 2. Define policies | In-code or `@parser.parse_policies(src)` | `@ast.Policy`, `@ast.ScopeConstraint` |
| 3. Build entity store | `MapEntityStore` or `@json.from_json(@json.parse(json_str))` | `@evaluator.MapEntityStore`, `@evaluator.EntityStore` (trait) |
| 4. Create request | PARC slots + context | `@evaluator.Request`, `@evaluator.concrete_uid()` |
| 5. Authorize | `is_authorized()` or `evaluate()` pipeline | `Decision`, `AuthorizationResult` |
| 6. Test | inspect snapshots for JSON, `_wbtest.mbt` for logic | `inspect(...)`, `_test.mbt` |

## 1. Dependency Setup

Add to your module's `moon.mod.json`:

```json
{ "deps": { "jaredzhou/mooncedar": "0.1.0" } }
```

Your package's `moon.pkg` needs these imports:

```mbt
import {
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "jaredzhou/mooncedar/parser",      // if parsing Cedar source
  "moonbitlang/core/json",            // if using JSON entity stores
}
```

Run `moon install`.

## 2. Defining Policies

**From Cedar source** (recommended — most readable):

```mbt
let policy_src = (
  #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");
)
let policies = @parser.parse_policies(policy_src)
```

**Direct struct construction** (for programmatic policies):

```mbt
let policy = @ast.Policy::{
  id: "allow-view",
  effect: @ast.PolicyEffect::Permit,
  annotations: [],
  principal: @ast.ScopeConstraint::Eq(@ast.EntityUID::{ type_: "User", id: "alice" }),
  action: @ast.ScopeConstraint::All,
  resource: @ast.ScopeConstraint::All,
  conditions: [],
}
```

## 3. Building Entity Stores

**From JSON string** (matches Cedar entity format, uses `"type"` key):

```mbt
let entities_src = (
  #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
)
let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(entities_src))
```

**Direct construction** (whitebox tests only, access to `entities` field):

```mbt
let store = @evaluator.MapEntityStore::{
  entities: Map([(@ast.EntityUID::{ type_: "User", id: "alice" }, entity)]),
}
```

**Custom EntityStore** (implement the trait):

```mbt
struct DbEntityStore { conn : Connection }

pub impl @evaluator.EntityStore for DbEntityStore with get_entity(self : DbEntityStore, uid : @ast.EntityUID) -> Option[@ast.Entity] {
  db_lookup(self.conn, uid)
}
```

## 4. Creating Authorization Requests

```mbt
let req = @evaluator.Request::{
  principal: @evaluator.concrete_uid("User", "alice"),
  action: @evaluator.concrete_uid("Action", "view"),
  resource: @evaluator.concrete_uid("Photo", "sunset.jpg"),
  context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
}
```

**Partial evaluation** — use `Unknown` for PARC slots not yet known:

```mbt
let req = @evaluator.Request::{
  principal: @evaluator.EntityUIDEntry::Unknown(@ast.EntityType("User")),
  // ...
}
```

## 5. Authorization Calls

**One-shot** (most common):

```mbt
let result = is_authorized(req, policies.iter(), store)
match result.decision {
  Decision::Allow => // permit
  Decision::Deny => // deny — check result.errors for diagnostics
}
```

**Pipeline** (partial eval, multi-round):

```mbt
let answer1 = evaluate(req, policies.iter(), store1)
let answer2 = answer1.reauthorize(req, store2, Map([]))
let result = answer2.concretize()
```

## 6. Interpreting Results

| Field | Meaning |
|-------|---------|
| `result.decision` | `Allow` or `Deny` (Deny-by-default, Forbid-overrides) |
| `result.determining_policies` | `Array[DiagnosticReason]` — which policies determined the outcome |
| `result.errors` | `Array[DiagnosticError]` — evaluation errors that were caught and skipped |

## 7. Complete Example

See `example_wbtest.mbt` in the mooncedar source. Policy and entities parsed from strings:

```mbt
test "example: parse policy + entities from strings, authorize → Allow" {
  let policy_src = (
    #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");
  )
  let entities_src = (
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]
  )

  let policies = @parser.parse_policies(policy_src)
  let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(entities_src))

  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", "alice"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }

  let result = is_authorized(req, policies.iter(), store)
  @debug.assert_eq(Decision::Allow, result.decision)
  @debug.assert_eq("policy0", result.determining_policies[0].policy_id)
}
```

## 8. MapEntityStore JSON

`MapEntityStore` implements `ToJson` and `FromJson` as a plain JSON array:

```json
[
  {"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]},
  {"uid":{"type":"Photo","id":"x"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}
]
```

Each entry has `uid` (uses `"type"` and `"id"` keys matching Cedar format), `attrs`, `tags`, `parents`. UIDs are extracted as map keys during deserialization.

```mbt
let json = store.to_json()                              // → Json::Array
let text = json.stringify()                             // → JSON string

let store : @evaluator.MapEntityStore = @json.from_json(json)  // deserialize

match store.get_entity(@ast.EntityUID::{ type_: "User", id: "alice" }) {
  Some(e) => // found
  None => // missing
}
```

**Inspect snapshot testing** (for JSON output verification):

```mbt
test "to_json single entity" {
  let src = (#|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]}]|)
  let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(src))
  inspect(store.to_json().stringify(), content=(
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]}]
  ))
}
// Run `moon test --update` to generate expected output, then verify with `moon test`.
```

See `evaluator/types_test.mbt` for complete inspect snapshot tests.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Passing `Array[Policy]` directly | Use `.iter()`: `[p1, p2].iter()` |
| Using old `EntityStore` struct name | Use `MapEntityStore` (or implement `EntityStore` trait) |
| Forgetting `pub impl` on custom trait impls | Must be `pub impl EntityStore for MyType with ...` to be visible outside your package |
| EntityUID JSON uses `"type_"` key | MoonBit maps `type_` field to `"type"` in JSON — use `"type"` when authoring JSON |
| Enum values in JSON (e.g. `Value::String`) | Serialized as `["String","value"]` — use this tuple format in JSON input |
| `#|` multiline string parse error | Wrap in `(...)`: `( #|content on one line\n )` or `(#|inline content|)` |
| Scopes not matching → unexpected Deny | `All` matches everything; `Eq` requires exact match; `In` needs hierarchy |
