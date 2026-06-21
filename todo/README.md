# TinyTodo

A demo application demonstrating Cedar policy-based authorization in MoonBit. Uses [pony](https://mooncakes.io/packages/jaredzhou/pony) for HTTP routing and [mooncedar](https://mooncakes.io/packages/jaredzhou/mooncedar) for Cedar policy evaluation.

## Quick Start

```bash
# Terminal 1: Start the server
moon run ./todo

# Terminal 2: Use the CLI client
moon run ./todo/client emina new Shopping
moon run ./todo/client emina list
moon run ./todo/client emina task 0 "Buy milk"
moon run ./todo/client emina share 0 aaron
moon run ./todo/client emina share 0 kesha editor
moon run ./todo/client aaron list
moon run ./todo/client aaron toggle 0 0
```

Server starts on `127.0.0.1:3000`.

## CLI Client Commands

```bash
moon run ./todo/client <user> <cmd> [args...]

  list                        view accessible lists
  view  <id>                  view a list with tasks
  new   <name>                create a new list
  done  <id>                  delete a list
  task  <list> <name>         add a task
  toggle <list> <pos>         toggle task done/todo
  del   <list> <pos>          delete a task
  share <list> <user> [editor]   share (default: readonly)
  unshare <list> <user>           unshare
```

## REST API (curl)

All requests use `X-User` header:

```bash
# Create a list
curl -H "X-User: emina" -X POST localhost:3000/lists -d '{"name":"Shopping"}'
# {"id":0,"name":"Shopping"}

# View your lists
curl -H "X-User: emina" localhost:3000/lists

# Share with aaron as editor
curl -H "X-User: emina" -X POST localhost:3000/lists/0/share \
  -d '{"target":"aaron","readonly":false}'

# aaron adds a task
curl -H "X-User: aaron" -X POST localhost:3000/lists/0/tasks \
  -d '{"name":"Buy milk"}'

# kesha tries to view — denied (403)
curl -H "X-User: kesha" localhost:3000/lists/0
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/lists` | Create a list |
| GET | `/lists` | List accessible lists |
| GET | `/lists/:id` | View a list with tasks |
| DELETE | `/lists/:id` | Delete a list (owner only) |
| POST | `/lists/:id/share` | Share/unshare a list |
| POST | `/lists/:id/tasks` | Add a task |
| PATCH | `/lists/:id/tasks/:pos` | Update task name/state |
| DELETE | `/lists/:id/tasks/:pos` | Delete a task |

## Authorization Model

| Role | CreateTask | GetList | UpdateTask | DeleteTask | DeleteList | Share |
|------|-----------|---------|------------|------------|------------|-------|
| Owner | Permit | Permit | Permit | Permit | Permit | Permit |
| Editor | Permit | Permit | Permit | Permit | Deny | Deny |
| Reader | Deny | Permit | Deny | Deny | Deny | Deny |
| Anyone | CreateList | — | — | — | — | — |

## Cedar Policies

```
permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");
permit(principal, action, resource) when { resource.owner == principal };
permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };
permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
```

## Pre-defined Users

| User | Teams | Location | Job Level |
|------|-------|----------|-----------|
| emina | admin | DEF33 | 8 |
| aaron | interns | ABC17 | 5 |
| andrew | admin, temp | XYZ77 | 5 |
| kesha | temp | ABC17 | 5 |
