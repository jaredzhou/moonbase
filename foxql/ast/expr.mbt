// AST statements (Stmt) and the WHERE-clause expression tree (Expr).

///|
/// A SELECT statement.
pub(all) struct SelectStmt {
  table : String
  columns : Array[ColumnRef]  // empty = SELECT *
  where_clause : Expr?
  joins : Array[JoinClause]
  order_by : Array[OrderByClause]
  limit : Int?
  offset : Int?
  distinct : Bool
  distinct_on : Array[ColumnRef]
} derive(Debug, Eq)

///|
/// A WHERE clause expression — a tree of comparisons joined by AND / OR / NOT.
pub(all) enum Expr {
  Compare(ColumnRef, Operator, Value)
  CompareCols(ColumnRef, Operator, ColumnRef)
  And(Array[Expr])
  Or(Array[Expr])
  Not(Expr)
  InList(ColumnRef, Array[Value])
  InSelect(ColumnRef, SelectStmt)
  Between(ColumnRef, Value, Value)
  IsNull(ColumnRef)
  IsNotNull(ColumnRef)
} derive(Debug, Eq)

///|
/// Combine two expressions with AND.  Flattens nested And for cleaner SQL.
pub fn Expr::and_(
  self : Expr,
  other : Expr,
) -> Expr {
  match self {
    Expr::And(arr) => {
      arr.push(other)
      Expr::And(arr)
    }
    _ => Expr::And([self, other])
  }
}

///|
/// Combine two expressions with OR.  Flattens nested Or for cleaner SQL.
pub fn Expr::or_(
  self : Expr,
  other : Expr,
) -> Expr {
  match self {
    Expr::Or(arr) => {
      arr.push(other)
      Expr::Or(arr)
    }
    _ => Expr::Or([self, other])
  }
}

///|
/// Wrap an expression with NOT.
pub fn not_(expr : Expr) -> Expr {
  Expr::Not(expr)
}

///|
/// An INSERT statement (placeholder — wired in a later ticket).
pub(all) struct InsertStmt {
  table : String
  columns : Array[ColumnRef]
  values : Array[Array[Value]]
  on_conflict : OnConflict?
  returning : Array[ColumnRef]?
} derive(Debug, Eq)

///|
pub(all) enum OnConflict {
  DoNothing(String)
  DoUpdate(String, Array[SetClause])
} derive(Debug, Eq)

///|
pub(all) struct SetClause {
  column : ColumnRef
  value : Value
} derive(Debug, Eq)

///|
/// An UPDATE statement.  where_clause is non-optional.
pub(all) struct UpdateStmt {
  table : String
  set_clauses : Array[SetClause]
  where_clause : Expr
  returning : Array[ColumnRef]?
} derive(Debug, Eq)

///|
/// A DELETE statement.  where_clause is non-optional.
pub(all) struct DeleteStmt {
  table : String
  where_clause : Expr
  returning : Array[ColumnRef]?
} derive(Debug, Eq)

///|
/// An INNER JOIN clause.
pub(all) struct JoinClause {
  table : String
  on : Expr
} derive(Debug, Eq)

///|
/// ORDER BY direction.
pub(all) enum OrderDirection {
  Asc
  Desc
} derive(Debug, Eq)

///|
pub(all) struct OrderByClause {
  column : ColumnRef
  direction : OrderDirection
} derive(Debug, Eq)

///|
/// An aggregation function call.
pub(all) enum Aggregation {
  Count(ColumnRef?)
  Sum(ColumnRef)
  Avg(ColumnRef)
  Min(ColumnRef)
  Max(ColumnRef)
} derive(Debug, Eq)
