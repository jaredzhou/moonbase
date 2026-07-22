// Blackbox tests for queryx → foxql bridge.

struct User {
  table : @builder.Table
  id : @builder.Column[Int]
  name : @builder.Column[String]
  age : @builder.Column[Int]
}

let user : User = {
  table: @builder.Table::new("users"),
  id: @builder.Column::new("id", "users", @ast.SqlType::Integer),
  name: @builder.Column::new("name", "users", @ast.SqlType::Text),
  age: @builder.Column::new("age", "users", @ast.SqlType::Integer),
}

impl FieldResolver for User with fn resolve_column(
  self : User,
  field : String,
) -> @ast.ColumnRef? {
  match field {
    "id" => Some(self.id.to_ref())
    "name" => Some(self.name.to_ref())
    "age" => Some(self.age.to_ref())
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Expr → foxql Expr → SQL
// ---------------------------------------------------------------------------

///|
test "bridge: compare eq" {
  let expr = Expr::Compare("age", CmpOp::Eq, Value::Int(18L))
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, []).where_(
    foxql_expr,
  ).to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age = $1")
  assert_true(args is [a] && a is Int(18))
}

///|
test "bridge: between" {
  let expr = Expr::Between("age", Value::Int(18L), Value::Int(65L))
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, []).where_(
    foxql_expr,
  ).to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.age BETWEEN $1 AND $2",
  )
  assert_true(args is [lo, hi] && lo is Int(18) && hi is Int(65))
}

///|
test "bridge: strmatch contains" {
  let expr = Expr::StrMatch("name", StrKind::Contains, "tom")
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, []).where_(
    foxql_expr,
  ).to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.name LIKE $1")
  assert_true(args is [s] && s is String("%tom%"))
}

///|
test "bridge: and composition" {
  let expr = Expr::And(
    [
      Expr::Compare("age", CmpOp::Gt, Value::Int(18L)),
      Expr::StrMatch("name", StrKind::StartsWith, "A"),
    ],
  )
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, []).where_(
    foxql_expr,
  ).to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.age > $1 AND users.name LIKE $2)",
  )
  assert_true(args is [a, s] && a is Int(18) && s is String("A%"))
}

///|
test "bridge: empty filter raises" {
  let expr = Expr::Empty
  try {
    let _ = to_foxql_expr(expr, user)
    abort("expected error")
  } catch {
    _ => ()
  }
}

///|
test "bridge: unknown field raises" {
  let expr = Expr::Compare("nope", CmpOp::Eq, Value::Null)
  try {
    let _ = to_foxql_expr(expr, user)
    abort("expected error")
  } catch {
    _ => ()
  }
}

///|
test "bridge: to_select with where and limit" {
  let input : Json = {
    "filter": { "name": { "contains": "tom" } },
    "order_by": [{ "age": "desc" }],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let result = to_select(query, user.table, user)

  let (sql, args) = result.to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.name LIKE $1 ORDER BY users.age DESC LIMIT $2",
  )
  assert_true(args is [s, l] && s is String("%tom%") && l is Int(10))
}
