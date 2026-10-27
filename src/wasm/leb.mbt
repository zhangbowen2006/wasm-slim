///|
/// Unsigned LEB128 as used by the WebAssembly binary format for sizes,
/// counts and indices. Returns the value and the position after it.
pub fn read_u32(data : Bytes, pos : Int32) -> (UInt32, Int32) {
  let mut result : UInt32 = 0U
  let mut shift = 0
  let mut i = pos
  let mut done = false
  let mut taken = 0
  while !done && i < data.length() {
    if taken >= 5 {
      // A u32 LEB128 cannot occupy more than 5 bytes; longer means the file
      // is malformed rather than truncated.
      println("error: LEB128 value at " + pos.to_string() + " exceeds 5 bytes")
      abort("bad leb128")
    }
    taken = taken + 1
    let b = data[i].to_int()
    result = result | ((b & 0x7F).reinterpret_as_uint() << shift)
    i = i + 1
    if (b & 0x80) == 0 {
      done = true
    } else {
      shift = shift + 7
    }
  }
  (result, i)
}

///|
/// Signed LEB128, used for constant expressions and block types.
pub fn read_i32(data : Bytes, pos : Int32) -> (Int32, Int32) {
  let mut result = 0
  let mut shift = 0
  let mut i = pos
  let mut byte = 0
  let mut done = false
  while !done && i < data.length() {
    byte = data[i].to_int()
    result = result | ((byte & 0x7F) << shift)
    shift = shift + 7
    i = i + 1
    if (byte & 0x80) == 0 {
      done = true
    }
  }
  // Sign-extend when the last payload bit is set.
  if shift < 32 && (byte & 0x40) != 0 {
    result = result | (0 - (1 << shift))
  }
  (result, i)
}

///|
/// Encode an unsigned integer as LEB128. Kept here so the rewriter can emit
/// the same encoding it parses.
pub fn write_u32(out : Array[Byte], value : UInt32) -> Unit {
  let mut v = value
  while true {
    let low = (v & 0x7FU).reinterpret_as_int()
    v = v >> 7
    if v == 0U {
      out.push(low.to_byte())
      break
    }
    out.push((low | 0x80).to_byte())
  }
}

///|
pub fn write_u32_bytes(value : UInt32) -> Bytes {
  let out : Array[Byte] = []
  write_u32(out, value)
  Bytes::from_array(out)
}
