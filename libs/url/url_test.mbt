///|
test "parse" {
  for t in url_tests {
    let url = parse(t.input)
    assert_eq(url, t.out)
    if t.roundtrip != "" {
      inspect(url, content=t.roundtrip)
    } else {
      inspect(url, content=t.input)
    }
  }
}

///|
test "benchmark parse" (b : @bench.T) {
  let r = @random.Rand::new()
  b.bench(() => {
    let i = r.int(limit=url_tests.length())
    try {
      let _ = parse(url_tests[i].input)
    } catch {
      _ => ()
    }
  })
}

///|
test "benchmark to_string" (b : @bench.T) {
  let r = @random.Rand::new()
  b.bench(() => {
    let i = r.int(limit=url_tests.length())
    let _ = url_tests[i].out.to_string()
  })
}

///|
test "request uri test" {
  for t in request_uri_tests {
    let (input, expected) = t
    try parse_request_uri(input) catch {
      _ => assert_eq(expected, false)
    } noraise {
      _ => assert_eq(expected, true)
    }
  }
}

///|
test "unescape %20 and +" {
  let query = "name=John+Doe&city=New%20York"
  inspect(query_unescape(query), content="name=John Doe&city=New York")
  inspect(path_segment_unescape(query), content="name=John+Doe&city=New York")
}

///|
test "query escape and unescape" {
  inspect(query_escape(""), content="")
  inspect(query_escape("abc"), content="abc")
  inspect(query_escape("one two"), content="one%20two")
}

///|
let request_uri_tests : Array[(String, Bool)] = [
  ("http://foo.com", true),
  ("http://foo.com/", true),
  ("http://foo.com/path", true),
  ("/", true),
  ("*", true),
  ("http://192.168.0.1/", true),
  ("http://192.168.0.1:8080/", true),
  ("http://[fe80::1]/", true),
  ("http://[fe80::1]:8080/", true),
  // Tests exercising RFC 6874 compliance:
  ("http://[fe80::1%25en0]/", true), // with alphanum zone identifier
  ("http://[fe80::1%25en0]:8080/", true), // with alphanum zone identifier
  ("http://[fe80::1%25%65%6e%301-._~]/", true), // with percent-encoded+unreserved zone identifier
  ("http://[fe80::1%25%65%6e%301-._~]:8080/", true), // with percent-encoded+unreserved zone identifier
  ("foo.html", false),
  ("../dir/", false),
  (" http://foo.com", false),
  ("http://192.168.0.%31/", false),
  ("http://192.168.0.%31:8080/", false),
  ("http://[fe80::%31]/", false),
  ("http://[fe80::%31]:8080/", false),
  ("http://[fe80::%31%25en0]/", false),
  ("http://[fe80::%31%25en0]:8080/", false),
  // These two cases are valid as textual representations as
  // described in RFC 4007, but are not valid as address
  // literals with IPv6 zone identifiers in URIs as described in
  // RFC 6874.
  ("http://[fe80::1%en0]/", false),
  ("http://[fe80::1%en0]:8080/", false),
]

///|
struct URLTest {
  input : String
  out : URL
  roundtrip : String
}

///|
/// this test data is copied from net/url/url_test.go in the Go standard library
let url_tests : Array[URLTest] = [
  // no path
  {
    input: "http://www.google.com",
    out: { ..empty_url, scheme: Some("http"), host: Some("www.google.com") },
    roundtrip: "",
  },
  // path
  {
    input: "http://www.google.com/",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // path with hex escaping
  {
    input: "http://www.google.com/file%20one%26two",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/file one&two"),
    },
    roundtrip: "http://www.google.com/file%20one&two",
  },
  // fragment with hex escaping
  {
    input: "http://www.google.com/#file%20one%26two",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      fragment: Some("file one&two"),
    },
    roundtrip: "http://www.google.com/#file%20one&two",
  },
  // user
  {
    input: "ftp://webmaster@www.google.com/",
    out: {
      ..empty_url,
      scheme: Some("ftp"),
      user_info: Some(UserInfo::{ username: "webmaster", password: None }),
      host: Some("www.google.com"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // escape sequence in username
  {
    input: "ftp://john%20doe@www.google.com/",
    out: {
      ..empty_url,
      scheme: Some("ftp"),
      user_info: Some(UserInfo::{ username: "john doe", password: None }),
      host: Some("www.google.com"),
      path: Some("/"),
    },
    roundtrip: "ftp://john%20doe@www.google.com/",
  },
  // empty query
  {
    input: "http://www.google.com/?",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
    },
    roundtrip: "http://www.google.com/",
  },
  // query ending in question mark (Issue 14573)
  {
    input: "http://www.google.com/?foo=bar?",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("foo=bar?"),
    },
    roundtrip: "",
  },
  // query
  {
    input: "http://www.google.com/?q=go+language",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("q=go+language"),
    },
    roundtrip: "",
  },
  // query with hex escaping: NOT parsed
  {
    input: "http://www.google.com/?q=go%20language",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("q=go%20language"),
    },
    roundtrip: "",
  },
  // %20 outside query
  {
    input: "http://www.google.com/a%20b?q=c+d",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/a b"),
      query: Some("q=c+d"),
    },
    roundtrip: "",
  },
  // path without leading /, so no parsing
  {
    input: "http:www.google.com/?q=go+language",
    out: {
      ..empty_url,
      scheme: Some("http"),
      opaque_str: Some("www.google.com/"),
      query: Some("q=go+language"),
    },
    roundtrip: "http:www.google.com/?q=go+language",
  },
  // path without leading /, so no parsing
  {
    input: "http:%2f%2fwww.google.com/?q=go+language",
    out: {
      ..empty_url,
      scheme: Some("http"),
      opaque_str: Some("%2f%2fwww.google.com/"),
      query: Some("q=go+language"),
    },
    roundtrip: "http:%2f%2fwww.google.com/?q=go+language",
  },
  // non-authority with path; see golang.org/issue/46059
  {
    input: "mailto:/webmaster@golang.org",
    out: {
      ..empty_url,
      scheme: Some("mailto"),
      path: Some("/webmaster@golang.org"),
    },
    roundtrip: "",
  },
  // non-authority
  {
    input: "mailto:webmaster@golang.org",
    out: {
      ..empty_url,
      scheme: Some("mailto"),
      opaque_str: Some("webmaster@golang.org"),
    },
    roundtrip: "",
  },
  // unescaped :// in query should not create a scheme
  {
    input: "/foo?query=http://bad",
    out: { ..empty_url, path: Some("/foo"), query: Some("query=http://bad") },
    roundtrip: "",
  },
  // leading // without scheme should create an authority
  { input: "//foo", out: { ..empty_url, host: Some("foo") }, roundtrip: "" },
  // leading // without scheme, with user_info, path, and query
  {
    input: "//user@foo/path?a=b",
    out: {
      ..empty_url,
      user_info: Some(UserInfo::{ username: "user", password: None }),
      host: Some("foo"),
      path: Some("/path"),
      query: Some("a=b"),
    },
    roundtrip: "",
  },
  // Three leading slashes isn't an authority, but doesn't return an error.
  // (We can't return an error, as this code is also used via
  // ServeHTTP -> ReadRequest -> Parse, which is arguably a
  // different URL parsing context, but currently shares the
  // same codepath)
  {
    input: "///threeslashes",
    out: { ..empty_url, path: Some("///threeslashes") },
    roundtrip: "",
  },
  {
    input: "http://user:password@google.com",
    out: {
      ..empty_url,
      scheme: Some("http"),
      user_info: Some(UserInfo::{ username: "user", password: Some("password") }),
      host: Some("google.com"),
    },
    roundtrip: "http://user:password@google.com",
  },
  // unescaped @ in username should not confuse host
  {
    input: "http://j@ne:password@google.com",
    out: {
      ..empty_url,
      scheme: Some("http"),
      user_info: Some(UserInfo::{ username: "j@ne", password: Some("password") }),
      host: Some("google.com"),
    },
    roundtrip: "http://j%40ne:password@google.com",
  },
  // unescaped @ in password should not confuse host
  {
    input: "http://jane:pass@word@google.com",
    out: {
      ..empty_url,
      scheme: Some("http"),
      user_info: Some(UserInfo::{
        username: "jane",
        password: Some("pass@word"),
      }),
      host: Some("google.com"),
    },
    roundtrip: "http://jane:pass%40word@google.com",
  },
  {
    input: "http://j@ne:password@google.com/p@th?q=@go",
    out: {
      ..empty_url,
      scheme: Some("http"),
      user_info: Some(UserInfo::{ username: "j@ne", password: Some("password") }),
      host: Some("google.com"),
      path: Some("/p@th"),
      query: Some("q=@go"),
    },
    roundtrip: "http://j%40ne:password@google.com/p@th?q=@go",
  },
  {
    input: "http://www.google.com/?q=go+language#foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("q=go+language"),
      fragment: Some("foo"),
    },
    roundtrip: "",
  },
  {
    input: "http://www.google.com/?q=go+language#foo&bar",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("q=go+language"),
      fragment: Some("foo&bar"),
    },
    roundtrip: "http://www.google.com/?q=go+language#foo&bar",
  },
  {
    input: "http://www.google.com/?q=go+language#foo%26bar",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("www.google.com"),
      path: Some("/"),
      query: Some("q=go+language"),
      fragment: Some("foo&bar"),
    },
    roundtrip: "http://www.google.com/?q=go+language#foo&bar",
  },
  {
    input: "file:///home/adg/rabbits",
    out: {
      ..empty_url,
      scheme: Some("file"),
      host: Some(""),
      path: Some("/home/adg/rabbits"),
    },
    roundtrip: "file:///home/adg/rabbits",
  },
  // "Windows" paths are no exception to the rule.
  // See golang.org/issue/6027, especially comment #9.
  {
    input: "file:///C:/FooBar/Baz.txt",
    out: {
      ..empty_url,
      scheme: Some("file"),
      host: Some(""),
      path: Some("/C:/FooBar/Baz.txt"),
    },
    roundtrip: "file:///C:/FooBar/Baz.txt",
  },
  // case-insensitive scheme
  {
    input: "MaIlTo:webmaster@golang.org",
    out: {
      ..empty_url,
      scheme: Some("mailto"),
      opaque_str: Some("webmaster@golang.org"),
    },
    roundtrip: "mailto:webmaster@golang.org",
  },
  // Relative path
  {
    input: "a/b/c",
    out: { ..empty_url, path: Some("a/b/c") },
    roundtrip: "a/b/c",
  },
  // escaped '?' in username and password
  {
    input: "http://%3Fam:pa%3Fsword@google.com",
    out: {
      ..empty_url,
      scheme: Some("http"),
      user_info: Some(UserInfo::{ username: "?am", password: Some("pa?sword") }),
      host: Some("google.com"),
    },
    roundtrip: "",
  },
  // host subcomponent; IPv4 address in RFC 3986
  {
    input: "http://192.168.0.1/",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("192.168.0.1"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host and port subcomponents; IPv4 address in RFC 3986
  {
    input: "http://192.168.0.1:8080/",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("192.168.0.1:8080"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host subcomponent; IPv6 address in RFC 3986
  {
    input: "http://[fe80::1]/",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1]"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host and port subcomponents; IPv6 address in RFC 3986
  {
    input: "http://[fe80::1]:8080/",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1]:8080"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host subcomponent; IPv6 address with zone identifier in RFC 6874
  {
    input: "http://[fe80::1%25en0]/", // alphanum zone identifier
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1%en0]"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host and port subcomponents; IPv6 address with zone identifier in RFC 6874
  {
    input: "http://[fe80::1%25en0]:8080/", // alphanum zone identifier
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1%en0]:8080"),
      path: Some("/"),
    },
    roundtrip: "",
  },
  // host subcomponent; IPv6 address with zone identifier in RFC 6874
  {
    input: "http://[fe80::1%25%65%6e%301-._~]/", // percent-encoded+unreserved zone identifier
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1%en01-._~]"),
      path: Some("/"),
    },
    roundtrip: "http://[fe80::1%25en01-._~]/",
  },
  // host and port subcomponents; IPv6 address with zone identifier in RFC 6874
  {
    input: "http://[fe80::1%25%65%6e%301-._~]:8080/", // percent-encoded+unreserved zone identifier
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[fe80::1%en01-._~]:8080"),
      path: Some("/"),
    },
    roundtrip: "http://[fe80::1%25en01-._~]:8080/",
  },
  // alternate escapings of path survive round trip
  {
    input: "http://rest.rsc.io/foo%2fbar/baz%2Fquux?alt=media",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("rest.rsc.io"),
      path: Some("/foo%2fbar/baz%2Fquux"),
      query: Some("alt=media"),
    },
    roundtrip: "",
  },
  // issue 12036
  {
    input: "mysql://a,b,c/bar",
    out: {
      ..empty_url,
      scheme: Some("mysql"),
      host: Some("a,b,c"),
      path: Some("/bar"),
    },
    roundtrip: "",
  },
  // worst case host, still round trips
  {
    input: "scheme://!$&'()*+,;=hello!:1/path",
    out: {
      ..empty_url,
      scheme: Some("scheme"),
      host: Some("!$&'()*+,;=hello!:1"),
      path: Some("/path"),
    },
    roundtrip: "",
  },
  // worst case path, still round trips
  {
    input: "http://host/!$&'()*+,;=:@[hello]",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("host"),
      path: Some("/!$&'()*+,;=:@[hello]"),
    },
    roundtrip: "",
  },
  // golang.org/issue/5684
  {
    input: "http://example.com/oid/[order_id]",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("example.com"),
      path: Some("/oid/[order_id]"),
    },
    roundtrip: "",
  },
  // golang.org/issue/12200 (colon with empty port)
  {
    input: "http://192.168.0.2:8080/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("192.168.0.2:8080"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  {
    input: "http://192.168.0.2:/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("192.168.0.2:"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  {
    // Malformed IPv6 but still accepted.
    input: "http://2b01:e34:ef40:7730:8e70:5aff:fefe:edac:8080/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("2b01:e34:ef40:7730:8e70:5aff:fefe:edac:8080"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  {
    // Malformed IPv6 but still accepted.
    input: "http://2b01:e34:ef40:7730:8e70:5aff:fefe:edac:/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("2b01:e34:ef40:7730:8e70:5aff:fefe:edac:"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  {
    input: "http://[2b01:e34:ef40:7730:8e70:5aff:fefe:edac]:8080/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[2b01:e34:ef40:7730:8e70:5aff:fefe:edac]:8080"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  {
    input: "http://[2b01:e34:ef40:7730:8e70:5aff:fefe:edac]:/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("[2b01:e34:ef40:7730:8e70:5aff:fefe:edac]:"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  // golang.org/issue/7991 and golang.org/issue/12719 (non-ascii %-encoded in host)
  {
    input: "http://hello.世界.com/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("hello.世界.com"),
      path: Some("/foo"),
    },
    roundtrip: "http://hello.%E4%B8%96%E7%95%8C.com/foo",
  },
  {
    input: "http://hello.%e4%b8%96%e7%95%8c.com/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("hello.世界.com"),
      path: Some("/foo"),
    },
    roundtrip: "http://hello.%E4%B8%96%E7%95%8C.com/foo",
  },
  {
    input: "http://hello.%E4%B8%96%E7%95%8C.com/foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("hello.世界.com"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  // golang.org/issue/10433 (path beginning with //)
  {
    input: "http://example.com//foo",
    out: {
      ..empty_url,
      scheme: Some("http"),
      host: Some("example.com"),
      path: Some("//foo"),
    },
    roundtrip: "",
  },
  // test that we can reparse the host names we accept.
  {
    input: "myscheme://authority<\"hi\">/foo",
    out: {
      ..empty_url,
      scheme: Some("myscheme"),
      host: Some("authority<\"hi\">"),
      path: Some("/foo"),
    },
    roundtrip: "",
  },
  // spaces in hosts are disallowed but escaped spaces in IPv6 scope IDs are grudgingly OK.
  // This happens on Windows.
  // golang.org/issue/14002
  {
    input: "tcp://[2020::2020:20:2020:2020%25Windows%20Loves%20Spaces]:2020",
    out: {
      ..empty_url,
      scheme: Some("tcp"),
      host: Some("[2020::2020:20:2020:2020%Windows Loves Spaces]:2020"),
    },
    roundtrip: "",
  },
  // test we can roundtrip magnet url
  // fix issue https://golang.org/issue/20054
  {
    input: "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn",
    out: {
      ..empty_url,
      scheme: Some("magnet"),
      opaque_str: Some(""),
      query: Some("xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn"),
    },
    roundtrip: "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335aa7c1367a88a&dn",
  },
  {
    input: "mailto:?subject=hi",
    out: {
      ..empty_url,
      scheme: Some("mailto"),
      opaque_str: Some(""),
      query: Some("subject=hi"),
    },
    roundtrip: "mailto:?subject=hi",
  },
]
