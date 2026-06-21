# moonbase

A [MoonBit](https://www.moonbitlang.com/) workspace for building web applications and shared libraries.

## Modules

### pony

A web framework inspired by Go's [Chi](https://github.com/go-chi/chi), featuring:

- **Radix tree router** — static, parameter, and wildcard routing with priority matching
- **Middleware chaining** — composable middleware with CORS, JWT auth, and request logging built-in
- **Type-safe context** — phantom-type extensions for request-scoped values (request ID, user ID)
- **HTTP helpers** — header management, status codes, JSON/redirect/error responses

```moonbit
fn main {
  let r = Router::Router()

  // GET /ping => 200 "pong"
  r.add(HttpMethod::Get, "/ping", ctx => ctx.write_text(status_ok, "pong"))

  // GET /users/42  => 200 "user: 42"
  r.add(HttpMethod::Get, "/users/{id}", ctx => {
    let id = ctx.param("id").unwrap_or("")
    ctx.write_text(status_ok, "user: \(id)")
  })

  // GET /search?q=pony  => 200 "searching: pony"
  r.add(HttpMethod::Get, "/search", ctx => {
    let q = ctx.query("q").unwrap_or("")
    ctx.write_text(status_ok, "searching: \(q)")
  })

  // GET /api/status  => 200 {"status":"ok","version":"0.1.0"}
  r.add(HttpMethod::Get, "/api/status", ctx => {
    ctx.response_ok(({ "status": "ok", "version": "0.1.0" } : Json))
  })

  // POST /api/items  => 400 {"code":3,"message":"name is required"}
  r.add(HttpMethod::Post, "/api/items", ctx => {
    ctx.response_error(invalid_argument, "name is required")
  })

  // GET /static/css/app.css  => 200 "file: css/app.css"
  r.add(HttpMethod::Get, "/static/*", ctx => {
    let path = ctx.wildcard().unwrap_or("")
    ctx.write_text(status_ok, "file: \(path)")
  })

  start("127.0.0.1:3000", r)
}
```

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

### todo (TinyTodo)

A demo application showcasing Cedar policy-based authorization in a multi-user todo app. Built with `pony` for HTTP routing and `mooncedar` for policy evaluation.

- **Authorization model** — role-based (Owner, Editor, Reader) with Cedar policies
- **REST API** — CRUD for lists and tasks, share/unshare lists
- **CLI client** — interactive command-line client

```bash
# Start the server
moon run main

# Use the CLI client
moon run ./todo/client emina list
moon run ./todo/client emina new "groceries"
moon run ./todo/client emina share groceries aaron Editor
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
