// Blackbox tests for FoxQL — SELECT with WHERE eq.
//
// Standard pattern: define a table proxy struct per database table, then use
// its fields to build queries.

/// Table proxy — one struct + one global per database table.
struct UserTable {
  table : @builder.Table
  id : @builder.Column[Int]
  name : @builder.Column[String]
  age : @builder.Column[Int]
}

let users : UserTable = {
  table: @builder.Table::new("users"),
  id: @builder.Column::new("id", "users", @ast.SqlType::Integer),
  name: @builder.Column::new("name", "users", @ast.SqlType::Text),
  age: @builder.Column::new("age", "users", @ast.SqlType::Integer),
}

///|
test "select star with where eq" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.eq(18))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age = $1")
  assert_true(args is [a] && a is Int(18))
}

///|
test "select columns with where eq" {
  // uses global `users`

  let (sql, args) = users.table
    .select(columns=[users.age, users.name])
    .where_(users.age.eq(18))
    .to_sql()

  inspect(
    sql,
    content="SELECT users.age, users.name FROM users WHERE users.age = $1",
  )
  assert_true(args is [a] && a is Int(18))
}

///|
test "select star without where" {
  let items = @builder.Table::new("items")

  let (sql, args) = items.select().to_sql()

  inspect(sql, content="SELECT * FROM items")
  assert_true(args is [])
}

///|
test "select with string eq" {
  // uses global `users`

  let (sql, args) = users.table
    .select(columns=[users.name])
    .where_(users.name.eq("Alice"))
    .to_sql()

  inspect(sql, content="SELECT users.name FROM users WHERE users.name = $1")
  assert_true(args is [n] && n is String("Alice"))
}

///|
test "select with qualified schema table" {
  let table = @builder.Table::new("profiles", schema="public")
  let id = @builder.Column::new("id", "profiles", @ast.SqlType::Integer)

  let (sql, args) = table
    .select()
    .where_(id.eq(1))
    .to_sql()

  inspect(sql, content="SELECT * FROM public.profiles WHERE profiles.id = $1")
  assert_true(args is [i] && i is Int(1))
}
