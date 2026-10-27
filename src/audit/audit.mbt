///|
/// One finding from an audit run. `level` is "error" (blocks release),
/// "warn" (needs a human look) or "info".
pub struct Finding {
  level : String
  code : String
  message : String
}

///|
pub struct Report {
  size : Int
  custom_bytes : Int
  custom_pct : Int
  profile : String
  dead_functions : Int
  dead_bytes : Int
  budget : Int
  findings : Array[Finding]
}

///|
/// A debug build carries the name table and debug sections; in practice that
/// is more than a fifth of the file. Release builds keep ~110 bytes.
pub fn classify(custom_bytes : Int, size : Int) -> String {
  if size <= 0 {
    "empty"
  } else if custom_bytes * 100 / size >= 20 {
    "debug"
  } else {
    "release"
  }
}

///|
/// Audit a module against a size budget and a release expectation.
/// `budget` of 0 means "no budget set".
pub fn audit(m : @wasm.Module, budget : Int) -> Report {
  let size = m.data.length()
  let custom_bytes = @wasm.custom_bytes(m)
  let custom_pct = if size > 0 { custom_bytes * 100 / size } else { 0 }
  let profile = classify(custom_bytes, size)
  let reach = @analysis.analyze(m)
  let dead = @analysis.unreachable_functions(reach)
  let bodies = @wasm.function_bodies(m)
  let mut dead_bytes = 0
  for idx in dead {
    let body_idx = idx.reinterpret_as_int() - reach.imported
    if body_idx >= 0 && body_idx < bodies.length() {
      dead_bytes = dead_bytes + (bodies[body_idx].end - bodies[body_idx].start)
    }
  }
  let findings : Array[Finding] = []
  if profile == "debug" {
    findings.push({
      level: "error",
      code: "debug-build",
      message: "looks like a debug build: custom sections are " +
        custom_pct.to_string() +
        "% of the file (" +
        custom_bytes.to_string() +
        " bytes). Ship a --release build, or strip the module.",
    })
  }
  if budget > 0 && size > budget {
    findings.push({
      level: "error",
      code: "over-budget",
      message: "size " +
        size.to_string() +
        " exceeds the budget of " +
        budget.to_string() +
        " bytes by " +
        (size - budget).to_string() +
        " bytes.",
    })
  }
  if dead.length() > 0 {
    findings.push({
      level: "warn",
      code: "dead-code",
      message: dead.length().to_string() +
        " function(s) are unreachable (" +
        dead_bytes.to_string() +
        " body bytes). Harmless, but they inflate the module.",
    })
  }
  if findings.length() == 0 {
    findings.push({
      level: "info",
      code: "ok",
      message: "no blocking issue found.",
    })
  }
  { size, custom_bytes, custom_pct, profile, dead_functions: dead.length(), dead_bytes, budget, findings }
}

///|
/// True when no finding is at the "error" level.
pub fn passed(r : Report) -> Bool {
  let mut ok = true
  for f in r.findings {
    if f.level == "error" {
      ok = false
    }
  }
  ok
}

///|
pub fn error_count(r : Report) -> Int {
  let mut n = 0
  for f in r.findings {
    if f.level == "error" {
      n = n + 1
    }
  }
  n
}
