# TinyTodo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a TinyTodo HTTP server in MoonBit using Cedar policy-based authorization with pony (router) and mooncedar (authorizer).

**Architecture:** Modular: store layer holds mutable state + Cedar entity store. Handlers read the `X-User` header, construct Cedar `Request`, call `authz.mbt` for authorization, then mutate state. `main.mbt` wires everything.

**Tech Stack:** MoonBit native target, `jaredzhou/pony@0.1.1`, `jaredzhou/mooncedar@0.1.1`, `moonbitlang/core/json`.

## Global Constraints

- Auth: `X-User` header, no JWT or /login endpoint
- No persistence: data lives in memory
- No schema validation or policy templates
- 4 active Cedar policies only (directly ported from original)
- 4 predefined users (`emina`, `aaron`, `andrew`, `kesha`), 3 teams (`temp`, `interns`, `admin`)
- All handlers return JSON responses
- Target: native

---

### Task 1: Module Scaffold

**Files:**
- Create: `todo/moon.mod`
- Create: `todo/moon.pkg`
- Create: `todo/store/moon.pkg`
- Create: `todo/auth/moon.pkg`
- Create: `todo/handler/moon.pkg`
- Modify: `moon.work`

**Interfaces:**
- Produces: Module `jaredzhou/todo@0.1.0` with imports to pony, mooncedar, core/json. Workspace includes `./todo`.

- [ ] **Step 1: Create `todo/moon.mod`**

```toml
name = "jaredzhou/todo"
version = "0.1.0"
license = "Apache-2.0"
description = "TinyTodo — Cedar policy-based authorization demo"
repository = "https://github.com/jaredzhou/moonbase"
preferred_target = "native"
readme = "README.md"

import {
  "jaredzhou/pony@0.1.1",
  "jaredzhou/mooncedar@0.1.1",
  "moonbitlang/core/json",
}
```

- [ ] **Step 2: Create `todo/moon.pkg`**

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

- [ ] **Step 3: Create `todo/store/moon.pkg`**

```toml
import {
  "jaredzhou/mooncedar",
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "moonbitlang/core/json",
}
```

- [ ] **Step 4: Create `todo/auth/moon.pkg`**

```toml
import {
  "jaredzhou/mooncedar",
  "jaredzhou/mooncedar/evaluator",
  "jaredzhou/mooncedar/ast",
  "jaredzhou/mooncedar/parser",
}
```

- [ ] **Step 5: Create `todo/handler/moon.pkg`**

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

- [ ] **Step 6: Add `./todo` to `moon.work` members**

```toml
members = [
  "./pony",
  "./libs",
  "./mooncedar",
  "./todo",
]
```

- [ ] **Step 7: Run `moon update` and `moon check`**

```bash
moon update && moon check
```
Expected: 0 errors.

- [ ] **Step 8: Commit**

```bash
git add todo/ moon.work
git commit -m "feat(todo): scaffold module with dependencies"
```

---

### Task 2: Store Layer

**Files:**
- Create: `todo/store/store.mbt`
- Create: `todo/store/store_wbtest.mbt`

**Interfaces:**
- Produces:
  - `ServerState::{ policies, entities }` with `pub fn init(policies_src: String, entities_src: String) -> ServerState`
  - `pub(all) struct ListData { pub id : Int, pub mut name : String, pub mut owner : String, pub mut readers : Array[String], pub mut editors : Array[String], pub mut tasks : Array[TaskData] }`
  - `pub(all) struct TaskData { pub id : Int, pub mut name : String, pub mut state : TaskState }`
  - `pub(all) enum TaskState { Todo, Done }`
  - `pub fn list_to_entity(l : ListData) -> @ast.Entity`
  - `pub fn add_list(state : ServerState, l : ListData) -> Unit`
  - `pub fn update_list_entity(state : ServerState, l : ListData) -> Unit`

**Design note:** `ServerState` wraps a mutable `Array[ListData]` for application logic plus a `@evaluator.MapEntityStore` (the Cedar entity store) for authorization. Base entities (Application, Users, Teams) are loaded once at init. List entities are synced into the store on every mutation so Cedar policy evaluation always sees current data.

- [ ] **Step 1: Write failing tests for `store_wbtest.mbt`**

```mbt
///|
test "init loads base entities" {
  let policies_src = (#|permit(principal,action,resource);|)
  let entities_src = (#|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":["String","DEF33"],"joblevel":["Long",8]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]}]|)
  let state = init(policies_src, entities_src)
  @debug.assert_eq(1, state.policies.length())
  // Entity store should have Application and User
  let app = state.entities.get_entity(@ast.EntityUID::{ type_: "Application", id: "TinyTodo" })
  @debug.assert_eq(true, app.is_some())
  let user = state.entities.get_entity(@ast.EntityUID::{ type_: "User", id: "emina" })
  @debug.assert_eq(true, user.is_some())
}

///|
test "init loads team hierarchy" {
  let policies_src = (#|permit(principal,action,resource);|)
  let entities_src = (#|[{"uid":{"type":"Team","id":"temp"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"interns"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]}]|)
  let state = init(policies_src, entities_src)
  let interns = state.entities.get_entity(@ast.EntityUID::{ type_: "Team", id: "interns" })
  @debug.assert_eq(true, interns.is_some())
  @debug.assert_eq(2, interns.unwrap().parents.length())
}

///|
test "add_list updates entity store" {
  let state = empty_state()
  let list = ListData::{ id: 0, name: "Shopping", owner: "emina" }
  add_list(state, list)
  let entity = state.entities.get_entity(@ast.EntityUID::{ type_: "List", id: "0" })
  @debug.assert_eq(true, entity.is_some())
  let e = entity.unwrap()
  @debug.assert_eq("Shopping", match e.attrs["name"] { @ast.Value::String(s) => s; _ => "" })
  // owner attribute is an EntityUID value pointing to User::"emina"
  match e.attrs["owner"] {
    @ast.Value::EntityUID(uid) => @debug.assert_eq("emina", uid.id)
    _ => @debug.fail()
  }
}

///|
test "list_to_entity builds correct entity structure" {
  let list = ListData::{
    id: 5,
    name: "Work",
    owner: "emina",
    readers: ["aaron"],
    editors: ["andrew"],
    tasks: [TaskData::{ id: 0, name: "Buy milk", state: Todo }],
  }
  let entity = list_to_entity(list)
  @debug.assert_eq("List", entity.uid.type_)
  @debug.assert_eq("5", entity.uid.id)
  // Check parent is Application::"TinyTodo"
  @debug.assert_eq("Application", entity.parents[0].type_)
  @debug.assert_eq("TinyTodo", entity.parents[0].id)
}

///|
test "update_list_entity reflects changes" {
  let state = empty_state()
  let mut list = ListData::{ id: 0, name: "Shopping", owner: "emina" }
  add_list(state, list)
  list.readers.push("aaron")
  update_list_entity(state, list)
  let entity = state.entities.get_entity(@ast.EntityUID::{ type_: "List", id: "0" }).unwrap()
  match entity.attrs["readers"] {
    @ast.Value::Set(refs) => @debug.assert_eq(1, refs.length())
    _ => @debug.fail()
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
moon test --package jaredzhou/todo
```
Expected: FAIL (types/functions not defined).

- [ ] **Step 3: Write `todo/store/store.mbt`**

```mbt
// Core data types for TinyTodo — in-memory state + entity store.

///|
pub(all) enum TaskState { Todo, Done } derive(Debug, Eq)

///|
pub(all) struct TaskData {
  pub id : Int
  pub mut name : String
  pub mut state : TaskState
} derive(Debug, Eq)

///|
pub(all) struct ListData {
  pub id : Int
  pub mut name : String
  pub mut owner : String
  pub mut readers : Array[String]
  pub mut editors : Array[String]
  pub mut tasks : Array[TaskData]
} derive(Debug)

///|
pub fn new_list(id : Int, name : String, owner : String) -> ListData {
  ListData::{ id, name, owner, readers: [], editors: [], tasks: [] }
}

///|
pub(all) struct ServerState {
  pub mut lists : Array[ListData]
  pub entities : @evaluator.MapEntityStore
  pub policies : Array[@ast.Policy]
}

///|
/// Build a Cedar Entity from a ListData, for storing in the entity store.
pub fn list_to_entity(l : ListData) -> @ast.Entity {
  let mut attrs = Map([
    ("name", @ast.Value::String(l.name)),
    (
      "owner",
      @ast.Value::EntityUID(@ast.EntityUID::{ type_: "User", id: l.owner }),
    ),
  ])
  attrs["readers"] = user_set(l.readers)
  attrs["editors"] = user_set(l.editors)
  attrs["tasks"] = task_set(l.tasks)
  @ast.Entity::{
    uid: @ast.EntityUID::{ type_: "List", id: l.id.to_string() },
    attrs,
    tags: Map([]),
    parents: [@ast.EntityUID::{ type_: "Application", id: "TinyTodo" }],
  }
}

///|
fn user_set(usernames : Array[String]) -> @ast.Value {
  let mut arr = []
  for u in usernames {
    arr.push(@ast.Value::EntityUID(@ast.EntityUID::{ type_: "User", id: u }))
  }
  @ast.Value::Set(arr)
}

///|
fn task_set(tasks : Array[TaskData]) -> @ast.Value {
  let mut arr = []
  for t in tasks {
    let state_str = match t.state {
      Todo => "todo"
      Done => "done"
    }
    arr.push(@ast.Value::Record(Map([
      ("id", @ast.Value::Long(t.id.to_int64())),
      ("name", @ast.Value::String(t.name)),
      ("state", @ast.Value::String(state_str)),
    ])))
  }
  @ast.Value::Set(arr)
}

///|
pub fn add_list(state : ServerState, l : ListData) -> Unit {
  let entity = list_to_entity(l)
  state.entities.entities.set(entity.uid, entity)
  state.lists.push(l)
}

///|
pub fn update_list_entity(state : ServerState, l : ListData) -> Unit {
  let entity = list_to_entity(l)
  state.entities.entities.set(entity.uid, entity)
}

///|
pub fn empty_state() -> ServerState {
  init(
    (#|permit(principal,action,resource);|),
    (#|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]}]|),
  )
}

///|
/// Load base entities from JSON and parse Cedar policies.
pub fn init(policies_src : String, entities_src : String) -> ServerState {
  let policies = @parser.parse_policies(policies_src)
  let store : @evaluator.MapEntityStore = @json.from_json(@json.parse(entities_src))
  ServerState::{ lists: [], entities: store, policies }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
moon test --package jaredzhou/todo
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add todo/store/
git commit -m "feat(todo): store layer — ServerState, ListData, TaskData, entity sync"
```

---

### Task 3: Auth Layer

**Files:**
- Create: `todo/auth/authz.mbt`
- Create: `todo/auth/authz_wbtest.mbt`

**Interfaces:**
- Produces:
  - `pub fn try_authorize(user: String, action_type: String, action_id: String, resource_type: String, resource_id: String, state: ServerState) -> Bool`
  - `pub fn authorize_or_fail(user: String, action_type: String, action_id: String, resource_type: String, resource_id: String, state: ServerState) -> Unit raise String`

- [ ] **Step 1: Write failing tests for `authz_wbtest.mbt`**

```mbt
///|
fn test_policies() -> String {
  #|permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");
permit(principal, action, resource) when { resource.owner == principal };
permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };
permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
  |#
}

///|
fn test_entities() -> String {
  #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":["String","DEF33"],"joblevel":["Long",8]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{"location":["String","ABC17"],"joblevel":["Long",5]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"admin"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]}]
}

///|
test "anyone can CreateList" {
  let state = @store.init(test_policies(), test_entities())
  @debug.assert_eq(true, try_authorize("aaron", "Action", "CreateList", "Application", "TinyTodo", state))
}

///|
test "owner has full control on own list" {
  let state = @store.init(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  // Owner can GetList
  @debug.assert_eq(true, try_authorize("emina", "Action", "GetList", "List", "0", state))
  // Owner can DeleteList
  @debug.assert_eq(true, try_authorize("emina", "Action", "DeleteList", "List", "0", state))
}

///|
test "non-owner, non-reader cannot GetList" {
  let state = @store.init(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  // aaron is not owner, not reader, not editor
  @debug.assert_eq(false, try_authorize("aaron", "Action", "GetList", "List", "0", state))
}

///|
test "reader can GetList but not DeleteList" {
  let state = @store.init(test_policies(), test_entities())
  let mut list = @store.new_list(0, "MyList", "emina")
  list.readers.push("aaron")
  @store.add_list(state, list)
  @debug.assert_eq(true, try_authorize("aaron", "Action", "GetList", "List", "0", state))
  @debug.assert_eq(false, try_authorize("aaron", "Action", "DeleteList", "List", "0", state))
}

///|
test "editor can CreateTask and UpdateTask" {
  let state = @store.init(test_policies(), test_entities())
  let mut list = @store.new_list(0, "MyList", "emina")
  list.editors.push("aaron")
  @store.add_list(state, list)
  @debug.assert_eq(true, try_authorize("aaron", "Action", "CreateTask", "List", "0", state))
  @debug.assert_eq(true, try_authorize("aaron", "Action", "UpdateTask", "List", "0", state))
}

///|
test "authorize_or_fail raises on deny" {
  let state = @store.init(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  let raised = try {
    authorize_or_fail("aaron", "Action", "DeleteList", "List", "0", state)
    false
  } catch {
    _ => true
  }
  @debug.assert_eq(true, raised)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
moon test --package jaredzhou/todo
```
Expected: FAIL (functions not defined).

- [ ] **Step 3: Write `todo/auth/authz.mbt`**

```mbt
// Authorization wrapper — builds Cedar requests and calls mooncedar.

///|
/// Check if the given user is authorized to perform an action on a resource.
/// Returns true if authorized, false if denied.
pub fn try_authorize(
  user : String,
  action_type : String,
  action_id : String,
  resource_type : String,
  resource_id : String,
  state : @store.ServerState,
) -> Bool {
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("User", user),
    action: @evaluator.concrete_uid(action_type, action_id),
    resource: @evaluator.concrete_uid(resource_type, resource_id),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let result = is_authorized(req, state.policies.iter(), state.entities)
  result.decision == Decision::Allow
}

///|
/// Authorize or raise a string error message.
pub fn authorize_or_fail(
  user : String,
  action_type : String,
  action_id : String,
  resource_type : String,
  resource_id : String,
  state : @store.ServerState,
) -> Unit {
  if not(try_authorize(user, action_type, action_id, resource_type, resource_id, state)) {
    raise "403: access denied"
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
moon test --package jaredzhou/todo
```
Expected: PASS (6 authz tests + 5 store tests = 11 total).

- [ ] **Step 5: Commit**

```bash
git add todo/auth/
git commit -m "feat(todo): auth layer — try_authorize, authorize_or_fail"
```

---

### Task 4: List Handlers

**Files:**
- Create: `todo/handler/list.mbt`
- Create: `todo/handler/list_wbtest.mbt`

**Interfaces:**
- Consumes: `@store.ServerState`, `@store.ListData`, `@store.add_list`, `@store.update_list_entity`, `@auth.try_authorize`, `@auth.authorize_or_fail`
- Produces: `pub fn build_list_routes(router : @pony.Router, state : @store.ServerState) -> @pony.Router`

- [ ] **Step 1: Write the complete `todo/handler/list.mbt`**

```mbt
// List CRUD handlers — create, list, get, delete, share, unshare.

///|
/// Register all list-related routes on the router.
/// Returns the router for chaining.
pub fn build_list_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  router
    .add(@pony.HttpMethod::Post, "/lists", create_list(state)) |> ignore
    .add(@pony.HttpMethod::Get, "/lists", get_lists(state)) |> ignore
    .add(@pony.HttpMethod::Get, "/lists/{id}", get_list(state)) |> ignore
    .add(@pony.HttpMethod::Delete, "/lists/{id}", delete_list(state)) |> ignore
    .add(@pony.HttpMethod::Post, "/lists/{id}/share", share_list(state)) |> ignore
    .add(@pony.HttpMethod::Delete, "/lists/{id}/share", unshare_list(state)) |> ignore
}

///|
/// POST /lists — create a new list
fn create_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => {
        ctx.reply_error(401, "missing X-User header")
        return
      }
    }
    @auth.authorize_or_fail(user, "Action", "CreateList", "Application", "TinyTodo", state)!
    let body = ctx.json()!
    let name = match body["name"] {
      @json.Json::String(s) => s
      _ => {
        ctx.reply_error(400, "missing or invalid 'name' field")
        return
      }
    }
    let id = state.lists.length()
    let list = @store.new_list(id, name, user)
    @store.add_list(state, list)
    ctx.set_content_type("application/json")
    ctx.write_text(201, { "id": id, "name": name }.stringify())
  })
}

///|
/// GET /lists — list all lists owned by the current user
fn get_lists(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    @auth.authorize_or_fail(user, "Action", "GetLists", "Application", "TinyTodo", state)!
    let mut items = []
    for l in state.lists {
      if l.owner == user || l.readers.contains(user) || l.editors.contains(user) {
        items.push({ "id": l.id, "name": l.name, "owner": l.owner, "tasks": l.tasks.length() })
      }
    }
    ctx.reply_ok(items)
  })
}

///|
/// GET /lists/:id — get a single list with tasks
fn get_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let list = match state.lists.iter().find(fn(l) { l.id == id }) {
      Some(l) => l
      None => { ctx.reply_error(404, "list not found"); return }
    }
    @auth.authorize_or_fail(user, "Action", "GetList", "List", id_str?, state)!
    let mut tasks = []
    for t in list.tasks {
      let state_str = match t.state { @store.Todo => "todo"; @store.Done => "done" }
      tasks.push({ "id": t.id, "name": t.name, "state": state_str })
    }
    ctx.reply_ok({ "id": list.id, "name": list.name, "owner": list.owner, "readers": list.readers, "editors": list.editors, "tasks": tasks })
  })
}

///|
/// DELETE /lists/:id — delete a list (owner only, per Cedar policy)
fn delete_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "list not found"); return }
    }
    @auth.authorize_or_fail(user, "Action", "DeleteList", "List", id_str?, state)!
    state.lists.remove(idx) |> ignore
    state.entities.entities.remove(@ast.EntityUID::{ type_: "List", id: id_str? }) |> ignore
    ctx.no_content()
  })
}

///|
/// POST /lists/:id/share — share a list with a user
fn share_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "list not found"); return }
    }
    @auth.authorize_or_fail(user, "Action", "EditShare", "List", id_str?, state)!
    let body = ctx.json()!
    let target = match body["target"] { @json.Json::String(s) => s; _ => { ctx.reply_error(400, "missing target"); return } }
    let readonly = match body["readonly"] { @json.Json::Bool(b) => b; @json.Json::Null => true; _ => true }
    if readonly {
      if not(state.lists[idx].readers.contains(target)) {
        state.lists[idx].readers.push(target)
      }
    } else {
      if not(state.lists[idx].editors.contains(target)) {
        state.lists[idx].editors.push(target)
      }
    }
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
/// DELETE /lists/:id/share — unshare a list from a user
fn unshare_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "list not found"); return }
    }
    @auth.authorize_or_fail(user, "Action", "EditShare", "List", id_str?, state)!
    let body = ctx.json()!
    let target = match body["target"] { @json.Json::String(s) => s; _ => { ctx.reply_error(400, "missing target"); return } }
    state.lists[idx].readers = state.lists[idx].readers.filter(fn(u) { u != target })
    state.lists[idx].editors = state.lists[idx].editors.filter(fn(u) { u != target })
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
fn find_list_index(state : @store.ServerState, id : Int) -> Int? {
  for i = 0; i < state.lists.length(); i = i + 1 {
    if state.lists[i].id == id {
      return Some(i)
    }
  }
  None
}
```

- [ ] **Step 2: Run `moon check` to verify compilation**

```bash
moon check
```
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add todo/handler/list.mbt
git commit -m "feat(todo): list handlers — create, get, delete, share, unshare"
```

---

### Task 5: Task Handlers

**Files:**
- Create: `todo/handler/task.mbt`

**Interfaces:**
- Consumes: `@store.ServerState`, `@auth.authorize_or_fail`, `find_list_index` (local)
- Produces: `pub fn build_task_routes(router : @pony.Router, state : @store.ServerState) -> @pony.Router`

- [ ] **Step 1: Write `todo/handler/task.mbt`**

```mbt
// Task CRUD handlers — create, update, delete tasks within a list.

///|
pub fn build_task_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  router
    .add(@pony.HttpMethod::Post, "/lists/{id}/tasks", create_task(state)) |> ignore
    .add(@pony.HttpMethod::Patch, "/lists/{id}/tasks/{pos}", update_task(state)) |> ignore
    .add(@pony.HttpMethod::Delete, "/lists/{id}/tasks/{pos}", delete_task(state)) |> ignore
}

///|
/// POST /lists/:id/tasks — add a task to a list
fn create_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "not found"); return }
    }
    @auth.authorize_or_fail(user, "Action", "CreateTask", "List", id_str?, state)!
    let body = ctx.json()!
    let task_name = match body["name"] { @json.Json::String(s) => s; _ => { ctx.reply_error(400, "missing 'name'"); return } }
    let task_id = state.lists[idx].tasks.length()
    let task = @store.TaskData::{ id: task_id, name: task_name, state: @store.Todo }
    state.lists[idx].tasks.push(task)
    @store.update_list_entity(state, state.lists[idx])
    ctx.reply_ok({ "id": task_id, "name": task_name, "state": "todo" })
  })
}

///|
/// PATCH /lists/:id/tasks/:pos — update a task's name or toggle its state
fn update_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let pos_str = ctx.param("pos")
    let pos = match pos_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing pos"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "not found"); return }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.reply_error(404, "task not found")
      return
    }
    @auth.authorize_or_fail(user, "Action", "UpdateTask", "List", id_str?, state)!
    let body = ctx.json()!
    match body["name"] {
      @json.Json::String(new_name) => state.lists[idx].tasks[pos].name = new_name
      _ => ()
    }
    match body["state"] {
      @json.Json::String("done") => state.lists[idx].tasks[pos].state = @store.Done
      @json.Json::String("todo") => state.lists[idx].tasks[pos].state = @store.Todo
      _ => ()
    }
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
/// DELETE /lists/:id/tasks/:pos — remove a task from a list
fn delete_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.reply_error(401, "missing X-User header"); return } }
    let id_str = ctx.param("id")
    let id = match id_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing id"); return } }
    let pos_str = ctx.param("pos")
    let pos = match pos_str { Some(s) => s.to_int(); None => { ctx.reply_error(400, "missing pos"); return } }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.reply_error(404, "not found"); return }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.reply_error(404, "task not found")
      return
    }
    @auth.authorize_or_fail(user, "Action", "DeleteTask", "List", id_str?, state)!
    state.lists[idx].tasks.remove(pos) |> ignore
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
fn find_list_index(state : @store.ServerState, id : Int) -> Int? {
  for i = 0; i < state.lists.length(); i = i + 1 {
    if state.lists[i].id == id {
      return Some(i)
    }
  }
  None
}
```

- [ ] **Step 2: Run `moon check`**

```bash
moon check
```
Expected: 0 errors.

- [ ] **Step 3: Commit**

```bash
git add todo/handler/task.mbt
git commit -m "feat(todo): task handlers — create, update, delete tasks"
```

---

### Task 6: Main Entry Point

**Files:**
- Create: `todo/main.mbt`
- Create: `todo/policies.cedar`
- Create: `todo/entities.json`

**Interfaces:**
- Consumes: `@store.init`, `@handler.list.build_list_routes`, `@handler.task.build_task_routes`, `@pony.start`
- Produces: Runnable server on `127.0.0.1:3000`

- [ ] **Step 1: Create `todo/policies.cedar`**

```
permit(
  principal,
  action in [Action::"CreateList", Action::"GetLists"],
  resource == Application::"TinyTodo"
);

permit(
  principal,
  action,
  resource
)
when { resource.owner == principal };

permit(
  principal,
  action == Action::"GetList",
  resource
)
when { principal in resource.readers || principal in resource.editors };

permit(
  principal,
  action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"],
  resource
)
when { principal in resource.editors };
```

- [ ] **Step 2: Create `todo/entities.json`**

```json
[
  {
    "uid": { "type": "Application", "id": "TinyTodo" },
    "attrs": {},
    "tags": {},
    "parents": []
  },
  {
    "uid": { "type": "User", "id": "emina" },
    "attrs": { "location": ["String", "DEF33"], "joblevel": ["Long", 8] },
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" },
      { "type": "Team", "id": "admin" }
    ]
  },
  {
    "uid": { "type": "User", "id": "aaron" },
    "attrs": { "location": ["String", "ABC17"], "joblevel": ["Long", 5] },
    "tags": {},
    "parents": [
      { "type": "Team", "id": "interns" },
      { "type": "Application", "id": "TinyTodo" }
    ]
  },
  {
    "uid": { "type": "User", "id": "andrew" },
    "attrs": { "location": ["String", "XYZ77"], "joblevel": ["Long", 5] },
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" },
      { "type": "Team", "id": "admin" },
      { "type": "Team", "id": "temp" }
    ]
  },
  {
    "uid": { "type": "User", "id": "kesha" },
    "attrs": { "location": ["String", "ABC17"], "joblevel": ["Long", 5] },
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" },
      { "type": "Team", "id": "temp" }
    ]
  },
  {
    "uid": { "type": "Team", "id": "temp" },
    "attrs": {},
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" }
    ]
  },
  {
    "uid": { "type": "Team", "id": "admin" },
    "attrs": {},
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" }
    ]
  },
  {
    "uid": { "type": "Team", "id": "interns" },
    "attrs": {},
    "tags": {},
    "parents": [
      { "type": "Application", "id": "TinyTodo" },
      { "type": "Team", "id": "temp" }
    ]
  }
]
```

- [ ] **Step 3: Create `todo/main.mbt`**

```mbt
// TinyTodo — Cedar policy-based authorization demo server.

///|
fn main {
  let policies_src = (
    #|permit(
  principal,
  action in [Action::"CreateList", Action::"GetLists"],
  resource == Application::"TinyTodo"
);

permit(
  principal,
  action,
  resource
)
when { resource.owner == principal };

permit(
  principal,
  action == Action::"GetList",
  resource
)
when { principal in resource.readers || principal in resource.editors };

permit(
  principal,
  action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"],
  resource
)
when { principal in resource.editors };
|
  )
  let entities_src = (
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":["String","DEF33"],"joblevel":["Long",8]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{"location":["String","ABC17"],"joblevel":["Long",5]},"tags":{},"parents":[{"type":"Team","id":"interns"},{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"User","id":"andrew"},"attrs":{"location":["String","XYZ77"],"joblevel":["Long",5]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"},{"type":"Team","id":"temp"}]},{"uid":{"type":"User","id":"kesha"},"attrs":{"location":["String","ABC17"],"joblevel":["Long",5]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]},{"uid":{"type":"Team","id":"temp"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"admin"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"interns"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]}]
  )

  let state = @store.init(policies_src, entities_src)
  let r = @pony.Router::Router()
  // Logging middleware: print method and URL for each request
  r.use_mw(@pony.Handler(async fn(ctx : @pony.Context) {
    println("\{ctx.http_method} \{ctx.url_str}")
    ctx.no_content()
  }) |> ignore)
  let _ = @handler.list.build_list_routes(r, state)
  let _ = @handler.task.build_task_routes(r, state)
  println("TinyTodo server starting on 127.0.0.1:3000")
  @pony.start("127.0.0.1:3000", r)?
}
```

- [ ] **Step 4: Run `moon check`**

```bash
moon check
```
Expected: 0 errors.

- [ ] **Step 5: Commit**

```bash
git add todo/main.mbt todo/policies.cedar todo/entities.json
git commit -m "feat(todo): main entry point — server startup with policies and entities"
```

---

### Task 7: Integration Tests

**Files:**
- Create: `todo/todo_test.mbt` (blackbox test, using HTTP-like assertions against handlers)
- Create: `todo/README.md`

**Interfaces:**
- Tests authorization flow end-to-end: create list → share → verify reader can view but not delete

- [ ] **Step 1: Write `todo/todo_test.mbt`**

```mbt
// Blackbox integration tests for TinyTodo authorization flow.
// Tests the store + auth layers together, simulating request flow.

///|
fn full_state() -> @store.ServerState {
  let policies_src = (
    #|permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");
permit(principal, action, resource) when { resource.owner == principal };
permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };
permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
|
  )
  let entities_src = (
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":["String","DEF33"],"joblevel":["Long",8]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"User","id":"kesha"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]}]
  )
  @store.init(policies_src, entities_src)
}

///|
test "full flow: create, share, read, task, verify access" {
  let state = full_state()

  // Step 1: emina creates a list
  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "CreateList", "Application", "TinyTodo", state))
  let list = @store.new_list(0, "Shopping", "emina")
  @store.add_list(state, list)
  @debug.assert_eq(1, state.lists.length())

  // Step 2: emina shares with aaron as editor
  state.lists[0].editors.push("aaron")
  @store.update_list_entity(state, state.lists[0])

  // Step 3: aaron can GetList (editor → read access)
  @debug.assert_eq(true, @auth.try_authorize("aaron", "Action", "GetList", "List", "0", state))

  // Step 4: aaron can create a task (editor → write access)
  @debug.assert_eq(true, @auth.try_authorize("aaron", "Action", "CreateTask", "List", "0", state))

  // Step 5: kesha cannot access the list (not owner, reader, or editor)
  @debug.assert_eq(false, @auth.try_authorize("kesha", "Action", "GetList", "List", "0", state))

  // Step 6: aaron cannot delete the list (editor ≠ owner for DeleteList)
  @debug.assert_eq(false, @auth.try_authorize("aaron", "Action", "DeleteList", "List", "0", state))
}

///|
test "owner can do everything" {
  let state = full_state()
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)

  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "GetList", "List", "0", state))
  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "DeleteList", "List", "0", state))
  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "CreateTask", "List", "0", state))
  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "UpdateTask", "List", "0", state))
  @debug.assert_eq(true, @auth.try_authorize("emina", "Action", "DeleteTask", "List", "0", state))
}
```

- [ ] **Step 2: Run all tests**

```bash
moon test --package jaredzhou/todo
```
Expected: All tests pass (11 unit tests + 2 integration tests = 13).

- [ ] **Step 3: Create `todo/README.md`**

```markdown
# TinyTodo

A demo application demonstrating Cedar policy-based authorization in MoonBit. Uses [pony](https://mooncakes.io/packages/jaredzhou/pony) for HTTP routing and [mooncedar](https://mooncakes.io/packages/jaredzhou/mooncedar) for Cedar policy evaluation.

## Quick Start

```bash
moon run --package jaredzhou/todo
```

Server starts on `127.0.0.1:3000`.

## Usage

All requests use `X-User` header to identify the current user:

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

# aaron views the list (editor can read)
curl -H "X-User: aaron" localhost:3000/lists/0

# kesha tries to view — denied (403)
curl -H "X-User: kesha" localhost:3000/lists/0

# aaron tries to delete the list — denied (not owner)
curl -H "X-User: aaron" -X DELETE localhost:3000/lists/0
```

## Authorization Model

| Role | CreateTask | GetList | UpdateTask | DeleteTask | DeleteList | Share |
|------|-----------|---------|------------|------------|------------|-------|
| Owner | Permit | Permit | Permit | Permit | Permit | Permit |
| Editor | Permit | Permit | Permit | Permit | Deny | Deny |
| Reader | Deny | Permit | Deny | Deny | Deny | Deny |
| Anyone | CreateList | — | — | — | — | — |

## Pre-defined Users

| User | Teams | Location | Job Level |
|------|-------|----------|-----------|
| emina | admin | DEF33 | 8 |
| aaron | interns | ABC17 | 5 |
| andrew | admin, temp | XYZ77 | 5 |
| kesha | temp | ABC17 | 5 |
```

- [ ] **Step 4: Final verification**

```bash
moon check && moon test && moon fmt && moon info
```
Expected: 0 errors, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add todo/todo_test.mbt todo/README.md
git commit -m "feat(todo): integration tests and README"
```

---
