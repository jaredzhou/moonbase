///|
/// JWT error types covering all failure modes in the parsing and validation pipeline.
pub suberror JwtError {
  InvalidSignature
  TokenExpired(expired_at~ : Int64, now~ : Int64)
  TokenNotYetValid(not_before~ : Int64, now~ : Int64)
  MalformedToken(String)
  InvalidAlgorithm(String)
} derive(Debug)
