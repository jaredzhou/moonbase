// InsertBuilder — fluent builder for INSERT statements.

///|
/// A fluent builder for an INSERT query.  Terminal: `.to_sql()`.
pub(all) struct InsertBuilder {
  table : Table
  columns : Array[@ast.ColumnRef]
  values : Array[Array[@ast.Value]]
  returning : Array[@ast.ColumnRef]?
} derive(Debug, Eq)

///|
/// Create a new InsertBuilder.  Internal — users call `table.insert(..)` instead.
pub fn InsertBuilder::new(
  table : Table,
  columns : Array[&AnyColumn],
) -> InsertBuilder {
  InsertBuilder::{ table, columns: columns.map(c=>c.to_ref()), values: [], returning: None }
}

///|
/// Add a single-row VALUES clause.
pub fn InsertBuilder::values(
  self : InsertBuilder,
  vals : Array[@ast.Value],
) -> InsertBuilder {
  InsertBuilder::{ ..self, values: [vals] }
}

///|
/// Add a multi-row VALUES clause.
pub fn InsertBuilder::rows(
  self : InsertBuilder,
  rows : Array[Array[@ast.Value]],
) -> InsertBuilder {
  InsertBuilder::{ ..self, values: rows }
}

///|
/// Attach a RETURNING clause.
pub fn InsertBuilder::returning(
  self : InsertBuilder,
  cols : Array[&AnyColumn],
) -> InsertBuilder {
  InsertBuilder::{ ..self, returning: Some(cols.map(c=>c.to_ref())) }
}

///|
/// Render the query to a parameterised SQL string + args array.
pub fn InsertBuilder::to_sql(self : InsertBuilder) -> (String, Array[@ast.Value]) {
  let node = @ast.InsertStmt::{
    table: self.table.qualified_name(),
    columns: self.columns,
    values: self.values,
    on_conflict: None,
    returning: self.returning,
  }
  @tosql.insert_stmt_to_sql(node)
}
