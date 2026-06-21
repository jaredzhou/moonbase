# jwt

A JWT (JSON Web Token) library for MoonBit, providing HMAC-SHA256 signing, claims validation, and an extensible algorithm interface.

## Usage

### Sign a token

```mbt check
///|
test {
  let jwt_string = @jwt.sign(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
    Json::object({}),
  )
  let parts_iter = jwt_string.split(".")
  let parts : Array[String] = []
  for p in parts_iter {
    parts.push(p.to_owned())
  }
  assert_eq(parts.length(), 3)
}
```

### Quick parse and verify

```mbt check
///|
test {
  let jwt_string = @jwt.sign(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
    Json::object({}),
  )
  let (parsed, _) : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse(
    jwt_string,
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
  )
  assert_eq(parsed.valid, true)
}
```

### Parse with RegisteredClaims

```mbt check
///|
test {
  let jwt_string = @jwt.sign(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
    @json.parse("{\"sub\":\"user-42\",\"iss\":\"my-app\"}") catch {
      _ => panic()
    },
  )
  let (_, populated) : (@jwt.Token, @jwt.RegisteredClaims) = @jwt.parse(
    jwt_string,
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
  )
  match populated.sub {
    Some(s) => assert_eq(s, "user-42")
    _ => panic()
  }
  match populated.iss {
    Some(s) => assert_eq(s, "my-app")
    _ => panic()
  }
}
```

### Parse unverified (no signature check)

```mbt check
///|
test {
  let jwt_string = @jwt.sign(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
    Json::object({}),
  )
  let parsed = @jwt.parse_unverified(jwt_string)
  match parsed.header.get("alg") {
    Some(Json::String(alg)) => assert_eq(alg, "HS256")
    _ => panic()
  }
  assert_eq(parsed.valid, false)
}
```

## API Reference

### Token

- `Token::Token(sig_method, claims)` — Create a new token
- `sign(sig_method, claims)` — Sign and produce the compact JWT string
- `parse(token_string, sig_method)` — Parse and verify with given signing method
- `parse_unverified(token_string)` — Parse without signature verification

### Parser

- `Parser::Parser()` — Create a new parser
- `Parser::register(sig_method)` — Register a signing method for verification
- `Parser::with_leeway(seconds)` — Set clock skew tolerance
- `Parser::without_claims_validation()` — Skip exp/nbf checks
- `Parser::parse(token_string, claims)` — Parse and validate a token

### RegisteredClaims

- `RegisteredClaims::RegisteredClaims()` — Empty claims
- Fields: `issuer`, `subject`, `audience`, `expires_at`, `not_before`, `issued_at`, `id`

### Signing Methods

- `new_hmac_sha256(key)` — Create an HS256 signing method with the given key
