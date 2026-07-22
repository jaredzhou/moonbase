## Problem Statement

Moonstore currently builds SQL queries by hand — raw strings with manual parameter interpolation. This is error-prone: typos in column names, wrong WHERE clause shape, SQL injection vectors, and no compile-time guard that column types match value types. Each query requires careful string concatenation, and refactoring a table schema means hunting down every raw SQL string that references the changed columns.

## Solution

FoxQL — a compile-time type-safe SQL builder for PostgreSQL. Users define a `TableProxy` struct per database table (hand-written, no code generation), then compose queries via fluent builder chains. The builder produces parameterized SQL (`$1`, `$2`, …) with a separate args array, preventing injection. Column types constrain which operators are available (`Int` columns get `gt`/`lt`, `String` columns get `like`). The compiler catches type mismatches before runtime.

## User Stories

1. As a Moonstore developer, I want to build a SELECT query with typed WHERE conditions, so that column-type mismatches are caught at compile time rather than at runtime.
2. As a Moonstore developer, I want the SQL builder to automatically parameterize values (`$1`, `$2`, …), so that I don't accidentally introduce SQL injection via string interpolation.
3. As a Moonstore developer, I want to define a table schema once (table name, columns, types) and reuse it across all queries, so that renaming a column is a single edit with compiler-verified consistency.
4. As a Moonstore developer, I want to compose WHERE conditions with method chaining (`col.gt(18).and(col.lt(65))`), so that complex filter logic reads naturally and is composable.
5. As a Moonstore developer, I want INSERT to accept column-value pairs in a specific order, so that the generated SQL column list and VALUES list are guaranteed to align.
6. As a Moonstore developer, I want DELETE and UPDATE to require a WHERE clause at the type level, so that I can't accidentally issue a `DELETE FROM users` without a filter.
7. As a Moonstore developer, I want JOIN support (INNER JOIN at minimum), so that I can express queries spanning multiple tables without dropping to raw SQL.
8. As a Moonstore developer, I want RETURNING clauses on INSERT/UPDATE/DELETE, so that I can retrieve server-generated values (IDs, timestamps) in a single round-trip.
9. As a Moonstore developer, I want ORDER BY, LIMIT, OFFSET, and DISTINCT on SELECT, so that I can control result ordering and pagination.
10. As a Moonstore developer, I want GROUP BY with HAVING and basic aggregation functions (COUNT, SUM, AVG, MIN, MAX), so that I can express aggregate queries.
11. As a Moonstore developer, I want ON CONFLICT (upsert) support for INSERT, so that I can express idempotent writes without raw SQL.
12. As a Moonstore developer, I want subqueries to appear in WHERE … IN clauses, so that I can express correlated filters.
13. As a Moonstore developer, I want `select()` with no arguments to emit `SELECT *`, so that simple "fetch all columns" queries are concise.
14. As a Moonstore developer, I want an escape hatch (`raw(String)`) for SQL fragments that can't be expressed through the builder, so that I'm never completely blocked by the type system.
15. As a Moonstore developer, I want the builder's `.to_sql()` method to return both the SQL string and the params array as a tuple, so that I can pass them directly to `pg_client.query(sql, args)`.
16. As a Moonstore developer, I want string columns to support `like`, `ilike`, and `not_like`, so that I can express pattern-matching WHERE conditions.
17. As a Moonstore developer, I want columns to support `in_` (with a list of values or a subquery) and `between`, so that I can express range and membership filters.
18. As a Moonstore developer, I want nullable columns to support `is_null()` and `is_not_null()`, so that I can filter on presence/absence of values.

## Implementation Decisions

**PostgreSQL-only.** Uses `$N` parameter placeholders, `RETURNING`, `ON CONFLICT`, `DISTINCT ON`, `JSONB`, `TIMESTAMPTZ`. No multi-dialect abstraction — the workspace is already PG-locked.

**Hand-written schema, no code generation.** Each table is a concrete struct embedding a shared `Table` (runtime metadata) and typed `Column[T]` fields. MoonBit traits lack associated types, making a pure-trait `Table` abstraction impossible without code generation — rejected to keep the toolchain simple.

**AnyColumn trait for heterogeneous column lists.** `select()` accepts `Array[AnyColumn]` — a trait that erases the `T` from `Column[T]`, exposing only column identity (name, table, SQL type). This means `select([users.name, users.age])` compiles, but cross-table column mixing in `select` is not caught at compile time — a deliberate trade-off since MoonBit has no variadic generics.

**Fluent builder API.** Method chaining ending with `.to_sql() -> (String, Array[Value])`. No callback style. Builders return new intermediate types to enforce ordering constraints (e.g., DELETE must call `.where_()` before `.to_sql()`).

**Type-state machine for DELETE/UPDATE.** `DeleteBuilder` and `UpdateBuilder` do not expose `.to_sql()` — only the type returned by `.where_()` does. This forces a WHERE clause at compile time.

**ToSql trait in separate sub-package.** Lives in `tosql/` to break circular imports: `builder/` constructs AST nodes, `ast/` defines the node types, `tosql/` implements `ToSql` for all AST nodes and depends on both.

**INSERT uses `~` operator for column-value pairing.** Syntax: `users.insert(users.name ~ "张三", users.age ~ 18)`. Order is preserved in the generated SQL column list and VALUES tuple.

**Module structure:**

```
foxql/
├── moon.mod
├── moon.pkg
├── ast/
│   ├── moon.pkg
│   ├── expr.mbt         # AST nodes: Select, Insert, Update, Delete, Condition, Join
│   ├── types.mbt        # SqlType, ColumnMeta, TableMeta
│   └── operator.mbt     # Operator enum: Eq, Neq, Gt, Gte, Lt, Lte, Like, In, Between, IsNull…
├── builder/
│   ├── moon.pkg
│   ├── select.mbt       # SelectBuilder
│   ├── insert.mbt       # InsertBuilder
│   ├── update.mbt       # UpdateBuilder
│   ├── delete.mbt       # DeleteBuilder
│   ├── condition.mbt    # Condition builder (and/or/not)
│   └── column.mbt       # Column[T], AnyColumn trait, operator traits
├── schema/
│   ├── moon.pkg
│   └── table.mbt        # Table struct
├── tosql/
│   ├── moon.pkg
│   └── tosql.mbt        # ToSql trait, impl for all AST nodes
├── foxql.mbt            # Top-level pub API re-exports
└── foxql_test.mbt
```

**Type mappings:**

| MoonBit | PostgreSQL |
|---------|-----------|
| `Int` | `INTEGER` / `BIGINT` |
| `String` | `TEXT` |
| `Bool` | `BOOLEAN` |
| `Float` | `DOUBLE PRECISION` |
| `Bytes` | `BYTEA` |
| `@datetime.DateTime` | `TIMESTAMPTZ` |
| `Decimal` | `NUMERIC` |
| `Json` | `JSONB` |
| `T?` | Column allows `NULL` |

**WHERE operators by column type:**
- `Column[Int]` / `Column[Float]`: `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, `in_`, `between`, `is_null`
- `Column[String]`: `eq`, `neq`, `like`, `in_`, `is_null`
- `Column[Bool]`: `eq`, `neq`, `is_null`
- All columns share `eq`, `neq`, `is_null`, `is_not_null`

Exact trait decomposition for these operator groups is deferred to implementation.

**Parameterization strategy.** User-supplied values become `$N` placeholders. Identifiers (column names, table names, `ASC`/`DESC`) are spliced directly. `raw(String)` escapes directly into the SQL string.

**Single statement only.** Each builder chain produces exactly one SQL statement. Transaction management (`BEGIN`/`COMMIT`/`ROLLBACK`) is the caller's responsibility.

### API Sketch (illustrative, not final)

```moonbit
// Schema definition (user writes once per table)
struct UserTable {
  table : Table
  id : Column[Int]
  name : Column[String]
  age : Column[Int]
}

// Usage
let users = UserTable::new()

// SELECT
let sql, args = users
  .select([users.name, users.age])
  .where_(users.age.gt(18).and(users.name.like("%foo%")))
  .order_by(users.age.desc())
  .limit(10)
  .to_sql()

// INSERT
let sql, args = users
  .insert(users.name ~ "张三", users.age ~ 18)
  .returning([users.id])
  .to_sql()

// UPDATE (WHERE required)
let sql, args = users
  .update(users.name ~ "李四")
  .where_(users.id.eq(1))
  .to_sql()

// DELETE (WHERE required)
let sql, args = users
  .delete()
  .where_(users.age.lt(18))
  .to_sql()
```

## Testing Decisions

**Single seam: `to_sql() -> (String, Array[Value])`.** Blackbox tests only — construct a builder chain, call `.to_sql()`, assert on the output. Uses `inspect()`-based snapshot tests, consistent with existing codebase convention (see queryx `queryx_test.mbt`, libs `url/url_test.mbt`).

**What makes a good test:**
- Test external behavior only — the SQL string and args output
- Do not test internal AST node shapes or builder implementation details
- Exercise edge cases: empty WHERE, deeply nested AND/OR, NULL handling, subquery in WHERE … IN, JOIN + WHERE combination
- Error cases: verify that type-state builders reject illegal method sequences at compile time (these are validated by `moon check`, not by runtime test code)

**Test files:**
- `foxql_test.mbt` — blackbox tests covering SELECT/INSERT/UPDATE/DELETE end-to-end, plus WHERE operators, JOIN, subqueries, GROUP BY/HAVING, ORDER BY/LIMIT/OFFSET, DISTINCT, ON CONFLICT, RETURNING

**Prior art:**
- `queryx/queryx_test.mbt` — inspect-based round-trip and error tests, flat structure
- `libs/url/url_test.mbt` and `libs/url/url_wbtest.mbt` — blackbox + whitebox split

## Out of Scope

- **Code generation tool.** Schema definitions are hand-written. No `.json`/`.yaml` → `.mbt` generator.
- **Multi-dialect support.** PostgreSQL only. MySQL, SQLite, etc. are not targeted.
- **Transaction management.** `BEGIN`/`COMMIT`/`ROLLBACK` are the caller's responsibility.
- **LEFT/RIGHT/CROSS JOIN.** INNER JOIN only for initial implementation.
- **Schema migration / DDL.** `CREATE TABLE`, `ALTER TABLE`, etc. are out of scope. FoxQL is a query builder, not a schema manager.
- **Runtime query validation.** No connection to a live database. FoxQL produces SQL strings; correctness of the generated SQL against the actual schema is the caller's responsibility.
- **Multi-statement batches.** One SQL statement per builder chain.
- **Streaming / cursor results.** FoxQL produces SQL; the caller executes it and handles result iteration.

## Further Notes

- The ADR at `foxql/docs/adr/0001-foxql-sql-builder-design.md` records the key architectural trade-offs (hand-written schema, PG-only, AnyColumn erasure).
- The glossary at `foxql/CONTEXT.md` defines canonical terms: `Column[T]`, `AnyColumn`, `Table`, `TableProxy`, `Condition`, `ToSql`, `Type-state builder`, etc.
- The workspace `moon.work` already includes `./queryx` as a member. FoxQL should be added similarly as `./foxql`.
- FoxQL targets `native` (like `moonstore` and `libs`), not `wasm-gc` (unlike `queryx`).
- All MoonBit conventions apply: run `moon fmt`, `moon check`, `moon test --all`, and `moon info` before committing. Use `///|` block separators for independent processing.
