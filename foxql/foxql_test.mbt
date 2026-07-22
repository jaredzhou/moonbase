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

// ---------------------------------------------------------------------------
// Comparison operators: neq, gt, gte, lt, lte
// ---------------------------------------------------------------------------

///|
test "where neq" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.neq(18))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age <> $1")
  assert_true(args is [a] && a is Int(18))
}

///|
test "where gt" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.gt(30))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age > $1")
  assert_true(args is [a] && a is Int(30))
}

///|
test "where gte" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.gte(18))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age >= $1")
  assert_true(args is [a] && a is Int(18))
}

///|
test "where lt" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.lt(65))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age < $1")
  assert_true(args is [a] && a is Int(65))
}

///|
test "where lte" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.lte(64))
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.age <= $1")
  assert_true(args is [a] && a is Int(64))
}

// ---------------------------------------------------------------------------
// String operators: like, not_like
// ---------------------------------------------------------------------------

///|
test "where like" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.like("Al%"))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.name LIKE $1",
  )
  assert_true(args is [s] && s is String("Al%"))
}

///|
test "where not_like" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.not_like("Spam%"))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.name NOT LIKE $1",
  )
  assert_true(args is [s] && s is String("Spam%"))
}

// ---------------------------------------------------------------------------
// Null operators: is_null, is_not_null
// ---------------------------------------------------------------------------

///|
test "where is_null" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.is_null())
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.name IS NULL")
  assert_true(args is [])
}

///|
test "where is_not_null" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.is_not_null())
    .to_sql()

  inspect(sql, content="SELECT * FROM users WHERE users.name IS NOT NULL")
  assert_true(args is [])
}

// ---------------------------------------------------------------------------
// Range / set operators: between, in_
// ---------------------------------------------------------------------------

///|
test "where between" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.between(18, 65))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.age BETWEEN $1 AND $2",
  )
  assert_true(args is [lo, hi] && lo is Int(18) && hi is Int(65))
}

///|
test "where in_ list" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.in_([18, 21, 30]))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.age IN ($1, $2, $3)",
  )
  assert_true(args is [a, b, c] && a is Int(18) && b is Int(21) && c is Int(30))
}

///|
test "where in_select subquery" {
  let orders = @builder.Table::new("orders")
  let user_id = @builder.Column::new("user_id", "orders", @ast.SqlType::Integer)

  let sub = orders.select(columns=[user_id]).where_(user_id.gt(0)).build()

  let (sql, args) = users.table
    .select()
    .where_(users.id.in_select(sub))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE users.id IN (SELECT orders.user_id FROM orders WHERE orders.user_id > $1)",
  )
  assert_true(args is [a] && a is Int(0))
}

// ---------------------------------------------------------------------------
// Condition composition: and_, or_, not_
// ---------------------------------------------------------------------------

///|
test "where with and_ composition" {
  let (sql, args) = users.table
    .select()
    .where_(users.age.gte(18).and_(users.age.lte(65)))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.age >= $1 AND users.age <= $2)",
  )
  assert_true(args is [lo, hi] && lo is Int(18) && hi is Int(65))
}

///|
test "where with or_ composition" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.eq("Alice").or_(users.name.eq("Bob")))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.name = $1 OR users.name = $2)",
  )
  assert_true(args is [a, b] && a is String("Alice") && b is String("Bob"))
}

///|
test "where with not_ composition" {
  let (sql, args) = users.table
    .select()
    .where_(@ast.not_(users.age.eq(0)))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE NOT (users.age = $1)",
  )
  assert_true(args is [a] && a is Int(0))
}

///|
test "where chained and_ flattens" {
  let (sql, args) = users.table
    .select()
    .where_(
      users.age.gte(18).and_(users.age.lte(65)).and_(users.name.is_not_null()),
    )
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.age >= $1 AND users.age <= $2 AND users.name IS NOT NULL)",
  )
  assert_true(args is [lo, hi] && lo is Int(18) && hi is Int(65))
}

///|
test "where nested and/or" {
  let (sql, args) = users.table
    .select()
    .where_(
      users.age.lt(18)
        .or_(users.age.gt(65))
        .and_(users.name.is_not_null()),
    )
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE ((users.age < $1 OR users.age > $2) AND users.name IS NOT NULL)",
  )
  assert_true(args is [lt, gt] && lt is Int(18) && gt is Int(65))
}

///|
test "where complex nested not with and" {
  let (sql, args) = users.table
    .select()
    .where_(@ast.not_(users.age.in_([1, 2, 3])).and_(users.name.like("A%")))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (NOT (users.age IN ($1, $2, $3)) AND users.name LIKE $4)",
  )
  assert_true(
    args is [a, b, c, d] &&
    a is Int(1) &&
    b is Int(2) &&
    c is Int(3) &&
    d is String("A%"),
  )
}

///|
test "where multiple or_ flattens" {
  let (sql, args) = users.table
    .select()
    .where_(users.name.eq("A").or_(users.name.eq("B")).or_(users.name.eq("C")))
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users WHERE (users.name = $1 OR users.name = $2 OR users.name = $3)",
  )
  assert_true(
    args is [a, b, c] &&
    a is String("A") &&
    b is String("B") &&
    c is String("C"),
  )
}
