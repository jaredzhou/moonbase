// Whitebox tests for auth layer — try_authorize and authorize_or_fail.

///|
fn test_policies() -> String {
  let s =
    #|permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");
    #|permit(principal, action, resource) when { resource.owner == principal };
    #|permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };
    #|permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
  s
}

///|
fn test_entities() -> String {
  let s =
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":["String","DEF33"],"joblevel":["Long","8"]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{"location":["String","ABC17"],"joblevel":["Long","5"]},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"admin"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]}]
  s
}

///|
test "anyone can CreateList" {
  let state = @store.init_state(test_policies(), test_entities())
  @debug.assert_eq(true, try_authorize("aaron", "Action", "CreateList", "Application", "TinyTodo", state))
}

///|
test "owner has full control on own list" {
  let state = @store.init_state(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  // Owner can GetList
  @debug.assert_eq(true, try_authorize("emina", "Action", "GetList", "List", "0", state))
  // Owner can DeleteList
  @debug.assert_eq(true, try_authorize("emina", "Action", "DeleteList", "List", "0", state))
}

///|
test "non-owner, non-reader cannot GetList" {
  let state = @store.init_state(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  // aaron is not owner, not reader, not editor
  @debug.assert_eq(false, try_authorize("aaron", "Action", "GetList", "List", "0", state))
}

///|
test "reader can GetList but not DeleteList" {
  let state = @store.init_state(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  list.readers.push("aaron")
  @store.add_list(state, list)
  @debug.assert_eq(true, try_authorize("aaron", "Action", "GetList", "List", "0", state))
  @debug.assert_eq(false, try_authorize("aaron", "Action", "DeleteList", "List", "0", state))
}

///|
test "editor can CreateTask and UpdateTask" {
  let state = @store.init_state(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  list.editors.push("aaron")
  @store.add_list(state, list)
  @debug.assert_eq(true, try_authorize("aaron", "Action", "CreateTask", "List", "0", state))
  @debug.assert_eq(true, try_authorize("aaron", "Action", "UpdateTask", "List", "0", state))
}

///|
test "authorize_or_fail raises on deny" {
  let state = @store.init_state(test_policies(), test_entities())
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)
  let raised = try {
    authorize_or_fail("aaron", "Action", "DeleteList", "List", "0", state)
    false
  } catch {
    AccessDenied(_) => true
  }
  @debug.assert_eq(true, raised)
}
