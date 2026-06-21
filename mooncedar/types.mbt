// Top-level re-exports — alias the ast package types for convenience.
// The authoritative definitions are in ast/types.mbt and ast/expr.mbt.

///|
pub fn parse_policies(
  src : String,
) -> Array[@ast.Policy] raise @parser.ParseError {
  @parser.parse_policies(src)
}

///|
pub fn stringify(p : @ast.Policy) -> String {
  @parser.stringify(p)
}

///|
pub fn stringify_expr(e : @ast.Expr) -> String {
  @parser.stringify_expr(e)
}
