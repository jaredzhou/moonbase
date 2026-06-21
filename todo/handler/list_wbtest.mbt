// Whitebox tests for list handlers — create, list, get, delete, share, unshare.

///|
test "find_list_index returns index of matching list" {
  let state = @store.empty_state()
  let list0 = @store.new_list(0, "Shopping", "emina")
  let list1 = @store.new_list(1, "Work", "emina")
  @store.add_list(state, list0)
  @store.add_list(state, list1)
  @debug.assert_eq(0, find_list_index(state, 0).unwrap())
  @debug.assert_eq(1, find_list_index(state, 1).unwrap())
}

///|
test "find_list_index returns None for missing id" {
  let state = @store.empty_state()
  @debug.assert_eq(true, find_list_index(state, 99) is None)
  @debug.assert_eq(true, find_list_index(state, -1) is None)
}

///|
test "find_list_index returns None for empty lists" {
  let state = @store.empty_state()
  @debug.assert_eq(true, find_list_index(state, 0) is None)
}
