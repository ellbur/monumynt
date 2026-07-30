// ============================================================================
// EditorPocTest — exercises src/EditorPoc.res, the working miniature of
// plans/editor-state-management-design.md (`npm run poc`).
//
// The assertions are the design doc's own claims, made countable: the unit
// counted is transfer-function runs (`stats.computes`), and the oracle for
// every scenario is `checkFresh` — the same pure function with the store
// removed. The seeded-random harness at the end is the doc's test protocol:
// scripted + seeded edit sequences run twice, once through the store, once
// fresh, asserting equal types and witnesses at every step.
// ============================================================================

open EditorPoc

let passCount = ref(0)
let failCount = ref(0)
let pass = (msg: string) => {
  Console.log("PASS: " ++ msg)
  passCount := passCount.contents + 1
}
let fail = (msg: string) => {
  Console.log("FAIL: " ++ msg)
  failCount := failCount.contents + 1
}
let check = (msg: string, b: bool) => b ? pass(msg) : fail(msg)
let checkInt = (msg: string, actual: int, expected: int) =>
  actual == expected
    ? pass(msg ++ " (" ++ Int.toString(actual) ++ ")")
    : fail(msg ++ " — expected " ++ Int.toString(expected) ++ ", got " ++ Int.toString(actual))
let section = (name: string) => Console.log("\n=== " ++ name ++ " ===")

let getOrDie = (o: option<'a>, what: string): 'a =>
  switch o {
  | Some(v) => v
  | None => failwith(what)
  }

let rec leftmostLeaf = (t: term): term =>
  switch children(t)->Array.get(0) {
  | None => t
  | Some(c) => leftmostLeaf(c)
  }

// How many nodes in `t` read variable `x` (have it free) — the exact set of
// records whose env-slice key changes when x's binding changes type.
let rec countReading = (store: store, t: term, x: string): int =>
  (freeVars(store, t)->Array.includes(x) ? 1 : 0) +
  children(t)->Array.reduce(0, (acc, c) => acc + countReading(store, c, x))

let rec deepAdd = (depth: int, leaf: unit => term): term =>
  depth == 0 ? leaf() : mkAdd(deepAdd(depth - 1, leaf), deepAdd(depth - 1, leaf))

// ---------------------------------------------------------------------------
section("basic typing — the from-scratch oracle")
// ---------------------------------------------------------------------------

let idInt = mkLam("x", TInt, mkVar("x"))
Console.log("  " ++ termToString(idInt) ++ "  :  " ++ resultToString(checkFresh(list{}, idInt)))
check(
  "\\x:Int. x has type Int -> Int",
  switch checkFresh(list{}, idInt).ty {
  | Some(TFun(TInt, TInt)) => true
  | _ => false
  },
)

let apOk = mkApp(mkLam("x", TInt, mkAdd(mkVar("x"), mkInt(1))), mkInt(41))
check(
  "(\\x:Int. x + 1) 41 has type Int, no witnesses",
  switch checkFresh(list{}, apOk) {
  | {ty: Some(TInt), witnesses: []} => true
  | _ => false
  },
)

let apBad = mkApp(mkLam("x", TInt, mkVar("x")), mkBool(true))
let rBad = checkFresh(list{}, apBad)
Console.log("  " ++ termToString(apBad) ++ "  :  " ++ resultToString(rBad))
check(
  "(\\x:Int. x) true is witnessed as an argument mismatch",
  rBad.ty == None && Array.length(rBad.witnesses) == 1,
)

let unbound = mkAdd(mkVar("q"), mkInt(1))
let rUnbound = checkFresh(list{}, unbound)
check("unbound variable is witnessed once and stays quiet upstream",
  rUnbound.ty == None && Array.length(rUnbound.witnesses) == 1)

let ifBad = mkIf(mkBool(true), mkInt(1), mkBool(false))
check(
  "if branches disagreeing is witnessed",
  Array.length(checkFresh(list{}, ifBad).witnesses) == 1,
)

let shadow = mkLet(
  "x",
  mkInt(1),
  mkLet("x", mkBool(true), mkIf(mkVar("x"), mkInt(1), mkInt(2))),
)
let sShadow = makeSession(shadow)
check(
  "shadowing binds nearest, identically through store and oracle",
  switch checkHead(sShadow) {
  | {ty: Some(TInt), witnesses: []} => true
  | _ => false
  } &&
  resultEqual(checkHead(sShadow), checkFresh(list{}, shadow)),
)

// ---------------------------------------------------------------------------
// The big two-cone program the remaining scenarios edit:
//   let x = 1 in <left cone: depth-4 Add tree over ints and x>
//              + <right cone: depth-4 Add tree over ints only>
// 65 records; the right cone never reads x.
// ---------------------------------------------------------------------------

let leafCounter = ref(0)
let altLeaf = () => {
  leafCounter := leafCounter.contents + 1
  mod(leafCounter.contents, 2) == 0 ? mkVar("x") : mkInt(leafCounter.contents)
}
let intLeaf = () => {
  leafCounter := leafCounter.contents + 1
  mkInt(leafCounter.contents)
}
let leftCone = deepAdd(4, altLeaf)
let rightCone = deepAdd(4, intLeaf)
let boundLit = mkInt(1)
let bigBody = mkAdd(leftCone, rightCone)
let bigProg = mkLet("x", boundLit, bigBody)
let progSize = size(bigProg)

// ---------------------------------------------------------------------------
section("cold check costs the program once; a re-demand costs nothing")
// ---------------------------------------------------------------------------

let s = makeSession(bigProg)
let r0 = checkHead(s)
Console.log(
  "  program: " ++ Int.toString(progSize) ++ " records, type " ++ resultToString(r0),
)
check(
  "big program types to Int with no witnesses",
  switch r0 {
  | {ty: Some(TInt), witnesses: []} => true
  | _ => false
  },
)
checkInt("cold check runs the transfer once per record", s.store.stats.computes, progSize)
resetStats(s.store)
let r0b = checkHead(s)
checkInt("re-demand: zero transfers", s.store.stats.computes, 0)
checkInt("re-demand: one hit, at the root", s.store.stats.hits, 1)
check("and the same answer", resultEqual(r0, r0b))

// ---------------------------------------------------------------------------
section("the worked keystroke: edit deep in one cone")
// ---------------------------------------------------------------------------

let deepLeaf = leftmostLeaf(leftCone)
resetStats(s.store)
let h3 = applyEdit(s, ~desc="replace deep leaf with 99", ~targetId=deepLeaf.id, ~build=_ =>
  mkInt(99)
)->getOrDie("edit target not found")
let touched3 = switch h3.step {
| Some(st) => st.touchedIds
| None => []
}
checkInt("the step's touched set is the 7-record path", Array.length(touched3), 7)
let r3 = checkHead(s)
checkInt("transfers = rebuilt path + the new leaf", s.store.stats.computes, 7)
checkInt(
  "hits = the shared frontier (4 siblings + the other cone + the binding)",
  s.store.stats.hits,
  6,
)
check(
  "incremental equals from-scratch",
  resultEqual(r3, checkFresh(list{}, versionOf(s.head))),
)

// ---------------------------------------------------------------------------
section("env-slice cutoff: a rebuilt binder whose reads are unchanged")
// ---------------------------------------------------------------------------

// Replace the bound side of the Let: the Let record is rebuilt, but every
// node of the body keys on (its own record, x's type) — both unchanged, so
// the whole body is a hit despite its binder having a new record.
let bound2 = mkInt(2)
resetStats(s.store)
let h4a = applyEdit(s, ~desc="bound 1 -> 2", ~targetId=boundLit.id, ~build=_ =>
  bound2
)->getOrDie("bound literal not found")
let r4a = checkHead(s)
checkInt("same-type bound edit: 2 transfers (Let + new literal), body all hit",
  s.store.stats.computes, 2)
check("equals from-scratch", resultEqual(r4a, checkFresh(list{}, versionOf(s.head))))

// Now change the bound side's TYPE: exactly the nodes that read x recompute.
let bodyNow = switch versionOf(s.head).node {
| Let({body}) => body
| _ => failwith("root should be a Let")
}
let readersOfX = countReading(s.store, bodyNow, "x")
resetStats(s.store)
let h4b = applyEdit(s, ~desc="bound 2 -> true", ~targetId=bound2.id, ~build=_ =>
  mkBool(true)
)->getOrDie("bound literal not found")
let r4b = checkHead(s)
checkInt(
  "type-changing bound edit: transfers = 2 + the nodes that read x",
  s.store.stats.computes,
  2 + readersOfX,
)
checkInt("each of the 8 uses of x is witnessed at its Add", Array.length(r4b.witnesses), 8)
check("equals from-scratch", resultEqual(r4b, checkFresh(list{}, versionOf(s.head))))

// ---------------------------------------------------------------------------
section("undo and redo are cache hits")
// ---------------------------------------------------------------------------

let expectFreeCheck = (label: string): checkResult => {
  resetStats(s.store)
  let r = checkHead(s)
  checkInt(label ++ ": zero transfers", s.store.stats.computes, 0)
  check(label ++ ": equals from-scratch", resultEqual(r, checkFresh(list{}, versionOf(s.head))))
  r
}

let _ = undo(s) // back to bound = 2
let _ = expectFreeCheck("undo to bound=2")
let _ = undo(s) // back to bound = 1, leaf 99
let _ = expectFreeCheck("undo to leaf=99")
let _ = undo(s) // back to the original program
let _ = expectFreeCheck("undo to the original")
ignore(h4a)
s.head = h4b // redo: jump forward again — entries were never invalidated
let _ = expectFreeCheck("redo (jump to a later head)")
let _ = undo(s)
let _ = undo(s)
let _ = undo(s) // back to the original for the preview scenario

// ---------------------------------------------------------------------------
section("previews: hypothetical versions over the shared store")
// ---------------------------------------------------------------------------

let rcLeaf = leftmostLeaf(rightCone)
let cand1 = mkInt(5)
let cand2 = mkBool(false)
let cand3 = mkAdd(mkInt(1), mkInt(2))

resetStats(s.store)
let p1 = previewEdit(s, ~desc="leaf -> 5", ~targetId=rcLeaf.id, ~build=_ => cand1)->getOrDie(
  "preview target not found",
)
checkInt("candidate 1 costs its path (6 rebuilt + 1 new)", s.store.stats.computes, 7)
check("candidate 1 checks clean", switch p1.previewResult {
| {ty: Some(TInt), witnesses: []} => true
| _ => false
})

resetStats(s.store)
let p2 = previewEdit(s, ~desc="leaf -> false", ~targetId=rcLeaf.id, ~build=_ => cand2)->getOrDie(
  "preview target not found",
)
checkInt("candidate 2 costs its path too", s.store.stats.computes, 7)
check(
  "candidate 2 is witnessed (Bool into an Add)",
  p2.previewResult.ty == None && Array.length(p2.previewResult.witnesses) == 1,
)

resetStats(s.store)
let p3 = previewEdit(s, ~desc="leaf -> 1+2", ~targetId=rcLeaf.id, ~build=_ => cand3)->getOrDie(
  "preview target not found",
)
checkInt("candidate 3 costs its path + its 3 new records", s.store.stats.computes, 9)
check("candidate 3 checks clean", switch p3.previewResult.ty {
| Some(TInt) => true
| _ => false
})

// Discarding p2 and p3 needs no rollback — nothing was invalidated. And
// committing the previewed candidate reuses its version: all hits.
resetStats(s.store)
let _ = commitPreview(s, p1)
let rCommitted = checkHead(s)
checkInt("committing the previewed edit: zero transfers", s.store.stats.computes, 0)
check(
  "committed head equals from-scratch",
  resultEqual(rCommitted, checkFresh(list{}, versionOf(s.head))),
)

// ---------------------------------------------------------------------------
section("the store is droppable: nothing observable but time")
// ---------------------------------------------------------------------------

dropStore(s)
resetStats(s.store)
let r7 = checkHead(s)
checkInt("cold recheck costs the program again", s.store.stats.computes, size(versionOf(s.head)))
check("and answers identically", resultEqual(r7, checkFresh(list{}, versionOf(s.head))))

// ---------------------------------------------------------------------------
section("branches share the store")
// ---------------------------------------------------------------------------

let base = s.head
let branchTarget = leftmostLeaf(findById(versionOf(s.head), leftCone.id)->getOrDie("left cone"))
let hB = applyEdit(s, ~desc="branch B: leaf -> 41", ~targetId=branchTarget.id, ~build=_ =>
  mkInt(41)
)->getOrDie("branch target")
let _ = checkHead(s) // warm branch B
let _ = undo(s)
check("undo from B lands on the common base", s.head === base)
let hC = applyEdit(s, ~desc="branch C: leaf -> 42", ~targetId=branchTarget.id, ~build=_ =>
  mkInt(42)
)->getOrDie("branch target")
let _ = checkHead(s) // warm branch C
resetStats(s.store)
s.head = hB
let rB = checkHead(s)
s.head = hC
let rC = checkHead(s)
checkInt("switching between warmed branches: zero transfers", s.store.stats.computes, 0)
check(
  "both branches answer as from-scratch",
  resultEqual(rB, checkFresh(list{}, versionOf(hB))) &&
  resultEqual(rC, checkFresh(list{}, versionOf(hC))),
)

// ---------------------------------------------------------------------------
section("caches evict, steps don't: refolding a dropped version")
// ---------------------------------------------------------------------------

let rBefore = checkHead(s)
let vBefore = versionOf(s.head)
s.head.versionCache = None
let vAfter = versionOf(s.head)
check("the refolded version is structurally identical, ids and all", termEqual(vBefore, vAfter))
resetStats(s.store)
let rAfter = checkHead(s)
let stC = switch s.head.step {
| Some(st) => st
| None => failwith("branch head has a step")
}
checkInt(
  "rechecking the refold costs only the rebuilt path (the replacement record is shared)",
  s.store.stats.computes,
  Array.length(stC.touchedIds) - 1,
)
check("and answers identically", resultEqual(rBefore, rAfter))

// ---------------------------------------------------------------------------
section("the cursor query demands only its cone")
// ---------------------------------------------------------------------------

dropStore(s)
resetStats(s.store)
let rcNow = findById(versionOf(s.head), rightCone.id)->getOrDie("right cone")
let rCursor = typeAt(s, rightCone.id)->getOrDie("cursor target")
checkInt(
  "typeAt on a cold store costs the cursor's cone + the one Let binding on the path",
  s.store.stats.computes,
  size(rcNow) + 1,
)
check("cursor type is Int", switch rCursor.ty {
| Some(TInt) => true
| _ => false
})
Console.log(
  "  (the program has " ++
  Int.toString(size(versionOf(s.head))) ++
  " records; the view demanded " ++
  Int.toString(s.store.stats.computes) ++ " transfers)",
)

// ---------------------------------------------------------------------------
section("oracle harness: seeded random edit sequences")
// ---------------------------------------------------------------------------

type rng = {mutable rngState: int}

let below = (r: rng, n: int): int => {
  r.rngState = r.rngState * 1103515245 + 12345
  let v = mod(r.rngState / 65536, n)
  v < 0 ? v + n : v
}

let varPool = ["x", "y", "z", "f"]
let pickVar = (r: rng): string => varPool->Array.getUnsafe(below(r, Array.length(varPool)))

let rec genTy = (r: rng, depth: int): ty =>
  switch below(r, depth > 0 ? 5 : 4) {
  | 0 | 1 => TInt
  | 2 | 3 => TBool
  | _ => TFun(genTy(r, depth - 1), genTy(r, depth - 1))
  }

let rec genTerm = (r: rng, depth: int): term =>
  if depth <= 0 {
    switch below(r, 4) {
    | 0 | 1 => mkInt(below(r, 100))
    | 2 => mkBool(below(r, 2) == 0)
    | _ => mkVar(pickVar(r))
    }
  } else {
    switch below(r, 7) {
    | 0 | 1 => mkAdd(genTerm(r, depth - 1), genTerm(r, depth - 1))
    | 2 => mkIf(genTerm(r, depth - 1), genTerm(r, depth - 1), genTerm(r, depth - 1))
    | 3 => mkLet(pickVar(r), genTerm(r, depth - 1), genTerm(r, depth - 1))
    | 4 => mkLam(pickVar(r), genTy(r, 1), genTerm(r, depth - 1))
    | 5 => mkApp(genTerm(r, depth - 1), genTerm(r, depth - 1))
    | _ => genTerm(r, 0)
    }
  }

// The design doc's protocol: every step runs twice — through the store and
// recomputed fresh — and must agree exactly, across edits, undos, store
// drops, and version-cache evictions.
let runSeed = (seed: int, nEdits: int): unit => {
  let r = {rngState: seed}
  let sess = makeSession(genTerm(r, 4))
  let divergences = ref(0)
  let storedTransfers = ref(0)
  let scratchTransfers = ref(0)
  let _ = checkHead(sess)
  for _step in 1 to nEdits {
    let op = below(r, 10)
    if op < 6 {
      // a random edit at a random node
      let v = versionOf(sess.head)
      let ids = collectIds(v)
      let target = ids->Array.getUnsafe(below(r, Array.length(ids)))
      let build = switch below(r, 4) {
      | 0 => {
          let repl = genTerm(r, 2)
          (_: term) => repl
        }
      | 1 => {
          let k = below(r, 50)
          (old: term) => mkAdd(old, mkInt(k))
        }
      | 2 => {
          let alt = genTerm(r, 1)
          (old: term) => mkIf(mkBool(true), old, alt)
        }
      | _ => {
          let k = below(r, 100)
          (_: term) => mkInt(k)
        }
      }
      applyEdit(sess, ~desc="random edit", ~targetId=target, ~build)->ignore
    } else if op < 8 {
      undo(sess)->ignore
    } else if op == 8 {
      dropStore(sess)
    } else {
      // evict the head's cached fold; it refolds from the step on demand
      switch sess.head.step {
      | Some(_) => sess.head.versionCache = None
      | None => ()
      }
    }
    resetStats(sess.store)
    let stored = checkHead(sess)
    storedTransfers := storedTransfers.contents + sess.store.stats.computes
    let v = versionOf(sess.head)
    scratchTransfers := scratchTransfers.contents + size(v)
    if !resultEqual(stored, checkFresh(list{}, v)) {
      divergences := divergences.contents + 1
    }
  }
  check(
    "seed " ++ Int.toString(seed) ++ ": incremental == from-scratch at every step",
    divergences.contents == 0,
  )
  Console.log(
    "  transfer runs through the store: " ++
    Int.toString(storedTransfers.contents) ++
    "  vs from-scratch: " ++
    Int.toString(scratchTransfers.contents),
  )
}

runSeed(1, 60)
runSeed(42, 60)
runSeed(2026, 60)

// ============================================================================

Console.log(
  "\n" ++
  Int.toString(passCount.contents) ++
  " passed, " ++
  Int.toString(failCount.contents) ++ " failed",
)
if failCount.contents > 0 {
  %raw(`process.exit(1)`)->ignore
}
