// List CRUD handlers — create, list, get, delete, share, unshare.

///|
/// Register all list-related routes on the router.
/// Returns the router for chaining.
pub fn build_list_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  try { router.add(@pony.HttpMethod::Post, "/lists", create_list(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Get, "/lists", get_lists(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Get, "/lists/{id}", get_list(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Delete, "/lists/{id}", delete_list(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Post, "/lists/{id}/share", share_list(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Delete, "/lists/{id}/share", unshare_list(state)) } catch { _ => () }
  router
}

///|
/// POST /lists — create a new list
fn create_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => {
        ctx.response_error(401, "missing X-User header")
        return
      }
    }
    if !@auth.try_authorize(user, "Action", "CreateList", "Application", "TinyTodo", state) {
      ctx.response_error(403, "access denied")
      return
    }
    let body : Json = ctx.json() catch {
      _ => {
        ctx.response_error(400, "invalid JSON body")
        return
      }
    }
    let name = match body {
      Json::Object(m) => {
        match m.get("name") {
          Some(Json::String(s)) => s
          _ => {
            ctx.response_error(400, "missing or invalid 'name' field")
            return
          }
        }
      }
      _ => {
        ctx.response_error(400, "expected JSON object")
        return
      }
    }
    let id = state.lists.length()
    let list = @store.new_list(id, name, user)
    @store.add_list(state, list)
    let resp = Json::object(Map([
      ("id", id.to_json()),
      ("name", name.to_json()),
    ]))
    ctx.set_content_type("application/json")
    ctx.write_text(201, resp.stringify())
  })
}

///|
/// GET /lists — list all lists owned by the current user
fn get_lists(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.response_error(401, "missing X-User header"); return } }
    if !@auth.try_authorize(user, "Action", "GetLists", "Application", "TinyTodo", state) {
      ctx.response_error(403, "access denied")
      return
    }
    let items : Array[Json] = []
    for l in state.lists {
      if l.owner == user || l.readers.contains(user) || l.editors.contains(user) {
        items.push(Json::object(Map([
          ("id", l.id.to_json()),
          ("name", l.name.to_json()),
          ("owner", l.owner.to_json()),
          ("tasks", l.tasks.length().to_json()),
        ])))
      }
    }
    ctx.response_ok(items)
  })
}

///|
/// GET /lists/:id — get a single list with tasks
fn get_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.response_error(401, "missing X-User header"); return } }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    let list = state.lists[idx]
    if !@auth.try_authorize(user, "Action", "GetList", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    let tasks : Array[Json] = []
    for t in list.tasks {
      let state_str = match t.state { @store.Todo => "todo"; @store.Done => "done" }
      tasks.push(Json::object(Map([
        ("id", t.id.to_json()),
        ("name", t.name.to_json()),
        ("state", state_str.to_json()),
      ])))
    }
    let resp = Json::object(Map([
      ("id", list.id.to_json()),
      ("name", list.name.to_json()),
      ("owner", list.owner.to_json()),
      ("readers", list.readers.to_json()),
      ("editors", list.editors.to_json()),
      ("tasks", tasks.to_json()),
    ]))
    ctx.response_ok(resp)
  })
}

///|
/// DELETE /lists/:id — delete a list (owner only, per Cedar policy)
fn delete_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.response_error(401, "missing X-User header"); return } }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    if !@auth.try_authorize(user, "Action", "DeleteList", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    state.lists.remove(idx) |> ignore
    state.entities.entities.remove(@ast.EntityUID::{ type_: "List", id: id_str }) |> ignore
    ctx.no_content()
  })
}

///|
/// POST /lists/:id/share — share a list with a user
fn share_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.response_error(401, "missing X-User header"); return } }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    if !@auth.try_authorize(user, "Action", "EditShare", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    let body : Json = ctx.json() catch {
      _ => {
        ctx.response_error(400, "invalid JSON body")
        return
      }
    }
    let m = match body {
      Json::Object(m) => m
      _ => {
        ctx.response_error(400, "expected JSON object")
        return
      }
    }
    let target = match m.get("target") {
      Some(Json::String(s)) => s
      _ => {
        ctx.response_error(400, "missing target")
        return
      }
    }
    let is_readonly = match m.get("readonly") {
      Some(v) => {
        try {
          let b : Bool = @json.from_json(v)
          b
        } catch {
          _ => true
        }
      }
      None => true
    }
    if is_readonly {
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
    let user = match ctx.header("X-User") { Some(u) => u; None => { ctx.response_error(401, "missing X-User header"); return } }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    if !@auth.try_authorize(user, "Action", "EditShare", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    let body : Json = ctx.json() catch {
      _ => {
        ctx.response_error(400, "invalid JSON body")
        return
      }
    }
    let m = match body {
      Json::Object(m) => m
      _ => {
        ctx.response_error(400, "expected JSON object")
        return
      }
    }
    let target = match m.get("target") {
      Some(Json::String(s)) => s
      _ => {
        ctx.response_error(400, "missing target")
        return
      }
    }
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

///|
fn parse_int(s : String) -> Int? {
  let mut result = 0
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c >= '0' && c <= '9' {
      result = result * 10 + (c.to_int() - 48)
    } else {
      return None
    }
  }
  Some(result)
}
