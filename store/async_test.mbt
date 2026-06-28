// Integration tests for the store module.
// Spins up a real HTTP server (pony + async/http) and tests
// the bucket + object REST endpoints end-to-end.

///|
async test "integration: create bucket with explicit Content-Length" {
  @async.with_task_group() <| group => {
    let port = 19880
    let storage = new_test_storage()
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    let client = @http.Client("http://127.0.0.1:\{port}")
    defer client.close()

    let body = #|{"name":"test-bucket","public":false}"
    let content_length = body.length().to_string()
    client.request(
      @http.RequestMethod::Post,
      "/bucket/",
      extra_headers={ "x-user": "alice", "Content-Length": content_length },
    )
    client.write(body)
    let resp = client.end_request()
    let _body = client.read_all()
    @debug.assert_eq(resp.code, 200)
  }
}

///|
async test "integration: simple GET bucket list" {
  @async.with_task_group() <| group => {
    let port = 19881
    let storage = new_test_storage()
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    let (resp, _) = @http.get(
      "http://127.0.0.1:\{port}/bucket/",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp.code, 200)
  }
}

///|
async test "integration: full flow" {
  @async.with_task_group() <| group => {
    let port = 19882
    let storage = new_test_storage()
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    let _ = build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Create bucket via GET with pre-created bucket
    let st = new_test_storage()
    let bucket_input = CreateBucketInput::{ name: "ops", public: false, file_size_limit: None, allowed_mime_types: None }
    let _ = st.create_bucket("alice", bucket_input) catch { _ => () }

    let create_body = #|{"name":"ops","public":false}"
    let (resp, _) = @http.post(
      "http://127.0.0.1:\{port}/bucket/",
      create_body,
      headers={ "x-user": "alice", "content-type": "application/json" },
    )
    @debug.assert_eq(resp.code, 200)

    // Upload
    let (resp2, _) = @http.post(
      "http://127.0.0.1:\{port}/object/ops/old.txt",
      "test data",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp2.code, 200)

    // Download
    let (resp3, _) = @http.get(
      "http://127.0.0.1:\{port}/object/authenticated/ops/old.txt",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp3.code, 200)

    // Move
    let move_body = #|{"bucket_id":"ops","source_key":"old.txt","destination_key":"new.txt"}"
    let (resp4, _) = @http.post(
      "http://127.0.0.1:\{port}/object/move",
      move_body,
      headers={ "x-user": "alice", "content-type": "application/json" },
    )
    @debug.assert_eq(resp4.code, 204)

    // Delete
    let dclient = @http.Client("http://127.0.0.1:\{port}")
    defer dclient.close()
    dclient.request(
      @http.RequestMethod::Delete,
      "/object/ops/new.txt",
      extra_headers={ "x-user": "alice" },
    )
    let resp5 = dclient.end_request()
    @debug.assert_eq(resp5.code, 204)
  }
}
