///|
/// Locate a custom section by name and return its payload range (the bytes
/// after the name itself).
pub fn custom_payload(m : Module, want : String) -> (Int, Int)? {
  for s in m.sections {
    if s.id == 0 {
      let (nm, p) = read_name(m.data, s.content_start)
      if nm == want {
        let size = s.content_start + s.content_size - p
        return Some((p, size))
      }
    }
  }
  None
}

///|
/// Parse the `name` custom section and return the function-name subsection.
/// Debug builds carry it; release builds usually do not, in which case the
/// map is empty and callers fall back to indices.
pub fn function_names(m : Module) -> @hashmap.HashMap[UInt, String] {
  let out : @hashmap.HashMap[UInt, String] = @hashmap.HashMap([])
  match custom_payload(m, "name") {
    None => ()
    Some((start, size)) => {
      let data = m.data
      let end = start + size
      let mut pos = start
      while pos < end {
        let sub_id = data[pos].to_int()
        let (sub_size, p0) = read_u32(data, pos + 1)
        let n = sub_size.reinterpret_as_int()
        if p0 + n > end {
          // malformed subsection: stop rather than read past the section
          pos = end
        } else {
          if sub_id == 1 {
            let (count, p1) = read_u32(data, p0)
            let mut q = p1
            for _ in 0..<count.reinterpret_as_int() {
              if q < end {
                let (idx, p2) = read_u32(data, q)
                let (nm, p3) = read_name(data, p2)
                out.set(idx, nm)
                q = p3
              }
            }
          }
          pos = p0 + n
        }
      }
    }
  }
  out
}

///|
/// Name for a function index, or a stable fallback.
pub fn name_of(names : @hashmap.HashMap[UInt, String], idx : UInt) -> String {
  match names.get(idx) {
    Some(n) => n
    None => "func[" + idx.reinterpret_as_int().to_string() + "]"
  }
}
