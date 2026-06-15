///|
/// A parsed or newly-created JWT token.
pub(all) struct Token {
  mut raw: String?
  mut header: Map[String, Json]
  mut claims: Json
  mut method: SigningMethod
  mut signature: Bytes?
  mut valid: Bool
}

///|
/// Create a new Token with the given signing method and claims.
pub fn Token::Token(
  method : SigningMethod,
  claims : Json,
) -> Token {
  {
    raw: None,
    header: build_header(method.alg()),
    claims,
    method,
    signature: None,
    valid: false,
  }
}

///|
/// Sign the token and produce the compact JWT string
/// in `header.payload.signature` format.
pub fn signed_string(token : Token) -> String raise JwtError {
  let header_str = Json::object(token.header).stringify()
  let header_enc = @base64.encode(header_str.to_bytes(), url_safe=true)

  let claims_str = token.claims.stringify()
  let claims_enc = @base64.encode(claims_str.to_bytes(), url_safe=true)

  let signing_input = header_enc + "." + claims_enc
  let sig_bytes = token.method.sign(signing_input)
  let sig_enc = @base64.encode(sig_bytes, url_safe=true)

  header_enc + "." + claims_enc + "." + sig_enc
}

///|
/// Parse a JWT token string without signature verification.
pub fn parse_unverified(token_string : String) -> Token raise JwtError {
  let parts_iter = token_string.split(".")
  let parts: Array[String] = []
  for p in parts_iter {
    parts.push(p.to_string())
  }
  if parts.length() != 3 {
    raise MalformedToken("token must have exactly 3 dot-separated parts")
  }
  let header_part = parts[0]
  let claims_part = parts[1]
  let sig_part = parts[2]

  let header_bytes = @base64.decode(header_part, url_safe=true) catch {
    _ => raise MalformedToken("invalid base64url in header")
  }
  let header_str = header_bytes.to_string()
  let header_json = @json.parse(header_str) catch {
    _ => raise MalformedToken("invalid JSON in header")
  }
  let header = match header_json {
    Json::Object(m) => m
    _ => raise MalformedToken("header must be a JSON object")
  }

  let claims_bytes = @base64.decode(claims_part, url_safe=true) catch {
    _ => raise MalformedToken("invalid base64url in payload")
  }
  let claims_str = claims_bytes.to_string()
  let claims = @json.parse(claims_str) catch {
    _ => raise MalformedToken("invalid JSON in payload")
  }

  let sig_bytes = @base64.decode(sig_part, url_safe=true) catch {
    _ => raise MalformedToken("invalid base64url in signature")
  }

  {
    raw: Some(token_string),
    header,
    claims,
    method: HMACSHA256(b""),
    signature: Some(sig_bytes),
    valid: false,
  }
}

///|
/// Build the JWT header JSON map for a given algorithm.
fn build_header(alg : String) -> Map[String, Json] {
  let header : Map[String, Json] = {}
  header["alg"] = Json::string(alg)
  header["typ"] = Json::string("JWT")
  header
}
