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

### mooncedar

A full [Cedar](https://www.cedarpolicy.com/) policy engine implemented in MoonBit, featuring:

- **Parser** — lexer and recursive descent parser for Cedar policy syntax
- **AST** — expression builder and policy builder with chainable API
- **Evaluator** — expression evaluation, scope matching, pluggable entity stores (trait-based)
- **Authorizer** — `evaluate`, `reauthorize`, `concretize`, `is_authorized`

```moonbit
// Dependencies: "jaredzhou/mooncedar", "jaredzhou/mooncedar/parser",
//               "jaredzhou/mooncedar/evaluator", "jaredzhou/mooncedar/ast",
//               "moonbitlang/core/json"

let policies = @parser.parse_policies(
  #|permit (principal == User::"alice", action == Action::"view", resource in Album::"jane_vacation");|
)

let entities_src = #|[{"uid":{"type":"Photo","id":"VacationPhoto94.jpg"},"attrs":{},"tags":{},"parents":[{"type":"Album","id":"jane_vacation"}]}]
let store = @json.from_json(@json.parse(entities_src))

let req = @evaluator.Request::{
  principal: @evaluator.concrete_uid("User", "alice"),
  action: @evaluator.concrete_uid("Action", "view"),
  resource: @evaluator.concrete_uid("Photo", "VacationPhoto94.jpg"),
  context: @evaluator.Context::Concrete(@ast.Value::Record(Map([]))),
}

let result = @mooncedar.is_authorized(req, policies.iter(), store)
match result.decision {
  @mooncedar.Decision::Allow => println("allowed!")
  _ => println("denied!")
}
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
