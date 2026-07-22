// Table — table identity.
//
// Users embed this in their per-table proxy struct alongside Column[T] fields:
//
//   struct UserTable { table : Table; id : Column[Int]; name : Column[String] }

///|
/// Table identity — name and optional schema.
pub(all) struct Table {
  name : String
  schema_name : String?
} derive(Debug, Eq)

///|
/// Create a table, optionally qualified with a schema.
pub fn Table::new(
  name : String,
  schema? : String,
) -> Table {
  Table::{ name, schema_name: schema }
}

///|
/// Return the fully-qualified table name for use in SQL (schema.name or name).
pub fn Table::qualified_name(self : Table) -> String {
  match self.schema_name {
    Some(s) => s + "." + self.name
    None => self.name
  }
}

///|
/// Start building a SELECT query on this table.  Omit columns for `SELECT *`.
pub fn Table::select(
  self : Table,
  columns? : Array[&AnyColumn],
) -> SelectBuilder {
  let refs = columns.unwrap_or([]).map(c=>c.to_ref())
  SelectBuilder::new(self, refs)
}
