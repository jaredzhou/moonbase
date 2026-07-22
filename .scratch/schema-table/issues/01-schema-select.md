# 01 — Schema + SchemaTable + SELECT

**What to build:** Load table metadata into a `Schema`, get a dynamic `SchemaTable` by name, build and render a SELECT query end-to-end. A real PG table → schema introspection → `.col("name").select().to_sql()` verified in tests.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

- [ ] `Schema::load` accepts `Array[SchemaColumn]` and builds a table→column→SqlType index
- [ ] `Schema::table("name")` returns `SchemaTable`, verifying the table exists
- [ ] `SchemaTable::col("name")` returns `ColumnRef` with table name filled in; unknown column aborts
- [ ] `SchemaTable::select(columns?)` returns `SelectBuilder`, reusing all existing foxql clauses
- [ ] `FieldResolver` trait gains `table_name(Self) -> String`
- [ ] `to_select` signature simplified to `(query, resolver)`, using `resolver.table_name()` internally
- [ ] Blackbox test: create a real PG table, introspect it, `.col("name").select().where_(col.gt(18)).to_sql()` produces correct SQL with matching args
- [ ] moon check and moon test pass
