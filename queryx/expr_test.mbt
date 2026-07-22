// Tests for Expr — filter operators, logical operators, between collapse, and eval.

// ---------------------------------------------------------------------------
// Filter operators — one per test
// ---------------------------------------------------------------------------

///|
test "eq operator (compact plain-value form)" {
  let input : Json = {
    "filter": { "status": "active" },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"status\":\"active\"},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "ne operator" {
  let input : Json = {
    "filter": { "status": { "ne": "deleted" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"status\":{\"ne\":\"deleted\"}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "gt operator" {
  let input : Json = {
    "filter": { "score": { "gt": 50.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"score\":{\"gt\":50}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "lt operator" {
  let input : Json = {
    "filter": { "score": { "lt": 100.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"score\":{\"lt\":100}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "ge operator" {
  let input : Json = {
    "filter": { "score": { "ge": 0.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"score\":{\"ge\":0}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "le operator" {
  let input : Json = {
    "filter": { "score": { "le": 100.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"score\":{\"le\":100}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "explicit eq serializes to compact form" {
  let input : Json = {
    "filter": { "status": { "eq": "active" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"status\":\"active\"},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "contains operator" {
  let input : Json = {
    "filter": { "name": { "contains": "tom" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"name\":{\"contains\":\"tom\"}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "starts_with operator" {
  let input : Json = {
    "filter": { "name": { "starts_with": "Mr." } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"name\":{\"starts_with\":\"Mr.\"}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "ends_with operator" {
  let input : Json = {
    "filter": { "email": { "ends_with": "@example.com" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"email\":{\"ends_with\":\"@example.com\"}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

// ---------------------------------------------------------------------------
// Between operator
// ---------------------------------------------------------------------------

///|
test "between operator with strings" {
  let input : Json = {
    "filter": { "created_at": { "between": ["2024-01-01", "2025-01-01"] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"created_at\":{\"between\":[\"2024-01-01\",\"2025-01-01\"]}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "between operator with numbers" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"age\":{\"between\":[18,65]}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

// ---------------------------------------------------------------------------
// Between collapse: separate range ops → single between
// ---------------------------------------------------------------------------

///|
test "gt+lt pair collapses to between" {
  let input : Json = {
    "filter": { "age": { "gt": 18.0, "lt": 30.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"age\":{\"between\":[18,30]}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "gt+le pair collapses to between" {
  let input : Json = {
    "filter": { "age": { "gt": 18.0, "le": 30.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"age\":{\"between\":[18,30]}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "ge+lt pair collapses to between" {
  let input : Json = {
    "filter": { "age": { "ge": 18.0, "lt": 30.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"age\":{\"between\":[18,30]}},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

// ---------------------------------------------------------------------------
// Logical operators
// ---------------------------------------------------------------------------

///|
test "or with two branches" {
  let input : Json = {
    "filter": { "or": [{ "status": "A" }, { "status": "B" }] },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"or\":[{\"status\":\"A\"},{\"status\":\"B\"}]},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "or with three branches" {
  let input : Json = {
    "filter": { "or": [{ "x": 1.0 }, { "x": 2.0 }, { "x": 3.0 }] },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  inspect(
    json.stringify(),
    content="{\"filter\":{\"or\":[{\"x\":1},{\"x\":2},{\"x\":3}]},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}",
  )
}

///|
test "explicit and flattened into parent object" {
  let input : Json = {
    "filter": { "and": [{ "a": 1.0 }, { "b": 2.0 }] },
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
    Some(f) => inspect(f.stringify(), content="{\"a\":1,\"b\":2}")
    None => abort("filter missing")
  }
}

///|
test "nested or inside top-level fields" {
  let input : Json = {
    "filter": {
      "category": "book",
      "or": [{ "status": "A" }, { "status": "B" }],
    },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  let want = "{\"filter\":{\"category\":\"book\",\"or\":[{\"status\":\"A\"},{\"status\":\"B\"}]},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}"
  inspect(json.stringify(), content=want)
}

///|
test "multiple fields ANDed implicitly" {
  let input : Json = {
    "filter": { "a": 1.0, "b": 2.0, "c": 3.0 },
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
    Some(f) => inspect(f.stringify(), content="{\"a\":1,\"b\":2,\"c\":3}")
    None => abort("filter missing")
  }
}

// ---------------------------------------------------------------------------
// Deeply nested
// ---------------------------------------------------------------------------

///|
test "nested or with multi-field branches" {
  let input : Json = {
    "filter": {
      "or": [
        { "status": "A", "priority": { "gt": 5.0 } },
        { "status": "B", "priority": { "lt": 3.0 } },
      ],
    },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let json = query.to_json()
  let want = "{\"filter\":{\"or\":[{\"status\":\"A\",\"priority\":{\"gt\":5}},{\"status\":\"B\",\"priority\":{\"lt\":3}}]},\"order_by\":[],\"page\":{\"after\":\"\",\"size\":10}}"
  inspect(json.stringify(), content=want)
}

// ---------------------------------------------------------------------------
// Boolean values
// ---------------------------------------------------------------------------

///|
test "boolean true" {
  let input : Json = {
    "filter": { "active": true },
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
    Some(f) => inspect(f.stringify(), content="{\"active\":true}")
    None => abort("filter missing")
  }
}

///|
test "boolean false" {
  let input : Json = {
    "filter": { "deleted": false },
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
    Some(f) => inspect(f.stringify(), content="{\"deleted\":false}")
    None => abort("filter missing")
  }
}

// ---------------------------------------------------------------------------
// Edge values
// ---------------------------------------------------------------------------

///|
test "filter with zero value" {
  let input : Json = {
    "filter": { "count": 0.0 },
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
    Some(f) => inspect(f.stringify(), content="{\"count\":0}")
    None => abort("filter missing")
  }
}

///|
test "filter with negative value" {
  let input : Json = {
    "filter": { "temperature": { "lt": -10.0 } },
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
    Some(f) => inspect(f.stringify(), content="{\"temperature\":{\"lt\":-10}}")
    None => abort("filter missing")
  }
}

// ---------------------------------------------------------------------------
// Error cases — filter
// ---------------------------------------------------------------------------

///|
test "error: filter not an object" {
  let input : Json = {
    "filter": "not_an_object",
    "order_by": [],
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
test "error: or value not an array" {
  let input : Json = {
    "filter": { "or": "not_an_array" },
    "order_by": [],
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
test "error: between needs exactly 2 values" {
  let input : Json = {
    "filter": { "age": { "between": [1.0] } },
    "order_by": [],
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
test "error: between needs array" {
  let input : Json = {
    "filter": { "age": { "between": 42.0 } },
    "order_by": [],
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
test "error: unknown operator" {
  let input : Json = {
    "filter": { "age": { "regex": ".*" } },
    "order_by": [],
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
test "error: starts_with requires string" {
  let input : Json = {
    "filter": { "age": { "starts_with": 1.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  try {
    let _ : Query = @json.from_json(input)
    abort("expected error")
  } catch {
    @json.JsonDecodeError(_) => ()
  }
}

// ---------------------------------------------------------------------------
// Query::eval
// ---------------------------------------------------------------------------

///|
test "eval eq match" {
  let input : Json = {
    "filter": { "status": "active" },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("active"))
  assert_true(query.filter.eval(values))
}

///|
test "eval eq no match" {
  let input : Json = {
    "filter": { "status": "active" },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("inactive"))
  assert_false(query.filter.eval(values))
}

///|
test "eval gt match" {
  let input : Json = {
    "filter": { "age": { "gt": 18.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(25))
  assert_true(query.filter.eval(values))
}

///|
test "eval gt no match" {
  let input : Json = {
    "filter": { "age": { "gt": 18.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(10))
  assert_false(query.filter.eval(values))
}

///|
test "eval between match" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(30))
  assert_true(query.filter.eval(values))
}

///|
test "eval between boundary lo" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(18))
  assert_true(query.filter.eval(values))
}

///|
test "eval between boundary hi" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(65))
  assert_true(query.filter.eval(values))
}

///|
test "eval between no match low" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(10))
  assert_false(query.filter.eval(values))
}

///|
test "eval between no match high" {
  let input : Json = {
    "filter": { "age": { "between": [18.0, 65.0] } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("age", Value::Int(100))
  assert_false(query.filter.eval(values))
}

///|
test "eval contains match" {
  let input : Json = {
    "filter": { "name": { "contains": "tom" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("name", Value::String("tommy"))
  assert_true(query.filter.eval(values))
}

///|
test "eval contains no match" {
  let input : Json = {
    "filter": { "name": { "contains": "tom" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("name", Value::String("jerry"))
  assert_false(query.filter.eval(values))
}

///|
test "eval starts_with match" {
  let input : Json = {
    "filter": { "name": { "starts_with": "Mr." } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("name", Value::String("Mr. Smith"))
  assert_true(query.filter.eval(values))
}

///|
test "eval starts_with no match" {
  let input : Json = {
    "filter": { "name": { "starts_with": "Mr." } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("name", Value::String("Dr. Jones"))
  assert_false(query.filter.eval(values))
}

///|
test "eval ends_with match" {
  let input : Json = {
    "filter": { "email": { "ends_with": "@example.com" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("email", Value::String("user@example.com"))
  assert_true(query.filter.eval(values))
}

///|
test "eval ends_with no match" {
  let input : Json = {
    "filter": { "email": { "ends_with": "@example.com" } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("email", Value::String("user@other.com"))
  assert_false(query.filter.eval(values))
}

///|
test "eval or match first branch" {
  let input : Json = {
    "filter": { "or": [{ "status": "A" }, { "status": "B" }] },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("A"))
  assert_true(query.filter.eval(values))
}

///|
test "eval or match second branch" {
  let input : Json = {
    "filter": { "or": [{ "status": "A" }, { "status": "B" }] },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("B"))
  assert_true(query.filter.eval(values))
}

///|
test "eval or no match" {
  let input : Json = {
    "filter": { "or": [{ "status": "A" }, { "status": "B" }] },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("C"))
  assert_false(query.filter.eval(values))
}

///|
test "eval multiple fields ANDed" {
  let input : Json = {
    "filter": { "status": "active", "score": { "gt": 50.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("active"))
  values.set("score", Value::Int(75))
  assert_true(query.filter.eval(values))
}

///|
test "eval multiple fields ANDed fail one" {
  let input : Json = {
    "filter": { "status": "active", "score": { "gt": 50.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  values.set("status", Value::String("active"))
  values.set("score", Value::Int(30))
  assert_false(query.filter.eval(values))
}

///|
test "eval unknown field becomes residual" {
  let input : Json = {
    "filter": { "age": { "gt": 18.0 } },
    "order_by": [],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let values : Map[String, Value] = Map([])
  // age is missing — substitute_unknowns leaves Unknown as-is,
  // eval_expr returns Residual, eval raises TypeMismatch
  try {
    let _ = query.filter.eval(values)
    abort("expected error")
  } catch {
    QueryError::EvalError(_) => ()
  }
}

// ---------------------------------------------------------------------------
// ToValue trait
// ---------------------------------------------------------------------------

///|
test "ToValue Int" {
  let v = ToValue::to_value(42)
  match v {
    Value::Int(n) => assert_eq(n, 42L)
    _ => abort("expected Long")
  }
}

///|
test "ToValue Int64" {
  let v = ToValue::to_value(99L)
  match v {
    Value::Int(n) => assert_eq(n, 99L)
    _ => abort("expected Long")
  }
}

///|
test "ToValue String" {
  let v = ToValue::to_value("hello")
  match v {
    Value::String(s) => assert_eq(s, "hello")
    _ => abort("expected String")
  }
}

///|
test "ToValue Bool" {
  let v = ToValue::to_value(true)
  match v {
    Value::Bool(b) => assert_true(b)
    _ => abort("expected Bool")
  }
}

///|
test "ToValue Double" {
  let v = ToValue::to_value(3.14)
  match v {
    Value::Float(f) => assert_eq(f, 3.14)
    _ => abort("expected Float")
  }
}
