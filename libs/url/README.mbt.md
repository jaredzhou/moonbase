# `url`

The `url` package provides URL parsing according to RFC 3986.

## Parsing URLs

### Basic URLs

```mbt check
///|
test "parse simple url" {
  let url = parse("http://example.com")
  @debug.assert_eq(url.scheme, Some("http"))
  @debug.assert_eq(url.host, Some("example.com"))
  inspect(url, content="http://example.com")
}
```

### URLs with Paths

```mbt check
///|
test "parse url with path" {
  let url = parse("http://example.com/path/to/resource")
  @debug.assert_eq(url.path, Some("/path/to/resource"))
  inspect(url, content="http://example.com/path/to/resource")
}
```

### URLs with Query Strings

```mbt check
///|
test "parse url with query" {
  let url = parse("http://example.com/search?q=keyword")
  @debug.assert_eq(url.query, Some("q=keyword"))
  inspect(url, content="http://example.com/search?q=keyword")
}
```

### URLs with Fragments

```mbt check
///|
test "parse url with fragment" {
  let url = parse("http://example.com/page#section")
  @debug.assert_eq(url.fragment, Some("section"))
  inspect(url, content="http://example.com/page#section")
}
```

### URLs with User Info

```mbt check
///|
test "parse url with userinfo" {
  let url = parse("http://user@example.com")
  match url.user_info {
    Some(info) => {
      @debug.assert_eq(info.username, "user")
      @debug.assert_eq(info.password, None)
    }
    None => panic()
  }
  inspect(url, content="http://user@example.com")
}

///|
test "parse url with password" {
  let url = parse("http://user:pass@example.com")
  match url.user_info {
    Some(info) => {
      @debug.assert_eq(info.username, "user")
      @debug.assert_eq(info.password, Some("pass"))
    }
    None => panic()
  }
  inspect(url, content="http://user:pass@example.com")
}
```

### URLs with Ports

```mbt check
///|
test "parse url with port" {
  let url = parse("http://example.com:8080")
  @debug.assert_eq(url.host, Some("example.com:8080"))
  inspect(url, content="http://example.com:8080")
}
```

### IPv6 Addresses

```mbt check
///|
test "parse ipv6 url" {
  let url = parse("http://[::1]:8080/")
  @debug.assert_eq(url.host, Some("[::1]:8080"))
  inspect(url, content="http://[::1]:8080/")
}
```

### Special Schemes

```mbt check
///|
test "parse https" {
  let url = parse("https://secure.example.com")
  @debug.assert_eq(url.scheme, Some("https"))
  inspect(url, content="https://secure.example.com")
}

///|
test "parse file url" {
  let url = parse("file:///path/to/file")
  @debug.assert_eq(url.scheme, Some("file"))
  @debug.assert_eq(url.host, Some(""))
  inspect(url, content="file:///path/to/file")
}

///|
test "parse mailto" {
  let url = parse("mailto:user@example.com")
  @debug.assert_eq(url.scheme, Some("mailto"))
  @debug.assert_eq(url.opaque_str, Some("user@example.com"))
  inspect(url, content="mailto:user@example.com")
}

///|
test "parse asterisk" {
  let url = parse("*")
  @debug.assert_eq(url.path, Some("*"))
  inspect(url, content="*")
}
```

## URL Encoding

### Query Escape

```mbt check
///|
test "query escape spaces" {
  let escaped = query_escape("hello world")
  @debug.assert_eq(escaped, "hello%20world")
  inspect(escaped, content="hello%20world")
}
```

### Query Unescape

```mbt check
///|
test "query unescape" {
  let result = query_unescape("hello%20world")
  @debug.assert_eq(result, "hello world")
  inspect(result, content="hello world")
}

///|
test "query unescape plus" {
  let result = query_unescape("hello+world")
  @debug.assert_eq(result, "hello world")
  inspect(result, content="hello world")
}
```

### Path Segment Escape

```mbt check
///|
test "path segment escape" {
  let escaped = path_segment_escape("a/b c")
  @debug.assert_eq(escaped, "a%2Fb%20c")
  inspect(escaped, content="a%2Fb%20c")
}
```

### Path Segment Unescape

```mbt check
///|
test "path segment unescape" {
  let result = path_segment_unescape("a%2fb%20c")
  @debug.assert_eq(result, "a/b c")
  inspect(result, content="a/b c")
}
```

## Request URI

### Origin Form

```mbt check
///|
test "parse origin form uri" {
  let url = parse_request_uri("/path?query=value")
  @debug.assert_eq(url.path, Some("/path"))
  @debug.assert_eq(url.query, Some("query=value"))
  inspect(url, content="/path?query=value")
}
```

### Asterisk Form

```mbt check
///|
test "parse asterisk form uri" {
  let url = parse_request_uri("*")
  @debug.assert_eq(url.path, Some("*"))
  inspect(url, content="*")
}
```


