///|
fn human(n : Int) -> String {
  if n >= 1024 {
    let whole = n / 1024
    let frac = n % 1024 * 10 / 1024
    "\{whole}.\{frac} KiB"
  } else {
    "\{n} B"
  }
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 2 {
    println("usage: wasmslim <file.wasm>")
    return
  }
  let path = args[1]
  let data = @fs.read_file_to_bytes(path)
  let m = @wasm.parse_module(data)
  let total = data.length()

  println("file    \{path}")
  println("size    \{human(total)} (\{total} bytes)")
  println("sections \{m.sections.length()}")
  for s in m.sections {
    let pct = s.content_size * 100 / total
    println("  id=\{s.id}  \{human(s.content_size)}  \{pct}%")
  }

  if args.length() > 2 && args[2] == "--strip" {
    let stripped = @wasm.strip_custom(m)
    let out_path = if args.length() > 4 && args[3] == "--out" { args[4] } else { path + ".stripped.wasm" }
    @fs.write_bytes_to_file(out_path, stripped) catch {
      _ => {
        println("cannot write " + out_path)
        return
      }
    }
    let saved = total - stripped.length()
    println("stripped   " + out_path)
    println("before     " + human(total) + " (" + total.to_string() + " bytes)")
    println("after      " + human(stripped.length()) + " (" + stripped.length().to_string() + " bytes)")
    println("saved      " + human(saved) + " (" + (saved * 100 / total).to_string() + "%)")
    println("removed    custom sections only; code/type/export untouched")
    return
  }
  if args.length() > 2 && args[2] == "--debug" {
    let bodies = @wasm.function_bodies(m)
    let mut i = 0
    while i < bodies.length() {
      let b = bodies[i]
      let scan = @wasm.scan_body(m.data, b)
      if scan.unsupported.length() > 0 {
        let at = scan.unsupported_at[0]
        let bad = scan.unsupported[0]
        println("func[" + i.to_string() + "] body=" + b.start.to_string() + ".." + b.end.to_string() + " bad op=" + bad.to_string() + " at=" + at.to_string())
        let from = if at - 8 > b.start { at - 8 } else { b.start }
        let to = if at + 8 < b.end { at + 8 } else { b.end }
        let mut hex = ""
        let mut j = from
        while j < to {
          hex = hex + " " + m.data[j].to_int().to_string()
          j = j + 1
        }
        println("  bytes:" + hex)
      }
      i = i + 1
    }
    return
  }
  let r = @analysis.analyze(m)
  let mut reach = 0
  for b in r.reachable {
    if b {
      reach = reach + 1
    }
  }
  let dead = @analysis.unreachable_functions(r)
  let bodies = @wasm.function_bodies(m)
  let mut dead_bytes = 0
  for idx in dead {
    let body_idx = idx.reinterpret_as_int() - r.imported
    if body_idx >= 0 && body_idx < bodies.length() {
      dead_bytes = dead_bytes + (bodies[body_idx].end - bodies[body_idx].start)
    }
  }
  println("")
  println("functions  imported=\{r.imported} defined=\{r.defined} total=\{r.total}")
  println("reachable  \{reach}")
  println("unreachable \{dead.length()}  bodies=\{human(dead_bytes)}")
  if r.indirect_sites > 0 {
    println("note       \{r.indirect_sites} function(s) use call_indirect; element targets are kept as roots")
  }
  if r.unsupported.length() > 0 {
    let mut ops = ""
    for u in r.unsupported {
      ops = ops + " 0x" + u.to_string()
    }
    println("warning    \{r.unsupported.length()} unsupported opcode(s):\{ops}")
  }
  if dead.length() > 0 {
    println("")
    println("dead function indices (first 20):")
    let mut shown = 0
    for idx in dead {
      if shown < 20 {
        println("  func[\{idx}]")
        shown = shown + 1
      }
    }
  }
}
