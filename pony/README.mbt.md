# jaredzhou/pony

A lightweight HTTP web framework for MoonBit, inspired by Go's [Chi](https://github.com/go-chi/chi).

## Installation

Add to your `moon.mod`:

```json
{ "deps": { "jaredzhou/pony": "0.1.0" } }
```

## Quick Start

```moonbit nocheck
///|
fn main {
  let r = Router::Router()

  // GET /ping => 200 "pong"
  r.add(HttpMethod::Get, "/ping", fn(ctx) { ctx.write_text(status_ok, "pong") })

  // GET /users/{id}  => 200 "user: 42"
  r.add(HttpMethod::Get, "/users/{id}", fn(ctx) {
    let id = ctx.param("id").or("")
    ctx.write_text(status_ok, "user: \(id)")
  })

  // GET /search?q=pony  => 200 "searching: pony"
  r.add(HttpMethod::Get, "/search", fn(ctx) {
    let q = ctx.query("q").or("")
    ctx.write_text(status_ok, "searching: \(q)")
  })

  // GET /api/status  => 200 {"status":"ok"}
  r.add(HttpMethod::Get, "/api/status", fn(ctx) {
    ctx.reply_ok({ "status": "ok" })
  })

  // POST /api/items  => 400 {"code":3,"message":"name is required"}
  r.add(HttpMethod::Post, "/api/items", fn(ctx) {
    ctx.reply_error(invalid_argument, "name is required")
  })

  // GET /static/css/app.css  => 200 "file: css/app.css"
  r.add(HttpMethod::Get, "/static/*", fn(ctx) {
    let path = ctx.wildcard().or("")
    ctx.write_text(status_ok, "file: \(path)")
  })

  start("127.0.0.1:3000", r)
}
```

## Features

### Router

- **Radix tree** with priority matching for static, parameter, and wildcard routes
- `{param}` path parameters and `*` wildcard capture
- Route-specific middleware per endpoint
- Sub-router mounting with `mount()`
- Custom 404 and 405 handlers

### Middleware

Built-in via `jaredzhou/pony/mw`:

```moonbit nocheck
r.use_mw(@mw.logger())
r.use_mw(@mw.cors(
  allow_origins=["*"],
  allow_methods=["GET", "POST"],
))
r.use_mw(@mw.jwt(new_hmac_sha256(secret)))
```

| Middleware | Description |
|-----------|-------------|
| `logger()` | Request logging (method, path, status, duration) |
| `cors()` | CORS headers with configurable origins, methods, headers, max-age |
| `jwt(signing_method)` | JWT bearer token auth, stores `sub` claim in context |

### Request Context (`Context`)

```moonbit nocheck
let id = ctx.param("id")           // path parameter
let q = ctx.query("search")        // query string
let header = ctx.header("Accept")  // request header
let body = ctx.json()?             // auto-deserialize JSON body
let form = ctx.form("name")?       // form values (application/x-www-form-urlencoded)

ctx.set_content_type("application/json")
ctx.write_text(200, "Hello")
ctx.write_json(200, {"key": "value"})
ctx.reply_ok({"status": "ok"})   // 200 JSON
ctx.reply_error(400, "bad input") // error JSON
ctx.redirect("/login")              // 302 redirect
ctx.no_content()                    // 204
```

### Extension Store

Type-safe key-value store for request-scoped data:

```moonbit nocheck
ctx.set_ext(@pony.RequestId{}, "req-abc")
ctx.set_ext(@pony.UserId{}, "user-42")

let uid = ctx.get_ext(@pony.UserId{})
```

### Header

Full HTTP header management with canonical keys and multi-value support:

```moonbit nocheck
let h = @pony.new()
h.set("Content-Type", "application/json")
h.add("Set-Cookie", "session=abc")
let ct = h.get("Content-Type")  // "application/json"
```

### Server

```moonbit nocheck
let server = @pony.Server::new("127.0.0.1:3000", router)
  .with_timeout(read=5000, write=10000)
server.start()!
```

## License

Apache-2.0
