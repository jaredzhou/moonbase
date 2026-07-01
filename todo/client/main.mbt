// TinyTodo CLI client — interact with the Cedar policy demo server.
//
// Usage: moon run ./todo/client <user> <cmd> [args...]
//
// Examples:
//   emina new Shopping
//   emina list
//   emina view 0
//   emina task 0 "Buy milk"
//   emina share 0 aaron
//   emina share 0 aaron editor
//   aaron toggle 0 0
//   aaron done 0

///|
let base = "http://127.0.0.1:3000"

///|
async fn main {
  let args = @sys.get_cli_args()
  if args.length() < 3 {
    show_usage()
    return
  }

  let user = args[1]
  let cmd = args[2]

  match cmd {
    "list" => get(user, "/lists")
    "view" =>
      if args.length() >= 4 {
        get(user, "/lists/" + args[3])
      } else {
        println("usage: view <id>")
      }
    "new" =>
      if args.length() >= 4 {
        post(user, "/lists", b1("name", join(args, 3)))
      } else {
        println("usage: new <name>")
      }
    "done" =>
      if args.length() >= 4 {
        delete(user, "/lists/" + args[3])
      } else {
        println("usage: done <id>")
      }
    "task" =>
      if args.length() >= 5 {
        post(user, "/lists/" + args[3] + "/tasks", b1("name", join(args, 4)))
      } else {
        println("usage: task <list> <name>")
      }
    "toggle" =>
      if args.length() >= 5 {
        patch(
          user,
          "/lists/" + args[3] + "/tasks/" + args[4],
          b1("state", "done"),
        )
      } else {
        println("usage: toggle <list> <pos>")
      }
    "del" =>
      if args.length() >= 5 {
        delete(user, "/lists/" + args[3] + "/tasks/" + args[4])
      } else {
        println("usage: del <list> <pos>")
      }
    "share" => {
      let id_str = if args.length() >= 4 {
        args[3]
      } else {
        println("usage: share <list> <user> [editor]")
        return
      }
      let target = if args.length() >= 5 {
        args[4]
      } else {
        println("usage: share <list> <user> [editor]")
        return
      }
      let ro = if args.length() >= 6 && args[5] == "editor" {
        "false"
      } else {
        "true"
      }
      let body = "{" +
        "\"target\":\"" +
        target +
        "\"," +
        "\"readonly\":" +
        ro +
        "}"
      post(user, "/lists/" + id_str + "/share", body)
    }
    "unshare" =>
      if args.length() >= 5 {
        delete_body(user, "/lists/" + args[3] + "/share", b1("target", args[4]))
      } else {
        println("usage: unshare <list> <user>")
      }
    "" => show_usage()
    _ => println("unknown: " + cmd)
  }
}

///|
fn show_usage() -> Unit {
  println("usage: moon run ./todo/client <user> <cmd> [args...]")
  println("cmds: list, view, new, done, task, toggle, del, share, unshare")
}

///|
fn hdr(user : String) -> Map[String, String] {
  Map([("X-User", user)])
}

///|
fn b1(key : String, val : String) -> String {
  "{" + "\"" + key + "\":\"" + val + "\"}"
}

///|
fn join(args : Array[String], start : Int) -> String {
  let mut s = ""
  for i = start; i < args.length(); i = i + 1 {
    if i > start {
      s = s + " "
    }
    s = s + args[i]
  }
  s
}

///|
async fn get(user : String, path : String) -> Unit {
  let url = base + path
  let (resp, body) = @http.get(url, headers=hdr(user))
  println(show_rsp(resp, body))
}

///|
async fn post(user : String, path : String, body : String) -> Unit {
  let url = base + path
  let (resp, rsp_body) = @http.post(url, body, headers=hdr(user))
  println(show_rsp(resp, rsp_body))
}

///|
async fn patch(user : String, path : String, body : String) -> Unit {
  let client = @http.Client(base, headers=hdr(user))
  client.request(@http.Patch, path, extra_headers=hdr(user))
  client.write(body)
  let resp = client.end_request()
  println(resp.code.to_string() + " " + resp.reason)
}

///|
async fn delete(user : String, path : String) -> Unit {
  let client = @http.Client(base, headers=hdr(user))
  client.request(@http.Delete, path, extra_headers=hdr(user))
  let resp = client.end_request()
  println(resp.code.to_string() + " " + resp.reason)
}

///|
async fn delete_body(user : String, path : String, body : String) -> Unit {
  let client = @http.Client(base, headers=hdr(user))
  client.request(@http.Delete, path, extra_headers=hdr(user))
  client.write(body)
  let resp = client.end_request()
  println(resp.code.to_string() + " " + resp.reason)
}

///|
fn show_rsp(resp : @http.Response, body : &@io.Data) -> String {
  let txt = body.text() catch { _ => "" }
  if txt == "" {
    resp.code.to_string() + " " + resp.reason
  } else {
    txt
  }
}
