// FoxQL — compile-time type-safe SQL builder for PostgreSQL.
//
// Convenience re-exports from sub-packages.  Import jaredzhou/foxql and use
// everything from one place, or import sub-packages directly for fine-grained control.

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

///| Table identity.
pub type Table = @builder.Table

///| Typed column reference.
pub type Column[T] = @builder.Column[T]

///| Type-erased column reference.
pub type ColumnRef = @ast.ColumnRef

///| A WHERE-clause expression tree.
pub type Expr = @ast.Expr

///| A SELECT statement AST node.
pub type SelectStmt = @ast.SelectStmt

///| An aggregation function call.
pub type Aggregation = @ast.Aggregation

///| ORDER BY clause.
pub type OrderByClause = @ast.OrderByClause

///| ORDER BY direction.
pub type OrderDirection = @ast.OrderDirection

///| PostgreSQL column types.
pub type SqlType = @ast.SqlType

///| A parameterised value.
pub type Value = @ast.Value

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

///| Wrap an expression with NOT.
pub fn not_(expr : Expr) -> Expr {
  @ast.not_(expr)
}

///| COUNT(column) aggregation.
pub fn count[T](col : Column[T]) -> Aggregation {
  @builder.count(col)
}

///| SUM(column) aggregation.
pub fn sum[T](col : Column[T]) -> Aggregation {
  @builder.sum(col)
}

///| AVG(column) aggregation.
pub fn avg[T](col : Column[T]) -> Aggregation {
  @builder.avg(col)
}

///| MIN(column) aggregation.
pub fn min[T](col : Column[T]) -> Aggregation {
  @builder.min(col)
}

///| MAX(column) aggregation.
pub fn max[T](col : Column[T]) -> Aggregation {
  @builder.max(col)
}

///| COUNT(*) — count all rows.
pub fn count_star() -> Aggregation {
  @builder.count_star()
}
