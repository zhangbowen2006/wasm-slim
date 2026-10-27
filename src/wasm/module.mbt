///|
/// One section of a WebAssembly module: its id and the byte range holding its
/// content (excluding the id byte and the size prefix).
pub struct Section {
  id : Int32
  content_start : Int32
  content_size : Int32
}

///|
pub struct Module {
  data : Bytes
  sections : Array[Section]
}

///|
/// Refuse to read past the end of the file. A malformed module must fail with
/// a message that names the offset, not with an index-out-of-bounds stack.
pub fn ensure(data : Bytes, pos : Int32, need : Int32, what : String) -> Unit {
  if pos < 0 || need < 0 || pos + need > data.length() {
    // `abort` drops its message on the wasm backend, so print first.
    println(
      "error: malformed module: " +
      what +
      " at " +
      pos.to_string() +
      " needs " +
      need.to_string() +
      " bytes, file has " +
      data.length().to_string(),
    )
    abort("malformed module")
  }
}

///|
pub fn is_wasm(data : Bytes) -> Bool {
  data.length() >= 8 &&
  data[0].to_int() == 0x00 &&
  data[1].to_int() == 0x61 &&
  data[2].to_int() == 0x73 &&
  data[3].to_int() == 0x6D
}

///|
/// Walk the section table. Unknown ids are kept so a rewrite can copy them
/// through unchanged instead of silently dropping data.
pub fn parse_module(data : Bytes) -> Module {
  let sections : Array[Section] = []
  if !is_wasm(data) {
    println(
      "error: not a WebAssembly module (need 8+ bytes starting with \\0asm; file has " +
      data.length().to_string() +
      " bytes)",
    )
    abort("not wasm")
  }
  let mut pos = 8
  while pos < data.length() {
    let id = data[pos].to_int()
    let (size, after) = read_u32(data, pos + 1)
    let n = size.reinterpret_as_int()
    ensure(data, after, n, "section " + id.to_string())
    sections.push({ id, content_start: after, content_size: n, })
    pos = after + n
  }
  { data, sections, }
}

///|
pub fn section_of(m : Module, id : Int32) -> Section? {
  let mut found : Section? = None
  for s in m.sections {
    if s.id == id && found is None {
      found = Some(s)
    }
  }
  found
}

///|
pub fn read_name(data : Bytes, pos : Int32) -> (String, Int32) {
  let (len, p) = read_u32(data, pos)
  let n = len.reinterpret_as_int()
  ensure(data, p, n, "name")
  let raw = data[p:p + n]
  (@utf8.decode(raw) catch { _ => "" }, p + n)
}

///|
pub fn skip_limits(data : Bytes, pos : Int32) -> Int32 {
  let flags = data[pos].to_int()
  let (_, p) = read_u32(data, pos + 1)
  if flags == 0 {
    p
  } else {
    let (_, p2) = read_u32(data, p)
    p2
  }
}

///|
pub fn skip_global_type(_data : Bytes, pos : Int32) -> Int32 {
  // valtype (1 byte) + mutability (1 byte)
  pos + 2
}

///|
pub fn skip_table_type(data : Bytes, pos : Int32) -> Int32 {
  // elemtype (1 byte) + limits
  skip_limits(data, pos + 1)
}

///|
pub struct Export {
  name : String
  kind : Int32
  index : UInt32
}

///|
pub fn exports(m : Module) -> Array[Export] {
  let out : Array[Export] = []
  match section_of(m, 7) {
    None => ()
    Some(sec) => {
      let data = m.data
      let (count, p0) = read_u32(data, sec.content_start)
      let mut pos = p0
      for _ in 0..<count.reinterpret_as_int() {
        let (name, p1) = read_name(data, pos)
        let kind = data[p1].to_int()
        let (index, p2) = read_u32(data, p1 + 1)
        out.push({ name, kind, index, })
        pos = p2
      }
    }
  }
  out
}

///|
pub fn imported_function_count(m : Module) -> Int32 {
  let mut funcs = 0
  match section_of(m, 2) {
    None => ()
    Some(sec) => {
      let data = m.data
      let (count, p0) = read_u32(data, sec.content_start)
      let mut pos = p0
      for _ in 0..<count.reinterpret_as_int() {
        let (_, p1) = read_name(data, pos)
        let (_, p2) = read_name(data, p1)
        let kind = data[p2].to_int()
        let mut p3 = p2 + 1
        match kind {
          0 => {
            let (_, p) = read_u32(data, p3)
            p3 = p
            funcs = funcs + 1
          }
          1 => p3 = skip_table_type(data, p3)
          2 => p3 = skip_limits(data, p3)
          3 => p3 = skip_global_type(data, p3)
          _ => abort("unknown import kind")
        }
        pos = p3
      }
    }
  }
  funcs
}

///|
pub fn defined_function_count(m : Module) -> Int32 {
  match section_of(m, 3) {
    None => 0
    Some(sec) => {
      let (count, _) = read_u32(m.data, sec.content_start)
      count.reinterpret_as_int()
    }
  }
}

///|
/// Copy every section except custom ones (id 0). Returns a new module image:
/// magic + version + the surviving sections with their original size prefixes.
pub fn strip_custom(m : Module) -> Bytes {
  let out : Array[Byte] = []
  // magic
  out.push(b'\x00')
  out.push(b'\x61')
  out.push(b'\x73')
  out.push(b'\x6D')
  // version 1
  out.push(b'\x01')
  out.push(b'\x00')
  out.push(b'\x00')
  out.push(b'\x00')
  for s in m.sections {
    if s.id != 0 {
      out.push(s.id.to_byte())
      let size_bytes = write_u32_bytes(s.content_size.reinterpret_as_uint())
      for b in size_bytes {
        out.push(b)
      }
      let mut i = s.content_start
      let end = s.content_start + s.content_size
      while i < end {
        out.push(m.data[i])
        i = i + 1
      }
    }
  }
  Bytes::from_array(out)
}

///|
/// Sum of the custom-section bytes, i.e. what strip_custom removes.
pub fn custom_bytes(m : Module) -> Int32 {
  let mut total = 0
  for s in m.sections {
    if s.id == 0 {
      total = total + s.content_size
    }
  }
  total
}
