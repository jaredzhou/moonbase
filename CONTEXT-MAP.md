# Context Map

## Contexts

- [FoxQL](./foxql/CONTEXT.md) — PostgreSQL SQL builder with compile-time type safety
- [Libs](./libs/CONTEXT.md) — shared libraries (URL parser, JWT)
- [Moonstore](./moonstore/CONTEXT.md) — object storage service with S3-style HTTP API
- [Queryx](./queryx/CONTEXT.md) — query expression module (TODO: define)

## Relationships

- **FoxQL → Moonstore**: FoxQL may be used by Moonstore as its SQL generation layer for PostgreSQL queries, replacing raw SQL strings.
- **FoxQL is independent of other contexts**: No other module depends on FoxQL. It is a standalone utility.
- **Libs → Moonstore**: Moonstore imports `jaredzhou/libs` for URL and JWT utilities.
- **Queryx is independent**: currently a standalone query expression module.
