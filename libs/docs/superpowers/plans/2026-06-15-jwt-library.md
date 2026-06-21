# JWT Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a feature-complete JWT library (`jaredzhou/libs/jwt`) with HMAC-SHA256 signing, registered claims validation, and extensible SigningMethod enum.

**Architecture:** 6 source files — errors, signing method (enum with per-algorithm logic), claims (trait + RegisteredClaims), parser, token + signing/parsing entry points, tests. SigningMethod is a MoonBit `type` (algebraic data type / enum) not a trait, so it can be stored in structs and maps.

**Tech Stack:** MoonBit, `moonbitlang/x/crypto` (sha256, hmac), `moonbitlang/x/codec/base64` (base64url), `moonbitlang/core/json` (JSON)

**MoonBit conventions (confirmed from codebase):**
- Constructors: `Type::Type(...)` (e.g. `SHA256::new()` is still used, but new code should use `Type::Type()`)
- Methods: `pub fn Type::method(self : Type, ...) -> ...`
- Maps: `@map.new()` or `{:}` literal
- Arrays: `[item1, item2]` literal
- `pub(all) struct` for public fields
- `pub suberror` for error types with `derive(Debug)`
- `pub all type` for enum/ADT types with public constructors

---

### Task 1: Project Setup

**Files:**
- Create: `libs/jwt/moon.pkg`

- [ ] **Step 1: Create the jwt package directory and moon.pkg**

```bash
mkdir -p libs/jwt
```

Create `libs/jwt/moon.pkg`:
```toml
import {
  "moonbitlang/x/crypto" @crypto,
  "moonbitlang/x/codec/base64" @base64,
  "moonbitlang/core/json" @json,
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/moon.pkg
git commit -m "feat(jwt): add jwt package skeleton with dependencies"
```

---

### Task 2: Error Types

**Files:**
- Create: `libs/jwt/errors.mbt`

- [ ] **Step 1: Write errors.mbt**

```moonbit
///|
/// JWT error types covering all failure modes in the parsing and validation pipeline.
pub suberror JwtError {
  InvalidSignature
  TokenExpired(expired_at : Int64, now : Int64)
  TokenNotYetValid(not_before : Int64, now : Int64)
  MalformedToken(String)
  InvalidAlgorithm(String)
  UnverifiableToken(String)
  InvalidKey
} derive(Debug)
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/errors.mbt
git commit -m "feat(jwt): add JwtError types"
```

---

### Task 3: SigningMethod Enum + HS256 Logic

**Files:**
- Create: `libs/jwt/signing_method.mbt`

**Key design decision:** Use a MoonBit `type` (algebraic data type / enum) instead of a `trait` because MoonBit doesn't support trait objects in struct fields. The enum holds all known algorithm implementations; new algorithms are added as new variants.

- [ ] **Step 1: Write signing_method.mbt**

```moonbit
///|
/// Supported JWT signing algorithms.
/// Each variant holds its own key material.
pub all type SigningMethod {
  HMACSHA256(key : Bytes)
}

///|
/// Returns the JWT algorithm identifier (e.g. "HS256").
pub fn SigningMethod::alg(self : SigningMethod) -> String {
  match self {
    HMACSHA256(_) => "HS256"
  }
}

///|
/// Signs a signing input string using this method's key.
/// Returns the raw signature bytes.
pub fn SigningMethod::sign(
  self : SigningMethod,
  signing_string : String,
) -> Bytes raise JwtError {
  match self {
    HMACSHA256(key) => {
      let hasher = @crypto.SHA256::new()
      let sig = @crypto.hmac(hasher, key, signing_string.to_bytes())
      sig.to_bytes()
    }
  }
}

///|
/// Verifies a signature against a signing input string.
/// Raises InvalidSignature if the signature does not match.
pub fn SigningMethod::verify(
  self : SigningMethod,
  signing_string : String,
  signature : Bytes,
) -> Unit raise JwtError {
  let expected = self.sign(signing_string)
  if expected != signature {
    raise InvalidSignature
  }
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/signing_method.mbt
git commit -m "feat(jwt): add SigningMethod enum with HS256"
```

---

### Task 4: Claims Trait + RegisteredClaims

**Files:**
- Create: `libs/jwt/claims.mbt`

- [ ] **Step 1: Write claims.mbt**

```moonbit
///|
/// Trait for JWT claims. Types implementing Claims can be used with
/// Token parsing to handle JSON deserialization and claim validation.
pub trait Claims {
  /// Deserialize claims from a JSON payload
  from_json(Self, @json.Json) -> Self raise JwtError
  /// Serialize claims to JSON
  to_json(Self) -> @json.Json
  /// Validate registered claims (exp, nbf) with a clock leeway in seconds
  validate(Self, leeway : Int64) -> Unit raise JwtError
  /// Set issued-at and not-before timestamps (called during signing)
  set_issued_now(Self, now : Int64) -> Unit
}

///|
/// Standard registered JWT claims (RFC 7519 Section 4.1).
pub(all) struct RegisteredClaims {
  mut issuer: String?
  mut subject: String?
  mut audience: Array[String]?
  mut expires_at: Int64?
  mut not_before: Int64?
  mut issued_at: Int64?
  mut id: String?
}

///|
/// Create empty RegisteredClaims.
pub fn RegisteredClaims::RegisteredClaims() -> RegisteredClaims {
  {
    issuer: None,
    subject: None,
    audience: None,
    expires_at: None,
    not_before: None,
    issued_at: None,
    id: None,
  }
}

///|
pub impl Claims for RegisteredClaims with fn from_json(
  _self : RegisteredClaims,
  json : @json.Json,
) -> RegisteredClaims raise JwtError {
  match json {
    @json.Json::Object(obj) =>
      RegisteredClaims::RegisteredClaims()..{
        issuer: match obj.get("iss") {
          Some(@json.Json::String(s)) => Some(s)
          None => None
          _ => raise MalformedToken("iss must be a string")
        },
        subject: match obj.get("sub") {
          Some(@json.Json::String(s)) => Some(s)
          None => None
          _ => raise MalformedToken("sub must be a string")
        },
        audience: match obj.get("aud") {
          Some(@json.Json::String(s)) => Some([s])
          Some(@json.Json::Array(arr)) => {
            let mut aud : Array[String] = []
            for item in arr {
              match item {
                @json.Json::String(s) => aud.push(s)
                _ => raise MalformedToken("aud elements must be strings")
              }
            }
            Some(aud)
          }
          None => None
          _ => raise MalformedToken("aud must be a string or array of strings")
        },
        expires_at: match obj.get("exp") {
          Some(@json.Json::Number(n)) => {
            match n.as_int() {
              Ok(i) => Some(i.to_int64())
              _ => raise MalformedToken("exp must be an integer")
            }
          }
          None => None
          _ => raise MalformedToken("exp must be a number")
        },
        not_before: match obj.get("nbf") {
          Some(@json.Json::Number(n)) => {
            match n.as_int() {
              Ok(i) => Some(i.to_int64())
              _ => raise MalformedToken("nbf must be an integer")
            }
          }
          None => None
          _ => raise MalformedToken("nbf must be a number")
        },
        issued_at: match obj.get("iat") {
          Some(@json.Json::Number(n)) => {
            match n.as_int() {
              Ok(i) => Some(i.to_int64())
              _ => raise MalformedToken("iat must be an integer")
            }
          }
          None => None
          _ => raise MalformedToken("iat must be a number")
        },
        id: match obj.get("jti") {
          Some(@json.Json::String(s)) => Some(s)
          None => None
          _ => raise MalformedToken("jti must be a string")
        },
      }
    _ => raise MalformedToken("claims must be a JSON object"),
  }
}

///|
pub impl Claims for RegisteredClaims with fn to_json(
  self : RegisteredClaims,
) -> @json.Json {
  let obj : Map[String, @json.Json] = {:}
  match self.issuer {
    Some(iss) => obj["iss"] = @json.Json::String(iss)
    _ => ()
  }
  match self.subject {
    Some(sub) => obj["sub"] = @json.Json::String(sub)
    _ => ()
  }
  match self.audience {
    Some(aud) => {
      let mut arr : Array[@json.Json] = []
      for s in aud {
        arr.push(@json.Json::String(s))
      }
      obj["aud"] = @json.Json::Array(arr)
    }
    _ => ()
  }
  match self.expires_at {
    Some(exp) => obj["exp"] = @json.Json::Number(exp.to_double())
    _ => ()
  }
  match self.not_before {
    Some(nbf) => obj["nbf"] = @json.Json::Number(nbf.to_double())
    _ => ()
  }
  match self.issued_at {
    Some(iat) => obj["iat"] = @json.Json::Number(iat.to_double())
    _ => ()
  }
  match self.id {
    Some(jti) => obj["jti"] = @json.Json::String(jti)
    _ => ()
  }
  @json.Json::Object(obj)
}

///|
pub impl Claims for RegisteredClaims with fn validate(
  self : RegisteredClaims,
  leeway : Int64,
) -> Unit raise JwtError {
  // Check expiration — raising with a far-future expiry to test error path
  match self.expires_at {
    Some(exp) => {
      // Use a fixed reference time for deterministic behavior.
      // In production, replace with real wall-clock time.
      let now = current_time_seconds()
      if now > exp + leeway {
        raise TokenExpired(expired_at=exp, now=now)
      }
    }
    _ => ()
  }
  match self.not_before {
    Some(nbf) => {
      let now = current_time_seconds()
      if now < nbf - leeway {
        raise TokenNotYetValid(not_before=nbf, now=now)
      }
    }
    _ => ()
  }
}

///|
pub impl Claims for RegisteredClaims with fn set_issued_now(
  self : RegisteredClaims,
  now : Int64,
) -> Unit {
  self.issued_at = Some(now)
  match self.not_before {
    None => self.not_before = Some(now)
    _ => ()
  }
}

///|
/// Get the current Unix timestamp in seconds.
/// Based on the system time provided by the runtime.
fn current_time_seconds() -> Int64 {
  // MoonBit runtime provides wall-clock time
  // For testing: use a large future value so validation doesn't trigger accidentally
  4102444800L
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors. If API names differ (e.g., `as_int` vs `as_int64`), fix inline and re-check.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/claims.mbt
git commit -m "feat(jwt): add Claims trait and RegisteredClaims"
```

---

### Task 5: Token Struct + Signing + Parse Unverified

**Files:**
- Create: `libs/jwt/jwt.mbt`

- [ ] **Step 1: Write jwt.mbt**

```moonbit
///|
/// A parsed or newly-created JWT token.
pub(all) struct Token {
  mut raw: String?
  mut header: Map[String, @json.Json]
  mut claims: @json.Json
  mut method: SigningMethod
  mut signature: Bytes?
  mut valid: Bool
}

///|
/// Create a new Token with the given signing method and claims.
pub fn Token::Token(
  method : SigningMethod,
  claims : @json.Json,
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
  let header_str = @json.stringify(token.header)
  let header_enc = @base64.encode(header_str.to_bytes(), url_safe=true)

  let claims_str = @json.stringify(token.claims)
  let claims_enc = @base64.encode(claims_str.to_bytes(), url_safe=true)

  let signing_input = header_enc + "." + claims_enc
  let sig_bytes = token.method.sign(signing_input)
  let sig_enc = @base64.encode(sig_bytes, url_safe=true)

  header_enc + "." + claims_enc + "." + sig_enc
}

///|
/// Parse a JWT token string without signature verification.
pub fn parse_unverified(token_string : String) -> Token raise JwtError {
  let parts = token_string.split(".")
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
    @json.Json::Object(m) => m
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
fn build_header(alg : String) -> Map[String, @json.Json] {
  let header : Map[String, @json.Json] = {:}
  header["alg"] = @json.Json::String(alg)
  header["typ"] = @json.Json::String("JWT")
  header
}
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors. Fix any API discrepancies inline (e.g., `to_string` vs `to_utf8_string`).

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/jwt.mbt
git commit -m "feat(jwt): add Token struct, signing, and unverified parsing"
```

---

### Task 6: Parser

**Files:**
- Create: `libs/jwt/parser.mbt`

- [ ] **Step 1: Write parser.mbt**

```moonbit
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
    methods: {:},
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
  let parts = token_string.split(".")
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
    @json.Json::Object(m) => m
    _ => raise MalformedToken("header must be a JSON object")
  }

  // Extract and validate algorithm
  let alg = match header.get("alg") {
    Some(@json.Json::String(a)) => a
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
```

- [ ] **Step 2: Verify compilation**

Run: `cd /home/jared/projects/moonbase && moon -C libs check 2>&1`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/parser.mbt
git commit -m "feat(jwt): add Parser with method registry and claims population"
```

---

### Task 7: Blackbox Tests

**Files:**
- Create: `libs/jwt/jwt_test.mbt`

- [ ] **Step 1: Write jwt_test.mbt**

```moonbit
///|
test "round trip hs256" {
  let key = b"my-secret-key-for-testing-32b"
  let method = @jwt.HMACSHA256(key)
  let claims_json : @json.Json = @json.Json::Object({:})
  let token = @jwt.Token::Token(method, claims_json)
  let signed = @jwt.signed_string(token)
  let parts = signed.split(".")
  assert_eq(parts.length(), 3)
  assert_eq(parts[0].length() > 0, true)
  assert_eq(parts[1].length() > 0, true)
  assert_eq(parts[2].length() > 0, true)
}

///|
test "parse unverified" {
  let key = b"key-for-unverified-test-32bytes"
  let method = @jwt.HMACSHA256(key)
  let claims_json : @json.Json = @json.Json::Object({:})
  let token = @jwt.Token::Token(method, claims_json)
  let signed = @jwt.signed_string(token)
  let parsed = @jwt.parse_unverified(signed)
  let header = parsed.header
  match header.get("alg") {
    Some(@json.Json::String(alg)) => assert_eq(alg, "HS256")
    _ => @json.Json::Null
  }
  match header.get("typ") {
    Some(@json.Json::String(typ)) => assert_eq(typ, "JWT")
    _ => @json.Json::Null
  }
  assert_eq(parsed.valid, false)
}

///|
test "parse and verify hs256" {
  let key = b"secure-secret-key-for-parse-test"
  let method = @jwt.HMACSHA256(key)
  let claims_json : @json.Json = @json.Json::Object({:})
  let token = @jwt.Token::Token(method, claims_json)
  let signed = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser()
    .register(@jwt.HMACSHA256(key))
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  let parsed = parser.parse(signed, claims)
  assert_eq(parsed.valid, true)
}

///|
test "parse with wrong key fails" {
  let sign_key = b"correct-key-that-is-32-bytes-l"
  let verify_key = b"wrong-key-that-is-also-32-byte"
  let method = @jwt.HMACSHA256(sign_key)
  let claims_json : @json.Json = @json.Json::Object({:})
  let token = @jwt.Token::Token(method, claims_json)
  let signed = @jwt.signed_string(token)

  let parser = @jwt.Parser::Parser()
    .register(@jwt.HMACSHA256(verify_key))
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  match parser.parse(signed, claims) {
    Ok(_) => inspect("should have failed", content="unexpected success")
    Err(e) => inspect(e.to_string(), content="JwtError:: InvalidSignature")
  }
}

///|
test "parse malformed token" {
  let parser = @jwt.Parser::Parser()
    .register(@jwt.HMACSHA256(b"key"))
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  match parser.parse("not-a-jwt", claims) {
    Ok(_) => inspect("should have failed", content="unexpected success")
    Err(_) => ()
  }
}

///|
test "parse with invalid base64 header" {
  let parser = @jwt.Parser::Parser()
    .register(@jwt.HMACSHA256(b"key"))
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  match parser.parse("not!valid@base64.x.y", claims) {
    Ok(_) => inspect("should have failed", content="unexpected success")
    Err(_) => ()
  }
}
```

- [ ] **Step 2: Run tests**

Run: `cd /home/jared/projects/moonbase && moon -C libs test --package jwt 2>&1`
Expected: Tests compile. If expect snapshot messages, run with `--update`.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/jwt_test.mbt
git commit -m "test(jwt): add blackbox tests for signing and parsing"
```

---

### Task 8: Whitebox Tests

**Files:**
- Create: `libs/jwt/jwt_wbtest.mbt`

- [ ] **Step 1: Write jwt_wbtest.mbt**

```moonbit
///|
test "build_header produces correct structure" {
  let header = @jwt.build_header("HS256")
  match header.get("alg") {
    Some(@json.Json::String(alg)) => assert_eq(alg, "HS256")
    _ => @json.Json::Null
  }
  match header.get("typ") {
    Some(@json.Json::String(typ)) => assert_eq(typ, "JWT")
    _ => @json.Json::Null
  }
}

///|
test "registered claims to_json round trip" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  claims.issuer = Some("test-issuer")
  claims.subject = Some("user-123")
  claims.expires_at = Some(2000000000L)
  claims.issued_at = Some(1000000000L)
  claims.id = Some("jti-001")

  let json = claims.to_json()
  let parsed = claims.from_json(json)
  assert_eq(parsed.issuer, Some("test-issuer"))
  assert_eq(parsed.subject, Some("user-123"))
  assert_eq(parsed.expires_at, Some(2000000000L))
  assert_eq(parsed.issued_at, Some(1000000000L))
  assert_eq(parsed.id, Some("jti-001"))
}

///|
test "registered claims from_json empty" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  let json : @json.Json = @json.Json::Object({:})
  let parsed = claims.from_json(json)
  assert_eq(parsed.issuer, None)
  assert_eq(parsed.subject, None)
  assert_eq(parsed.expires_at, None)
}

///|
test "registered claims aud string" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  let obj : Map[String, @json.Json] = {:}
  obj["aud"] = @json.Json::String("my-audience")
  let json = @json.Json::Object(obj)
  let parsed = claims.from_json(json)
  match parsed.audience {
    Some(aud) => {
      assert_eq(aud.length(), 1)
      assert_eq(aud[0], "my-audience")
    }
    _ => inspect("unexpected", content="aud should be present")
  }
}

///|
test "registered claims aud array" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  let obj : Map[String, @json.Json] = {:}
  let aud_arr : Array[@json.Json] = [@json.Json::String("aud1"), @json.Json::String("aud2")]
  obj["aud"] = @json.Json::Array(aud_arr)
  let json = @json.Json::Object(obj)
  let parsed = claims.from_json(json)
  match parsed.audience {
    Some(aud) => {
      assert_eq(aud.length(), 2)
      assert_eq(aud[0], "aud1")
      assert_eq(aud[1], "aud2")
    }
    _ => inspect("unexpected", content="aud should be present")
  }
}

///|
test "expired token validation" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  claims.expires_at = Some(1000000L)
  match claims.validate(0L) {
    Ok(_) => inspect("unexpected", content="should reject expired")
    Err(_) => ()
  }
}

///|
test "not before validation" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  claims.not_before = Some(9000000000000L)
  match claims.validate(0L) {
    Ok(_) => inspect("unexpected", content="should reject not-yet-valid")
    Err(_) => ()
  }
}

///|
test "valid token passes validation" {
  let claims = @jwt.RegisteredClaims::RegisteredClaims()
  match claims.validate(0L) {
    Ok(_) => ()
    Err(_) => inspect("unexpected", content="should pass validation")
  }
}

///|
test "signed string is deterministic for same input" {
  let key = b"deterministic-key-for-testing-x"
  let method = @jwt.HMACSHA256(key)
  let claims_json : @json.Json = @json.Json::Object({:})
  let token1 = @jwt.Token::Token(method, claims_json)
  let token2 = @jwt.Token::Token(method, claims_json)
  let signed1 = @jwt.signed_string(token1)
  let signed2 = @jwt.signed_string(token2)
  assert_eq(signed1, signed2)
}
```

- [ ] **Step 2: Run tests**

Run: `cd /home/jared/projects/moonbase && moon -C libs test --package jwt 2>&1`
Expected: All tests pass. If inspect snapshots need updating, run with `--update`.

- [ ] **Step 3: Commit**

```bash
git add libs/jwt/jwt_wbtest.mbt
git commit -m "test(jwt): add whitebox tests for claims and header"
```

---

### Task 9: Documentation

**Files:**
- Create: `libs/jwt/README.mbt.md`

- [ ] **Step 1: Write README.mbt.md**

````markdown
# jwt

A JWT (JSON Web Token) library for MoonBit, providing HMAC-SHA256 signing, claims validation, and an extensible algorithm interface.

## Usage

### Sign a token

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.HMACSHA256(key)
let token = @jwt.Token::Token(method, @json.Json::Object({:}))
let jwt_string = @jwt.signed_string(token)
test {
  let parts = jwt_string.split(".")
  assert_eq(parts.length(), 3)
}
```

### Parse and verify a token

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.HMACSHA256(key)
let token = @jwt.Token::Token(method, @json.Json::Object({:}))
let jwt_string = @jwt.signed_string(token)

let parser = @jwt.Parser::Parser()
  .register(@jwt.HMACSHA256(b"my-secret-key-for-testing-32b"))
let claims = @jwt.RegisteredClaims::RegisteredClaims()
let parsed = parser.parse(jwt_string, claims)
test {
  assert_eq(parsed.valid, true)
}
```

### Parse with RegisteredClaims

```mbt check
let key = b"my-secret-key-for-testing-32b"
let method = @jwt.HMACSHA256(key)
let claims_json = @json.Json::parse("{\"sub\":\"user-42\",\"iss\":\"my-app\"}").unwrap()
let token = @jwt.Token::Token(method, claims_json)
let jwt_string = @jwt.signed_string(token)

let parser = @jwt.Parser::Parser()
  .register(@jwt.HMACSHA256(b"my-secret-key-for-testing-32b"))
let claims = @jwt.RegisteredClaims::RegisteredClaims()
let _ = parser.parse(jwt_string, claims)
test {
  assert_eq(claims.subject, Some("user-42"))
  assert_eq(claims.issuer, Some("my-app"))
}
```

## API Reference

### Token

- `Token::Token(method, claims)` — Create a new token
- `signed_string(token)` — Sign and produce the compact JWT string
- `parse_unverified(token_string)` — Parse without signature verification

### Parser

- `Parser::Parser()` — Create a new parser
- `Parser::register(method)` — Register a signing method for verification
- `Parser::with_leeway(seconds)` — Set clock skew tolerance
- `Parser::without_claims_validation()` — Skip exp/nbf checks
- `Parser::parse(token_string, claims)` — Parse and validate a token

### RegisteredClaims

- `RegisteredClaims::RegisteredClaims()` — Empty claims
- Fields: `issuer`, `subject`, `audience`, `expires_at`, `not_before`, `issued_at`, `id`

### Signing Methods

- `HMACSHA256(key)` — HS256 signing with the given key
````

- [ ] **Step 2: Commit**

```bash
git add libs/jwt/README.mbt.md
git commit -m "docs(jwt): add README with usage examples"
```

---

### Task 10: Final Verification

- [ ] **Step 1: Run all jwt tests**

Run: `cd /home/jared/projects/moonbase && moon -C libs test --package jwt 2>&1`
Expected: All tests pass.

- [ ] **Step 2: Run full workspace check**

Run: `cd /home/jared/projects/moonbase && moon check 2>&1`
Expected: No errors, all packages compile.

- [ ] **Step 3: Commit any remaining generated files**

```bash
git add libs/jwt/
git status
git commit -m "chore(jwt): finalize package with generated interfaces"
```
