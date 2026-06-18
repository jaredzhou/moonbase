// Cedar expression parser — recursive descent with ArrayView pattern matching.
// References: cedar-policy/cedar (Rust), cedar-policy/cedar-go
//
// Precedence per Cedar spec (lowest → highest):
//   Expr  ::= Or | 'if' Expr 'then' Expr 'else' Expr
//   Or    ::= And {'||' And}
//   And   ::= Relation {'&&' Relation}
//   Rel   ::= Add [RELOP Add | 'has' I | 'like' P | 'is' Path ('in' Add)?]
//   Add   ::= Mult {('+' | '-') Mult}
//   Mult  ::= Unary {'*' Unary}
//   Unary ::= ['!' | '-']×4 Member
//   Member::= Primary {'.' IDENT ['(' Args ')'] | '[' STR ']'}

// ParseError is defined in token.mbt

// ---------------------------------------------------------------------------
// parse_expr — top-level entry
// ---------------------------------------------------------------------------

pub fn parse_expr(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Keyword(If), .. }, .. rest] => {
      let (cond, rest) = parse_expr(rest)
      guard rest is [{ kind: Keyword(Then), .. }, .. r1] else {
        raise ParseError("expected 'then'", rest[0].pos)
      }
      let (then_expr, r1) = parse_expr(r1)
      guard r1 is [{ kind: Keyword(Else), .. }, .. r2] else {
        raise ParseError("expected 'else'", r1[0].pos)
      }
      let (else_expr, r2) = parse_expr(r2)
      (@ast.If(cond, then_expr, else_expr), r2)
    }
    _ => parse_or(tokens)
  }
}

// ---------------------------------------------------------------------------
// Or ::= And {'||' And}
// ---------------------------------------------------------------------------

fn parse_or(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_and(tokens)
  let mut expr = left
  let mut tkns = rest
  while tkns is [{ kind: Op(Or), .. }, .. r1] {
    let (right, r1) = parse_and(r1)
    expr = @ast.Or(expr, right)
    tkns = r1
  }
  (expr, tkns)
}

// ---------------------------------------------------------------------------
// And ::= Relation {'&&' Relation}
// ---------------------------------------------------------------------------

fn parse_and(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_relation(tokens)
  let mut expr = left
  let mut tkns = rest
  while tkns is [{ kind: Op(And), .. }, .. r1] {
    let (right, r1) = parse_relation(r1)
    expr = @ast.And(expr, right)
    tkns = r1
  }
  (expr, tkns)
}

// ---------------------------------------------------------------------------
// Relation ::= Add [RELOP Add | 'has' I | 'like' P | 'is' Path ('in' Add)?]
// ---------------------------------------------------------------------------

fn parse_relation(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_add(tokens)
  match rest {
    [{ kind: Op(Eq), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Eq, left, right), r1)
    }
    [{ kind: Op(Ne), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Ne, left, right), r1)
    }
    [{ kind: Op(Lt), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Less, left, right), r1)
    }
    [{ kind: Op(Le), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.LessEq, left, right), r1)
    }
    [{ kind: Op(Gt), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Gt, left, right), r1)
    }
    [{ kind: Op(Ge), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.Ge, left, right), r1)
    }
    [{ kind: Keyword(In), .. }, .. r1] => {
      let (right, r1) = parse_add(r1)
      (@ast.BinaryApp(@ast.In_, left, right), r1)
    }

    [{ kind: Keyword(Has), .. }, .. r1] => parse_has_expr(left, r1)
    [{ kind: Keyword(Like), .. }, .. r1] => parse_like_expr(left, r1)
    [{ kind: Keyword(Is), .. }, .. r1] => parse_is_expr(left, r1)

    _ => (left, rest)
  }
}

// ---------------------------------------------------------------------------
// Add ::= Mult {('+' | '-') Mult}
// ---------------------------------------------------------------------------

fn parse_add(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_mult(tokens)
  let mut expr = left
  let mut tkns = rest
  while true {
    match tkns {
      [{ kind: Op(Add), .. }, .. r1] => {
        let (right, r1) = parse_mult(r1)
        expr = @ast.BinaryApp(@ast.Add, expr, right)
        tkns = r1
      }
      [{ kind: Op(Sub), .. }, .. r1] => {
        let (right, r1) = parse_mult(r1)
        expr = @ast.BinaryApp(@ast.Sub, expr, right)
        tkns = r1
      }
      _ => break
    }
  }
  (expr, tkns)
}

// ---------------------------------------------------------------------------
// Mult ::= Unary {'*' Unary}
// ---------------------------------------------------------------------------

fn parse_mult(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (left, rest) = parse_unary(tokens)
  match rest {
    [{ kind: Op(Mul), .. }, .. r1] => {
      let (right, r1) = parse_mult(r1)
      (@ast.BinaryApp(@ast.Mul, left, right), r1)
    }
    _ => (left, rest)
  }
}

// ---------------------------------------------------------------------------
// Unary ::= ['!' | '-']×4 Member
// ---------------------------------------------------------------------------

fn parse_unary(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Op(Not), .. }, .. rest] => {
      let (operand, rest) = parse_unary(rest)
      (@ast.UnaryApp(@ast.Not, operand), rest)
    }
    [{ kind: Op(Sub), .. }, .. rest] => match rest {
      [{ kind: Int(n), .. }, .. r2] => {
        // negative literal: -N → Lit(Long(-N)), then continue member
        parse_postfix(@ast.Lit(@ast.Long(-n)), r2)
      }
      _ => {
        let (operand, rest) = parse_unary(rest)
        (@ast.UnaryApp(@ast.Neg, operand), rest)
      }
    }
    _ => parse_member(tokens)
  }
}

// ---------------------------------------------------------------------------
// Member ::= Primary {'.' IDENT ['(' Args ')'] | '[' STR ']'}
// ---------------------------------------------------------------------------

fn parse_member(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (expr, rest) = parse_primary(tokens)
  parse_postfix(expr, rest)
}

fn parse_postfix(
  expr : @ast.Expr,
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [{ kind: Symbol("."), .. }, .. rest] => {
      guard rest is [{ kind: Ident(name), .. }, .. r2] else {
        raise ParseError("expected attribute name after dot", rest[0].pos)
      }
      match r2 {
        [{ kind: Bracket('('), .. }, .. r3] => {
          let (args, r3) = parse_arg_list(r3)
          guard r3 is [{ kind: Bracket(')'), .. }, .. r4] else {
            raise ParseError("expected ')'", r3[0].pos)
          }
          parse_postfix(make_method_call(expr, name, args), r4)
        }
        _ => parse_postfix(@ast.GetAttr(expr, name), r2)
      }
    }

    [{ kind: Bracket('['), .. }, .. rest] => {
      guard rest is [{ kind: String(s), .. }, .. r2] else {
        raise ParseError("expected string in bracket access", rest[0].pos)
      }
      guard r2 is [{ kind: Bracket(']'), .. }, .. r3] else {
        raise ParseError("expected ']'", r2[0].pos)
      }
      parse_postfix(@ast.GetAttr(expr, unescape_string(s)), r3)
    }

    _ => (expr, tokens)
  }
}

fn make_method_call(
  lhs : @ast.Expr,
  method_name : String,
  args : Array[@ast.Expr]
) -> @ast.Expr {
  match method_name {
    "contains" => @ast.BinaryApp(@ast.Contains, lhs, args[0])
    "containsAll" => @ast.BinaryApp(@ast.ContainsAll, lhs, args[0])
    "containsAny" => @ast.BinaryApp(@ast.ContainsAny, lhs, args[0])
    "getTag" => @ast.BinaryApp(@ast.GetTag, lhs, args[0])
    "hasTag" => @ast.BinaryApp(@ast.HasTag, lhs, args[0])
    "isEmpty" => @ast.UnaryApp(@ast.IsEmpty, lhs)
    _ => @ast.ExtensionApp({ ns: [], name: method_name }, cons_expr(lhs, args))
  }
}

// ---------------------------------------------------------------------------
// Primary ::= LITERAL | VAR | Entity | '(' Expr ')' | '[' ... ']' | '{' ... '}'
// ---------------------------------------------------------------------------

fn parse_primary(
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  match tokens {
    [head, .. rest] => match head.kind {
      Bool(b) => (@ast.Lit(@ast.Bool(b)), rest)
      Int(n) => (@ast.Lit(@ast.Long(n)), rest)
      String(s) => (@ast.Lit(@ast.String(unescape_string(s))), rest)

      Ident("principal") => (@ast.Var(@ast.Principal), rest)
      Ident("action") => (@ast.Var(@ast.Action), rest)
      Ident("resource") => (@ast.Var(@ast.Resource), rest)
      Ident("context") => (@ast.Var(@ast.Context), rest)

      Ident(_) => parse_entity_or_extfun(head, rest)

      Bracket('(') => {
        let (expr, rest) = parse_expr(rest)
        guard rest is [{ kind: Bracket(')'), .. }, .. r2] else {
          raise ParseError("expected ')'", rest[0].pos)
        }
        (expr, r2)
      }

      Bracket('[') => {
        let (elems, rest) = parse_comma_list(rest, ']')
        (@ast.Set(elems), rest)
      }

      Bracket('{') => {
        let (entries, rest) = parse_record_body(rest)
        (@ast.Record(entries), rest)
      }

      _ => raise ParseError("unexpected token in expression", head.pos)
    }
    [] => raise ParseError("unexpected end of expression",
      @ast.Position::{filename: "", offset: 0, line: 0, column: 0})
  }
}

// ---------------------------------------------------------------------------
// Entity UID or extension function call
// ---------------------------------------------------------------------------

fn parse_entity_or_extfun(
  first_tok : Token,
  rest : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard first_tok.kind is Ident(first_name) else {
    raise ParseError("expected entity or function name", first_tok.pos)
  }

  // extension function call: func(args)
  if rest.length() > 0 && rest[0].kind == Bracket('(') {
    let (args, r2) = parse_arg_list(rest[1:])
    guard r2.length() > 0 && r2[0].kind == Bracket(')') else {
      raise ParseError("expected ')'", first_tok.pos)
    }
    return (@ast.ExtensionApp({ ns: [], name: first_name }, args), r2[1:])
  }

  // entity UID: Type::...::"id"
  guard rest is [{ kind: Symbol("::"), .. }, .. r2] else {
    raise ParseError("expected '(' or '::'", rest[0].pos)
  }
  let mut path = first_name
  let mut tkns = r2
  while true {
    match tkns {
      [{ kind: Ident(next), .. }, .. r3] => {
        path = "\{path}::\{next}"
        guard r3 is [{ kind: Symbol("::"), .. }, .. r4] else {
          raise ParseError("expected '::' in entity UID", r3[0].pos)
        }
        tkns = r4
      }
      [{ kind: String(id), .. }, .. r3] =>
        return (@ast.Lit(@ast.EntityUID({ type_: path, id })), r3)
      [t, ..] =>
        raise ParseError("expected type name or id string", t.pos)
      [] =>
        raise ParseError("unexpected end of entity UID", first_tok.pos)
    }
  }
  raise ParseError("unexpected end of entity UID", first_tok.pos)
}

// ---------------------------------------------------------------------------
// Special RHS parsers — has / like / is
// ---------------------------------------------------------------------------

fn parse_has_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard tokens is [head, .. r1] else {
    raise ParseError("expected attribute after 'has'", tokens[0].pos)
  }
  let first_attr = match head.kind {
    Ident(a) => a
    String(s) => unescape_string(s)
    _ => raise ParseError("expected attribute after 'has'", head.pos)
  }

  let mut result = @ast.HasAttr(lhs, first_attr)
  let mut current = @ast.GetAttr(lhs, first_attr)
  let mut tkns = r1

  while true {
    match tkns {
      [{ kind: Symbol("."), .. }, .. r2] => {
        guard r2 is [{ kind: Ident(attr), .. }, .. r3] else {
          raise ParseError("expected attribute name after dot", r2[0].pos)
        }
        result = @ast.And(result, @ast.HasAttr(current, attr))
        current = @ast.GetAttr(current, attr)
        tkns = r3
      }
      _ => break
    }
  }

  (result, tkns)
}

fn parse_like_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: String(pat), .. }, .. r1] else {
    raise ParseError("expected string pattern after 'like'", tokens[0].pos)
  }
  let pattern = parse_pattern(pat)
  (@ast.Like(lhs, pattern), r1)
}

fn parse_is_expr(
  lhs : @ast.Expr,
  tokens : ArrayView[Token]
) -> (@ast.Expr, ArrayView[Token]) raise ParseError {
  let (etype, r1) = parse_entity_type(tokens)
  match r1 {
    [{ kind: Keyword(In), .. }, .. r2] => {
      let (in_entity, r2) = parse_add(r2)
      let is_expr = @ast.Expr::Is(lhs, etype)
      (@ast.And(is_expr, @ast.BinaryApp(@ast.In_,
        @ast.Expr::Is(lhs, etype), in_entity)), r2)
    }
    _ => (@ast.Expr::Is(lhs, etype), r1)
  }
}

// ---------------------------------------------------------------------------
// List / record / argument parsers
// ---------------------------------------------------------------------------

fn parse_arg_list(
  tokens : ArrayView[Token]
) -> (Array[@ast.Expr], ArrayView[Token]) raise ParseError {
  let args : Array[@ast.Expr] = []
  let mut tkns = tokens
  while true {
    match tkns {
      [{ kind: Bracket(')'), .. }, ..] => break
      _ => {
        let (arg, r2) = parse_expr(tkns)
        args.push(arg)
        tkns = match r2 {
          [{ kind: Symbol(","), .. }, .. r3] => r3
          _ => r2
        }
      }
    }
  }
  (args, tkns)
}

fn parse_comma_list(
  tokens : ArrayView[Token],
  end_bracket : Char
) -> (Array[@ast.Expr], ArrayView[Token]) raise ParseError {
  let exprs : Array[@ast.Expr] = []
  let mut tkns = tokens
  while true {
    match tkns {
      [{ kind: Bracket(b), .. }, .. r1] if b == end_bracket => {
        tkns = r1
        break
      }
      _ => {
        let (expr, r2) = parse_expr(tkns)
        exprs.push(expr)
        tkns = match r2 {
          [{ kind: Symbol(","), .. }, .. r3] => r3
          _ => r2
        }
      }
    }
  }
  (exprs, tkns)
}

fn parse_record_body(
  tokens : ArrayView[Token]
) -> (Array[(String, @ast.Expr)], ArrayView[Token]) raise ParseError {
  let entries : Array[(String, @ast.Expr)] = []
  let mut tkns = tokens
  while true {
    match tkns {
      [{ kind: Bracket('}'), .. }, .. r1] => return (entries, r1)
      [head, .. r2] => {
        let key = match head.kind {
          Ident(k) => k
          String(s) => unescape_string(s)
          _ => raise ParseError("expected record key", head.pos)
        }
        guard r2 is [{ kind: Symbol(":"), .. }, .. r3] else {
          raise ParseError("expected ':'", r2[0].pos)
        }
        let (value, r4) = parse_expr(r3)
        entries.push((key, value))
        tkns = match r4 {
          [{ kind: Symbol(","), .. }, .. r5] => r5
          _ => r4
        }
      }
      [] => raise ParseError("expected '}'",
        @ast.Position::{filename: "", offset: 0, line: 0, column: 0})
    }
  }
  raise ParseError("expected '}'", tokens[0].pos)
}

// ---------------------------------------------------------------------------
// Entity type path
// ---------------------------------------------------------------------------

fn parse_entity_type(
  tokens : ArrayView[Token]
) -> (@ast.EntityType, ArrayView[Token]) raise ParseError {
  guard tokens is [{ kind: Ident(first), .. }, .. r1] else {
    raise ParseError("expected entity type", tokens[0].pos)
  }
  let mut path = first
  let mut tkns = r1
  while true {
    match tkns {
      [{ kind: Symbol("::"), .. }, .. r2] => {
        guard r2 is [{ kind: Ident(next), .. }, .. r3] else {
          raise ParseError("expected type name after ::", r2[0].pos)
        }
        path = "\{path}::\{next}"
        tkns = r3
      }
      _ => break
    }
  }
  (@ast.EntityType(path), tkns)
}

// ---------------------------------------------------------------------------
// Helpers — pattern, unescape, cons
// ---------------------------------------------------------------------------

fn parse_pattern(raw : String) -> @ast.Pattern {
  let char_array = raw.iter().to_array()
  let elems : Array[@ast.PatternElem] = []
  let mut i = 0
  while i < char_array.length() {
    if char_array[i] == '*' {
      elems.push(@ast.Wildcard)
      i = i + 1
    } else if char_array[i] == '\\' && i + 1 < char_array.length() {
      i = i + 1
      match char_array[i] {
        'n' => elems.push(@ast.Char('\n'))
        'r' => elems.push(@ast.Char('\r'))
        't' => elems.push(@ast.Char('\t'))
        _ => elems.push(@ast.Char(char_array[i]))
      }
      i = i + 1
    } else {
      elems.push(@ast.Char(char_array[i]))
      i = i + 1
    }
  }
  { elements: elems }
}

fn unescape_string(s : String) -> String {
  let chars = s.iter().to_array()
  let mut buf = ""
  let mut p = 0
  while p < chars.length() {
    let ch = chars[p]
    if ch == '\\' && p + 1 < chars.length() {
      p = p + 1
      match chars[p] {
        'n' => buf = buf + "\n"
        'r' => buf = buf + "\r"
        't' => buf = buf + "\t"
        '\\' => buf = buf + "\\"
        '"' => buf = buf + "\""
        '\'' => buf = buf + "'"
        '*' => buf = buf + "*"
        '0' => buf = buf + "\u0000"
        _ => buf = buf + chars[p].to_string()
      }
    } else {
      buf = buf + ch.to_string()
    }
    p = p + 1
  }
  buf
}

fn[T] cons_expr(x : T, xs : Array[T]) -> Array[T] {
  let result : Array[T] = [x]
  for i = 0; i < xs.length(); i = i + 1 {
    result.push(xs[i])
  }
  result
}
