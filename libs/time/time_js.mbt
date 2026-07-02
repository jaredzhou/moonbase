///|
/// Returns the current UTC time.
pub fn now() -> Datetime {
  let millis = js_date_now()
  let sec = millis / 1000L
  let ms = (millis % 1000L).to_int()
  let dt = @xtime.unix(sec, nanosecond=ms * 1_000_000, zone=@xtime.utc_zone) catch {
    _ => panic()
  }
  Datetime::{ inner: dt }
}

///|
extern "js" fn js_date_now() -> Int64 = "Date.now"
