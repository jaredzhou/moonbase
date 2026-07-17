/// A representation of a URL.
/// See https://tools.ietf.org/html/rfc3986
/// for more details. 
/// 
///URI         = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
///hier-part   = "//" authority path-abempty
///              / path-absolute
///              / path-rootless
///              / path-empty
/// 
///relative-ref  = relative-part [ "?" query ] [ "#" fragment ]
///relative-part = "//" authority path-abempty
///                / path-absolute
///                / path-noscheme
///                / path-empty
///
///authority     = [ userinfo "@" ] host [ ":" port ]
///userinfo      = *( unreserved / pct-encoded / sub-delims / ":" )
///host          = IP-literal / IPv4address / reg-name
///port          = *DIGIT
///IP-literal    = "[" ( IPv6address / IPvFuture ) "]"
///reg-name      = *( unreserved / pct-encoded / sub-delims )
///
///path-abempty  = *( "/" segment )
///path-absolute = "/" [ segment-nz *( "/" segment ) ]
///path-rootless = segment-nz *( "/" segment )
///path-noscheme = segment-nz-nc *( "/" segment )
///path-empty    = 0*pchar
///segment       = *pchar
///segment-nz    = 1*pchar
///segment-nz-nc = 1*( unreserved / pct-encoded / sub-delims / "@" )
///
///pchar         = unreserved / pct-encoded / sub-delims / ":" / "@"
///unreserved    = ALPHA / DIGIT / "-" / "." / "_" / "~"
///reserved      = gen-delims / sub-delims
///gen-delims    = ":" / "/" / "?" / "#" / "[" / "]" / "@"
///sub-delims    = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
///pct-encoded   = "%" HEXDIG HEXDIG

///|
///A representation of a URI reference
///
///The general form represented is:
///
///	[scheme:][//[userinfo@]host][/]path[?query][#fragment]
///
/// URLs that do not start with a slash after the scheme are interpreted as:
///
///	scheme:opaque[?query][#fragment] 
pub(all) struct URL {
  scheme : String?
  opaque_str : String?
  user_info : UserInfo?
  host : String?
  path : String?
  query : String?
  fragment : String?
} derive(Eq, Debug)

///|
pub impl Show for URL with fn to_string(self : URL) -> String {
  let builder = StringBuilder::new()
  if self.scheme is Some(scheme) {
    builder..write_string(scheme).write_string(":")
  }
  if self.opaque_str is Some(opaque_str) {
    builder.write_string(opaque_str)
  } else {
    if self.host is Some(host) {
      builder.write_string("//")
      if self.user_info is Some(userinfo) {
        builder.write_string(escape(userinfo.username, EncodeUserPassword))
        if userinfo.password is Some(password) {
          builder
          ..write_string(":")
          .write_string(escape(password, EncodeUserPassword))
        }
        builder.write_string("@")
      }
      builder.write_string(escape(host, EncodeHost))
    }
    if self.path is Some(path) {
      builder.write_string(escape(path, EncodePath))
    }
  }
  if self.query is Some(query) {
    // Like Go's net/url: RawQuery is appended as-is.
    // Escaping '='/'&'/'?' here would corrupt query structure.
    builder..write_string("?").write_string(query)
  }
  if self.fragment is Some(fragment) {
    builder..write_string("#").write_string(escape(fragment, EncodeFragment))
  }
  builder.to_string()
}

///|
pub let empty_url : URL = URL::{
  scheme: None,
  opaque_str: None,
  user_info: None,
  host: None,
  path: None,
  query: None,
  fragment: None,
}

///|
pub(all) struct UserInfo {
  username : String
  password : String?
} derive(Eq, Debug)

///|
pub impl Show for UserInfo with fn to_string(self : UserInfo) -> String {
  let builder = StringBuilder::new()
  builder.write_string(self.username)
  if self.password is Some(password) {
    builder..write_string(":").write_string(password)
  }
  builder.to_string()
}

///|
pub suberror URLParseError {
  URLParseError(String)
} derive(Debug)

///|
pub fn parse(url_str : String) -> URL raise URLParseError {
  guard url_str.length() > 0 else { raise URLParseError("URL string is empty") }
  let url_str = url_str.to_string_view()
  guard !containsAsciiControl(url_str) else {
    raise URLParseError("URL contains ASCII control characters")
  }
  if url_str == "*" {
    return { ..empty_url, path: Some("*") }
  }
  let (scheme, rest) = parse_scheme(url_str)
  //there may be only one "#" in the URL, so just cut by first "#" 
  let (rest, fragment) = if rest.find("#") is Some(index) {
    let frag_str = rest.sub(start=index + 1)
    let decoded_frag = unescape(frag_str, EncodeFragment)
    (rest.sub(start=0, end=index), Some(decoded_frag))
  } else {
    (rest, None)
  }
  //there is no '?' before query, so just cut by first "?"
  let (rest, query) = if rest.find("?") is Some(index) {
    let query_str = rest.sub(start=index + 1)
    let query = if query_str.length() == 0 {
      None
    } else {
      Some(query_str.to_owned())
    }
    (rest.sub(start=0, end=index), query)
  } else {
    (rest, None)
  }
  let (user_info, host, rest) : (UserInfo?, String?, StringView) = match
    (scheme, rest) {
    // if it has scheme and starting with '//' it has authority component
    (Some(_), [.. "//", .. rest]) => parse_authority(rest)
    // if it has scheme and starting with '/',  it is non-authority with path
    (Some(_), ['/', ..]) => (None, None, rest)
    // if it has scheme and starting without '/' and it is opaque URL
    (Some(_), _) =>
      return {
        ..empty_url,
        scheme,
        opaque_str: Some(rest.to_owned()),
        query,
        fragment,
      }
    // otherwise it is a relative URL
    (None, rest) =>
      match rest {
        // start with "//" is with authority
        // but start with "///"  is just a path
        [.. "//", .. r] if !(rest is [.. "///", ..]) => parse_authority(r)
        rest => {
          // Avoid confusion with malformed schemes, like cache_object:foo/bar.
          // See golang.org/issue/16822.
          //
          // RFC 3986, §3.3:
          // In addition, a URI reference (Section 4.1) may be a relative-path reference,
          // in which case the first path segment cannot contain a colon (":") character.
          let segment = if rest.find("/") is Some(index) {
            rest.sub(start=0, end=index)
          } else {
            rest
          }
          if segment.contains(":") {
            raise URLParseError(
              "relative URL path's first path segment cannot contains colon",
            )
          }
          (None, None, rest)
        }
      }
  }
  let path = if rest.length() > 0 {
    Some(unescape(rest, EncodePath))
  } else {
    None
  }
  { scheme, opaque_str: None, user_info, host, path, query, fragment }
}

///|
pub fn parse_request_uri(uri_str : String) -> URL raise URLParseError {
  let url = parse(uri_str)
  // absolute-form for proxy request
  //authority-form is not allowed
  if url.scheme is Some(_) && url.host is Some(_) {
    return url
  }

  // opaque form is not allowed
  if url.opaque_str is Some(_) {
    raise URLParseError("invalid request URI: opaque form not allowed")
  }

  // origin-form: /path[?query]
  // asterisk-form: * for OPTIONS request
  if url.path is Some(path) {
    guard path == "*" || path is ['/', ..] else {
      raise URLParseError(
        "invalid request URI: non-absolute-form must start with '/' or be '*'",
      )
    }
  }
  url
}

///|
/// query_escape escapes the string so it can be safely placed
/// inside a URL query.
pub fn query_escape(s : String) -> String {
  escape(s.to_string_view(), EncodeQueryComponent)
}

///|
/// query_unescape does the inverse transformation of [query_escape],
/// converting each 3-byte encoded substring of the form "%AB" into the
/// hex-decoded byte 0xAB.
/// It returns an error if any % is not followed by two hexadecimal
/// digits.
pub fn query_unescape(s : String) -> String raise URLParseError {
  unescape(s.to_string_view(), EncodeQueryComponent)
}

///|
/// path_segment_escape escapes the string so it can be safely placed
/// inside a URL path segment.
/// replacing special characters (including /) with %XX sequences as needed. 
pub fn path_segment_escape(s : String) -> String {
  escape(s.to_string_view(), EncodePathSegment)
}

///|
/// path_segment_unescape does the inverse transformation of [path_segment_escape],
/// converting each 3-byte encoded substring of the form "%AB" into the 
/// hex-decoded byte 0xAB. It returns an error if any % is not followed
/// by two hexadecimal digits.
///
/// path_segment_unescape is identical to [query_unescape] except that it does not
/// unescape '+' to ' ' (space).
pub fn path_segment_unescape(s : String) -> String raise URLParseError {
  return unescape(s, EncodePathSegment)
}

///|
fn parse_authority(
  rest : StringView,
) -> (UserInfo?, String?, StringView) raise URLParseError {
  let (auth, rest) = if rest.find("/") is Some(index) {
    (rest.sub(start=0, end=index), rest.sub(start=index))
  } else {
    (rest, "".to_string_view())
  }
  let (userInfo, host) = if auth.rev_find("@") is Some(index) {
    let userinfo_str = auth.sub(start=0, end=index)
    let host_str = auth.sub(start=index + 1)
    (Some(parse_userinfo(userinfo_str)), parse_host(host_str))
  } else {
    (None, parse_host(auth))
  }
  (userInfo, host, rest)
}

///|
fn parse_host(host_str : StringView) -> String? raise URLParseError {
  guard host_str.length() > 0 else { return Some("") }
  match host_str {
    ['[', ..] => {
      // Parse an IP-Literal in RFC 3986 and RFC 6874.
      // E.g., "[fe80::1]", "[fe80::1%25en0]", "[fe80::1]:80".
      let index = host_str.rev_find("]")
      guard index is Some(idx) else {
        raise URLParseError(
          "invalid IP literal address: missing ']' in \{host_str} ",
        )
      }
      let colonPort = host_str.sub(start=idx + 1)
      if !validOptionalPort(colonPort) {
        raise URLParseError("invalid port in IP literal address: \{host_str} ")
      }
      // RFC 6874 defines that %25 (%-encoded percent) introduces
      // the zone identifier, and the zone identifier can use basically
      // any %-encoding it likes. That's different from the host, which
      // can only %-encode non-ASCII bytes.
      // We do impose some restrictions on the zone, to avoid stupidity
      // like newlines.
      let ip = host_str.sub(start=0, end=idx)
      let zoneIndex = ip.find("%25")
      if zoneIndex is Some(zidx) {
        let host = unescape(ip.sub(start=0, end=zidx), EncodeHost)
        let zone = unescape(ip.sub(start=zidx), EncodeZone)
        let port = unescape(colonPort, EncodeHost) // includes ']'
        return Some(host + zone + "]" + port)
      }
    }
    _ => {
      let colonIndex = host_str.rev_find(":")
      if colonIndex is Some(index) {
        let port_str = host_str.sub(start=index)
        if !validOptionalPort(port_str) {
          raise URLParseError("invalid port in host: \{host_str} ")
        }
      }
    }
  }
  Some(unescape(host_str, EncodeHost))
}

///|
fn parse_userinfo(userinfo_str : StringView) -> UserInfo raise URLParseError {
  if !validUserinfo(userinfo_str) {
    raise URLParseError("invalid userinfo string: \{userinfo_str} ")
  }
  if userinfo_str.find(":") is Some(index) {
    let username = userinfo_str.sub(start=0, end=index)
    let password = userinfo_str.sub(start=index + 1)
    let username = unescape(username, EncodeUserPassword)
    let password = unescape(password, EncodeUserPassword)
    UserInfo::{ username, password: Some(password) }
  } else {
    let username = unescape(userinfo_str, EncodeUserPassword)
    UserInfo::{ username, password: None }
  }
}
// Parse the scheme from the URL string.
// scheme must be [a-zA-Z][a-zA-Z0-9+.-]*
// if scheme is found, it is set in the URL struct.
// else scheme is left as None.
// The rest of the URL string is returned.

///|
fn parse_scheme(
  url_str : StringView,
) -> (String?, StringView) raise URLParseError {
  // must start with a letter
  guard url_str is ['a'..<'z' | 'A'..<'Z', .. rest] else {
    if url_str is [':', ..] {
      //  missing protocol scheme 
      raise URLParseError("missing protocol scheme")
    } else {
      return (None, url_str)
    }
  }
  let mut sindex = 1
  for s = rest {
    if s is ['a'..='z' | 'A'..<'Z' | '0'..='9' | '+' | '-' | '.', .. rest] {
      sindex += 1
      continue rest
    } else if s is [':', .. rest] {
      let scheme = url_str.sub(start=0, end=sindex).to_owned()
      break (Some(scheme.to_lower()), rest)
    } else {
      break (None, url_str)
    }
  }
}

///|
fn containsAsciiControl(s : StringView) -> Bool {
  for b in s {
    if b < '\u001F' || b == '\u007F' {
      return true
    }
  }
  false
}

///|
enum Encoding {
  EncodePath
  EncodePathSegment
  EncodeHost
  EncodeZone
  EncodeUserPassword
  EncodeQueryComponent
  EncodeFragment
} derive(Eq)

///|
fn ishex(c : Char) -> Bool {
  match c {
    '0'..='9' | 'a'..='f' | 'A'..='F' => true
    _ => false
  }
}

///|
fn unhex(c : Char) -> Byte {
  match c {
    '0'..='9' => (c.to_int() - '0'.to_int()).to_byte()
    'a'..='f' => (c.to_int() - 'a'.to_int() + 10).to_byte()
    'A'..='F' => (c.to_int() - 'A'.to_int() + 10).to_byte()
    _ => 0
  }
}

// Return true if the specified character should be escaped when
// appearing in a URL string, according to RFC 3986.
//
// Please be informed that for now shouldEscape does not check all
// reserved characters correctly. See golang.org/issue/5684.

///|
fn shouldEscape(c : Char, mode : Encoding) -> Bool {
  // §2.3 Unreserved characters (alphanum)
  if c is ('a'..='z' | 'A'..='Z' | '0'..='9') {
    return false
  }
  if mode == EncodeHost || mode == EncodeZone {
    // §3.2.2 Host allows
    //	sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="
    // as part of reg-name.
    // We add : because we include :port as part of host.
    // We add [ ] because we include [ipv6]:port as part of host.
    // We add < > because they're the only characters left that
    // we could possibly allow, and Parse will reject them if we
    // escape them (because hosts can't use %-encoding for
    // ASCII bytes).
    if c
      is ('!'
      | '$'
      | '&'
      | '\''
      | '('
      | ')'
      | '*'
      | '+'
      | ','
      | ';'
      | '='
      | ':'
      | '['
      | ']'
      | '<'
      | '>'
      | '"') {
      return false
    }
  }
  if mode == EncodePath {
    if c is ('!' | '\'' | '(' | ')' | '*' | '[' | ']') {
      return false
    }
  }
  match c {
    '-' | '_' | '.' | '~' => return false // §2.3 Unreserved characters (mark) -, _, ., ~
    '$' | '&' | '+' | ',' | '/' | ':' | ';' | '=' | '?' | '@' => // §2.2 Reserved characters (reserved)
      // Different sections of the URL allow a few of
      // the reserved characters to appear unescaped.
      match mode {
        EncodePath => return c == '?'
        EncodePathSegment => return c == '/' || c == ';' || c == ',' || c == '?'
        EncodeUserPassword =>
          return c == '@' || c == '/' || c == '?' || c == ':'
        EncodeQueryComponent => return true
        EncodeFragment => return false
        _ => ()
      }
    _ => ()
  }
  if mode == EncodeFragment {
    // RFC 3986 §2.2 allows not escaping sub-delims. A subset of sub-delims are
    // included in reserved from RFC 2396 §2.2. The remaining sub-delims do not
    // need to be escaped. To minimize potential breakage, we apply two restrictions:
    // (1) we always escape sub-delims outside of the fragment, and (2) we always
    // escape single quote to avoid breaking callers that had previously assumed that
    // single quotes would be escaped. See issue #19917.
    if c is ('!' | '(' | ')' | '*') {
      return false
    }
  }

  // Everything else must be escaped.
  true
}

///|
pub fn escape(s : StringView, mode : Encoding) -> String {
  let mut spaceCount = 0
  let mut hexCount = 0
  for s = s {
    match s {
      [.. "%2f", .. rest] | [.. "%2F", .. rest] if mode == EncodePath =>
        continue rest
      [c, .. rest] => {
        if shouldEscape(c, mode) {
          if c == ' ' && mode == EncodeQueryComponent {
            spaceCount += 1
          } else {
            hexCount += 1
          }
        }
        continue rest
      }
      [] => break
    }
  }
  // Short circuit if nothing to escape
  if spaceCount == 0 && hexCount == 0 {
    return s.to_owned()
  }
  let required = s.length() + 2 * hexCount + 2 * spaceCount
  let t = StringBuilder::new(size_hint=required)
  for s = s {
    match s {
      ['%', '2', f, .. rest] if mode == EncodePath && (f == 'f' || f == 'F') => {
        t.write_string("%2")
        t.write_char(f)
        continue rest
      }
      [c, .. rest] if shouldEscape(c, mode) => {
        let utf8_bytes = @encoding/utf8.encode(String::from_array([c]))
        for b in utf8_bytes {
          t.write_char('%')
          t.write_char(upperhex[(b >> 4).to_int()])
          t.write_char(upperhex[(b & 15).to_int()])
        }
        continue rest
      }
      [c, .. rest] => {
        t.write_char(c)
        continue rest
      }
      [] => break
    }
  }
  t.to_string()
}

///|
let upperhex : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
]

///|
// unescape unescape a string; the mode specifies which section of the URL string is being unescaped.
// These characters need to be parsed into UTF-8 bytes and then decoded into a string,
// because percent-encoding for non-ASCII characters uses UTF-8 byte sequences.
// Percent-encoded bytes cannot be treated as individual characters directly.
fn unescape(s : StringView, mode : Encoding) -> String raise URLParseError {
  let buf = Buffer(size_hint=s.length())
  for s = s {
    match s {
      ['%', .. rest] => {
        guard rest is [c1, c2, .. rest] else {
          raise URLParseError("invalid URL escape: \{s}")
        }
        if !ishex(c1) || !ishex(c2) {
          raise URLParseError("invalid URL escape: \{s}")
        }
        let escaped = String::from_array(['%', c1, c2])
        // escaped '/' in path just keep it escaped
        // otherwise you can't distinguish it from path separator
        if (escaped == "%2f" || escaped == "%2F") && mode == EncodePath {
          buf.write_string_utf8(escaped)
          continue rest
        }
        // Per https://tools.ietf.org/html/rfc3986#page-21
        // in the host component %-encoding can only be used
        // for non-ASCII bytes.
        // But https://tools.ietf.org/html/rfc6874#section-2
        // introduces %25 being allowed to escape a percent sign
        // in IPv6 scoped-address literals. Yay.
        if mode == EncodeHost && unhex(c1) < 8 && escaped != "%25" {
          raise URLParseError("invalid URL escape in host component: \{s} ")
        }
        // RFC 6874 says basically "anything goes" for zone identifiers
        // and that even non-ASCII can be redundantly escaped,
        // but it seems prudent to restrict %-escaped bytes here to those
        // that are valid host name bytes in their unescaped form.
        // That is, you can use escaping in the zone identifier but not
        // to introduce bytes you couldn't just write directly.
        // But Windows puts spaces here! Yay.
        let v = (unhex(c1) << 4) | unhex(c2)
        if mode == EncodeZone {
          if escaped != "%25" &&
            v != b' ' &&
            shouldEscape(v.to_char(), EncodeHost) {
            raise URLParseError("invalid URL escape in zone identifier: \{s} ")
          }
        }
        buf.write_byte(v)
        continue rest
      }
      ['+', .. rest] => {
        if mode == EncodeQueryComponent {
          buf.write_char_utf8(' ')
        } else {
          buf.write_char_utf8('+')
        }
        continue rest
      }
      [c, .. rest] => {
        if (mode == EncodeHost || mode == EncodeZone) &&
          c < '\u0080' &&
          shouldEscape(c, mode) {
          raise URLParseError(
            "invalid character in host or zone identifier: \{s} ",
          )
        }
        buf.write_char_utf8(c)
        continue rest
      }
      [] => break
    }
  }
  @encoding/utf8.decode(buf.to_bytes()) catch {
    _ => raise URLParseError("invalid UTF-8 encoding in URL: \{s} ")
  }
}

// validUserinfo reports whether s is a valid userinfo string per RFC 3986
// Section 3.2.1:
//
//	userinfo    = *( unreserved / pct-encoded / sub-delims / ":" )
//	unreserved  = ALPHA / DIGIT / "-" / "." / "_" / "~"
//	sub-delims  = "!" / "$" / "&" / "'" / "(" / ")"
//	              / "*" / "+" / "," / ";" / "="
//
// It doesn't validate pct-encoded. The caller does that via func unescape.

///|
fn validUserinfo(s : StringView) -> Bool {
  for s = s {
    match s {
      [
        'a'..='z'
        | 'A'..='Z'
        | '0'..='9'
        | '-'
        | '.'
        | '_'
        | ':'
        | '~'
        | '!'
        | '$'
        | '&'
        | '\''
        | '('
        | ')'
        | '*'
        | '+'
        | ','
        | ';'
        | '='
        | '%'
        | '@',
        .. rest,
      ] => continue rest
      [_, ..] => return false
      [] => return true
    }
  }
}

///|
fn validOptionalPort(port : StringView) -> Bool {
  if port.length() == 0 {
    return true
  }
  guard port is [':', .. port] else { return false }
  for c in port {
    if !(c is ('0'..='9')) {
      return false
    }
  }
  true
}
