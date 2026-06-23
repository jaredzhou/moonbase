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

// ---------------------------------------------------------------------------
// RequestJSON roundtrip tests
// ---------------------------------------------------------------------------

///|
test "request json roundtrip: concrete PARC" {
  let req = @evaluator.Request::{
    principal: @evaluator.concrete_uid("GitApp::User", "JaneDoe"),
    action: @evaluator.concrete_uid("GitApp::Action", "addRepoAdmin"),
    resource: @evaluator.concrete_uid("GitApp::Repo", "CodeRepo1"),
    context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
  }
  let json = to_request_json(req).to_json()
  inspect(
    json.stringify(),
    content="{\"principal\":\"GitApp::User::\\\"JaneDoe\\\"\",\"action\":\"GitApp::Action::\\\"addRepoAdmin\\\"\",\"resource\":\"GitApp::Repo::\\\"CodeRepo1\\\"\",\"context\":{}}",
  )
  let parsed : RequestJSON = @json.from_json(json)
  let req2 = parsed.to_request()
  @debug.assert_eq(req, req2)
}

///|
test "request json: unknown principal" {
  let req = @evaluator.Request::{
    principal: @evaluator.unknown_uid("User"),
    action: @evaluator.concrete_uid("Action", "view"),
    resource: @evaluator.concrete_uid("Photo", "x"),
    context: @evaluator.Context::Unknown,
  }
  let json = to_request_json(req).to_json()
  inspect(
    json.stringify(),
    content="{\"principal\":\"User\",\"action\":\"Action::\\\"view\\\"\",\"resource\":\"Photo::\\\"x\\\"\",\"context\":{}}",
  )
  let parsed : RequestJSON = @json.from_json(json)
  guard parsed.principal is Some(s) else { return }
  @debug.assert_eq(s, "User")
}

///|
test "request json: entity object format → roundtrip" {
  let json = @json.parse(
    "{\"principal\":{\"type\":\"User\",\"id\":\"alice\"},\"action\":{\"type\":\"Action\",\"id\":\"view\"},\"resource\":{\"type\":\"Photo\",\"id\":\"x\"},\"context\":{}}",
  )
  let dto : RequestJSON = @json.from_json(json)
  guard dto.principal is Some(p) else { return }
  @debug.assert_eq(p, "User::\"alice\"")
  guard dto.action is Some(a) else { return }
  @debug.assert_eq(a, "Action::\"view\"")
  guard dto.resource is Some(r) else { return }
  @debug.assert_eq(r, "Photo::\"x\"")
  // Roundtrip: RequestJSON → Request → RequestJSON
  let req = dto.to_request()
  let dto2 = to_request_json(req)
  @debug.assert_eq(dto, dto2)
}
