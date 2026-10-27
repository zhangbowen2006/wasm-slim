///|
/// A module with a fake custom section that is large relative to the file:
/// 8-byte header + custom(id 0, size 20) + a small type section.
fn debug_like_module() -> Bytes {
  let bytes : Array[Byte] = [
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x14',
  ]
  for _ in 0..<20 {
    bytes.push(b'\x00')
  }
  bytes.push(b'\x01')
  bytes.push(b'\x02')
  bytes.push(b'\x01')
  bytes.push(b'\x60')
  Bytes::from_array(bytes)
}

///|
/// Same shape but without the custom section: release-like.
fn release_like_module() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x02', b'\x01', b'\x60',
  ])
}

///|
test "custom-heavy modules are classified as debug" {
  inspect(classify(60, 100), content="debug")
  inspect(classify(0, 100), content="release")
  inspect(classify(19, 100), content="release")
  inspect(classify(20, 100), content="debug")
  inspect(classify(0, 0), content="empty")
}

///|
test "a debug-like module fails the gate" {
  let m = @wasm.parse_module(debug_like_module())
  let r = audit(m, 0)
  inspect(r.profile, content="debug")
  inspect(passed(r), content="false")
  inspect(error_count(r), content="1")
}

///|
test "a release-like module passes" {
  let m = @wasm.parse_module(release_like_module())
  let r = audit(m, 0)
  inspect(r.profile, content="release")
  inspect(passed(r), content="true")
}

///|
test "a budget below the file size fails the gate" {
  let m = @wasm.parse_module(release_like_module())
  let r = audit(m, 4)
  inspect(passed(r), content="false")
  inspect(error_count(r), content="1")
}

///|
test "a budget above the file size does not fail" {
  let m = @wasm.parse_module(release_like_module())
  let r = audit(m, 1_000_000)
  inspect(passed(r), content="true")
}
