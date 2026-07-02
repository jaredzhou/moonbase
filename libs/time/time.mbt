///|
/// A UTC datetime wrapper around Unix epoch milliseconds.
/// Provides JSON serialization as ISO 8601 and PostgreSQL `timestamptz`
/// compatibility.
pub struct Datetime {
  millis : Int64
} derive(Eq, Compare, Debug)

///|
/// Creates a `Datetime` from Unix epoch milliseconds.
pub fn Datetime::from_unix_millis(millis : Int64) -> Datetime {
  Datetime::{ millis, }
}

///|
/// Returns the underlying Unix epoch milliseconds.
pub fn Datetime::to_unix_millis(self : Datetime) -> Int64 {
  self.millis
}

///|
/// Formats the datetime as an ISO 8601 UTC string.
///
/// * Examples: `"2024-01-01T00:00:00Z"` or `"2024-01-01T00:00:00.123Z"`.
pub fn Datetime::to_iso8601(self : Datetime) -> String {
  let seconds = self.millis / 1000L
  let ms = (self.millis % 1000L).to_int()
  let dt = @xtime.unix(seconds, nanosecond=ms * 1_000_000, zone=@xtime.utc_zone) catch {
    _ => panic()
  }
  let year = pad(dt.year().to_string(), 4, '0')
  let month = pad(dt.month().to_string(), 2, '0')
  let day = pad(dt.day().to_string(), 2, '0')
  let hour = pad(dt.hour().to_string(), 2, '0')
  let minute = pad(dt.minute().to_string(), 2, '0')
  let second = pad(dt.second().to_string(), 2, '0')
  if ms == 0 {
    "\{year}-\{month}-\{day}T\{hour}:\{minute}:\{second}Z"
  } else {
    let ms_str = pad(ms.to_string(), 3, '0')
    "\{year}-\{month}-\{day}T\{hour}:\{minute}:\{second}.\{ms_str}Z"
  }
}

///|
/// Parses an ISO 8601 UTC string and returns a `Datetime`.
///
/// Supports `"Z"` suffix with or without fractional seconds:
/// * `"2024-01-01T00:00:00Z"`
/// * `"2024-01-01T00:00:00.123Z"`
pub fn Datetime::from_iso8601(s : String) -> Datetime raise Error {
  let len = s.length()
  guard len == 20 || len == 24 else {
    raise Failure::Failure("invalid ISO 8601 length")
  }
  guard s[len - 1] == 'Z' else {
    raise Failure::Failure("invalid ISO 8601 timezone marker")
  }
  let year = parse_int(s[0:4])
  let month = parse_int(s[5:7])
  let day = parse_int(s[8:10])
  let hour = parse_int(s[11:13])
  let minute = parse_int(s[14:16])
  let second = parse_int(s[17:19])
  let ms = if len == 24 {
    guard s[19] == '.' else {
      raise Failure::Failure("invalid ISO 8601 fractional seconds")
    }
    parse_int(s[20:23])
  } else {
    0
  }
  let dt = @xtime.date_time(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    zone=@xtime.utc_zone,
  ) catch {
    _ => raise Failure::Failure("invalid ISO 8601 datetime")
  }
  let seconds = dt.to_unix_second()
  Datetime::{ millis: seconds * 1000L + ms.to_int64() }
}

///|
/// Formats the datetime for PostgreSQL `timestamptz`.
///
/// PostgreSQL accepts ISO 8601 strings as `timestamptz` literals, so this
/// returns the same value as `to_iso8601`.
pub fn Datetime::to_pg_timestamptz(self : Datetime) -> String {
  self.to_iso8601()
}

///|
pub impl ToJson for Datetime with fn to_json(self) {
  Json::string(self.to_iso8601())
}

///|
pub impl Show for Datetime with fn output(self, logger) {
  logger.write_string(self.to_iso8601())
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

///|
fn pad(s : String, len : Int, c : Char) -> String {
  if s.length() >= len {
    s
  } else {
    let pad_len = len - s.length()
    let buf = StringBuilder::new()
    for _ in 0..<pad_len {
      buf.write_char(c)
    }
    buf.write_string(s)
    buf.to_string()
  }
}

///|
fn parse_int(s : StringView) -> Int raise Error {
  let mut sign = 1
  let mut start = 0
  if s[0] == '-' {
    sign = -1
    start = 1
  }
  let mut n = 0
  for i in start..<s.length() {
    let c = s[i]
    guard c >= '0' && c <= '9' else { raise Failure::Failure("expected digit") }
    n = n * 10 + (c - '0').to_int()
  }
  sign * n
}
