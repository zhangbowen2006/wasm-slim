///|
/// Named module: two functions called alpha and beta.
fn named_two() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00', b'\x01',
    b'\x05', b'\x01', b'\x60', b'\x00', b'\x01', b'\x7f', b'\x03', b'\x03', b'\x02',
    b'\x00', b'\x00', b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    b'\x0a', b'\x0b', b'\x02', b'\x04', b'\x00', b'\x41', b'\x01', b'\x0b', b'\x04',
    b'\x00', b'\x41', b'\x02', b'\x0b', b'\x00', b'\x0e', b'\x04', b'\x6e', b'\x61',
    b'\x6d', b'\x65', b'\x01', b'\x07', b'\x02', b'\x00', b'\x01', b'\x61', b'\x01',
    b'\x01', b'\x62',
  ])
}

///|
/// Same code, no name section.
fn unnamed_two() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00', b'\x01',
    b'\x05', b'\x01', b'\x60', b'\x00', b'\x01', b'\x7f', b'\x03', b'\x03', b'\x02',
    b'\x00', b'\x00', b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    b'\x0a', b'\x0b', b'\x02', b'\x04', b'\x00', b'\x41', b'\x01', b'\x0b', b'\x04',
    b'\x00', b'\x41', b'\x02', b'\x0b',
  ])
}

///|
test "a named module compared with an unnamed one still matches by index" {
  let named = @wasm.parse_module(named_two())
  let unnamed = @wasm.parse_module(unnamed_two())
  let d = diff(named, unnamed)
  // Both sides must fall back to index keys; otherwise every function would
  // be reported as added *and* removed.
  inspect(d.named, content="false")
  inspect(d.added.length(), content="0")
  inspect(d.removed.length(), content="0")
  inspect(d.changed.length(), content="0")
  inspect(d.old_functions, content="2")
  inspect(d.new_functions, content="2")
}

///|
test "two named modules match by name" {
  let a = @wasm.parse_module(named_two())
  let b = @wasm.parse_module(named_two())
  let d = diff(a, b)
  inspect(d.named, content="true")
  inspect(d.added.length(), content="0")
  inspect(d.changed.length(), content="0")
}
