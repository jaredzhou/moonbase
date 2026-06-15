///|
/// Parser holds configuration for JWT token parsing and validation.
pub(all) struct Parser {
  mut methods : Map[String, SigningMethod]
  mut leeway : Int64
  mut skip_claims_validation : Bool
}

///|
/// Create a new Parser with default settings.
pub fn Parser::Parser() -> Parser {
  {
    methods: {},
    leeway: 0L,
    skip_claims_validation: false,
  }
}

///|
/// Register a signing method for verification.
/// The method's alg() value is used as the key in the internal registry.
/// Returns self for chaining.
pub fn Parser::register(
  self : Parser,
  method : SigningMethod,
) -> Parser {
  self.methods[method.alg()] = method
  self
}

///|
/// Set the clock skew leeway in seconds.
pub fn Parser::with_leeway(self : Parser, leeway : Int64) -> Parser {
  self.leeway = leeway
  self
}

///|
/// Skip claims validation (exp, nbf checks).
pub fn Parser::without_claims_validation(self : Parser) -> Parser {
  self.skip_claims_validation = true
  self
}

///|
/// Parse and validate a JWT token string.
/// The algorithm is read from the JWT header; the parser looks up
/// the corresponding SigningMethod in its registry for verification.
/// The provided claims object is populated from the token payload.
pub fn Parser::parse[C : Claims](
  self : Parser,
  token_string : String,
  claims : C,
) -> Token raise JwtError {
  // Split token into 3 parts
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

  // Decode header
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

  // Extract algorithm from header
  let alg = match header.get("alg") {
    Some(Json::String(a)) => a
    _ => raise MalformedToken("missing or invalid alg in header")
  }

  // Look up registered signing method
  let method = match self.methods.get(alg) {
    Some(m) => m
    None => raise InvalidAlgorithm("no registered method for \{alg}")
  }

  // Verify signature
  let signing_input = header_part + "." + claims_part
  let sig_bytes = @base64.decode(sig_part, url_safe=true) catch {
    _ => raise MalformedToken("invalid base64url in signature")
  }
  method.verify(signing_input, sig_bytes)

  // Decode and deserialize claims
  let claims_bytes = @base64.decode(claims_part, url_safe=true) catch {
    _ => raise MalformedToken("invalid base64url in payload")
  }
  let claims_str = claims_bytes.to_string()
  let claims_json = @json.parse(claims_str) catch {
    _ => raise MalformedToken("invalid JSON in payload")
  }
  let parsed_claims = claims.from_json(claims_json)

  // Validate claims
  if !self.skip_claims_validation {
    parsed_claims.validate(self.leeway)
  }

  {
    raw: Some(token_string),
    header,
    claims: claims_json,
    method,
    signature: Some(sig_bytes),
    valid: true,
  }
}
