///|
/// Returns the current Unix timestamp in seconds.
pub fn now() -> Int64 {
  runtime_time_now_seconds()
}

///|
/// Returns the current Unix timestamp in milliseconds.
pub fn now_mill() -> Int64 {
  runtime_time_now_millis()
}

///|
extern "C" fn runtime_time_now_seconds() -> Int64 = "runtime_time_now_seconds"

///|
extern "C" fn runtime_time_now_millis() -> Int64 = "runtime_time_now_millis"
