///|
/// JWT middleware. Parses `Authorization: Bearer <token>`,
/// decodes the payload, and stores the `sub` claim as user_id
/// via `ctx.set_ext(UserId, ...)`.
pub fn jwt() -> @pony.Middleware {
  next => {
    ctx => {
      let token = match ctx.header("authorization") {
        Some(auth) if auth.has_prefix("Bearer ") => auth[7:].to_owned()
        _ => {
          next(ctx)
          return
        }
      }
      match @jwt.decode(token) {
        Ok(payload) => {
          let json = @json.parse(payload) catch { _ => return next(ctx) }
          match json {
            Json::Object(m) => match m.get("sub") {
              Some(Json::String(s)) => ctx.set_ext(@pony.UserId::{}, s)
              _ => ()
            }
            _ => ()
          }
        }
        Err(_) => ()
      }
      next(ctx)
    }
  }
}
