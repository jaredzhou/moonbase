// SelectBuilder — fluent builder for SELECT statements.

///|
/// A fluent builder for a SELECT query.  Terminal: `.to_sql()`.
pub(all) struct SelectBuilder {
  table : Table
  columns : Array[@ast.ColumnRef]
  where_clause : @ast.Expr?
} derive(Debug, Eq)

///|
/// Create a new SelectBuilder.  Internal — users call `table.select(..)` instead.
/// Pass an empty list or omit the argument for `SELECT *`.
pub fn SelectBuilder::new(
  table : Table,
  columns : Array[@ast.ColumnRef],
) -> SelectBuilder {
  SelectBuilder::{ table, columns, where_clause: None }
}

///|
/// Attach a WHERE clause to this SELECT.
pub fn SelectBuilder::where_(
  self : SelectBuilder,
  condition : @ast.Expr,
) -> SelectBuilder {
  SelectBuilder::{ ..self, where_clause: Some(condition) }
}

///|
/// Produce the AST node without rendering.
pub fn SelectBuilder::to_stmt(self : SelectBuilder) -> @ast.SelectStmt {
  @ast.SelectStmt::{
    table: self.table.qualified_name(),
    columns: self.columns,
    where_clause: self.where_clause,
  }
}

///|
/// Render the query to a parameterised SQL string + args array.
pub fn SelectBuilder::to_sql(self : SelectBuilder) -> (String, Array[@ast.Value]) {
  @tosql.select_stmt_to_sql(self.to_stmt())
}
