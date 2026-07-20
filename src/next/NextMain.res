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
// 2. Double each element — text and handles build the same program
// ============================================================================

header("list flow: text and handles agree")
{
  let src = `
double = js "x => x * 2"
[1, 2, 3] -> open list -> double -~> collect => out
`
  let fromText = TextResolve.parseProgram(src)

  let b = Build.make()
  let dbl = Build.raw(b, "x => x * 2")
  let xs = Build.lit(b, array_([int_(1), int_(2), int_(3)]))
  let it = Build.uncollectList(b, xs.value)
  let doubled = Build.app(b, dbl.value, [it.element])
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
double = js "x => x * 2"
[[1, 2], [3]] -> open list -> open list -> double -~> join -~> collect => flat
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
double = js "x => x * 2"
triple = js "x => x * 3"
[1, 2, 3] -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
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
double = js "x => x * 2"
five = js "5"
five -> open option -> double -~> collect => out
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
dbl = js "x => x * 2"
[10, 20, 30] -> open list -> inc -> dbl -~> collect => out
`
  let p = TextResolve.parseProgram(src)
  expectOutput(p, "out", array_([int_(22), int_(42), int_(62)]))
  expectRoundTrip(p)
  // whole chain — source list through the two apps to the bare collect — on one
  // line (names are the printer's own, so assert the stable structural markers).
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
  let dbl = Build.raw(b, "x => x * 2")
  let maybes = Build.lit(b, array_([int_(1), undefined, int_(5)]))
  let it = Build.uncollectList(b, maybes.value)
  let cs = Build.caseSplit(b, ~alts=["Just", "Nothing"], ~discriminator=disc.value, it.element)
  let just = Build.alt(cs, "Just")
  let nothing = Build.alt(cs, "Nothing")
  let doubled = Build.app(b, dbl.value, [just.altValue])
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
dbl = js "x => x * 2"
[1, 2, 3, 4] -> open list => a, ~L
a -> split classify of Even, Odd => cs
cs.Odd -> dbl => doubled
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
// 10. Witness surface: incomparable contexts (the old silent time travel)
// ============================================================================

header("check: combining sibling flows' elements is witnessed as time travel")
{
  let b = Build.make()
  let addF = Build.raw(b, "(a, b) => a + b")
  let xs = Build.lit(b, array_([int_(1), int_(2)]))
  let ys = Build.lit(b, array_([int_(10), int_(20)]))
  let itX = Build.uncollectList(b, xs.value)
  let itY = Build.uncollectList(b, ys.value)
  let s = Build.app(b, addF.value, [itX.element, itY.element])
  let inner = Build.collect(b, ~flow=itX.flow, s.value)
  let outer = Build.collect(b, ~flow=itY.flow, inner.value)
  let p = Build.finish(b, ~outputs=[("out", outer.value)])
  switch Pipeline.compile(p) {
  | Error(ws) =>
    if ws->Array.some(w => w.rule === "time-travel") {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("time-travel witness produced (completion will insert a Cross here, phase 4)")
    } else {
      fail(
        "expected a time-travel witness, got:\n  " ++
        ws->Array.map(Check.witnessToString)->Array.join("\n  "),
      )
    }
  | Ok(_) => fail("sibling-flow combination compiled without a witness")
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

Console.log(
  "\n" ++
  Int.toString(passCount.contents) ++
  " passed, " ++
  Int.toString(failCount.contents) ++ " failed",
)
if failCount.contents > 0 {
  %raw(`process.exit(1)`)->ignore
}
