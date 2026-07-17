// List CRUD handlers — create, list, get, delete, share, unshare.

///|
struct CreateListReq {
  name : String
} derive(FromJson)

///|
struct ShareReq {
  target : String
  is_readonly : Bool?
} derive(FromJson)

///|
struct ListItem {
  id : Int
  name : String
  owner : String
  tasks : Int
} derive(ToJson)

///|
struct TaskItem {
  id : Int
  name : String
  state : String
} derive(ToJson)

///|
struct ListDetail {
  id : Int
  name : String
  owner : String
  readers : Array[String]
  editors : Array[String]
  tasks : Array[TaskItem]
} derive(ToJson)

///|
struct ListCreated {
  id : Int
  name : String
} derive(ToJson)

///|
/// Register all list-related routes on the router.
pub fn build_list_routes(
  router : @pony.Router,
  state : @store.ServerState,
) -> @pony.Router {
  router.add(@pony.HttpMethod::Post, "/lists", create_list(state)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Get, "/lists", get_lists(state)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Get, "/lists/{id}", get_list(state)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Delete, "/lists/{id}", delete_list(state)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Post, "/lists/{id}/share", share_list(state)) catch {
    _ => ()
  }
  router.add(@pony.HttpMethod::Delete, "/lists/{id}/share", unshare_list(state)) catch {
    _ => ()
  }
  router
}

///|
/// POST /lists — create a new list
fn create_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    if !@auth.try_authorize(
        user, "Action", "CreateList", "Application", "TinyTodo", state,
      ) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    let req : CreateListReq = ctx.json() catch {
      _ => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid JSON body")))
        return
      }
    }
    let id = state.lists.length()
    let list = @store.new_list(id, req.name, user)
    @store.add_list(state, list)
    ctx.reply_ok(ListCreated::{ id, name: req.name })
  })
}

///|
/// GET /lists — list all lists visible to the current user
fn get_lists(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    if !@auth.try_authorize(
        user, "Action", "GetLists", "Application", "TinyTodo", state,
      ) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    let items : Array[ListItem] = []
    for l in state.lists {
      if @auth.try_authorize(
          user,
          "Action",
          "GetList",
          "List",
          l.id.to_string(),
          state,
        ) {
        items.push(ListItem::{
          id: l.id,
          name: l.name,
          owner: l.owner,
          tasks: l.tasks.length(),
        })
      }
    }
    ctx.reply_ok(items)
  })
}

///|
/// GET /lists/:id — get a single list with tasks
fn get_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id_str = ctx.param("id") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid id")))
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::NotFound("list not found")))
        return
      }
    }
    let list = state.lists[idx]
    if !@auth.try_authorize(user, "Action", "GetList", "List", id_str, state) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    let tasks : Array[TaskItem] = []
    for t in list.tasks {
      let state_str = match t.state {
        @store.Todo => "todo"
        @store.Done => "done"
      }
      tasks.push(TaskItem::{ id: t.id, name: t.name, state: state_str })
    }
    ctx.reply_ok(ListDetail::{
      id: list.id,
      name: list.name,
      owner: list.owner,
      readers: list.readers,
      editors: list.editors,
      tasks,
    })
  })
}

///|
/// DELETE /lists/:id — delete a list (owner only, per Cedar policy)
fn delete_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id_str = ctx.param("id") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid id")))
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::NotFound("list not found")))
        return
      }
    }
    if !@auth.try_authorize(user, "Action", "DeleteList", "List", id_str, state) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    state.lists.remove(idx) |> ignore
    state.entities.entities.remove(@ast.EntityUID::{ type_: "List", id: id_str })
    |> ignore
    ctx.no_content()
  })
}

///|
/// POST /lists/:id/share — share a list with a user
fn share_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id_str = ctx.param("id") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid id")))
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::NotFound("list not found")))
        return
      }
    }
    if !@auth.try_authorize(user, "Action", "EditShare", "List", id_str, state) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    let req : ShareReq = ctx.json() catch {
      _ => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid JSON body")))
        return
      }
    }
    let is_readonly = match req.is_readonly {
      Some(b) => b
      None => true
    }
    if is_readonly {
      if !state.lists[idx].readers.contains(req.target) {
        state.lists[idx].readers.push(req.target)
      }
    } else if !state.lists[idx].editors.contains(req.target) {
      state.lists[idx].editors.push(req.target)
    }
    @store.update_list_entity(state, state.lists[idx])
    ctx.no_content()
  })
}

///|
/// DELETE /lists/:id/share — unshare a list from a user
fn unshare_list(state : @store.ServerState) -> @pony.Handler {
  @pony.Handler(async fn(ctx) {
    let user = ctx.header("X-User") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id_str = ctx.param("id") catch {
      e => {
        ctx.reply_error(@pony.to_api_error(e))
        return
      }
    }
    let id = match parse_int(id_str) {
      Some(n) => n
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid id")))
        return
      }
    }
    let idx = match find_list_index(state, id) {
      Some(i) => i
      None => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::NotFound("list not found")))
        return
      }
    }
    if !@auth.try_authorize(user, "Action", "EditShare", "List", id_str, state) {
      ctx.reply_error(@pony.to_api_error(@pony.PonyError::PermissionDenied("access denied")))
      return
    }
    let req : ShareReq = ctx.json() catch {
      _ => {
        ctx.reply_error(@pony.to_api_error(@pony.PonyError::InvalidArgument("invalid JSON body")))
        return
      }
    }
    state.lists[idx].readers = state.lists[idx].readers.filter(fn(u) {
      u != req.target
    })
    state.lists[idx].editors = state.lists[idx].editors.filter(fn(u) {
      u != req.target
    })
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
