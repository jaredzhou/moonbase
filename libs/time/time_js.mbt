///|
/// Returns the current UTC time.
pub fn now() -> Datetime {
  Datetime::{ millis: js_date_now() }
}

///|
extern "js" fn js_date_now() -> Int64 = "Date.now"
