///|
/// A parsed or newly-created JWT token.
pub(all) struct Token {
  mut raw : String?
  mut header : Map[String, Json]
  mut claims : Json
  mut sig_method : SigningMethod
  mut signature : Bytes?
  mut valid : Bool
}

///|
/// Create a new Token with the given signing method and claims.
pub fn Token::Token(sig_method : SigningMethod, claims : Json) -> Token {
  {
    raw: None,
    header: build_header(sig_method.alg()),
    claims,
    sig_method,
    signature: None,
    valid: false,
  }
}

///|
/// Sign the token and produce the compact JWT string
/// in `header.payload.signature` format.
pub fn signed_string(token : Token) -> String {
  let header_str = Json::object(token.header).stringify()
  let header_enc = @base64.encode(
    @encoding/utf8.encode(header_str),
    url_safe=true,
  )

  let claims_str = token.claims.stringify()
  let claims_enc = @base64.encode(
    @encoding/utf8.encode(claims_str),
    url_safe=true,
  )

  let signing_input = header_enc + "." + claims_enc
  let sig_bytes = token.sig_method.sign(signing_input)
  let sig_enc = @base64.encode(sig_bytes, url_safe=true)

  header_enc + "." + claims_enc + "." + sig_enc
}

///|
/// Sign claims with the given signing method and produce the compact JWT string.
pub fn sign(sig_method : SigningMethod, claims : Json) -> String {
  signed_string(Token::Token(sig_method, claims))
}

///|
/// Parse a JWT token string without signature verification.
pub fn parse_unverified(token_string : String) -> Token raise JwtError {
  Parser::Parser().parse_unverified(token_string)
}

///|
/// Parse and verify a JWT token with the given signing method.
pub fn[C : Claims] parse(
  token_string : String,
  sig_method : SigningMethod,
) -> (Token, C) raise JwtError {
  Parser::Parser()
    .register(sig_method)
    .parse(token_string)
}

///|
/// Parse and verify a JWT token with multiple accepted signing methods.
/// The parser will use the method matching the token's `alg` header.
pub fn[C : Claims] parse_with(
  token_string : String,
  methods : Array[SigningMethod],
) -> (Token, C) raise JwtError {
  let mut parser = Parser::Parser()
  for m in methods {
    parser = parser.register(m)
  }
  parser.parse(token_string)
}

///|
/// Build the JWT header JSON map for a given algorithm.
fn build_header(alg : String) -> Map[String, Json] {
  let header : Map[String, Json] = {}
  header["alg"] = Json::string(alg)
  header["typ"] = Json::string("JWT")
  header
}
