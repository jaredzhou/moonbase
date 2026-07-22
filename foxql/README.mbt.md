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
```

## SELECT

```moonbit nocheck
// SELECT * FROM users
users.table.select().to_sql()

// SELECT name, age FROM users
users.table.select(columns=[users.name, users.age]).to_sql()

// SELECT * FROM users WHERE age = 18
users.table.select().where_(users.age.eq(18)).to_sql()
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
users.age.between(18, 65)
users.name.like("Al%")
users.name.is_null()
users.age.in_([1, 2, 3])
```

### Condition composition

```moonbit nocheck
// AND / OR — chainable, flattens automatically
users.age.gte(18).and_(users.age.lte(65))
users.name.eq("Alice").or_(users.name.eq("Bob"))

// NOT — standalone function
not_(users.age.eq(0))

// Complex nesting
users.age.lt(18).or_(users.age.gt(65)).and_(users.name.is_not_null())
```

### ORDER BY, LIMIT, OFFSET, DISTINCT

```moonbit nocheck
users.table.select()
  .order_by(users.name.asc())
  .order_by(users.age.desc())
  .limit(10)
  .offset(20)
  .to_sql()

// DISTINCT / DISTINCT ON
users.table.select(columns=[users.name]).distinct().to_sql()
users.table.select(columns=[users.name, users.age]).distinct_on([users.name]).to_sql()
```

## INSERT / UPDATE / DELETE

### INSERT

```moonbit nocheck
// Single row
users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .to_sql()

// Multi-row
users.table.insert([users.name, users.age])
  .rows([["Alice", 30], ["Bob", 25]])
  .to_sql()

// With RETURNING
users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .returning([users.id])
  .to_sql()
```

### UPDATE

Type-state enforced: `.where_()` is **required** before `.to_sql()`.

```mbt nocheck
users.table.update()
  .set(users.name, "Dave")
  .set(users.age, 99)
  .where_(users.id.eq(1))
  .returning([users.id, users.name])
  .to_sql()
```

### DELETE

Type-state enforced: `.where_()` is **required** before `.to_sql()`.

```mbt nocheck
users.table.delete()
  .where_(users.age.lt(18))
  .returning([users.id])
  .to_sql()
```

### ON CONFLICT (upsert)

```mbt nocheck
// DO NOTHING
users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .on_conflict([users.name])
  .do_nothing()
  .to_sql()

// DO UPDATE
users.table.insert([users.name, users.age])
  .values(["Alice", 30])
  .on_conflict([users.name])
  .do_update(users.age, 30)
  .to_sql()
```

## JOIN

```moonbit nocheck
struct OrdersTable {
  table : Table
  id : Column[Int]
  user_id : Column[Int]
  amount : Column[Int]
}

let orders : OrdersTable = {
  table: Table::new("orders"),
  id: Column::new("id", "orders", SqlType::Integer),
  user_id: Column::new("user_id", "orders", SqlType::Integer),
  amount: Column::new("amount", "orders", SqlType::Integer),
}

// INNER JOIN with ON condition (column-to-column via eq_col)
users.table
  .select(columns=[users.name, orders.amount])
  .join(orders.table, users.id.eq_col(orders.user_id))
  .where_(orders.amount.gt(100))
  .order_by(orders.amount.desc())
  .to_sql()
// SELECT users.name, orders.amount
// FROM users
// INNER JOIN orders ON users.id = orders.user_id
// WHERE orders.amount > $1
// ORDER BY orders.amount DESC
```

## Aggregation & GROUP BY

```moonbit nocheck
// Aggregation functions: count, sum, avg, min, max, count_star
orders.table
  .select(columns=[orders.user_id])
  .agg(sum(orders.amount))
  .agg(count_star())
  .group_by([orders.user_id])
  .having(sum(orders.amount).gt(1000))
  .order_by(orders.user_id.asc())
  .to_sql()
// SELECT orders.user_id, SUM(orders.amount), COUNT(*)
// FROM orders
// GROUP BY orders.user_id
// HAVING SUM(orders.amount) > $1
// ORDER BY orders.user_id ASC
```

## Subqueries

```moonbit nocheck
// WHERE … IN (SELECT …)
let sub = orders.table.select(columns=[orders.user_id]).where_(orders.amount.gt(100)).build()
users.table.select().where_(users.id.in_select(sub)).to_sql()

// Scalar subquery
let max_age = users.table.select(columns=[users.age]).order_by(users.age.desc()).limit(1).build()
users.table.select().where_(users.age.eq_select(max_age)).to_sql()
```

## Schema-qualified tables

```moonbit nocheck
///|
let table = Table::new("profiles", schema="public")
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
