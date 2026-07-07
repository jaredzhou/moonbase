// Whitebox tests for store layer — in-memory state + Cedar entity sync.

///|
test "init loads base entities" {
  let policies_src =
    #|permit(principal,action,resource);
  let entities_src =
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":"DEF33","joblevel":8},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]}]
  let state = init_state(policies_src, entities_src)
  @debug.assert_eq(1, state.policies.length())
  // Entity store should have Application and User
  let app = state.entities.get_entity(@ast.EntityUID::{
    type_: "Application",
    id: "TinyTodo",
  })
  @debug.assert_eq(true, app is Some(_))
  let user = state.entities.get_entity(@ast.EntityUID::{
    type_: "User",
    id: "emina",
  })
  @debug.assert_eq(true, user is Some(_))
}

///|
test "init loads team hierarchy" {
  let policies_src =
    #|permit(principal,action,resource);
  let entities_src =
    #|[{"uid":{"type":"Team","id":"temp"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"interns"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]}]
  let state = init_state(policies_src, entities_src)
  let interns = state.entities.get_entity(@ast.EntityUID::{
    type_: "Team",
    id: "interns",
  })
  @debug.assert_eq(true, interns is Some(_))
  @debug.assert_eq(2, interns.unwrap().parents.length())
}

///|
test "add_list updates entity store" {
  let state = empty_state()
  let list = ListData::{
    id: 0,
    name: "Shopping",
    owner: "emina",
    readers: [],
    editors: [],
    tasks: [],
  }
  add_list(state, list)
  let entity = state.entities.get_entity(@ast.EntityUID::{
    type_: "List",
    id: "0",
  })
  @debug.assert_eq(true, entity is Some(_))
  let e = entity.unwrap()
  @debug.assert_eq(
    "Shopping",
    match e.attrs["name"] {
      @ast.Value::String(s) => s
      _ => ""
    },
  )
  // owner attribute is an EntityUID value pointing to User::"emina"
  match e.attrs["owner"] {
    @ast.Value::EntityUID(uid) => @debug.assert_eq("emina", uid.id)
    _ => abort("expected EntityUID for owner")
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
  let list = ListData::{
    id: 0,
    name: "Shopping",
    owner: "emina",
    readers: [],
    editors: [],
    tasks: [],
  }
  add_list(state, list)
  list.readers.push("aaron")
  update_list_entity(state, list)
  let entity = state.entities
    .get_entity(@ast.EntityUID::{ type_: "List", id: "0" })
    .unwrap()
  match entity.attrs["readers"] {
    @ast.Value::Set(refs) => @debug.assert_eq(1, refs.length())
    _ => abort("expected Set for readers")
  }
}
