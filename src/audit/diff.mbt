///|
/// Per-function size change between two module versions.
pub struct FuncDelta {
  name : String
  old_size : Int
  new_size : Int
}

///|
pub fn delta_of(d : FuncDelta) -> Int {
  d.new_size - d.old_size
}

///|
pub struct DiffReport {
  old_size : Int
  new_size : Int
  old_functions : Int
  new_functions : Int
  added : Array[FuncDelta]
  removed : Array[FuncDelta]
  changed : Array[FuncDelta]
  named : Bool
}

///|
/// Function name -> body size for one module.
fn collect(m : @wasm.Module) -> (@hashmap.HashMap[String, Int], Bool) {
  let names = @wasm.function_names(m)
  let bodies = @wasm.function_bodies(m)
  let imported = @wasm.imported_function_count(m)
  let out : @hashmap.HashMap[String, Int] = @hashmap.HashMap([])
  let mut i = 0
  while i < bodies.length() {
    let b = bodies[i]
    let idx = (imported + i).reinterpret_as_uint()
    let nm = @wasm.name_of(names, idx)
    out.set(nm, b.end - b.start)
    i = i + 1
  }
  (out, names.length() > 0)
}

///|
/// Compare two modules function by function. Matching is by name; when the
/// name section is missing both sides fall back to `func[<index>]`, which is
/// only meaningful if the function order did not shift.
pub fn diff(old : @wasm.Module, new : @wasm.Module) -> DiffReport {
  let (old_map, old_named) = collect(old)
  let (new_map, new_named) = collect(new)
  let added : Array[FuncDelta] = []
  let removed : Array[FuncDelta] = []
  let changed : Array[FuncDelta] = []
  for k, v in new_map {
    match old_map.get(k) {
      None => added.push({ name: k, old_size: 0, new_size: v })
      Some(prev) => {
        if prev != v {
          changed.push({ name: k, old_size: prev, new_size: v })
        }
      }
    }
  }
  for k, v in old_map {
    if new_map.get(k) is None {
      removed.push({ name: k, old_size: v, new_size: 0 })
    }
  }
  {
    old_size: old.data.length(),
    new_size: new.data.length(),
    old_functions: old_map.length(),
    new_functions: new_map.length(),
    added,
    removed,
    changed,
    named: old_named && new_named,
  }
}

///|
/// Sort by absolute delta, descending, and keep the first `n`.
fn top_by_abs(items : Array[FuncDelta], n : Int) -> Array[FuncDelta] {
  let mut i = 0
  while i < items.length() {
    let mut best = i
    let mut j = i + 1
    while j < items.length() {
      let dj = delta_of(items[j])
      let db = delta_of(items[best])
      let aj = if dj < 0 { -dj } else { dj }
      let ab = if db < 0 { -db } else { db }
      if aj > ab {
        best = j
      }
      j = j + 1
    }
    let tmp = items[i]
    items[i] = items[best]
    items[best] = tmp
    i = i + 1
  }
  let out : Array[FuncDelta] = []
  let mut k = 0
  while k < n && k < items.length() {
    out.push(items[k])
    k = k + 1
  }
  out
}

///|
pub fn top_changes(r : DiffReport, n : Int) -> Array[FuncDelta] {
  let all : Array[FuncDelta] = []
  for d in r.added {
    all.push(d)
  }
  for d in r.changed {
    all.push(d)
  }
  for d in r.removed {
    all.push(d)
  }
  top_by_abs(all, n)
}
