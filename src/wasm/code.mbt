///|
/// One function body inside the code section, expressed as a byte range.
pub struct FuncBody {
  start : Int32
  end : Int32
}

///|
/// What a single function body references. `unsupported` records opcodes this
/// scanner does not understand, so the caller can refuse to delete anything
/// rather than guess.
pub struct RefScan {
  calls : Array[UInt32]
  ref_funcs : Array[UInt32]
  mut has_indirect : Bool
  unsupported : Array[Int32]
  unsupported_at : Array[Int32]
}

///|
pub fn new_ref_scan() -> RefScan {
  {
    calls: [],
    ref_funcs: [],
    has_indirect: false,
    unsupported: [],
    unsupported_at: [],
  }
}

///|
/// Skip a block type: either a single byte (0x40 empty, or a value type) or a
/// signed LEB128 type index.
pub fn skip_block_type(data : Bytes, pos : Int32) -> Int32 {
  let b = data[pos].to_int()
  if b == 0x40 {
    pos + 1
  } else if b >= 0x7B && b <= 0x7F {
    // numeric / vector value types
    pos + 1
  } else if b >= 0x63 && b <= 0x67 {
    // reference types (GC proposal): one byte, optionally followed by a heap type
    if b == 0x63 || b == 0x64 {
      let (_, p) = read_i32(data, pos + 1)
      p
    } else {
      pos + 1
    }
  } else {
    let (_, p) = read_i32(data, pos)
    p
  }
}

///|
/// Skip a memory argument: align (u32) + offset (u32).
fn skip_memarg(data : Bytes, pos : Int32) -> Int32 {
  let (_, p1) = read_u32(data, pos)
  let (_, p2) = read_u32(data, p1)
  p2
}

///|
/// Scan one function body for calls, function references and globals.
/// Unknown opcodes are recorded instead of silently skipped.
pub fn scan_body(data : Bytes, body : FuncBody) -> RefScan {
  let scan = new_ref_scan()
  let mut pos = body.start
  // local declarations: count, then (n, valtype)*
  let (local_groups, p0) = read_u32(data, pos)
  pos = p0
  for _ in 0..<local_groups.reinterpret_as_int() {
    let (_, p1) = read_u32(data, pos)
    pos = p1 + 1
  }
  while pos < body.end {
    let op = data[pos].to_int()
    pos = pos + 1
    match op {
      0x00 | 0x01 | 0x05 | 0x0A | 0x0B | 0x0F | 0x1A | 0x1B | 0xD1 => ()
      // control
      0x02 | 0x03 | 0x04 => pos = skip_block_type(data, pos)
      0x0C | 0x0D => {
        let (_, p) = read_u32(data, pos)
        pos = p
      }
      0x0E => {
        let (n, p) = read_u32(data, pos)
        pos = p
        for _ in 0..<n.reinterpret_as_int() {
          let (_, p2) = read_u32(data, pos)
          pos = p2
        }
        let (_, p3) = read_u32(data, pos)
        pos = p3
      }
      // calls
      0x10 | 0x12 => {
        let (idx, p) = read_u32(data, pos)
        scan.calls.push(idx)
        pos = p
      }
      0x11 | 0x13 => {
        let (_, p) = read_u32(data, pos)
        let (_, p2) = read_u32(data, p)
        scan.has_indirect = true
        pos = p2
      }
      // parametric
      0x1C => {
        let (n, p) = read_u32(data, pos)
        pos = p + n.reinterpret_as_int()
      }
      // variables and globals
      0x20 | 0x21 | 0x22 | 0x23 | 0x24 => {
        let (_, p) = read_u32(data, pos)
        pos = p
      }
      0x25 | 0x26 => {
        let (_, p) = read_u32(data, pos)
        pos = p
      }
      // memory load/store
      0x28
      | 0x29
      | 0x2A
      | 0x2B
      | 0x2C
      | 0x2D
      | 0x2E
      | 0x2F
      | 0x30
      | 0x31
      | 0x32
      | 0x33
      | 0x34
      | 0x35
      | 0x36
      | 0x37
      | 0x38
      | 0x39
      | 0x3A
      | 0x3B
      | 0x3C
      | 0x3D
      | 0x3E => pos = skip_memarg(data, pos)
      0x3F | 0x40 => pos = pos + 1
      // constants
      0x41 => {
        let (_, p) = read_i32(data, pos)
        pos = p
      }
      0x42 => {
        let (_, p) = read_i32(data, pos)
        pos = p
      }
      0x43 => pos = pos + 4
      0x44 => pos = pos + 8
      // reference types
      0xD0 => pos = pos + 1
      0xD2 => {
        let (idx, p) = read_u32(data, pos)
        scan.ref_funcs.push(idx)
        pos = p
      }
      // numeric instructions: no immediates
      0x45
      | 0x46
      | 0x47
      | 0x48
      | 0x49
      | 0x4A
      | 0x4B
      | 0x4C
      | 0x4D
      | 0x4E
      | 0x4F
      | 0x50
      | 0x51
      | 0x52
      | 0x53
      | 0x54
      | 0x55
      | 0x56
      | 0x57
      | 0x58
      | 0x59
      | 0x5A
      | 0x5B
      | 0x5C
      | 0x5D
      | 0x5E
      | 0x5F
      | 0x60
      | 0x61
      | 0x62
      | 0x63
      | 0x64
      | 0x65
      | 0x66
      | 0x67
      | 0x68
      | 0x69
      | 0x6A
      | 0x6B
      | 0x6C
      | 0x6D
      | 0x6E
      | 0x6F
      | 0x70
      | 0x71
      | 0x72
      | 0x73
      | 0x74
      | 0x75
      | 0x76
      | 0x77
      | 0x78
      | 0x79
      | 0x7A
      | 0x7B
      | 0x7C
      | 0x7D
      | 0x7E
      | 0x7F
      | 0x80
      | 0x81
      | 0x82
      | 0x83
      | 0x84
      | 0x85
      | 0x86
      | 0x87
      | 0x88
      | 0x89
      | 0x8A
      | 0x8B
      | 0x8C
      | 0x8D
      | 0x8E
      | 0x8F
      | 0x90
      | 0x91
      | 0x92
      | 0x93
      | 0x94
      | 0x95
      | 0x96
      | 0x97
      | 0x98
      | 0x99
      | 0x9A
      | 0x9B
      | 0x9C
      | 0x9D
      | 0x9E
      | 0x9F
      | 0xA0
      | 0xA1
      | 0xA2
      | 0xA3
      | 0xA4
      | 0xA5
      | 0xA6
      | 0xA7
      | 0xA8
      | 0xA9
      | 0xAA
      | 0xAB
      | 0xAC
      | 0xAD
      | 0xAE
      | 0xAF
      | 0xB0
      | 0xB1
      | 0xB2
      | 0xB3
      | 0xB4
      | 0xB5
      | 0xB6
      | 0xB7
      | 0xB8
      | 0xB9
      | 0xBA
      | 0xBB
      | 0xBC
      | 0xBD
      | 0xBE
      | 0xBF
      | 0xC0
      | 0xC1
      | 0xC2
      | 0xC3
      | 0xC4 => ()
      // 0xFC prefix: saturating conversions and bulk memory
      0xFC => {
        let (sub, p) = read_u32(data, pos)
        pos = p
        match sub.reinterpret_as_int() {
          0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 => ()
          8 => {
            // memory.init: dataidx + memidx
            let (_, p1) = read_u32(data, pos)
            let (_, p2) = read_u32(data, p1)
            pos = p2
          }
          9 => {
            let (_, p1) = read_u32(data, pos)
            pos = p1
          }
          10 => {
            // memory.copy: two memidx
            let (_, p1) = read_u32(data, pos)
            let (_, p2) = read_u32(data, p1)
            pos = p2
          }
          11 => {
            let (_, p1) = read_u32(data, pos)
            pos = p1
          }
          12 => {
            // table.init: elemidx + tableidx
            let (_, p1) = read_u32(data, pos)
            let (_, p2) = read_u32(data, p1)
            pos = p2
          }
          13 => {
            let (_, p1) = read_u32(data, pos)
            pos = p1
          }
          14 | 15 | 16 | 17 => {
            let (_, p1) = read_u32(data, pos)
            let (_, p2) = read_u32(data, p1)
            pos = p2
          }
          _ => {
            scan.unsupported.push(op)
            scan.unsupported_at.push(pos - 1)
            break
          }
        }
      }
      // 0xFB prefix: GC instructions. Record as unsupported for now.
      0xFB => {
        scan.unsupported.push(op)
        scan.unsupported_at.push(pos - 1)
        break
      }
      // 0xFD prefix: SIMD, fixed-width immediate in most cases
      0xFD => {
        let (sub, p) = read_u32(data, pos)
        pos = p
        match sub.reinterpret_as_int() {
          // v128.load / load8x8 / ... / store: memarg only
          0..<=11 | 94 | 95 => pos = skip_memarg(data, pos)
          // v128.const / i8x16.shuffle: 16 immediate bytes
          12 | 13 => pos = pos + 16
          // swizzle + splat: no immediates
          14..<=20 => ()
          // extract_lane / replace_lane: one lane byte
          21..<=34 => pos = pos + 1
          // comparisons, bitwise, any_true: no immediates
          35..<=83 => ()
          // load/store lane: memarg + one lane byte
          84..<=93 => {
            let p1 = skip_memarg(data, pos)
            pos = p1 + 1
          }
          // remaining SIMD arithmetic takes no immediates
          96..<=300 => ()
          _ => {
            // conservative: treat as unsupported so we never mis-delete
            scan.unsupported.push(op)
            scan.unsupported_at.push(pos - 1)
            break
          }
        }
      }
      _ => {
        scan.unsupported.push(op)
        scan.unsupported_at.push(pos - 1)
        break
      }
    }
  }
  scan
}

///|
/// Byte ranges of every function body in the code section.
pub fn function_bodies(m : Module) -> Array[FuncBody] {
  let out : Array[FuncBody] = []
  match section_of(m, 10) {
    None => ()
    Some(sec) => {
      let data = m.data
      let (count, p0) = read_u32(data, sec.content_start)
      let mut pos = p0
      for _ in 0..<count.reinterpret_as_int() {
        let (size, p1) = read_u32(data, pos)
        let n = size.reinterpret_as_int()
        out.push({ start: p1, end: p1 + n, })
        pos = p1 + n
      }
    }
  }
  out
}
