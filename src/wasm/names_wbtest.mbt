///|
/// A two-function module plus a `name` custom section naming them "alpha"
/// and "beta".
fn named_module() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    // type: () -> i32
     b'\x01', b'\x05', b'\x01', b'\x60', b'\x00', b'\x01', b'\x7f',
    // function: two of type 0
     b'\x03', b'\x03', b'\x02', b'\x00', b'\x00',
    // export "a" func 0
     b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    // code: two 4-byte bodies
     b'\x0a', b'\x0b', b'\x02', b'\x04', b'\x00', b'\x41', b'\x01', b'\x0b', b'\x04',
    b'\x00', b'\x41', b'\x02', b'\x0b',
    // custom "name": function-names subsection (id 1) with two entries
     b'\x00', b'\x0e', b'\x04', b'\x6e', b'\x61', b'\x6d', b'\x65', b'\x01', b'\x07',
    b'\x02', b'\x00', b'\x01', b'\x61', b'\x01', b'\x01', b'\x62',
  ])
}

///|
test "function names come from the name custom section" {
  let m = parse_module(named_module())
  let names = function_names(m)
  inspect(name_of(names, 0U), content="a")
  inspect(name_of(names, 1U), content="b")
  inspect(name_of(names, 2U), content="func[2]")
}

///|
test "a module without a name section yields an empty map" {
  let m = parse_module(
    Bytes::from_array([
      b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00', b'\x01',
      b'\x02', b'\x01', b'\x60',
    ]),
  )
  inspect(function_names(m).length(), content="0")
}

///|
test "name_of falls back to the index when the entry is missing" {
  let m = parse_module(named_module())
  let names = function_names(m)
  inspect(name_of(names, 7U), content="func[7]")
}

///|
test "custom_payload finds the section by name" {
  let m = parse_module(named_module())
  match custom_payload(m, "name") {
    None => abort("expected the name section")
    Some((_, size)) => inspect(size, content="9")
  }
  inspect(custom_payload(m, "producers") is None, content="true")
}
