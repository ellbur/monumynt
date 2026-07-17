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

  Console.log("TEXT (lane groups print; parsing them is on the growth path):")
  Console.log(TextPrint.print(p))
  expectOutput(p, "out", array_([int_(2), int_(0), int_(10)]))
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
// 8. Registers: representable and printable, not yet compilable
// ============================================================================

header("register pair: prints today, compiles in phase 6")
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
  switch Pipeline.compile(p) {
  | exception Failure(msg) => pass("compile declines gracefully: " ++ msg)
  | Ok(_) => fail("register compile unexpectedly succeeded — phase 6 arrived early?")
  | Error(ws) =>
    fail(
      "expected a bridge failure, got witnesses:\n  " ++
      ws->Array.map(Check.witnessToString)->Array.join("\n  "),
    )
  }
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

header("check: combining sibling flows' elements is witnessed, not trusted")
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
  | Error(ws) => {
      Console.log(ws->Array.map(Check.witnessToString)->Array.join("\n"))
      pass("alignment witness produced (completion will insert a Cross here, phase 4)")
    }
  | Ok(_) => fail("sibling-flow combination compiled without a witness")
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
