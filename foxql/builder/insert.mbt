// InsertBuilder — fluent builder for INSERT statements.

///|
/// A fluent builder for an INSERT query.  Terminal: `.to_sql()`.
pub(all) struct InsertBuilder {
  table : Table
  columns : Array[@ast.ColumnRef]
  values : Array[Array[@ast.Value]]
  conflict_cols : Array[@ast.ColumnRef]
  conflict_action : Int  // 0=none, 1=do_nothing, 2=do_update
  conflict_sets : Array[@ast.SetClause]
  returning : Array[@ast.ColumnRef]?
} derive(Debug, Eq)

///|
/// Create a new InsertBuilder.  Internal — users call `table.insert(..)` instead.
pub fn InsertBuilder::new(
  table : Table,
  columns : Array[&AnyColumn],
) -> InsertBuilder {
  InsertBuilder::{
    table,
    columns: columns.map(c=>c.to_ref()),
    values: [],
    conflict_cols: [],
    conflict_action: 0,
    conflict_sets: [],
    returning: None,
  }
}

///|
/// Add a single-row VALUES clause.
pub fn InsertBuilder::values(
  self : InsertBuilder,
  vals : Array[&@ast.ToValue],
) -> InsertBuilder {
  InsertBuilder::{ ..self, values: [vals.map(fn(v) { v.to_value() })] }
}

///|
/// Add a multi-row VALUES clause.
pub fn InsertBuilder::rows(
  self : InsertBuilder,
  rows : Array[Array[&@ast.ToValue]],
) -> InsertBuilder {
  InsertBuilder::{ ..self, values: rows.map(fn(row) { row.map(fn(v) { v.to_value() }) }) }
}

///|
/// Set the ON CONFLICT target column(s).
pub fn InsertBuilder::on_conflict(
  self : InsertBuilder,
  cols : Array[&AnyColumn],
) -> InsertBuilder {
  InsertBuilder::{ ..self, conflict_cols: cols.map(c=>c.to_ref()) }
}

///|
/// ON CONFLICT DO NOTHING.
pub fn InsertBuilder::do_nothing(self : InsertBuilder) -> InsertBuilder {
  InsertBuilder::{ ..self, conflict_action: 1 }
}

///|
/// ON CONFLICT DO UPDATE SET column = value.
pub fn InsertBuilder::do_update(
  self : InsertBuilder,
  column : &AnyColumn,
  value : &@ast.ToValue,
) -> InsertBuilder {
  self.conflict_sets.push(@ast.SetClause::{ column: column.to_ref(), value: value.to_value() })
  InsertBuilder::{ ..self, conflict_action: 2, conflict_sets: self.conflict_sets }
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
  let on_conflict = if self.conflict_action == 0 {
    None
  } else if self.conflict_action == 1 {
    Some(@ast.OnConflict::DoNothing(render_conflict_target(self.conflict_cols)))
  } else {
    Some(@ast.OnConflict::DoUpdate(render_conflict_target(self.conflict_cols), self.conflict_sets))
  }
  let node = @ast.InsertStmt::{
    table: self.table.qualified_name(),
    columns: self.columns,
    values: self.values,
    on_conflict,
    returning: self.returning,
  }
  @tosql.insert_stmt_to_sql(node)
}

fn render_conflict_target(cols : Array[@ast.ColumnRef]) -> String {
  if cols.length() == 0 {
    ""
  } else {
    " (" + cols.map(fn(c) { c.name }).join(", ") + ")"
  }
}
