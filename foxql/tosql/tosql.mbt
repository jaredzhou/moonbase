// ToSql trait — render an AST node to (sql_string, args_array).
//
// Also exposes plain functions (select_stmt_to_sql, expr_to_sql) that callers
// in other packages can use directly, avoiding cross-package trait dispatch.

///|
/// Trait for AST nodes that can be rendered to parameterised SQL.
pub trait ToSql {
  fn to_sql(Self) -> (String, Array[@ast.Value])
}

///|
impl ToSql for @ast.SelectStmt with fn to_sql(
  self : @ast.SelectStmt,
) -> (String, Array[@ast.Value]) {
  select_stmt_to_sql(self)
}

///|
impl ToSql for @ast.Expr with fn to_sql(
  self : @ast.Expr,
) -> (String, Array[@ast.Value]) {
  expr_to_sql(self)
}

// ---------------------------------------------------------------------------
// Public plain-function API
// ---------------------------------------------------------------------------

///|
/// Render a SelectStmt to parameterised SQL.
pub fn select_stmt_to_sql(stmt : @ast.SelectStmt) -> (String, Array[@ast.Value]) {
  let columns_part = if stmt.columns.length() == 0 {
    "*"
  } else {
    render_columns(stmt.columns)
  }
  let (where_part, args) = render_where(stmt.where_clause)
  (
    "SELECT " + columns_part + " FROM " + stmt.table + where_part,
    args,
  )
}

///|
/// Render an Expr to parameterised SQL.
pub fn expr_to_sql(expr : @ast.Expr) -> (String, Array[@ast.Value]) {
  match expr {
    @ast.Expr::Compare(col, op, val) => {
      let sql = col.table + "." + col.name + " " + op.to_sql_op() + " $1"
      (sql, [val])
    }
    @ast.Expr::And(conditions) => {
      render_composed(" AND ", conditions)
    }
    @ast.Expr::Or(conditions) => {
      render_composed(" OR ", conditions)
    }
    @ast.Expr::Not(inner) => {
      let (sub_sql, sub_args) = expr_to_sql(inner)
      ("NOT (" + sub_sql + ")", sub_args)
    }
    @ast.Expr::InList(col, vals) => {
      let (placeholders, args) = render_value_list(vals)
      (col.table + "." + col.name + " IN (" + placeholders + ")", args)
    }
    @ast.Expr::InSelect(col, sub) => {
      let (sub_sql, sub_args) = select_stmt_to_sql(sub)
      (col.table + "." + col.name + " IN (" + sub_sql + ")", sub_args)
    }
    @ast.Expr::Between(col, lo, hi) => {
      (col.table + "." + col.name + " BETWEEN $1 AND $2", [lo, hi])
    }
    @ast.Expr::IsNull(col) => {
      (col.table + "." + col.name + " IS NULL", [])
    }
    @ast.Expr::IsNotNull(col) => {
      (col.table + "." + col.name + " IS NOT NULL", [])
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

fn render_columns(cols : Array[@ast.ColumnRef]) -> String {
  render_columns_rec(cols, 0, "")
}

fn render_columns_rec(
  cols : Array[@ast.ColumnRef],
  i : Int,
  acc : String,
) -> String {
  if i >= cols.length() {
    acc
  } else {
    let prefix = if i == 0 { "" } else { ", " }
    let next = cols[i].table + "." + cols[i].name
    render_columns_rec(cols, i + 1, acc + prefix + next)
  }
}

fn render_where(
  cond : @ast.Expr?,
) -> (String, Array[@ast.Value]) {
  match cond {
    Some(c) => {
      let (sql, args) = expr_to_sql(c)
      (" WHERE " + sql, args)
    }
    None => ("", [])
  }
}

fn render_composed(
  sep : String,
  conditions : Array[@ast.Expr],
) -> (String, Array[@ast.Value]) {
  render_composed_rec(conditions, 0, sep, "", [])
}

fn render_composed_rec(
  conditions : Array[@ast.Expr],
  i : Int,
  sep : String,
  acc_sql : String,
  acc_args : Array[@ast.Value],
) -> (String, Array[@ast.Value]) {
  if i >= conditions.length() {
    ("(" + acc_sql + ")", acc_args)
  } else {
    let (sub_sql, sub_args) = expr_to_sql(conditions[i])
    let renumbered = renumber_placeholders(sub_sql, acc_args.length())
    let new_sql = if i == 0 {
      acc_sql + renumbered
    } else {
      acc_sql + sep + renumbered
    }
    let new_args = acc_args
    for a in sub_args {
      new_args.push(a)
    }
    render_composed_rec(conditions, i + 1, sep, new_sql, new_args)
  }
}

fn render_value_list(vals : Array[@ast.Value]) -> (String, Array[@ast.Value]) {
  render_value_list_rec(vals, 0, "", [])
}

fn render_value_list_rec(
  vals : Array[@ast.Value],
  i : Int,
  acc : String,
  acc_args : Array[@ast.Value],
) -> (String, Array[@ast.Value]) {
  if i >= vals.length() {
    (acc, acc_args)
  } else {
    let prefix = if i == 0 { "" } else { ", " }
    let n = acc_args.length() + 1
    acc_args.push(vals[i])
    render_value_list_rec(
      vals,
      i + 1,
      acc + prefix + "$" + n.to_string(),
      acc_args,
    )
  }
}

fn renumber_placeholders(sql : String, offset : Int) -> String {
  if offset == 0 {
    return sql
  }
  renumber_placeholders_rec(sql, offset, 0, "")
}

fn renumber_placeholders_rec(
  sql : String,
  offset : Int,
  i : Int,
  acc : String,
) -> String {
  if i >= sql.length() {
    return acc
  }
  let ch = sql[i:i + 1]
  if ch == "$" && i + 1 < sql.length() {
    let (num, next_i) = parse_number(sql, i + 1)
    if num > 0 {
      renumber_placeholders_rec(
        sql,
        offset,
        next_i,
        acc + "$" + (num + offset).to_string(),
      )
    } else {
      renumber_placeholders_rec(sql, offset, i + 1, acc + ch.to_owned())
    }
  } else {
    renumber_placeholders_rec(sql, offset, i + 1, acc + ch.to_owned())
  }
}

fn parse_number(sql : String, i : Int) -> (Int, Int) {
  parse_number_rec(sql, i, 0)
}

fn parse_number_rec(sql : String, i : Int, acc : Int) -> (Int, Int) {
  if i >= sql.length() {
    (acc, i)
  } else {
    let d = digit_value(sql[i:i + 1].to_owned())
    if d < 0 {
      (acc, i)
    } else {
      parse_number_rec(sql, i + 1, acc * 10 + d)
    }
  }
}

fn digit_value(s : String) -> Int {
  if s == "0" { 0 } else if s == "1" { 1 } else if s == "2" { 2 } else
  if s == "3" { 3 } else if s == "4" { 4 } else if s == "5" { 5 } else
  if s == "6" { 6 } else if s == "7" { 7 } else if s == "8" { 8 } else
  if s == "9" { 9 } else { -1 }
}
