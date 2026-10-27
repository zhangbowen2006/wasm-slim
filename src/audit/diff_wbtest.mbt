///|
/// Two functions, each with a 4-byte body.
fn mod_two() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x04', b'\x01', b'\x60', b'\x00', b'\x7f',
    b'\x03', b'\x03', b'\x02', b'\x00', b'\x00',
    b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    b'\x0a', b'\x0b', b'\x02',
    b'\x04', b'\x00', b'\x41', b'\x01', b'\x0b',
    b'\x04', b'\x00', b'\x41', b'\x02', b'\x0b',
  ])
}

///|
/// Three functions: the first grew to 6 bytes, a third one is new.
fn mod_three() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x04', b'\x01', b'\x60', b'\x00', b'\x7f',
    b'\x03', b'\x04', b'\x03', b'\x00', b'\x00', b'\x00',
    b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    b'\x0a', b'\x13', b'\x03',
    b'\x07', b'\x00', b'\x41', b'\x01', b'\x1a', b'\x41', b'\x01', b'\x0b',
    b'\x04', b'\x00', b'\x41', b'\x02', b'\x0b',
    b'\x04', b'\x00', b'\x41', b'\x03', b'\x0b',
  ])
}

///|
test "diff reports one added function and one that grew" {
  let old = @wasm.parse_module(mod_two())
  let new = @wasm.parse_module(mod_three())
  let d = diff(old, new)
  inspect(d.old_functions, content="2")
  inspect(d.new_functions, content="3")
  inspect(d.added.length(), content="1")
  inspect(d.removed.length(), content="0")
  inspect(d.changed.length(), content="1")
  // the changed function is func[0]: 4 -> 6 bytes
  inspect(d.changed[0].old_size, content="4")
  inspect(d.changed[0].new_size, content="7")
  inspect(delta_of(d.changed[0]), content="3")
}

///|
test "diff reports removals when a function disappears" {
  let old = @wasm.parse_module(mod_three())
  let new = @wasm.parse_module(mod_two())
  let d = diff(old, new)
  inspect(d.added.length(), content="0")
  inspect(d.removed.length(), content="1")
  inspect(d.changed.length(), content="1")
  inspect(delta_of(d.changed[0]), content="-3")
}

///|
test "identical modules produce no changes" {
  let a = @wasm.parse_module(mod_two())
  let b = @wasm.parse_module(mod_two())
  let d = diff(a, b)
  inspect(d.added.length(), content="0")
  inspect(d.removed.length(), content="0")
  inspect(d.changed.length(), content="0")
  inspect(d.old_size, content=d.new_size.to_string())
}

///|
test "top_changes sorts by absolute delta" {
  let old = @wasm.parse_module(mod_two())
  let new = @wasm.parse_module(mod_three())
  let d = diff(old, new)
  let top = top_changes(d, 5)
  // the added 4-byte function ties the +2 change only if sizes differ;
  // here the added body is 4 bytes and the change is +2, so added comes first
  inspect(top[0].new_size, content="4")
  inspect(top[0].old_size, content="0")
}
