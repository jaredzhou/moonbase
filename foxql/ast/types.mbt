// Types shared across all foxql sub-packages.

///|
/// PostgreSQL column types.
pub(all) enum SqlType {
  Integer
  BigInt
  Text
  Boolean
  DoublePrecision
  Bytea
  TimestampTz
  Numeric
  Jsonb
} derive(Debug, Eq)

///|
/// A runtime parameterised value — each variant maps to a PG type.
pub(all) enum Value {
  Null
  Bool(Bool)
  Int(Int)
  Float(Double)
  String(String)
} derive(Debug, Eq)

///|
/// Convert a MoonBit native type into a parameterised Value.
pub trait ToValue {
  fn to_value(Self) -> Value
}

///|
pub impl ToValue for Int with fn to_value(self : Int) -> Value {
  Value::Int(self)
}

///|
pub impl ToValue for String with fn to_value(self : String) -> Value {
  Value::String(self)
}

///|
pub impl ToValue for Bool with fn to_value(self : Bool) -> Value {
  Value::Bool(self)
}

///|
pub impl ToValue for Double with fn to_value(self : Double) -> Value {
  Value::Float(self)
}

///|
/// Identifies a column by (table, name).
pub(all) struct ColumnRef {
  name : String
  table : String
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Bridge to moonpg — foxql Values can be passed directly to conn.query().
// ---------------------------------------------------------------------------

///|
pub impl @moonpg.ToValue for Value with fn to_value(self : Value) -> @moonpg.Value {
  match self {
    Value::Null => {
      let none : Int? = None
      @moonpg.ToValue::to_value(none)
    }
    Value::Bool(b) => @moonpg.ToValue::to_value(b)
    Value::Int(i) => @moonpg.ToValue::to_value(i)
    Value::Float(f) => @moonpg.ToValue::to_value(f)
    Value::String(s) => @moonpg.ToValue::to_value(s)
  }
}
