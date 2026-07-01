///|
test "now and now_mill are monotonic and consistent" {
  let s1 = now()
  let ms1 = now_mill()
  let s2 = now()
  let ms2 = now_mill()

  // Seconds should not decrease
  assert_true(s2 >= s1)

  // Milliseconds should not decrease
  assert_true(ms2 >= ms1)

  // Milliseconds roughly equal seconds * 1000 (within one second tolerance)
  let diff = ms2 - s2 * 1000L
  assert_true(diff >= 0L)
  assert_true(diff <= 1000L)
}
