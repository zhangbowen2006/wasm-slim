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
/// Digits only; used for --budget. Ignores anything that is not 0-9.
fn parse_uint(s : String) -> Int {
  let mut n = 0
  for c in s.to_array() {
    let d = c.to_int()
    if d >= 48 && d <= 57 {
      n = n * 10 + (d - 48)
    }
  }
  n
}

///|
fn usage() -> Unit {
  println("usage:")
  println("  wasmslim <file.wasm>                 size attribution")
  println("  wasmslim <file.wasm> --check         release gate (exit 1 on error)")
  println("  wasmslim <file.wasm> --check --budget 16384")
  println("  wasmslim <file.wasm> --strip [--out <path>]")
}

///|
fn main raise {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  let path = args[1]
  let data = @fs.read_file_to_bytes(path)
  let m = @wasm.parse_module(data)
  let total = data.length()

  let mut do_check = false
  let mut do_strip = false
  let mut do_debug = false
  let mut budget = 0
  let mut out_path = path + ".stripped.wasm"
  let mut i = 2
  while i < args.length() {
    let a = args[i]
    if a == "--check" {
      do_check = true
    } else if a == "--strip" {
      do_strip = true
    } else if a == "--debug" {
      do_debug = true
    } else if a == "--budget" && i + 1 < args.length() {
      budget = parse_uint(args[i + 1])
      i = i + 1
    } else if a == "--out" && i + 1 < args.length() {
      out_path = args[i + 1]
      i = i + 1
    }
    i = i + 1
  }

  if do_check {
    let r = @audit.audit(m, budget)
    println("file      \{path}")
    println("size      \{human(total)} (\{total} bytes)")
    println(
      "profile   \{r.profile} (custom sections \{r.custom_pct}%)",
    )
    println("dead code \{r.dead_functions} function(s), \{r.dead_bytes} body bytes")
    if budget > 0 {
      println("budget    \{budget} bytes")
    } else {
      println("budget    not set")
    }
    println("")
    for f in r.findings {
      println("  \{f.level}  \{f.code}  \{f.message}")
    }
    println("")
    let verdict = if @audit.passed(r) { "PASS" } else { "FAIL" }
    println("verdict   \{verdict}")
    if !@audit.passed(r) {
      // abort carries the exit code (1) so CI can gate on it
      abort("audit failed")
    }
    return
  }

  if do_strip {
    let stripped = @wasm.strip_custom(m)
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

  if do_debug {
    let bodies = @wasm.function_bodies(m)
    let mut bi = 0
    while bi < bodies.length() {
      let b = bodies[bi]
      let scan = @wasm.scan_body(m.data, b)
      if scan.unsupported.length() > 0 {
        let at = scan.unsupported_at[0]
        let bad = scan.unsupported[0]
        println("func[" + bi.to_string() + "] body=" + b.start.to_string() + ".." + b.end.to_string() + " bad op=" + bad.to_string() + " at=" + at.to_string())
      }
      bi = bi + 1
    }
    return
  }

  // default: attribution
  println("file    \{path}")
  println("size    \{human(total)} (\{total} bytes)")
  println("sections \{m.sections.length()}")
  for s in m.sections {
    let pct = s.content_size * 100 / total
    println("  id=\{s.id}  \{human(s.content_size)}  \{pct}%")
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
}
