///|
/// Result of reachability analysis over the function index space.
pub struct Reach {
  imported : Int32
  defined : Int32
  total : Int32
  reachable : Array[Bool]
  roots : Array[UInt32]
  unsupported : Array[Int32]
  indirect_sites : Int32
}

///|
pub fn unreachable_functions(r : Reach) -> Array[UInt32] {
  let out : Array[UInt32] = []
  for i in 0..<r.total {
    if !r.reachable[i] {
      out.push(i.reinterpret_as_uint())
    }
  }
  out
}

///|
/// Skip a constant expression, returning the position after its `end`.
pub fn skip_expr(data : Bytes, pos : Int32) -> Int32 {
  let mut i = pos
  let mut depth = 0
  let mut done = false
  while !done && i < data.length() {
    let op = data[i].to_int()
    i = i + 1
    match op {
      0x0B => if depth == 0 { done = true } else { depth = depth - 1 }
      0x02 | 0x03 | 0x04 => depth = depth + 1
      0x41 => {
        let (_, p) = @wasm.read_i32(data, i)
        i = p
      }
      0x42 => {
        let (_, p) = @wasm.read_i32(data, i)
        i = p
      }
      0x43 => i = i + 4
      0x44 => i = i + 8
      0xD0 => i = i + 1
      0xD2 => {
        let (_, p) = @wasm.read_u32(data, i)
        i = p
      }
      0x23 => {
        let (_, p) = @wasm.read_u32(data, i)
        i = p
      }
      _ => ()
    }
  }
  i
}

///|
/// Scan a constant expression for a `ref.func` index. Used by expression-form
/// element segments (flags 4..7), whose entries are `ref.func <i> end` rather
/// than a raw index vector.
fn expr_ref_func(data : Bytes, pos : Int32) -> (UInt32?, Int32) {
  let mut i = pos
  let mut found : UInt32? = None
  let mut done = false
  while !done && i < data.length() {
    let op = data[i].to_int()
    i = i + 1
    match op {
      0x0B => done = true
      0xD2 => {
        let (idx, p) = @wasm.read_u32(data, i)
        found = Some(idx)
        i = p
      }
      0xD0 => i = i + 1
      0x41 | 0x42 => {
        let (_, p) = @wasm.read_i32(data, i)
        i = p
      }
      0x23 => {
        let (_, p) = @wasm.read_u32(data, i)
        i = p
      }
      0x6A | 0x6B | 0x6C | 0x7C => ()
      _ => done = true
    }
  }
  (found, i)
}

///|
/// Collect function indices referenced by the element section. Every one of
/// them is a root: an indirect call may reach any of them. All eight flag
/// forms are handled, including the expression forms (4..7).
pub fn element_roots(m : @wasm.Module) -> (Array[UInt32], Array[Int32]) {
  let roots : Array[UInt32] = []
  let unsupported : Array[Int32] = []
  match @wasm.section_of(m, 9) {
    None => ()
    Some(sec) => {
      let data = m.data
      let (count, p0) = @wasm.read_u32(data, sec.content_start)
      let mut pos = p0
      for _ in 0..<count.reinterpret_as_int() {
        let (flags, p1) = @wasm.read_u32(data, pos)
        match flags.reinterpret_as_int() {
          0 => {
            let p2 = skip_expr(data, p1)
            let (n, p3) = @wasm.read_u32(data, p2)
            let mut p4 = p3
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = @wasm.read_u32(data, p4)
              roots.push(idx)
              p4 = p
            }
            pos = p4
          }
          1 => {
            let (n, p2) = @wasm.read_u32(data, p1 + 1)
            let mut p3 = p2
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = @wasm.read_u32(data, p3)
              roots.push(idx)
              p3 = p
            }
            pos = p3
          }
          2 => {
            let (_, p2) = @wasm.read_u32(data, p1)
            let p3 = skip_expr(data, p2)
            let (n, p4) = @wasm.read_u32(data, p3 + 1)
            let mut p5 = p4
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = @wasm.read_u32(data, p5)
              roots.push(idx)
              p5 = p
            }
            pos = p5
          }
          3 => {
            let (n, p2) = @wasm.read_u32(data, p1 + 1)
            let mut p3 = p2
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = @wasm.read_u32(data, p3)
              roots.push(idx)
              p3 = p
            }
            pos = p3
          }
          4 => {
            let p2 = skip_expr(data, p1)
            let (n, p3) = @wasm.read_u32(data, p2)
            let mut p4 = p3
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = expr_ref_func(data, p4)
              match idx {
                Some(i) => roots.push(i)
                None => ()
              }
              p4 = p
            }
            pos = p4
          }
          5 => {
            // reftype (1 byte) + vec(expr)
            let (n, p2) = @wasm.read_u32(data, p1 + 1)
            let mut p3 = p2
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = expr_ref_func(data, p3)
              match idx {
                Some(i) => roots.push(i)
                None => ()
              }
              p3 = p
            }
            pos = p3
          }
          6 => {
            let (_, p2) = @wasm.read_u32(data, p1)
            let p3 = skip_expr(data, p2)
            // p3 points at reftype; vector count follows
            let (n, p4) = @wasm.read_u32(data, p3 + 1)
            let mut p5 = p4
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = expr_ref_func(data, p5)
              match idx {
                Some(i) => roots.push(i)
                None => ()
              }
              p5 = p
            }
            pos = p5
          }
          7 => {
            let (n, p2) = @wasm.read_u32(data, p1 + 1)
            let mut p3 = p2
            for _ in 0..<n.reinterpret_as_int() {
              let (idx, p) = expr_ref_func(data, p3)
              match idx {
                Some(i) => roots.push(i)
                None => ()
              }
              p3 = p
            }
            pos = p3
          }
          _ => {
            unsupported.push(flags.reinterpret_as_int())
            return (roots, unsupported)
          }
        }
      }
    }
  }
  (roots, unsupported)
}

///|
/// Breadth-first reachability from exports, the start function and element
/// segments. Imported functions have no body, so they are roots only when
/// exported and never scanned.
pub fn analyze(m : @wasm.Module) -> Reach {
  let imported = @wasm.imported_function_count(m)
  let defined = @wasm.defined_function_count(m)
  let total = imported + defined
  let reachable : Array[Bool] = []
  for _ in 0..<total {
    reachable.push(false)
  }
  let roots : Array[UInt32] = []
  for e in @wasm.exports(m) {
    if e.kind == 0 {
      roots.push(e.index)
    }
  }
  let (elem_roots, elem_unsupported) = element_roots(m)
  for r in elem_roots {
    roots.push(r)
  }
  match @wasm.section_of(m, 8) {
    None => ()
    Some(sec) => {
      let (idx, _) = @wasm.read_u32(m.data, sec.content_start)
      roots.push(idx)
    }
  }
  let unsupported : Array[Int32] = []
  for u in elem_unsupported {
    unsupported.push(u)
  }
  let queue : Array[UInt32] = []
  for r in roots {
    let i = r.reinterpret_as_int()
    if i >= 0 && i < total && !reachable[i] {
      reachable[i] = true
      queue.push(r)
    }
  }
  let bodies = @wasm.function_bodies(m)
  let mut head = 0
  let mut indirect_sites = 0
  while head < queue.length() {
    let idx = queue[head]
    head = head + 1
    let body_idx = idx.reinterpret_as_int() - imported
    if body_idx >= 0 && body_idx < bodies.length() {
      let scan = @wasm.scan_body(m.data, bodies[body_idx])
      if scan.has_indirect {
        indirect_sites = indirect_sites + 1
      }
      for op in scan.unsupported {
        let mut seen = false
        for u in unsupported {
          if u == op {
            seen = true
          }
        }
        if !seen {
          unsupported.push(op)
        }
      }
      for c in scan.calls {
        let ci = c.reinterpret_as_int()
        if ci >= 0 && ci < total && !reachable[ci] {
          reachable[ci] = true
          queue.push(c)
        }
      }
      for r in scan.ref_funcs {
        let ri = r.reinterpret_as_int()
        if ri >= 0 && ri < total && !reachable[ri] {
          reachable[ri] = true
          queue.push(r)
        }
      }
    }
  }
  { imported, defined, total, reachable, roots, unsupported, indirect_sites, }
}
