# moonbase

A [MoonBit](https://www.moonbitlang.com/) workspace for building web applications and shared libraries.

## Modules

### libs

Shared libraries used across the workspace.

#### url

A complete RFC 3986 URL parsing package, modeled after Go's `net/url`. Provides URL parsing, component extraction, percent-encoding, and query string handling.

```moonbit
let u = @url.parse("https://user:pwd@example.com:8080/path?q=v#frag").unwrap()
assert_eq!(u.scheme?, "https")
assert_eq!(u.user_info?.username, "user")
assert_eq!(u.host?, "example.com:8080")
assert_eq!(u.path?, "/path")
assert_eq!(u.query?, "q=v")
assert_eq!(u.fragment?, "frag")
```

#### jwt

JWT creation, signing, parsing, and validation with HMAC-SHA256 (HS256). Supports registered claims (RFC 7519) and extensible custom claims.

```moonbit
let method = new_hmac_sha256(b"secret-key")
let claims = RegisteredClaims::new(subject="user123")
let token = Token::sign(method, claims)

let parser = Parser::new()
let (token, claims) = parser.parse("eyJhbG...", method)
assert_eq!(claims.subject?, "user123")
```

## Getting Started

```bash
# Clone the repo
git clone git@github.com:jaredzhou/moonbase.git
cd moonbase

# Run tests
moon test --all

# Check the workspace
moon check
```

## License

Apache 2.0 — see [LICENSE](LICENSE) for details.
