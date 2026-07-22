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

struct OrdersTable {
  table : @builder.Table
  id : @builder.Column[Int]
  user_id : @builder.Column[Int]
  amount : @builder.Column[Int]
}

let orders : OrdersTable = {
  table: @builder.Table::new("orders"),
  id: @builder.Column::new("id", "orders", @ast.SqlType::Integer),
  user_id: @builder.Column::new("user_id", "orders", @ast.SqlType::Integer),
  amount: @builder.Column::new("amount", "orders", @ast.SqlType::Integer),
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

// ---------------------------------------------------------------------------
// Mutation: INSERT
// ---------------------------------------------------------------------------

///|
test "insert single row" {
  let (sql, args) = users.table
    .insert([users.name, users.age])
    .values(["Alice", 30])
    .to_sql()

  inspect(
    sql,
    content="INSERT INTO users (name, age) VALUES ($1, $2)",
  )
  assert_true(args is [n, a] && n is String("Alice") && a is Int(30))
}

///|
test "insert multi row" {
  let (sql, args) = users.table
    .insert([users.name, users.age])
    .rows([
      ["Alice", 30],
      ["Bob", 25],
    ])
    .to_sql()

  inspect(
    sql,
    content="INSERT INTO users (name, age) VALUES ($1, $2), ($3, $4)",
  )
  assert_true(
    args is [a, b, c, d] &&
    a is String("Alice") &&
    b is Int(30) &&
    c is String("Bob") &&
    d is Int(25),
  )
}

///|
test "insert with returning" {
  let (sql, args) = users.table
    .insert([users.name, users.age])
    .values(["Charlie", 42])
    .returning([users.id])
    .to_sql()

  inspect(
    sql,
    content="INSERT INTO users (name, age) VALUES ($1, $2) RETURNING users.id",
  )
  assert_true(args is [n, a] && n is String("Charlie") && a is Int(42))
}

// ---------------------------------------------------------------------------
// Mutation: UPDATE
// ---------------------------------------------------------------------------

///|
test "update set with where" {
  let (sql, args) = users.table
    .update()
    .set(users.name, "Dave")
    .set(users.age, 99)
    .where_(users.id.eq(1))
    .to_sql()

  inspect(
    sql,
    content="UPDATE users SET users.name = $1, users.age = $2 WHERE users.id = $3",
  )
  assert_true(
    args is [n, a, i] &&
    n is String("Dave") &&
    a is Int(99) &&
    i is Int(1),
  )
}

///|
test "update with returning" {
  let (sql, args) = users.table
    .update()
    .set(users.age, 55)
    .where_(users.id.eq(1))
    .returning([users.name, users.age])
    .to_sql()

  inspect(
    sql,
    content="UPDATE users SET users.age = $1 WHERE users.id = $2 RETURNING users.name, users.age",
  )
  assert_true(args is [a, i] && a is Int(55) && i is Int(1))
}

// ---------------------------------------------------------------------------
// Mutation: DELETE
// ---------------------------------------------------------------------------

///|
test "delete with where" {
  let (sql, args) = users.table
    .delete()
    .where_(users.id.eq(1))
    .to_sql()

  inspect(sql, content="DELETE FROM users WHERE users.id = $1")
  assert_true(args is [i] && i is Int(1))
}

///|
test "delete with returning" {
  let (sql, args) = users.table
    .delete()
    .where_(users.age.lt(18))
    .returning([users.id, users.name])
    .to_sql()

  inspect(
    sql,
    content="DELETE FROM users WHERE users.age < $1 RETURNING users.id, users.name",
  )
  assert_true(args is [a] && a is Int(18))
}

// ---------------------------------------------------------------------------
// ORDER BY, LIMIT, OFFSET, DISTINCT
// ---------------------------------------------------------------------------

///|
test "select order by asc" {
  let (sql, args) = users.table
    .select()
    .order_by(users.name.asc())
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users ORDER BY users.name ASC",
  )
  assert_true(args is [])
}

///|
test "select order by desc" {
  let (sql, args) = users.table
    .select()
    .order_by(users.age.desc())
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users ORDER BY users.age DESC",
  )
  assert_true(args is [])
}

///|
test "select order by multiple columns" {
  let (sql, args) = users.table
    .select(columns=[users.name, users.age])
    .order_by(users.age.desc())
    .order_by(users.name.asc())
    .to_sql()

  inspect(
    sql,
    content="SELECT users.name, users.age FROM users ORDER BY users.age DESC, users.name ASC",
  )
  assert_true(args is [])
}

///|
test "select limit" {
  let (sql, args) = users.table
    .select()
    .limit(10)
    .to_sql()

  inspect(sql, content="SELECT * FROM users LIMIT $1")
  assert_true(args is [n] && n is Int(10))
}

///|
test "select limit offset" {
  let (sql, args) = users.table
    .select()
    .limit(10)
    .offset(20)
    .to_sql()

  inspect(
    sql,
    content="SELECT * FROM users LIMIT $1 OFFSET $2",
  )
  assert_true(args is [l, o] && l is Int(10) && o is Int(20))
}

///|
test "select distinct" {
  let (sql, args) = users.table
    .select(columns=[users.name])
    .distinct()
    .to_sql()

  inspect(
    sql,
    content="SELECT DISTINCT users.name FROM users",
  )
  assert_true(args is [])
}

///|
test "select distinct on" {
  let (sql, args) = users.table
    .select(columns=[users.name, users.age])
    .distinct_on([users.name])
    .to_sql()

  inspect(
    sql,
    content="SELECT DISTINCT ON (users.name) users.name, users.age FROM users",
  )
  assert_true(args is [])
}

///|
test "select all modifiers combined" {
  let (sql, args) = users.table
    .select(columns=[users.name, users.age])
    .distinct()
    .where_(users.age.gte(18))
    .order_by(users.name.asc())
    .limit(5)
    .offset(10)
    .to_sql()

  inspect(
    sql,
    content="SELECT DISTINCT users.name, users.age FROM users WHERE users.age >= $1 ORDER BY users.name ASC LIMIT $2 OFFSET $3",
  )
  assert_true(args is [a, l, o] && a is Int(18) && l is Int(5) && o is Int(10))
}

// ---------------------------------------------------------------------------
// JOIN
// ---------------------------------------------------------------------------

///|
test "select with inner join" {
  let (sql, args) = users.table
    .select(columns=[users.name, orders.amount])
    .join(orders.table, users.id.eq_col(orders.user_id))
    .to_sql()

  inspect(
    sql,
    content="SELECT users.name, orders.amount FROM users INNER JOIN orders ON users.id = orders.user_id",
  )
  assert_true(args is [])
}

///|
test "select with join and where" {
  let (sql, args) = users.table
    .select(columns=[users.name, orders.amount])
    .join(orders.table, users.id.eq_col(orders.user_id))
    .where_(orders.amount.gt(100))
    .to_sql()

  inspect(
    sql,
    content="SELECT users.name, orders.amount FROM users INNER JOIN orders ON users.id = orders.user_id WHERE orders.amount > $1",
  )
  assert_true(args is [a] && a is Int(100))
}

///|
test "select with join where order by" {
  let (sql, args) = users.table
    .select(columns=[users.name, orders.amount])
    .join(orders.table, users.id.eq_col(orders.user_id))
    .where_(orders.amount.gte(50))
    .order_by(orders.amount.desc())
    .limit(10)
    .to_sql()

  inspect(
    sql,
    content="SELECT users.name, orders.amount FROM users INNER JOIN orders ON users.id = orders.user_id WHERE orders.amount >= $1 ORDER BY orders.amount DESC LIMIT $2",
  )
  assert_true(args is [a, l] && a is Int(50) && l is Int(10))
}

// ---------------------------------------------------------------------------
// Type-state verification (compile-time — verified by moon check)
//
// These are NOT runtime tests.  The following calls should produce a
// compile error because .to_sql() is not available without .where_():
//
//   users.table.update().set(...).to_sql()     // error: UpdateBuilder has no to_sql
//   users.table.delete().to_sql()               // error: DeleteBuilder has no to_sql
// ---------------------------------------------------------------------------
