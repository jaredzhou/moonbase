// Cedar runtime types — the type system and value representations.
// References:
//   Rust: cedar-policy-core/src/ast/ (Type, ValueKind, EntityUID)
//   Go:   cedar-go/types/ (Value interface, concrete types)

// ---------------------------------------------------------------------------
// Identifiers & Names
// ---------------------------------------------------------------------------

///|
/// A unique entity identifier, e.g. `User::"alice"`.
pub(all) struct EntityUID {
  type_ : String
  id : String
} derive(Debug, Eq, Hash)

///|
/// An entity type name, e.g. `User`, `Photo`.
pub(all) struct EntityType(String) derive(Debug, Eq, ToJson, FromJson)

///|
/// A namespaced path for extension functions, e.g. `ip`, `decimal`.
pub(all) struct Name {
  ns : Array[String]
  name : String
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Source position for diagnostics / error messages.
pub(all) struct Position {
  filename : String // optional source file name, "" if unknown
  offset : Int // byte offset, starting at 0
  line : Int // line number, starting at 1
  column : Int // column number, starting at 1
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Pattern (for the `like` operator)
// ---------------------------------------------------------------------------

///|
/// Pattern for the `like` operator (IAM-style `StringLike`).
/// The wildcard `*` matches any string; `\*` matches a literal `*`.
pub(all) struct Pattern {
  elements : Array[PatternElem]
} derive(Debug, Eq)

///|
pub(all) enum PatternElem {
  Char(Char)
  Wildcard
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Type — the Cedar type system (Rust approach)
// ---------------------------------------------------------------------------

///|
/// The runtime type of a Cedar value.
/// Two entity types are equal iff they have the same Name.
/// Two extension types are equal iff they have the same Name.
pub(all) enum Type {
  Bool
  Long
  String
  Set
  Record
  Entity(EntityType)
  Extension(Name)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Value — all runtime values (Rust ValueKind, flattened)
// ---------------------------------------------------------------------------

///|
/// All values that can be the dynamic result of evaluating an Expr.
/// Includes extension values (ip, decimal, datetime, duration, etc.)
/// as opaque Extension(Name, String) entries for MVP.
pub(all) enum Value {
  Bool(Bool)
  Long(Int64)
  String(String)
  EntityUID(EntityUID)
  Set(Array[Value])
  Record(Map[String, Value])
  Extension(Name, String) // opaque: (fn_name, serialized_arg)
} derive(Debug, Eq, ToJson, FromJson)

// ---------------------------------------------------------------------------
// Entity — application data for evaluation (attrs + tags + parents)
// ---------------------------------------------------------------------------

///|
/// An entity as provided by the application. Contains attributes (schema-defined),
/// tags (free-form), and parent relationships for hierarchy traversal (`in` operator).
pub(all) struct Entity {
  uid : EntityUID
  attrs : Map[String, Value]
  tags : Map[String, Value]
  parents : Array[EntityUID]
} derive(Debug, Eq, ToJson, FromJson)

// (Request, Decision, Diagnostic* types moved to evaluator/request.mbt)

// ---------------------------------------------------------------------------
// EntityUID JSON: map type_ (MoonBit keyword workaround) ↔ "type" (Cedar JSON)
// ---------------------------------------------------------------------------

///|
/// Serialize EntityUID as Cedar-compatible JSON: { "type": "...", "id": "..." }.
pub impl ToJson for EntityUID with fn to_json(self) -> Json {
  Json::object(
    Map([("type", Json::string(self.type_)), ("id", Json::string(self.id))]),
  )
}

///|
/// Deserialize from Cedar JSON entity UID format.
pub impl FromJson for EntityUID with fn from_json(
  json : Json,
  path : @json.JsonPath,
) -> EntityUID raise @json.JsonDecodeError {
  match json {
    Json::Object(fields) =>
      match (fields.get("type"), fields.get("id")) {
        (Some(Json::String(type_s)), Some(Json::String(id_s))) =>
          EntityUID::{ type_: type_s, id: id_s }
        _ => {
          let payload : (@json.JsonPath, String) = (
            path, "expected {type, id} for EntityUID",
          )
          raise @json.JsonDecodeError(payload)
        }
      }
    _ => {
      let payload : (@json.JsonPath, String) = (
        path, "expected object for EntityUID",
      )
      raise @json.JsonDecodeError(payload)
    }
  }
}
