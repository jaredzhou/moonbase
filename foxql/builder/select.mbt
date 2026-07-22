// SelectBuilder — fluent builder for SELECT statements.

///|
/// A fluent builder for a SELECT query.  Terminal: `.to_sql()` or `.build()`.
pub(all) struct SelectBuilder {
  table : Table
  columns : Array[@ast.ColumnRef]
  where_clause : @ast.Expr?
  joins : Array[@ast.JoinClause]
  order_by : Array[@ast.OrderByClause]
  limit : Int?
  offset : Int?
  distinct : Bool
  distinct_on : Array[@ast.ColumnRef]
} derive(Debug, Eq)

///|
/// Create a new SelectBuilder.  Internal — users call `table.select(..)` instead.
pub fn SelectBuilder::new(
  table : Table,
  columns : Array[@ast.ColumnRef],
) -> SelectBuilder {
  SelectBuilder::{
    table,
    columns,
    where_clause: None,
    joins: [],
    order_by: [],
    limit: None,
    offset: None,
    distinct: false,
    distinct_on: [],
  }
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
/// Add an INNER JOIN clause.
pub fn SelectBuilder::join(
  self : SelectBuilder,
  other : Table,
  on : @ast.Expr,
) -> SelectBuilder {
  self.joins.push(
    @ast.JoinClause::{ table: other.qualified_name(), on },
  )
  self
}

///|
/// Add an ORDER BY clause.  Chain multiple times for multiple columns.
pub fn SelectBuilder::order_by(
  self : SelectBuilder,
  clause : @ast.OrderByClause,
) -> SelectBuilder {
  self.order_by.push(clause)
  self
}

///|
/// Attach a LIMIT clause.
pub fn SelectBuilder::limit(
  self : SelectBuilder,
  n : Int,
) -> SelectBuilder {
  SelectBuilder::{ ..self, limit: Some(n) }
}

///|
/// Attach an OFFSET clause.
pub fn SelectBuilder::offset(
  self : SelectBuilder,
  n : Int,
) -> SelectBuilder {
  SelectBuilder::{ ..self, offset: Some(n) }
}

///|
/// Add SELECT DISTINCT.
pub fn SelectBuilder::distinct(self : SelectBuilder) -> SelectBuilder {
  SelectBuilder::{ ..self, distinct: true }
}

///|
/// Add SELECT DISTINCT ON (columns).
pub fn SelectBuilder::distinct_on(
  self : SelectBuilder,
  cols : Array[&AnyColumn],
) -> SelectBuilder {
  SelectBuilder::{ ..self, distinct_on: cols.map(c=>c.to_ref()) }
}

///|
/// Produce the AST node without rendering.
pub fn SelectBuilder::build(self : SelectBuilder) -> @ast.SelectStmt {
  @ast.SelectStmt::{
    table: self.table.qualified_name(),
    columns: self.columns,
    where_clause: self.where_clause,
    joins: self.joins,
    order_by: self.order_by,
    limit: self.limit,
    offset: self.offset,
    distinct: self.distinct,
    distinct_on: self.distinct_on,
  }
}

///|
/// Render the query to a parameterised SQL string + args array.
pub fn SelectBuilder::to_sql(self : SelectBuilder) -> (String, Array[@ast.Value]) {
  @tosql.select_stmt_to_sql(self.build())
}
