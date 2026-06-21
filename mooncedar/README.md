# MoonCedar

A [Cedar](https://www.cedarpolicy.com) policy engine implemented in MoonBit — parser, evaluator, and authorizer.

## Installation

Add to your `moon.mod`:

```json
{ "deps": { "jaredzhou/mooncedar": "0.1.0" } }
```

## Quick Start

```moonbit
// 1. Parse a Cedar policy
let policies = @parser.parse_policies(
  #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");|
)

// 2. Build an entity store from JSON
let entities_src = #|[{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]
let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(entities_src))

// 3. Create a request
let req = @evaluator.Request::{
  principal: @evaluator.concrete_uid("User", "alice"),
  action: @evaluator.concrete_uid("Action", "view"),
  resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
  context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
}

// 4. Authorize
let result = is_authorized(req, policies.iter(), store)
match result.decision {
  Decision::Allow => println("permitted")
  Decision::Deny => println("denied")
}
// => permitted
```

## Packages

| Package | Imports | Purpose |
|---------|---------|---------|
| `jaredzhou/mooncedar` | `@parser`, `@evaluator`, `@ast` | Top-level: `is_authorized`, `evaluate`, `reauthorize`, `concretize` |
| `jaredzhou/mooncedar/ast` | — | AST types: `Expr`, `Policy`, `EntityUID`, `Value`, `Entity` |
| `jaredzhou/mooncedar/parser` | `@ast` | Lexer + recursive descent parser + `stringify` |
| `jaredzhou/mooncedar/evaluator` | `@ast` | Expression evaluator, scope matching, entity store trait |

## Features

### Policy Language

Full Cedar policy syntax support:

- `permit` / `forbid` effects with annotations
- Scope constraints (`==`, `in`, `in [set]`, `All`)
- `when` / `unless` conditions
- Expression language: `&&`, `||`, `!`, `>`, `<`, `>=`, `<=`, `!=`, `like`, `in`, `contains`, `has`, `.`, `.tag`
- Records, sets, if-then-else, extension function calls

### Expression Builder

```moonbit
let e = @ast.var_principal()
  .eq(@ast.val_str("alice"))
  .and_(@ast.var_resource()
    .has_tag(@ast.val_str("confidential"))
  )
```

### Policy Builder

```moonbit
let policy = @ast.default()
  .permit()
  .principal_eq("User", "alice")
  .action_eq("Action", "view")
  .resource_in("Album", "photos")
  .when_(@ast.var_resource().has_tag(@ast.val_str("public")))
```

### Strategy Validation

```moonbit
let errors = @ast.validate_policies(policies)
```

### Entity Store (Pluggable)

```moonbit
// In-memory store
let store = @evaluator.new_map_store()

// Custom backend via trait
struct DbStore { conn : Connection }
pub impl @evaluator.EntityStore for DbStore with get_entity(self, uid) {
  db_lookup(self.conn, uid)
}
```

Entity hierarchy: `is_descendant` uses BFS for ancestor traversal. Wildcard matching uses two-pointer backtracking.

### Partial Evaluation

Support for unknown PARC (principal, action, resource, context) slots — policies evaluate to residual expressions that can be re-evaluated when more information is available:

```moonbit
let req = @evaluator.Request::{
  principal: @evaluator.EntityUIDEntry::Unknown(@ast.EntityType("User")),
  action: @evaluator.concrete_uid("Action", "view"),
  resource: @evaluator.concrete_uid("Photo", "x"),
  context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
}

let answer = evaluate(req, policies.iter(), store1)        // partial result
let answer = answer.reauthorize(req, store2, Map([]))      // fill unknowns
let result = answer.concretize()                           // final decision
```

### JSON Serialization

Entity stores and entity UIDs serialize to/from Cedar-compatible JSON format:

```moonbit
let json_str = (#|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]}]
let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(json_str))

// Serialize back
let json = store.to_json()
println(json.stringify())
```

### Stringify (AST -> Cedar Source)

```moonbit
let src = @parser.stringify(policies)
```

## Status

- **546 tests** passing (parser, evaluator, authorizer, JSON)
- Entity stores as pluggable traits
- JSON serialization (Cedar-compatible format)
- Policy validation
- Full expression evaluation (18 expression variants, 12 binary + 3 unary operators)

## License

Apache-2.0
