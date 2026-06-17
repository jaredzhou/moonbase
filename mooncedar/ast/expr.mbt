// Cedar expression AST — all expression and policy nodes.
// References:
//   Rust: cedar-policy-core/src/ast/ (ExprKind, Policy, TemplateBody)
//   Go:   cedar-go/x/exp/ast/ (node.go, policy.go, scope.go)

// ---------------------------------------------------------------------------
// Literal — atomic leaf values (subset of Value, used by Expr::Lit)
// ---------------------------------------------------------------------------

/// A literal value that can appear directly in Cedar source text.
/// Set and Record are NOT literals — they are compound expressions.
pub(all) enum Literal {
  Bool(Bool)
  Long(Int64)
  String(String)
  EntityUID(EntityUID)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Variables & Operators
// ---------------------------------------------------------------------------

/// The four PARC variables that Cedar expressions can reference.
pub(all) enum VarKind {
  Principal
  Action
  Resource
  Context
} derive(Debug, Eq)

/// Built-in unary operators.
pub(all) enum UnaryOp {
  Not       // logical negation — argument must have Bool type
  Neg       // integer negation — argument must have Long type
  IsEmpty   // set/record emptiness test
} derive(Debug, Eq)

/// Built-in binary operators.
pub(all) enum BinaryOp {
  Eq          // total equality — different types return false, not error
  Ne          // !=
  Less        // <  — arguments must have Long type
  LessEq      // <= — arguments must have Long type
  Gt          // >  — arguments must have Long type
  Ge          // >= — arguments must have Long type
  Add         // +  — integer addition
  Sub         // -  — integer subtraction
  Mul         // *  — integer multiplication
  In_         // hierarchy membership — first is entity, second is entity or set of entities
  Contains    // set membership test
  ContainsAll // set superset test
  ContainsAny // set intersection test (is intersection non-empty?)
  GetTag      // get an entity tag by key — first arg entity, second arg string
  HasTag      // does entity have this tag?
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Expression AST
// ---------------------------------------------------------------------------

/// The complete expression AST for Cedar.
/// Covers every node type from the Cedar language specification.
pub(all) enum Expr {
  // Literal value (Bool, Long, String, EntityUID)
  Lit(Literal)

  // Variable reference (principal / action / resource / context)
  Var(VarKind)

  // Ternary conditional: if test_expr then then_expr else else_expr
  If(Expr, Expr, Expr)

  // Boolean AND — short-circuit evaluation (left evaluated first)
  And(Expr, Expr)

  // Boolean OR — short-circuit evaluation (left evaluated first)
  Or(Expr, Expr)

  // Application of a built-in unary operator
  UnaryApp(UnaryOp, Expr)

  // Application of a built-in binary operator
  BinaryApp(BinaryOp, Expr, Expr)

  // Attribute access: expr.attr
  GetAttr(Expr, String)

  // Check whether an entity/record has a given attribute: expr has attr
  HasAttr(Expr, String)

  // String pattern matching (IAM StringLike semantics): expr like pattern
  Like(Expr, Pattern)

  // Entity type test: expr is EntityType
  Is(Expr, EntityType)

  // Set literal: [e1, e2, ...]
  Set(Array[Expr])

  // Anonymous record literal: { key1: val1, key2: val2, ... }
  Record(Array[(String, Expr)])

  // Extension function / method call: name(args...)
  ExtensionApp(Name, Array[Expr])

  // Template slot reference (for policy templates)
  Slot(String)

  // Symbolic Unknown for partial evaluation
  Unknown(String)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Expr builder — convenient constructors and chaining methods
// ---------------------------------------------------------------------------

// Leaf constructors (free functions)

pub fn val_bool(b : Bool) -> Expr {
  Lit(Bool(b))
}

pub fn val_long(l : Int64) -> Expr {
  Lit(Long(l))
}

pub fn val_str(s : String) -> Expr {
  Lit(String(s))
}

pub fn val_euid(type_ : String, id : String) -> Expr {
  Lit(EntityUID(EntityUID::{ type_, id }))
}

pub fn var_principal() -> Expr {
  Var(Principal)
}

pub fn var_action() -> Expr {
  Var(Action)
}

pub fn var_resource() -> Expr {
  Var(Resource)
}

pub fn var_context() -> Expr {
  Var(Context)
}

// Non-chaining constructors (free functions)

pub fn if_(cond : Expr, t : Expr, e : Expr) -> Expr {
  If(cond, t, e)
}

pub fn not_(e : Expr) -> Expr {
  UnaryApp(Not, e)
}

pub fn neg(e : Expr) -> Expr {
  UnaryApp(Neg, e)
}

pub fn is_empty(e : Expr) -> Expr {
  UnaryApp(IsEmpty, e)
}

pub fn set_(elements : Array[Expr]) -> Expr {
  Set(elements)
}

pub fn record_(pairs : Array[(String, Expr)]) -> Expr {
  Record(pairs)
}

pub fn ext_call(name : Name, args : Array[Expr]) -> Expr {
  ExtensionApp(name, args)
}

// Chaining methods on Expr

/// self == rhs
fn Expr::eq(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Eq, self, rhs)
}

/// self != rhs  — desugared: not_(eq(self, rhs))
fn Expr::ne(self : Expr, rhs : Expr) -> Expr {
  (BinaryApp(Ne, self, rhs))
}

/// self < rhs
fn Expr::lt(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Less, self, rhs)
}

/// self <= rhs
fn Expr::le(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(LessEq, self, rhs)
}

/// self > rhs  — desugared: not_(le(self, rhs))
fn Expr::gt(self : Expr, rhs : Expr) -> Expr {
  (BinaryApp(Gt, self, rhs))
}

/// self >= rhs  — desugared: not_(lt(self, rhs))
fn Expr::ge(self : Expr, rhs : Expr) -> Expr {
  (BinaryApp(Ge, self, rhs))
}

/// self + rhs
fn Expr::add(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Add, self, rhs)
}

/// self - rhs
fn Expr::sub(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Sub, self, rhs)
}

/// self * rhs
fn Expr::mul(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Mul, self, rhs)
}

/// self && rhs  (keyword: and)
fn Expr::and_(self : Expr, rhs : Expr) -> Expr {
  And(self, rhs)
}

/// self || rhs  (keyword: or)
fn Expr::or_(self : Expr, rhs : Expr) -> Expr {
  Or(self, rhs)
}

/// self in rhs  (keyword: in)
fn Expr::in_(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(In_, self, rhs)
}

/// self.contains(rhs)
fn Expr::contains(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(Contains, self, rhs)
}

/// self.contains_all(rhs)
fn Expr::contains_all(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(ContainsAll, self, rhs)
}

/// self.contains_any(rhs)
fn Expr::contains_any(self : Expr, rhs : Expr) -> Expr {
  BinaryApp(ContainsAny, self, rhs)
}

/// self.get_tag(tag)
fn Expr::get_tag(self : Expr, tag : Expr) -> Expr {
  BinaryApp(GetTag, self, tag)
}

/// self.has_tag(tag)
fn Expr::has_tag(self : Expr, tag : Expr) -> Expr {
  BinaryApp(HasTag, self, tag)
}

/// self.attr
fn Expr::access(self : Expr, attr : String) -> Expr {
  GetAttr(self, attr)
}

/// self has attr
fn Expr::has(self : Expr, attr : String) -> Expr {
  HasAttr(self, attr)
}

/// self like pattern
fn Expr::like(self : Expr, pattern : Pattern) -> Expr {
  Like(self, pattern)
}

/// self is EntityType  (keyword: is)
fn Expr::is_(self : Expr, ty : EntityType) -> Expr {
  Expr::Is(self, ty)
}

/// self is ty AND self in entity  — desugared to and_ + is_ + in_
fn Expr::is_in(self : Expr, ty : EntityType, entity : Expr) -> Expr {
  let lhs = Expr::Is(self, ty)
  And(lhs, BinaryApp(In_, self, entity))
}
