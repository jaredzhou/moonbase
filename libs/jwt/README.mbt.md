# jwt

A JWT (JSON Web Token) library for MoonBit, providing HMAC-SHA256 signing, claims validation, and an extensible algorithm interface.

## Usage

### Sign a token

```mbt check
///|
test {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(sig_method, claims)
  let jwt_string = @jwt.signed_string(token)
  let parts_iter = jwt_string.split(".")
  let parts : Array[String] = []
  for p in parts_iter {
    parts.push(p.to_owned())
  }
  assert_eq(parts.length(), 3)
}
```

### Parse and verify a token

```mbt check
///|
test {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(sig_method, claims)
  let jwt_string = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser().register(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
  )
  let (parsed, _) : (@jwt.Token, @jwt.RegisteredClaims) = parser.parse(
    jwt_string,
  ) catch {
    _ => panic()
  }
  assert_eq(parsed.valid, true)
}
```

### Parse with RegisteredClaims

```mbt check
///|
test {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let claims_json = @json.parse("{\"sub\":\"user-42\",\"iss\":\"my-app\"}") catch {
    _ => panic()
  }
  let token = @jwt.Token::Token(sig_method, claims_json)
  let jwt_string = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser().register(
    @jwt.new_hmac_sha256(b"my-secret-key-for-testing-32b"),
  )
  let (_, populated) : (@jwt.Token, @jwt.RegisteredClaims) = parser.parse(
    jwt_string,
  ) catch {
    _ => panic()
  }
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

### Quick parse with a secret key

```mbt check
///|
test {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let token = @jwt.Token::Token(sig_method, Json::object({}))
  let jwt_string = @jwt.signed_string(token)

  let (parsed, claims) = @jwt.parse(
    jwt_string,
    b"my-secret-key-for-testing-32b",
    @jwt.RegisteredClaims::RegisteredClaims(),
  )
  assert_eq(parsed.valid, true)
}
```

### Parse unverified (no signature check)

```mbt check
///|
test {
  let key = b"my-secret-key-for-testing-32b"
  let sig_method = @jwt.new_hmac_sha256(key)
  let claims = Json::object({})
  let token = @jwt.Token::Token(sig_method, claims)
  let jwt_string = @jwt.signed_string(token)
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
- `signed_string(token)` — Sign and produce the compact JWT string
- `parse(token_string, key, claims)` — Parse and verify with HS256, populate claims
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
