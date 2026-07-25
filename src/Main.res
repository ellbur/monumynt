// Smoke tests / playground for the compiler.
//
//   npm start             (build first: npm run build)
//
// Deliberately narrative rather than exhaustive: each test prints the
// textual form and the generated JS so the pieces can be *seen* working
// together. `expectOutput` is an independent oracle: it evals the compiled
// output and compares against an author-written expected value.

open JsBuild

@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"

let evalExpression = (code: string): 'a => evalJs("(" ++ code ++ ")")

let passCount = ref(0)
let failCount = ref(0)

let pass = (msg: string) => {
  passCount := passCount.contents + 1
  Console.log("PASS: " ++ msg)
}

let fail = (msg: string) => {
  failCount := failCount.contents + 1
  Console.log("FAIL: " ++ msg)
}

let header = (name: string) => Console.log("\n=== " ++ name ++ " ===")

// Count non-overlapping occurrences of `needle` in `haystack` (golden checks
// that a fragment — the user's work, an accumulator — is emitted once).
let countOccurrences = (haystack: string, needle: string): int =>
  Array.length(String.split(haystack, needle)) - 1

// Compile one named output and compare its eval'd value against expected JS.
let expectOutput = (p: Program.program, name: string, expected: JsAst.expr): unit =>
  switch Pipeline.compile(p) {
  | exception Codegen.Todo(gap) => fail("expected output '" ++ name ++ "' but codegen has no emitter: " ++ gap)
  | Error(ws) =>
    fail(
      "expected output '" ++
      name ++
      "' but check failed:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === name) {
    | None => fail("no output named " ++ name)
    | Some(o) => {
        Console.log("JS (" ++ name ++ "):")
        Console.log(o.js)
        let actual = jsonStringify(evalExpression(o.js))
        let want = jsonStringify(evalExpression(JsPrint.printExpr(expected)))
        if actual === want {
          pass(name ++ " = " ++ actual)
        } else {
          fail(name ++ ": expected " ++ want ++ ", got " ++ actual)
        }
      }
    }
  }

// Round-trip: print -> parse -> same wiring; and the print is stable.
let expectRoundTrip = (p: Program.program): unit => {
  let text = TextPrint.print(p)
  Console.log("TEXT:")
  Console.log(text)
  let reparsed = TextResolve.parseProgram(text)
  if Program.equal(p, reparsed) {
    pass("round-trip: parse(print(p)) has identical wiring")
  } else {
    fail("round-trip: wiring changed\n-- original --\n" ++ Program.dump(p) ++ "\n-- reparsed --\n" ++ Program.dump(reparsed))
  }
  let text2 = TextPrint.print(reparsed)
  if text === text2 {
    pass("round-trip: print is stable")
  } else {
    fail("round-trip: print not stable\n-- first --\n" ++ text ++ "\n-- second --\n" ++ text2)
  }
}

// ============================================================================
// 1. Value fragment, sharing by name
// ============================================================================

header("value fragment: sharing is opt-in via naming")
{
  let src = `
add = js "(a, b) => a + b"
ten = 10
ten, ten -> add => twenty
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "twenty", int_(20))
  expectRoundTrip(p)
}

// ============================================================================
// 1b. Infix operators in source position: `a * a` is App of the `*` extern to
//     two operands, so squaring is fan-out from one named port; precedence is
//     standard (`*` binds tighter than `+`), left-associative.
// ============================================================================

header("infix: source-position operators desugar to App (fan-in, precedence)")
{
  let src = `
a = 3
b = 4
a * a => sq
a + b * a => mixed
b - a => diff
b % a => rem
out sq
out mixed
out diff
out rem
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "sq", int_(9)) // 3 * 3
  expectOutput(p, "mixed", int_(15)) // 3 + (4 * 3), not (3 + 4) * 3
  expectOutput(p, "diff", int_(1)) // 4 - 3; '-' does not collide with the arrows
  expectOutput(p, "rem", int_(1)) // 4 % 3
  expectRoundTrip(p)
}

// ============================================================================
// 1c. Prefix application: `f(x, y)` is the same App the postfix `x, y -> f`
//     builds — the permissive grammar's other authoring path
//     (textual-representation-design.md, "parse accepts prefix (`f(x, y)`)").
//     Nesting and mixing with infix both work; the round-trip prints the
//     postfix form (App-node wiring is identical either way).
// ============================================================================

header("prefix application: f(x, y) desugars to App, one reading with postfix")
{
  let src = `
add = js "(a, b) => a + b"
mul = js "(a, b) => a * b"
add(3, 4) => seven
mul(add(1, 2), 5) => fifteen
add(mul(2, 3), 4) * 2 => twenty
out seven
out fifteen
out twenty
`
  let fromText = TextResolve.parseProgram(src)
  expectOutput(fromText, "seven", int_(7))
  expectOutput(fromText, "fifteen", int_(15)) // (1 + 2) * 5
  expectOutput(fromText, "twenty", int_(20)) // (2 * 3 + 4) * 2
  expectRoundTrip(fromText)

  // Prefix `add(x, y)` and postfix `x, y -> add` build identical wiring — the
  // permissive grammar's two authoring paths converge on one App (P4).
  let prefix = TextResolve.parseProgram(`
add = js "(a, b) => a + b"
add(3, 4) => s
out s
`)
  let postfix = TextResolve.parseProgram(`
add = js "(a, b) => a + b"
3, 4 -> add => s
out s
`)
  if Program.equal(prefix, postfix) {
    pass("prefix f(x, y) and postfix x, y -> f build identical wiring")
  } else {
    fail(
      "prefix vs postfix wiring differs\n-- prefix --\n" ++
      Program.dump(prefix) ++
      "\n-- postfix --\n" ++
      Program.dump(postfix),
    )
  }
}

// ============================================================================
// 2. Multiply each element by 2 — text (inline `* 2`) and handles agree
// ============================================================================

header("list flow: text and handles agree")
{
  let src = `
[1, 2, 3] -> open list -> * 2 -~> collect => out
`
  let fromText = TextResolve.parseProgram(src)

  // The handle-built twin: `* 2` desugars to App of the binary `*` extern to
  // the element and the literal 2.
  let b = Build.make()
  let mul = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let doubled = Build.app(b, mul.value, [it.element, two.value])
  let out = Build.collect(b, ~flow=it.flow, doubled.value)
  let fromHandles = Build.finish(b, ~outputs=[("out", out.value)])

  if Program.equal(fromText, fromHandles) {
    pass("text-built and handle-built programs have identical wiring")
  } else {
    fail(
      "text vs handles wiring differs\n-- text --\n" ++
      Program.dump(fromText) ++
      "\n-- handles --\n" ++
      Program.dump(fromHandles),
    )
  }
  expectOutput(fromText, "out", array_([int_(2), int_(4), int_(6)]))
  expectRoundTrip(fromText)
}

// ============================================================================
// 3. Flatten: nested opens, bare join in chain position
// ============================================================================

header("flatten: implicit flow stack, binary join")
{
  let src = `
[[1, 2], [3]] -> open list -> open list -> * 2 -~> join -~> collect => flat
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "flat", array_([int_(2), int_(4), int_(6)]))
  expectRoundTrip(p)
}

// ============================================================================
// 4. Multi-close via junction taps
// ============================================================================

header("multi-close: taps desugar to shared references")
{
  let src = `
[1, 2, 3] -> open list -> | * 2 -~> collect => doubled
| -> * 3 -~> collect => tripled
out doubled
out tripled
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "doubled", array_([int_(2), int_(4), int_(6)]))
  expectOutput(p, "tripled", array_([int_(3), int_(6), int_(9)]))
  expectRoundTrip(p)
}

// ============================================================================
// 5. Option flow
// ============================================================================

header("option flow")
{
  let src = `
five = js "5"
five -> open option -> * 2 -~> collect => out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", int_(10))
  expectRoundTrip(p)
}

// ============================================================================
// 5c. Printer chain compression (ARCHITECTURE.md worklist item 4)
// ============================================================================
// Single-consumer runs fuse into one postfix chain; the flow a chain opens and
// closes itself is implicit (no `~name`); single-use data literals inline. The
// round-trip check is the correctness spec — these add a golden assertion that
// the fused shape is actually produced, not just that it reparses.

// Assert some printed line contains every needle (the fused chain landed on one
// line rather than being split across named statements).
let expectFusedLine = (p: Program.program, needles: array<string>, label: string): unit => {
  let text = TextPrint.print(p)
  let hit =
    text
    ->String.split("\n")
    ->Array.some(line => needles->Array.every(nd => line->String.includes(nd)))
  if hit {
    pass("print fuses: " ++ label)
  } else {
    fail("print did not fuse (" ++ label ++ "):\n" ++ text)
  }
}

header("printer: a multi-stage value chain fuses onto one line")
{
  let src = `
inc = js "x => x + 1"
[10, 20, 30] -> open list -> inc -> * 2 -~> collect => out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(22), int_(42), int_(62)]))
  expectRoundTrip(p)
  // whole chain — source list through the named app and the `* 2` operator
  // section to the bare collect — on one line (names are the printer's own, so
  // assert the stable structural markers).
  expectFusedLine(p, ["[10, 20, 30]", "open list", "-~> collect", "=> out"], "source..collect")
}

header("printer: an application stage carries an inlined extra argument")
{
  let src = `
add = js "(a, b) => a + b"
[1, 2, 3] -> open list -> add(100) -~> collect => out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(101), int_(102), int_(103)]))
  expectRoundTrip(p)
  // the extra argument literal inlines into the call: `-> nN(100)`.
  expectFusedLine(p, ["open list", "(100)", "-~> collect", "=> out"], "inlined extra arg")
}

// ============================================================================
// 5b. A computed function — App's fn is a wire
// ============================================================================
// App's fn is a wire like any argument; here it is another App's output (a
// computed function), not just a named extern.

header("computed function: fn is a wire")
{
  let b = Build.make()
  let makeAdder = Build.raw(b, "a => b => a + b")
  let three = Build.lit(b, int_(3))
  let ten = Build.lit(b, int_(10))
  let add3 = Build.app(b, makeAdder.value, [three.value])
  let out = Build.app(b, add3.value, [ten.value])
  let p = Build.finish(b, ~outputs=[("thirteen", out.value)])
  expectOutput(p, "thirteen", int_(13))
}

// ============================================================================
// 6. Case split with per-alt ports (no Branch node anywhere)
// ============================================================================

header("case split: alt ports, exhaustive collect")
{
  let b = Build.make()
  let disc = Build.raw(
    b,
    "x => x === undefined ? {tag: 'Nothing'} : {tag: 'Just', value: x}",
  )
  let mul = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let maybes = Build.lit(b, array_([int_(1), undefined, int_(5)]))
  let it = Build.uncollectList(b, maybes.value)
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, it.element)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  let doubled = Build.app(b, mul.value, [just.altValue, two.value])
  let zero = Build.lit(b, int_(0))
  let perElem = Build.collectCases(
    b,
    [(just.altFlow, doubled.value), (nothing.altFlow, zero.value)],
  )
  let out = Build.collect(b, ~flow=it.flow, perElem.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])

  expectOutput(p, "out", array_([int_(2), int_(0), int_(10)]))
}

// ============================================================================
// 6b. Case collect from text — lane groups now parse and round-trip
// ============================================================================

header("case collect: lane group parses, compiles, round-trips")
{
  let src = `
classify = js "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}"
[1, 2, 3, 4] -> open list => a, ~L
a -> split classify of Even, Odd => cs
cs.Odd -> * 2 => doubled
~cs.Even: cs.Even
~cs.Odd: doubled
-~> collect => perElem
perElem -~> collect ~L => out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(2), int_(2), int_(6), int_(4)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7. Filter as join(list, case-alt flow) — from text
// ============================================================================

header("filter is join with a case-alt inner operand")
{
  let src = `
parity = js "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}"
[1, 2, 3, 4] -> open list => a, ~L
a -> split parity of Even, Odd => cs
~cs.Even ~> join into ~L => ~keep
a -~> collect ~keep => evens
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "evens", array_([int_(2), int_(4)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7d. Nested flatten + filter — join(join(list, list), case-alt). Flatten a
//     list-of-lists and keep the evens. The join whose OUTER is itself a join
//     stacks two list layers before the filter: Codegen's per-level spine walk
//     compiles it (emitCellChain loops its leading list levels), but the
//     join-adjacency check formerly rejected it — it compared the alt's exterior
//     (two layers) against a single-layer `[outer]` interior of the inner join.
//     Fixed by Context.flowInterior computing a Join's flattened interior.
// ============================================================================

header("nested flatten + filter: join(join(list, list), case-alt) is adjacent")
{
  let b = Build.make()
  let parity = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let xs = Build.lit(b, array_([array_([int_(1), int_(2)]), array_([int_(3), int_(4)])]))
  let i1 = Build.uncollectList(b, xs.value)
  let i2 = Build.uncollectList(b, i1.element)
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, i2.element)
  let ev = Build.alt(cs, "Even")
  // Flatten the two list layers (j1), then join the per-element Even cell (j2).
  let j1 = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=ev.altFlow)
  let out = Build.collect(b, ~flow=j2.flow, ev.altValue)
  let p = Build.finish(b, ~outputs=[("evens", out.value)])
  // The flattened evens across both inner lists: [2, 4].
  expectOutput(p, "evens", array_([int_(2), int_(4)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7e. Filter over an option leading level — join(join(list, option), case-alt).
//     Per list element, open an option (present iff n >= 2); per present value,
//     dispatch by parity and keep the evens. The option level is a defined-check
//     nested inside the list's for-of: an absent option skips (contributes
//     nothing), a present-but-Odd value is dropped by the filter, a present Even
//     is pushed. Validated against a hand-computed value, like the partial
//     collects.
// ============================================================================

header("filter over an option level: join(join(list, option), case-alt)")
{
  let b = Build.make()
  let optSrc = Build.raw(b, "n => n >= 2 ? n : undefined")
  let parity = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let i1 = Build.uncollectList(b, xs.value)
  let optIn = Build.app(b, optSrc.value, [i1.element])
  let i2 = Build.uncollectOption(b, optIn.value)
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, i2.element)
  let ev = Build.alt(cs, "Even")
  // Flatten the option into the list (j1), then join the per-value Even cell (j2).
  let j1 = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=ev.altFlow)
  let out = Build.collect(b, ~flow=j2.flow, ev.altValue)
  let p = Build.finish(b, ~outputs=[("evens", out.value)])
  // 1 -> option absent (skip); 2 -> Some(2) Even (keep); 3 -> Some(3) Odd (drop);
  // 4 -> Some(4) Even (keep). Result [2, 4].
  expectOutput(p, "evens", array_([int_(2), int_(4)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7f. Filter over ONLY option levels — join(option, case-alt), no list. The
//     any-list rule (lazy-compile-design.md) makes the output an OPTION, not a
//     list: `let out;` set only when the option fires and the alt matches — the
//     single-alt case of the partial collect's collected-alone reading (7c).
//     Validated against a hand-computed value.
// ============================================================================

header("filter over only options: join(option, case-alt) yields an option")
{
  let b = Build.make()
  let optSrc = Build.raw(b, "n => n >= 2 ? n : undefined")
  let parity = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let v = Build.lit(b, int_(4))
  let optIn = Build.app(b, optSrc.value, [v.value])
  let i = Build.uncollectOption(b, optIn.value)
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, i.element)
  let ev = Build.alt(cs, "Even")
  // join the per-value Even cell onto the option; no list in the chain.
  let j = Build.join(b, ~outer=i.flow, ~inner=ev.altFlow)
  let out = Build.collect(b, ~flow=j.flow, ev.altValue)
  let p = Build.finish(b, ~outputs=[("even", out.value)])
  // 4 -> Some(4) (>= 2), Even -> kept -> the option holds 4.
  expectOutput(p, "even", int_(4))
  expectRoundTrip(p)
}

// ============================================================================
// 7g. Filter-then-flatmap — join(join(list, case-alt), inner-list). The
//     dispatch is NON-trailing: an inner list opens inside the kept alt and is
//     flattened out. For each outer element, dispatch by tag; for a "Just",
//     iterate its payload list and emit each element; a "Nothing" contributes
//     nothing. The emitted thunk nests a for-of INSIDE the alt guard's if —
//     a dispatch that is not the innermost level. Validated against a
//     hand-computed value.
// ============================================================================

header("filter-then-flatmap: join(join(list, case-alt), inner-list) flattens the kept alt")
{
  let b = Build.make()
  // The discriminator drops n === 2 (Nothing) and tags the rest as Just whose
  // payload is a two-element list to flatten out.
  let disc = Build.raw(b, "n => n === 2 ? {tag: 'Nothing'} : {tag: 'Just', value: [n, n * 10]}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let outer = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, outer.element)
  let just = Build.alt(cs, "Just")
  // The inner list opens over the kept alt's payload (nested under the alt flow).
  let inner = Build.uncollectList(b, ~nesting=just.altFlow, just.altValue)
  // join the alt cell onto the outer list (j1), then flatten the inner list (j2).
  let j1 = Build.join(b, ~outer=outer.flow, ~inner=just.altFlow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=inner.flow)
  let out = Build.collect(b, ~flow=j2.flow, inner.element)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // 1 -> Just([1,10]); 2 -> Nothing (skip); 3 -> Just([3,30]). Flattened: [1,10,3,30].
  expectOutput(p, "out", array_([int_(1), int_(10), int_(3), int_(30)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7b. Partial collect — the merged flow of two covered cells, terminated by a
//     join (a multi-cell filter: "keep the A's and B's, drop the C's").
//     Validated against a hand-computed value, like registers.
// ============================================================================

header("partial collect: merged flow of two cells drives a multi-cell filter")
{
  let src = `
classify = js "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})"
[1, 2, 3, 4, 5, 6] -> open list => a, ~L
a -> split classify of A, B, C => cs
~cs.A: cs.A
~cs.B: cs.B
-~> collect => picked, ~pf
~pf ~> join into ~L => ~keep
picked -~> collect ~keep => out
`
  let p = TextResolve.parseProgram(src)
  // keep n where n%3 in {0,1}: 1(B) 3(A) 4(B) 6(A); drop 2,5 (C).
  expectOutput(p, "out", array_([int_(1), int_(3), int_(4), int_(6)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7c. Partial collect collected alone — the merged flow of two cells
//     terminated at the parent as an option (0-or-1). Exercises the
//     no-leading-level (option accumulator) path of emitCellChain.
// ============================================================================

header("partial collect: merged flow collected alone yields an option")
{
  let src = `
classify = js "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})"
4 -> split classify of A, B, C => cs
~cs.A: cs.A
~cs.B: cs.B
-~> collect => picked, ~pf
picked -~> collect ~pf => out
`
  let p = TextResolve.parseProgram(src)
  // 4 % 3 == 1 -> B (a covered cell) -> the merged flow fires with value 4.
  expectOutput(p, "out", int_(4))
  expectRoundTrip(p)
}

// ============================================================================
// 7i. COMPUTATION AT THE MERGED CONTEXT — the doc's `logAndFallback` step
//     (partial-collect-design.md, "The construct" and "The merged flow as
//     parent scope"). A value computed FROM a partial collect's merged value
//     lives at the cell-set context {A, B}, which no chain segment names: the
//     chain opens one alt per dispatch arm. What admits it is the containment
//     theorem — `{A} ⊆ {A, B}`, so a merged-context value is available inside
//     each constituent cell (Context.cellSet / cellContains, consulted by
//     Codegen.matchChain). The emission is the doc's sanctioned choice: once
//     per arm, code duplicated, evaluation still once, since exactly one arm
//     runs. Collected-alone (option) shape, mirroring 7c.
// ============================================================================

header("partial collect: a computation AT the merged context (collected alone)")
{
  let b = Build.make()
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let dbl = Build.raw(b, "x => x * 2")
  let four = Build.lit(b, int_(4))
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, four.value)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  let pf = Program.FlowPort(picked.node, "flow")
  // `fb` is the merged-context computation: its structural context is the
  // merged flow {A, B}, not either alt.
  let fb = Build.app(b, dbl.value, [picked.value])
  let out = Build.collect(b, ~flow=pf, fb.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // 4 % 3 == 1 -> B (covered) -> merged value 4 -> doubled = 8.
  expectOutput(p, "out", int_(8))
  expectRoundTrip(p)
}

// ============================================================================
// 7j. The merged-context computation over a MULTI-CELL FILTER — the doc's HTTP
//     program in miniature: per list firing, dispatch a split, merge two of the
//     three cells, and run ONE computation over the merged value ("handle these
//     two cases the same way," said once). Extends 7b, whose terminating value
//     referenced the merged value directly. Hand-computed, with a golden that
//     pins the doc's emission choice: the merged computation appears once per
//     covered arm (two arms ⇒ two occurrences), and each firing runs one arm.
// ============================================================================

header("partial collect: merged-context computation over a multi-cell filter")
{
  let src = `
classify = js "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})"
label = js "n => (globalThis.__mcRuns = (globalThis.__mcRuns || 0) + 1, 'n=' + n)"
[1, 2, 3, 4, 5, 6] -> open list => a, ~L
a -> split classify of A, B, C => cs
~cs.A: cs.A
~cs.B: cs.B
-~> collect => picked, ~pf
picked -> label => tagged
~pf ~> join into ~L => ~keep
tagged -~> collect ~keep => out
`
  let p = TextResolve.parseProgram(src)
  let _: int = evalJs("globalThis.__mcRuns = 0")
  // Kept firings (n%3 in {0,1}): 1(B) 3(A) 4(B) 6(A); 2 and 5 are C, dropped.
  // `label` runs once per kept firing, at the merged context, whichever cell
  // fired — "handle these two cases the same way," said once.
  expectOutput(
    p,
    "out",
    array_([str("n=1"), str("n=3"), str("n=4"), str("n=6")]),
  )

  // The doc's emission choice, pinned from both sides. Syntactically the
  // merged computation is DUPLICATED — one dispatch arm per covered cell.
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out") {
    | Some(o) =>
      let n = countOccurrences(o.js, ".push(")
      if n === 2 {
        pass("the merged-context computation is emitted once per covered arm")
      } else {
        fail("expected two dispatch arms, found " ++ Int.toString(n))
      }
    | None => fail("no out to inspect")
    }
  | Error(ws) =>
    fail(
      "merged-context program failed check:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
  // Semantically it EVALUATES ONCE per firing: exactly one arm runs, so the
  // counter reads one run per kept firing (4), not one per arm per firing (8).
  let runs: int = evalJs("globalThis.__mcRuns")
  if runs === 4 {
    pass("the merged computation evaluates once per kept firing (4), not once per arm")
  } else {
    fail("expected 4 merged-context evaluations, got " ++ Int.toString(runs))
  }

  expectRoundTrip(p)
}

// ============================================================================
// 7k. The containment theorem is ONE-DIRECTIONAL (partial-collect-design.md,
//     "The merged flow as parent scope": "It never moves a value *out* of a
//     constituent"). A `{A}`-borne value — one cell's own payload — read at the
//     merged `{A, B}` context is ill-formed: it does not exist on the firings
//     where B fired. Getting a value TO the merged context from inside cells is
//     what the partial collect's value threading is for, so the only door is
//     that explicit node. Now a `flow-borne` witness rather than a codegen
//     crash: `branchInterior` computes a merged flow's interior exactly, so the
//     rule reaches this branch instead of leaving it to the backstop.
// ============================================================================

header("partial collect: a cell-borne value cannot escape to the merged context")
{
  let b = Build.make()
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let four = Build.lit(b, int_(4))
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, four.value)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  let pf = Program.FlowPort(picked.node, "flow")
  // The terminating collect iterates the merged flow {A, B} but reads alt A's
  // OWN payload — the coarsening direction the theorem denies.
  let out = Build.collect(b, ~flow=pf, ca.altValue)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "flow-borne") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("flow-borne witness: a cell-borne value does not coarsen to the merged context")
    } else {
      fail(
        "expected a flow-borne witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("a cell-borne value escaped to the merged context without a witness")
  }
}

// ============================================================================
// 7l. THE COVERING CELL-SET COLLECT — the design's HTTP program, worked in full
//     (partial-collect-design.md, "The construct"). A response splits four ways;
//     the two error cases share their handling, so a partial collect merges them
//     into `~err` and ONE `logAndFallback` runs at the merged context. The final
//     collect's branches are keyed by disjoint covering cell SETS — two
//     singletons and a pair — which is the provenance sketch's generalized
//     coverage demand landing as the node's actual signature: "the exhaustive
//     case collect is not a sibling construct to the partial collect; it is the
//     covering configuration of the same node".
//
//     Dispatch stays one arm per cell, and each of the pair's arms binds the
//     merged value to its own branch's — the containment theorem, operationally.
// ============================================================================

header("covering cell-set collect: the HTTP program (two singletons and a pair)")
{
  let b = Build.make()
  // The four-way split on an HTTP status code; the payload is the code itself.
  let disc = Build.raw(
    b,
    "c => ({tag: c < 300 ? 'Ok' : (c < 400 ? 'Redirect' : (c < 500 ? 'ClientError' : 'ServerError')), value: c})",
  )
  let parse = Build.raw(b, "s => 'parsed:' + s")
  let follow = Build.raw(b, "u => 'followed:' + u")
  let logAndFallback = Build.raw(
    b,
    "s => (globalThis.__fbRuns = (globalThis.__fbRuns || 0) + 1, 'fallback:' + s)",
  )
  let responses = Build.lit(b, array_([int_(200), int_(404), int_(301), int_(500)]))
  let it = Build.uncollectList(b, responses.value)
  let h = Build.caseSplit(
    b,
    ~alts=["Ok", "Redirect", "ClientError", "ServerError"],
    ~discriminator=disc.value,
    it.element,
  )
  let ok = Build.alt(h, "Ok")
  let redirect = Build.alt(h, "Redirect")
  let clientErr = Build.alt(h, "ClientError")
  let serverErr = Build.alt(h, "ServerError")
  // The partial collect: merge the two error cells. `errStatus` is the status
  // whichever error fired; `~err` is the merged flow spanning both.
  let errStatus = Build.collectCases(
    b,
    [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
  )
  let err = Program.FlowPort(errStatus.node, "flow")
  // "handle these two cases the same way," said once — at the merged context.
  let fb = Build.app(b, logAndFallback.value, [errStatus.value])
  // The covering collect: {Ok} + {Redirect} + {ClientError, ServerError}.
  let result = Build.collectCases(
    b,
    [
      (ok.altFlow, Build.app(b, parse.value, [ok.altValue]).value),
      (redirect.altFlow, Build.app(b, follow.value, [redirect.altValue]).value),
      (err, fb.value),
    ],
  )
  let out = Build.collect(b, ~flow=it.flow, result.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])

  let _: int = evalJs("globalThis.__fbRuns = 0")
  expectOutput(
    p,
    "out",
    array_([
      str("parsed:200"),
      str("fallback:404"),
      str("followed:301"),
      str("fallback:500"),
    ]),
  )
  // One fallback per error firing, of EITHER kind — two errors in the list, so
  // two runs, even though the arm-per-cell dispatch emits the call twice.
  let runs: int = evalJs("globalThis.__fbRuns")
  if runs === 2 {
    pass("logAndFallback ran once per error firing, of either kind")
  } else {
    fail("expected 2 fallback runs, got " ++ Int.toString(runs))
  }
  expectRoundTrip(p)
}

// ============================================================================
// 7m. The covering demand is over CELL SETS, not alt ports: a collect whose
//     branches are a merged pair {ClientError, ServerError} and a singleton
//     {ClientError} covers ClientError twice, so "the firing branch" would not
//     refer — ill-formed at the node (partial-collect-design.md, "Disjointness
//     is a node demand"). Read off cell sets, this is one witness; read off port
//     names it would be invisible, since a merged flow's port is always "flow".
// ============================================================================

header("covering cell-set collect: overlapping branch cell sets are witnessed")
{
  let b = Build.make()
  let disc = Build.raw(
    b,
    "c => ({tag: c < 300 ? 'Ok' : (c < 500 ? 'ClientError' : 'ServerError'), value: c})",
  )
  let one = Build.lit(b, int_(200))
  let h = Build.caseSplit(
    b,
    ~alts=["Ok", "ClientError", "ServerError"],
    ~discriminator=disc.value,
    one.value,
  )
  let ok = Build.alt(h, "Ok")
  let clientErr = Build.alt(h, "ClientError")
  let serverErr = Build.alt(h, "ServerError")
  let errStatus = Build.collectCases(
    b,
    [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
  )
  let err = Program.FlowPort(errStatus.node, "flow")
  // {Ok} + {ClientError, ServerError} + {ClientError}: ClientError twice.
  let result = Build.collectCases(
    b,
    [(ok.altFlow, ok.altValue), (err, errStatus.value), (clientErr.altFlow, clientErr.altValue)],
  )
  let p = Build.finish(b, ~outputs=[("out", result.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "coverage") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("coverage witness: overlapping branch cell sets")
    } else {
      fail(
        "expected a coverage witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("overlapping cell sets compiled without a witness")
  }
}

// ============================================================================
// 7n. A PARTIAL collect built over another partial collect's merged flow —
//     merge {ClientError, ServerError} into `~err`, then merge THAT with
//     {Redirect} into a still-partial `~nonOk` spanning three of the bundle's
//     four cells. Nothing new was written for it: the cell walk recurses, so the
//     outer node names cells of the one underlying split, and the dispatch is
//     over CELLS rather than branches, each arm binding every merged value on
//     the path down to it. Two levels of merged-context computation ride along —
//     one at {ClientError, ServerError}, one at {ClientError, ServerError,
//     Redirect} — so containment is exercised at both depths.
// ============================================================================

header("partial collect over a partial collect: nested cell merges")
{
  let b = Build.make()
  let disc = Build.raw(
    b,
    "c => ({tag: c < 300 ? 'Ok' : (c < 400 ? 'Redirect' : (c < 500 ? 'ClientError' : 'ServerError')), value: c})",
  )
  let describe = Build.raw(b, "s => 'err:' + s")
  let mark = Build.raw(b, "s => '[' + s + ']'")
  let codes = Build.lit(b, array_([int_(200), int_(301), int_(404), int_(500)]))
  let it = Build.uncollectList(b, codes.value)
  let h = Build.caseSplit(
    b,
    ~alts=["Ok", "Redirect", "ClientError", "ServerError"],
    ~discriminator=disc.value,
    it.element,
  )
  let redirect = Build.alt(h, "Redirect")
  let clientErr = Build.alt(h, "ClientError")
  let serverErr = Build.alt(h, "ServerError")
  // Inner merge: the two error cells.
  let errs = Build.collectCases(
    b,
    [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
  )
  let errFlow = Program.FlowPort(errs.node, "flow")
  // A computation at the INNER merged context {ClientError, ServerError}.
  let described = Build.app(b, describe.value, [errs.value])
  // Outer merge: that merged flow together with {Redirect} — still partial
  // (3 of 4 cells), so this node keeps a merged flow of its own.
  let nonOk = Build.collectCases(
    b,
    [(errFlow, described.value), (redirect.altFlow, redirect.altValue)],
  )
  let nonOkFlow = Program.FlowPort(nonOk.node, "flow")
  // A computation at the OUTER merged context {ClientError, ServerError, Redirect}.
  let marked = Build.app(b, mark.value, [nonOk.value])
  // Keep the non-Ok firings out of the list; Ok drops.
  let keep = Build.join(b, ~outer=it.flow, ~inner=nonOkFlow)
  let out = Build.collect(b, ~flow=keep.flow, marked.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // 200 -> Ok, dropped. 301 -> Redirect: the outer merge carries 301 itself.
  // 404 -> ClientError and 500 -> ServerError: the inner merge carries the
  // status, `describe` runs at the inner merged context, the outer merge
  // carries that, and `mark` runs at the outer one.
  expectOutput(p, "out", array_([str("[301]"), str("[err:404]"), str("[err:500]")]))
  expectRoundTrip(p)
}

// ============================================================================
// 7o. A merged value read from INSIDE one of its cells, by a chain that opens
//     that cell some other way — the containment theorem reached on demand
//     rather than by the merging node's own emitter. The merge spans {A, B}; an
//     ordinary filter keeps only the A firings and reads the merged value there.
//     `{A} ⊆ {A, B}`, so the merged value is available — and inside cell A it IS
//     A's branch value.
// ============================================================================

header("partial collect: the merged value read from inside one cell")
{
  let b = Build.make()
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let dbl = Build.raw(b, "x => x * 2")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4), int_(5), int_(6)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, it.element)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  // A plain filter on alt A — nothing here mentions the merge — whose value
  // reads the merged value of the {A, B} merge.
  let keepA = Build.join(b, ~outer=it.flow, ~inner=ca.altFlow)
  let doubled = Build.app(b, dbl.value, [picked.value])
  let out = Build.collect(b, ~flow=keepA.flow, doubled.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // A firings are the multiples of 3: 3 and 6; inside cell A the merged value
  // is A's own payload, so the result is [6, 12].
  expectOutput(p, "out", array_([int_(6), int_(12)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7p. The same read from a cell the merge does NOT cover. `{C} ⊄ {A, B}`, so the
//     merged value is not available there — it does not exist on the firings
//     where C fired — and the merged flow survives the collect as a context the
//     output cannot be read at. A `flow-borne` witness, not a codegen crash.
// ============================================================================

header("partial collect: a merged value is not readable from an uncovered cell")
{
  let b = Build.make()
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let dbl = Build.raw(b, "x => x * 2")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, it.element)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let cc = Build.alt(cs, "C")
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  // Keep the C firings — a cell the {A, B} merge does not cover — and read the
  // merged value there.
  let keepC = Build.join(b, ~outer=it.flow, ~inner=cc.altFlow)
  let doubled = Build.app(b, dbl.value, [picked.value])
  let out = Build.collect(b, ~flow=keepC.flow, doubled.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "flow-borne") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("flow-borne witness: the merged value is not readable from an uncovered cell")
    } else {
      fail(
        "expected a flow-borne witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("a merged value was read from an uncovered cell without a witness")
  }
}

// ============================================================================
// 7q. OVERLAPPING cell sets combine at their MEET (bundle-provenance-design.md,
//     "Revision: overlap is incorporate, not a clash"). Two merges over one
//     bundle — {A, B} and {B, C} — carry values that combine at
//     {A,B} ∩ {B,C} = {B}, "the greatest cell set contained in both ... and it
//     is *unique*". Only a DISJOINT meet is bundle mixing.
//
//     The meet has to be a set the program constructed, exactly as a sibling
//     combine's home has to be a constructed product; a single cell always is —
//     the split's own alt flow port, engaged by both merges. Nothing in codegen
//     was needed: the combine lands at cell B's arm, and each merged value
//     resolves there by containment (7o's on-demand read).
// ============================================================================

header("partial collect: overlapping cell sets combine at their meet")
{
  let b = Build.make()
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let tenX = Build.raw(b, "n => n * 10")
  let plus = Build.raw(b, "(x, y) => x + y")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, it.element)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let cc = Build.alt(cs, "C")
  // {A, B}: the payload as-is. {B, C}: the payload times ten.
  let ab = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  let bc = Build.collectCases(
    b,
    [
      (cb.altFlow, Build.app(b, tenX.value, [cb.altValue]).value),
      (cc.altFlow, Build.app(b, tenX.value, [cc.altValue]).value),
    ],
  )
  // The combine lives at {B} — the only cell on which both merges fire.
  let both = Build.app(b, plus.value, [ab.value, bc.value])
  let keepB = Build.join(b, ~outer=it.flow, ~inner=cb.altFlow)
  let out = Build.collect(b, ~flow=keepB.flow, both.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // B firings are n % 3 == 1: 1 and 4. At B, {A,B} carries n and {B,C} carries
  // 10n, so the sum is 11n: [11, 44].
  expectOutput(p, "out", array_([int_(11), int_(44)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7r. The two ways a cell-set overlap can fail to resolve, each reported by the
//     rule that owns it rather than misfiled as time travel (which would offer
//     "insert a Cross" as the remedy for a bundle question).
//
//     (a) DISJOINT cell sets — {A, B} against {C, D} — are bundle mixing: no
//         execution produces both. Alt ports of one split were always caught;
//         two merged flows live on their own nodes and used to look like
//         unrelated opens.
//     (b) A meet WIDER than one cell — {A,B,C} ∩ {B,C,D} = {B,C} — is where the
//         values combine, but only a set the program CONSTRUCTED can host them,
//         exactly as a sibling combine needs a constructed product. The remedy
//         is to build the merge, not to insert a Cross.
// ============================================================================

header("partial collect: disjoint cell sets are bundle mixing, wide meets need constructing")
{
  let mk = (~overlap: bool) => {
    let b = Build.make()
    let classify = Build.raw(
      b,
      "n => ({tag: ['A', 'B', 'C', 'D'][n % 4], value: n})",
    )
    let plus = Build.raw(b, "(x, y) => x + y")
    let one = Build.lit(b, int_(1))
    let cs = Build.caseSplit(b, ~alts=["A", "B", "C", "D"], ~discriminator=classify.value, one.value)
    let cell = name => Build.alt(cs, name)
    let left = Build.collectCases(
      b,
      overlap
        ? [
            (cell("A").altFlow, cell("A").altValue),
            (cell("B").altFlow, cell("B").altValue),
            (cell("C").altFlow, cell("C").altValue),
          ]
        : [(cell("A").altFlow, cell("A").altValue), (cell("B").altFlow, cell("B").altValue)],
    )
    let right = Build.collectCases(
      b,
      overlap
        ? [
            (cell("B").altFlow, cell("B").altValue),
            (cell("C").altFlow, cell("C").altValue),
            (cell("D").altFlow, cell("D").altValue),
          ]
        : [(cell("C").altFlow, cell("C").altValue), (cell("D").altFlow, cell("D").altValue)],
    )
    let combined = Build.app(b, plus.value, [left.value, right.value])
    let out = Build.collect(b, ~flow=Program.FlowPort(left.node, "flow"), combined.value)
    Build.finish(b, ~outputs=[("out", out.value)])
  }

  let expectRule = (p, rule, what) =>
    switch Pipeline.compile(p) {
    | Error(ws) =>
      if ws->Array.some(w => w.rule === rule) {
        Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
        pass(what)
      } else {
        fail(
          "expected a " ++
          rule ++
          " witness, got:\n  " ++
          ws->Array.map(Check.witnessToString)->Array.join("\n  "),
        )
      }
    | exception Codegen.Todo(m) => fail("expected a " ++ rule ++ " witness, got a Todo: " ++ m)
    | Ok(_) => fail("expected a " ++ rule ++ " witness, but the program compiled")
    }

  expectRule(mk(~overlap=false), "bundle-mixing", "disjoint merged cell sets are bundle mixing")
  expectRule(
    mk(~overlap=true),
    "unconstructed-meet",
    "a meet wider than one cell is named, with the remedy of constructing it",
  )
}

// ============================================================================
// 7s. A merged flow as a NON-TRAILING level — `join(join(list, partial), inner)`:
//     keep the error firings, then flatten a list derived from each. This is the
//     multi-cell twin of the filter-then-flatmap shape (7g), and it is what made
//     the level walk recursive: a partial level BRANCHES, so every level after it
//     — and the payload — is assembled once per covered cell, under that cell's
//     own context. The list being flattened is itself computed at the merged
//     context, so the whole chain rides on the containment theorem.
//
//     Both fiberings of the shape are drawn: the partial nested inside a list
//     loop, and the partial as the outermost level with no loop above it.
// ============================================================================

header("partial collect: a merged flow as a non-trailing level (filter-then-flatmap)")
{
  let mk = (~overList: bool) => {
    let b = Build.make()
    let disc = Build.raw(
      b,
      "c => ({tag: c < 300 ? 'Ok' : (c < 400 ? 'Redirect' : (c < 500 ? 'ClientError' : 'ServerError')), value: c})",
    )
    // A per-error detail list, computed AT the merged context {CE, SE}.
    let expand = Build.raw(b, "c => [c, c + 1]")
    let src = overList
      ? Build.lit(b, array_([int_(200), int_(404), int_(301), int_(500)]))
      : Build.lit(b, int_(404))
    let (elem, outerFlow) = if overList {
      let it = Build.uncollectList(b, src.value)
      (it.element, Some(it.flow))
    } else {
      (src.value, None)
    }
    let h = Build.caseSplit(
      b,
      ~alts=["Ok", "Redirect", "ClientError", "ServerError"],
      ~discriminator=disc.value,
      elem,
    )
    let clientErr = Build.alt(h, "ClientError")
    let serverErr = Build.alt(h, "ServerError")
    let errs = Build.collectCases(
      b,
      [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
    )
    let errFlow = Program.FlowPort(errs.node, "flow")
    let details = Build.app(b, expand.value, [errs.value])
    let inner = Build.uncollectList(b, details.value)
    // Filter to the error firings, then flatten each one's detail list: the
    // partial level sits ABOVE an iter level, not at the end of the chain.
    let filtered = switch outerFlow {
    | Some(lf) => Build.join(b, ~outer=lf, ~inner=errFlow).flow
    | None => errFlow
    }
    let flat = Build.join(b, ~outer=filtered, ~inner=inner.flow)
    let out = Build.collect(b, ~flow=flat.flow, inner.element)
    Build.finish(b, ~outputs=[("out", out.value)])
  }

  // Over a list: 200 (Ok) and 301 (Redirect) drop; 404 expands to [404, 405]
  // and 500 to [500, 501], flattened in firing order.
  expectOutput(
    mk(~overList=true),
    "out",
    array_([int_(404), int_(405), int_(500), int_(501)]),
  )
  expectRoundTrip(mk(~overList=true))
  // With no loop above it, the partial level is the outermost: one error
  // firing, its detail list flattened. The any-list rule still gives a list.
  expectOutput(mk(~overList=false), "out", array_([int_(404), int_(405)]))
  expectRoundTrip(mk(~overList=false))
}

// ============================================================================
// 7d. Partial collect over an option leading level —
//     join(join(list, option), <partial>). Per list element, open an option
//     (present iff n >= 2); per present value, dispatch a covered subset {A, B}
//     of the split and drop the uncovered C. The option level is a defined-check
//     nested inside the list's for-of (an absent option skips), the innermost
//     dispatch is the k-arm non-exhaustive if-chain. Any-list ⇒ list output.
//     Validated against a hand-computed value, like 7b/7c and the filter option
//     level 7e.
// ============================================================================

header("partial collect: option leading level — join(join(list, option), partial)")
{
  let b = Build.make()
  let optSrc = Build.raw(b, "n => n >= 2 ? n : undefined")
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4), int_(5), int_(6)]))
  let i1 = Build.uncollectList(b, xs.value)
  let optIn = Build.app(b, optSrc.value, [i1.element])
  let i2 = Build.uncollectOption(b, optIn.value)
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, i2.element)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  // Partial collect over the covered subset {A, B}; C drops.
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  let pf = Program.FlowPort(picked.node, "flow")
  // Flatten the option into the list (j1), then join the partial's merged flow (j2).
  let j1 = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=pf)
  let out = Build.collect(b, ~flow=j2.flow, picked.value)
  let p = Build.finish(b, ~outputs=[("picked", out.value)])
  // 1 -> option absent (skip); 2 -> Some(2) C (drop); 3 -> Some(3) A (keep 3);
  // 4 -> Some(4) B (keep 4); 5 -> Some(5) C (drop); 6 -> Some(6) A (keep 6).
  // Result [3, 4, 6].
  expectOutput(p, "picked", array_([int_(3), int_(4), int_(6)]))
  expectRoundTrip(p)
}

// ============================================================================
// 7h. Partial collect with a case-alt LEADING level — filter-then-partial,
//     join(join(list, case-alt), <partial>). Per list element, keep only the
//     "Even" alt of a first split (an ordinary filter); for the kept payload,
//     dispatch a second split (n % 3) and partial-collect the covered subset
//     {A, B}, dropping C. The kept-alt guard nests the k-arm partial dispatch —
//     the dispatch-leading-level shape, mirroring the shared level walk.
//     Any-list ⇒ list output. Validated against a hand-computed value like
//     7b/7c/7d.
// ============================================================================

header("partial collect: case-alt leading level — join(join(list, case-alt), partial)")
{
  let b = Build.make()
  let parity = Build.raw(b, "n => ({tag: n % 2 === 0 ? 'Even' : 'Odd', value: n})")
  let classify = Build.raw(b, "n => ({tag: n % 3 === 0 ? 'A' : (n % 3 === 1 ? 'B' : 'C'), value: n})")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4), int_(5), int_(6)]))
  let i1 = Build.uncollectList(b, xs.value)
  // First split: keep Even (an ordinary filter over the list).
  let par = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, i1.element)
  let even = Build.alt(par, "Even")
  // Second split over the kept payload; partial-collect the covered subset {A, B}.
  let cs = Build.caseSplit(b, ~alts=["A", "B", "C"], ~discriminator=classify.value, even.altValue)
  let ca = Build.alt(cs, "A")
  let cb = Build.alt(cs, "B")
  let picked = Build.collectCases(b, [(ca.altFlow, ca.altValue), (cb.altFlow, cb.altValue)])
  let pf = Program.FlowPort(picked.node, "flow")
  // Filter the list to its Even firings (j1), then join the partial's merged
  // flow (j2): the leading level is a case-alt dispatch, not a loop.
  let j1 = Build.join(b, ~outer=i1.flow, ~inner=even.altFlow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=pf)
  let out = Build.collect(b, ~flow=j2.flow, picked.value)
  let p = Build.finish(b, ~outputs=[("picked", out.value)])
  // Evens: 2, 4, 6. 2%3=2 -> C (drop); 4%3=1 -> B (keep 4); 6%3=0 -> A (keep 6).
  // Odds 1, 3, 5 are filtered out by the first split. Result [4, 6].
  expectOutput(p, "picked", array_([int_(4), int_(6)]))
  expectRoundTrip(p)
}

// ============================================================================
// 8. Registers: a running sum via the Delay pair
// ============================================================================

header("register pair: running sum compiles")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let sum = Build.delay(b, ~flow=it.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, it.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])

  Console.log("TEXT:")
  Console.log(TextPrint.print(p))
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("register program passes the implemented checks")
  } else {
    fail(
      "unexpected witnesses:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
  // 0 + 1 + 2 + 3 = 6, the value after the last element (init if empty).
  expectOutput(p, "total", int_(6))
}

// ============================================================================
// 8b. Register empty-list case: final = init when no iteration ran
// ============================================================================

header("register pair: empty list yields init")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([]))
  let it = Build.uncollectList(b, xs.value)
  let sum = Build.delay(b, ~flow=it.flow, ~init=Build.lit(b, int_(42)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, it.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])
  expectOutput(p, "total", int_(42))
}

// ============================================================================
// 8c. Register over a FLATTENED (joined) sequence — one global running sum
//     across a list-of-lists. The driving flow is `join(outer, inner)`, so
//     `spine` gives two iter levels: the loops nest and the ONE accumulator
//     lives outside them both, folding the whole flattened firing order. This
//     is the register's sequence face — the delay-ontology fork "dissolves on
//     sequences" (iteration-with-state-design.md); a grid (a Cross product)
//     stays the open case. `prev` aligns with the innermost element because a
//     joined driving flow places `prev` at the join's interior (Context.res).
// ============================================================================

header("register pair: running sum over a flattened list-of-lists (one accumulator)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xss = Build.lit(b, array_([array_([int_(1), int_(2)]), array_([int_(3), int_(4)])]))
  let ito = Build.uncollectList(b, xss.value)
  let iti = Build.uncollectList(b, ~nesting=ito.flow, ito.element)
  let flat = Build.join(b, ~outer=ito.flow, ~inner=iti.flow)
  let sum = Build.delay(b, ~flow=flat.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, iti.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])

  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("flattened register passes the implemented checks (prev aligns with the inner element)")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // 0 + 1 + 2 + 3 + 4 = 10 across the whole flattened sequence.
  expectOutput(p, "total", int_(10))
  // The accumulator is declared exactly once — outside both loops (one fold,
  // not one-per-outer-element).
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "total") {
    | Some(o) =>
      if countOccurrences(o.js, "let ") === 1 {
        pass("one accumulator, outside both loops (a global fold over the flatten)")
      } else {
        fail("expected a single `let ` accumulator, found " ++ Int.toString(countOccurrences(o.js, "let ")))
      }
    | None => fail("no total output")
    }
  | _ => fail("flattened register failed to compile")
  }
}

// ============================================================================
// 8d. The contrast: a register over the INNER flow directly (not the join)
//     resets per outer element — a running sum per group, collected into a
//     list. Same two lists, different register: here `final` is borne on the
//     outer flow and the accumulator lives INSIDE the outer loop, so 8c's
//     global fold and 8d's per-group folds are two distinct programs over the
//     same data (the join is what makes the fold span the whole sequence).
// ============================================================================

header("register pair: per-group running sum (register over the inner flow) -> list of totals")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xss = Build.lit(b, array_([array_([int_(1), int_(2), int_(3)]), array_([int_(10), int_(20)])]))
  let ito = Build.uncollectList(b, xss.value)
  let iti = Build.uncollectList(b, ~nesting=ito.flow, ito.element)
  let sum = Build.delay(b, ~flow=iti.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, iti.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let out = Build.collect(b, ~flow=ito.flow, w.final)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // per group: 1+2+3 = 6, 10+20 = 30.
  expectOutput(p, "out", array_([int_(6), int_(30)]))
}

// ============================================================================
// 8e. Register over a FILTERED (case-alt) driving flow — a running sum over the
//     kept subsequence. The driving flow is `join(list, case-alt)`, so `spine`
//     gives a list level then a dispatch level; the register walks the
//     Some-subsequence, advancing `reg` only on the firings whose alt matches
//     (delay-ontology-design.md, route (b) "filter inside": the Delay's flow is
//     the kept subsequence, so the register "only updates when the option is
//     Some"). The alt-guard logic is shared with the filter collect
//     (walkFilterLevels), so the step and `prev` sit INSIDE the alt guard and
//     the one `let reg` lives outside the loop and the guard.
// ============================================================================

header("register pair: running sum over a filtered sequence (only kept firings advance)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  // Keep the positives; drop the negatives (an option-shaped case split).
  let disc = Build.raw(b, "x => x > 0 ? {tag: 'Keep', value: x} : {tag: 'Drop', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(-2), int_(3), int_(-4), int_(5)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=it.flow, it.element)
  let keep = Build.alt(cs, "Keep")
  let filtered = Build.join(b, ~outer=it.flow, ~inner=keep.altFlow)
  let sum = Build.delay(b, ~flow=filtered.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, keep.altValue])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])

  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("filtered register passes the implemented checks")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // Only the kept positives fold: 0 + 1 + 3 + 5 = 9 (the negatives never advance).
  expectOutput(p, "total", int_(9))
  // One accumulator, declared once outside the loop and the alt guard.
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "total") {
    | Some(o) =>
      if countOccurrences(o.js, "let ") === 1 {
        pass("one accumulator, outside the loop and the alt guard")
      } else {
        fail("expected a single `let ` accumulator, found " ++ Int.toString(countOccurrences(o.js, "let ")))
      }
    | None => fail("no total output")
    }
  | _ => fail("filtered register failed to compile")
  }
}

// ============================================================================
// 8f. The all-dropped edge: no firing matches the kept alt, so the register
//     never advances and `final` is `init` — the same law as the empty list
//     (8b), reached through the guard rather than an empty loop.
// ============================================================================

header("register pair: a filter that keeps nothing yields init")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(b, "x => x > 0 ? {tag: 'Keep', value: x} : {tag: 'Drop', value: x}")
  let xs = Build.lit(b, array_([int_(-1), int_(-2), int_(-3)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=it.flow, it.element)
  let keep = Build.alt(cs, "Keep")
  let filtered = Build.join(b, ~outer=it.flow, ~inner=keep.altFlow)
  let sum = Build.delay(b, ~flow=filtered.flow, ~init=Build.lit(b, int_(42)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, keep.altValue])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])
  expectOutput(p, "total", int_(42))
}

// ============================================================================
// 8g. A register over a filter-then-flatmap driving flow —
//     join(join(list, case-alt), inner-list): keep the matching alts, then
//     flatten each kept alt's payload list, folding the whole flattened kept
//     order with one accumulator. The dispatch is a NON-trailing level (an iter
//     level nested inside it), so `prev` aligns with the innermost list element.
// ============================================================================

header("register pair: running sum over a filter-then-flatmap sequence")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  // Keep even-headed groups; each Keep carries the group's list as its payload.
  let disc = Build.raw(
    b,
    "g => g[0] % 2 === 0 ? {tag: 'Keep', value: g} : {tag: 'Drop', value: g}",
  )
  let groups = Build.lit(
    b,
    array_([
      array_([int_(2), int_(3)]),    // head 2 even -> kept, contributes 2, 3
      array_([int_(5), int_(7)]),    // head 5 odd  -> dropped
      array_([int_(4), int_(1), int_(6)]), // head 4 even -> kept, contributes 4, 1, 6
    ]),
  )
  let ito = Build.uncollectList(b, groups.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=ito.flow, ito.element)
  let keep = Build.alt(cs, "Keep")
  let iti = Build.uncollectList(b, ~nesting=keep.altFlow, keep.altValue)
  // join(join(list, case-alt), inner-list): filter the groups, flatten the kept.
  let j1 = Build.join(b, ~outer=ito.flow, ~inner=keep.altFlow)
  let flat = Build.join(b, ~outer=j1.flow, ~inner=iti.flow)
  let sum = Build.delay(b, ~flow=flat.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, iti.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])
  // 0 + (2+3) + (4+1+6) = 16; the odd-headed group never advances.
  expectOutput(p, "total", int_(16))
}

// ============================================================================
// 8l. A register over a PARTIAL merged driving flow — the k-arm-dispatch cell-set
//     case, which is the filtered register (8e) at width k. A partial collect
//     merges the two error cells of a status-code split; the register folds over
//     the merged flow, so the kept subsequence is "the firings landing in ANY
//     covered cell" and `OrderDemand.orderOf` reads its order as the parent's,
//     restricted — the same reading a single alt gets.
//
//     Nothing new was needed in the emitter: `emitRegister` now assembles
//     through `buildChain`, the recursive level walk `emitCellChain` uses, so a
//     partial level BRANCHES — each covered cell re-assembles the step subtree
//     under its own context (exactly one arm runs per firing), while the ONE
//     `let reg` stays outside every loop, guard, and arm. The severity is
//     computed AT the merged context, so the containment theorem carries it into
//     each arm: two arms syntactically, one evaluation per firing.
// ============================================================================

header("register pair: running sum over a partial (cell-set) merged driving flow")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let severity = Build.raw(b, "c => c >= 500 ? 10 : 1")
  let disc = Build.raw(
    b,
    "c => ({tag: c < 300 ? 'Ok' : (c < 400 ? 'Redirect' : (c < 500 ? 'ClientError' : 'ServerError')), value: c})",
  )
  let codes = Build.lit(b, array_([int_(200), int_(404), int_(500), int_(301), int_(503)]))
  let it = Build.uncollectList(b, codes.value)
  let cs = Build.caseSplit(
    b,
    ~alts=["Ok", "Redirect", "ClientError", "ServerError"],
    ~discriminator=disc.value,
    ~nesting=it.flow,
    it.element,
  )
  let clientErr = Build.alt(cs, "ClientError")
  let serverErr = Build.alt(cs, "ServerError")
  // Merge the two error cells; the merged value is the status code either way.
  let errs = Build.collectCases(
    b,
    [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
  )
  let errFlow = Program.FlowPort(errs.node, "flow")
  let kept = Build.join(b, ~outer=it.flow, ~inner=errFlow)
  // Computed at the merged context {ClientError, ServerError}, then folded.
  let sev = Build.app(b, severity.value, [errs.value])
  let total = Build.delay(b, ~flow=kept.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [total.prev, sev.value])
  let w = Build.writeBack(b, ~read=total, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])

  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("a register over a merged flow passes the implemented checks")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // 200 (Ok) and 301 (Redirect) never fire the merged flow. 404 -> 1,
  // 500 -> 10, 503 -> 10: the fold is 0 + 1 + 10 + 10 = 21.
  expectOutput(p, "total", int_(21))
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "total") {
    | Some(o) =>
      // One accumulator outside every loop, guard, and arm...
      if countOccurrences(o.js, "let ") === 1 {
        pass("one accumulator, outside the loop and both cell arms")
      } else {
        fail("expected a single `let ` accumulator, found " ++ Int.toString(countOccurrences(o.js, "let ")))
      }
      // ...and the step subtree emitted once per covered cell (two arms, two
      // copies), which is the doc's sanctioned duplication: exactly one runs.
      if countOccurrences(o.js, "\"ClientError\"") === 1 && countOccurrences(o.js, "\"ServerError\"") === 1 {
        pass("one arm per covered cell, the uncovered cells absent")
      } else {
        fail("expected exactly one arm per covered cell")
      }
    | None => fail("no total output")
    }
  | _ => fail("the partial register failed to compile")
  }
}

// ============================================================================
// 8m. The empty case: no firing lands in a covered cell, so the register never
//     advances and `final` is `init` — the all-dropped edge (8f) at width k.
// ============================================================================

header("register pair: a merged flow that never fires yields init")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(
    b,
    "c => ({tag: c < 300 ? 'Ok' : (c < 400 ? 'Redirect' : (c < 500 ? 'ClientError' : 'ServerError')), value: c})",
  )
  let codes = Build.lit(b, array_([int_(200), int_(301), int_(204)]))
  let it = Build.uncollectList(b, codes.value)
  let cs = Build.caseSplit(
    b,
    ~alts=["Ok", "Redirect", "ClientError", "ServerError"],
    ~discriminator=disc.value,
    ~nesting=it.flow,
    it.element,
  )
  let clientErr = Build.alt(cs, "ClientError")
  let serverErr = Build.alt(cs, "ServerError")
  let errs = Build.collectCases(
    b,
    [(clientErr.altFlow, clientErr.altValue), (serverErr.altFlow, serverErr.altValue)],
  )
  let kept = Build.join(b, ~outer=it.flow, ~inner=Program.FlowPort(errs.node, "flow"))
  let total = Build.delay(b, ~flow=kept.flow, ~init=Build.lit(b, int_(7)).value)
  let stepped = Build.app(b, addF.value, [total.prev, errs.value])
  let w = Build.writeBack(b, ~read=total, ~step=stepped.value)
  let p = Build.finish(b, ~outputs=[("total", w.final)])
  expectOutput(p, "total", int_(7))
}

// ============================================================================
// 8h. The running view (scanl): a sibling collect over the SAME driving flow
//     reads the register's `prev`, building the running-value list. A register
//     is a feature of the flow (delay-ontology-design.md), so its running total
//     is readable per firing; the eager model gives the reading collect its own
//     loop that re-runs the fold and PUSHES `prev` each step. Collecting `prev`
//     yields the prefix sums BEFORE each element ([0, 1, 3] for [1,2,3]);
//     collecting the stepped value yields them AFTER ([1, 3, 6]). The write
//     half's `final` still folds independently in its own loop.
// ============================================================================

header("register pair: running view (scanl) — a sibling collect reads prev")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let sum = Build.delay(b, ~flow=it.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, it.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  // Running-before list (collect prev): [0, 1, 3]. Running-after list (collect
  // the stepped value): [1, 3, 6]. And the final total alongside: 6.
  let before = Build.collect(b, ~flow=it.flow, sum.prev)
  let after = Build.collect(b, ~flow=it.flow, stepped.value)
  let p = Build.finish(
    b,
    ~outputs=[("before", before.value), ("after", after.value), ("total", w.final)],
  )
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("running-view program passes the implemented checks")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectOutput(p, "before", array_([int_(0), int_(1), int_(3)]))
  expectOutput(p, "after", array_([int_(1), int_(3), int_(6)]))
  expectOutput(p, "total", int_(6))
  expectRoundTrip(p)
}

// ============================================================================
// 8i. The running view over a FLATTENED (joined) driving flow: a register folds
//     a list-of-lists with one accumulator (test 8c), and the sibling running
//     collect re-runs that same flattened fold, pushing one running value per
//     innermost element — a flat list of prefix sums across the whole order.
// ============================================================================

header("register pair: running view over a flattened list-of-lists")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let outer = Build.lit(b, array_([array_([int_(1), int_(2)]), array_([int_(3), int_(4)])]))
  let ito = Build.uncollectList(b, outer.value)
  let iti = Build.uncollectList(b, ~nesting=ito.flow, ito.element)
  let flat = Build.join(b, ~outer=ito.flow, ~inner=iti.flow)
  let sum = Build.delay(b, ~flow=flat.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, iti.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  // Flattened order 1,2,3,4 -> running-after prefix sums 1,3,6,10; total 10.
  let after = Build.collect(b, ~flow=flat.flow, stepped.value)
  let p = Build.finish(b, ~outputs=[("after", after.value), ("total", w.final)])
  expectOutput(p, "after", array_([int_(1), int_(3), int_(6), int_(10)]))
  expectOutput(p, "total", int_(10))
}

// ============================================================================
// 8j. The FILTERED running view: a sibling collect reads `prev` over a filtered
//     (case-alt) driving flow. The register itself already folds the kept
//     subsequence (tests 8e–8g, delay-ontology-design.md route (b) "filter
//     inside"); the view is that same fold re-run with a push, so it walks the
//     SAME levels — `walkFilterLevels`, shared with the register and the filter
//     collect — and both the push and the advance sit inside the alt guard. One
//     output element per KEPT firing: a dropped firing contributes nothing to
//     the view and does not step the register. Filter-then-scan, which is what
//     the composition ought to mean.
// ============================================================================

header("register pair: the running view over a filtered (case-alt) driving flow")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(b, "x => x > 0 ? {tag: 'Keep', value: x} : {tag: 'Drop', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(-2), int_(3), int_(-4), int_(5)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=it.flow, it.element)
  let keep = Build.alt(cs, "Keep")
  let filtered = Build.join(b, ~outer=it.flow, ~inner=keep.altFlow)
  let sum = Build.delay(b, ~flow=filtered.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, keep.altValue])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  // Sibling collects over the SAME filtered flow. Kept subsequence: 1, 3, 5.
  // Running-before (collect prev): [0, 1, 4]; running-after (collect the
  // stepped value): [1, 4, 9]; the write half's own fold: 9.
  let before = Build.collect(b, ~flow=filtered.flow, sum.prev)
  let after = Build.collect(b, ~flow=filtered.flow, stepped.value)
  let p = Build.finish(
    b,
    ~outputs=[("before", before.value), ("after", after.value), ("total", w.final)],
  )
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("filtered running view passes the implemented checks (well-formed)")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectOutput(p, "before", array_([int_(0), int_(1), int_(4)]))
  expectOutput(p, "after", array_([int_(1), int_(4), int_(9)]))
  expectOutput(p, "total", int_(9))
  // (No round-trip: the text surface for a nested case split in a chain is a
  // known TextPrint gap, shared with the filtered register tests 8e–8g.)
}

// ============================================================================
// 8j2. The filtered running view over a NON-TRAILING dispatch (filter-then-
//      flatmap): keep an alt, then flatten the kept payload's list. The register
//      folds the flattened kept order (test 8g); the view pushes once per
//      innermost element of that order. Same walk, one more level.
// ============================================================================

header("register pair: running view over a filter-then-flatmap driving flow")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  // Keep the rows whose head is positive; the alt payload is the row itself.
  let disc = Build.raw(b, "r => r[0] > 0 ? {tag: 'Keep', value: r} : {tag: 'Drop', value: r}")
  let rows = Build.lit(
    b,
    array_([
      array_([int_(1), int_(2)]),
      array_([int_(-9), int_(100)]),
      array_([int_(3), int_(4)]),
    ]),
  )
  let ito = Build.uncollectList(b, rows.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=ito.flow, ito.element)
  let keep = Build.alt(cs, "Keep")
  let iti = Build.uncollectList(b, ~nesting=keep.altFlow, keep.altValue)
  let kept = Build.join(b, ~outer=ito.flow, ~inner=keep.altFlow)
  let flat = Build.join(b, ~outer=kept.flow, ~inner=iti.flow)
  let sum = Build.delay(b, ~flow=flat.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, iti.element])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  // Kept flattened order 1,2,3,4 (the -9 row is dropped whole) -> running-after
  // prefix sums 1,3,6,10; total 10.
  let after = Build.collect(b, ~flow=flat.flow, stepped.value)
  let p = Build.finish(b, ~outputs=[("after", after.value), ("total", w.final)])
  expectOutput(p, "after", array_([int_(1), int_(3), int_(6), int_(10)]))
  expectOutput(p, "total", int_(10))
}

// ============================================================================
// 8j3. The running view over a PARTIAL (cell-set) driving flow — the scan of the
//      kept subsequence at width k. A partial collect merges two of a split's
//      three cells; the register folds the merged value over the firings that
//      land in either, and a sibling collect over that same merged flow reads
//      `prev` to build the running view. One element per KEPT firing, exactly as
//      the filtered view (8j) — the same construct with k arms instead of one.
//
//      The two halves agree by construction: both walk the levels through the
//      shared `buildChain`, so the push and the advance sit inside the arm that
//      fired, and `levelKey` names a partial level by its CELL SET, so a view is
//      only offered a register that scans the same subsequence.
// ============================================================================

header("register pair: running view over a partial (cell-set) merged driving flow")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(
    b,
    "x => x % 3 === 0 ? {tag: 'Three', value: x} : (x % 2 === 0 ? {tag: 'Two', value: x} : {tag: 'Other', value: x})",
  )
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(
    b,
    ~alts=["Three", "Two", "Other"],
    ~discriminator=disc.value,
    ~nesting=it.flow,
    it.element,
  )
  let three = Build.alt(cs, "Three")
  let two = Build.alt(cs, "Two")
  // A partial collect over two of the three alts: the merged flow of the
  // covered cells.
  let pc = Build.collectCases(
    b,
    [(three.altFlow, three.altValue), (two.altFlow, two.altValue)],
  )
  let merged = Program.FlowPort(pc.node, "flow")
  let inner = Build.join(b, ~outer=it.flow, ~inner=merged)
  let sum = Build.delay(b, ~flow=inner.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, pc.value])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let before = Build.collect(b, ~flow=inner.flow, sum.prev)
  let after = Build.collect(b, ~flow=inner.flow, stepped.value)
  let p = Build.finish(
    b,
    ~outputs=[("before", before.value), ("after", after.value), ("total", w.final)],
  )
  // 1 -> Other, dropped. 2 -> Two, 3 -> Three, 4 -> Two: the kept subsequence
  // carries 2, 3, 4. Prefix sums before each kept firing: [0, 2, 5]; after:
  // [2, 5, 9]; and `final` folds independently to 9.
  expectOutput(p, "before", array_([int_(0), int_(2), int_(5)]))
  expectOutput(p, "after", array_([int_(2), int_(5), int_(9)]))
  expectOutput(p, "total", int_(9))
}

// ============================================================================
// 8j4. The cell set is what identifies the subsequence. A register folding
//      {Three, Two} is NOT the register a view over {Three, Other} wants: the
//      two merges keep different firings, so "does this register scan the same
//      sequence I iterate?" must answer no — which is why `levelKey` names a
//      partial level by its cells, exactly as it names an alt level by its alt.
//      Either answer is acceptable (a witness, or a clean Todo); silently
//      compiling someone else's fold is not.
// ============================================================================

header("register pair: a view over a different cell set is not offered the fold")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(
    b,
    "x => x % 3 === 0 ? {tag: 'Three', value: x} : (x % 2 === 0 ? {tag: 'Two', value: x} : {tag: 'Other', value: x})",
  )
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(
    b,
    ~alts=["Three", "Two", "Other"],
    ~discriminator=disc.value,
    ~nesting=it.flow,
    it.element,
  )
  let three = Build.alt(cs, "Three")
  let two = Build.alt(cs, "Two")
  let other = Build.alt(cs, "Other")
  let folded = Build.collectCases(
    b,
    [(three.altFlow, three.altValue), (two.altFlow, two.altValue)],
  )
  let viewed = Build.collectCases(
    b,
    [(three.altFlow, three.altValue), (other.altFlow, other.altValue)],
  )
  let foldFlow = Build.join(b, ~outer=it.flow, ~inner=Program.FlowPort(folded.node, "flow"))
  let viewFlow = Build.join(b, ~outer=it.flow, ~inner=Program.FlowPort(viewed.node, "flow"))
  let sum = Build.delay(b, ~flow=foldFlow.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, folded.value])
  let _ = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  let running = Build.collect(b, ~flow=viewFlow.flow, sum.prev)
  let p = Build.finish(b, ~outputs=[("running", running.value)])
  switch Pipeline.compile(p) {
  | exception Codegen.Todo(_) => pass("a view over a different cell set declines with a clean Todo")
  | Error(_) => pass("a view over a different cell set is witnessed before codegen")
  | Ok(_) => fail("a view over a different cell set compiled against someone else's fold")
  }
}

// ============================================================================
// 8k. The other side of the order-demand rule: DEGENERATE order is well-formed,
//     not ill-formed. A bare option (or case alt) is totally ordered trivially,
//     because it has at most one firing — so a register there never steps and
//     `prev` only ever reads the seed. delay-ontology-design.md makes the point
//     that this is a fact about CARDINALITY, not about the kind ("the async
//     value supplies no next *because it is one firing, not because it is
//     async* — the same reason a bare option doesn't, and nobody ever felt a
//     need to write 'Delay is meaningless over options' as a kind fact"). So
//     the check must ADMIT it, and the compiler must produce the inert fold:
//     seed when the option is absent, one step when it fires.
// ============================================================================

header("register pair: a register over a bare option is inert, not ill-formed")
{
  let mk = (input: JsAst.expr) => {
    let b = Build.make()
    let addF = Build.raw(b, "(a, b) => a + b")
    let optSrc = Build.raw(b, "n => n >= 2 ? n : undefined")
    let v = Build.lit(b, input)
    let optIn = Build.app(b, optSrc.value, [v.value])
    let i = Build.uncollectOption(b, optIn.value)
    let reg = Build.delay(b, ~flow=i.flow, ~init=Build.lit(b, int_(100)).value)
    let step = Build.app(b, addF.value, [reg.prev, i.element])
    let w = Build.writeBack(b, ~read=reg, ~step=step.value)
    Build.finish(b, ~outputs=[("total", w.final)])
  }
  // One firing: `prev` reads the seed, the single step runs. 100 + 5.
  expectOutput(mk(int_(5)), "total", int_(105))
  // No firing: the fold is the seed itself.
  expectOutput(mk(int_(1)), "total", int_(100))
}

// ============================================================================
// 9. Witness surface: a bad port reference
// ============================================================================

header("check: bad port reference yields a witness, not a crash")
{
  let n0: Program.node = {id: 0, kind: Lit(int_(1))}
  let n1: Program.node = {
    id: 1,
    kind: App({
      fn: ValuePort(n0, "value"),
      args: [ValuePort(n0, "oops")],
    }),
  }
  let p: Program.program = {
    nodes: [n0, n1],
    outputs: [{name: "x", source: ValuePort(n1, "value")}],
  }
  switch Pipeline.compile(p) {
  | Error(ws) => {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("port-exists witness produced")
    }
  | Ok(_) => fail("bad port ref compiled")
  }
}

// ============================================================================
// 10. Completion: the sibling-opens combine (the old silent time travel) is now
//     COMPLETED — the two-lists program with no hand-drawn Cross has one
//     inserted for it (product-flows-design.md, "smallest first step" 3;
//     time-travel-programs-design.md, disposition 4). What test 13b checked at
//     the Check level — a Cross admits this combine — completion now supplies
//     automatically, and the completed program compiles via the whole-table
//     emitter (test 15) to the same values as the hand-drawn version.
// ============================================================================

header("complete: a sibling-opens combine gets a Cross inserted, then compiles")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  // No hand-drawn Cross: this is the under-committed time-travel program.
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let outer = Build.collect(b, ~flow=itY.flow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", outer.value)])
  // Collect itX inner (holding y), itY outer — per y, the list over x.
  expectOutput(p, "out", array_([array_([int_(11), int_(12)]), array_([int_(21), int_(22)])]))
  // The completion is reported as an insertion addressed to the combine's node.
  switch Pipeline.compile(p) {
  | Ok({insertions}) =>
    if Array.length(insertions) === 1 {
      Console.log("insertion: " ++ (insertions->Array.getUnsafe(0)).description)
      pass("completion inserted exactly one Cross for the sibling combine")
    } else {
      fail("expected one inserted Cross, got " ++ Int.toString(Array.length(insertions)))
    }
  | Error(ws) =>
    fail("sibling-opens program failed to complete:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 10c. Completion at rank 3: the SAME sibling-opens completion, n-ary. Three
//      lists combined with no hand-drawn Cross — an under-committed time-travel
//      program over {X,Y,Z}. Completion inserts the product spanning exactly
//      those axes (a nested `Cross(Cross(x,y),z)` chain), and the completed
//      program compiles via the whole-table cube emitter to the same values as
//      the hand-authored rank-3 product (test 15d/15e). The full span is read
//      off the flow-variable sets, so all three axes are reached — not just the
//      first incomparable pair (product-flows-design.md, N-ary; the completion's
//      "n-ary combines" gap discharged).
header("complete: a rank-3 sibling-opens combine gets a product inserted, then compiles")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  // No hand-drawn Cross anywhere: the fully-uncrossed rank-3 time-travel program.
  let a1 = Build.collect(b, ~flow=itX.flow, s.value) // inner: holds y, z; lists over x
  let a2 = Build.collect(b, ~flow=itY.flow, a1.value) // mid
  let out = Build.collect(b, ~flow=itZ.flow, a2.value) // outer
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // out[iz][iy][ix] = x + y + z — identical to the hand-authored 15d/15e cube.
  expectOutput(
    p,
    "out",
    array_([
      array_([array_([int_(111), int_(112)]), array_([int_(121), int_(122)])]),
      array_([array_([int_(211), int_(212)]), array_([int_(221), int_(222)])]),
    ]),
  )
  // One product is reported (however many binary Cross nodes back it).
  switch Pipeline.compile(p) {
  | Ok({insertions}) =>
    if Array.length(insertions) === 1 {
      Console.log("insertion: " ++ (insertions->Array.getUnsafe(0)).description)
      pass("completion inserted one rank-3 product for the sibling combine")
    } else {
      fail("expected one inserted product, got " ++ Int.toString(Array.length(insertions)))
    }
  | Error(ws) =>
    fail("rank-3 sibling-opens program failed to complete:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 10d. The completion LENS, in text: everything completion inserted prints
//      faint — a leading `+` (time-travel-programs-design.md, "in the textual
//      form, faint is a leading `+`"; textual-representation-design.md, "the
//      printer renders the derived insertions as `+` lines"). The program is
//      authored under-committed IN TEXT — two sibling opens, no `cross with`
//      line — and `Pipeline.completionText` shows it back with the product the
//      compiler supplied.
//
//      The three laws the design states for the lens are checked here rather
//      than asserted, and each one is a property of machinery that already
//      existed: CONSERVATIVITY — parse discards `+` lines, so reparsing the
//      completed print gives back the AUTHORED program, byte-identical wiring
//      to what the source built; DETERMINISM/IDEMPOTENCE — completing that
//      reparse reproduces the same text; and the completed program has no `+`
//      lines of its own when printed plainly (the insertions are re-derived,
//      never stored). The statement ORDER needs no new machinery either: the
//      printer's topological sort already places the inserted `cross with`
//      after the statements binding its two operand flows, which is the doc's
//      "reordering statements as needed to restore token-order-is-time".
header("complete: the inserted product prints faint (`+` lines) and reparses away")
{
  let src = `
add = js "(a, b) => a + b"
[1, 2] -> open list => ~fx, ex
[10, 20] -> open list => ~fy, ey
ex, ey -> add => s
s -~> collect ~fx => inner
inner -~> collect ~fy => out1
out out1
`
  let authored = TextResolve.parseProgram(src)
  let lens = Pipeline.completionText(authored)
  Console.log("COMPLETION LENS:")
  Console.log(lens)

  // The lens shows exactly one derived line, and it is the inserted product.
  let plusLines =
    lens->String.split("\n")->Array.filter(l => l->String.startsWith("+"))
  switch plusLines {
  | [one] if one->String.includes("cross with") =>
    pass("the completion lens renders the inserted product as one `+` line")
  | _ =>
    fail(
      "expected exactly one `+ … cross with …` line, got:\n  " ++
      plusLines->Array.join("\n  "),
    )
  }

  // Conservativity: `+` lines are derived, not stored — reparsing the lens
  // gives back the authored program, not the completed one.
  let reparsed = TextResolve.parseProgram(lens)
  if Program.equal(authored, reparsed) {
    pass("reparsing the lens discards the `+` lines — the authored program comes back")
  } else {
    fail(
      "lens reparse changed the wiring\n-- authored --\n" ++
      Program.dump(authored) ++
      "\n-- reparsed --\n" ++
      Program.dump(reparsed),
    )
  }

  // Determinism + idempotence: re-deriving the lens from that reparse
  // reproduces it exactly.
  if Pipeline.completionText(reparsed) === lens {
    pass("the lens is deterministic and idempotent (re-derived, never stored)")
  } else {
    fail("re-deriving the lens produced different text")
  }

  // And a program that IS complete has no `+` lines: the same wiring with the
  // product drawn solid is its own completion (constraint 1, "explicit
  // structure is fixed").
  let solid = TextResolve.parseProgram(
    src->String.replace("ex, ey -> add => s", "~fx ~> cross with ~fy => ~fxy\nex, ey -> add => s"),
  )
  if !(Pipeline.completionText(solid)->String.includes("\n+")) {
    pass("a program authored with the product drawn solid completes to no `+` lines")
  } else {
    fail("a complete program produced completion lines:\n" ++ Pipeline.completionText(solid))
  }
}

header("complete: a non-invariant sibling cross is NOT completed (stays a witness)")
{
  // Two independent opens, but itY's SOURCE is derived from itX's element via a
  // hand-drawn (invalid) Cross — a dependent nesting, not a product. Completion
  // must not paper over it; the invariance check still witnesses.
  let b = Build.make()
  let mkRange = Build.raw(b, "n => Array.from({length: n}, (_, i) => i)")
  let xs = Build.lit(b, array_([int_(2), int_(3)]))
  let itX = Build.uncollectList(b, xs.value)
  let ys = Build.app(b, mkRange.value, [itX.element])
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let p = Build.finish(b, ~outputs=[("out", xs.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "invariance") {
      pass("dependent nesting still witnessed as non-invariant (not silently completed)")
    } else {
      fail("expected an invariance witness, got:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
    }
  | Ok(_) => fail("dependent cross was wrongly completed")
  }
}

// ============================================================================
// 10b. Witness surface: combining two ALTS of one split — bundle mixing, the
//      other clash flavor. The two values live in mutually exclusive cells of
//      one case split, so no execution produces both; this is a hard error, not
//      a completable time-travel gap (bundle-provenance-design.md).
// ============================================================================

header("check: combining sibling alts of one split is witnessed as bundle mixing")
{
  let b = Build.make()
  let disc = Build.raw(
    b,
    "x => x === undefined ? {tag: 'Nothing'} : {tag: 'Just', value: x}",
  )
  let addF = Build.raw(b, "(a, b) => a + b")
  let five = Build.lit(b, int_(5))
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, five.value)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  // Combine the Just payload with the Nothing payload directly — no collect.
  let mixed = Build.app(b, addF.value, [just.altValue, nothing.altValue])
  let p = Build.finish(b, ~outputs=[("bad", mixed.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "bundle-mixing") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("bundle-mixing witness produced")
    } else {
      fail(
        "expected a bundle-mixing witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("sibling-alt combination compiled without a witness")
  }
}

// ============================================================================
// 11. Witness surface: a malformed case collect (an alt covered twice)
// ============================================================================

header("check: covering an alt twice is witnessed, not a codegen crash")
{
  let b = Build.make()
  let disc = Build.raw(b, "x => ({tag: 'A', value: x})")
  let xs = Build.lit(b, array_([int_(1)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["A", "B"], ~discriminator=disc.value, it.element)
  let zero = Build.lit(b, int_(0))
  let one = Build.lit(b, int_(1))
  // Two branches for "A", none for "B": covered-count still matches, so this
  // would misclassify as full and crash the case emitter without a check.
  let perElem = Build.collectCases(
    b,
    [(Build.alt(cs, "A").altFlow, zero.value), (Build.alt(cs, "A").altFlow, one.value)],
  )
  let out = Build.collect(b, ~flow=it.flow, perElem.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "coverage") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("coverage witness produced")
    } else {
      fail("expected a coverage witness, got:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
    }
  | Ok(_) => fail("malformed case collect compiled without a witness")
  }
}

// ============================================================================
// 12. Witness surface: the general interior rule. A case collect whose branch
//     for one alt reads ANOTHER alt's payload — a value borne on a sibling cell
//     the collect does not iterate at that branch. Coverage is well-formed (one
//     branch per alt) and no node merges the two cells, so neither the coverage
//     nor the alignment check fires; without the interior rule this reaches
//     Codegen and trips its "flow-borne port reached outside its flow" failwith
//     (a crash, since Pipeline only catches Todo). The check turns it into a
//     witness.
// ============================================================================

header("check: a case collect branch reading a sibling alt's payload is witnessed")
{
  let b = Build.make()
  let disc = Build.raw(
    b,
    "x => x === undefined ? {tag: 'Nothing'} : {tag: 'Just', value: x}",
  )
  let xs = Build.lit(b, array_([int_(1), undefined, int_(5)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, it.element)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  // The "Just" branch reads the "Nothing" payload — the wrong cell. Coverage is
  // still one-branch-per-alt (well-formed), so only the interior rule catches it.
  let perElem = Build.collectCases(
    b,
    [(just.altFlow, nothing.altValue), (nothing.altFlow, nothing.altValue)],
  )
  let out = Build.collect(b, ~flow=it.flow, perElem.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "flow-borne") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("flow-borne interior witness produced")
    } else {
      fail(
        "expected a flow-borne witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("cross-cell case collect compiled without a witness")
  }
}

// ============================================================================
// 13. Cross's demand: mutual invariance (product-flows-design.md, the Cross
//     round's first step). Two sibling top-level flows are mutually invariant —
//     a legitimate product, the two-lists program — so they raise no invariance
//     witness (the whole-table emitter is still the deferred poset round, so we
//     assert at the Check level, not by compiling). Crossing an axis with a
//     flow DERIVED from its element is dependent nesting, not a product, and is
//     witnessed.
// ============================================================================

header("check: two sibling flows cross cleanly (the invariance demand holds)")
{
  let b = Build.make()
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  // Output something trivial; the Cross sits in the node set and the invariance
  // check visits it regardless of downstream use.
  let p = Build.finish(b, ~outputs=[("out", xs.value)])
  let ws = Check.check(p)
  if ws->Array.some(w => w.rule === "invariance") {
    fail(
      "sibling cross wrongly witnessed as non-invariant:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  } else {
    pass("sibling cross satisfies the invariance demand (emitter is the poset round)")
  }
}

header("check: siblings sharing an outer loop still cross cleanly (source vs own axis)")
{
  // Two inner flows nested in ONE outer loop. They SHARE the outer axis, but
  // neither's firings depend on the OTHER's element — mutually invariant within
  // the shared loop. This is the case that would break a naive set-disjointness
  // test (the shared outer axis is in both operands' full axis sets); the demand
  // is source-vs-introduced, so it passes.
  let b = Build.make()
  let ls = Build.lit(b, array_([int_(0), int_(1)]))
  let itL = Build.uncollectList(b, ls.value)
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, ~nesting=itL.flow, xs.value)
  let itY = Build.uncollectList(b, ~nesting=itL.flow, ys.value)
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let p = Build.finish(b, ~outputs=[("out", ls.value)])
  let ws = Check.check(p)
  if ws->Array.some(w => w.rule === "invariance") {
    fail(
      "siblings sharing an outer loop wrongly witnessed:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  } else {
    pass("shared-outer siblings cross cleanly (the demand tests source, not raw axes)")
  }
}

header("check: crossing an axis with a flow derived from its element is witnessed")
{
  let b = Build.make()
  let mkRange = Build.raw(b, "n => Array.from({length: n}, (_, i) => i)")
  let xs = Build.lit(b, array_([int_(2), int_(3)]))
  let itX = Build.uncollectList(b, xs.value)
  // itY's SOURCE depends on itX's element — the inner flow's shape varies with
  // the outer element, so the two are not mutually invariant.
  let ys = Build.app(b, mkRange.value, [itX.element])
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let p = Build.finish(b, ~outputs=[("out", xs.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "invariance") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("invariance witness produced (dependent nesting is not a product)")
    } else {
      fail(
        "expected an invariance witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("dependent cross compiled without a witness")
  }
}

// ============================================================================
// 13b. Context wired onto Poset: a Cross ADMITS a sibling combine. The same
//      two-lists program that witnessed time travel in test 10 (add x, y over
//      two independent opens) is now well-formed once a Cross constructs their
//      product — the combine has a home at {X || Y} (product-flows-design.md,
//      "The context model"). Checked at the Check level, not compiled: the
//      point-indexed-table emitter is still the deferred poset round, so the
//      collects here would trip Codegen — the well-formedness gate is what
//      advances, exactly as with the invariance demand (test 13).
// ============================================================================

let noAlignmentWitness = (label, ws: array<Check.witness>) =>
  if ws->Array.some(w => w.rule === "time-travel" || w.rule === "invariance") {
    fail(label ++ " — unexpected witness:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  } else {
    pass(label)
  }

header("check: a Cross admits the sibling combine that was time travel without it")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  // The Cross that gives {X, Y} a home. Without it, this is test 10's time travel.
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let outer = Build.collect(b, ~flow=itY.flow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", outer.value)])
  noAlignmentWitness("the Cross gives the sibling combine a home at {X || Y}", Check.check(p))
}

header("check: siblings sharing an outer loop cross and combine cleanly (L > {X || Y})")
{
  // The product's exterior is the shared loop L; the two axes go parallel inside
  // it. Exercises crossProduct's series-prefix-then-parallel construction.
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let ls = Build.lit(b, array_([int_(0), int_(1)]))
  let itL = Build.uncollectList(b, ls.value)
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, ~nesting=itL.flow, xs.value)
  let itY = Build.uncollectList(b, ~nesting=itL.flow, ys.value)
  let _ = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let p = Build.finish(b, ~outputs=[("out", ls.value)])
  noAlignmentWitness("shared-outer siblings combine at L > {X || Y}", Check.check(p))
}

header("check: a Cross of the WRONG axes does not admit the combine (still time travel)")
{
  // Three independent opens; combine x with y, but the only Cross is (x, z). Its
  // product is {X || Z}, which does not host the {X, Y} combine — a combine's
  // home is exact, not a covering-or-adjacent product. So the clash still stands.
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1)]))
  let ys = Build.lit(b, array_([int_(10)]))
  let zs = Build.lit(b, array_([int_(100)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itZ.flow)
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let outer = Build.collect(b, ~flow=itY.flow, inner.value)
  let _ = itZ
  let p = Build.finish(b, ~outputs=[("out", outer.value)])
  let ws = Check.check(p)
  if ws->Array.some(w => w.rule === "time-travel") {
    pass("a {X || Z} cross does not host the {X, Y} combine — still time travel")
  } else {
    fail(
      "expected the {X,Y} combine to stay time travel, got:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
}

// ============================================================================
// 14. The series-parallel context algebra (Poset.res) — the Fork-A `≤` primitive
//     and the LUB merge, unit-tested against the cases worked on paper. Products
//     + nesting only (cells arrive with partial-collect's merged context).
// ============================================================================

header("poset: the ≤ primitive (axes-⊆ + order-extends)")
{
  open Poset
  let x = Axis("x")
  let y = Axis("y")
  let z = Axis("z")
  let a = Axis("a")
  let leqCheck = (name, s, r, expected) =>
    if leq(s, r) === expected {
      pass("≤ " ++ name ++ " (" ++ toString(s) ++ (expected ? " ≤ " : " ≰ ") ++ toString(r) ++ ")")
    } else {
      fail("≤ " ++ name ++ ": " ++ toString(s) ++ " vs " ++ toString(r) ++ " expected " ++ (expected ? "≤" : "≰"))
    }

  // table reused in a traversal: the product is available at either nesting order
  leqCheck("product ≤ traversal", parallel([x, y]), series([y, x]), true)
  leqCheck("product ≤ other traversal", parallel([x, y]), series([x, y]), true)
  // no time travel: a nesting is not available at the reversed nesting
  leqCheck("nesting ≰ reversed", series([x, y]), series([y, x]), false)
  // a dependent (ragged) nesting is not available at the rectangular product
  leqCheck("nesting ≰ product", series([x, y]), parallel([x, y]), false)
  // any subset of a product's axes is a sub-product, usable in the whole
  leqCheck("sub-product ≤ product", parallel([y, z]), parallel([x, y, z]), true)
  // the plain prefix rule survives as the all-Series special case
  leqCheck("prefix", a, series([a, y]), true)
  leqCheck("reflexive", parallel([x, y]), parallel([x, y]), true)

  // the depth-mismatched cross (stopwords × words-per-doc): Parallel(s, Series(d,w)),
  // a non-graded but series-parallel context — reusable at any traversal that
  // keeps d outside w, and only those.
  let stop = parallel([Axis("s"), series([Axis("d"), Axis("w")])])
  leqCheck("depth-mismatch ≤ d-outer traversal", stop, series([Axis("d"), Axis("s"), Axis("w")]), true)
  leqCheck("depth-mismatch ≰ w-before-d traversal", stop, series([Axis("w"), Axis("d"), Axis("s")]), false)
}

header("poset: merge (a combine's home is the EXACT constructed product)")
{
  open Poset
  let x = Axis("x")
  let y = Axis("y")
  let z = Axis("z")
  let w = Axis("w")
  let a = Axis("a")

  // comparable operands merge to the deeper one — no product needed
  switch merge(~products=[], a, series([a, y])) {
  | m if leq(series([a, y]), m) && leq(m, series([a, y])) => pass("merge comparable → deeper")
  | m => fail("merge comparable gave " ++ toString(m))
  }

  // two siblings whose EXACT product was constructed → that product
  let prodXY = parallel([x, y])
  switch merge(~products=[prodXY], x, y) {
  | m if leq(prodXY, m) && leq(m, prodXY) => pass("merge siblings → exact constructed product")
  | m => fail("merge siblings gave " ++ toString(m))
  }

  // two siblings with NO constructed product → Incomparable (the time-travel gap)
  switch merge(~products=[], x, y) {
  | exception Incomparable(_, _) => pass("merge siblings, no product → Incomparable (time travel)")
  | m => fail("merge without a product should raise, gave " ++ toString(m))
  }

  // a SUPERSET product does not host a smaller combine — a flat cross builds no
  // sub-product, so this is a completion gap, not a silent bind to {x,y,z}
  switch merge(~products=[parallel([x, y, z])], x, y) {
  | exception Incomparable(_, _) => pass("merge siblings, only a superset product → Incomparable (gap)")
  | m => fail("superset product should not host the {x,y} combine, gave " ++ toString(m))
  }

  // the ambiguous cross: two incomparable products both cover {x,y} and neither
  // IS {x,y} — exact-match refuses to silently pick; it is a time-travel program
  // for completion to make concrete compatibly with the rest of the program
  switch merge(~products=[parallel([x, y, z]), parallel([x, y, w])], x, y) {
  | exception Incomparable(_, _) =>
    pass("merge siblings, two covering supersets → Incomparable (no silent pick)")
  | m => fail("ambiguous cross should not silently pick, gave " ++ toString(m))
  }
}

// ============================================================================
// 15. The whole-table Cross emitter (product-flows-design.md, "Compile" and
//     "smallest first step" 2). The two-lists program compiled in BOTH orders:
//     one shared point-indexed table, built once in the Cross's stored
//     orientation, indexed by each consumer in its own order — the transpose is
//     free, and the user's `add` runs once. Validated against hand-built
//     tables, and a golden check pins add-once.
// ============================================================================

header("cross: the two-lists product, both orders, one shared table")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  // The Cross gives the {X, Y} combine a home (test 13b); its stored orientation
  // (left = x outer, right = y inner) is the table's build order.
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  // Order 1: collect x inner (holding y), y outer — per y, the list over x.
  let inner1 = Build.collect(b, ~flow=itX.flow, s.value)
  let out1 = Build.collect(b, ~flow=itY.flow, inner1.value)
  // Order 2: the transpose — collect y inner (holding x), x outer.
  let inner2 = Build.collect(b, ~flow=itY.flow, s.value)
  let out2 = Build.collect(b, ~flow=itX.flow, inner2.value)
  let p = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])

  // out1: grouped per y — [[1+10,2+10,3+10],[1+20,2+20,3+20]].
  expectOutput(
    p,
    "out1",
    array_([
      array_([int_(11), int_(12), int_(13)]),
      array_([int_(21), int_(22), int_(23)]),
    ]),
  )
  // out2: the transpose — grouped per x.
  expectOutput(
    p,
    "out2",
    array_([
      array_([int_(11), int_(21)]),
      array_([int_(12), int_(22)]),
      array_([int_(13), int_(23)]),
    ]),
  )

  // Golden: the user's add appears exactly once in a compiled output — the two
  // orders share the table rather than each recomputing the product.
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out1") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b")
      if n === 1 {
        pass("add's work appears once (both orders share the table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out1 to inspect for add-once")
    }
  | Error(ws) =>
    fail("product program failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

header("cross: a single-order product still compiles (the direct table read)")
{
  // Just one consumer chain — the table is built and read once. This is the
  // exact program test 13b only checked; now it compiles and runs.
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20), int_(30)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let out = Build.collect(b, ~flow=itY.flow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // per y: [1+y, 2+y]
  expectOutput(
    p,
    "out",
    array_([
      array_([int_(11), int_(12)]),
      array_([int_(21), int_(22)]),
      array_([int_(31), int_(32)]),
    ]),
  )
  // The standalone product prints and reparses (the `cross with` surface form).
  expectRoundTrip(p)
}

// 15b. The `cross with` text surface (ARCHITECTURE worklist item 3, parser
//      catch-up). A product program authored directly in text — the Cross node
//      is a standalone `~left ~> cross with ~right => ~flow` statement, and the
//      two axis flows are collected in either order. Text and handles build the
//      identical wiring, and the text compiles to the same shared-table output.
// ============================================================================

header("cross: the product authored in text (`cross with`), both orders")
{
  let src = `
add = js "(a, b) => a + b"
[1, 2, 3] -> open list => ~fx, ex
[10, 20] -> open list => ~fy, ey
~fx ~> cross with ~fy => ~fxy
ex, ey -> add => s
s -~> collect ~fx => inner1
inner1 -~> collect ~fy => out1
s -~> collect ~fy => inner2
inner2 -~> collect ~fx => out2
out out1
out out2
`
  let fromText = TextResolve.parseProgram(src)

  // The same program, built via handles (mirrors test 15's structure).
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let inner1 = Build.collect(b, ~flow=itX.flow, s.value)
  let out1 = Build.collect(b, ~flow=itY.flow, inner1.value)
  let inner2 = Build.collect(b, ~flow=itY.flow, s.value)
  let out2 = Build.collect(b, ~flow=itX.flow, inner2.value)
  let fromHandles = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])

  if Program.equal(fromText, fromHandles) {
    pass("text `cross with` and handles build identical wiring")
  } else {
    fail(
      "text vs handles wiring differs\n-- text --\n" ++
      Program.dump(fromText) ++
      "\n-- handles --\n" ++
      Program.dump(fromHandles),
    )
  }
  // out1: grouped per y — [[1+10,2+10,3+10],[1+20,2+20,3+20]].
  expectOutput(
    fromText,
    "out1",
    array_([array_([int_(11), int_(12), int_(13)]), array_([int_(21), int_(22), int_(23)])]),
  )
  // out2: the transpose — grouped per x.
  expectOutput(
    fromText,
    "out2",
    array_([array_([int_(11), int_(21)]), array_([int_(12), int_(22)]), array_([int_(13), int_(23)])]),
  )
  expectRoundTrip(fromText)
}

// 15d. The n-ary (rank-3) product (product-flows-design.md, "N-ary products: the
//      three-list example"). Three lists crossed side by side via nested binary
//      Crosses — `cross(cross(x, y), z)` — flatten to one flat axis set {X,Y,Z}.
//      A full consumer chain of three nested collects reads the shared cube in a
//      chosen order; the transpose to a different order reads the SAME cube (the
//      six orders are the S₃ orbit — "the table indexing generalises verbatim …
//      f run once per point regardless of how many of the six consumers traverse
//      in how many orders"). Validated against hand-built cubes and an
//      add-once golden, exactly like the two-axis test.
header("cross: the three-lists product (rank 3), two orders, one shared cube")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  // The stored orientation is the nesting tree left-to-right: cross(cross(x,y),z)
  // ⇒ axes [x, y, z]. Both sub-products ({X,Y} and {X,Y,Z}) are constructed.
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  // Order A (outer→inner = z, y, x): out[iz][iy][ix] = x + y + z.
  let a1 = Build.collect(b, ~flow=itX.flow, s.value)
  let a2 = Build.collect(b, ~flow=itY.flow, a1.value)
  let outA = Build.collect(b, ~flow=itZ.flow, a2.value)
  // Order B (outer→inner = x, y, z): the transpose — out[ix][iy][iz] = x + y + z.
  let b1 = Build.collect(b, ~flow=itZ.flow, s.value)
  let b2 = Build.collect(b, ~flow=itY.flow, b1.value)
  let outB = Build.collect(b, ~flow=itX.flow, b2.value)
  let p = Build.finish(b, ~outputs=[("outA", outA.value), ("outB", outB.value)])

  // outA: grouped z, then y, then x.
  expectOutput(
    p,
    "outA",
    array_([
      array_([array_([int_(111), int_(112), int_(113)]), array_([int_(121), int_(122), int_(123)])]),
      array_([array_([int_(211), int_(212), int_(213)]), array_([int_(221), int_(222), int_(223)])]),
    ]),
  )
  // outB: the transpose — grouped x, then y, then z. Same values, re-indexed.
  expectOutput(
    p,
    "outB",
    array_([
      array_([array_([int_(111), int_(211)]), array_([int_(121), int_(221)])]),
      array_([array_([int_(112), int_(212)]), array_([int_(122), int_(222)])]),
      array_([array_([int_(113), int_(213)]), array_([int_(123), int_(223)])]),
    ]),
  )

  // Golden: the user's f3 appears exactly once in a compiled output — both orders
  // share the one cube rather than each recomputing the rank-3 product.
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "outA") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b + c")
      if n === 1 {
        pass("f3's work appears once (both orders share the rank-3 cube)")
      } else {
        fail("expected f3 once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no outA to inspect for f3-once")
    }
  | Error(ws) =>
    fail("rank-3 product failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 15e. The rank-3 product authored directly in text: nested `cross with`
//      statements naming the intermediate {X,Y} product, then the full
//      {X,Y,Z}. Parses, checks, compiles via the whole-table (cube) emitter,
//      and round-trips — the two-axis `cross with` surface (15b) generalises to
//      nesting for free.
header("cross: the rank-3 product authored in text (nested `cross with`)")
{
  let src = `
f3 = js "(a, b, c) => a + b + c"
[1, 2] -> open list => ~fx, ex
[10, 20] -> open list => ~fy, ey
[100, 200] -> open list => ~fz, ez
~fx ~> cross with ~fy => ~fxy
~fxy ~> cross with ~fz => ~fxyz
ex, ey, ez -> f3 => s
s -~> collect ~fx => a1
a1 -~> collect ~fy => a2
a2 -~> collect ~fz => out
out out
`
  let p = TextResolve.parseProgram(src)
  // out[iz][iy][ix] = x + y + z (chain collects fx inner, fy mid, fz outer).
  expectOutput(
    p,
    "out",
    array_([
      array_([array_([int_(111), int_(112)]), array_([int_(121), int_(122)])]),
      array_([array_([int_(211), int_(212)]), array_([int_(221), int_(222)])]),
    ]),
  )
  expectRoundTrip(p)
}

// 15f. An under-covered rank-3 consumer: three lists combined, but only the
//      {X,Y} sub-product was crossed (never the full {X,Y,Z}). The combine
//      `f3(x, y, z)` demands a value per (x, y, z) — it demands the full product
//      exist — and it does not (product-flows-design.md, N-ary: "the combine is
//      ill-formed until a Cross supplies {X,Y,Z}"). checkAlignment now catches
//      this soundly with its FULL-SPAN re-verification: the {X,Y} pair has a home
//      but the whole value's span does not, so it witnesses `time-travel` (a
//      completable gap) at the Check level rather than admitting the first pair
//      and leaving Codegen to decline with a Todo. This is the poset round's
//      "checkAlignment does not yet re-verify the full span" note discharged; the
//      Codegen `underCoveredProduct` Todo remains as the backstop for the
//      partial/sub-product traversal (holding axes), a genuinely different shape.
header("cross: an under-covered rank-3 consumer is witnessed as time travel")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow) // only {X,Y} — no full product
  let i1 = Build.collect(b, ~flow=itX.flow, s.value)
  let i2 = Build.collect(b, ~flow=itY.flow, i1.value)
  let out = Build.collect(b, ~flow=itZ.flow, i2.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "time-travel") {
      pass("under-covered rank-3 consumer witnessed as time travel (full-span check)")
    } else {
      fail("expected a time-travel witness, got:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
    }
  | exception Codegen.Todo(m) => fail("expected a Check witness, got a Codegen Todo: " ++ m)
  | Ok(_) => fail("under-covered rank-3 consumer unexpectedly compiled")
  }
}

// 15g. The full-span check's sharpest case (product-flows-design.md, N-ary: "the
//      first place that 'if one exists' bites"). Two OVERLAPPING sub-products
//      were constructed — {X,Y} and {Y,Z} — so every adjacent pair of the combine
//      f3(x,y,z) is individually covered by SOME product, yet no single product
//      spans {X,Y,Z}. A first-pair-only check would admit this; the full-span
//      re-verification reaches the uncovered step (a value at {X,Y} combined with
//      a value at {Z}, with no constructed common superset) and witnesses time
//      travel. This is the poset's partiality — "no least upper bound ⇒ no context
//      to combine at" — delivered by the existing rule, exactly as the doc says.
header("cross: overlapping sub-products {X,Y} and {Y,Z} still leave the span uncovered")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  // Two overlapping sub-products; the full {X,Y,Z} was never constructed.
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=itY.flow, ~right=itZ.flow)
  let p = Build.finish(b, ~outputs=[("out", xs.value)])
  let ws = Check.check(p)
  if ws->Array.some(w => w.rule === "time-travel") {
    pass("overlapping sub-products do not host the full-span combine — still time travel")
  } else {
    fail(
      "expected the {X,Y,Z} span to stay time travel, got:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
}

// 15h. Reduce along an axis, fibered over the rest (product-flows-design.md,
//      "Registers over products" / the context model's "a collect over a crossed
//      axis reports {Y}"). A collect over ONE axis of a product, with the other
//      axis still standing: `collect ~fx` over the {X,Y}-spanning value yields
//      one list PER Y — a value that still varies with Y — which an ordinary
//      per-fiber computation consumes and a second collect gathers. The two
//      fiberings (reduce X holding Y, reduce Y holding X) are the two readings of
//      the ONE shared table, so the user's computation still runs once per point.
//      The reducer is deliberately non-commutative (join with "-") so the axis
//      order is observable in the result, per the doc's smallest-first-step 2.
header("cross: reduce along one axis, fibered over the other (both fiberings)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let sumL = Build.raw(b, "(l) => l.reduce((a, b) => a + b, 0)")
  let joinL = Build.raw(b, "(l) => l.join(\"-\")")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  // Fiber over Y: collect the X axis (holding y), reduce each column, gather.
  let colX = Build.collect(b, ~flow=itX.flow, s.value)
  let totX = Build.app(b, sumL.value, [colX.value])
  let outX = Build.collect(b, ~flow=itY.flow, totX.value)
  // Fiber over X: the transpose — collect the Y axis (holding x), join each row.
  let rowY = Build.collect(b, ~flow=itY.flow, s.value)
  let joinedY = Build.app(b, joinL.value, [rowY.value])
  let outY = Build.collect(b, ~flow=itX.flow, joinedY.value)
  let p = Build.finish(b, ~outputs=[("outX", outX.value), ("outY", outY.value)])

  // Per y: [1+y, 2+y, 3+y] summed — y=10 ⇒ 36, y=20 ⇒ 66.
  expectOutput(p, "outX", array_([int_(36), int_(66)]))
  // Per x: [x+10, x+20] joined — the non-commutative reducer pins the Y order.
  expectOutput(p, "outY", array_([str("11-21"), str("12-22"), str("13-23")]))

  // Golden: the user's add still appears once — the two fiberings index the one
  // shared table, exactly as the two full traversals do (test 15).
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "outX") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b,")
      if n === 1 {
        pass("add's work appears once (both fiberings share the table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no outX to inspect for add-once")
    }
  | Error(ws) =>
    fail("fibered product failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 15i. The same fibered reading authored in text — no new surface was needed,
//      the ordinary postfix chain expresses it: collect one axis, compute per
//      fiber, collect the other.
header("cross: the fibered reduce authored in text, round-trips")
{
  let src = `
add = js "(a, b) => a + b"
sum = js "(l) => l.reduce((a, b) => a + b, 0)"
[1, 2, 3] -> open list => ~fx, ex
[10, 20] -> open list => ~fy, ey
~fx ~> cross with ~fy => ~fxy
ex, ey -> add => s
s -~> collect ~fx => col
col -> sum => tot
tot -~> collect ~fy => out
out out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(36), int_(66)]))
  expectRoundTrip(p)
}

// 15l. The sub-product traversal: a rank-3 cube collected over TWO of its axes
//      with the third held. The fiber is still one axis, so the same machinery
//      carries it — the chain's two loops index the shared cube at their own
//      coordinates and the holding loop supplies the third. This is the shape
//      the `underCoveredProduct` backstop used to decline ("a covered span
//      collected over only SOME of its axes while holding the rest").
header("cross: a rank-3 cube collected over two axes, the third held")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let sum2 = Build.raw(b, "(m) => m.reduce((a, r) => a + r.reduce((u, v) => u + v, 0), 0)")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  // Collect X then Y — a per-z matrix — reduce it, then gather over z.
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let plane = Build.collect(b, ~flow=itY.flow, inner.value)
  let tot = Build.app(b, sum2.value, [plane.value])
  let out = Build.collect(b, ~flow=itZ.flow, tot.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // z=100: 111+112+121+122 = 466; z=200: 211+212+221+222 = 866.
  expectOutput(p, "out", array_([int_(466), int_(866)]))
}

// 15k. A REGISTER along one axis of a product, fibered over the other
//      (product-flows-design.md, "Registers over products", the finding: "for
//      each fixed y, run an ordinary register along the X-fiber; state does not
//      cross between different y's"). The Delay names its driving flow, so the
//      axis is the one it names; `final` is not a scalar but a Y-FLOW — rank
//      n−1, the reduced axis gone, the surviving axis still a flow — which the
//      second collect gathers. Both fiberings are drawn in one program: the same
//      register machinery, its surrounding context now the other axis. The
//      operator is non-commutative (a*2+b) so the within-fiber order is
//      observable, per the doc's smallest-first-step 2.
header("cross: a register folds along one axis, fibered over the other")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let mixF = Build.raw(b, "(a, b) => a * 2 + b")
  let zero = Build.lit(b, int_(0))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  // Along X, fibered over Y: one fold per column, `final` a Y-flow.
  let regX = Build.delay(b, ~flow=itX.flow, ~init=zero.value)
  let stepX = Build.app(b, mixF.value, [regX.prev, s.value])
  let wX = Build.writeBack(b, ~read=regX, ~step=stepX.value)
  let outX = Build.collect(b, ~flow=itY.flow, wX.final)
  // Along Y, fibered over X: the transpose fold, `final` an X-flow.
  let regY = Build.delay(b, ~flow=itY.flow, ~init=zero.value)
  let stepY = Build.app(b, mixF.value, [regY.prev, s.value])
  let wY = Build.writeBack(b, ~read=regY, ~step=stepY.value)
  let outY = Build.collect(b, ~flow=itX.flow, wY.final)
  let p = Build.finish(b, ~outputs=[("outX", outX.value), ("outY", outY.value)])

  // Along X at y=10: 0*2+11=11, 11*2+12=34, 34*2+13=81; at y=20: 21, 64, 151.
  expectOutput(p, "outX", array_([int_(81), int_(151)]))
  // Along Y at x=1: 0*2+11=11, 11*2+21=43; x=2: 12, 46; x=3: 13, 49.
  expectOutput(p, "outY", array_([int_(43), int_(46), int_(49)]))
}

// 15n. The RUNNING VIEW of a fibered register — scan along an axis
//      (product-flows-design.md, "The running view keeps the shape"): unlike
//      `final`, which drops the folded axis, the scan keeps the FULL product
//      shape (rank unchanged), the value at each point being the accumulation so
//      far along X *within that point's fiber*. A sibling collect over the
//      register's own driving flow re-runs the fold and pushes each running
//      value (emitRunningCollect), now placed at the fiber rather than at the
//      top level. Collecting `prev` gives the values BEFORE each element,
//      collecting the stepped value gives them AFTER — the same pair a register
//      over a list gives, one rank higher.
header("cross: the running view of a fibered register (scan along an axis)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let zero = Build.lit(b, int_(0))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let reg = Build.delay(b, ~flow=itX.flow, ~init=zero.value)
  let step = Build.app(b, addF.value, [reg.prev, s.value])
  let w = Build.writeBack(b, ~read=reg, ~step=step.value)
  // Before: collect `prev` along X, per fiber, then gather the fibers.
  let runBefore = Build.collect(b, ~flow=itX.flow, reg.prev)
  let outBefore = Build.collect(b, ~flow=itY.flow, runBefore.value)
  // After: collect the stepped value instead.
  let runAfter = Build.collect(b, ~flow=itX.flow, step.value)
  let outAfter = Build.collect(b, ~flow=itY.flow, runAfter.value)
  // And the reduce, for contrast: rank n−1, the folded axis gone.
  let outFinal = Build.collect(b, ~flow=itY.flow, w.final)
  let p = Build.finish(
    b,
    ~outputs=[("before", outBefore.value), ("after", outAfter.value), ("total", outFinal.value)],
  )

  // y=10: s = 11,12,13 ⇒ prefix values before each element 0, 11, 23.
  // y=20: s = 21,22,23 ⇒ 0, 21, 43.
  expectOutput(
    p,
    "before",
    array_([array_([int_(0), int_(11), int_(23)]), array_([int_(0), int_(21), int_(43)])]),
  )
  // The same fold read after each step.
  expectOutput(
    p,
    "after",
    array_([array_([int_(11), int_(23), int_(36)]), array_([int_(21), int_(43), int_(66)])]),
  )
  // The reduce: one total per fiber (rank 1, not 2).
  expectOutput(p, "total", array_([int_(36), int_(66)]))
}

// 15o. Full reduction as an AXIS PERMUTATION (product-flows-design.md's
//      smallest-first-step 4): reducing a product all the way down is two
//      registers composed — fold one axis, then fold the resulting lower-rank
//      flow — and *which axis first* is the permutation. For a commutative,
//      associative operator the two orders agree (the doc's "one order-free
//      exception": the operator's own law discharges the order demand); for a
//      non-commutative one they differ, which is why the axis must be named.
//      Nothing new in the compiler — a register whose step reads a fibered
//      register's `final` is an ordinary register over the surviving axis.
header("cross: full reduction is two registers — the axis order shows in the result")
{
  let mk = (op: string, init: JsAst.expr) => {
    let b = Build.make()
    let addF = Build.raw(b, "(a, b) => a + b")
    let opF = Build.raw(b, op)
    let seed = Build.lit(b, init)
    let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
    let ys = Build.lit(b, array_([int_(10), int_(20)]))
    let itX = Build.uncollectList(b, xs.value)
    let itY = Build.uncollectList(b, ys.value)
    let s = Build.app(b, addF.value, [itX.element, itY.element])
    let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
    // X first, then Y: fold each column, then fold the column results.
    let rX = Build.delay(b, ~flow=itX.flow, ~init=seed.value)
    let wX = Build.writeBack(b, ~read=rX, ~step=Build.app(b, opF.value, [rX.prev, s.value]).value)
    let rXY = Build.delay(b, ~flow=itY.flow, ~init=seed.value)
    let wXY = Build.writeBack(b, ~read=rXY, ~step=Build.app(b, opF.value, [rXY.prev, wX.final]).value)
    // Y first, then X: the other permutation.
    let rY = Build.delay(b, ~flow=itY.flow, ~init=seed.value)
    let wY = Build.writeBack(b, ~read=rY, ~step=Build.app(b, opF.value, [rY.prev, s.value]).value)
    let rYX = Build.delay(b, ~flow=itX.flow, ~init=seed.value)
    let wYX = Build.writeBack(b, ~read=rYX, ~step=Build.app(b, opF.value, [rYX.prev, wY.final]).value)
    Build.finish(b, ~outputs=[("xFirst", wXY.final), ("yFirst", wYX.final)])
  }

  // Commutative and associative: the two orders agree (1+2+3 = 6, over two y's
  // ⇒ 6+6 + 3*10 + 3*20 = 102 either way).
  let sums = mk("(a, b) => a + b", int_(0))
  expectOutput(sums, "xFirst", int_(102))
  expectOutput(sums, "yFirst", int_(102))

  // Non-commutative: the nesting order is visible in the result.
  let cats = mk("(a, b) => a + \"|\" + b", str(""))
  expectOutput(cats, "xFirst", str("||11|12|13||21|22|23"))
  expectOutput(cats, "yFirst", str("||11|21||12|22||13|23"))
}

// 15m. The boundary the fibered register does NOT cross: a register whose
//      driving flow is the PRODUCT itself (a grid) — "reduce the whole product
//      as one sequence", which the doc calls ill-formed for the ordinary reason
//      (no order exists), the remedy being "fold one axis, or Join first"
//      (product-flows-design.md; the commutative-monoid exception needs the
//      catalog row's commutativity flag, which does not exist yet). It is now
//      rejected BY THE RULE the doc names — Check's `order-demand` rule
//      (delay-ontology-design.md, "The order-demand check, named"): the driving
//      flow classifies as SURPLUS order (every axis order real, none
//      privileged), so the Delay's demand for *one* previous firing has no
//      answer. Before the rule landed the program was still rejected, but only
//      incidentally, through its step's combine (a `time-travel` witness) —
//      the right answer for the wrong reason. That witness still fires too (a
//      Cross OUTPUT port is not yet an axis set in the poset), so the assertion
//      is that the owed rule is AMONG the witnesses, not that it is alone.
header("cross: a register over the whole product is rejected by the order-demand rule")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let zero = Build.lit(b, int_(0))
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let prod = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let reg = Build.delay(b, ~flow=prod.flow, ~init=zero.value)
  let step = Build.app(b, addF.value, [reg.prev, s.value])
  let w = Build.writeBack(b, ~read=reg, ~step=step.value)
  let p = Build.finish(b, ~outputs=[("out", w.final)])
  switch Pipeline.compile(p) {
  | exception Codegen.Todo(m) => fail("expected an order-demand witness, got a Codegen Todo: " ++ m)
  | Ok(_) => fail("a whole-product register unexpectedly compiled")
  | Error(ws) =>
    if ws->Array.some(w => w.Check.rule === "order-demand") {
      pass("a whole-product register is witnessed by the order-demand rule (surplus order)")
    } else {
      fail(
        "expected an order-demand witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  }
  // And the same register with an AXIS named compiles (15k) — the remedy the
  // witness points at is a real program, not a dead end.
}

// 15j. The ≥2-AXIS FIBER: a rank-3 product collected over ONE axis leaves TWO
//      axes standing. The fiber is then a genuine product context, which no
//      linear path holds as a NESTING — but the placement question only needs
//      to know WHICH axes must be open, and the consuming chain supplies the
//      order it chose. So `Context.remainderPath` reports both surviving axes
//      (flattened in the combine's own operand order) and `Codegen.matchChain`
//      matches a structural path's flows as a SET, which is what its own
//      contract always said ("the shortest prefix of the chain that opens every
//      flow the path names"). The traversal itself was already k-general: index
//      the one shared cube at the held coordinates.
//
//      Here: reduce along X, fibered over {Y, Z}. For each (y, z) the X-fiber
//      [x + y + z for x in xs] is summed; then Y is collected, then Z. The
//      user's computation still runs once per point, out of the one cube.
header("cross: the two-axis fiber — reduce along X, fibered over {Y, Z}")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let sumL = Build.raw(b, "(l) => l.reduce((a, b) => a + b, 0)")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  // Collect X only: {Y, Z} survive — a product context, not a path.
  let col = Build.collect(b, ~flow=itX.flow, s.value)
  let tot = Build.app(b, sumL.value, [col.value])
  let mid = Build.collect(b, ~flow=itY.flow, tot.value)
  let out = Build.collect(b, ~flow=itZ.flow, mid.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("the two-axis fiber passes the implemented checks")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // fiber sums: (1+y+z) + (2+y+z) = 3 + 2y + 2z.
  //   z=100: y=10 -> 223, y=20 -> 243.   z=200: y=10 -> 423, y=20 -> 443.
  expectOutput(
    p,
    "out",
    array_([
      array_([int_(223), int_(243)]),
      array_([int_(423), int_(443)]),
    ]),
  )
}

// 15j2. Both two-axis fiberings of one rank-3 product, in ONE program: reduce
//       along X (fibered over {Y, Z}) and along Y (fibered over {X, Z}). They
//       read the SAME cube — the rank-3 analogue of 15h/15i's two readings, and
//       the golden below pins it: the user's computation still appears once, so
//       it runs once per point however many fiberings read it.
header("cross: both two-axis fiberings of one product share the one cube")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let sumL = Build.raw(b, "(l) => l.reduce((a, b) => a + b, 0)")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  // Fiber along X, gathered Y-then-Z.
  let colX = Build.collect(b, ~flow=itX.flow, s.value)
  let totX = Build.app(b, sumL.value, [colX.value])
  let midX = Build.collect(b, ~flow=itY.flow, totX.value)
  let outX = Build.collect(b, ~flow=itZ.flow, midX.value)
  // Fiber along Y, gathered Z-then-X.
  let colY = Build.collect(b, ~flow=itY.flow, s.value)
  let totY = Build.app(b, sumL.value, [colY.value])
  let midY = Build.collect(b, ~flow=itZ.flow, totY.value)
  let outY = Build.collect(b, ~flow=itX.flow, midY.value)
  let p = Build.finish(b, ~outputs=[("outX", outX.value), ("outY", outY.value)])
  // Along X: (1+y+z) + (2+y+z) = 3 + 2y + 2z, gathered [z][y].
  //   z=100: y=10 -> 223, y=20 -> 243.   z=200: y=10 -> 423, y=20 -> 443.
  expectOutput(
    p,
    "outX",
    array_([array_([int_(223), int_(243)]), array_([int_(423), int_(443)])]),
  )
  // Along Y: (x+10+z) + (x+20+z) = 2x + 2z + 30, gathered [x][z].
  //   x=1: z=100 -> 232, z=200 -> 432.   x=2: z=100 -> 234, z=200 -> 434.
  expectOutput(
    p,
    "outY",
    array_([array_([int_(232), int_(432)]), array_([int_(234), int_(434)])]),
  )
  // Golden: the per-point computation appears once — both fiberings index the
  // one shared cube (test 15h's add-once, at rank 3 with a wider fiber).
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "outX") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b + c")
      if n === 1 {
        pass("the per-point computation appears once (both fiberings share the cube)")
      } else {
        fail("expected the computation once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no outX to inspect for the shared-cube golden")
    }
  | Error(ws) =>
    fail("two-axis fibering failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 15j3. A REGISTER folding along one axis of a rank-3 product, fibered over the
//       other two — 15k's fibered register with a wider fiber. The step spans
//       the product, so `final` is a flow of rank n−2 rather than a scalar: one
//       accumulator per (y, z) point, state never crossing between fibers. A
//       non-commutative operator pins the within-fiber order.
header("cross: a register folding one axis of a rank-3 product (two-axis fiber)")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  // (acc, v) => acc * 2 + v — order-sensitive, so the fiber's traversal order
  // is observable in the value.
  let stepF = Build.raw(b, "(a, v) => a * 2 + v")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  let reg = Build.delay(b, ~flow=itX.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, stepF.value, [reg.prev, s.value])
  let w = Build.writeBack(b, ~read=reg, ~step=stepped.value)
  let mid = Build.collect(b, ~flow=itY.flow, w.final)
  let out = Build.collect(b, ~flow=itZ.flow, mid.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // Per (y, z) fiber over x = 1, 2: acc = ((0*2 + (1+y+z))*2 + (2+y+z)).
  //   z=100: y=10 -> (111)*2 + 112 = 334.  y=20 -> (121)*2 + 122 = 364.
  expectOutput(p, "out", array_([array_([int_(334), int_(364)])]))
}

// 15c. The `commute out of` text surface (ARCHITECTURE worklist item 3, parser
//      catch-up — the last of the standalone flow-combine forms). A commute
//      swaps a list opened inside an option's absent-or-present flow: the
//      two-port Commute node is a standalone `~inner ~> commute out of ~outer
//      => cN` statement, its swapped flows referenced as ~cN.outer / ~cN.inner.
//      Commute is representable-but-not-compilable (the poset round owns its
//      emitter), so this validates the surface by wiring identity, a clean
//      check, and the round-trip — not by evaluation.
// ============================================================================

header("commute: the swap authored in text (`commute out of`), round-trips")
{
  let src = `
[1, 2, 3] -> open list => ~xs, x
x -> open option in ~xs => ~opt, ov
~opt ~> commute out of ~xs => c
ov -~> collect ~c.inner -~> collect ~c.outer => out
out out
`
  let fromText = TextResolve.parseProgram(src)

  // The same program, built via handles.
  let b = Build.make()
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let opt = Build.uncollectOption(b, ~nesting=it.flow, it.element)
  let cm = Build.commute(b, ~outer=it.flow, ~inner=opt.flow)
  let lst = Build.collect(b, ~flow=cm.innerFlow, opt.element)
  let res = Build.collect(b, ~flow=cm.outerFlow, lst.value)
  let fromHandles = Build.finish(b, ~outputs=[("out", res.value)])

  if Program.equal(fromText, fromHandles) {
    pass("text `commute out of` and handles build identical wiring")
  } else {
    fail(
      "text vs handles wiring differs\n-- text --\n" ++
      Program.dump(fromText) ++
      "\n-- handles --\n" ++
      Program.dump(fromHandles),
    )
  }
  // The fully-collected commute passes the implemented checks (both swapped
  // flows are collected, so nothing is left flow-borne at the boundary).
  let ws = Check.check(fromText)
  if Array.length(ws) === 0 {
    pass("commute program passes the implemented checks")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // Representable and checkable, but this commute is over a genuine (dependent)
  // nesting — an option opened inside a list element — so it is the directed
  // SEQUENCE operation, whose short-circuiting output construction waits on
  // stream flows (lazy-stream-commute-design.md). Compile declines with a clean
  // Todo rather than a bad emit, which is what we assert here. The other
  // operation the word names — transpose over a crossed pair — compiles (15p).
  switch Pipeline.compile(fromText) {
  | exception Codegen.Todo(_) =>
    pass("commute over a non-product nesting declines to compile (the sequence operation)")
  | Ok(_) => fail("commute unexpectedly compiled — its emitter was Todo")
  | Error(ws) =>
    fail("commute program failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectRoundTrip(fromText)
}

// ============================================================================
// 15p. The TRANSPOSING commute: commute over a crossed pair
//      (product-flows-design.md, theorem 2 "commute is total on crossed pairs";
//      lazy-stream-commute-design.md's taxonomy row "Transpose", the lawful
//      exception to the same-kind commute otherwise declined on usefulness
//      grounds — "the decline applies exactly where the nesting is not a
//      product").
//
//      This is Option A's spelling made real: the Cross stores an orientation,
//      and the consumer that wants the other one reads through a Commute. Two
//      things fall out rather than being built:
//
//      - Transpose is a RE-READING, not a restructuring, so the commute's
//        output ports simply denote its operands swapped
//        (`Context.throughCommutes`); the transposed chain is then an ordinary
//        product chain in its own order, and every k! order already indexes the
//        one shared point-indexed table. So the emitter is unchanged, and the
//        `add` still runs once per point — pinned by the golden below.
//      - The two axes are nesting-adjacent BY the product (theorem 1,
//        rectangularity), which is the join-adjacency carve-out in `Check`:
//        their own exteriors are sibling, and the Cross is what makes them
//        adjacent.
// ============================================================================

header("commute over a crossed pair: transpose, re-reading the one shared table")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  // The product, stored oriented: x outer, y inner.
  let _ = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  // The stored reading, naming the axes directly: per x, the list over y.
  let inner1 = Build.collect(b, ~flow=itY.flow, s.value)
  let out1 = Build.collect(b, ~flow=itX.flow, inner1.value)
  // The transposed reading, through a Commute over the crossed pair. `c.outer`
  // is the ex-inner (y) now outermost; `c.inner` the ex-outer (x) now innermost.
  let cm = Build.commute(b, ~outer=itX.flow, ~inner=itY.flow)
  let inner2 = Build.collect(b, ~flow=cm.innerFlow, s.value)
  let out2 = Build.collect(b, ~flow=cm.outerFlow, inner2.value)
  let p = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])

  // out1: grouped per x — [[1+10,1+20],[2+10,2+20],[3+10,3+20]].
  expectOutput(
    p,
    "out1",
    array_([
      array_([int_(11), int_(21)]),
      array_([int_(12), int_(22)]),
      array_([int_(13), int_(23)]),
    ]),
  )
  // out2: the transpose read through the commute — grouped per y.
  expectOutput(
    p,
    "out2",
    array_([
      array_([int_(11), int_(12), int_(13)]),
      array_([int_(21), int_(22), int_(23)]),
    ]),
  )

  // The commute is nesting-adjacent by the product — no join-adjacency witness.
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("a commute over a crossed pair passes join-adjacency (the product makes it adjacent)")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }

  // Golden: the transposed reading costs nothing — it indexes the SAME table, so
  // the user's add still appears exactly once (theorem 2's "the same product read
  // the other way; nothing can fail" as an operational fact).
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out2") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b")
      if n === 1 {
        pass("the transposed reading shares the stored orientation's table (add once)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out2 to inspect for add-once")
    }
  | Error(ws) =>
    fail("transposing-commute program failed check:\n  " ++
    ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }

  expectRoundTrip(p)
}

header("commute at rank 3: swapping two axes the stored orientation puts apart")
{
  // In a cube stored x > y > z, X and Z are not neighbours — Y sits between them.
  // But a product has no "between": its axes are mutually order-free, so the swap
  // is lawful and the transposed chain is just another permutation indexing the
  // one cube. This is why `crossedPair` asks CONTAINMENT ("both axes of one
  // product") rather than the exact-span discipline a combine's home gets: a flat
  // three-way cross builds no {X, Z} sub-product, and it does not need to.
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100), int_(200)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let itZ = Build.uncollectList(b, zs.value)
  let s = Build.app(b, f3.value, [itX.element, itY.element, itZ.element])
  let cxy = Build.cross(b, ~left=itX.flow, ~right=itY.flow)
  let _ = Build.cross(b, ~left=cxy.flow, ~right=itZ.flow)
  // The stored reading, x > y > z.
  let a1 = Build.collect(b, ~flow=itZ.flow, s.value)
  let a2 = Build.collect(b, ~flow=itY.flow, a1.value)
  let outA = Build.collect(b, ~flow=itX.flow, a2.value)
  // The same reading with X and Z transposed: z > y > x, read through a commute
  // whose operands are the two non-neighbouring axes.
  let cm = Build.commute(b, ~outer=itX.flow, ~inner=itZ.flow)
  let b1 = Build.collect(b, ~flow=cm.innerFlow, s.value)
  let b2 = Build.collect(b, ~flow=itY.flow, b1.value)
  let outB = Build.collect(b, ~flow=cm.outerFlow, b2.value)
  let p = Build.finish(b, ~outputs=[("outA", outA.value), ("outB", outB.value)])

  // outA: grouped x, then y, then z.
  expectOutput(
    p,
    "outA",
    array_([
      array_([array_([int_(111), int_(211)]), array_([int_(121), int_(221)])]),
      array_([array_([int_(112), int_(212)]), array_([int_(122), int_(222)])]),
      array_([array_([int_(113), int_(213)]), array_([int_(123), int_(223)])]),
    ]),
  )
  // outB: grouped z, then y, then x — the same cube, indexed the other way.
  expectOutput(
    p,
    "outB",
    array_([
      array_([array_([int_(111), int_(112), int_(113)]), array_([int_(121), int_(122), int_(123)])]),
      array_([array_([int_(211), int_(212), int_(213)]), array_([int_(221), int_(222), int_(223)])]),
    ]),
  )

  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("a commute of two non-neighbouring axes of one cube checks clean")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "outB") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b + c")
      if n === 1 {
        pass("the rank-3 transpose shares the one cube (f3 once)")
      } else {
        fail("expected f3 once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no outB to inspect for f3-once")
    }
  | Error(ws) =>
    fail("rank-3 transposing commute failed check:\n  " ++
    ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectRoundTrip(p)
}

header("commute of two UNCROSSED siblings still witnesses (the carve-out is the Cross's)")
{
  // The same two top-level lists, the same Commute — but no Cross. Nothing makes
  // the two axes nesting-adjacent, so the swap has no pair to swap and the
  // join-adjacency rule reports it exactly as before. The carve-out above is
  // theorem 1 speaking (the product IS the adjacency), not the rule weakening.
  let b = Build.make()
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let cm = Build.commute(b, ~outer=itX.flow, ~inner=itY.flow)
  let inner = Build.collect(b, ~flow=cm.innerFlow, itX.element)
  let out = Build.collect(b, ~flow=cm.outerFlow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  let ws = Check.check(p)
  if ws->Array.some(w => w.rule === "join-adjacency") {
    pass("join-adjacency witness produced (two siblings with no product between them)")
  } else {
    fail(
      "expected a join-adjacency witness, got:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
}

// 15q. A product opened INSIDE an enclosing loop — the per-group cartesian
//      product. The two axes are derived from the SAME outer element, so they
//      share an exterior (`L > {X || Y}`, the poset Check test 13b already
//      admits) and neither varies with the other: mutually invariant, a lawful
//      Cross. Nothing about the compile changes except where it lives — the
//      shared table is built once per group inside the group loop, and the
//      consuming chain reads it there. This is the "cross of non-top-level axes"
//      half of ARCHITECTURE worklist item 8.
header("cross: a product opened inside an enclosing loop (the per-group product)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let bOf = Build.raw(b, "g => [[10, 20], [100]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let itG = Build.uncollectList(b, gs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let bv = Build.app(b, bOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let itB = Build.uncollectList(b, ~nesting=itG.flow, bv.value)
  let _ = Build.cross(b, ~left=itA.flow, ~right=itB.flow)
  let s = Build.app(b, addF.value, [itA.element, itB.element])
  let inner = Build.collect(b, ~flow=itA.flow, s.value) // per b: the list over a
  let mid = Build.collect(b, ~flow=itB.flow, inner.value) // the group's table
  let out = Build.collect(b, ~flow=itG.flow, mid.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // group 0: a=[1,2] × b=[10,20]; group 1: a=[3] × b=[100].
  expectOutput(
    p,
    "out",
    array_([
      array_([array_([int_(11), int_(12)]), array_([int_(21), int_(22)])]),
      array_([array_([int_(103)])]),
    ]),
  )
  expectRoundTrip(p)
}

// 10e. Completion of a per-group sibling combine — the nested counterpart of
//      test 10. The combine's axis SPAN names the enclosing loop too (`{G, A,
//      B}`), but G is not a sibling of A or B: it is the context both were
//      opened in. Completion crosses the span's sibling FRONTIER — the axes
//      that do not determine another axis in the span — so the inserted product
//      is `{A || B}` with exterior `L`, and the completed program is identical
//      to the hand-drawn 15q.
header("complete: a per-group sibling combine gets its product inserted, then compiles")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let bOf = Build.raw(b, "g => [[10, 20], [100]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let itG = Build.uncollectList(b, gs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let bv = Build.app(b, bOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let itB = Build.uncollectList(b, ~nesting=itG.flow, bv.value)
  // No hand-drawn Cross: the under-committed per-group time-travel program.
  let s = Build.app(b, addF.value, [itA.element, itB.element])
  let inner = Build.collect(b, ~flow=itA.flow, s.value)
  let mid = Build.collect(b, ~flow=itB.flow, inner.value)
  let out = Build.collect(b, ~flow=itG.flow, mid.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(
    p,
    "out",
    array_([
      array_([array_([int_(11), int_(12)]), array_([int_(21), int_(22)])]),
      array_([array_([int_(103)])]),
    ]),
  )
  switch Pipeline.compile(p) {
  | Ok({insertions}) =>
    if Array.length(insertions) === 1 {
      Console.log("insertion: " ++ (insertions->Array.getUnsafe(0)).description)
      pass("completion inserted one per-group product for the sibling combine")
    } else {
      fail("expected one inserted product, got " ++ Int.toString(Array.length(insertions)))
    }
  | Error(ws) =>
    fail("per-group sibling program failed to complete:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 10f. The guard on that frontier rule. Here one axis is top-level and the
//      other is opened inside a loop, so the span's dropped axis (the loop) is
//      an ancestor of ONE frontier member and not the other. Which nesting to
//      commit — `G > {X || A}` or `{G || X} > A` — is a genuine ambiguity, not
//      something this pass gets to settle by convenience, so it stays a
//      time-travel witness and asks for a hand-drawn Cross.
header("complete: an ancestor shared by only SOME frontier axes is not completed")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let xs = Build.lit(b, array_([int_(100), int_(200)]))
  let itG = Build.uncollectList(b, gs.value)
  let itX = Build.uncollectList(b, xs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let s = Build.app(b, addF.value, [itX.element, itA.element])
  let inner = Build.collect(b, ~flow=itA.flow, s.value)
  let mid = Build.collect(b, ~flow=itX.flow, inner.value)
  let out = Build.collect(b, ~flow=itG.flow, mid.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Ok(_) => fail("a partially-shared ancestor was completed — the frontier guard did not hold")
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "time-travel") {
      pass("a partially-shared ancestor stays a time-travel witness (needs a hand-drawn Cross)")
    } else {
      fail("expected a time-travel witness, got:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
    }
  | exception Codegen.Todo(m) => fail("expected a Check witness, got a Codegen Todo: " ++ m)
  }
}

// 15q2. The same per-group product read in BOTH orders. Everything the
//       top-level product's shared table gives (test 15) holds one layer in:
//       the two chains share one table per group, so the user's computation
//       still runs once per point — the add-once golden, now inside a loop.
header("cross: both orders of a per-group product share that group's one table")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let bOf = Build.raw(b, "g => [[10, 20], [100]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let itG = Build.uncollectList(b, gs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let bv = Build.app(b, bOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let itB = Build.uncollectList(b, ~nesting=itG.flow, bv.value)
  let _ = Build.cross(b, ~left=itA.flow, ~right=itB.flow)
  let s = Build.app(b, addF.value, [itA.element, itB.element])
  // Order 1: a inner (holding b), b outer.
  let i1 = Build.collect(b, ~flow=itA.flow, s.value)
  let m1 = Build.collect(b, ~flow=itB.flow, i1.value)
  let out1 = Build.collect(b, ~flow=itG.flow, m1.value)
  // Order 2: the transpose — b inner, a outer.
  let i2 = Build.collect(b, ~flow=itB.flow, s.value)
  let m2 = Build.collect(b, ~flow=itA.flow, i2.value)
  let out2 = Build.collect(b, ~flow=itG.flow, m2.value)
  let p = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])
  expectOutput(
    p,
    "out1",
    array_([
      array_([array_([int_(11), int_(12)]), array_([int_(21), int_(22)])]),
      array_([array_([int_(103)])]),
    ]),
  )
  expectOutput(
    p,
    "out2",
    array_([
      array_([array_([int_(11), int_(21)]), array_([int_(12), int_(22)])]),
      array_([array_([int_(103)])]),
    ]),
  )
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out1") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + bb")
      if n === 1 {
        pass("add's work appears once (both orders share the per-group table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out1 to inspect for add-once")
    }
  | Error(ws) =>
    fail("per-group product failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
}

// 15q3. A REGISTER folding along one axis of a per-group product — the fibered
//       register (test 15k) with the whole product one layer in. State never
//       crosses fibers OR groups: `final` is a B-flow within its group, and the
//       operator is non-commutative so the within-fiber order is observable.
header("cross: a register folds one axis of a per-group product, fibered over the other")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let mixF = Build.raw(b, "(a, bb) => a * 2 + bb")
  let zero = Build.lit(b, int_(0))
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let bOf = Build.raw(b, "g => [[10, 20], [100]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let itG = Build.uncollectList(b, gs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let bv = Build.app(b, bOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let itB = Build.uncollectList(b, ~nesting=itG.flow, bv.value)
  let _ = Build.cross(b, ~left=itA.flow, ~right=itB.flow)
  let s = Build.app(b, addF.value, [itA.element, itB.element])
  let reg = Build.delay(b, ~flow=itA.flow, ~init=zero.value)
  let step = Build.app(b, mixF.value, [reg.prev, s.value])
  let w = Build.writeBack(b, ~read=reg, ~step=step.value)
  let perB = Build.collect(b, ~flow=itB.flow, w.final)
  let out = Build.collect(b, ~flow=itG.flow, perB.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // g0,b=10: 0*2+11=11, 11*2+12=34. g0,b=20: 21, 21*2+22=64. g1,b=100: 103.
  expectOutput(p, "out", array_([array_([int_(34), int_(64)]), array_([int_(103)])]))
}

// 15q4. The FIBERED TRAVERSAL of a per-group product: collect only the A axis
//       while B is held, reduce each column, then gather. The held coordinate
//       now comes from a loop that is itself inside the group loop, and the
//       table it indexes is that group's — the partial-product matcher's
//       machinery unchanged, one layer in.
header("cross: a fibered traversal of a per-group product (reduce each column)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let sumF = Build.raw(b, "l => l.reduce((u, v) => u + v, 0)")
  let aOf = Build.raw(b, "g => [[1, 2], [3]][g]")
  let bOf = Build.raw(b, "g => [[10, 20], [100]][g]")
  let gs = Build.lit(b, array_([int_(0), int_(1)]))
  let itG = Build.uncollectList(b, gs.value)
  let av = Build.app(b, aOf.value, [itG.element])
  let bv = Build.app(b, bOf.value, [itG.element])
  let itA = Build.uncollectList(b, ~nesting=itG.flow, av.value)
  let itB = Build.uncollectList(b, ~nesting=itG.flow, bv.value)
  let _ = Build.cross(b, ~left=itA.flow, ~right=itB.flow)
  let s = Build.app(b, addF.value, [itA.element, itB.element])
  let col = Build.collect(b, ~flow=itA.flow, s.value) // one column per (group, b)
  let tot = Build.app(b, sumF.value, [col.value])
  let perB = Build.collect(b, ~flow=itB.flow, tot.value)
  let out = Build.collect(b, ~flow=itG.flow, perB.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  // g0: b=10 -> 11+12=23, b=20 -> 21+22=43. g1: b=100 -> 103.
  expectOutput(p, "out", array_([array_([int_(23), int_(43)]), array_([int_(103)])]))
}

// 15r. A FILTERED axis in a product — product-flows-design.md's first filtering
//      regime, "Partial products: filtering, in three regimes": *filter an axis
//      by its own element* (the predicate reads only x), so "the filtered flow's
//      shape is still invariant of ~x — the same rows survive for every x. Still
//      a product, still crossable, still transposable. Rectangular, just
//      smaller."
//
//      An axis is therefore not only a single list open: it may be a join CHAIN,
//      `join(list, case-alt)`, whose extent is the kept subsequence. The table is
//      built by walking that chain (one row per kept firing) and each consumer
//      traverses the axis by index over its kept COUNT, so both orders still read
//      the one shared table and the user's computation still runs once per point.
// ============================================================================

header("cross: a FILTERED axis, both orders, one shared table")
{
  let src = `
add = js "(a, b) => a + b"
parity = js "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}"
[1, 2, 3, 4] -> open list => ex, ~fx
ex -> split parity of Even, Odd => cs
~cs.Even ~> join into ~fx => ~kx
[10, 20] -> open list => ey, ~fy
~kx ~> cross with ~fy => ~fxy
cs.Even, ey -> add => s
s -~> collect ~kx => inner1
inner1 -~> collect ~fy => out1
s -~> collect ~fy => inner2
inner2 -~> collect ~kx => out2
out out1
out out2
`
  let fromText = TextResolve.parseProgram(src)

  // The same program via handles.
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let parity = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let itX = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, itX.element)
  let ev = Build.alt(cs, "Even")
  let kx = Build.join(b, ~outer=itX.flow, ~inner=ev.altFlow)
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=kx.flow, ~right=itY.flow)
  let s = Build.app(b, addF.value, [ev.altValue, itY.element])
  let inner1 = Build.collect(b, ~flow=kx.flow, s.value)
  let out1 = Build.collect(b, ~flow=itY.flow, inner1.value)
  let inner2 = Build.collect(b, ~flow=itY.flow, s.value)
  let out2 = Build.collect(b, ~flow=kx.flow, inner2.value)
  let fromHandles = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])

  if Program.equal(fromText, fromHandles) {
    pass("filtered-axis product: text and handles build identical wiring")
  } else {
    fail(
      "text vs handles wiring differs\n-- text --\n" ++
      Program.dump(fromText) ++
      "\n-- handles --\n" ++
      Program.dump(fromHandles),
    )
  }
  // The kept axis is [2, 4]; the table is 2x2 over ([2,4], [10,20]).
  // out1 groups per y: [[2+10, 4+10], [2+20, 4+20]].
  expectOutput(
    fromText,
    "out1",
    array_([array_([int_(12), int_(14)]), array_([int_(22), int_(24)])]),
  )
  // out2 is the transpose — grouped per kept x.
  expectOutput(
    fromText,
    "out2",
    array_([array_([int_(12), int_(22)]), array_([int_(14), int_(24)])]),
  )

  // Golden: the user's add still appears exactly once — filtering an axis
  // changes the table's extent, not the fact that there is one table.
  switch Pipeline.compile(fromText) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out1") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + b")
      if n === 1 {
        pass("add's work appears once (both orders share the filtered table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out1 to inspect for add-once")
    }
  | Error(ws) =>
    fail("filtered-axis product failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectRoundTrip(fromText)
}

// 15r2. BOTH axes filtered. The table build nests one chain inside the other,
//       and each axis's kept count is walked once and shared, so the two
//       traversal orders still index the one table. A non-commutative operator
//       pins which coordinate is which.
// ============================================================================

header("cross: both axes filtered — the rectangle is just smaller on both sides")
{
  let b = Build.make()
  let combine = Build.raw(b, "(a, bb) => a * 100 + bb")
  let even = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let odd = Build.raw(b, "y => y % 2 === 1 ? {tag: 'Odd', value: y} : {tag: 'Even', value: y}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let itX = Build.uncollectList(b, xs.value)
  let csX = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=even.value, itX.element)
  let evX = Build.alt(csX, "Even")
  let kx = Build.join(b, ~outer=itX.flow, ~inner=evX.altFlow)
  let ys = Build.lit(b, array_([int_(10), int_(11), int_(12), int_(13)]))
  let itY = Build.uncollectList(b, ys.value)
  let csY = Build.caseSplit(b, ~alts=["Odd", "Even"], ~discriminator=odd.value, itY.element)
  let oddY = Build.alt(csY, "Odd")
  let ky = Build.join(b, ~outer=itY.flow, ~inner=oddY.altFlow)
  let _ = Build.cross(b, ~left=kx.flow, ~right=ky.flow)
  let s = Build.app(b, combine.value, [evX.altValue, oddY.altValue])
  let inner1 = Build.collect(b, ~flow=kx.flow, s.value)
  let out1 = Build.collect(b, ~flow=ky.flow, inner1.value)
  let inner2 = Build.collect(b, ~flow=ky.flow, s.value)
  let out2 = Build.collect(b, ~flow=kx.flow, inner2.value)
  let p = Build.finish(b, ~outputs=[("out1", out1.value), ("out2", out2.value)])
  // kept x = [2, 4]; kept y = [11, 13]; s = x*100 + y.
  expectOutput(
    p,
    "out1", // per kept y: [x0, x1]
    array_([array_([int_(211), int_(411)]), array_([int_(213), int_(413)])]),
  )
  expectOutput(
    p,
    "out2", // the transpose: per kept x
    array_([array_([int_(211), int_(213)]), array_([int_(411), int_(413)])]),
  )
  expectRoundTrip(p)
}

// 15r3. The regime the product does NOT survive: a predicate that reads the
//       OTHER axis's element. product-flows-design.md's third regime — "shape
//       depends on the other flow's value … no product exists. This is true
//       raggedness; the nesting is dependent; one order is meaningful and the
//       transpose is not. An attempt to cross such flows … fails the invariance
//       demand, with the dependence-introducing node as the witness." Filtering
//       per POINT is a legitimate program (regime two), but it is authored by
//       absorbing the per-point option in each consumer chain, not by folding
//       the predicate into an axis, which is what this is.
// ============================================================================

header("cross: an axis filtered by the OTHER axis's element is not a product")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let disc = Build.raw(b, "n => n % 2 === 0 ? {tag: 'Even', value: n} : {tag: 'Odd', value: n}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  // The predicate reads BOTH elements: the surviving x's differ per y.
  let mixed = Build.app(b, addF.value, [itX.element, itY.element])
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=disc.value, mixed.value)
  let ev = Build.alt(cs, "Even")
  let kx = Build.join(b, ~outer=itX.flow, ~inner=ev.altFlow)
  let _ = Build.cross(b, ~left=kx.flow, ~right=itY.flow)
  let inner = Build.collect(b, ~flow=kx.flow, ev.altValue)
  let out = Build.collect(b, ~flow=itY.flow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.Check.rule === "invariance") {
      pass("a per-point-filtered axis is witnessed by the invariance rule, not crossed")
    } else {
      fail(
        "expected an invariance witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("expected the dependent filter to be witnessed, but it compiled")
  | exception Codegen.Todo(g) => fail("expected an invariance witness, got a codegen gap: " ++ g)
  }
}

// 15r4. The other thing an axis chain must not be: a REPEATED axis. Crossing X
//       with `join(X, Z)` reaches one axis through both operands, which is
//       `Poset.res`'s repeated-flow DIAMOND — "one axis reached by two
//       incomparable ancestry paths, left unresolved between ALIGN (zip) and
//       CROSS", the incoherent middle the checker witnesses rather than
//       represents. It is the invariance rule's second cell: not a dependent
//       nesting, but an operand pair that is not two axes at all.
// ============================================================================

header("cross: an operand that repeats the other's axis is witnessed, not crossed")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let inner = Build.raw(b, "n => [n, n + 1]")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let itX = Build.uncollectList(b, xs.value)
  let zsrc = Build.app(b, inner.value, [itX.element])
  let itZ = Build.uncollectList(b, ~nesting=itX.flow, zsrc.value)
  let jxz = Build.join(b, ~outer=itX.flow, ~inner=itZ.flow)
  let _ = Build.cross(b, ~left=itX.flow, ~right=jxz.flow)
  let s = Build.app(b, addF.value, [itX.element, itZ.element])
  let innerC = Build.collect(b, ~flow=jxz.flow, s.value)
  let out = Build.collect(b, ~flow=itX.flow, innerC.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.Check.rule === "invariance") {
      pass("a repeated axis is witnessed by the invariance rule")
    } else {
      fail(
        "expected an invariance witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("expected the repeated axis to be witnessed, but it compiled")
  | exception Codegen.Todo(g) => fail("expected an invariance witness, got a codegen gap: " ++ g)
  }
}

// 15r5. A filtered axis HELD while the other is collected — the FIBERED read
//       over a filtered axis. Holding an axis means having its coordinate, and
//       for a filtered axis that coordinate is not a loop index: it is the
//       running count of the firings that SURVIVED the chain, which is exactly
//       what the table build pushed its rows by. So the holding chain mints a
//       kept-firing counter and hands each kept firing `const i = c++`, and the
//       traversal nested inside indexes the shared table at it — the same read
//       the plain-axis fiber does (15h), over an axis that is "rectangular, just
//       smaller" (product-flows-design.md's first filtering regime). Both
//       fiberings are here, and they share the one table: hold the filtered axis
//       and collect the plain one, and the transpose.
// ============================================================================

header("cross: a FIBERED read over a filtered axis (both fiberings, one table)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let sumF = Build.raw(b, "l => l.reduce((u, v) => u + v, 0)")
  let joinF = Build.raw(b, "l => l.join(\"-\")")
  let parity = Build.raw(b, "x => x % 2 === 0 ? {tag: 'Even', value: x} : {tag: 'Odd', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3), int_(4)]))
  let itX = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Even", "Odd"], ~discriminator=parity.value, itX.element)
  let ev = Build.alt(cs, "Even")
  let kx = Build.join(b, ~outer=itX.flow, ~inner=ev.altFlow)
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=kx.flow, ~right=itY.flow)
  let s = Build.app(b, addF.value, [ev.altValue, itY.element])
  // Fiber over the FILTERED axis: hold each kept x, collect the Y axis, reduce.
  let row = Build.collect(b, ~flow=itY.flow, s.value) // one row per kept x
  let tot = Build.app(b, sumF.value, [row.value])
  let out = Build.collect(b, ~flow=kx.flow, tot.value)
  // The transpose: hold each y, collect the filtered X axis, join (a
  // non-commutative reducer, so the kept-x order is observable).
  let col = Build.collect(b, ~flow=kx.flow, s.value) // one column per y
  let joined = Build.app(b, joinF.value, [col.value])
  let outT = Build.collect(b, ~flow=itY.flow, joined.value)
  let p = Build.finish(b, ~outputs=[("out", out.value), ("outT", outT.value)])
  // kept x = [2, 4]; y = [10, 20]; s = x + y.
  // Per kept x: [x+10, x+20] summed — 2 ⇒ 34, 4 ⇒ 38.
  expectOutput(p, "out", array_([int_(34), int_(38)]))
  // Per y: the kept x's, in kept order — [2+y, 4+y] joined.
  expectOutput(p, "outT", array_([str("12-14"), str("22-24")]))

  // Golden: the user's add still appears once. Both fiberings — one holding the
  // filtered axis, one collecting it — read the one shared table, so the
  // computation still runs once per point of the smaller rectangle.
  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + bb")
      if n === 1 {
        pass("add's work appears once (both fiberings share the filtered table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out to inspect for add-once")
    }
  | Error(ws) =>
    fail(
      "the fibered filtered read failed check:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  | exception Codegen.Todo(g) => fail("the fibered filtered read declined: " ++ g)
  }
  expectRoundTrip(p)
}

// 15r6. The same sentence with no dispatch in it: a FLATTENED axis
//       (`join(list, list)` — a list of groups, iterated as one sequence) held
//       while the other axis is collected. A chain axis's coordinate is the count
//       of the firings it produces, whether a dispatch dropped some of them or a
//       flatten multiplied them, so the flattened fiber is the filtered one with
//       the guard removed. Both fiberings again, over the one shared table.
// ============================================================================

header("cross: a FIBERED read over a FLATTENED axis (both fiberings, one table)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, bb) => a + bb")
  let sumF = Build.raw(b, "l => l.reduce((u, v) => u + v, 0)")
  let joinF = Build.raw(b, "l => l.join(\"-\")")
  let groups = Build.lit(b, array_([array_([int_(1), int_(2)]), array_([int_(3)])]))
  let itG = Build.uncollectList(b, groups.value)
  let itX = Build.uncollectList(b, itG.element)
  let fx = Build.join(b, ~outer=itG.flow, ~inner=itX.flow) // firings: 1, 2, 3
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itY = Build.uncollectList(b, ys.value)
  let _ = Build.cross(b, ~left=fx.flow, ~right=itY.flow)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  // Fiber over the flattened axis: hold each firing, collect Y, reduce.
  let row = Build.collect(b, ~flow=itY.flow, s.value)
  let tot = Build.app(b, sumF.value, [row.value])
  let out = Build.collect(b, ~flow=fx.flow, tot.value)
  // The transpose: hold each y, collect the flattened axis, join.
  let col = Build.collect(b, ~flow=fx.flow, s.value)
  let joined = Build.app(b, joinF.value, [col.value])
  let outT = Build.collect(b, ~flow=itY.flow, joined.value)
  let p = Build.finish(b, ~outputs=[("out", out.value), ("outT", outT.value)])
  // The flattened order is 1, 2, 3 — the groups are gone, one axis remains.
  expectOutput(p, "out", array_([int_(32), int_(34), int_(36)]))
  expectOutput(p, "outT", array_([str("11-12-13"), str("21-22-23")]))

  switch Pipeline.compile(p) {
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === "out") {
    | Some(o) =>
      let n = countOccurrences(o.js, "a + bb")
      if n === 1 {
        pass("add's work appears once (both fiberings share the flattened table)")
      } else {
        fail("expected add once, found " ++ Int.toString(n) ++ " occurrences")
      }
    | None => fail("no out to inspect for add-once")
    }
  | Error(ws) =>
    fail(
      "the fibered flattened read failed check:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  | exception Codegen.Todo(g) => fail("the fibered flattened read declined: " ++ g)
  }
  expectRoundTrip(p)
}

// ============================================================================
// Coverage ported from the previous compiler's value-test suite. These exercise
// distinct compiler behaviours the sections above do not: value-fragment
// variety (object build, field access, zero-arg, ternary), multi-output and
// cross-branch value sharing, loop-invariant placement, plain nested collects
// (collect-of-collect, no join), deeper join flattening, option-of-option and
// option-of-list nestings, and nested case dispatch. Each is validated against
// an author-written expected value, like the sections above.
// ============================================================================

header("value fragment: object build, field access, zero-arg, ternary (ported)")
{
  let b = Build.make()
  let makePoint = Build.raw(b, "(x, y) => ({x: x, y: y})")
  let getX = Build.raw(b, "p => p.x")
  let addF = Build.raw(b, "(a, b) => a + b")
  let minF = Build.raw(b, "(a, b) => a < b ? a : b")
  let const42 = Build.raw(b, "() => 42")
  let one = Build.lit(b, int_(1))
  let two = Build.lit(b, int_(2))
  let three = Build.lit(b, int_(3))
  let four = Build.lit(b, int_(4))
  let seven = Build.lit(b, int_(7))
  let ten = Build.lit(b, int_(10))
  // getX(makePoint(1 + 2, 3 + 4)) = 3 — object construction then field access.
  let pt = Build.app(
    b,
    makePoint.value,
    [Build.app(b, addF.value, [one.value, two.value]).value, Build.app(b, addF.value, [three.value, four.value]).value],
  )
  let px = Build.app(b, getX.value, [pt.value])
  // minOfTwo(minOfTwo(7, 4), 10) = 4 — a ternary extern, nested (`four` shared).
  let m = Build.app(b, minF.value, [Build.app(b, minF.value, [seven.value, four.value]).value, ten.value])
  // A zero-argument call.
  let z = Build.app(b, const42.value, [])
  let p = Build.finish(b, ~outputs=[("px", px.value), ("m", m.value), ("z", z.value)])
  expectOutput(p, "px", int_(3))
  expectOutput(p, "m", int_(4))
  expectOutput(p, "z", int_(42))
}

header("value fragment: two outputs share pi and r (multi-output memo)")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let pi = Build.lit(b, member(id("Math"), "PI"))
  let r = Build.lit(b, int_(3))
  let two = Build.lit(b, int_(2))
  let rsq = Build.app(b, mulF.value, [r.value, r.value])
  let area = Build.app(b, mulF.value, [pi.value, rsq.value])
  let twoPi = Build.app(b, mulF.value, [two.value, pi.value])
  let circ = Build.app(b, mulF.value, [twoPi.value, r.value])
  let p = Build.finish(b, ~outputs=[("area", area.value), ("circ", circ.value)])
  // pi and r are each one shared Lit feeding both outputs' subtrees.
  expectOutput(p, "area", mul(member(id("Math"), "PI"), int_(9)))
  expectOutput(p, "circ", mul(mul(int_(2), member(id("Math"), "PI")), int_(3)))
}

header("value fragment: deep diamond — one leaf feeds three consumers")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let plusOne = Build.raw(b, "a => a + 1")
  let timesTwo = Build.raw(b, "a => a * 2")
  let combine = Build.raw(b, "(a, b, c) => a + b + c")
  let leaf = Build.app(b, mulF.value, [Build.lit(b, int_(2)).value, Build.lit(b, int_(3)).value]) // 6, once
  let out = Build.app(
    b,
    combine.value,
    [leaf.value, Build.app(b, plusOne.value, [leaf.value]).value, Build.app(b, timesTwo.value, [leaf.value]).value],
  )
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", int_(25)) // 6 + (6 + 1) + (6 * 2)
}

header("list iter: a constant shared inside and outside the loop (placement)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let bundle = Build.raw(b, "(base, m) => ({base: base, m: m})")
  let k = Build.lit(b, int_(100))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let mapped = Build.collect(b, ~flow=it.flow, Build.app(b, addF.value, [k.value, it.element]).value)
  // k is used both inside the loop body (per element) and outside (paired with
  // the result): one binding, both uses reference it — no recomputation.
  let out = Build.app(b, bundle.value, [k.value, mapped.value])
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", obj([("base", int_(100)), ("m", array_([int_(101), int_(102), int_(103)]))]))
}

header("list iter: post-process the collected result (length of a mapped list)")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let lengthOf = Build.raw(b, "a => a.length")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([int_(5), int_(10), int_(15), int_(20)]))
  let it = Build.uncollectList(b, xs.value)
  let mapped = Build.collect(b, ~flow=it.flow, Build.app(b, mulF.value, [it.element, two.value]).value)
  let out = Build.app(b, lengthOf.value, [mapped.value]) // a collect's output as an ordinary value
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", int_(4))
}

header("list iter: empty input yields an empty list")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([]))
  let it = Build.uncollectList(b, xs.value)
  let out = Build.collect(b, ~flow=it.flow, Build.app(b, mulF.value, [it.element, two.value]).value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", array_([]))
}

header("multi-close: a shared per-iter intermediate, one branch used twice")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let addF = Build.raw(b, "(a, b) => a + b")
  let bundle = Build.raw(b, "(a, b, c) => ({a: a, b: b, c: c})")
  let one = Build.lit(b, int_(1))
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let square = Build.app(b, mulF.value, [it.element, it.element]) // computed once per iter
  let c1 = Build.collect(b, ~flow=it.flow, Build.app(b, addF.value, [square.value, one.value]).value)
  let c2 = Build.collect(b, ~flow=it.flow, Build.app(b, mulF.value, [square.value, two.value]).value)
  let out = Build.app(b, bundle.value, [c1.value, c1.value, c2.value]) // c1 twice downstream
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(
    p,
    "out",
    obj([
      ("a", array_([int_(2), int_(5), int_(10)])),
      ("b", array_([int_(2), int_(5), int_(10)])),
      ("c", array_([int_(2), int_(8), int_(18)])),
    ]),
  )
}

header("nested list: plain map over a list of lists (collect-of-collect, no join)")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([array_([int_(1), int_(2)]), array_([]), array_([int_(3)])]))
  let outer = Build.uncollectList(b, xs.value)
  let inner = Build.uncollectList(b, ~nesting=outer.flow, outer.element)
  let innerList = Build.collect(b, ~flow=inner.flow, Build.app(b, mulF.value, [inner.element, two.value]).value)
  // The outer collect's per-element value is itself an inner list — the result
  // stays a list of lists (an empty inner list among non-empty ones).
  let out = Build.collect(b, ~flow=outer.flow, innerList.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", array_([array_([int_(2), int_(4)]), array_([]), array_([int_(6)])]))
}

header("join x2: two-level flatten of a list of lists of lists")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(
    b,
    array_([
      array_([array_([int_(1), int_(2)]), array_([int_(3)])]),
      array_([array_([int_(4)])]),
    ]),
  )
  let i1 = Build.uncollectList(b, xs.value)
  let i2 = Build.uncollectList(b, i1.element)
  let i3 = Build.uncollectList(b, i2.element)
  let doubled = Build.app(b, mulF.value, [i3.element, two.value])
  let j1 = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let j2 = Build.join(b, ~outer=j1.flow, ~inner=i3.flow)
  let out = Build.collect(b, ~flow=j2.flow, doubled.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", array_([int_(2), int_(4), int_(6), int_(8)]))
}

header("option of option: Some(Some(5)) flattened and doubled -> 10")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let five = Build.lit(b, int_(5)) // Some(Some(5)) encodes as 5 (undefined = None)
  let i1 = Build.uncollectOption(b, five.value)
  let i2 = Build.uncollectOption(b, i1.element)
  let doubled = Build.app(b, mulF.value, [i2.element, two.value])
  let j = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let out = Build.collect(b, ~flow=j.flow, doubled.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", int_(10)) // all-option chain -> option output (present)
}

header("option of list: Some([1,2,3]) flattened and doubled -> [2,4,6]")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let two = Build.lit(b, int_(2))
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)])) // the Some payload is a list
  let i1 = Build.uncollectOption(b, xs.value)
  let i2 = Build.uncollectList(b, i1.element)
  let doubled = Build.app(b, mulF.value, [i2.element, two.value])
  let j = Build.join(b, ~outer=i1.flow, ~inner=i2.flow)
  let out = Build.collect(b, ~flow=j.flow, doubled.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", array_([int_(2), int_(4), int_(6)])) // any-list rule -> list output
}

header("nested case: Maybe<Either<string,int>> — Just(Right(7)) -> 14")
{
  let b = Build.make()
  let mulF = Build.raw(b, "(a, b) => a * b")
  let lengthOf = Build.raw(b, "s => s.length")
  let outerDisc = Build.raw(b, "x => x === undefined ? {tag: 'Nothing'} : {tag: 'Just', value: x}")
  let innerDisc = Build.raw(
    b,
    "e => e.side === 'L' ? {tag: 'Left', value: e.val} : {tag: 'Right', value: e.val}",
  )
  let two = Build.lit(b, int_(2))
  let zero = Build.lit(b, int_(0))
  let input = Build.lit(b, obj([("side", str("R")), ("val", int_(7))])) // Just(Right(7))
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=outerDisc.value, input.value)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  let inner = Build.caseSplit(
    b,
    ~alts=["Left", "Right"],
    ~discriminator=innerDisc.value,
    ~nesting=just.altFlow,
    just.altValue,
  )
  let left = Build.alt(inner, "Left")
  let right = Build.alt(inner, "Right")
  let innerCollect = Build.collectCases(
    b,
    [
      (left.altFlow, Build.app(b, lengthOf.value, [left.altValue]).value),
      (right.altFlow, Build.app(b, mulF.value, [right.altValue, two.value]).value),
    ],
  )
  let out = Build.collectCases(b, [(just.altFlow, innerCollect.value), (nothing.altFlow, zero.value)])
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", int_(14)) // Right(7) * 2
}

header("case split: a value shared across both branches (placement)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(b, "x => x === undefined ? {tag: 'Nothing'} : {tag: 'Just', value: x}")
  let input = Build.lit(b, int_(42)) // Just(42)
  let bonus = Build.app(b, addF.value, [Build.lit(b, int_(10)).value, Build.lit(b, int_(5)).value]) // 15, shared
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, input.value)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  let out = Build.collectCases(
    b,
    [
      (just.altFlow, Build.app(b, addF.value, [just.altValue, bonus.value]).value),
      (nothing.altFlow, bonus.value),
    ],
  )
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", int_(57)) // 42 + 15; bonus bound once, used in both alts
}

// ============================================================================
// 16. Aggregate / Disaggregate — struct construction and field projection
//     (visual-language-spec.md, "Aggregate" / "Disaggregate"). Pure value
//     nodes: Aggregate builds an object literal from named field wires,
//     Disaggregate projects one value port per field. Authored via handles
//     (no textual surface yet). These are the value fragment, not the poset
//     round — they compile the same way an App does (memoised lazy cell,
//     let-floated to where the fields jointly live).
// ============================================================================

header("aggregate: build a struct, project a field, output the whole struct")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let one = Build.lit(b, int_(1))
  let two = Build.lit(b, int_(2))
  let three = Build.lit(b, int_(3))
  let four = Build.lit(b, int_(4))
  // pt = {x: 1 + 2, y: 3 + 4} = {x: 3, y: 7}
  let pt = Build.aggregate(
    b,
    ~fields=[
      ("x", Build.app(b, addF.value, [one.value, two.value]).value),
      ("y", Build.app(b, addF.value, [three.value, four.value]).value),
    ],
  )
  // Project x and y off one Disaggregate node.
  let d = Build.disaggregate(b, ~fields=["x", "y"], pt.value)
  // sum = pt.x + pt.y = 10 — both projections feed one App.
  let sum = Build.app(b, addF.value, [Build.field(d, "x"), Build.field(d, "y")])
  let p = Build.finish(
    b,
    ~outputs=[("pt", pt.value), ("x", Build.field(d, "x")), ("sum", sum.value)],
  )
  expectOutput(p, "pt", obj([("x", int_(3)), ("y", int_(7))]))
  expectOutput(p, "x", int_(3))
  expectOutput(p, "sum", int_(10))
  expectRoundTrip(p)
}

header("aggregate: a per-element struct across a list collect (placement inside the loop)")
{
  let b = Build.make()
  let mul = Build.raw(b, "(a, b) => a * b")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  // Per element x: {v: x, sq: x * x}. The struct varies with the element, so it
  // must be emitted INSIDE the loop body (let-floating places it there).
  let sq = Build.app(b, mul.value, [it.element, it.element])
  let rec_ = Build.aggregate(b, ~fields=[("v", it.element), ("sq", sq.value)])
  let out = Build.collect(b, ~flow=it.flow, rec_.value)
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(
    p,
    "out",
    array_([
      obj([("v", int_(1)), ("sq", int_(1))]),
      obj([("v", int_(2)), ("sq", int_(4))]),
      obj([("v", int_(3)), ("sq", int_(9))]),
    ]),
  )
  expectRoundTrip(p)
}

header("disaggregate: project a per-element field, then collect")
{
  let b = Build.make()
  // A list of structs, projected per element down to one field, collected back.
  let structs = Build.lit(
    b,
    array_([
      obj([("x", int_(10)), ("y", int_(1))]),
      obj([("x", int_(20)), ("y", int_(2))]),
      obj([("x", int_(30)), ("y", int_(3))]),
    ]),
  )
  let it = Build.uncollectList(b, structs.value)
  let d = Build.disaggregate(b, ~fields=["x", "y"], it.element)
  let out = Build.collect(b, ~flow=it.flow, Build.field(d, "x"))
  let p = Build.finish(b, ~outputs=[("out", out.value)])
  expectOutput(p, "out", array_([int_(10), int_(20), int_(30)]))
  // No round-trip here: the SOURCE is an array of object literals, and the text
  // grammar has no object-literal leaf term, so the printer sends it through the
  // `js "..."` escape hatch and it reparses as an ERaw. That is the literal
  // renderer's own recorded limitation (TextPrint.litText), not the struct
  // surface's — the disaggregate statement itself round-trips in the tests below.
}

header("aggregate then disaggregate is identity (project both fields back out)")
{
  let b = Build.make()
  let seven = Build.lit(b, int_(7))
  let nine = Build.lit(b, int_(9))
  let s = Build.aggregate(b, ~fields=[("a", seven.value), ("b", nine.value)])
  let d = Build.disaggregate(b, ~fields=["a", "b"], s.value)
  let p = Build.finish(b, ~outputs=[("a", Build.field(d, "a")), ("b", Build.field(d, "b"))])
  expectOutput(p, "a", int_(7))
  expectOutput(p, "b", int_(9))
  expectRoundTrip(p)
}

// The struct surface authored in TEXT (textual-representation-design.md's
// grammar grown by two stages). `aggregate` mirrors an application — the
// chain's sources, in order, are the field values — and `disaggregate` mirrors
// `split`: a multi-output node named once, its fields reached by projection off
// that name. That symmetry is the whole design: nothing new to learn beyond the
// two words, and the printer's existing node-naming machinery already knew how
// to render a projected node.
header("struct: aggregate and disaggregate authored in text, round-tripped")
{
  let src = `
add = js "(a, b) => a + b"
one = 1
two = 2
three = 3
four = 4
one, two -> add => xv
three, four -> add => yv
xv, yv -> aggregate x, y => pt
pt -> disaggregate x, y => d
d.x, d.y -> add => total
out pt
out total
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "pt", obj([("x", int_(3)), ("y", int_(7))]))
  expectOutput(p, "total", int_(10))
  expectRoundTrip(p)
}

header("struct: a per-element struct built and projected inside a loop, in text")
{
  let src = `
mul = js "(a, b) => a * b"
xs = [1, 2, 3]
xs -> open list => e, ~L
e, e -> mul => sq
e, sq -> aggregate v, sq => rec
rec -> disaggregate v, sq => d
d.sq -~> collect ~L => out
out out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(1), int_(4), int_(9)]))
  expectRoundTrip(p)
}

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
