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
  claims.iss = Some("test-issuer")
  claims.sub = Some("user-123")
  claims.exp = Some(2000000000L)
  claims.iat = Some(1000000000L)
  claims.jti = Some("jti-001")

  let json = claims.to_json()
  let parsed : RegisteredClaims = @json.from_json(json)
  match parsed.iss { Some(s) => assert_eq(s, "test-issuer"); None => abort("expected Some") }
  match parsed.sub { Some(s) => assert_eq(s, "user-123"); None => abort("expected Some") }
  match parsed.exp { Some(e) => assert_eq(e, 2000000000L); None => abort("expected Some") }
  match parsed.iat { Some(i) => assert_eq(i, 1000000000L); None => abort("expected Some") }
  match parsed.jti { Some(j) => assert_eq(j, "jti-001"); None => abort("expected Some") }
}

///|
test "registered claims from_json empty" {
  let json = Json::object({})
  let parsed : RegisteredClaims = @json.from_json(json)
  match parsed.iss { None => (); Some(_) => abort("expected None") }
  match parsed.sub { None => (); Some(_) => abort("expected None") }
  match parsed.exp { None => (); Some(_) => abort("expected None") }
}

///|
test "registered claims aud array" {
  let obj : Map[String, Json] = {}
  let aud_arr : Array[Json] = [Json::string("aud1"), Json::string("aud2")]
  obj["aud"] = Json::array(aud_arr)
  let json = Json::object(obj)
  let parsed : RegisteredClaims = @json.from_json(json)
  match parsed.aud {
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
  claims.exp = Some(1000000L)
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
  claims.nbf = Some(9000000000000L)
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
