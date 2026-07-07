// Core data types for TinyTodo — in-memory state + entity store.

///|
pub(all) enum TaskState {
  Todo
  Done
} derive(Debug, Eq)

///|
pub(all) struct TaskData {
  id : Int
  mut name : String
  mut state : TaskState
} derive(Debug, Eq)

///|
pub(all) struct ListData {
  id : Int
  mut name : String
  mut owner : String
  mut readers : Array[String]
  mut editors : Array[String]
  mut tasks : Array[TaskData]
} derive(Debug)

///|
pub fn new_list(id : Int, name : String, owner : String) -> ListData {
  ListData::{ id, name, owner, readers: [], editors: [], tasks: [] }
}

///|
pub(all) struct ServerState {
  mut lists : Array[ListData]
  entities : @mooncedar.MapEntityStore
  policies : Array[@ast.Policy]
}

///|
/// Build a Cedar Entity from a ListData, for storing in the entity store.
pub fn list_to_entity(l : ListData) -> @ast.Entity {
  let attrs = Map([
    ("name", @ast.Value::String(l.name)),
    (
      "owner",
      @ast.Value::EntityUID(@ast.EntityUID::{ type_: "User", id: l.owner }),
    ),
    ("readers", user_set(l.readers)),
    ("editors", user_set(l.editors)),
    ("tasks", task_set(l.tasks)),
  ])
  @ast.Entity::{
    uid: @ast.EntityUID::{ type_: "List", id: l.id.to_string() },
    attrs,
    tags: Map([]),
    parents: [@ast.EntityUID::{ type_: "Application", id: "TinyTodo" }],
  }
}

///|
fn user_set(usernames : Array[String]) -> @ast.Value {
  let arr = []
  for u in usernames {
    arr.push(@ast.Value::EntityUID(@ast.EntityUID::{ type_: "User", id: u }))
  }
  @ast.Value::Set(arr)
}

///|
fn task_set(tasks : Array[TaskData]) -> @ast.Value {
  let arr = []
  for t in tasks {
    let state_str = match t.state {
      Todo => "todo"
      Done => "done"
    }
    arr.push(
      @ast.Value::Record(
        Map([
          ("id", @ast.Value::Long(t.id.to_int64())),
          ("name", @ast.Value::String(t.name)),
          ("state", @ast.Value::String(state_str)),
        ]),
      ),
    )
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
/// Load base entities from JSON and parse Cedar policies.
pub fn init_state(policies_src : String, entities_src : String) -> ServerState {
  let policies = @parser.parse_policies(policies_src) catch {
    _ => abort("parse_policies failed")
  }
  let store = (
    @json.from_json(@json.parse(entities_src)) : @mooncedar.MapEntityStore) catch {
    _ => abort("from_json failed")
  }
  ServerState::{ lists: [], entities: store, policies }
}

///|
pub fn empty_state() -> ServerState {
  let policies_src =
    #|permit(principal,action,resource);
  let entities_src =
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]}]
  init_state(policies_src, entities_src)
}
