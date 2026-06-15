///|
test "build_header produces correct structure" {
  let header = build_header("HS256")
  match header.get("alg") {
    Some(Json::String(alg)) => assert_eq(alg, "HS256")
    _ => ()
  }
  match header.get("typ") {
    Some(Json::String(typ)) => assert_eq(typ, "JWT")
    _ => ()
  }
}

///|
test "registered claims to_json round trip" {
  let claims = RegisteredClaims::RegisteredClaims()
  claims.issuer = Some("test-issuer")
  claims.subject = Some("user-123")
  claims.expires_at = Some(2000000000L)
  claims.issued_at = Some(1000000000L)
  claims.id = Some("jti-001")

  let json = claims.to_json()
  let parsed = claims.from_json(json)
  assert_eq(parsed.issuer, Some("test-issuer"))
  assert_eq(parsed.subject, Some("user-123"))
  assert_eq(parsed.expires_at, Some(2000000000L))
  assert_eq(parsed.issued_at, Some(1000000000L))
  assert_eq(parsed.id, Some("jti-001"))
}

///|
test "registered claims from_json empty" {
  let claims = RegisteredClaims::RegisteredClaims()
  let json = Json::object({})
  let parsed = claims.from_json(json)
  assert_eq(parsed.issuer, None)
  assert_eq(parsed.subject, None)
  assert_eq(parsed.expires_at, None)
}

///|
test "registered claims aud string" {
  let claims = RegisteredClaims::RegisteredClaims()
  let obj : Map[String, Json] = {}
  obj["aud"] = Json::string("my-audience")
  let json = Json::object(obj)
  let parsed = claims.from_json(json)
  match parsed.audience {
    Some(aud) => {
      assert_eq(aud.length(), 1)
      assert_eq(aud[0], "my-audience")
    }
    _ => inspect("unexpected", content="aud should be present")
  }
}

///|
test "registered claims aud array" {
  let claims = RegisteredClaims::RegisteredClaims()
  let obj : Map[String, Json] = {}
  let aud_arr : Array[Json] = [Json::string("aud1"), Json::string("aud2")]
  obj["aud"] = Json::array(aud_arr)
  let json = Json::object(obj)
  let parsed = claims.from_json(json)
  match parsed.audience {
    Some(aud) => {
      assert_eq(aud.length(), 2)
      assert_eq(aud[0], "aud1")
      assert_eq(aud[1], "aud2")
    }
    _ => inspect("unexpected", content="aud should be present")
  }
}

///|
test "expired token validation" {
  let claims = RegisteredClaims::RegisteredClaims()
  claims.expires_at = Some(1000000L)
  let is_expired = try {
    claims.validate(0L)
    false
  } catch {
    _ => true
  }
  assert_eq(is_expired, true)
}

///|
test "not before validation" {
  let claims = RegisteredClaims::RegisteredClaims()
  claims.not_before = Some(9000000000000L)
  let is_invalid = try {
    claims.validate(0L)
    false
  } catch {
    _ => true
  }
  assert_eq(is_invalid, true)
}

///|
test "valid token passes validation" {
  let claims = RegisteredClaims::RegisteredClaims()
  let is_valid = try {
    claims.validate(0L)
    true
  } catch {
    _ => false
  }
  assert_eq(is_valid, true)
}

///|
test "signed string is deterministic for same input" {
  let key = b"deterministic-key-for-testing-x"
  let sig_method = HMACSHA256(key)
  let claims = Json::object({})
  let token1 = Token::Token(sig_method, claims)
  let token2 = Token::Token(sig_method, claims)
  let signed1 = signed_string(token1)
  let signed2 = signed_string(token2)
  assert_eq(signed1, signed2)
}
