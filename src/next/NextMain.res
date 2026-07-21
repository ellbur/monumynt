// Smoke tests / playground for the next-generation scaffolding.
//
//   npm run next          (build first: npm run build)
//
// Deliberately narrative rather than exhaustive: each test prints the
// textual form and the generated JS so the pieces can be *seen* working
// together. The legacy suite (src/Main.res, `npm start`) remains the
// semantic regression net for the compiler the bridge reuses.

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

let engineLabel = (e: Pipeline.engine): string =>
  switch e {
  | NextCodegen => "next codegen"
  | Bridge => "legacy bridge"
  }

// The differential check: whenever the new codegen compiled an output, the
// bridge (the legacy compiler, i.e. the rebuild's spec) must agree on the
// eval'd value — if the bridge can compile the program at all. This runs
// automatically from expectOutput, so every emitter that lands in
// Codegen.res is verified against the legacy shapes without new tests.
let differential = (p: Program.program, name: string, codegenValue: string): unit =>
  switch Pipeline.compileVia(Bridge, p) {
  | exception Failure(_) => () // the bridge can't express it; nothing to compare
  | Error(_) => ()
  | Ok({outputs}) =>
    switch outputs->Array.find(o => o.outputName === name) {
    | None => ()
    | Some(bo) => {
        let bridgeValue = jsonStringify(evalExpression(bo.js))
        if bridgeValue === codegenValue {
          pass("differential: codegen ≡ bridge for " ++ name)
        } else {
          fail(
            "differential: engines disagree on " ++
            name ++
            ": codegen " ++
            codegenValue ++
            ", bridge " ++ bridgeValue,
          )
        }
      }
    }
  }

// Compile one named output and compare its eval'd value against expected JS.
let expectOutput = (p: Program.program, name: string, expected: JsAst.expr): unit =>
  switch Pipeline.compile(p) {
  | Error(ws) =>
    fail(
      "expected output '" ++
      name ++
      "' but check failed:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  | Ok({outputs, codegenGap}) => {
      switch codegenGap {
      | Some(gap) => Console.log("codegen gap (bridge stood in): " ++ gap)
      | None => ()
      }
      switch outputs->Array.find(o => o.outputName === name) {
      | None => fail("no output named " ++ name)
      | Some(o) => {
          Console.log("JS (" ++ name ++ ", via " ++ engineLabel(o.engine) ++ "):")
          Console.log(o.js)
          let actual = jsonStringify(evalExpression(o.js))
          let want = jsonStringify(evalExpression(JsPrint.printExpr(expected)))
          if actual === want {
            pass(name ++ " = " ++ actual)
          } else {
            fail(name ++ ": expected " ++ want ++ ", got " ++ actual)
          }
          switch o.engine {
          | NextCodegen => differential(p, name, actual)
          | Bridge => ()
          }
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
// 5b. A computed function — the new codegen exceeding the bridge
// ============================================================================
// App's fn is a wire; here it is another App's output, which the legacy
// representation cannot express (it embeds fn as a JsAst payload). No
// differential is possible — this output exists only via the new codegen.

header("computed function: fn is a wire, beyond the bridge")
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
//     is pushed. Beyond the bridge (its filter close is list-only), so validated
//     against a hand-computed value, like the partial collects.
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
// 7b. Partial collect — the merged flow of two covered cells, terminated by a
//     join (a multi-cell filter: "keep the A's and B's, drop the C's").
//     Beyond the bridge (its case close is exhaustive-or-throw), so validated
//     against a hand-computed value, like registers.
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
//     Beyond the bridge (a partial collect is not a legacy shape), so validated
//     against a hand-computed value, like 7b/7c and the filter option level 7e.
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
// 8. Registers: a running sum via the Delay pair — the first non-legacy
//    construct to run (beyond the bridge, so no differential is possible)
// ============================================================================

header("register pair: running sum compiles via next codegen")
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
//     free, and the user's `add` runs once. Beyond the bridge (Cross), so
//     validated against hand-built tables, and a golden check pins add-once.
// ============================================================================

let countOccurrences = (haystack: string, needle: string): int =>
  Array.length(String.split(haystack, needle)) - 1

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
  // poset round owns it (neither NextCodegen nor the disposable bridge compiles
  // it). NextCodegen declines with a Todo rather than a bad emit, so force that
  // engine and confirm the gap (Pipeline.compile would fall through to the
  // bridge, which raises Failure on commute — an engine gap, not the point here).
  switch Pipeline.compileVia(NextCodegen, fromText) {
  | exception Codegen.Todo(_) => pass("commute declines to compile via NextCodegen (poset round owns the emitter)")
  | Ok(_) => fail("commute unexpectedly compiled — its emitter was Todo")
  | Error(ws) =>
    fail("commute program failed check:\n  " ++ ws->Array.map(Check.witnessToString)->Array.join("\n  "))
  }
  expectRoundTrip(fromText)
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
