///|
/// Supported JWT signing algorithms.
/// Each variant holds its own key material.
pub enum SigningMethod {
  HMACSHA256(Bytes)
}

///|
/// Create a new HMACSHA256 signing method with the given key.
pub fn new_hmac_sha256(key : Bytes) -> SigningMethod {
  HMACSHA256(key)
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
      let sig = @crypto.hmac(hasher, key, @encoding/utf8.encode(signing_string))
      Bytes::from_array(sig)
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
