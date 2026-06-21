// Expression evaluation — recursive evaluator for all 16 Expr variants.
// Reference: cedar-policy-core/src/evaluator.rs — partial_eval_expr

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

///|
/// Convert a Literal AST node to a concrete Value.
fn lit_to_value(lit : @ast.Literal) -> @ast.Value {
  match lit {
    @ast.Literal::Bool(b) => @ast.Value::Bool(b)
    @ast.Literal::Long(n) => @ast.Value::Long(n)
    @ast.Literal::String(s) => @ast.Value::String(s)
    @ast.Literal::EntityUID(uid) => @ast.Value::EntityUID(uid)
  }
}

///|
/// Look up a PARC variable from the Request. Returns a concrete Value for
/// concrete slots, or an Unknown Expr for unknown slots (partial eval).
fn var_to_result(vk : @ast.VarKind, req : Request) -> EvalResult {
  match vk {
    @ast.VarKind::Principal =>
      match req.principal {
        EntityUIDEntry::Concrete(uid) =>
          EvalResult::Value(@ast.Value::EntityUID(uid))
        EntityUIDEntry::Unknown(ty) =>
          EvalResult::Residual(
            @ast.Expr::Unknown("principal", Some(@ast.Type::Entity(ty))),
          )
      }
    @ast.VarKind::Action =>
      match req.action {
        EntityUIDEntry::Concrete(uid) =>
          EvalResult::Value(@ast.Value::EntityUID(uid))
        EntityUIDEntry::Unknown(ty) =>
          EvalResult::Residual(
            @ast.Expr::Unknown("action", Some(@ast.Type::Entity(ty))),
          )
      }
    @ast.VarKind::Resource =>
      match req.resource {
        EntityUIDEntry::Concrete(uid) =>
          EvalResult::Value(@ast.Value::EntityUID(uid))
        EntityUIDEntry::Unknown(ty) =>
          EvalResult::Residual(
            @ast.Expr::Unknown("resource", Some(@ast.Type::Entity(ty))),
          )
      }
    @ast.VarKind::Context =>
      match req.context {
        Context::Concrete(v) => EvalResult::Value(v)
        Context::Unknown(e) => EvalResult::Residual(e)
        Context::Partial(expr) =>
          match expr {
            @ast.Expr::Record(pairs) => {
              let concrete : Map[String, @ast.Value] = Map([])
              for pair in pairs {
                let (key, val_expr) = pair
                match val_expr {
                  @ast.Expr::Lit(lit) => concrete.set(key, lit_to_value(lit))
                  @ast.Expr::Unknown(_, _) => () // skip — handled by get_attr_value
                  _ => concrete.set(key, @ast.Value::String("unexpected")) // fallback
                }
              }
              EvalResult::Value(@ast.Value::Record(concrete))
            }
            _ => EvalResult::Value(@ast.Value::Record(Map([]))) // fallback
          }
      }
  }
}

///|
/// Check if entity exists in store. If not, entity-lookup produces a residual
/// so that reauthorize can resolve it later with an expanded store.
fn[S : EntityStore] entity_exists(uid : @ast.EntityUID, store : S) -> Bool {
  match store.get_entity(uid) {
    Some(_) => true
    None => false
  }
}

///|
/// Handle the `in` operator with hierarchy traversal.
/// Returns Residual if the entity being checked is not in the store (so
/// reauthorize with more entities can resolve it later).
fn[S : EntityStore] eval_in_op(
  uid_val : @ast.Value,
  target : @ast.Value,
  store : S,
) -> EvalResult {
  match (uid_val, target) {
    (@ast.Value::EntityUID(uid), @ast.Value::EntityUID(parent)) =>
      if entity_exists(uid, store) {
        EvalResult::Value(@ast.Value::Bool(is_descendant(uid, parent, store)))
      } else {
        EvalResult::Residual(
          @ast.Expr::BinaryApp(
            @ast.BinaryOp::In_,
            @ast.Expr::Lit(@ast.Literal::EntityUID(uid)),
            @ast.Expr::Lit(@ast.Literal::EntityUID(parent)),
          ),
        )
      }
    (@ast.Value::EntityUID(uid), @ast.Value::Set(uids)) =>
      if entity_exists(uid, store) {
        for target_val in uids {
          match target_val {
            @ast.Value::EntityUID(tuid) =>
              if is_descendant(uid, tuid, store) {
                return EvalResult::Value(@ast.Value::Bool(true))
              }
            _ => continue
          }
        }
        EvalResult::Value(@ast.Value::Bool(false))
      } else {
        EvalResult::Residual(
          @ast.Expr::BinaryApp(
            @ast.BinaryOp::In_,
            @ast.Expr::Lit(@ast.Literal::EntityUID(uid)),
            @ast.Expr::Set(
              uids.map(fn(v : @ast.Value) -> @ast.Expr {
                @ast.Expr::Lit(lit_from_value(v))
              }),
            ),
          ),
        )
      }
    _ => EvalResult::Value(@ast.Value::Bool(false))
  }
}

///|
/// Convert a Value back to a Literal (for residual construction).
fn lit_from_value(v : @ast.Value) -> @ast.Literal {
  match v {
    @ast.Value::Bool(b) => @ast.Literal::Bool(b)
    @ast.Value::Long(n) => @ast.Literal::Long(n)
    @ast.Value::String(s) => @ast.Literal::String(s)
    @ast.Value::EntityUID(uid) => @ast.Literal::EntityUID(uid)
    _ => @ast.Literal::String("unexpected") // fallback — shouldn't happen for entity sets
  }
}

///|
/// Get an attribute from a record or entity.
/// When the record is a context Record and the key corresponds to an unknown
/// context entry, returns the residual expression from the context map.
fn[S : EntityStore] get_attr_value(
  v : @ast.Value,
  attr : String,
  store : S,
  req : Request,
) -> EvalResult raise EvalError {
  match v {
    @ast.Value::Record(map) =>
      match map.get(attr) {
        Some(val) => EvalResult::Value(val)
        None =>
          match req.context {
            Context::Partial(@ast.Expr::Record(pairs)) => {
              let mut found = false
              for pair in pairs {
                if pair.0 == attr {
                  match pair.1 {
                    @ast.Expr::Unknown(_, _) => found = true
                    _ => ()
                  }
                }
              }
              if found {
                EvalResult::Residual(
                  @ast.Expr::GetAttr(
                    @ast.Expr::Var(@ast.VarKind::Context),
                    attr,
                  ),
                )
              } else {
                raise EntityNotFound("attribute '\{attr}' not found in record")
              }
            }
            _ => raise EntityNotFound("attribute '\{attr}' not found in record")
          }
      }
    @ast.Value::EntityUID(uid) =>
      match store.get_entity(uid) {
        Some(entity) =>
          match entity.attrs.get(attr) {
            Some(val) => EvalResult::Value(val)
            None =>
              raise EntityNotFound(
                "attribute '\{attr}' not found on entity '\{uid.type_}::\"\{uid.id}\"",
              )
          }
        None =>
          raise EntityNotFound("entity '\{uid.type_}::\"\{uid.id}\" not found")
      }
    _ =>
      raise TypeMismatch(
        "cannot access attribute '\{attr}' on non-record, non-entity",
      )
  }
}

///|
/// Check if a record or entity has an attribute.
/// For context Records, unknown entries count as having the attribute.
fn[S : EntityStore] has_attr_value(
  v : @ast.Value,
  attr : String,
  store : S,
  req : Request,
) -> @ast.Value {
  match v {
    @ast.Value::Record(map) =>
      if map.contains(attr) {
        @ast.Value::Bool(true)
      } else {
        match req.context {
          Context::Partial(@ast.Expr::Record(pairs)) => {
            let mut found = false
            for pair in pairs {
              if pair.0 == attr {
                match pair.1 {
                  @ast.Expr::Unknown(_, _) => found = true
                  _ => ()
                }
              }
            }
            @ast.Value::Bool(found)
          }
          _ => @ast.Value::Bool(false)
        }
      }
    @ast.Value::EntityUID(uid) =>
      match store.get_entity(uid) {
        Some(entity) => @ast.Value::Bool(entity.attrs.contains(attr))
        None => @ast.Value::Bool(false)
      }
    _ => @ast.Value::Bool(false)
  }
}

///|
/// Evaluate all elements of a Set expression. Returns Value if all concrete, Residual if any residual.
fn[S : EntityStore] eval_set_elements(
  elements : Array[@ast.Expr],
  req : Request,
  store : S,
) -> EvalResult raise EvalError {
  let vals : Array[@ast.Value] = []
  for elem in elements {
    match eval_expr(elem, req, store) {
      EvalResult::Value(v) => vals.push(v)
      EvalResult::Residual(_) =>
        return EvalResult::Residual(@ast.Expr::Set(elements))
    }
  }
  EvalResult::Value(@ast.Value::Set(vals))
}

///|
/// Evaluate all key-value pairs of a Record expression.
fn[S : EntityStore] eval_record_pairs(
  pairs : Array[(String, @ast.Expr)],
  req : Request,
  store : S,
) -> EvalResult raise EvalError {
  let map_items : Array[(String, @ast.Value)] = []
  for pair in pairs {
    match eval_expr(pair.1, req, store) {
      EvalResult::Value(v) => map_items.push((pair.0, v))
      EvalResult::Residual(_) =>
        return EvalResult::Residual(@ast.Expr::Record(pairs))
    }
  }
  EvalResult::Value(@ast.Value::Record(Map(map_items)))
}

// ---------------------------------------------------------------------------
// Main expression evaluator
// ---------------------------------------------------------------------------

///|
/// Convert a concrete Value back into an Expr (inverse of lit_to_value).
pub fn value_to_expr(v : @ast.Value) -> @ast.Expr {
  match v {
    @ast.Value::Bool(b) => @ast.Expr::Lit(@ast.Literal::Bool(b))
    @ast.Value::Long(n) => @ast.Expr::Lit(@ast.Literal::Long(n))
    @ast.Value::String(s) => @ast.Expr::Lit(@ast.Literal::String(s))
    @ast.Value::EntityUID(uid) => @ast.Expr::Lit(@ast.Literal::EntityUID(uid))
    @ast.Value::Set(items) => @ast.Expr::Set(items.map(value_to_expr))
    @ast.Value::Record(_) => @ast.Expr::Unknown("record", None)
    @ast.Value::Extension(name, s) =>
      @ast.Expr::ExtensionApp(name, [@ast.Expr::Lit(@ast.Literal::String(s))])
  }
}

///|
/// Best-effort evaluation: tries partial_eval, falls back to original expr on error.
/// Used when one side of a short-circuit operator is residual — the other side's
/// errors must be suppressed because the residual side might evaluate to a value
/// that short-circuits past the error at runtime.
fn[S : EntityStore] try_eval(
  expr : @ast.Expr,
  req : Request,
  store : S,
) -> EvalResult {
  eval_expr(expr, req, store) catch {
    _ => EvalResult::Residual(expr)
  }
}

///|
/// Evaluate a Cedar expression in the context of a Request and EntityStore.
/// Returns Value(concrete) for fully-reducible expressions, or Residual(expr)
/// for expressions that cannot be fully reduced (partial evaluation).
pub fn[S : EntityStore] eval_expr(
  expr : @ast.Expr,
  req : Request,
  store : S,
) -> EvalResult raise EvalError {
  match expr {
    @ast.Expr::Lit(lit) => EvalResult::Value(lit_to_value(lit))
    @ast.Expr::Var(vk) => var_to_result(vk, req)

    // If — evaluate condition, then branch
    @ast.Expr::If(cond, then_e, else_e) =>
      match eval_expr(cond, req, store) {
        EvalResult::Value(@ast.Value::Bool(true)) =>
          eval_expr(then_e, req, store)
        EvalResult::Value(@ast.Value::Bool(false)) =>
          eval_expr(else_e, req, store)
        EvalResult::Value(_) => raise TypeMismatch("If condition must be Bool")
        EvalResult::Residual(re) =>
          EvalResult::Residual(@ast.Expr::If(re, then_e, else_e))
      }

    // And — short-circuit on false.
    // When left is residual, right-side errors are suppressed (they would be
    // short-circuited if left eventually evaluates to false at runtime).
    // true && residual is NOT simplified to residual — the And wrapper
    // preserves the type check that the right operand must be Bool.
    @ast.Expr::And(left, right) =>
      match eval_expr(left, req, store) {
        EvalResult::Value(@ast.Value::Bool(false)) =>
          EvalResult::Value(@ast.Value::Bool(false))
        EvalResult::Value(@ast.Value::Bool(true)) =>
          match eval_expr(right, req, store) {
            EvalResult::Value(@ast.Value::Bool(true)) =>
              EvalResult::Value(@ast.Value::Bool(true))
            EvalResult::Value(@ast.Value::Bool(false)) =>
              EvalResult::Value(@ast.Value::Bool(false))
            EvalResult::Value(_) =>
              raise TypeMismatch("And requires Bool operands")
            EvalResult::Residual(re) =>
              EvalResult::Residual(
                @ast.Expr::And(@ast.Expr::Lit(@ast.Literal::Bool(true)), re),
              )
          }
        EvalResult::Value(_) => raise TypeMismatch("And requires Bool operands")
        EvalResult::Residual(le) =>
          match try_eval(right, req, store) {
            EvalResult::Value(rv) =>
              EvalResult::Residual(@ast.Expr::And(le, value_to_expr(rv)))
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::And(le, re))
          }
      }

    // Or — short-circuit on true.
    // false || residual is NOT simplified to residual — the Or wrapper
    // preserves the type check that the right operand must be Bool.
    @ast.Expr::Or(left, right) =>
      match eval_expr(left, req, store) {
        EvalResult::Value(@ast.Value::Bool(true)) =>
          EvalResult::Value(@ast.Value::Bool(true))
        EvalResult::Value(@ast.Value::Bool(false)) =>
          match eval_expr(right, req, store) {
            EvalResult::Value(@ast.Value::Bool(true)) =>
              EvalResult::Value(@ast.Value::Bool(true))
            EvalResult::Value(@ast.Value::Bool(false)) =>
              EvalResult::Value(@ast.Value::Bool(false))
            EvalResult::Value(_) =>
              raise TypeMismatch("Or requires Bool operands")
            EvalResult::Residual(re) =>
              EvalResult::Residual(
                @ast.Expr::Or(@ast.Expr::Lit(@ast.Literal::Bool(false)), re),
              )
          }
        EvalResult::Value(_) => raise TypeMismatch("Or requires Bool operands")
        EvalResult::Residual(le) =>
          match try_eval(right, req, store) {
            EvalResult::Value(rv) =>
              EvalResult::Residual(@ast.Expr::Or(le, value_to_expr(rv)))
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::Or(le, re))
          }
      }

    // UnaryApp — delegate to operator module
    @ast.Expr::UnaryApp(op, arg) =>
      match eval_expr(arg, req, store) {
        EvalResult::Value(v) => EvalResult::Value(eval_unary(op, v))
        EvalResult::Residual(re) =>
          EvalResult::Residual(@ast.Expr::UnaryApp(op, re))
      }

    // BinaryApp — delegate to operator module (or handle store-dependent ops inline)
    @ast.Expr::BinaryApp(op, lhs, rhs) =>
      match eval_expr(lhs, req, store) {
        EvalResult::Value(lv) =>
          match eval_expr(rhs, req, store) {
            EvalResult::Value(rv) =>
              match op {
                @ast.BinaryOp::In_ => eval_in_op(lv, rv, store)
                _ => EvalResult::Value(eval_binary(op, lv, rv))
              }
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::BinaryApp(op, lhs, re))
          }
        EvalResult::Residual(le) =>
          match eval_expr(rhs, req, store) {
            EvalResult::Value(_) =>
              EvalResult::Residual(@ast.Expr::BinaryApp(op, le, rhs))
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::BinaryApp(op, le, re))
          }
      }

    // GetAttr — record access or entity dereference
    @ast.Expr::GetAttr(e, attr) =>
      match eval_expr(e, req, store) {
        EvalResult::Value(v) => get_attr_value(v, attr, store, req)
        EvalResult::Residual(re) =>
          EvalResult::Residual(@ast.Expr::GetAttr(re, attr))
      }

    // HasAttr — check if record/entity has attribute
    @ast.Expr::HasAttr(e, attr) =>
      match eval_expr(e, req, store) {
        EvalResult::Value(v) =>
          EvalResult::Value(has_attr_value(v, attr, store, req))
        EvalResult::Residual(re) =>
          EvalResult::Residual(@ast.Expr::HasAttr(re, attr))
      }

    // GetTag — get entity tag
    @ast.Expr::GetTag(entity_e, tag_e) =>
      match eval_expr(entity_e, req, store) {
        EvalResult::Value(lv) =>
          match eval_expr(tag_e, req, store) {
            EvalResult::Value(rv) =>
              match (lv, rv) {
                (@ast.Value::EntityUID(uid), @ast.Value::String(tag)) =>
                  match store.get_entity(uid) {
                    Some(entity) =>
                      match entity.tags.get(tag) {
                        Some(val) => EvalResult::Value(val)
                        None =>
                          raise EntityNotFound(
                            "tag '\{tag}' not found on entity '\{uid.type_}::\"\{uid.id}\"",
                          )
                      }
                    None =>
                      raise EntityNotFound(
                        "entity '\{uid.type_}::\"\{uid.id}\" not found",
                      )
                  }
                (@ast.Value::EntityUID(_), _) =>
                  raise TypeMismatch("tag name must be a String")
                _ => raise TypeMismatch("GetTag requires an entity")
              }
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::GetTag(entity_e, re))
          }
        EvalResult::Residual(le) =>
          EvalResult::Residual(@ast.Expr::GetTag(le, tag_e))
      }

    // HasTag — check if entity has tag
    @ast.Expr::HasTag(entity_e, tag_e) =>
      match eval_expr(entity_e, req, store) {
        EvalResult::Value(lv) =>
          match eval_expr(tag_e, req, store) {
            EvalResult::Value(rv) =>
              match (lv, rv) {
                (@ast.Value::EntityUID(uid), @ast.Value::String(tag)) =>
                  match store.get_entity(uid) {
                    Some(entity) =>
                      EvalResult::Value(
                        @ast.Value::Bool(entity.tags.contains(tag)),
                      )
                    None =>
                      raise EntityNotFound(
                        "entity '\{uid.type_}::\"\{uid.id}\" not found",
                      )
                  }
                _ => EvalResult::Value(@ast.Value::Bool(false))
              }
            EvalResult::Residual(re) =>
              EvalResult::Residual(@ast.Expr::HasTag(entity_e, re))
          }
        EvalResult::Residual(le) =>
          EvalResult::Residual(@ast.Expr::HasTag(le, tag_e))
      }

    // Like — string pattern matching
    @ast.Expr::Like(e, pattern) =>
      match eval_expr(e, req, store) {
        EvalResult::Value(@ast.Value::String(s)) =>
          EvalResult::Value(@ast.Value::Bool(wildcard_match(s, pattern)))
        EvalResult::Value(_) =>
          raise TypeMismatch("Like requires String operand")
        EvalResult::Residual(re) =>
          EvalResult::Residual(@ast.Expr::Like(re, pattern))
      }

    // Is — entity type test
    @ast.Expr::Is(e, ty) =>
      match eval_expr(e, req, store) {
        EvalResult::Value(@ast.Value::EntityUID(uid)) =>
          EvalResult::Value(@ast.Value::Bool(uid.type_ == ty.0))
        EvalResult::Value(_) => EvalResult::Value(@ast.Value::Bool(false))
        EvalResult::Residual(re) => EvalResult::Residual(@ast.Expr::Is(re, ty))
      }

    // Set — evaluate all elements
    @ast.Expr::Set(elements) => eval_set_elements(elements, req, store)

    // Record — evaluate all key-value pairs
    @ast.Expr::Record(pairs) => eval_record_pairs(pairs, req, store)

    // ExtensionApp — not supported in MVP
    @ast.Expr::ExtensionApp(name, _) =>
      raise ExtensionNotSupported(
        "extension function '\{name.ns.join("::")}::\{name.name}' not supported",
      )

    // Slot — not supported in MVP
    @ast.Expr::Slot(_) => raise SlotNotSupported

    // Unknown — return as residual (preserves type annotation if any)
    @ast.Expr::Unknown(_, _) => EvalResult::Residual(expr)
  }
}
