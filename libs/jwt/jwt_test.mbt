///|
test "round trip hs256" {
  let key = b"my-secret-key-for-testing-32b"
  let method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(method, claims)
  let signed = @jwt.signed_string(token)
  let parts_iter = signed.split(".")
  let parts: Array[String] = []
  for p in parts_iter {
    parts.push(p.to_string())
  }
  assert_eq(parts.length(), 3)
  assert_eq(parts[0].length() > 0, true)
  assert_eq(parts[1].length() > 0, true)
  assert_eq(parts[2].length() > 0, true)
}

///|
test "parse unverified" {
  let key = b"key-for-unverified-test-32bytes"
  let method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(method, claims)
  let signed = @jwt.signed_string(token)
  let parsed = @jwt.parse_unverified(signed)
  let header = parsed.header
  match header.get("alg") {
    Some(Json::String(alg)) => assert_eq(alg, "HS256")
    _ => ()
  }
  match header.get("typ") {
    Some(Json::String(typ)) => assert_eq(typ, "JWT")
    _ => ()
  }
  assert_eq(parsed.valid, false)
}

///|
test "parse and verify hs256" {
  let key = b"secure-secret-key-for-parse-test"
  let method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(method, claims)
  let signed = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser()
    .register(@jwt.new_hmac_sha256(key))
  let registered_claims = @jwt.RegisteredClaims::RegisteredClaims()
  try parser.parse(signed, registered_claims) catch {
    _ => abort("parse should not fail")
  } noraise {
    parsed => assert_eq(parsed.valid, true)
  }
}

///|
test "parse with wrong key fails" {
  let sign_key = b"correct-key-that-is-32-bytes-l"
  let verify_key = b"wrong-key-that-is-also-32-byte"
  let method = @jwt.new_hmac_sha256(sign_key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(method, claims)
  let signed = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser()
    .register(@jwt.new_hmac_sha256(verify_key))
  let registered_claims = @jwt.RegisteredClaims::RegisteredClaims()
  try parser.parse(signed, registered_claims) catch {
    _ => ()
  } noraise {
    _ => assert_eq(true, false)
  }
}

///|
test "parse malformed token" {
  let parser = @jwt.Parser::Parser()
    .register(@jwt.new_hmac_sha256(b"key"))
  let registered_claims = @jwt.RegisteredClaims::RegisteredClaims()
  try parser.parse("not-a-jwt", registered_claims) catch {
    _ => ()
  } noraise {
    _ => assert_eq(true, false)
  }
}

///|
test "parse with invalid base64 header" {
  let parser = @jwt.Parser::Parser()
    .register(@jwt.new_hmac_sha256(b"key"))
  let registered_claims = @jwt.RegisteredClaims::RegisteredClaims()
  try parser.parse("not!valid@base64.x.y", registered_claims) catch {
    _ => ()
  } noraise {
    _ => assert_eq(true, false)
  }
}
