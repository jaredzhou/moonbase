// MapEntityStore JSON (ToJson / FromJson) — blackbox tests via inspect snapshot.

///|
test "to_json empty store" {
  let store : MapEntityStore = @json.from_json(@json.parse("[]"))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[]
    ),
  )
}

///|
test "to_json single entity" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":"admin"},"tags":{},"parents":[]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":["String","admin"]},"tags":{},"parents":[]}]
    ),
  )
}

///|
test "to_json entity with parents and tags" {
  let src =
    #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{"env":"prod"},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{"env":["String","prod"]},"parents":[{"type":"Album","id":"vacation"}]}]
    ),
  )
}

///|
test "to_json multiple entities" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  inspect(
    store.to_json().stringify(),
    content=(
      #|[{"uid":{"type":"User","id":"alice"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
    ),
  )
}

///|
test "from_json recovers entities" {
  let src =
    #|[{"uid":{"type":"User","id":"alice"},"attrs":{"role":"admin"},"tags":{},"parents":[]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  match store.get_entity(@ast.EntityUID::{ type_: "User", id: "alice" }) {
    Some(e) => {
      @debug.assert_eq("User", e.uid.type_)
      @debug.assert_eq("alice", e.uid.id)
    }
    None => @debug.assert_eq("should find alice", "missing")
  }
}

///|
test "from_json entity hierarchy preserved" {
  let src =
    #|[{"uid":{"type":"Photo","id":"x.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"vacation"}]}]
  let store : MapEntityStore = @json.from_json(@json.parse(src))
  match store.get_entity(@ast.EntityUID::{ type_: "Photo", id: "x.jpg" }) {
    Some(e) => {
      @debug.assert_eq(1, e.parents.length())
      @debug.assert_eq("Album", e.parents[0].type_)
      @debug.assert_eq("vacation", e.parents[0].id)
    }
    None => @debug.assert_eq("should find photo", "missing")
  }
}

///|
test "from_json wrong shape raises error" {
  let src =
    #|{"not":"an array"}
  let json = @json.parse(src)
  let mut raised = false
  try {
    let _store : MapEntityStore = @json.from_json(json)
  } catch {
    _ => raised = true
  }
  @debug.assert_eq(true, raised)
}
