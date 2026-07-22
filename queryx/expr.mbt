// Expr — filter expression tree with to_json / from_json / eval.

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

///|
pub suberror QueryError {
  EvalError(String)
} derive(ToJson)

// ---------------------------------------------------------------------------
// Value — runtime values
// ---------------------------------------------------------------------------

///|
pub(all) enum Value {
  Null
  Bool(Bool)
  Int(Int64)
  Float(Double)
  String(String)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// ToValue trait — convert native MoonBit types into Value
// ---------------------------------------------------------------------------

///|
pub trait ToValue {
  fn to_value(Self) -> Value
}

///|
pub impl ToValue for Value with fn to_value(self) -> Value {
  self
}

///|
pub impl ToValue for Int with fn to_value(self) -> Value {
  Value::Int(self.to_int64())
}

///|
pub impl ToValue for Int64 with fn to_value(self) -> Value {
  Value::Int(self)
}

///|
pub impl ToValue for String with fn to_value(self) -> Value {
  Value::String(self)
}

///|
pub impl ToValue for Bool with fn to_value(self) -> Value {
  Value::Bool(self)
}

///|
pub impl ToValue for Double with fn to_value(self) -> Value {
  Value::Float(self)
}

// ---------------------------------------------------------------------------
// CmpOp / StrKind — comparison & string-match operators
// ---------------------------------------------------------------------------

///|
pub(all) enum CmpOp {
  Eq
  Ne
  Gt
  Lt
  Ge
  Le
} derive(Debug, Eq)

///|
pub(all) enum StrKind {
  Contains
  StartsWith
  EndsWith
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Expr — filter expression tree
// ---------------------------------------------------------------------------

///|
pub(all) enum Expr {
  Lit(Value) // literal value
  Field(String) // field reference
  Compare(String, CmpOp, Value) // field OP value
  Between(String, Value, Value) // field BETWEEN lo AND hi
  StrMatch(String, StrKind, String) // field STR_KIND pattern
  And(Array[Expr]) // logical AND
  Or(Array[Expr]) // logical OR
  Not(Expr) // logical NOT
  Empty // matches all
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Value :: ToJson / FromJson
// ---------------------------------------------------------------------------

///|
pub impl ToJson for Value with fn to_json(self : Value) -> Json {
  match self {
    Value::Null => Json::null()
    Value::Bool(b) => Json::boolean(b)
    Value::Int(n) => Json::number(n.to_double())
    Value::Float(f) => Json::number(f)
    Value::String(s) => Json::string(s)
  }
}

///|
pub impl @json.FromJson for Value with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Value raise @json.JsonDecodeError {
  match json {
    Json::Null => Value::Null
    Json::True => Value::Bool(true)
    Json::False => Value::Bool(false)
    Json::Number(n, ..) =>
      if n == n.to_int().to_double() {
        Value::Int(n.to_int64())
      } else {
        Value::Float(n)
      }
    Json::String(s) => Value::String(s)
    _ =>
      raise @json.JsonDecodeError(
        (path, "unsupported JSON literal: \{json.stringify()}"),
      )
  }
}

// ---------------------------------------------------------------------------
// Expr :: ToJson / FromJson
// ---------------------------------------------------------------------------

///|
pub impl ToJson for Expr with fn to_json(self : Expr) -> Json {
  match self {
    Expr::Empty => Json::empty_object()
    Expr::Lit(_) => Json::empty_object()
    Expr::Field(_) => Json::empty_object()
    Expr::Compare(field, CmpOp::Eq, val) => {
      let map = Map([], capacity=1)
      map.set(field, val.to_json())
      Json::object(map)
    }
    Expr::Compare(field, op, val) => {
      let map = Map([], capacity=1)
      let ops = Map([], capacity=1)
      ops.set(op_to_name(op), val.to_json())
      map.set(field, Json::object(ops))
      Json::object(map)
    }
    Expr::Between(field, lo, hi) => {
      let map = Map([], capacity=1)
      let ops = Map([], capacity=1)
      ops.set("between", Json::array([lo.to_json(), hi.to_json()]))
      map.set(field, Json::object(ops))
      Json::object(map)
    }
    Expr::StrMatch(field, kind, pattern) => {
      let map = Map([], capacity=1)
      let ops = Map([], capacity=1)
      ops.set(strkind_to_name(kind), Json::string(pattern))
      map.set(field, Json::object(ops))
      Json::object(map)
    }
    Expr::And(sub_exprs) => and_exprs_to_json(sub_exprs)
    Expr::Or(sub_exprs) => {
      let arr = sub_exprs.map(fn(e) { e.to_json() })
      let map = Map([], capacity=1)
      map.set("or", Json::array(arr))
      Json::object(map)
    }
    Expr::Not(sub) => {
      let map = Map([], capacity=1)
      map.set("not", sub.to_json())
      Json::object(map)
    }
  }
}

///|
pub impl @json.FromJson for Expr with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Expr raise @json.JsonDecodeError {
  match json {
    Json::Object(map) => parse_filter_object(map, path)
    _ =>
      raise @json.JsonDecodeError(
        (path, "filter must be a JSON object, got \{json.stringify()}"),
      )
  }
}

// ---------------------------------------------------------------------------
// Expr :: eval
// ---------------------------------------------------------------------------

///|
/// Evaluate the expression against a concrete map of field → value bindings.
pub fn Expr::eval(
  self : Expr,
  values : Map[String, Value],
) -> Bool raise QueryError {
  match self {
    Expr::Empty => true
    Expr::Lit(Value::Bool(b)) => b
    Expr::Lit(_) => raise EvalError("literal is not a boolean")
    Expr::Field(_) => raise EvalError("unresolved field")
    Expr::Compare(field, op, rhs) => {
      let lhs = match values.get(field) {
        Some(v) => v
        None => raise EvalError("missing value for field '\{field}'")
      }
      lhs.compare(op, rhs)
    }
    Expr::Between(field, lo, hi) => {
      let v = match values.get(field) {
        Some(x) => x
        None => raise EvalError("missing value for field '\{field}'")
      }
      v.compare(CmpOp::Ge, lo) && v.compare(CmpOp::Le, hi)
    }
    Expr::StrMatch(field, kind, pattern) => {
      let v = match values.get(field) {
        Some(Value::String(s)) => s
        Some(_) => raise EvalError("field '\{field}' is not a string")
        None => raise EvalError("missing value for field '\{field}'")
      }
      match kind {
        StrKind::Contains => v.contains(pattern)
        StrKind::StartsWith => v.has_prefix(pattern)
        StrKind::EndsWith => v.has_suffix(pattern)
      }
    }
    Expr::And(sub_exprs) => {
      for e in sub_exprs {
        if !e.eval(values) {
          return false
        }
      }
      true
    }
    Expr::Or(sub_exprs) => {
      for e in sub_exprs {
        if e.eval(values) {
          return true
        }
      }
      false
    }
    Expr::Not(sub) => !sub.eval(values)
  }
}

// ============================================================================
// Private helpers
// ============================================================================

// ---------------------------------------------------------------------------
// CmpOp ↔ operator name
// ---------------------------------------------------------------------------

///|
fn op_to_name(op : CmpOp) -> String {
  match op {
    CmpOp::Eq => "eq"
    CmpOp::Ne => "ne"
    CmpOp::Gt => "gt"
    CmpOp::Lt => "lt"
    CmpOp::Ge => "ge"
    CmpOp::Le => "le"
  }
}

// ---------------------------------------------------------------------------
// StrKind ↔ name
// ---------------------------------------------------------------------------

///|
fn strkind_to_name(kind : StrKind) -> String {
  match kind {
    StrKind::Contains => "contains"
    StrKind::StartsWith => "starts_with"
    StrKind::EndsWith => "ends_with"
  }
}

// ---------------------------------------------------------------------------
// Expr :: from_json helpers
// ---------------------------------------------------------------------------

///|
fn parse_filter_object(
  map : Map[String, Json],
  path : @json.JsonPath,
) -> Expr raise @json.JsonDecodeError {
  let exprs : Array[Expr] = []
  for key, value in map {
    match key {
      "or" =>
        match value {
          Json::Array(arr) => {
            let branches : Array[Expr] = []
            for v in arr {
              branches.push(@json.from_json(v))
            }
            exprs.push(Expr::Or(branches))
          }
          _ =>
            raise @json.JsonDecodeError(
              (path.add_key(key), "'or' value must be an array"),
            )
        }
      "and" =>
        match value {
          Json::Array(arr) => {
            let conjuncts : Array[Expr] = []
            for v in arr {
              conjuncts.push(@json.from_json(v))
            }
            exprs.push(Expr::And(conjuncts))
          }
          _ =>
            raise @json.JsonDecodeError(
              (path.add_key(key), "'and' value must be an array"),
            )
        }
      _ => exprs.push(parse_field_value(key, value, path.add_key(key)))
    }
  }
  match exprs.length() {
    0 => Expr::Empty
    1 => exprs[0]
    _ => Expr::And(exprs)
  }
}

///|
fn parse_field_value(
  field : String,
  value : Json,
  path : @json.JsonPath,
) -> Expr raise @json.JsonDecodeError {
  match value {
    Json::Object(ops_map) => {
      let conds : Array[Expr] = []
      for op_name, op_val in ops_map {
        conds.push(parse_field_operator(field, op_name, op_val, path))
      }
      match conds.length() {
        0 => Expr::Empty
        1 => conds[0]
        _ => Expr::And(conds)
      }
    }
    plain => Expr::Compare(field, CmpOp::Eq, @json.from_json(plain))
  }
}

///|
fn parse_field_operator(
  field : String,
  op_name : String,
  op_val : Json,
  path : @json.JsonPath,
) -> Expr raise @json.JsonDecodeError {
  match op_name {
    "eq" => Expr::Compare(field, CmpOp::Eq, @json.from_json(op_val))
    "ne" => Expr::Compare(field, CmpOp::Ne, @json.from_json(op_val))
    "gt" => Expr::Compare(field, CmpOp::Gt, @json.from_json(op_val))
    "lt" => Expr::Compare(field, CmpOp::Lt, @json.from_json(op_val))
    "ge" => Expr::Compare(field, CmpOp::Ge, @json.from_json(op_val))
    "le" => Expr::Compare(field, CmpOp::Le, @json.from_json(op_val))
    "contains" =>
      match op_val {
        Json::String(s) => Expr::StrMatch(field, StrKind::Contains, s)
        _ =>
          raise @json.JsonDecodeError(
            (path, "'contains' requires a string value"),
          )
      }
    "starts_with" =>
      match op_val {
        Json::String(s) => Expr::StrMatch(field, StrKind::StartsWith, s)
        _ =>
          raise @json.JsonDecodeError(
            (path, "'starts_with' requires a string value"),
          )
      }
    "ends_with" =>
      match op_val {
        Json::String(s) => Expr::StrMatch(field, StrKind::EndsWith, s)
        _ =>
          raise @json.JsonDecodeError(
            (path, "'ends_with' requires a string value"),
          )
      }
    "between" =>
      match op_val {
        Json::Array(arr) if arr.length() == 2 =>
          Expr::Between(field, @json.from_json(arr[0]), @json.from_json(arr[1]))
        _ =>
          raise @json.JsonDecodeError(
            (path, "'between' requires an array of exactly 2 values"),
          )
      }
    _ => raise @json.JsonDecodeError((path, "unknown operator '\{op_name}'"))
  }
}

// ---------------------------------------------------------------------------
// Expr :: to_json helpers
// ---------------------------------------------------------------------------

///|
fn and_exprs_to_json(sub_exprs : Array[Expr]) -> Json {
  let map = Map([])
  for e in sub_exprs {
    match e {
      Expr::Compare(field, CmpOp::Eq, val) =>
        merge_field_value(map, field, "eq", val.to_json())
      Expr::Compare(field, op, val) =>
        merge_field_value(map, field, op_to_name(op), val.to_json())
      Expr::Between(field, lo, hi) => {
        let ops = Map([], capacity=1)
        ops.set("between", Json::array([lo.to_json(), hi.to_json()]))
        map.set(field, Json::object(ops))
      }
      Expr::StrMatch(field, kind, pat) =>
        merge_field_value(map, field, strkind_to_name(kind), Json::string(pat))
      Expr::Or(sub) =>
        map.set("or", Json::array(sub.map(fn(s) { s.to_json() })))
      Expr::And(inner) =>
        match Expr::And(inner).to_json() {
          Json::Object(inner_map) =>
            for k, v in inner_map {
              merge_field_json(map, k, v)
            }
          _ => ()
        }
      Expr::Not(_) => map.set("not", e.to_json())
      _ => ()
    }
  }
  collapse_between_in_map(map)
  Json::object(map)
}

///|
/// Walk a filter map and collapse any ge+le / gt+lt pairs into `between`.
fn collapse_between_in_map(map : Map[String, Json]) -> Unit {
  for _, val in map {
    match val {
      Json::Object(ops) => {
        match (ops.get("ge"), ops.get("le")) {
          (Some(lo), Some(hi)) => {
            ops.remove("ge")
            ops.remove("le")
            ops.set("between", Json::array([lo, hi]))
          }
          _ => ()
        }
        match (ops.get("gt"), ops.get("lt")) {
          (Some(lo), Some(hi)) => {
            ops.remove("gt")
            ops.remove("lt")
            ops.set("between", Json::array([lo, hi]))
          }
          _ => ()
        }
        match (ops.get("gt"), ops.get("le")) {
          (Some(lo), Some(hi)) => {
            ops.remove("gt")
            ops.remove("le")
            ops.set("between", Json::array([lo, hi]))
          }
          _ => ()
        }
        match (ops.get("ge"), ops.get("lt")) {
          (Some(lo), Some(hi)) => {
            ops.remove("ge")
            ops.remove("lt")
            ops.set("between", Json::array([lo, hi]))
          }
          _ => ()
        }
      }
      _ => ()
    }
  }
}

///|
/// Merge a single (op_name, json_val) into the map for a field.
fn merge_field_value(
  map : Map[String, Json],
  field : String,
  op_name : String,
  val : Json,
) -> Unit {
  if op_name == "eq" {
    merge_field_json(map, field, val)
  } else {
    let ops = Map([], capacity=1)
    ops.set(op_name, val)
    merge_field_json(map, field, Json::object(ops))
  }
}

///|
fn merge_field_json(
  map : Map[String, Json],
  field : String,
  val : Json,
) -> Unit {
  match map.get(field) {
    None => map.set(field, val)
    Some(Json::Object(existing)) =>
      match val {
        Json::Object(v_ops) =>
          for op_k, op_v in v_ops {
            existing.set(op_k, op_v)
          }
        plain => existing.set("eq", plain)
      }
    Some(plain) => {
      let ops = Map([], capacity=2)
      ops.set("eq", plain)
      match val {
        Json::Object(v_ops) =>
          for op_k, op_v in v_ops {
            ops.set(op_k, op_v)
          }
        other => ops.set("eq", other)
      }
      map.set(field, Json::object(ops))
    }
  }
}

// ---------------------------------------------------------------------------
// Value comparison helpers (for eval)
// ---------------------------------------------------------------------------

///|
fn Value::compare(
  self : Value,
  op : CmpOp,
  other : Value,
) -> Bool raise QueryError {
  let ordering = value_ord(self, other)
  match op {
    CmpOp::Eq => ordering == 0
    CmpOp::Ne => ordering != 0
    CmpOp::Gt => ordering > 0
    CmpOp::Lt => ordering < 0
    CmpOp::Ge => ordering >= 0
    CmpOp::Le => ordering <= 0
  }
}

///|
fn value_ord(a : Value, b : Value) -> Int raise QueryError {
  match (a, b) {
    (Value::Int(x), Value::Int(y)) => x.compare(y)
    (Value::Float(x), Value::Float(y)) => x.compare(y)
    (Value::Int(x), Value::Float(y)) => x.to_double().compare(y)
    (Value::Float(x), Value::Int(y)) => x.compare(y.to_double())
    (Value::String(x), Value::String(y)) => x.compare(y)
    (Value::Bool(x), Value::Bool(y)) =>
      if x == y {
        0
      } else if x {
        1
      } else {
        -1
      }
    (Value::Null, Value::Null) => 0
    _ => raise EvalError("type mismatch: cannot compare the two values")
  }
}
