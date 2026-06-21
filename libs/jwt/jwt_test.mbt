///|
test "sign and parse round trip" {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let signed = @jwt.sign(sig_method, Json::object({}))
  let parts_iter = signed.split(".")
  let parts : Array[String] = []
  for p in parts_iter {
    parts.push(p.to_owned())
  }
  assert_eq(parts.length(), 3)
  assert_eq(parts[0].length() > 0, true)
  assert_eq(parts[1].length() > 0, true)
  assert_eq(parts[2].length() > 0, true)
}

///|
test "signed_string via Token" {
  let key = b"my-secret-key-for-testing-32b"
  let token = @jwt.Token::Token(@jwt.new_hmac_sha256(key), Json::object({}))
  let signed = @jwt.signed_string(token)
  let parts_iter = signed.split(".")
  let parts : Array[String] = []
  for p in parts_iter {
    parts.push(p.to_owned())
  }
  assert_eq(parts.length(), 3)
}

///|
test "parse unverified" {
  let signed = @jwt.sign(
    @jwt.new_hmac_sha256(b"key-for-unverified-test-32bytes"),
    Json::object({}),
  )
  let parsed = @jwt.parse_unverified(signed)
  match parsed.header.get("alg") {
    Some(Json::String(alg)) => assert_eq(alg, "HS256")
    _ => ()
  }
  match parsed.header.get("typ") {
    Some(Json::String(typ)) => assert_eq(typ, "JWT")
    _ => ()
  }
  assert_eq(parsed.valid, false)
}

///|
test "parse convenience single method" {
  let key = b"secure-secret-key-for-parse-test"
  let signed = @jwt.sign(@jwt.new_hmac_sha256(key), Json::object({}))
  let (parsed, _) : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse(
    signed,
    @jwt.new_hmac_sha256(key),
  )
  assert_eq(parsed.valid, true)
}

///|
test "parse with wrong key fails" {
  let sign_key = b"correct-key-that-is-32-bytes-l"
  let verify_key = b"wrong-key-that-is-also-32-byte"
  let signed = @jwt.sign(@jwt.new_hmac_sha256(sign_key), Json::object({}))
  let _ : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse(
    signed,
    @jwt.new_hmac_sha256(verify_key),
  ) catch {
    _ => return
  }
  assert_eq(true, false)
}

///|
test "parse_with multiple methods" {
  let key_a = b"key-a-for-multi-method-testing"
  let key_b = b"key-b-for-multi-method-testing"
  let signed = @jwt.sign(@jwt.new_hmac_sha256(key_a), Json::object({}))
  let (parsed, _) : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse_with(
    signed,
    [@jwt.new_hmac_sha256(key_b), @jwt.new_hmac_sha256(key_a)],
  )
  assert_eq(parsed.valid, true)
}

///|
test "parse_with no matching method fails" {
  let signed = @jwt.sign(
    @jwt.new_hmac_sha256(b"correct-key-for-no-match"),
    Json::object({}),
  )
  let _ : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse_with(signed, [
    @jwt.new_hmac_sha256(b"wrong-key-only"),
  ]) catch {
    _ => return
  }
  assert_eq(true, false)
}

///|
test "parse malformed token" {
  let parser = @jwt.Parser::Parser().register(@jwt.new_hmac_sha256(b"key"))
  let _ : (@jwt.Token, @jwt.RegisteredClaims) = parser.parse("not-a-jwt") catch {
    _ => return
  }
  assert_eq(true, false)
}

///|
test "parse with invalid base64 header" {
  let parser = @jwt.Parser::Parser().register(@jwt.new_hmac_sha256(b"key"))
  let _ : (@jwt.Token, @jwt.RegisteredClaims) = parser.parse(
    "not!valid@base64.x.y",
  ) catch {
    _ => return
  }
  assert_eq(true, false)
}
