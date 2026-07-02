///|
test "from_iso8601 parses UTC datetime with fractional seconds" {
  let s = "2024-01-01T00:00:00Z"
  let year = parse_int(s[0:4])
  let month = parse_int(s[5:7])
  let day = parse_int(s[8:10])
  let hour = parse_int(s[11:13])
  let minute = parse_int(s[14:16])
  let second = parse_int(s[17:19])
  let dt = @xtime.date_time(
    year,
    month,
    day,
    hour~,
    minute~,
    second~,
    zone=@xtime.utc_zone,
  ) catch {
    _ => panic()
  }
  inspect(dt.to_unix_second(), content="1704067200")
}

///|
test "from_iso8601 directly" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00Z") catch {
    e => {
      println("error: " + e.to_string())
      panic()
    }
  }
  inspect(dt.to_unix_millis(), content="1704067200000")
}
