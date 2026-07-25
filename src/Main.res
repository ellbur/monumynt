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
//     compiles it (emitFilterCollect loops its leading list levels), but the
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
//     no-leading-level (option accumulator) path of emitPartialCollect.
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
//     the dispatch-leading-level shape, mirroring emitFilterCollect's level walk.
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
// 8j. The FILTERED running view — a sibling collect reads `prev` over a filtered
//     (case-alt) driving flow — is well-formed (passes Check) but the emitter is
//     the shared-loop-skeleton case, deferred with the rest of the running-view
//     work. It must decline with a clean Codegen.Todo, not a raw failwith crash
//     (the error-discipline fix: a well-formed program never crashes the
//     compiler). ARCHITECTURE worklist item 6.
// ============================================================================

header("register pair: a filtered running view declines cleanly (Todo, not a crash)")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let disc = Build.raw(b, "x => x > 0 ? {tag: 'Keep', value: x} : {tag: 'Drop', value: x}")
  let xs = Build.lit(b, array_([int_(1), int_(-2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let cs = Build.caseSplit(b, ~alts=["Keep", "Drop"], ~discriminator=disc.value, ~nesting=it.flow, it.element)
  let keep = Build.alt(cs, "Keep")
  let filtered = Build.join(b, ~outer=it.flow, ~inner=keep.altFlow)
  let sum = Build.delay(b, ~flow=filtered.flow, ~init=Build.lit(b, int_(0)).value)
  let stepped = Build.app(b, addF.value, [sum.prev, keep.altValue])
  let w = Build.writeBack(b, ~read=sum, ~step=stepped.value)
  // A sibling collect over the SAME filtered flow reads prev.
  let running = Build.collect(b, ~flow=filtered.flow, sum.prev)
  let p = Build.finish(b, ~outputs=[("running", running.value), ("total", w.final)])
  let ws = Check.check(p)
  if Array.length(ws) === 0 {
    pass("filtered running view passes the implemented checks (well-formed)")
  } else {
    fail("unexpected witnesses:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  switch Pipeline.compile(p) {
  | exception Codegen.Todo(_) => pass("filtered running view declines with a clean Todo (not a crash)")
  | Ok(_) => fail("filtered running view unexpectedly compiled — its emitter is deferred")
  | Error(ws) =>
    fail("filtered running view failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  // (No round-trip: the text surface for a nested case split in a chain is a
  // known TextPrint gap, shared with the filtered register tests 8e–8g.)
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

// 15j. The fiber that is still deferred: a rank-3 product collected over ONE
//      axis leaves TWO axes standing, and a two-axis fiber is a genuine product
//      context — no linear path holds it, so `Context.valueContext` keeps
//      reporting the exterior and Codegen declines with a clean Todo rather than
//      mis-placing the consumer. This is the remaining half of the poset round's
//      context model (the general poset-valued context); the one-axis fiber above
//      is what the linear report can carry exactly.
header("cross: a two-axis fiber (rank 3, one axis collected) still declines cleanly")
{
  let b = Build.make()
  let f3 = Build.raw(b, "(a, b, c) => a + b + c")
  let sumL = Build.raw(b, "(l) => l.reduce((a, b) => a + b, 0)")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let zs = Build.lit(b, array_([int_(100)]))
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
  switch Pipeline.compile(p) {
  | exception Codegen.Todo(_) => pass("a two-axis fiber declines with a clean Todo (poset round)")
  | Ok(_) => fail("a two-axis fiber unexpectedly compiled")
  | Error(ws) =>
    fail(
      "expected a Codegen Todo, got witnesses:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
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
  // Representable and checkable, but the commute emitter is still Todo — the
  // poset round owns it. Compile declines with a clean Todo rather than a bad
  // emit, which is what we assert here.
  switch Pipeline.compile(fromText) {
  | exception Codegen.Todo(_) => pass("commute declines to compile (poset round owns the emitter)")
  | Ok(_) => fail("commute unexpectedly compiled — its emitter was Todo")
  | Error(ws) =>
    fail("commute program failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectRoundTrip(fromText)
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
