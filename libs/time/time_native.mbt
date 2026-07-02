///|
/// Returns the current UTC time.
pub fn now() -> Datetime {
  Datetime::{ millis: time_now_millis() }
}

///|
extern "C" fn time_now_millis() -> Int64 = "time_now_millis"
