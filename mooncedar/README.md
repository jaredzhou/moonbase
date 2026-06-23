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
let entities_src =
  #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]
let store : MapEntityStore = @json.from_json(@json.parse(entities_src))

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
| `jaredzhou/mooncedar` | `@parser`, `@evaluator`, `@ast`, `@json` | Top-level: `is_authorized`, `evaluate`, `reauthorize`, `concretize`, `MapEntityStore`, `new_map_store` |
| `jaredzhou/mooncedar/ast` | — | AST types: `Expr`, `Policy`, `EntityUID`, `Value`, `Entity` + builder methods |
| `jaredzhou/mooncedar/parser` | `@ast` | Lexer + recursive descent parser + `stringify` |
| `jaredzhou/mooncedar/evaluator` | `@ast` | `EntityStore` trait, expression evaluator, scope matching, CPE semantics |

Root-level `entity_store.mbt` provides `MapEntityStore` and Cedar JSON entity parsing.

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
let e = @ast.expr_principal()
  .eq(@ast.expr_str("alice"))
  .and_(@ast.expr_resource()
    .has_tag(@ast.expr_str("confidential"))
  )
```

### Policy Builder

```moonbit
let policy = @ast.default()
  .permit()
  .principal_eq("User", "alice")
  .action_eq("Action", "view")
  .resource_in("Album", "photos")
  .when_(@ast.expr_resource().has_tag(@ast.expr_str("public")))
```

### Strategy Validation

```moonbit
let errors = @ast.validate_policies(policies)
```

### Entity Store (Pluggable)

```moonbit
// In-memory store
let store = new_map_store()

// From JSON
let store : MapEntityStore = @json.from_json(@json.parse(entities_src))

// Custom backend via trait (pub(open) — implementable from any package)
struct DbStore { conn : Connection }
pub impl @evaluator.EntityStore for DbStore with get_entity(self, uid) {
  db_lookup(self.conn, uid)
}
```

Entity hierarchy: `is_descendant` uses BFS for ancestor traversal. Wildcard matching uses two-pointer backtracking.

### Partial Evaluation

Support for 4 sources of unknown during partial eval — policies evaluate to residual expressions that can be re-evaluated when more information is available:

```moonbit
// Unknown principal, entity missing, or unknown("x") in policy conditions
let answer = evaluate(req, policies.iter(), store1)        // partial result
let answer = answer.reauthorize(req, store2, mapping)      // fill unknowns
let result = answer.concretize()                           // final decision
```

The `reauthorize` method accepts an expanded entity store and a `Map[String, Value]` mapping to resolve unknowns by name.

### JSON Serialization

Entity stores serialize to/from Cedar-compatible JSON format:

```moonbit
let json_str =
  #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]}]
let store : MapEntityStore = @json.from_json(@json.parse(json_str))
let json = store.to_json()
```

### Stringify (AST -> Cedar Source)

```moonbit
let src = @parser.stringify(policies)
```

## Status

- **569 tests** passing (parser, evaluator, authorizer, JSON, reauthorize)
- Entity stores as pluggable traits (`pub(open)`)
- JSON serialization (Cedar-compatible format)
- Policy validation
- Full expression evaluation (18 expression variants, 12 binary + 3 unary operators)
- Partial evaluation with reauthorize (5-category coverage per partial_source.md spec)

## License

Apache-2.0
