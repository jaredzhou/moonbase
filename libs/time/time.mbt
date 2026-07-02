///|
/// A datetime wrapper around `@xtime.ZonedDateTime`.
///
/// Provides JSON serialization as ISO 8601 and PostgreSQL `timestamptz`
/// compatibility. By default values are created in UTC, but the underlying
/// `ZonedDateTime` preserves the original zone and offset.
pub struct Datetime {
  inner : @xtime.ZonedDateTime
} derive(Debug)

///|
pub impl Eq for Datetime with fn equal(self, other) {
  self.inner.to_unix_second() == other.inner.to_unix_second() &&
  self.inner.nanosecond() == other.inner.nanosecond()
}

///|
pub impl Compare for Datetime with fn compare(self, other) {
  let sec_cmp = self.inner
    .to_unix_second()
    .compare(other.inner.to_unix_second())
  if sec_cmp != 0 {
    sec_cmp
  } else {
    self.inner.nanosecond().compare(other.inner.nanosecond())
  }
}

///|
/// Creates a `Datetime` from a raw `@xtime.ZonedDateTime`.
pub fn Datetime::from_zoned(dt : @xtime.ZonedDateTime) -> Datetime {
  Datetime::{ inner: dt }
}

///|
/// Returns the underlying `@xtime.ZonedDateTime`.
pub fn Datetime::to_zoned(self : Datetime) -> @xtime.ZonedDateTime {
  self.inner
}

///|
/// Creates a `Datetime` from Unix epoch milliseconds in UTC.
pub fn Datetime::from_unix_millis(millis : Int64) -> Datetime {
  let seconds = millis / 1000L
  let ns = (millis % 1000L * 1_000_000L).to_int()
  let dt = @xtime.unix(seconds, nanosecond=ns, zone=@xtime.utc_zone) catch {
    _ => panic()
  }
  Datetime::{ inner: dt }
}

///|
/// Returns the Unix epoch milliseconds.
pub fn Datetime::to_unix_millis(self : Datetime) -> Int64 {
  self.inner.to_unix_second() * 1000L +
  (self.inner.nanosecond() / 1_000_000).to_int64()
}

///|
/// Formats the datetime as an ISO 8601 string with the original zone offset.
///
/// * UTC examples: `"2024-01-01T00:00:00Z"` or `"2024-01-01T00:00:00.123Z"`.
pub fn Datetime::to_iso8601(self : Datetime) -> String {
  let year = pad(self.inner.year().to_string(), 4, '0')
  let month = pad(self.inner.month().to_string(), 2, '0')
  let day = pad(self.inner.day().to_string(), 2, '0')
  let hour = pad(self.inner.hour().to_string(), 2, '0')
  let minute = pad(self.inner.minute().to_string(), 2, '0')
  let second = pad(self.inner.second().to_string(), 2, '0')
  let ms = self.inner.nanosecond() / 1_000_000
  let offset = self.inner.offset().to_string()
  if ms == 0 {
    "\{year}-\{month}-\{day}T\{hour}:\{minute}:\{second}\{offset}"
  } else {
    let ms_str = pad(ms.to_string(), 3, '0')
    "\{year}-\{month}-\{day}T\{hour}:\{minute}:\{second}.\{ms_str}\{offset}"
  }
}

///|
/// Parses an ISO 8601 string and returns a `Datetime`.
///
/// Supports `"Z"` or numeric offsets (`+08:00`, `-05:00`) with or without
/// fractional seconds:
/// * `"2024-01-01T00:00:00Z"`
/// * `"2024-01-01T00:00:00.123Z"`
/// * `"2024-01-01T08:00:00+08:00"`
pub fn Datetime::from_iso8601(s : String) -> Datetime raise Error {
  let len = s.length()
  guard len == 20 || len == 24 || len == 25 || len == 29 else {
    raise Failure::Failure("invalid ISO 8601 length")
  }
  let year = parse_int(s[0:4])
  let month = parse_int(s[5:7])
  let day = parse_int(s[8:10])
  let hour = parse_int(s[11:13])
  let minute = parse_int(s[14:16])
  let second = parse_int(s[17:19])
  let (ms, tz_start) = if s[19] == '.' {
    guard len >= 24 else {
      raise Failure::Failure("invalid ISO 8601 fractional seconds")
    }
    (parse_int(s[20:23]), 23)
  } else {
    (0, 19)
  }
  let zone = if s[tz_start] == 'Z' {
    guard len == tz_start + 1 else {
      raise Failure::Failure("invalid ISO 8601 timezone")
    }
    @xtime.utc_zone
  } else {
    guard len == tz_start + 6 else {
      raise Failure::Failure("invalid ISO 8601 zone offset length")
    }
    let offset = parse_offset(s[tz_start:len])
    @xtime.fixed_zone("offset", offset) catch {
      _ => raise Failure::Failure("invalid ISO 8601 zone offset")
    }
  }
  let dt = @xtime.date_time(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    nanosecond=ms * 1_000_000,
    zone~,
  ) catch {
    _ => raise Failure::Failure("invalid ISO 8601 datetime")
  }
  Datetime::{ inner: dt }
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

///|
/// Parses a numeric zone offset such as `+08:00` or `-05:30` and returns the
/// offset in seconds.
fn parse_offset(s : StringView) -> Int raise Error {
  guard s.length() == 6 else {
    raise Failure::Failure("invalid ISO 8601 zone offset length")
  }
  let sign = if s[0] == '+' {
    1
  } else if s[0] == '-' {
    -1
  } else {
    raise Failure::Failure("invalid ISO 8601 zone offset sign")
  }
  let hour = parse_int(s[1:3])
  guard s[3] == ':' else {
    raise Failure::Failure("invalid ISO 8601 zone offset")
  }
  let minute = parse_int(s[4:6])
  sign * (hour * 3600 + minute * 60)
}
