// QueryX — query DSL with to_json / from_json.

// ---------------------------------------------------------------------------
// Order / Page / Query — top-level query types
// ---------------------------------------------------------------------------

///|
pub(all) struct Order(String) derive(Debug)

///|
pub(all) struct Page {
  after : String
  size : Int
} derive(Debug, ToJson, FromJson)

///|
pub(all) struct Query {
  filter : Expr
  order_by : Order?
  page : Page?
  set : Json?
} derive(Debug)

// ---------------------------------------------------------------------------
// Order :: ToJson / FromJson
// ---------------------------------------------------------------------------

///|
pub impl ToJson for Order with fn to_json(self : Order) -> Json {
  let s = self.0
  if s == "" {
    return Json::array([])
  }
  let parts = split_by(s, ',')
  let arr : Array[Json] = []
  for part in parts {
    let kv = split_by(part, ':')
    if kv.length() >= 2 {
      let map = Map([], capacity=1)
      map.set(kv[0], Json::string(kv[1]))
      arr.push(Json::object(map))
    }
  }
  Json::array(arr)
}

///|
pub impl @json.FromJson for Order with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Order raise @json.JsonDecodeError {
  match json {
    Json::Array(arr) => {
      let parts : Array[String] = []
      for i = 0; i < arr.length(); i = i + 1 {
        let entry = arr[i]
        match entry {
          Json::Object(obj) =>
            for field, dir in obj {
              match dir {
                Json::String(d) => parts.push(field + ":" + d)
                _ =>
                  raise @json.JsonDecodeError(
                    (path.add_index(i), "direction must be a string"),
                  )
              }
            }
          _ =>
            raise @json.JsonDecodeError(
              (path.add_index(i), "each entry must be a JSON object"),
            )
        }
      }
      Order(join_with(parts, ","))
    }
    _ => raise @json.JsonDecodeError((path, "expected a JSON array"))
  }
}

// ---------------------------------------------------------------------------
// Query :: ToJson / FromJson
// ---------------------------------------------------------------------------

///|
pub impl ToJson for Query with fn to_json(self : Query) -> Json {
  let map = Map([])
  map.set("filter", self.filter.to_json())
  match self.order_by {
    Some(o) => map.set("order_by", o.to_json())
    None => ()
  }
  match self.page {
    Some(p) => map.set("page", p.to_json())
    None => ()
  }
  match self.set {
    Some(s) => map.set("set", s)
    None => ()
  }
  Json::object(map)
}

///|
pub impl @json.FromJson for Query with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> Query raise @json.JsonDecodeError {
  match json {
    Json::Object(map) => {
      let filter = match map.get("filter") {
        Some(f) => @json.from_json(f)
        None => Expr::Empty
      }
      let order_by : Order? = match map.get("order_by") {
        Some(o) => Some(@json.from_json(o))
        None => None
      }
      let page : Page? = match map.get("page") {
        Some(p) => Some(@json.from_json(p))
        None => None
      }
      let set = match map.get("set") {
        Some(s) => Some(s)
        None => None
      }
      { filter, order_by, page, set }
    }
    _ => raise @json.JsonDecodeError((path, "expected a JSON object"))
  }
}

// ---------------------------------------------------------------------------
// String helpers (shared by Order)
// ---------------------------------------------------------------------------

///|
fn split_by(s : String, delim : Char) -> Array[String] {
  split_rec(s, delim, 0, 0, [])
}

///|
fn split_rec(
  s : String,
  delim : Char,
  start : Int,
  pos : Int,
  acc : Array[String],
) -> Array[String] {
  if pos >= s.length() {
    let last = s[start:].trim().to_owned()
    if last != "" {
      acc.push(last)
    }
    acc
  } else if s[pos:pos + 1] == delim.to_string() {
    let part = s[start:pos].trim().to_owned()
    if part != "" {
      acc.push(part)
    }
    split_rec(s, delim, pos + 1, pos + 1, acc)
  } else {
    split_rec(s, delim, start, pos + 1, acc)
  }
}

///|
fn join_with(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let buf = StringBuilder(size_hint=0)
  buf.write_string(parts[0])
  for i = 1; i < parts.length(); i = i + 1 {
    buf.write_string(sep)
    buf.write_string(parts[i])
  }
  buf.to_string()
}
