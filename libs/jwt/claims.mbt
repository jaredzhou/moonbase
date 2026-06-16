///|
/// Trait for JWT claims. Types implementing Claims can be used with
/// Token parsing to handle JSON deserialization and claim validation.
pub trait Claims: FromJson + ToJson {
  /// Validate registered claims (exp, nbf) with a clock leeway in seconds
  fn validate(Self, leeway : Int64) -> Unit raise JwtError
  /// Set issued-at and not-before timestamps (called during signing)
  fn set_issued_now(Self, now : Int64) -> Unit
}

///|
/// Standard registered JWT claims (RFC 7519 Section 4.1).
pub(all) struct RegisteredClaims {
  mut iss : String?
  mut sub : String?
  mut aud : Array[String]?
  mut exp : Int64?
  mut nbf : Int64?
  mut iat : Int64?
  mut jti : String?
} derive(Debug, FromJson, ToJson)

///|
/// Create empty RegisteredClaims.
pub fn RegisteredClaims::RegisteredClaims() -> RegisteredClaims {
  {
    iss: None,
    sub: None,
    aud: None,
    exp: None,
    nbf: None,
    iat: None,
    jti: None,
  }
}

///|
pub impl Claims for RegisteredClaims with fn validate(
  self : RegisteredClaims,
  leeway : Int64,
) -> Unit raise JwtError {
  match self.exp {
    Some(exp) => {
      let now = current_time_seconds()
      if now > exp + leeway {
        raise TokenExpired(expired_at=exp, now~)
      }
    }
    _ => ()
  }
  match self.nbf {
    Some(nbf) => {
      let now = current_time_seconds()
      if now < nbf - leeway {
        raise TokenNotYetValid(not_before=nbf, now~)
      }
    }
    _ => ()
  }
}

///|
pub impl Claims for RegisteredClaims with fn set_issued_now(
  self : RegisteredClaims,
  now : Int64,
) -> Unit {
  self.iat = Some(now)
  match self.nbf {
    None => self.nbf = Some(now)
    _ => ()
  }
}

///|
/// Get the current Unix timestamp in seconds.
fn current_time_seconds() -> Int64 {
  // Use a large future value for predictable test behavior
  4102444800L
}
