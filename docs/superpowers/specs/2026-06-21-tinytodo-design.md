# TinyTodo — MoonBit Reimplementation Design

## Overview

Reimplement the [TinyTodo](https://github.com/cedar-policy/cedar-examples/tree/release/4.11.x/tinytodo) example application in MoonBit, using two workspace modules (`pony`, `mooncedar`) to demonstrate Cedar policy-based authorization in a realistic web application.

No persistence — data lives in memory for the server's lifetime (matching the original).

Authentication is demo-simple: `X-User` header names the current user, no JWT, no login endpoint. The focus is on Cedar authorization.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     todo/                            │
│  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │  main.mbt │  │ policies │  │ entities.json     │  │
│  │  (入口)   │  │ .cedar   │  │ (初始 User/Team)  │  │
│  └────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
│       │              │                │              │
│  ┌────┴──────────────┴────────────────┴──────────┐  │
│  │                  Router (pony)                  │  │
│  │        GET/POST/DELETE/PATCH routes            │  │
│  └────────────────────┬───────────────────────────┘  │
│                       │                              │
│              ┌────────┴────────┐                     │
│              │    handlers     │                     │
│              │  list + task    │                     │
│              └────────┬───────┘                     │
│                       │                              │
│           ┌───────────┴───────────┐                  │
│           │       authz.mbt       │                  │
│           │  mooncedar.is_authorized│                │
│           └───────────┬───────────┘                  │
│                       │                              │
│           ┌───────────┴───────────┐                  │
│           │       store.mbt       │                  │
│           │  内存 EntityStore      │                  │
│           │  + List/Task 数据      │                  │
│           └───────────────────────┘                  │
└─────────────────────────────────────────────────────┘

Dependencies:
  todo ──► pony (HTTP router)
  todo ──► mooncedar (authorizer) ──► moonbitlang/x
```

## Entity Types

| Type | Attributes | Notes |
|------|-----------|-------|
| `Application` | (none) | Root singleton `Application::"TinyTodo"` |
| `User` | `location: String`, `joblevel: Int` | 4 predefined users |
| `Team` | (none) | `temp`, `interns`, `admin` |
| `List` | `name: String`, `owner: User`, `readers: Team`, `editors: Team`, `tasks: Set<Task>` | Created at runtime |
| `Task` | `id: Int`, `name: String`, `state: String` | "todo" or "done" |

## Actions & Permissions

| Action | Resource | Owner | Editor | Reader | Anyone |
|--------|----------|-------|--------|--------|--------|
| `CreateList` | `Application` | — | — | — | Permit |
| `GetLists` | `Application` | — | — | — | Permit |
| `GetList` | `List` | Permit | Permit | Permit | Deny |
| `UpdateList` | `List` | Permit | Permit | Deny | Deny |
| `DeleteList` | `List` | Permit | Deny | Deny | Deny |
| `CreateTask` | `List` | Permit | Permit | Deny | Deny |
| `UpdateTask` | `List` | Permit | Permit | Deny | Deny |
| `DeleteTask` | `List` | Permit | Permit | Deny | Deny |
| `EditShare` | `List` | Permit | Deny | Deny | Deny |

## Cedar Policies (4 active, directly ported)

```
// Policy 0: Anyone can create a list or view their lists
permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");

// Policy 1: Owner has full control
permit(principal, action, resource) when { resource.owner == principal };

// Policy 2: Editors and readers can view lists
permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };

// Policy 3: Editors can modify lists and tasks
permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
```

## HTTP API

All requests require `X-User: <username>` header to identify the principal.

### List endpoints

| Method | Path | Body | Cedar Action |
|--------|------|------|-------------|
| POST | `/lists` | `{"name":"..."}` | `CreateList` |
| GET | `/lists` | — | `GetLists` |
| GET | `/lists/:id` | — | `GetList` |
| DELETE | `/lists/:id` | — | `DeleteList` |
| POST | `/lists/:id/share` | `{"target":"User::\"alice\"", "readonly":true}` | `EditShare` |
| DELETE | `/lists/:id/share` | `{"target":"User::\"alice\""}` | `EditShare` |

### Task endpoints

| Method | Path | Body | Cedar Action |
|--------|------|------|-------------|
| POST | `/lists/:id/tasks` | `{"name":"..."}` | `CreateTask` |
| PATCH | `/lists/:id/tasks/:pos` | `{"name":"..."}` or `{"state":"done"}` | `UpdateTask` |
| DELETE | `/lists/:id/tasks/:pos` | — | `DeleteTask` |

### Example

```bash
# Create a list as emina
curl -H "X-User: emina" -X POST localhost:3000/lists -d '{"name":"Shopping"}'

# Share with alice as editor
curl -H "X-User: emina" -X POST localhost:3000/lists/0/share \
  -d '{"target":"User::\"alice\"","readonly":false}'

# Try to delete list as reader (should 403)
curl -H "X-User: kesha" -X DELETE localhost:3000/lists/0
```

## Module Structure

```
todo/
  moon.mod              # jaredzhou/todo@0.1.0
  moon.pkg
  main.mbt              # Server startup, policy loading, entity init
  policies.cedar        # Embedded Cedar policies
  entities.json         # Predefined User + Team entities
  handler/
    moon.pkg
    list.mbt            # List CRUD + share handlers
    task.mbt            # Task CRUD handlers
  auth/
    moon.pkg
    authz.mbt           # is_authorized wrapper + Cedar action/resource constructors
  store/
    moon.pkg
    store.mbt           # In-memory entity store + List/Task storage (ServerState)
```

### Dependencies (`moon.mod`)

```toml
import {
  "jaredzhou/pony@0.1.1",
  "jaredzhou/mooncedar@0.1.1",
  "moonbitlang/core/json",
}
```

### Imports (`moon.pkg`)

```toml
import {
  "jaredzhou/pony",
  "jaredzhou/mooncedar",
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "jaredzhou/mooncedar/parser",
  "moonbitlang/core/json",
}
```

## Data Flow (example: create list)

```
1. Client: POST /lists {"name":"Shopping"}  +  X-User: emina
2. list.mbt handler:
   a. user = ctx.header("X-User")  →  "emina"
   b. req = Request { principal: User::"emina", action: CreateList, resource: Application::"TinyTodo" }
   c. authz.mbt: is_authorized(req, policies.iter(), store)
   d. If Deny → 403
   e. Create List entity, add to store
   f. Return 201 {"id": 0, "name": "Shopping"}
```

## Testing

- Whitebox tests for `store.mbt` (CRUD operations, entity hierarchy)
- Whitebox tests for `authz.mbt` (policy evaluation with known inputs)
- Integration tests via `moon test` — create lists, share, attempt unauthorized access

## Out of Scope

- JWT / real authentication (demo uses `X-User` header for simplicity)
- Schema validation (mooncedar doesn't support `.cedarschema` yet)
- Policy templates (mooncedar doesn't support `Slot` evaluation yet)
- Permanent storage
- The 3 commented-out bonus policies (admin omnipotence, intern restrictions, joblevel/location)
