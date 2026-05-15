// Test runner for Expr -> JS compilation.
//
// Each test builds an Expr, compiles it to a self-contained JS expression
// (an IIFE), evaluates the JS, and compares the result against an expected
// value supplied as a separate JS expression. Comparison is done via
// JSON.stringify on both sides, which is sufficient for the kinds of
// values (numbers, strings, booleans, arrays, plain objects) we exercise.
//
// The test header shows the number of `const` bindings the compiler
// emitted for the test, which makes the effect of sharing visible — the
// same logical computation produces fewer bindings when sub-expressions
// are bound and reused than when they are duplicated.

open JsBuild
open Expr

@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"

let evalExpression = (code: string): 'a => evalJs("(" ++ code ++ ")")

let passCount = ref(0)
let failCount = ref(0)

let runTest = (~name: string, ~expr: Expr.expr, ~expected: JsAst.expr) => {
  let (stmts, _) = Compile.compileToBody(expr)
  let bindingCount = Array.length(stmts)
  let iife = Compile.compileToIIFE(expr)
  let jsCode = JsPrint.printExpr(iife)
  let expectedCode = JsPrint.printExpr(expected)
  Console.log(
    "--- " ++ name ++ "  (" ++ Int.toString(bindingCount) ++ " bindings) ---",
  )
  Console.log(jsCode)
  let actualVal = evalExpression(jsCode)
  let expectedVal = evalExpression(expectedCode)
  let actualStr = jsonStringify(actualVal)
  let expectedStr = jsonStringify(expectedVal)
  if actualStr == expectedStr {
    Console.log("PASS: " ++ actualStr)
    passCount := passCount.contents + 1
  } else {
    Console.log("FAIL")
    Console.log("  expected: " ++ expectedStr)
    Console.log("  actual:   " ++ actualStr)
    failCount := failCount.contents + 1
  }
  Console.log("")
}

// --- Helpers for building Expr literals ---

let litI = (n: int): Expr.expr => lit(int_(n))
let litS = (s: string): Expr.expr => lit(str(s))
let litB = (b: bool): Expr.expr => lit(bool_(b))

// --- JS functions referenced by examples ---

let jsAdd = arrowExpr([p("a"), p("b")], add(id("a"), id("b")))
let jsMul = arrowExpr([p("a"), p("b")], mul(id("a"), id("b")))
let jsSub = arrowExpr([p("a"), p("b")], sub(id("a"), id("b")))
// String concatenation shares the JS `+` operator.
let jsConcat = arrowExpr([p("a"), p("b")], add(id("a"), id("b")))
// (a, b) => a < b ? a : b
let jsMinOfTwo = arrowExpr(
  [p("a"), p("b")],
  cond(lt(id("a"), id("b")), id("a"), id("b")),
)

let mathSqrt = member(id("Math"), "sqrt")
let mathMax = member(id("Math"), "max")
let mathAbs = member(id("Math"), "abs")
let mathPow = member(id("Math"), "pow")
let arrayOf = member(id("Array"), "of")

let makePoint = arrowExpr(
  [p("x"), p("y")],
  obj([("x", id("x")), ("y", id("y"))]),
)

// =====================================================================
// Baseline tests: every Expr node compiles to one binding. No sharing.
// =====================================================================

runTest(~name="literal int", ~expr=litI(5), ~expected=int_(5))
runTest(~name="literal string", ~expr=litS("hello"), ~expected=str("hello"))
runTest(~name="literal bool true", ~expr=litB(true), ~expected=bool_(true))
runTest(
  ~name="literal array",
  ~expr=lit(array_([int_(1), int_(2), int_(3)])),
  ~expected=array_([int_(1), int_(2), int_(3)]),
)
runTest(
  ~name="literal object",
  ~expr=lit(obj([("x", int_(1)), ("y", int_(2))])),
  ~expected=obj([("x", int_(1)), ("y", int_(2))]),
)
runTest(
  ~name="literal Math.PI reference",
  ~expr=lit(member(id("Math"), "PI")),
  ~expected=member(id("Math"), "PI"),
)

runTest(
  ~name="add(2, 3)",
  ~expr=app(jsAdd, [litI(2), litI(3)]),
  ~expected=int_(5),
)
runTest(
  ~name="Math.sqrt(16)",
  ~expr=app(mathSqrt, [litI(16)]),
  ~expected=int_(4),
)
runTest(
  ~name="Math.max(3, 7, 2, 5)",
  ~expr=app(mathMax, [litI(3), litI(7), litI(2), litI(5)]),
  ~expected=int_(7),
)
runTest(
  ~name="Math.abs(-42)",
  ~expr=app(mathAbs, [litI(-42)]),
  ~expected=int_(42),
)
runTest(
  ~name="string concat",
  ~expr=app(jsConcat, [litS("hello "), litS("world")]),
  ~expected=str("hello world"),
)
runTest(
  ~name="Array.of(1, 2, 3)",
  ~expr=app(arrayOf, [litI(1), litI(2), litI(3)]),
  ~expected=array_([int_(1), int_(2), int_(3)]),
)
runTest(
  ~name="makePoint(3, 4)",
  ~expr=app(makePoint, [litI(3), litI(4)]),
  ~expected=obj([("x", int_(3)), ("y", int_(4))]),
)
runTest(
  ~name="2*3 + 4*5",
  ~expr=app(jsAdd, [
    app(jsMul, [litI(2), litI(3)]),
    app(jsMul, [litI(4), litI(5)]),
  ]),
  ~expected=int_(26),
)
runTest(
  ~name="sqrt(7 + 9)",
  ~expr=app(mathSqrt, [app(jsAdd, [litI(7), litI(9)])]),
  ~expected=int_(4),
)
runTest(
  ~name="Math.pow(2, 8)",
  ~expr=app(mathPow, [litI(2), litI(8)]),
  ~expected=int_(256),
)
runTest(
  ~name="sqrt(3*3 + 4*4)",
  ~expr=app(mathSqrt, [
    app(jsAdd, [
      app(jsMul, [litI(3), litI(3)]),
      app(jsMul, [litI(4), litI(4)]),
    ]),
  ]),
  ~expected=int_(5),
)
runTest(
  ~name="minOfTwo(minOfTwo(7, 4), 10)",
  ~expr=app(jsMinOfTwo, [
    app(jsMinOfTwo, [litI(7), litI(4)]),
    litI(10),
  ]),
  ~expected=int_(4),
)
runTest(
  ~name="sub(5, 8) -> -3",
  ~expr=app(jsSub, [litI(5), litI(8)]),
  ~expected=int_(-3),
)

let getX = arrowExpr([p("p")], member(id("p"), "x"))
runTest(
  ~name="getX(makePoint(add(1, 2), add(3, 4)))",
  ~expr=app(getX, [
    app(makePoint, [
      app(jsAdd, [litI(1), litI(2)]),
      app(jsAdd, [litI(3), litI(4)]),
    ]),
  ]),
  ~expected=int_(3),
)

let const42 = arrowExpr([], int_(42))
runTest(
  ~name="zero-arg function () => 42",
  ~expr=app(const42, []),
  ~expected=int_(42),
)

// =====================================================================
// Sharing tests. These pair a "no sharing" version (each subexpression
// constructed afresh) with a "shared" version (one Expr value bound and
// reused). Both produce the same value; the shared version emits fewer
// bindings, which the binding count in the test header makes visible.
// =====================================================================

// (1) (2*3) + (2*3), each sub-expression constructed twice.
runTest(
  ~name="unshared: (2*3) + (2*3) — two independent sub-trees",
  ~expr=app(jsAdd, [
    app(jsMul, [litI(2), litI(3)]),
    app(jsMul, [litI(2), litI(3)]),
  ]),
  ~expected=int_(12),
)

// (1') Same expression, but 2*3 built once and shared as both args.
{
  let twoThree = app(jsMul, [litI(2), litI(3)])
  runTest(
    ~name="shared: (2*3) + (2*3) — single 2*3 bound and reused",
    ~expr=app(jsAdd, [twoThree, twoThree]),
    ~expected=int_(12),
  )
}

// (2) Diamond: a literal node feeds two siblings of an outer node.
{
  let x = litI(7)
  runTest(
    ~name="diamond: add(x, x) where x = lit(7)",
    ~expr=app(jsAdd, [x, x]),
    ~expected=int_(14),
  )
}

// (3) Three uses of the same literal.
{
  let x = litI(5)
  let triple = arrowExpr(
    [p("a"), p("b"), p("c")],
    add(id("a"), add(id("b"), id("c"))),
  )
  runTest(
    ~name="triangle: triple(x, x, x) — one literal bound, three uses",
    ~expr=app(triple, [x, x, x]),
    ~expected=int_(15),
  )
}

// (4) A non-trivial shared literal: Math.PI used twice.
{
  let pi = lit(member(id("Math"), "PI"))
  runTest(
    ~name="shared Math.PI: Math.PI + Math.PI",
    ~expr=app(jsAdd, [pi, pi]),
    ~expected=bin(Mul, int_(2), member(id("Math"), "PI")),
  )
}

// (5) Larger example: circle area and circumference, both depending on
//     a shared `pi` and a shared radius `r`. The output bundles them in
//     one object via a small JS helper.
{
  let pi = lit(member(id("Math"), "PI"))
  let r = litI(3)
  let two = litI(2)
  let rsq = app(jsMul, [r, r])
  let area = app(jsMul, [pi, rsq])
  let twoPi = app(jsMul, [two, pi])
  let circumference = app(jsMul, [twoPi, r])
  let bundle = arrowExpr(
    [p("a"), p("c")],
    obj([("area", id("a")), ("circ", id("c"))]),
  )
  runTest(
    ~name="circle metrics: area and circumference share pi and r",
    ~expr=app(bundle, [area, circumference]),
    ~expected=obj([
      ("area", bin(Mul, member(id("Math"), "PI"), int_(9))),
      (
        "circ",
        bin(
          Mul,
          bin(Mul, int_(2), member(id("Math"), "PI")),
          int_(3),
        ),
      ),
    ]),
  )
}

// (6) Deep diamond: a single shared root used by a tree of consumers.
{
  let leaf = app(jsMul, [litI(2), litI(3)]) // = 6, computed once
  let plusOne = arrowExpr([p("a")], add(id("a"), int_(1)))
  let timesTwo = arrowExpr([p("a")], mul(id("a"), int_(2)))
  let combine = arrowExpr(
    [p("a"), p("b"), p("c")],
    add(id("a"), add(id("b"), id("c"))),
  )
  runTest(
    ~name="deep diamond: combine(leaf, plusOne(leaf), timesTwo(leaf))",
    ~expr=app(combine, [
      leaf,
      app(plusOne, [leaf]),
      app(timesTwo, [leaf]),
    ]),
    ~expected=int_(6 + (6 + 1) + 6 * 2), // 25
  )
}

Console.log("==== Summary ====")
Console.log(
  Int.toString(passCount.contents) ++
  " passed, " ++
  Int.toString(failCount.contents) ++ " failed",
)
