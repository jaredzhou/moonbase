///|
test "from_unix and to_unix roundtrip" {
  let dt = Datetime::from_unix(1704067200L)
  inspect(dt.to_unix(), content="1704067200")
}

///|
test "to_iso8601 without milliseconds" {
  let dt = Datetime::from_unix(1704067200L)
  inspect(dt.to_iso8601(), content="2024-01-01T00:00:00Z")
}

///|
test "to_iso8601 with milliseconds" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00.123Z") catch {
    _ => panic()
  }
  inspect(dt.to_iso8601(), content="2024-01-01T00:00:00.123Z")
}

///|
test "from_iso8601 roundtrip" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00Z") catch { _ => panic() }
  inspect(dt.to_unix(), content="1704067200")
  let dt2 = Datetime::from_iso8601("2024-01-01T00:00:00.123Z") catch {
    _ => panic()
  }
  inspect(dt2.to_unix(), content="1704067200")
}

///|
test "to_json serializes as ISO 8601 string" {
  let dt = Datetime::from_unix(1704067200L)
  inspect(dt.to_json().stringify(), content="\"2024-01-01T00:00:00Z\"")
}

///|
test "to_pg_timestamptz matches ISO 8601" {
  let dt = Datetime::from_iso8601("2024-01-01T00:00:00.123Z") catch {
    _ => panic()
  }
  inspect(dt.to_pg_timestamptz(), content="2024-01-01T00:00:00.123Z")
}
