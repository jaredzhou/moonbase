# JWT Library Design

## Overview

Create `jaredzhou/libs/jwt` — a feature-complete JWT (JSON Web Token) library for MoonBit, modeled after golang-jwt v5, targeting RFC 7519 compliance. Focus on HMAC signing initially with an abstract SigningMethod trait for future algorithm support.

## Architecture

```
libs/jwt/
├── moon.pkg                  # Package config
├── jwt.mbt                   # Token creation/parsing entry points
├── claims.mbt                # Claims trait + RegisteredClaims + validation
├── signing_method.mbt        # SigningMethod trait + HMAC implementations (HS256)
├── errors.mbt                # Structured error types
├── parser.mbt                # Parser config + parse logic
├── jwt_test.mbt              # Blackbox tests
├── jwt_wbtest.mbt            # Whitebox tests (internal logic)
└── README.mbt.md             # Documentation + doctests
```

## Dependencies

- `moonbitlang/x/crypto` — sha256, hmac, CryptoHasher trait
- `moonbitlang/x/codec/base64` — base64url encode/decode (RFC 4648)
- `moonbitlang/core/json` — header/payload JSON serialization

HS384/HS512 require SHA-384/512 which are not in the official library. When needed, Tigerls/mb-hash will provide the CryptoHasher implementation via the same SigningMethod trait interface.

## Core Types

### Token

```
pub(all) struct Token {
  raw: String                     // original token string
  header: Map[String, Json]       // decoded JWT header
  claims: @json.Json              // decoded payload (claims)
  method: SigningMethod           // signing algorithm used
  signature: Bytes                // raw signature bytes
  valid: Bool                     // whether token passed validation
}
```

### SigningMethod Trait

```
pub trait SigningMethod {
  alg(Self) -> String                                    // e.g. "HS256"
  sign(Self, String) -> Bytes raise JwtError             // sign signing_string (uses self key)
  verify(Self, String, signature : Bytes) -> Unit raise JwtError // verify (uses self key)
}

// SigningMethod is stateful — each instance holds its own key.
// sign() and verify() use the key stored in the method instance.
```

#### HMAC Implementations

- `SigningMethodHMACSHA256(key : Bytes)` — uses `@crypto.sha256` + `@crypto.hmac`
- `SigningMethodHMACSHA384(key : Bytes)` — deferred (needs SHA-384 CryptoHasher)
- `SigningMethodHMACSHA512(key : Bytes)` — deferred (needs SHA-512 CryptoHasher)

Constructor: `pub fn SigningMethodHMACSHA256::SigningMethodHMACSHA256(key : Bytes) -> SigningMethodHMACSHA256`

### Claims Trait + RegisteredClaims

```
pub trait Claims {
  from_json(Self, @json.Json) -> Self raise JwtError  // deserialize from JSON payload
  to_json(Self) -> @json.Json                          // serialize to JSON
  validate(Self, leeway : Int64) -> Unit raise JwtError  // validate registered claims
  set_issued_now(Self, Int64) -> Unit                     // set iat/nbf during signing
}

pub(all) struct RegisteredClaims {
  issuer: String?          // iss
  subject: String?         // sub
  audience: Array[String]? // aud
  expires_at: Int64?       // exp  (Unix timestamp)
  not_before: Int64?       // nbf  (Unix timestamp)
  issued_at: Int64?        // iat  (Unix timestamp)
  id: String?              // jti  (unique token ID)
}

// RegisteredClaims implements Claims
```

RegisteredClaims implements Claims with validation logic:
- exp: token expired if now > exp + leeway
- nbf: token not yet valid if now < nbf - leeway
- iat: not technically required for validation, just informational

### Parser

```
pub(all) struct Parser {
  methods: Map[String, SigningMethod]  // alg -> SigningMethod (registered by user)
  leeway: Int64                         // clock skew tolerance in seconds
  skip_claims_validation: Bool          // skip claims validation
}

pub fn Parser::Parser() -> Parser
// defaults: leeway=0, empty methods

pub fn Parser::register(self : Parser, method : SigningMethod) -> Parser
// register a signing method by its alg() value for verification
// e.g. parser.register(SigningMethodHMACSHA256::SigningMethodHMACSHA256(key))
```

When parsing, the parser:
1. Reads `alg` from JWT header
2. Looks up `alg` in `self.methods` → gets the matching `SigningMethod` (which holds the key)
3. Calls `method.verify(signing_string, signature)` to verify
4. Raises `InvalidAlgorithm` if no matching method registered

### Error Types

```
pub suberror JwtError {
  InvalidSignature
  TokenExpired(expired_at: Int64, now: Int64)
  TokenNotYetValid(not_before: Int64, now: Int64)
  MalformedToken(String)
  InvalidAlgorithm(String)
  InvalidAudience(String)
  InvalidIssuer(String)
  MissingRequiredClaim(String)
  UnverifiableToken(String)
  InvalidKey
}
```

## API Surface

### Entry Points (jwt.mbt)

```moonbit
// Create a token (method holds the key internally)
pub fn Token::Token(method : SigningMethod, claims : @json.Json) -> Token

// Sign and produce the compact JWT string (method's key used internally)
pub fn signed_string(token : Token) -> String raise JwtError

// Parse and validate — parser looks up SigningMethod by header alg
pub fn Parser::parse[C : Claims](self : Parser, token_string : String, claims : C) -> Token raise JwtError

// Parse without verification (decode only, no signature check)
pub fn parse_unverified(token_string : String) -> Token raise JwtError
```

### Signing/Verification Flow

**Signing:**
1. User creates `SigningMethodHMACSHA256` with key, then `Token::Token(method, claims)`
2. Calls `signed_string(token)` which:
   a. Sets iat/nbf on claims
   b. Builds header JSON `{"alg":"HS256","typ":"JWT"}`
   c. Base64url-encodes header and claims → `header.payload`
   d. Calls `method.sign("header.payload")` → signature (key from method)
   e. Base64url-encodes signature
   f. Returns `header.payload.signature`

**Parsing:**
1. Split token on `.` → 3 parts (header, payload, signature)
2. Base64url-decode each part
3. Parse header JSON → extract `alg`
4. Look up `alg` in parser's registered methods → get `SigningMethod` (with its key)
5. Call `method.verify("header.payload", signature)` → raises on mismatch
6. Call `claims.from_json(payload_json)` → populate claims struct
7. Call `claims.validate(parser.leeway)` → check exp, nbf, etc.
8. Return valid Token

## Testing Strategy

- **Blackbox tests** (jwt_test.mbt): Cover full signing → parsing round-trips, error cases, edge cases (empty claims, max timestamps, etc.)
- **Whitebox tests** (jwt_wbtest.mbt): Test internal base64url encoding, header construction, signing_string format, claims validation logic
- **Test vectors**: Use RFC test vectors for known-good token outputs
- **Doctests**: README.mbt.md with runnable examples
