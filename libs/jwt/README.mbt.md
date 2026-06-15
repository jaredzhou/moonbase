# jwt

A JWT (JSON Web Token) library for MoonBit, providing HMAC-SHA256 signing, claims validation, and an extensible algorithm interface.

## Usage

### Sign a token

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.new_hmac_sha256(key)
let claims = Json::object({})
let token = @jwt.Token::Token(method, claims)
let jwt_string = @jwt.signed_string(token)
test {
  let parts_iter = jwt_string.split(".")
  let parts: Array[String] = []
  for p in parts_iter {
    parts.push(p.to_string())
  }
  assert_eq(parts.length(), 3)
}
```

### Parse and verify a token

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.new_hmac_sha256(key)
let claims = Json::object({})
let token = @jwt.Token::Token(method, claims)
let jwt_string = @jwt.signed_string(token)

let parser = @jwt.Parser::Parser()
  .register(@jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"))
let registered_claims = @jwt.RegisteredClaims::RegisteredClaims()
let parsed = try parser.parse(jwt_string, registered_claims) catch {
  _ => panic!("parse failed")
}
test {
  assert_eq(parsed.valid, true)
}
```

### Parse with RegisteredClaims

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.new_hmac_sha256(key)
let claims_json = @json.parse("{\"sub\":\"user-42\",\"iss\":\"my-app\"}").unwrap()
let token = @jwt.Token::Token(method, claims_json)
let jwt_string = @jwt.signed_string(token)

let parser = @jwt.Parser::Parser()
  .register(@jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"))
let claims = @jwt.RegisteredClaims::RegisteredClaims()
let _ = try parser.parse(jwt_string, claims) catch {
  _ => panic!("parse failed")
}
test {
  assert_eq(claims.subject, Some("user-42"))
  assert_eq(claims.issuer, Some("my-app"))
}
```

### Parse unverified (no signature check)

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.new_hmac_sha256(key)
let claims = Json::object({})
let token = @jwt.Token::Token(method, claims)
let jwt_string = @jwt.signed_string(token)
let parsed = @jwt.parse_unverified(jwt_string)
test {
  match parsed.header.get("alg") {
    Some(Json::String(alg)) => assert_eq(alg, "HS256")
    _ => panic!("missing alg")
  }
  assert_eq(parsed.valid, false)
}
```

## API Reference

### Token

- `Token::Token(method, claims)` -- Create a new token
- `signed_string(token)` -- Sign and produce the compact JWT string
- `parse_unverified(token_string)` -- Parse without signature verification

### Parser

- `Parser::Parser()` -- Create a new parser
- `Parser::register(method)` -- Register a signing method for verification
- `Parser::with_leeway(seconds)` -- Set clock skew tolerance
- `Parser::without_claims_validation()` -- Skip exp/nbf checks
- `Parser::parse(token_string, claims)` -- Parse and validate a token

### RegisteredClaims

- `RegisteredClaims::RegisteredClaims()` -- Empty claims
- Fields: `issuer`, `subject`, `audience`, `expires_at`, `not_before`, `issued_at`, `id`

### Signing Methods

- `new_hmac_sha256(key)` -- Create an HS256 signing method with the given key
