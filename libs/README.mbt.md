# jaredzhou/libs

Shared libraries for MoonBit — URL parsing and JWT creation/verification.

## Installation

Add to your `moon.mod`:

```json
{ "deps": { "jaredzhou/libs": "0.1.0" } }
```

## Packages

### `jaredzhou/libs/url`

A complete RFC 3986 URL parsing package, modeled after Go's `net/url`.

```moonbit nocheck
let u = @url.parse("https://user:pwd@example.com:8080/path?q=v#frag")?
assert_eq!(u.scheme?, "https")
assert_eq!(u.user_info?.username, "user")
assert_eq!(u.host?, "example.com:8080")
assert_eq!(u.path?, "/path")
assert_eq!(u.query?, "q=v")
assert_eq!(u.fragment?, "frag")
```

**Features:**
- Full RFC 3986 URL parsing (`parse`, `parse_request_uri`)
- URL component extraction (scheme, userinfo, host, path, query, fragment)
- Percent-encoding/decoding for queries and path segments (`query_escape`, `query_unescape`, `path_segment_escape`, `path_segment_unescape`)
- `URL.to_string()` serialization
- `UserInfo` type with username and optional password

### `jaredzhou/libs/jwt`

JWT creation, signing, parsing, and verification.

```moonbit nocheck
// Create a secret key
let secret = b"my-secret-key".to_bytes()
let method = new_hmac_sha256(secret)

// Create and sign a token
let claims = Map::of([("sub", @json.Json::String("user-123"))])
let token_str = sign(method, @json.Json::Object(claims))

// Parse and verify
let parser = Parser::Parser()
  .register(method)
  .with_leeway(30)
let (token, reg_claims) = parser.parse(token_str)
assert_eq!(reg_claims.sub?, "user-123")
```

**Features:**
- HMAC-SHA256 signing (`HS256` algorithm)
- Token creation (`sign`, `signed_string`)
- Token parsing with or without verification (`parse_unverified`, `parse`, `parse_with`)
- Configurable `Parser` with leeway and claims validation skipping
- `RegisteredClaims` with standard RFC 7519 fields (`iss`, `sub`, `aud`, `exp`, `nbf`, `iat`, `jti`)
- Extensible `Claims` trait for custom claim types

## License

Apache-2.0
