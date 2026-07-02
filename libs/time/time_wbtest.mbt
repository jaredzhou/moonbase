///|
test "from_iso8601 parses UTC datetime" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00Z") catch {
    e => {
      println("error: " + e.to_string())
      panic()
    }
  }
  inspect(dt.to_unix_millis(), content="1704067200000")
}

///|
test "from_iso8601 parses UTC datetime with fractional seconds" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00.123Z") catch {
    e => {
      println("error: " + e.to_string())
      panic()
    }
  }
  inspect(dt.to_unix_millis(), content="1704067200123")
}

///|
test "from_iso8601 parses positive offset" {
  let dt = Datetime::from_iso8601("2024-01-01T08:00:00+08:00") catch {
    e => {
      println("error: " + e.to_string())
      panic()
    }
  }
  inspect(dt.to_unix_millis(), content="1704067200000")
}
