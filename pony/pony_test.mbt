///|
/// Combined test: tree structure, middleware, HTTP integration,
/// not-found, method-not-allowed, and mount.
async test "test_pony" {
  // --- middleware ---
  let mut count = 0
  let _counter : Middleware = next => {
    ctx => {
      count = count + 1
      next(ctx)
    }
  }
  let logbuf = StringBuilder::new()
  let logmsg = "logmw test"
  let _logmw : Middleware = next => {
    ctx => {
      logbuf.write_string(logmsg)
      next(ctx)
    }
  }

  // --- handlers ---
  let ping : Handler = ctx => ctx.write_text(200, "pong")
  let ping_all : Handler = ctx => ctx.write_text(200, "pong all")
  let ping_all2 : Handler = ctx => ctx.write_text(200, "pong all 2")
  let ping_one : Handler = ctx => {
    let id = ctx.param("id").unwrap_or("")
    ctx.write_text(200, "pong " + id)
  }
  let ping_woop : Handler = ctx => {
    let id = ctx.param("iidd").unwrap_or("")
    ctx.write_text(200, "pong woop " + id)
  }
  let catch_all : Handler = ctx => ctx.write_text(200, "caughtall")
  let echo_query : Handler = ctx => {
    let name = ctx.query("name").unwrap_or("none")
    ctx.write_text(200, "hello " + name)
  }
  let login : Handler = async fn(ctx) {
    let user = ctx.form("user").unwrap_or("")
    ctx.write_text(200, "welcome " + user)
  }

  // --- custom not-found & method-not-allowed ---
  let custom_not_found : Handler = ctx => ctx.write_text(404, "custom 404")
  let custom_not_allowed : Handler = ctx => ctx.write_text(405, "custom 405")

  // --- sub-router for mount ---
  let sub = Router::Router()
  sub.add(
    HttpMethod::Get,
    "/hi",
    ctx => ctx.write_text(200, "hello from sub"),
    name="sub_hi",
  )

  // --- router ---
  let r = Router::Router()
  r.add(HttpMethod::Get, "/echo", echo_query, name="echo")
  r.add(HttpMethod::Post, "/login", login, name="login")
  r.add(HttpMethod::Get, "/ping", ping, name="ping")
  r.add(HttpMethod::Get, "/pingall", ping_all, name="pingAll")
  r.add(HttpMethod::Get, "/ping/all", ping_all, name="pingAllAlias")
  r.add(HttpMethod::Get, "/ping/all2", ping_all2, name="pingAll2")
  r.add(HttpMethod::Get, "/ping/{id}", ping_one, name="pingOne")
  r.add(HttpMethod::Get, "/ping/{iidd}/woop", ping_woop, name="pingWoop2")
  r.any("/admin/*", catch_all, name="catchAll")
  r.mount("/api", sub)
  r.set_not_found(custom_not_found)
  r.set_method_not_allowed(custom_not_allowed)

  // --- tree structure ---
  inspect(
    r,
    content=(
      #|Static()
      #|    └── Static(/)
      #|        ├── Static(echo) Get(/echo)
      #|        ├── Static(login) Post(/login)
      #|        ├── Static(ping) Get(/ping)
      #|        │   ├── Static(all) Get(/pingall)
      #|        │   └── Static(/)
      #|        │       ├── Static(all) Get(/ping/all)
      #|        │       │   └── Static(2) Get(/ping/all2)
      #|        │       p── Param(id,/) Get(/ping/{id})
      #|        │           └── Static(/woop) Get(/ping/{iidd}/woop)
      #|        └── Static(a)
      #|            ├── Static(dmin/)
      #|            │   w── * Any(/admin/*)
      #|            └── Static(pi/)
      #|                w── * Any(/api/*)
      #|
    ),
  )

  // --- middleware verification ---
  inspect(logbuf.to_string(), content="")

  // --- HTTP integration ---
  @async.with_task_group() <| group => {
    let port = 19876
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    let (resp, body) = @http.get(base + "/ping")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong")

    let (resp, body) = @http.get(base + "/pingall")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong all")

    let (resp, body) = @http.get(base + "/ping/42")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "pong 42")

    let (resp, body) = @http.get(base + "/admin/anything/here")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "caughtall")

    // not found
    let (resp, body) = @http.get(base + "/nope")
    assert_eq(resp.code, 404)
    assert_eq(body.text(), "custom 404")

    // method not allowed — path exists but wrong method
    let (resp, body) = @http.post(base + "/ping", b"")
    assert_eq(resp.code, 405)
    assert_eq(body.text(), "custom 405")

    // mounted sub-router
    let (resp, body) = @http.get(base + "/api/hi")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hello from sub")

    // query parameter
    let (resp, body) = @http.get(base + "/echo?name=moonbit")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hello moonbit")

    // POST form data
    let (resp, body) = @http.post(base + "/login", "user=pony&pass=1234")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "welcome pony")
  }
}

///|
/// query parameter: key with value, key without value, multi-value key.
async test "test_query" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/search",
    ctx => {
      let q = ctx.query("q").unwrap_or("")
      let page = ctx.query("page").unwrap_or("1")
      let tags = ctx.queries.get_all("tag")
      let has_flag = ctx.query("flag") is Some(_)
      let flag_val = ctx.query("flag").unwrap_or("none")
      ctx.write_text(
        200,
        "q=\{"\{q}"} page=\{"\{page}"} has_flag=\{"\{has_flag}"} flag_val=\{"\{flag_val}"} tags=\{"\{tags}"}",
      )
    },
    name="search",
  )

  @async.with_task_group() <| group => {
    let port = 19877
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // key with value, no flag
    let (resp, body) = @http.get(base + "/search?q=pony")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q=pony page=1 has_flag=false flag_val=none tags=[]")

    // key without value (flag is present, value is empty string)
    let (resp, body) = @http.get(base + "/search?q=pony&flag")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q=pony page=1 has_flag=true flag_val= tags=[]")

    // same key multiple values
    let (resp, body) = @http.get(
      base + "/search?tag=web&tag=framework&tag=fast",
    )
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q= page=1 has_flag=false flag_val=none tags=[web, framework, fast]")

    // mixed: multi-value + key-without-value
    let (resp, body) = @http.get(base + "/search?tag=rust&flag&tag=go")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q= page=1 has_flag=true flag_val= tags=[rust, go]")

    // no query at all
    let (resp, body) = @http.get(base + "/search")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "q= page=1 has_flag=false flag_val=none tags=[]")
  }
}

///|
struct User {
  name : String
  age : Int
} derive(FromJson, ToJson, Eq)

///|
/// JSON body deserialization via ctx.json() with a custom struct.
async test "test_json" {
  let r = Router::Router()
  r.add(
    HttpMethod::Post,
    "/user",
    async fn(ctx) {
      let user : User = ctx.json() catch {
        _ => {
          ctx.write_text(400, "bad json")
          return
        }
      }
      ctx.write_text(200, "\{"\{user.name}"} is \{"\{user.age}"}")
    },
    name="create_user",
  )

  @async.with_task_group() <| group => {
    let port = 19878
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    let (resp, body) = @http.post(
      base + "/user",
      "{\"name\":\"alice\",\"age\":30}",
    )
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "alice is 30")
  }
}

///|
/// write_bytes, set_content_type, no_content, redirect.
async test "test_write" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/bytes",
    ctx => {
      ctx.set_content_type("application/octet-stream")
      ctx.write_bytes(200, b"\x00\x01\x02")
    },
    name="bytes",
  )
  r.add(
    HttpMethod::Post,
    "/done",
    ctx => ctx.no_content(),
    name="no_content",
  )
  r.add(
    HttpMethod::Get,
    "/go",
    ctx => ctx.redirect("/ping"),
    name="redirect",
  )

  @async.with_task_group() <| group => {
    let port = 19879
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // write_bytes + set_content_type
    let (resp, _body) = @http.get(base + "/bytes")
    assert_eq(resp.code, 200)
    assert_eq(resp.headers.get("content-type").unwrap_or(""), "application/octet-stream")

    // no_content
    let (resp, _) = @http.post(base + "/done", b"")
    assert_eq(resp.code, 204)

    // redirect
    let (resp, _) = @http.get(base + "/go")
    assert_eq(resp.code, 302)
    assert_eq(resp.headers.get("location").unwrap_or(""), "/ping")
  }
}

///|
/// Mount: sub-router with middleware, not-found, method-not-allowed.
async test "test_mount" {
  let sub = Router::Router()
  sub.add(HttpMethod::Get, "/hi", ctx => ctx.write_text(200, "hi"), name="hi")
  sub.add(
    HttpMethod::Post,
    "/create",
    ctx => ctx.write_text(201, "created"),
    name="create",
  )
  sub.set_not_found(ctx => ctx.write_text(404, "sub 404"))
  sub.set_method_not_allowed(ctx => ctx.write_text(405, "sub 405"))

  let r = Router::Router()
  r.mount("/v1", sub)

  @async.with_task_group() <| group => {
    let port = 19880
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      start("127.0.0.1:\{port}", r)
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)

    // mounted GET
    let (resp, body) = @http.get(base + "/v1/hi")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "hi")

    // not found inside sub
    let (resp, body) = @http.get(base + "/v1/nope")
    assert_eq(resp.code, 404)
    assert_eq(body.text(), "sub 404")

    // method not allowed inside sub
    let (resp, body) = @http.post(base + "/v1/hi", b"")
    assert_eq(resp.code, 405)
    assert_eq(body.text(), "sub 405")
  }
}

///|
/// JWT middleware: decode bearer token and set user_id in ext.
///|
/// JWT middleware: decode bearer token and set user_id in ext.
async test "test_jwt" {
  let r = Router::Router()
  r.use_mw(@mw.jwt())
  r.add(
    HttpMethod::Get,
    "/me",
    ctx => {
      let user : String = ctx.get_ext(@pony.UserId::{}) catch {
        _ => "anonymous"
      }
      ctx.write_text(200, "user=" + user)
    },
    name="me",
  )

  @async.with_task_group() <| group => {
    let port = 19882
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let server = @http.Server::Server(@socket.Addr::parse("127.0.0.1:\{port}"))
      server.run_forever((req, req_body, conn) => r.handle(req, req_body, conn))
    }
    let base = "http://127.0.0.1:\{port}"
    @async.sleep(500)


    let payload:Json = {"sub": "user-123"}
    let token = @jwt.sign(payload.stringify(), "secret")
    let (resp, body) = @http.get(
      base + "/me",
      headers={ "Authorization": "Bearer \{token}" },
    )
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "user=user-123")

    // no token
    let (resp, body) = @http.get(base + "/me")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "user=anonymous")

    // // no token
    // let (resp, body) = @http.get(base + "/me")
    // assert_eq(resp.code, 200)
    // assert_eq(body.text(), "anonymous")
  }
}

///|
/// Server: encapsulated router with request_id.
async test "test_server" {
  let r = Router::Router()
  r.add(
    HttpMethod::Get,
    "/hello",
    ctx => {
      let id = ctx.get_ext(@pony.RequestId::{}) catch { _ => "?" }
      ctx.write_text(200, "req=" + id)
    },
    name="hello",
  )

  let s = Server::Server("127.0.0.1:19881", r)

  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      s.start()
    }
    @async.sleep(500)

    let (resp, body) = @http.get("http://127.0.0.1:19881/hello")
    assert_eq(resp.code, 200)
    assert_eq(body.text(), "req=1")
  }
}

test "any test" {
  let user = @any.of("User-1")
  assert_eq(user.to(), "User-1")
}

///|
test "ext_store" {
  let s = ExtStore::new()
  s.set(RequestId::{}, "REQ-42")
  s.set(UserId::{}, "USER-99")

  let req_id : String = s.get(RequestId::{}) catch { _ => "?" }
  let user_id : String = s.get(UserId::{}) catch { _ => "?" }

  assert_eq(req_id, "REQ-42")
  assert_eq(user_id, "USER-99")
}