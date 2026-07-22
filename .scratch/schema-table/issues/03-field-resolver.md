# 03 — FieldResolver for SchemaTable

**What to build:** `SchemaTable` implements `FieldResolver` so a queryx `Query` can be converted to a foxql `SelectBuilder` via `to_select(query, table)` — JSON filter → field validation → SQL, in one step.

**Blocked by:** 01 (Schema + SchemaTable + SELECT)

**Status:** ready-for-agent

- [ ] `impl FieldResolver for SchemaTable` — `resolve_column` validates field exists in schema and returns `ColumnRef`; `table_name` returns the table name
- [ ] `to_select(query, resolver)` end-to-end: JSON → queryx → field validation → foxql SelectBuilder
- [ ] Blackbox tests: full WHERE conditions from JSON, ORDER BY, LIMIT via page, unknown field raises
- [ ] moon check and moon test pass
