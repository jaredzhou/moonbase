# FoxQL

Compile-time type-safe SQL builder for PostgreSQL in MoonBit.

## Setup

Add to your `moon.mod`:

```moonbit nocheck
import {
  "jaredzhou/foxql@0.1.0",
}
```

Then import in your `moon.pkg`:

```moonbit nocheck
import {
  "jaredzhou/foxql",
}
```

## Quick start

Define table proxies with typed columns, then build queries fluently.

```moonbit nocheck
///|
struct UserTable {
  table : Table
  id : Column[Int]
  name : Column[String]
  age : Column[Int]
}

///|
let users : UserTable = {
  table: Table::new("users"),
  id: Column::new("id", "users", SqlType::Integer),
  name: Column::new("name", "users", SqlType::Text),
  age: Column::new("age", "users", SqlType::Integer),
}

///|
struct OrdersTable {
  table : Table
  id : Column[Int]
  user_id : Column[Int]
  amount : Column[Int]
}

///|
let orders : OrdersTable = {
  table: Table::new("orders"),
  id: Column::new("id", "orders", SqlType::Integer),
  user_id: Column::new("user_id", "orders", SqlType::Integer),
  amount: Column::new("amount", "orders", SqlType::Integer),
}
```

## SELECT

```moonbit nocheck
let (sql, args) = users.table.select().to_sql()
// sql  = "SELECT * FROM users"
// args = []

let (sql, args) = users.table.select(columns=[users.name, users.age]).to_sql()
// sql  = "SELECT users.name, users.age FROM users"
// args = []

let (sql, args) = users.table.select().where_(users.age.eq(18)).to_sql()
// sql  = "SELECT * FROM users WHERE users.age = $1"
// args = [18]
```

### WHERE operators

All operators are **type-safe at compile time** — `Column[Int]` gets comparison operators, `Column[String]` gets string operators, `Column[Bool]` gets only equality.

| Category | Operators | Available on |
|----------|-----------|-------------|
| Equality | `eq`, `neq` | All types |
| Comparison | `gt`, `gte`, `lt`, `lte` | `Int`, `Double` |
| Range | `between(lo, hi)` | `Int`, `Double` |
| Set | `in_([vals])` | All types |
| String | `like`, `not_like` | `String` |
| Null | `is_null`, `is_not_null` | All types |

```moonbit nocheck
users.age.gt(18)
// → users.age > $1  [18]

users.age.between(18, 65)
// → users.age BETWEEN $1 AND $2  [18, 65]

users.name.like("Al%")
// → users.name LIKE $1  ["Al%"]

users.name.is_null()
// → users.name IS NULL  []

users.age.in_([1, 2, 3])
// → users.age IN ($1, $2, $3)  [1, 2, 3]
```

### Condition composition

```moonbit nocheck
let (sql, args) = users.table.select()
  .where_(users.age.gte(18).and_(users.age.lte(65)))
  .to_sql()
// sql  = "SELECT * FROM users WHERE (users.age >= $1 AND users.age <= $2)"
// args = [18, 65]

let (sql, args) = users.table.select()
  .where_(users.name.eq("Alice").or_(users.name.eq("Bob")))
  .to_sql()
// sql  = "SELECT * FROM users WHERE (users.name = $1 OR users.name = $2)"
// args = ["Alice", "Bob"]

let (sql, args) = users.table.select()
  .where_(not_(users.age.eq(0)))
  .to_sql()
// sql  = "SELECT * FROM users WHERE NOT (users.age = $1)"
// args = [0]

// Complex nesting
let (sql, args) = users.table.select()
  .where_(users.age.lt(18).or_(users.age.gt(65)).and_(users.name.is_not_null()))
  .to_sql()
// sql  = "SELECT * FROM users WHERE ((users.age < $1 OR users.age > $2) AND users.name IS NOT NULL)"
// args = [18, 65]
```

### ORDER BY, LIMIT, OFFSET, DISTINCT

```moonbit nocheck
let (sql, args) = users.table.select()
  .order_by(users.name.asc())
  .order_by(users.age.desc())
  .limit(10)
  .offset(20)
  .to_sql()
// sql  = "SELECT * FROM users ORDER BY users.name ASC, users.age DESC LIMIT $1 OFFSET $2"
// args = [10, 20]

let (sql, args) = users.table.select(columns=[users.name]).distinct().to_sql()
// sql  = "SELECT DISTINCT users.name FROM users"
// args = []

let (sql, args) = users.table.select(columns=[users.name, users.age])
  .distinct_on([users.name]).to_sql()
// sql  = "SELECT DISTINCT ON (users.name) users.name, users.age FROM users"
// args = []
```

## INSERT / UPDATE / DELETE

### INSERT

```moonbit nocheck
let (sql, args) = users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2)"
// args = ["Alice", 30]

let (sql, args) = users.table.insert([users.name, users.age])
  .rows([["Alice", 30], ["Bob", 25]])
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2), ($3, $4)"
// args = ["Alice", 30, "Bob", 25]

let (sql, args) = users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .returning([users.id])
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2) RETURNING users.id"
// args = ["Alice", 30]
```

### UPDATE

Type-state enforced: `.where_()` is **required** before `.to_sql()`.

```mbt nocheck
let (sql, args) = users.table.update()
  .set(users.name, "Dave")
  .set(users.age, 99)
  .where_(users.id.eq(1))
  .returning([users.id, users.name])
  .to_sql()
// sql  = "UPDATE users SET users.name = $1, users.age = $2 WHERE users.id = $3 RETURNING users.id, users.name"
// args = ["Dave", 99, 1]
```

### DELETE

Type-state enforced: `.where_()` is **required** before `.to_sql()`.

```mbt nocheck
let (sql, args) = users.table.delete()
  .where_(users.age.lt(18))
  .returning([users.id])
  .to_sql()
// sql  = "DELETE FROM users WHERE users.age < $1 RETURNING users.id"
// args = [18]
```

### ON CONFLICT (upsert)

```mbt nocheck
let (sql, args) = users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .on_conflict([users.name])
  .do_nothing()
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2) ON CONFLICT (name) DO NOTHING"
// args = ["Alice", 30]

let (sql, args) = users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .on_conflict([users.name])
  .do_update(users.age, 30)
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2) ON CONFLICT (name) DO UPDATE SET users.age = $3"
// args = ["Alice", 30, 30]
```

## JOIN

```moonbit nocheck
let (sql, args) = users.table
  .select(columns=[users.name, orders.amount])
  .join(orders.table, users.id.eq_col(orders.user_id))
  .where_(orders.amount.gt(100))
  .order_by(orders.amount.desc())
  .to_sql()
// sql  = "SELECT users.name, orders.amount FROM users"
//        " INNER JOIN orders ON users.id = orders.user_id"
//        " WHERE orders.amount > $1"
//        " ORDER BY orders.amount DESC"
// args = [100]
```

## Aggregation & GROUP BY

```moonbit nocheck
let (sql, args) = orders.table
  .select(columns=[orders.user_id])
  .agg(sum(orders.amount))
  .agg(count_star())
  .group_by([orders.user_id])
  .having(sum(orders.amount).gt(1000))
  .order_by(orders.user_id.asc())
  .to_sql()
// sql  = "SELECT orders.user_id, SUM(orders.amount), COUNT(*)"
//        " FROM orders"
//        " GROUP BY orders.user_id"
//        " HAVING SUM(orders.amount) > $1"
//        " ORDER BY orders.user_id ASC"
// args = [1000]
```

## Subqueries

```moonbit nocheck
// WHERE … IN (SELECT …)
let sub = orders.table.select(columns=[orders.user_id])
  .where_(orders.amount.gt(100)).build()
let (sql, args) = users.table.select()
  .where_(users.id.in_select(sub)).to_sql()
// sql  = "SELECT * FROM users WHERE users.id IN (SELECT orders.user_id FROM orders WHERE orders.amount > $1)"
// args = [100]

// Scalar subquery
let max_age = users.table.select(columns=[users.age])
  .order_by(users.age.desc()).limit(1).build()
let (sql, args) = users.table.select()
  .where_(users.age.eq_select(max_age)).to_sql()
// sql  = "SELECT * FROM users WHERE users.age = (SELECT users.age FROM users ORDER BY users.age DESC LIMIT $1)"
// args = [1]
```

## Schema-qualified tables

```moonbit nocheck
///|
let table = Table::new("profiles", schema="public")
// → "public"."profiles"
```

## Building AST nodes

Use `.build()` instead of `.to_sql()` to get the AST node for subqueries:

```moonbit nocheck
///|
let stmt : SelectStmt = users.table.select().where_(users.age.gt(18)).build()
```

## Type-safe operators

Operator availability is checked at compile time:

| Column type | `gt` `gte` `lt` `lte` `between` | `like` `not_like` | `eq` `neq` `is_null` |
|-------------|----------------------------------|---------------------|----------------------|
| `Column[Int]` | ✅ | ❌ | ✅ |
| `Column[Double]` | ✅ | ❌ | ✅ |
| `Column[String]` | ❌ | ✅ | ✅ |
| `Column[Bool]` | ❌ | ❌ | ✅ |

```moonbit nocheck
// These compile:
users.age.gt(18)
users.name.like("A%")

// These fail at compile time:
// users.age.like("A%")   // Int does not implement StringMatchable
// users.name.gt(18)      // String does not implement Comparable
```

## Package structure

```
foxql/
├── ast/          # AST types (SelectStmt, Expr, Value, ...)
├── builder/      # Fluent builders (Table, Column, SelectBuilder, ...)
├── tosql/        # SQL rendering
├── schema.mbt    # Dynamic schema (Schema, SchemaTable)
├── foxql.mbt     # Re-exports (Table, Column, SqlType, count, sum, ...)
└── foxql_test.mbt
```

Import the root package for the common surface:

```moonbit nocheck
import { "jaredzhou/foxql" }
```

Or sub-packages for fine-grained control:

```moonbit nocheck
import {
  "jaredzhou/foxql/ast",
  "jaredzhou/foxql/builder",
}
```

## Dynamic schema (SchemaTable)

> **Use only when you need runtime introspection.** For tables with a known, stable structure, prefer the static `Column[T]` proxies — they give you compile-time type safety, operator traits, and zero `abort` risk. `SchemaTable` is for building PostgREST-style dynamic APIs where table schemas are discovered at startup.

```moonbit nocheck
// 1. Introspect on startup (query information_schema in your app)
let schema = Schema::load([
  { table_name: "users", column_name: "id",   sql_type: SqlType::Integer },
  { table_name: "users", column_name: "name", sql_type: SqlType::Text },
  { table_name: "users", column_name: "age",  sql_type: SqlType::Integer },
])

let users = schema.table("users")

// 2. Dynamic column access via .col("name")
let (sql, args) = users
  .select(columns=[users.col("name"), users.col("age")])
  .where_(users.col("age").gt(18).and_(users.col("name").like("A%")))
  .order_by(users.col("name").asc())
  .limit(10)
  .to_sql()
// sql  = "SELECT users.name, users.age FROM users"
//        " WHERE (users.age > $1 AND users.name LIKE $2)"
//        " ORDER BY users.name ASC LIMIT $3"
// args = [18, "A%", 10]

// 3. Mutations work the same way
users.insert([users.col("name"), users.col("age")])
  .values(["Alice", 30])
  .returning([users.col("id")])
  .to_sql()
// sql  = "INSERT INTO users (name, age) VALUES ($1, $2) RETURNING users.id"
// args = ["Alice", 30]

users.update()
  .set(users.col("name"), "Bob")
  .where_(users.col("id").eq(1))
  .to_sql()
// sql  = "UPDATE users SET users.name = $1 WHERE users.id = $2"
// args = ["Bob", 1]
```

`SchemaTable` also implements `FieldResolver`, so queryx `to_select` works with a single argument:

```moonbit nocheck
let query : Query = from_json!(...)
let (sql, args) = to_select(query, users).to_sql()
```
