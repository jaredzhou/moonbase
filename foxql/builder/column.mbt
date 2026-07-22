// Column[T] — a statically-typed column reference.
//
// The type parameter T controls which operators are available at compile time:
//
//   Column[Int] / Column[Double] → eq, neq, gt, gte, lt, lte, between, in_, is_null
//   Column[String]               → eq, neq, like, not_like, in_, is_null
//   Column[Bool]                 → eq, neq, is_null

// ---------------------------------------------------------------------------
// Operator marker traits
// ---------------------------------------------------------------------------

///| Trait for types that support comparison operators (gt, gte, lt, lte, between).
pub trait Comparable {
  to_sql_type(Self) -> @ast.SqlType
}

///| Trait for types that support string operators (like, not_like).
pub trait StringMatchable {
  to_sql_type(Self) -> @ast.SqlType
}

///|
pub impl Comparable for Int with fn to_sql_type(self : Int) -> @ast.SqlType {
  @ast.SqlType::Integer
}
///|
pub impl Comparable for Double with fn to_sql_type(self : Double) -> @ast.SqlType {
  @ast.SqlType::DoublePrecision
}
///|
pub impl StringMatchable for String with fn to_sql_type(self : String) -> @ast.SqlType {
  @ast.SqlType::Text
}

// ---------------------------------------------------------------------------

///|
/// A typed column reference in a specific table.
pub(all) struct Column[T] {
  name : String
  table : String
  sql_type : @ast.SqlType
} derive(Debug, Eq)

///|
/// Trait that erases T — exposes column identity for heterogeneous column lists.
pub trait AnyColumn {
  fn name(Self) -> String
  fn table_name(Self) -> String
  fn sql_type(Self) -> @ast.SqlType
}

pub fn &AnyColumn::to_ref(self : &AnyColumn) -> @ast.ColumnRef {
  @ast.ColumnRef::{ name: self.name(), table: self.table_name() }
}

pub fn &AnyColumn::asc(self : &AnyColumn) -> @ast.OrderByClause {
  @ast.OrderByClause::{ column: self.to_ref(), direction: @ast.OrderDirection::Asc }
}

pub fn &AnyColumn::desc(self : &AnyColumn) -> @ast.OrderByClause {
  @ast.OrderByClause::{ column: self.to_ref(), direction: @ast.OrderDirection::Desc }
}
///|
pub impl[T] AnyColumn for Column[T] with fn name(self : Column[T]) -> String {
  self.name
}

///|
pub impl[T] AnyColumn for Column[T] with fn table_name(self : Column[T]) -> String {
  self.table
}

///|
pub impl[T] AnyColumn for Column[T] with fn sql_type(self : Column[T]) -> @ast.SqlType {
  self.sql_type
}


///|
/// Create a new column reference.
pub fn[T] Column::new(
  name : String,
  table : String,
  sql_type : @ast.SqlType,
) -> Column[T] {
  Column::{ name, table, sql_type }
}

///|
/// Produce a type-erased ColumnRef.
pub fn[T] Column::to_ref(self : Column[T]) -> @ast.ColumnRef {
  @ast.ColumnRef::{ name: self.name, table: self.table }
}

///|
/// Sort ascending.
pub fn[T] Column::asc(self : Column[T]) -> @ast.OrderByClause {
  @ast.OrderByClause::{ column: self.to_ref(), direction: @ast.OrderDirection::Asc }
}

///|
/// Sort descending.
pub fn[T] Column::desc(self : Column[T]) -> @ast.OrderByClause {
  @ast.OrderByClause::{ column: self.to_ref(), direction: @ast.OrderDirection::Desc }
}

// ---------------------------------------------------------------------------
// Equality operators
// ---------------------------------------------------------------------------

///|
pub fn[T : @ast.ToValue] Column::eq(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Eq, value.to_value())
}

///|
pub fn[T : @ast.ToValue] Column::neq(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Neq, value.to_value())
}

///|
/// Compare two columns for equality (for JOIN ON).
pub fn[T] Column::eq_col(
  self : Column[T],
  other : Column[T],
) -> @ast.Expr {
  @ast.Expr::CompareCols(self.to_ref(), @ast.Operator::Eq, other.to_ref())
}

// ---------------------------------------------------------------------------
// Null operators
// ---------------------------------------------------------------------------

///|
pub fn[T] Column::is_null(self : Column[T]) -> @ast.Expr {
  @ast.Expr::IsNull(self.to_ref())
}

///|
pub fn[T] Column::is_not_null(self : Column[T]) -> @ast.Expr {
  @ast.Expr::IsNotNull(self.to_ref())
}

// ---------------------------------------------------------------------------
// Comparison operators
// ---------------------------------------------------------------------------

///|
pub fn[T : Comparable + @ast.ToValue] Column::gt(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Gt, value.to_value())
}

///|
pub fn[T : Comparable + @ast.ToValue] Column::gte(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Gte, value.to_value())
}

///|
pub fn[T : Comparable + @ast.ToValue] Column::lt(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Lt, value.to_value())
}

///|
pub fn[T : Comparable + @ast.ToValue] Column::lte(
  self : Column[T],
  value : T,
) -> @ast.Expr {
  @ast.Expr::Compare(self.to_ref(), @ast.Operator::Lte, value.to_value())
}

// ---------------------------------------------------------------------------
// String operators
// ---------------------------------------------------------------------------

///|
pub fn[T : StringMatchable] Column::like(
  self : Column[T],
  pattern : String,
) -> @ast.Expr {
  @ast.Expr::Compare(
    self.to_ref(),
    @ast.Operator::Like,
    @ast.Value::String(pattern),
  )
}

///|
pub fn[T : StringMatchable] Column::not_like(
  self : Column[T],
  pattern : String,
) -> @ast.Expr {
  @ast.Expr::Compare(
    self.to_ref(),
    @ast.Operator::NotLike,
    @ast.Value::String(pattern),
  )
}

// ---------------------------------------------------------------------------
// Range / set operators
// ---------------------------------------------------------------------------

///|
pub fn[T : @ast.ToValue] Column::in_(
  self : Column[T],
  vals : Array[T],
) -> @ast.Expr {
  @ast.Expr::InList(self.to_ref(), vals.map(fn(v) { v.to_value() }))
}

///|
pub fn[T] Column::in_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::InSelect(self.to_ref(), subquery)
}

///|
/// Compare column with a scalar subquery.
pub fn[T] Column::eq_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Eq, subquery)
}

///|
pub fn[T] Column::neq_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Neq, subquery)
}

///|
pub fn[T] Column::gt_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Gt, subquery)
}

///|
pub fn[T] Column::gte_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Gte, subquery)
}

///|
pub fn[T] Column::lt_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Lt, subquery)
}

///|
pub fn[T] Column::lte_select(
  self : Column[T],
  subquery : @ast.SelectStmt,
) -> @ast.Expr {
  @ast.Expr::CompareSelect(self.to_ref(), @ast.Operator::Lte, subquery)
}

///|
pub fn[T : Comparable + @ast.ToValue] Column::between(
  self : Column[T],
  lo : T,
  hi : T,
) -> @ast.Expr {
  @ast.Expr::Between(self.to_ref(), lo.to_value(), hi.to_value())
}

// ---------------------------------------------------------------------------
// Aggregation functions
// ---------------------------------------------------------------------------

///|
pub fn count[T](col : Column[T]) -> @ast.Aggregation {
  @ast.Aggregation::Count(Some(col.to_ref()))
}

///|
pub fn sum[T](col : Column[T]) -> @ast.Aggregation {
  @ast.Aggregation::Sum(col.to_ref())
}

///|
pub fn avg[T](col : Column[T]) -> @ast.Aggregation {
  @ast.Aggregation::Avg(col.to_ref())
}

///|
pub fn min[T](col : Column[T]) -> @ast.Aggregation {
  @ast.Aggregation::Min(col.to_ref())
}

///|
pub fn max[T](col : Column[T]) -> @ast.Aggregation {
  @ast.Aggregation::Max(col.to_ref())
}

///|
/// COUNT(*) — count all rows.
pub fn count_star() -> @ast.Aggregation {
  @ast.Aggregation::Count(None)
}

