// Blackbox integration tests for TinyTodo authorization flow.
// Tests the store + auth layers together, simulating request flow.

///|
fn full_state() -> @store.ServerState {
  let policies_src =
    #|permit(principal, action in [Action::"CreateList", Action::"GetLists"], resource == Application::"TinyTodo");
    #|permit(principal, action, resource) when { resource.owner == principal };
    #|permit(principal, action == Action::"GetList", resource) when { principal in resource.readers || principal in resource.editors };
    #|permit(principal, action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"], resource) when { principal in resource.editors };
  let entities_src =
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":"DEF33","joblevel":8},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"User","id":"kesha"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]}]
  @store.init_state(policies_src, entities_src)
}

///|
test "full flow: create, share, read, task, verify access" {
  let state = full_state()

  // Step 1: emina creates a list
  @debug.assert_eq(
    true,
    @auth.try_authorize(
      "emina", "Action", "CreateList", "Application", "TinyTodo", state,
    ),
  )
  let list = @store.new_list(0, "Shopping", "emina")
  @store.add_list(state, list)
  @debug.assert_eq(1, state.lists.length())

  // Step 2: emina shares with aaron as editor
  state.lists[0].editors.push("aaron")
  @store.update_list_entity(state, state.lists[0])

  // Step 3: aaron can GetList (editor -> read access)
  @debug.assert_eq(
    true,
    @auth.try_authorize("aaron", "Action", "GetList", "List", "0", state),
  )

  // Step 4: aaron can create a task (editor -> write access)
  @debug.assert_eq(
    true,
    @auth.try_authorize("aaron", "Action", "CreateTask", "List", "0", state),
  )

  // Step 5: kesha cannot access the list (not owner, reader, or editor)
  @debug.assert_eq(
    false,
    @auth.try_authorize("kesha", "Action", "GetList", "List", "0", state),
  )

  // Step 6: aaron cannot delete the list (editor != owner for DeleteList)
  @debug.assert_eq(
    false,
    @auth.try_authorize("aaron", "Action", "DeleteList", "List", "0", state),
  )
}

///|
test "owner can do everything" {
  let state = full_state()
  let list = @store.new_list(0, "MyList", "emina")
  @store.add_list(state, list)

  @debug.assert_eq(
    true,
    @auth.try_authorize("emina", "Action", "GetList", "List", "0", state),
  )
  @debug.assert_eq(
    true,
    @auth.try_authorize("emina", "Action", "DeleteList", "List", "0", state),
  )
  @debug.assert_eq(
    true,
    @auth.try_authorize("emina", "Action", "CreateTask", "List", "0", state),
  )
  @debug.assert_eq(
    true,
    @auth.try_authorize("emina", "Action", "UpdateTask", "List", "0", state),
  )
  @debug.assert_eq(
    true,
    @auth.try_authorize("emina", "Action", "DeleteTask", "List", "0", state),
  )
}
