// Task CRUD handlers — create, update, delete tasks within a list.

///|
struct CreateTaskReq {
  name : String
} derive(FromJson)

///|
struct UpdateTaskReq {
  name : String?
  state : String?
} derive(FromJson)

///|
/// Register all task-related routes on the router.
pub fn build_task_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  router.add(@pony.HttpMethod::Post, "/lists/{id}/tasks", create_task(state)) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Patch,
    "/lists/{id}/tasks/{pos}",
    update_task(state),
  ) catch {
    _ => ()
  }
  router.add(
    @pony.HttpMethod::Delete,
    "/lists/{id}/tasks/{pos}",
    delete_task(state),
  ) catch {
    _ => ()
  }
  router
}

///|
/// POST /lists/:id/tasks — add a task to a list
fn create_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => {
        ctx.reply_error(401, "missing X-User header")
        return
      }
    }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => {
        ctx.reply_error(400, "missing id")
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(400, "invalid id")
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(404, "list not found")
        return
      }
    }
    if !@auth.try_authorize(user, "Action", "CreateTask", "List", id_str, state) {
      ctx.reply_error(403, "access denied")
      return
    }
    let req : CreateTaskReq = ctx.json() catch {
      _ => {
        ctx.reply_error(400, "invalid JSON body")
        return
      }
    }
    let task_id = state.lists[idx].tasks.length()
    state.lists[idx].tasks.push(@store.TaskData::{
      id: task_id,
      name: req.name,
      state: @store.Todo,
    })
    @store.update_list_entity(state, state.lists[idx])
    ctx.reply_ok(TaskItem::{ id: task_id, name: req.name, state: "todo" })
  })
}

///|
/// PATCH /lists/:id/tasks/:pos — update a task's name or toggle its state
fn update_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => {
        ctx.reply_error(401, "missing X-User header")
        return
      }
    }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => {
        ctx.reply_error(400, "missing id")
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(400, "invalid id")
        return
      }
    }
    let pos_str = match ctx.param("pos") {
      Some(s) => s
      None => {
        ctx.reply_error(400, "missing pos")
        return
      }
    }
    let pos = match parse_int(pos_str) {
      Some(n) => n
      None => {
        ctx.reply_error(400, "invalid pos")
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(404, "list not found")
        return
      }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.reply_error(404, "task not found")
      return
    }
    if !@auth.try_authorize(user, "Action", "UpdateTask", "List", id_str, state) {
      ctx.reply_error(403, "access denied")
      return
    }
    let req : UpdateTaskReq = ctx.json() catch {
      _ => {
        ctx.reply_error(400, "invalid JSON body")
        return
      }
    }
    match req.name {
      Some(new_name) => state.lists[idx].tasks[pos].name = new_name
      None => ()
    }
    match req.state {
      Some(s) =>
        if s == "done" {
          state.lists[idx].tasks[pos].state = @store.Done
        } else if s == "todo" {
          state.lists[idx].tasks[pos].state = @store.Todo
        }
      None => ()
    }
    @store.update_list_entity(state, state.lists[idx])
    ctx.reply_ok(({} : Json))
  })
}

///|
/// DELETE /lists/:id/tasks/:pos — remove a task from a list
fn delete_task(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = match ctx.header("X-User") {
      Some(u) => u
      None => {
        ctx.reply_error(401, "missing X-User header")
        return
      }
    }
    let id_str = match ctx.param("id") {
      Some(s) => s
      None => {
        ctx.reply_error(400, "missing id")
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(400, "invalid id")
        return
      }
    }
    let pos_str = match ctx.param("pos") {
      Some(s) => s
      None => {
        ctx.reply_error(400, "missing pos")
        return
      }
    }
    let pos = match parse_int(pos_str) {
      Some(n) => n
      None => {
        ctx.reply_error(400, "invalid pos")
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(404, "list not found")
        return
      }
    }
    if pos < 0 || pos >= state.lists[idx].tasks.length() {
      ctx.reply_error(404, "task not found")
      return
    }
    if !@auth.try_authorize(user, "Action", "DeleteTask", "List", id_str, state) {
      ctx.reply_error(403, "access denied")
      return
    }
    state.lists[idx].tasks.remove(pos) |> ignore
    @store.update_list_entity(state, state.lists[idx])
    ctx.reply_ok(({} : Json))
  })
}
