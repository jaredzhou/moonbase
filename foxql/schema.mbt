// Schema — introspected table metadata for dynamic query building.
//
// Usage:
//   1. Query information_schema.columns on startup.
//   2. Build SchemaColumn values, pass to Schema::load.
//   3. schema.table("users") returns a SchemaTable.
//   4. Use .col("name"), .select(), .insert(), etc. just like a static proxy.

// ---------------------------------------------------------------------------
// SchemaColumn — one column's metadata
// ---------------------------------------------------------------------------

///|
/// One column's metadata, typically from information_schema.columns.
pub(all) struct SchemaColumn {
  table_name : String
  column_name : String
  sql_type : @ast.SqlType
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Schema — table → columns index
// ---------------------------------------------------------------------------

///|
/// Introspected schema.  Build with Schema::load.
pub(all) struct Schema {
  tables : Map[String, Map[String, @ast.SqlType]]
}

///|
/// Load schema from a flat list of column descriptors.
pub fn Schema::load(columns : Array[SchemaColumn]) -> Schema {
  let tables : Map[String, Map[String, @ast.SqlType]] = Map([])
  for c in columns {
    match tables.get(c.table_name) {
      Some(cols) => cols.set(c.column_name, c.sql_type)
      None => {
        let cols : Map[String, @ast.SqlType] = Map([])
        cols.set(c.column_name, c.sql_type)
        tables.set(c.table_name, cols)
      }
    }
  }
  Schema::{ tables, }
}

///|
/// Get a dynamic table reference.  Panics if the table is not in the schema.
pub fn Schema::table(self : Schema, name : String) -> SchemaTable {
  let cols = match self.tables.get(name) {
    Some(c) => c
    None => abort("table not found in schema: \{name}")
  }
  SchemaTable::{ table_name: name, columns: cols }
}

// ---------------------------------------------------------------------------
// SchemaTable — a dynamic table that exposes the same builders as a static proxy
// ---------------------------------------------------------------------------

///|
/// A dynamic table reference.  Exposes .select() / .insert() / .update() / .delete().
pub(all) struct SchemaTable {
  table_name : String
  columns : Map[String, @ast.SqlType]
}

///|
/// Get a ColumnRef for a column.  Panics if the column is not in the schema.
pub fn SchemaTable::col(self : SchemaTable, name : String) -> @ast.ColumnRef {
  match self.columns.get(name) {
    Some(_) => @ast.ColumnRef::{ name, table: self.table_name }
    None => abort("column not found in schema: \{self.table_name}.\{name}")
  }
}

///|
/// Check whether a column exists.
pub fn SchemaTable::has_column(self : SchemaTable, name : String) -> Bool {
  self.columns.get(name) is Some(_)
}

///|
/// Start building a SELECT query.  Omit columns for SELECT *.
pub fn SchemaTable::select(
  self : SchemaTable,
  columns? : Array[&@builder.AnyColumn],
) -> @builder.SelectBuilder {
  let cols = match columns {
    Some(arr) => arr.map(c => c.to_ref())
    None => []
  }
  @builder.SelectBuilder::new(@builder.Table::new(self.table_name), cols)
}

///|
/// Start building an INSERT query.
pub fn SchemaTable::insert(
  self : SchemaTable,
  columns : Array[&@builder.AnyColumn],
) -> @builder.InsertBuilder {
  @builder.InsertBuilder::new(@builder.Table::new(self.table_name), columns)
}

///|
/// Start building an UPDATE query.  Requires .where_() before .to_sql().
pub fn SchemaTable::update(self : SchemaTable) -> @builder.UpdateBuilder {
  @builder.UpdateBuilder::new(@builder.Table::new(self.table_name))
}

///|
/// Start building a DELETE query.  Requires .where_() before .to_sql().
pub fn SchemaTable::delete(self : SchemaTable) -> @builder.DeleteBuilder {
  @builder.DeleteBuilder::new(@builder.Table::new(self.table_name))
}
