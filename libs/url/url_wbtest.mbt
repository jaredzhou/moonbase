///|
test "escape" {
  let str = "/foo%2fbar/baz%2Fquux"
  let escaped = escape(str, Encoding::EncodePath)
  inspect(escaped, content="/foo%2fbar/baz%2Fquux")
  let escaped = escape("%", Encoding::EncodePath)
  inspect(escaped, content="%25")
  let escaped = escape("hello.世界", Encoding::EncodeHost)
  inspect(escaped, content="hello.%E4%B8%96%E7%95%8C")
  let unescaped = unescape(escaped, Encoding::EncodeHost)
  inspect(unescaped, content="hello.世界")
}

///|
test "query escape spaces" {
  let escaped = escape("hello world", EncodePath)
  assert_eq(escaped, "hello%20world")
  let escaped = escape("hello world", EncodeQueryComponent)
  assert_eq(escaped, "hello%20world")
}
