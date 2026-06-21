// Task CRUD handlers — create, update, delete tasks within a list.

///|
/// Register all task-related routes on the router.
/// Returns the router for chaining.
pub fn build_task_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  try { router.add(@pony.HttpMethod::Post, "/lists/{id}/tasks", create_task(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Patch, "/lists/{id}/tasks/{pos}", update_task(state)) } catch { _ => () }
  try { router.add(@pony.HttpMethod::Delete, "/lists/{id}/tasks/{pos}", delete_task(state)) } catch { _ => () }
  router
}

///|
/// POST /lists/:id/tasks — add a task to a list
fn create_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => { ctx.response_error(401, "missing X-User header"); return }
    }
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
    if !@auth.try_authorize(user, "Action", "CreateTask", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    let body : Json = ctx.json() catch {
      _ => { ctx.response_error(400, "invalid JSON body"); return }
    }
    let task_name = match body {
      Json::Object(m) => match m.get("name") {
        Some(Json::String(s)) => s
        _ => { ctx.response_error(400, "missing or invalid 'name' field"); return }
      }
      _ => { ctx.response_error(400, "expected JSON object"); return }
    }
    let task_id = state.lists[idx].tasks.length()
    let task = @store.TaskData::{ id: task_id, name: task_name, state: @store.Todo }
    state.lists[idx].tasks.push(task)
    @store.update_list_entity(state, state.lists[idx])
    let resp = Json::object(Map([
      ("id", task_id.to_json()),
      ("name", task_name.to_json()),
      ("state", "todo".to_json()),
    ]))
    ctx.response_ok(resp)
  })
}

///|
/// PATCH /lists/:id/tasks/:pos — update a task's name or toggle its state
fn update_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => { ctx.response_error(401, "missing X-User header"); return }
    }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let pos_str = match ctx.param("pos") {
      Some(s) => s
      None => { ctx.response_error(400, "missing pos"); return }
    }
    let pos = match parse_int(pos_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid pos"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.response_error(404, "task not found")
      return
    }
    if !@auth.try_authorize(user, "Action", "UpdateTask", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    let body : Json = ctx.json() catch {
      _ => { ctx.response_error(400, "invalid JSON body"); return }
    }
    match body {
      Json::Object(m) => {
        match m.get("name") {
          Some(Json::String(new_name)) => state.lists[idx].tasks[pos].name = new_name
          _ => ()
        }
        match m.get("state") {
          Some(Json::String(s)) => {
            if s == "done" {
              state.lists[idx].tasks[pos].state = @store.Done
            } else {
              if s == "todo" {
                state.lists[idx].tasks[pos].state = @store.Todo
              }
            }
          }
          _ => ()
        }
      }
      _ => { ctx.response_error(400, "expected JSON object"); return }
    }
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
/// DELETE /lists/:id/tasks/:pos — remove a task from a list
fn delete_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => { ctx.response_error(401, "missing X-User header"); return }
    }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => { ctx.response_error(400, "missing id"); return }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid id"); return }
    }
    let pos_str = match ctx.param("pos") {
      Some(s) => s
      None => { ctx.response_error(400, "missing pos"); return }
    }
    let pos = match parse_int(pos_str) {
      Some(n) => n
      None => { ctx.response_error(400, "invalid pos"); return }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => { ctx.response_error(404, "list not found"); return }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.response_error(404, "task not found")
      return
    }
    if !@auth.try_authorize(user, "Action", "DeleteTask", "List", id_str, state) {
      ctx.response_error(403, "access denied")
      return
    }
    state.lists[idx].tasks.remove(pos) |> ignore
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}
