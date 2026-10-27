///|
/// A two-function module:
///   (func $a (export "a") (result i32) i32.const 1)
///   (func $b (result i32) i32.const 2)
/// `$b` is never called and never exported, so it is unreachable.
fn two_function_module() -> Bytes {
  Bytes::from_array([
    // magic + version
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    // type: count=1, () -> i32
    b'\x01', b'\x04', b'\x01', b'\x60', b'\x00', b'\x7f',
    // function: count=2, both type 0
    b'\x03', b'\x03', b'\x02', b'\x00', b'\x00',
    // export: count=1, "a" func 0
    b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    // code: count=2, each body = 4 bytes (0 locals, const, end)
    b'\x0a', b'\x0b', b'\x02',
    b'\x04', b'\x00', b'\x41', b'\x01', b'\x0b',
    b'\x04', b'\x00', b'\x41', b'\x02', b'\x0b',
  ])
}

///|
/// Same module, but `$a` calls `$b` first, so both are reachable.
fn two_function_module_with_call() -> Bytes {
  Bytes::from_array([
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x00', b'\x00',
    b'\x01', b'\x04', b'\x01', b'\x60', b'\x00', b'\x7f',
    b'\x03', b'\x03', b'\x02', b'\x00', b'\x00',
    b'\x07', b'\x05', b'\x01', b'\x01', b'\x61', b'\x00', b'\x00',
    // code: body 0 = call 1; drop; i32.const 1; end  (5 bytes)
    // body 1 = i32.const 2; end (4 bytes)
    b'\x0a', b'\x0e', b'\x02',
    b'\x07', b'\x00', b'\x10', b'\x01', b'\x1a', b'\x41', b'\x01', b'\x0b',
    b'\x04', b'\x00', b'\x41', b'\x02', b'\x0b',
  ])
}

///|
test "an exported function is reachable and an unused one is not" {
  let m = @wasm.parse_module(two_function_module())
  inspect(m.sections.length(), content="4")
  let r = analyze(m)
  inspect(r.imported, content="0")
  inspect(r.defined, content="2")
  inspect(r.total, content="2")
  let dead = unreachable_functions(r)
  inspect(dead.length(), content="1")
  inspect(dead[0].reinterpret_as_int(), content="1")
}

///|
test "a call makes the callee reachable" {
  let m = @wasm.parse_module(two_function_module_with_call())
  let r = analyze(m)
  inspect(r.total, content="2")
  inspect(unreachable_functions(r).length(), content="0")
}

///|
test "exports are parsed with names and indices" {
  let m = @wasm.parse_module(two_function_module())
  let es = @wasm.exports(m)
  inspect(es.length(), content="1")
  inspect(es[0].name, content="a")
  inspect(es[0].kind, content="0")
  inspect(es[0].index.reinterpret_as_int(), content="0")
}

///|
test "stripping a hand-built module keeps it parseable" {
  let m = @wasm.parse_module(two_function_module())
  let stripped = @wasm.strip_custom(m)
  inspect(stripped.length(), content=m.data.length().to_string())
  let re = @wasm.parse_module(stripped)
  inspect(re.sections.length(), content="4")
}
