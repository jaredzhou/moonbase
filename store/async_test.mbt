// Integration tests for the store module.
// Spins up a real HTTP server (pony + async/http) and tests
// the bucket + object REST endpoints end-to-end.

///|
async test "integration: list and get bucket via HTTP" {
  @async.with_task_group() <| group => {
    let port = 19880
    let storage = new_test_storage()
    // Pre-populate a bucket directly in the storage
    let input = CreateBucketInput::{ name: "my-bucket", public: Some(false), file_size_limit: None, allowed_mime_types: None }
    let _bucket = storage.create_bucket("alice", input) catch { e => panic() }
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // List buckets
    let (resp, _) = @http.get(
      "http://127.0.0.1:\{port}/bucket/",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp.code, 200)

    // Get specific bucket
    let (resp2, _) = @http.get(
      "http://127.0.0.1:\{port}/bucket/my-bucket",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp2.code, 200)
  }
}

///|
async test "integration: upload and download object via HTTP" {
  @async.with_task_group() <| group => {
    let port = 19881
    let storage = new_test_storage()
    let bucket_input = CreateBucketInput::{ name: "pub", public: Some(true), file_size_limit: None, allowed_mime_types: None }
    let _bucket = storage.create_bucket("alice", bucket_input) catch { e => panic() }
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    let _ = build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Upload
    let (resp2, _) = @http.post(
      "http://127.0.0.1:\{port}/object/pub/hello.txt",
      "hello world",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp2.code, 200)

    // Public download
    let (resp3, _) = @http.get(
      "http://127.0.0.1:\{port}/object/public/pub/hello.txt",
    )
    @debug.assert_eq(resp3.code, 200)
  }
}

///|
async test "integration: move and delete object via HTTP" {
  @async.with_task_group() <| group => {
    let port = 19882
    let storage = new_test_storage()
    let bucket_input = CreateBucketInput::{ name: "ops", public: Some(false), file_size_limit: None, allowed_mime_types: None }
    let _bucket = storage.create_bucket("alice", bucket_input) catch { e => panic() }
    let r = @pony.Router::Router()
    let _ = build_bucket_routes(r, storage)
    let _ = build_object_routes(r, storage)
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      @pony.start("127.0.0.1:\{port}", r)
    }
    @async.sleep(500)

    // Upload
    let (resp2, _) = @http.post(
      "http://127.0.0.1:\{port}/object/ops/old.txt",
      "test data",
      headers={ "x-user": "alice" },
    )
    @debug.assert_eq(resp2.code, 200)

    // Move
    let move_body = #|{"bucket_id":"ops","source_key":"old.txt","destination_key":"new.txt"}"
    let (resp3, _) = @http.post(
      "http://127.0.0.1:\{port}/object/move",
      move_body,
      headers={ "x-user": "alice", "content-type": "application/json" },
    )
    @debug.assert_eq(resp3.code, 204)

    // Delete
    let dclient = @http.Client("http://127.0.0.1:\{port}")
    defer dclient.close()
    dclient.request(
      @http.RequestMethod::Delete,
      "/object/ops/new.txt",
      extra_headers={ "x-user": "alice" },
    )
    let resp4 = dclient.end_request()
    @debug.assert_eq(resp4.code, 204)
  }
}
