// Tests for QueryX top-level types — Query, Order, Page, Value, and ToValue.

// ---------------------------------------------------------------------------
// Full round-trip
// ---------------------------------------------------------------------------

///|
test "full round-trip with all fields" {
  let input : Json = {
    "filter": {
      "id": 1.0,
      "age": { "gt": 18.0, "lt": 30.0 },
      "name": { "contains": "tom" },
      "created_at": { "between": ["2024-01-01", "2025-01-01"] },
      "or": [{ "status": "A" }, { "status": "B" }],
    },
    "order_by": [{ "age": "desc" }, { "name": "asc" }],
    "page": { "after": "cursor123", "size": 10.0 },
    "set": { "a": 1.0, "b": "haha" },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()

  let want = "{\"filter\":{\"id\":1,\"age\":{\"between\":[18,30]},\"name\":{\"contains\":\"tom\"},\"created_at\":{\"between\":[\"2024-01-01\",\"2025-01-01\"]},\"or\":[{\"status\":\"A\"},{\"status\":\"B\"}]},\"order_by\":[{\"age\":\"desc\"},{\"name\":\"asc\"}],\"page\":{\"after\":\"cursor123\",\"size\":10},\"set\":{\"a\":1,\"b\":\"haha\"}}"
  inspect(json.stringify(), content=want)
}

// ---------------------------------------------------------------------------
// Missing / optional fields — JSON omits them, Query gets None
// ---------------------------------------------------------------------------

///|
test "missing filter defaults to empty" {
  let input : Json = { "order_by": [], "page": { "after": "", "size": 10.0 } }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  // Missing filter -> empty object in output
  let filter = match json {
    Json::Object(m) => m.get("filter")
    _ => abort("bad")
  }
  match filter {
    Some(f) => inspect(f.stringify(), content="{}")
    None => abort("filter missing")
  }
}

///|
test "missing order_by becomes None and omitted from output" {
  let input : Json = {
    "filter": { "x": 1.0 },
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  // order_by should be None
  match query.order_by {
    None => ()
    Some(_) => abort("order_by should be None")
  }
  let json = query.to_json()
  match json {
    Json::Object(m) => assert_false(m.get("order_by") is Some(_))
    _ => abort("bad")
  }
}

///|
test "missing page becomes None and omitted from output" {
  let input : Json = { "filter": { "x": 1.0 } }
  let query : Query = @json.from_json(input)
  match query.page {
    None => ()
    Some(_) => abort("page should be None")
  }
  let json = query.to_json()
  match json {
    Json::Object(m) => assert_false(m.get("page") is Some(_))
    _ => abort("bad")
  }
}

///|
test "missing set becomes None and omitted from output" {
  let input : Json = {
    "filter": { "x": 1.0 },
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  match query.set {
    None => ()
    Some(_) => abort("set should be None")
  }
  let json = query.to_json()
  match json {
    Json::Object(m) => assert_false(m.get("set") is Some(_))
    _ => abort("bad")
  }
}

// ---------------------------------------------------------------------------
// Empty filter
// ---------------------------------------------------------------------------

///|
test "empty filter object" {
  let input : Json = {
    "filter": Json::empty_object(),
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  let filter = match json {
    Json::Object(m) => m.get("filter")
    _ => abort("bad")
  }
  match filter {
    Some(f) => inspect(f.stringify(), content="{}")
    None => abort("filter missing")
  }
}

// ---------------------------------------------------------------------------
// Order to_json / from_json
// ---------------------------------------------------------------------------

///|
test "Order empty array" {
  let json : Json = Json::array([])
  let order : Order = @json.from_json(json)
  let out = order.to_json()
  inspect(out.stringify(), content="[]")
}

///|
test "Order single field" {
  let map = Map([], capacity=1)
  map.set("created_at", Json::string("desc"))
  let json = Json::array([Json::object(map)])
  let order : Order = @json.from_json(json)
  let out = order.to_json()
  inspect(out.stringify(), content="[{\"created_at\":\"desc\"}]")
}

///|
test "Order multiple fields" {
  let map1 = Map([], capacity=1)
  map1.set("age", Json::string("desc"))
  let map2 = Map([], capacity=1)
  map2.set("name", Json::string("asc"))
  let json = Json::array([Json::object(map1), Json::object(map2)])
  let order : Order = @json.from_json(json)
  let out = order.to_json()
  inspect(out.stringify(), content="[{\"age\":\"desc\"},{\"name\":\"asc\"}]")
}

// ---------------------------------------------------------------------------
// Page to_json / from_json
// ---------------------------------------------------------------------------

///|
test "Page normal values" {
  let map = Map([], capacity=2)
  map.set("after", Json::string("cursor_abc"))
  map.set("size", Json::number(25.0))
  let json = Json::object(map)
  let page : Page = @json.from_json(json)
  let out = page.to_json()
  inspect(out.stringify(), content="{\"after\":\"cursor_abc\",\"size\":25}")
}

///|
test "Page empty cursor and zero size" {
  let map = Map([], capacity=2)
  map.set("after", Json::string(""))
  map.set("size", Json::number(0.0))
  let json = Json::object(map)
  let page : Page = @json.from_json(json)
  let out = page.to_json()
  inspect(out.stringify(), content="{\"after\":\"\",\"size\":0}")
}

// ---------------------------------------------------------------------------
// Set passthrough
// ---------------------------------------------------------------------------

///|
test "set is passed through unchanged" {
  let input : Json = {
    "filter": { "x": 1.0 },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
    "set": { "context_key": "val", "num": 42.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  match json {
    Json::Object(m) =>
      match m.get("set") {
        Some(s) =>
          inspect(s.stringify(), content="{\"context_key\":\"val\",\"num\":42}")
        None => abort("set missing")
      }
    _ => abort("bad")
  }
}

// ---------------------------------------------------------------------------
// Error cases — order_by
// ---------------------------------------------------------------------------

///|
test "error: order_by not an array" {
  let input : Json = {
    "filter": { "x": 1.0 },
    "order_by": "not_array",
    "page": { "after": "", "size": 10.0 },
  }
  try {
    let _ : Query = @json.from_json(input)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

///|
test "error: order entry not an object" {
  let json = Json::array(["not_an_object"])
  try {
    let _ : Order = @json.from_json(json)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

///|
test "error: order direction not a string" {
  let map = Map([], capacity=1)
  map.set("field", Json::number(1.0))
  let json = Json::array([Json::object(map)])
  try {
    let _ : Order = @json.from_json(json)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Error cases — page
// ---------------------------------------------------------------------------

///|
test "error: page not an object" {
  let input : Json = { "filter": { "x": 1.0 }, "page": "not_object" }
  try {
    let _ : Query = @json.from_json(input)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

///|
test "error: page missing after" {
  let input : Json = { "filter": { "x": 1.0 }, "page": { "size": 10.0 } }
  try {
    let _ : Query = @json.from_json(input)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

///|
test "error: page missing size" {
  let input : Json = { "filter": { "x": 1.0 }, "page": { "after": "abc" } }
  try {
    let _ : Query = @json.from_json(input)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Error cases — query
// ---------------------------------------------------------------------------

///|
test "error: query not an object" {
  try {
    let _ : Query = @json.from_json(Json::string("nope"))
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}
