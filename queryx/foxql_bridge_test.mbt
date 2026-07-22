// Blackbox tests for queryx → foxql bridge.

// ---------------------------------------------------------------------------
// Schema for SchemaTable tests
// ---------------------------------------------------------------------------

///|
let test_schema : @foxql.Schema = @foxql.Schema::load([
  { table_name: "users", column_name: "id", sql_type: @ast.SqlType::Integer },
  { table_name: "users", column_name: "name", sql_type: @ast.SqlType::Text },
  { table_name: "users", column_name: "age", sql_type: @ast.SqlType::Integer },
  {
    table_name: "orders",
    column_name: "amount",
    sql_type: @ast.SqlType::Integer,
  },
])

///|
let users_schema : @foxql.SchemaTable = test_schema.table("users")

// ---------------------------------------------------------------------------

///|
struct User {
  table : @builder.Table
  id : @builder.Column[Int]
  name : @builder.Column[String]
  age : @builder.Column[Int]
}

///|
let user : User = {
  table: @builder.Table::new("users"),
  id: @builder.Column::new("id", "users", @ast.SqlType::Integer),
  name: @builder.Column::new("name", "users", @ast.SqlType::Text),
  age: @builder.Column::new("age", "users", @ast.SqlType::Integer),
}

///|
impl @foxql.FieldResolver for User with fn resolve_column(
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

///|
impl @foxql.FieldResolver for User with fn table_name(_self : User) -> String {
  "users"
}

// ---------------------------------------------------------------------------
// SchemaTable → to_select
// ---------------------------------------------------------------------------

///|
test "bridge: schema table to_select" {
  let input : Json = {
    "filter": { "name": { "contains": "tom" }, "age": { "gt": 18.0 } },
    "order_by": [{ "age": "desc" }],
    "page": { "after": "", "size": 10.0 },
  }
  let query : Query = @json.from_json(input)
  let builder = to_select(query, users_schema)
  let (sql, args) = builder.to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.name LIKE $1 AND users.age > $2) ORDER BY users.age DESC LIMIT $3",
  )
  assert_true(
    args is [s, a, l] && s is String("%tom%") && a is Int(18) && l is Int(10),
  )
}

///|
test "bridge: schema table insert" {
  let (sql, args) = users_schema
    .insert([users_schema.col("name"), users_schema.col("age")])
    .values(["Alice", 30])
    .to_sql()

  inspect(sql, content="INSERT INTO users (name, age) VALUES ($1, $2)")
  assert_true(args is [n, a] && n is String("Alice") && a is Int(30))
}

///|
test "bridge: schema table update" {
  let (sql, args) = users_schema
    .update()
    .set(users_schema.col("name"), "Bob")
    .where_(users_schema.col("id").eq(1))
    .to_sql()

  inspect(sql, content="UPDATE users SET users.name = $1 WHERE users.id = $2")
  assert_true(args is [n, i] && n is String("Bob") && i is Int(1))
}

///|
test "bridge: schema table delete" {
  let (sql, args) = users_schema
    .delete()
    .where_(users_schema.col("id").eq(1))
    .returning([users_schema.col("id")])
    .to_sql()

  inspect(
    sql,
    content="DELETE FROM users WHERE users.id = $1 RETURNING users.id",
  )
  assert_true(args is [i] && i is Int(1))
}

///|
test "bridge: schema table unknown field raises" {
  let query : Query = @json.from_json({ "filter": { "nope": 1.0 } })
  try {
    let _builder = to_select(query, users_schema)
    abort("expected error")
  } catch {
    _ => ()
  }
}

// ---------------------------------------------------------------------------
// Expr → foxql Expr → SQL
// ---------------------------------------------------------------------------

///|
test "bridge: compare eq" {
  let expr = Expr::Compare("age", CmpOp::Eq, Value::Int(18L))
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, [])
    .where_(foxql_expr)
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age = $1")
  assert_true(args is [a] && a is Int(18))
}

///|
test "bridge: between" {
  let expr = Expr::Between("age", Value::Int(18L), Value::Int(65L))
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, [])
    .where_(foxql_expr)
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age BETWEEN $1 AND $2")
  assert_true(args is [lo, hi] && lo is Int(18) && hi is Int(65))
}

///|
test "bridge: strmatch contains" {
  let expr = Expr::StrMatch("name", StrKind::Contains, "tom")
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, [])
    .where_(foxql_expr)
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.name LIKE $1")
  assert_true(args is [s] && s is String("%tom%"))
}

///|
test "bridge: and composition" {
  let expr = Expr::And([
    Expr::Compare("age", CmpOp::Gt, Value::Int(18L)),
    Expr::StrMatch("name", StrKind::StartsWith, "A"),
  ])
  let foxql_expr = to_foxql_expr(expr, user)
  let (sql, args) = @builder.SelectBuilder::new(user.table, [])
    .where_(foxql_expr)
    .to_sql()

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
  let builder = to_select(query, user)
  let (sql, args) = builder.to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.name LIKE $1 ORDER BY users.age DESC LIMIT $2",
  )
  assert_true(args is [s, l] && s is String("%tom%") && l is Int(10))
}
