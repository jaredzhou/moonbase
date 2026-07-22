// Bridge: queryx Expr / Query → foxql builders and AST.
//
// Usage:
//   1. Implement FieldResolver for your table proxy struct.
//   2. Call to_foxql_expr() or apply_select() to convert.

// ---------------------------------------------------------------------------
// FieldResolver — map queryx field names to foxql ColumnRefs
// ---------------------------------------------------------------------------

///|
/// Trait for resolving queryx string field names to foxql ColumnRefs.
pub(open) trait FieldResolver {
  fn resolve_column(Self, field : String) -> @ast.ColumnRef?
}

// ---------------------------------------------------------------------------
// Value conversion
// ---------------------------------------------------------------------------

///|
/// Convert a queryx Value to a foxql Value.
pub fn to_foxql_value(v : Value) -> @ast.Value {
  match v {
    Value::Null => @ast.Value::Null
    Value::Bool(b) => @ast.Value::Bool(b)
    Value::Int(n) => @ast.Value::Int(n.to_int())
    Value::Float(f) => @ast.Value::Float(f)
    Value::String(s) => @ast.Value::String(s)
  }
}

// ---------------------------------------------------------------------------
// Operator conversion
// ---------------------------------------------------------------------------

///|
/// Convert a queryx CmpOp to a foxql Operator.
pub fn to_foxql_op(op : CmpOp) -> @ast.Operator {
  match op {
    CmpOp::Eq => @ast.Operator::Eq
    CmpOp::Ne => @ast.Operator::Neq
    CmpOp::Gt => @ast.Operator::Gt
    CmpOp::Lt => @ast.Operator::Lt
    CmpOp::Ge => @ast.Operator::Gte
    CmpOp::Le => @ast.Operator::Lte
  }
}

// ---------------------------------------------------------------------------
// Expr conversion
// ---------------------------------------------------------------------------

///|
/// Convert a queryx Expr to a foxql Expr.
/// Returns None for Empty, Lit, and Field (no SQL condition).
pub fn[R : FieldResolver] to_foxql_expr(
  expr : Expr,
  resolver : R,
) -> @ast.Expr? {
  match expr {
    Expr::Empty => None
    Expr::Lit(_) => None
    Expr::Field(_) => None
    Expr::Compare(field, op, val) => {
      let col = match resolver.resolve_column(field) {
        Some(c) => c
        None => return None
      }
      Some(@ast.Expr::Compare(col, to_foxql_op(op), to_foxql_value(val)))
    }
    Expr::Between(field, lo, hi) => {
      let col = match resolver.resolve_column(field) {
        Some(c) => c
        None => return None
      }
      Some(
        @ast.Expr::Between(col, to_foxql_value(lo), to_foxql_value(hi)),
      )
    }
    Expr::StrMatch(field, kind, pattern) => {
      let col = match resolver.resolve_column(field) {
        Some(c) => c
        None => return None
      }
      let (op, sql_pattern) = strmatch_to_like(kind, pattern)
      Some(
        @ast.Expr::Compare(col, op, @ast.Value::String(sql_pattern)),
      )
    }
    Expr::And(sub_exprs) => {
      let converted = collect_exprs(sub_exprs, resolver)
      make_composed(fn(x) { @ast.Expr::And(x) }, converted)
    }
    Expr::Or(sub_exprs) => {
      let converted = collect_exprs(sub_exprs, resolver)
      make_composed(fn(x) { @ast.Expr::Or(x) }, converted)
    }
    Expr::Not(inner) => {
      match to_foxql_expr(inner, resolver) {
        Some(e) => Some(@ast.Expr::Not(e))
        None => None
      }
    }
  }
}

///|
fn[R : FieldResolver] collect_exprs(
  exprs : Array[Expr],
  resolver : R,
) -> Array[@ast.Expr] {
  let converted : Array[@ast.Expr] = []
  for e in exprs {
    match to_foxql_expr(e, resolver) {
      Some(c) => converted.push(c)
      None => ()
    }
  }
  converted
}

///|
fn make_composed(
  cons : (Array[@ast.Expr]) -> @ast.Expr,
  parts : Array[@ast.Expr],
) -> @ast.Expr? {
  if parts.length() == 0 {
    None
  } else if parts.length() == 1 {
    Some(parts[0])
  } else {
    Some(cons(parts))
  }
}

// ---------------------------------------------------------------------------
// StrMatch → LIKE conversion
// ---------------------------------------------------------------------------

///|
fn strmatch_to_like(kind : StrKind, pattern : String) -> (@ast.Operator, String) {
  match kind {
    StrKind::Contains => (@ast.Operator::Like, "%" + pattern + "%")
    StrKind::StartsWith => (@ast.Operator::Like, pattern + "%")
    StrKind::EndsWith => (@ast.Operator::Like, "%" + pattern)
  }
}

// ---------------------------------------------------------------------------
// Query → foxql builder
// ---------------------------------------------------------------------------

///|
/// Apply a queryx Query to a foxql SelectBuilder (WHERE, ORDER BY, LIMIT, OFFSET).
pub fn[R : FieldResolver] apply_select(
  query : Query,
  builder : @builder.SelectBuilder,
  resolver : R,
) -> @builder.SelectBuilder {
  let b1 = match to_foxql_expr(query.filter, resolver) {
    Some(cond) => builder.where_(cond)
    None => builder
  }
  let b2 = match query.order_by {
    Some(order) => apply_order(b1, order, resolver)
    None => b1
  }
  match query.page {
    Some(page) => b2.limit(page.size)
    None => b2
  }
}

///|
/// Apply a queryx Order string to a foxql SelectBuilder.
fn[R : FieldResolver] apply_order(
  builder : @builder.SelectBuilder,
  order : Order,
  resolver : R,
) -> @builder.SelectBuilder {
  let s = order.0
  if s == "" {
    return builder
  }
  let parts = split_order(s)
  apply_order_parts(builder, parts, 0, resolver)
}

///|
fn[R : FieldResolver] apply_order_parts(
  builder : @builder.SelectBuilder,
  parts : Array[String],
  i : Int,
  resolver : R,
) -> @builder.SelectBuilder {
  if i >= parts.length() {
    builder
  } else {
    let kv = split_order_kv(parts[i])
    let next = if kv.length() >= 2 {
      match resolver.resolve_column(kv[0]) {
        Some(col) => {
          let clause = if kv[1] == "desc" {
            @ast.OrderByClause::{
              column: col,
              direction: @ast.OrderDirection::Desc,
            }
          } else {
            @ast.OrderByClause::{
              column: col,
              direction: @ast.OrderDirection::Asc,
            }
          }
          builder.order_by(clause)
        }
        None => builder
      }
    } else {
      builder
    }
    apply_order_parts(next, parts, i + 1, resolver)
  }
}

///|
fn split_order(s : String) -> Array[String] {
  split_order_rec(s, 0, 0, [])
}

///|
fn split_order_rec(
  s : String,
  start : Int,
  pos : Int,
  acc : Array[String],
) -> Array[String] {
  if pos >= s.length() {
    let last = s[start:].trim().to_owned()
    if last != "" {
      acc.push(last)
    }
    acc
  } else if s[pos:pos + 1] == "," {
    let part = s[start:pos].trim().to_owned()
    if part != "" {
      acc.push(part)
    }
    split_order_rec(s, pos + 1, pos + 1, acc)
  } else {
    split_order_rec(s, start, pos + 1, acc)
  }
}

///|
fn split_order_kv(s : String) -> Array[String] {
  split_order_kv_rec(s, 0, 0, [])
}

///|
fn split_order_kv_rec(
  s : String,
  start : Int,
  pos : Int,
  acc : Array[String],
) -> Array[String] {
  if pos >= s.length() {
    acc.push(s[start:].trim().to_owned())
    acc
  } else if s[pos:pos + 1] == ":" {
    acc.push(s[start:pos].trim().to_owned())
    split_order_kv_rec(s, pos + 1, pos + 1, acc)
  } else {
    split_order_kv_rec(s, start, pos + 1, acc)
  }
}
