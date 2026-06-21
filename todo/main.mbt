// TinyTodo — Cedar policy-based authorization demo server.

///|
async fn main {
  let policies_src =
    #|permit(
    #|  principal,
    #|  action in [Action::"CreateList", Action::"GetLists"],
    #|  resource == Application::"TinyTodo"
    #|);
    #|
    #|permit(
    #|  principal,
    #|  action,
    #|  resource
    #|)
    #|when { resource.owner == principal };
    #|
    #|permit(
    #|  principal,
    #|  action == Action::"GetList",
    #|  resource
    #|)
    #|when { principal in resource.readers || principal in resource.editors };
    #|
    #|permit(
    #|  principal,
    #|  action in [Action::"UpdateList", Action::"CreateTask", Action::"UpdateTask", Action::"DeleteTask"],
    #|  resource
    #|)
    #|when { principal in resource.editors };
  let entities_src =
    #|[{"uid":{"type":"Application","id":"TinyTodo"},"attrs":{},"tags":{},"parents":[]},{"uid":{"type":"User","id":"emina"},"attrs":{"location":"DEF33","joblevel":8},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"}]},{"uid":{"type":"User","id":"aaron"},"attrs":{"location":"ABC17","joblevel":5},"tags":{},"parents":[{"type":"Team","id":"interns"},{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"User","id":"andrew"},"attrs":{"location":"XYZ77","joblevel":5},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"admin"},{"type":"Team","id":"temp"}]},{"uid":{"type":"User","id":"kesha"},"attrs":{"location":"ABC17","joblevel":5},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]},{"uid":{"type":"Team","id":"temp"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"admin"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"}]},{"uid":{"type":"Team","id":"interns"},"attrs":{},"tags":{},"parents":[{"type":"Application","id":"TinyTodo"},{"type":"Team","id":"temp"}]}]

  let state = @store.init_state(policies_src, entities_src)
  let r = @pony.Router::Router()
  let _ = @handler.build_list_routes(r, state)
  let _ = @handler.build_task_routes(r, state)
  println("TinyTodo server starting on 127.0.0.1:3000")
  @pony.start("127.0.0.1:3000", r)
}
