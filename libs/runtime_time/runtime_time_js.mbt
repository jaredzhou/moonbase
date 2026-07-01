///|
/// Returns the current Unix timestamp in seconds.
pub fn now() -> Int64 {
  (js_date_now() / 1000L).to_int64()
}

///|
/// Returns the current Unix timestamp in milliseconds.
pub fn now_mill() -> Int64 {
  js_date_now()
}

///|
extern "js" fn js_date_now() -> Int64 = "Date.now"
