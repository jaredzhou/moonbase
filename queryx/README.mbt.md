# QueryX

JSON-queryable filter DSL with to/from JSON, eval, and foxql bridge.

## Setup

```moonbit nocheck
// moon.mod
import {
  "jaredzhou/queryx@0.1.0",
}
```

```moonbit nocheck
// moon.pkg
import {
  "jaredzhou/queryx",
}
```

## Quick start

```moonbit nocheck
///|
let input : Json = {
  "filter": { "age": { "gt": 18.0, "lt": 65.0 }, "name": { "contains": "tom" } },
  "order_by": [{ "age": "desc" }],
  "page": { "after": "", "size": 10.0 },
}

///|
let query : Query = @json.from_json(input)

// JSON round-trip

///|
let json = query.to_json()
```

## Expr — filter expression tree

Supports `Compare`, `Between`, `StrMatch` (contains/starts_with/ends_with), `And`, `Or`, `Not`, and `Empty`.

```moonbit nocheck
let expr = Expr::And([
  Expr::Compare("age", CmpOp::Gt, Value::Int(18L)),
  Expr::StrMatch("name", StrKind::Contains, "tom"),
])

// Evaluate against field bindings
let values = Map([])
values.set("age", Value::Int(25L))
values.set("name", Value::String("tommy"))
assert_true(expr.eval(values)!)
```

## FoxQL bridge

Convert queryx `Expr` / `Query` into foxql SQL via `FieldResolver`.

### 1. Implement FieldResolver for your table

```moonbit nocheck
///|
struct User {
  table : Table
  id : Column[Int]
  name : Column[String]
  age : Column[Int]
}

///|
impl FieldResolver for User with fn resolve_column(self, field) -> ColumnRef? {
  match field {
    "id" => Some(self.id.to_ref())
    "name" => Some(self.name.to_ref())
    "age" => Some(self.age.to_ref())
    _ => None
  }
}

///|
impl FieldResolver for User with fn table_name(self) -> String {
  "users"
}
```

### 2. Expr → foxql Expr

```moonbit nocheck
///|
let expr = Expr::Compare("age", CmpOp::Gt, Value::Int(18L))

///|
let foxql_expr = to_foxql_expr(expr, user)
// → Expr::Compare(users.age, Gt, Value::Int(18))
```

### 3. Query → foxql SelectBuilder

```moonbit nocheck
let query : Query = @json.from_json(...)
let (sql, args) = to_select(query, user).to_sql()
// WHERE + ORDER BY + LIMIT all handled automatically
```

### 4. Dynamic schema (SchemaTable)

```moonbit nocheck
let schema = Schema::load([...])
let users = schema.table("users")
// SchemaTable implements FieldResolver natively
let (sql, args) = to_select(query, users).to_sql()
```

## Package structure

```
queryx/
├── queryx.mbt     # Query, Order, Page types + JSON serde
├── expr.mbt       # Expr, Value, CmpOp, StrKind + eval + JSON serde
├── foxql_bridge.mbt  # FieldResolver trait, to_foxql_expr, to_select
├── foxql_bridge_test.mbt
├── queryx_test.mbt
└── expr_test.mbt
```
