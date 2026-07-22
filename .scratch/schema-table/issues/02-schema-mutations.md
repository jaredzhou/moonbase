# 02 — SchemaTable insert / update / delete

**What to build:** Mutation builders on `SchemaTable` — INSERT, UPDATE (type-state: WHERE required), DELETE (type-state: WHERE required), all with RETURNING support.

**Blocked by:** 01 (Schema + SchemaTable + SELECT)

**Status:** ready-for-agent

- [ ] `SchemaTable::insert(columns)` returns `InsertBuilder`, with `.values()` / `.rows()` / `.returning()`
- [ ] `SchemaTable::update()` returns `UpdateBuilder`, `.to_sql()` gated by `.where_()`
- [ ] `SchemaTable::delete()` returns `DeleteBuilder`, `.to_sql()` gated by `.where_()`
- [ ] Blackbox tests: insert, update with where, delete with where, returning on all three
- [ ] moon check and moon test pass
