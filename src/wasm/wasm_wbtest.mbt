///|
test "leb128 round-trips values used by section sizes" {
  for v in [0, 1, 127, 128, 300, 16384, 1000000] {
    let encoded = write_u32_bytes(v.reinterpret_as_uint())
    let (decoded, next) = read_u32(encoded, 0)
    if decoded.reinterpret_as_int() != v {
      abort("round-trip failed for \{v}")
    }
    if next != encoded.length() {
      abort("consumed \{next} of \{encoded.length()} bytes for \{v}")
    }
  }
}

///|
test "an empty module has no sections" {
  let bytes = Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
  ])
  let m = parse_module(bytes)
  inspect(m.sections.length(), content="0")
  inspect(is_wasm(bytes), content="true")
}

///|
test "magic is checked" {
  let bytes = Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6e', b'\x01', b'\x00', b'\x00', b'\x00',
  ])
  inspect(is_wasm(bytes), content="false")
}

///|
test "sections are walked with correct sizes" {
  // magic + version + (type section: id=1, size=4, 4 payload bytes)
  let bytes = Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x04', b'\x01', b'\x60', b'\x00', b'\x00',
  ])
  let m = parse_module(bytes)
  inspect(m.sections.length(), content="1")
  inspect(m.sections[0].id, content="1")
  inspect(m.sections[0].content_size, content="4")
}

///|
test "custom sections are stripped and the rest is preserved" {
  // magic + version + custom(id 0, size 3, "abc") + type(id 1, size 2, payload)
  let bytes = Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x03', b'\x61', b'\x62', b'\x63',
    b'\x01', b'\x02', b'\x01', b'\x60',
  ])
  let m = parse_module(bytes)
  inspect(m.sections.length(), content="2")
  inspect(custom_bytes(m), content="3")
  let stripped = strip_custom(m)
  inspect(stripped.length(), content="12")
  let re = parse_module(stripped)
  inspect(re.sections.length(), content="1")
  inspect(re.sections[0].id, content="1")
}
