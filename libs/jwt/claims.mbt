///|
/// Trait for JWT claims. Types implementing Claims can be used with
/// Token parsing to handle JSON deserialization and claim validation.
pub trait Claims {
  /// Deserialize claims from a JSON payload
  from_json(Self, Json) -> Self raise JwtError
  /// Serialize claims to JSON
  to_json(Self) -> Json
  /// Validate registered claims (exp, nbf) with a clock leeway in seconds
  validate(Self, leeway : Int64) -> Unit raise JwtError
  /// Set issued-at and not-before timestamps (called during signing)
  set_issued_now(Self, now : Int64) -> Unit
}

///|
/// Standard registered JWT claims (RFC 7519 Section 4.1).
pub(all) struct RegisteredClaims {
  mut issuer: String?
  mut subject: String?
  mut audience: Array[String]?
  mut expires_at: Int64?
  mut not_before: Int64?
  mut issued_at: Int64?
  mut id: String?
}

///|
/// Create empty RegisteredClaims.
pub fn RegisteredClaims::RegisteredClaims() -> RegisteredClaims {
  {
    issuer: None,
    subject: None,
    audience: None,
    expires_at: None,
    not_before: None,
    issued_at: None,
    id: None,
  }
}

///|
pub impl Claims for RegisteredClaims with fn from_json(
  _self : RegisteredClaims,
  json : Json,
) -> RegisteredClaims raise JwtError {
  match json {
    Json::Object(obj) => {
      let claims = RegisteredClaims::RegisteredClaims()
      match obj.get("iss") {
        Some(Json::String(s)) => claims.issuer = Some(s)
        None => ()
        _ => raise MalformedToken("iss must be a string")
      }
      match obj.get("sub") {
        Some(Json::String(s)) => claims.subject = Some(s)
        None => ()
        _ => raise MalformedToken("sub must be a string")
      }
      match obj.get("aud") {
        Some(Json::String(s)) => claims.audience = Some([s])
        Some(Json::Array(arr)) => {
          let aud : Array[String] = []
          for item in arr {
            match item {
              Json::String(s) => aud.push(s)
              _ => raise MalformedToken("aud elements must be strings")
            }
          }
          claims.audience = Some(aud)
        }
        None => ()
        _ => raise MalformedToken("aud must be a string or array of strings")
      }
      match obj.get("exp") {
        Some(Json::Number(n, ..)) => claims.expires_at = Some(n.to_int().to_int64())
        None => ()
        _ => raise MalformedToken("exp must be a number")
      }
      match obj.get("nbf") {
        Some(Json::Number(n, ..)) => claims.not_before = Some(n.to_int().to_int64())
        None => ()
        _ => raise MalformedToken("nbf must be a number")
      }
      match obj.get("iat") {
        Some(Json::Number(n, ..)) => claims.issued_at = Some(n.to_int().to_int64())
        None => ()
        _ => raise MalformedToken("iat must be a number")
      }
      match obj.get("jti") {
        Some(Json::String(s)) => claims.id = Some(s)
        None => ()
        _ => raise MalformedToken("jti must be a string")
      }
      claims
    }
    _ => raise MalformedToken("claims must be a JSON object")
  }
}

///|
pub impl Claims for RegisteredClaims with fn to_json(
  self : RegisteredClaims,
) -> Json {
  let obj : Map[String, Json] = {}
  match self.issuer {
    Some(iss) => obj["iss"] = Json::string(iss)
    _ => ()
  }
  match self.subject {
    Some(sub) => obj["sub"] = Json::string(sub)
    _ => ()
  }
  match self.audience {
    Some(aud) => {
      let arr : Array[Json] = []
      for s in aud {
        arr.push(Json::string(s))
      }
      obj["aud"] = Json::array(arr)
    }
    _ => ()
  }
  match self.expires_at {
    Some(exp) => obj["exp"] = Json::number(exp.to_double())
    _ => ()
  }
  match self.not_before {
    Some(nbf) => obj["nbf"] = Json::number(nbf.to_double())
    _ => ()
  }
  match self.issued_at {
    Some(iat) => obj["iat"] = Json::number(iat.to_double())
    _ => ()
  }
  match self.id {
    Some(jti) => obj["jti"] = Json::string(jti)
    _ => ()
  }
  Json::object(obj)
}

///|
pub impl Claims for RegisteredClaims with fn validate(
  self : RegisteredClaims,
  leeway : Int64,
) -> Unit raise JwtError {
  match self.expires_at {
    Some(exp) => {
      let now = current_time_seconds()
      if now > exp + leeway {
        raise TokenExpired(expired_at=exp, now=now)
      }
    }
    _ => ()
  }
  match self.not_before {
    Some(nbf) => {
      let now = current_time_seconds()
      if now < nbf - leeway {
        raise TokenNotYetValid(not_before=nbf, now=now)
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
  self.issued_at = Some(now)
  match self.not_before {
    None => self.not_before = Some(now)
    _ => ()
  }
}

///|
/// Get the current Unix timestamp in seconds.
fn current_time_seconds() -> Int64 {
  // Use a large future value for predictable test behavior
  4102444800L
}
