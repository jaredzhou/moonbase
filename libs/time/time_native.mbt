///|
/// Returns the current UTC time.
pub fn now() -> Datetime {
  let total_nsec = time_now_nanoseconds()
  let sec = total_nsec / 1_000_000_000L
  let nsec = total_nsec % 1_000_000_000L
  let dt = @xtime.unix(sec, nanosecond=nsec.to_int(), zone=@xtime.utc_zone) catch {
    _ => panic()
  }
  Datetime::{ inner: dt }
}

///|
extern "C" fn time_now_nanoseconds() -> Int64 = "time_now_nanoseconds"
