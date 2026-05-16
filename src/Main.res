// Test runner for Expr -> JS compilation.
//
// Each test builds an Expr, compiles it to a self-contained JS expression
// (an IIFE), evaluates the JS, and compares the result against an expected
// value supplied as a separate JS expression. Comparison is done via
// JSON.stringify on both sides, which is sufficient for the kinds of
// values (numbers, strings, booleans, arrays, plain objects) we exercise.
//
// The test header shows the number of outer-level statements the compiler
// emitted for the test (const bindings + for-of statements). Differences
// across versions of the same logical computation make sharing, hoisting,
// and joining visible at a glance — a "shared" version typically emits
// fewer outer stmts than its "unshared" counterpart, and a joined nested
// loop emits fewer than its non-joined sibling.

open JsBuild
open Expr

@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"

let evalExpression = (code: string): 'a => evalJs("(" ++ code ++ ")")

let passCount = ref(0)
let failCount = ref(0)

let runTest = (~name: string, ~expr: Expr.expr, ~expected: JsAst.expr) => {
  let (stmts, _) = Compile.compileToBody(expr)
  let stmtCount = Array.length(stmts)
  let exprRendering = ExprPrint.render(expr)
  let iife = Compile.compileToIIFE(expr)
  let jsCode = JsPrint.printExpr(iife)
  let expectedCode = JsPrint.printExpr(expected)
  Console.log(
    "--- " ++ name ++ "  (" ++ Int.toString(stmtCount) ++ " outer stmts) ---",
  )
  Console.log("EXPR:")
  Console.log(exprRendering)
  Console.log("JS:")
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

// --- Bundling helpers used by tests to package multiple results into
//     one named-field object via a JS arrow function. `bundle2("a", "b")`
//     is `(a, b) => ({a: a, b: b})` (renamed if labels differ). ---

let bundle2 = (l1: string, l2: string): JsAst.expr =>
  arrowExpr([p("a"), p("b")], obj([(l1, id("a")), (l2, id("b"))]))

let bundle3 = (l1: string, l2: string, l3: string): JsAst.expr =>
  arrowExpr(
    [p("a"), p("b"), p("c")],
    obj([(l1, id("a")), (l2, id("b")), (l3, id("c"))]),
  )

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
  runTest(
    ~name="circle metrics: area and circumference share pi and r",
    ~expr=app(bundle2("area", "circ"), [area, circumference]),
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

// =====================================================================
// Flow tests. Single-open / single-close list iteration only — Open is
// always ListIter, Close is a list close. The compiled output is
// a `for…of` loop that builds an array and pushes per-iteration values
// into it. Loop-invariant computations are hoisted to the outer level.
// =====================================================================

// (1) Identity map — a sanity check that opening + closing alone does the
//     right thing.
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  runTest(
    ~name="list iter: identity map of [1,2,3]",
    ~expr=close_(opened, opened),
    ~expected=array_([int_(1), int_(2), int_(3)]),
  )
}

// (2) Map double — a single transformation applied per element.
let double = arrowExpr([p("x")], mul(id("x"), int_(2)))
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  runTest(
    ~name="list iter: map double over [1,2,3]",
    ~expr=close_(opened, app(double, [opened])),
    ~expected=array_([int_(2), int_(4), int_(6)]),
  )
}

// (3) Empty input — the loop body simply doesn't run.
{
  let input = lit(array_([]))
  let opened = open_(ListIter, input)
  runTest(
    ~name="list iter: map double over []",
    ~expr=close_(opened, app(double, [opened])),
    ~expected=array_([]),
  )
}

// (4) Element shared inside the loop body — the per-iteration element is
//     used twice in `square = elem * elem`. The `square` binding lives
//     inside the loop, but the element is referenced (not recomputed) for
//     each use.
{
  let input = lit(array_([int_(2), int_(3), int_(4)]))
  let opened = open_(ListIter, input)
  let square = app(jsMul, [opened, opened])
  runTest(
    ~name="list iter: square — element shared inside body",
    ~expr=close_(opened, square),
    ~expected=array_([int_(4), int_(9), int_(16)]),
  )
}

// (5) Loop-invariant Lit — a literal used only inside the body but which
//     does not depend on the iteration element should be hoisted to the
//     outer level so it is computed once. The compiled JS shows the
//     `const v_ten = 10;` outside the for-of, with the body referencing
//     `v_ten`.
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let ten = lit(int_(10))
  runTest(
    ~name="list iter: loop-invariant constant hoisted out",
    ~expr=close_(opened, app(jsAdd, [ten, opened])),
    ~expected=array_([int_(11), int_(12), int_(13)]),
  )
}

// (6) Value shared between inside and outside the loop. `k` is used both
//     in the loop body (added to each element) and outside (paired with
//     the resulting list). It is bound once at the outer level and both
//     uses reference that binding — no recomputation.
{
  let k = lit(int_(100))
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let mapped = close_(opened, app(jsAdd, [k, opened]))
  runTest(
    ~name="list iter: shared k=100 used both inside and outside loop",
    ~expr=app(bundle2("base", "mapped"), [k, mapped]),
    ~expected=obj([
      ("base", int_(100)),
      ("mapped", array_([int_(101), int_(102), int_(103)])),
    ]),
  )
}

// (7) The Close's output is a normal value downstream — feed it to a
//     plain function call after the loop has run.
{
  let lengthOf = arrowExpr([p("a")], member(id("a"), "length"))
  let input = lit(array_([int_(5), int_(10), int_(15), int_(20)]))
  let opened = open_(ListIter, input)
  let mapped = close_(opened, app(double, [opened]))
  runTest(
    ~name="list iter: post-process — length of mapped result",
    ~expr=app(lengthOf, [mapped]),
    ~expected=int_(4),
  )
}

// =====================================================================
// Multi-close tests. One Open can be closed by several Closes; all of
// them share a single for-of loop and each pushes into its own output
// array. This is meaningful for lists because each iteration can
// contribute to several outputs at once.
// =====================================================================

let triple = arrowExpr([p("x")], mul(id("x"), int_(3)))

// (1) Two Closes from one Open. The compiled JS should contain a single
//     for-of loop with two pushes (one per Close) and two output arrays
//     declared at the outer level.
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let doubled = close_(opened, app(double, [opened]))
  let tripled = close_(opened, app(triple, [opened]))
  runTest(
    ~name="multi-close: doubled and tripled, one loop two pushes",
    ~expr=app(bundle2("doubled", "tripled"), [doubled, tripled]),
    ~expected=obj([
      ("doubled", array_([int_(2), int_(4), int_(6)])),
      ("tripled", array_([int_(3), int_(6), int_(9)])),
    ]),
  )
}

// (2) Three Closes from one Open. One loop, three pushes.
{
  let plusOne = arrowExpr([p("x")], add(id("x"), int_(1)))
  let input = lit(array_([int_(10), int_(20), int_(30)]))
  let opened = open_(ListIter, input)
  let asIs = close_(opened, opened)
  let dbl = close_(opened, app(double, [opened]))
  let inc = close_(opened, app(plusOne, [opened]))
  runTest(
    ~name="multi-close: identity + double + +1, one loop three pushes",
    ~expr=app(bundle3("a", "b", "c"), [asIs, dbl, inc]),
    ~expected=obj([
      ("a", array_([int_(10), int_(20), int_(30)])),
      ("b", array_([int_(20), int_(40), int_(60)])),
      ("c", array_([int_(11), int_(21), int_(31)])),
    ]),
  )
}

// (3) Two Closes that share an intermediate computation. `square = x*x`
//     is referenced by both bodies; it should be computed exactly once
//     per iteration (a single binding in the loop body, used by both
//     pushes).
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let square = app(jsMul, [opened, opened])
  let one = lit(int_(1))
  let two = lit(int_(2))
  let close1 = close_(opened, app(jsAdd, [square, one]))
  let close2 = close_(opened, app(jsMul, [square, two]))
  runTest(
    ~name="multi-close: shared intermediate (square computed once per iter)",
    ~expr=app(bundle2("plusOne", "timesTwo"), [close1, close2]),
    ~expected=obj([
      ("plusOne", array_([int_(2), int_(5), int_(10)])),
      ("timesTwo", array_([int_(2), int_(8), int_(18)])),
    ]),
  )
}

// (4) Each Close has its own loop-invariant Lit (different constants).
//     Both should be hoisted to the outer level (declared once each,
//     used inside the loop body for each Close's body).
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let ten = lit(int_(10))
  let hundred = lit(int_(100))
  let plus10 = close_(opened, app(jsAdd, [ten, opened]))
  let plus100 = close_(opened, app(jsAdd, [hundred, opened]))
  runTest(
    ~name="multi-close: each Close has its own loop-invariant constant",
    ~expr=app(bundle2("p10", "p100"), [plus10, plus100]),
    ~expected=obj([
      ("p10", array_([int_(11), int_(12), int_(13)])),
      ("p100", array_([int_(101), int_(102), int_(103)])),
    ]),
  )
}

// (5) Two independent loops in sequence (different Opens). They should
//     compile to two for-of loops, each with their own loop variable
//     and output array — no interference.
{
  let inputA = lit(array_([int_(1), int_(2), int_(3)]))
  let openedA = open_(ListIter, inputA)
  let resultA = close_(openedA, app(double, [openedA]))
  let inputB = lit(array_([int_(10), int_(20)]))
  let openedB = open_(ListIter, inputB)
  let resultB = close_(openedB, app(triple, [openedB]))
  runTest(
    ~name="two independent loops in sequence",
    ~expr=app(bundle2("first", "second"), [resultA, resultB]),
    ~expected=obj([
      ("first", array_([int_(2), int_(4), int_(6)])),
      ("second", array_([int_(30), int_(60)])),
    ]),
  )
}

// (6) The same Close referenced in two places downstream — should
//     compile only once (memo hit on the second reference). Combined
//     with multi-close: two Closes sharing an Open, and one of them
//     used twice downstream.
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input)
  let doubled = close_(opened, app(double, [opened]))
  let tripled = close_(opened, app(triple, [opened]))
  runTest(
    ~name="multi-close: one Close used twice downstream + sibling Close",
    ~expr=app(bundle3("d1", "d2", "t"), [doubled, doubled, tripled]),
    ~expected=obj([
      ("d1", array_([int_(2), int_(4), int_(6)])),
      ("d2", array_([int_(2), int_(4), int_(6)])),
      ("t", array_([int_(3), int_(6), int_(9)])),
    ]),
  )
}

// =====================================================================
// Nested list flows. Iterate over a list of lists: open the outer list,
// open each inner list, transform each inner element, close the inner
// flow back to a list, close the outer flow to a list of lists.
// =====================================================================

// (1) Plain nested map — double each element of [[1,2],[3,4]].
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3), int_(4)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  let innerClosed = close_(
    innerOpened,
    app(double, [innerOpened]),
  )
  let outerClosed = close_(outerOpened, innerClosed)
  runTest(
    ~name="nested list flows: double each elem of [[1,2],[3,4]]",
    ~expr=outerClosed,
    ~expected=array_([
      array_([int_(2), int_(4)]),
      array_([int_(6), int_(8)]),
    ]),
  )
}

// (2) An empty inner list among non-empty ones — the inner loop simply
//     doesn't execute for that outer iteration, producing an empty
//     inner result.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([]),
    array_([int_(3)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  let innerClosed = close_(
    innerOpened,
    app(double, [innerOpened]),
  )
  let outerClosed = close_(outerOpened, innerClosed)
  runTest(
    ~name="nested list flows: with an empty inner list",
    ~expr=outerClosed,
    ~expected=array_([
      array_([int_(2), int_(4)]),
      array_([]),
      array_([int_(6)]),
    ]),
  )
}

// (3) Nesting combined with multi-close on the inner loop. For each
//     outer element, run the inner loop once but produce two inner
//     output lists (doubled and tripled) bundled into an object. The
//     inner for-of contains two pushes; everything is inside the outer
//     for-of body.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  let innerDoubled = close_(
    innerOpened,
    app(double, [innerOpened]),
  )
  let innerTripled = close_(
    innerOpened,
    app(triple, [innerOpened]),
  )
  let perOuter = app(bundle2("d", "t"), [innerDoubled, innerTripled])
  let outerClosed = close_(outerOpened, perOuter)
  runTest(
    ~name="nested + multi-close on inner: each outer elem -> {d, t}",
    ~expr=outerClosed,
    ~expected=array_([
      obj([
        ("d", array_([int_(2), int_(4)])),
        ("t", array_([int_(3), int_(6)])),
      ]),
      obj([("d", array_([int_(6)])), ("t", array_([int_(9)]))]),
    ]),
  )
}

// =====================================================================
// Join (list flow). `Join` wraps an opener; closing on a joined opener
// flattens one level on output. The loops are still nested (one for
// each Open in the chain), the computation still happens in the
// innermost body, but the output array is allocated above the
// outermost loop instead of in its parent's body.
// =====================================================================

// (1) Basic join: nested map flattened — [[1,2],[3,4]] → [2,4,6,8].
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3), int_(4)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  runTest(
    ~name="join: nested map flattened — [[1,2],[3,4]] -> [2,4,6,8]",
    ~expr=close_(
        join_(innerOpened),
      app(double, [innerOpened]),
    ),
    ~expected=array_([int_(2), int_(4), int_(6), int_(8)]),
  )
}

// (2) Identity join: just flatten the input — [[1,2],[],[3]] → [1,2,3].
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([]),
    array_([int_(3)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  runTest(
    ~name="join: flatten of [[1,2],[],[3]] -> [1,2,3]",
    ~expr=close_(join_(innerOpened), innerOpened),
    ~expected=array_([int_(1), int_(2), int_(3)]),
  )
}

// (3) Empty outer — no inner iterations happen at all, result is [].
{
  let input = lit(array_([]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  runTest(
    ~name="join: empty outer -> []",
    ~expr=close_(join_(innerOpened), innerOpened),
    ~expected=array_([]),
  )
}

// (4) Loop-invariant Lit hoisted; join still gets a flat list. The
//     `ten` constant should appear once at the very top, before either
//     loop, even though it's only referenced from inside the inner body.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3)]),
  ]))
  let outerOpened = open_(ListIter, input)
  let innerOpened = open_(ListIter, outerOpened)
  let ten = lit(int_(10))
  runTest(
    ~name="join: with hoisted constant — flat list of x+10",
    ~expr=close_(
        join_(innerOpened),
      app(jsAdd, [ten, innerOpened]),
    ),
    ~expected=array_([int_(11), int_(12), int_(13)]),
  )
}

// (5) Triply nested with two joins — flatten two levels.
//     [[[1,2],[3]],[[4]]] → [2,4,6,8].
{
  let input = lit(array_([
    array_([array_([int_(1), int_(2)]), array_([int_(3)])]),
    array_([array_([int_(4)])]),
  ]))
  let l1 = open_(ListIter, input)
  let l2 = open_(ListIter, l1)
  let l3 = open_(ListIter, l2)
  runTest(
    ~name="join x2: flatten of [[[1,2],[3]],[[4]]] mapped *2 -> [2,4,6,8]",
    ~expr=close_(
        join_(join_(l3)),
      app(double, [l3]),
    ),
    ~expected=array_([int_(2), int_(4), int_(6), int_(8)]),
  )
}

// (6) Compare side by side: same input, joined vs unjoined, paired.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3)]),
  ]))
  let openOuter1 = open_(ListIter, input)
  let openInner1 = open_(ListIter, openOuter1)
  let nested = close_(
    openOuter1,
    close_(openInner1, app(double, [openInner1])),
  )
  let openOuter2 = open_(ListIter, input)
  let openInner2 = open_(ListIter, openOuter2)
  let flat = close_(
    join_(openInner2),
    app(double, [openInner2]),
  )
  runTest(
    ~name="join vs nested side-by-side on the same input",
    ~expr=app(bundle2("nested", "flat"), [nested, flat]),
    ~expected=obj([
      (
        "nested",
        array_([
          array_([int_(2), int_(4)]),
          array_([int_(6)]),
        ]),
      ),
      ("flat", array_([int_(2), int_(4), int_(6)])),
    ]),
  )
}

// =====================================================================
// Mixed joinCounts on a single opener. Both joined and unjoined closes
// share the same inner Open and the same loops; each produces its own
// output array at its own joined-out scope.
// =====================================================================

// (1) Mixed unjoined + joined inner closes, with an outer close that
//     consumes the unjoined per-iter list. Expected JS structure:
//     - unjoined out (per outer iter) inside outer body.
//     - joined out at top level.
//     - outer-close out at top level (collecting the per-iter lists).
//     - Both pushes inside the inner body.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3), int_(4)]),
  ]))
  let outer = open_(ListIter, input)
  let inner = open_(ListIter, outer)
  let unjoined = close_(inner, app(double, [inner]))
  let flat = close_(join_(inner), app(double, [inner]))
  let nested = close_(outer, unjoined)
  runTest(
    ~name="mixed: unjoined + joined on one opener; nested wraps unjoined",
    ~expr=app(bundle2("nested", "flat"), [nested, flat]),
    ~expected=obj([
      ("nested", array_([
        array_([int_(2), int_(4)]),
        array_([int_(6), int_(8)]),
      ])),
      ("flat", array_([int_(2), int_(4), int_(6), int_(8)])),
    ]),
  )
}

// (2) Same as above but the per-element computation is *shared* between
//     the unjoined and joined closes (same node, not two equivalent
//     ones). The compiled JS should compute `double(elem)` exactly once
//     per inner iteration and push the same binding into both arrays.
{
  let input = lit(array_([
    array_([int_(1), int_(2)]),
    array_([int_(3)]),
  ]))
  let outer = open_(ListIter, input)
  let inner = open_(ListIter, outer)
  let body = app(double, [inner])  // shared between both closes
  let unjoined = close_(inner, body)
  let flat = close_(join_(inner), body)
  let nested = close_(outer, unjoined)
  runTest(
    ~name="mixed (shared body): one double per iter, two pushes",
    ~expr=app(bundle2("nested", "flat"), [nested, flat]),
    ~expected=obj([
      ("nested", array_([
        array_([int_(2), int_(4)]),
        array_([int_(6)]),
      ])),
      ("flat", array_([int_(2), int_(4), int_(6)])),
    ]),
  )
}

// =====================================================================
// Case-split flow. `Open CaseSplit({alts, discriminator})` opens an
// alternative-typed value into one value port + one flow port per alt.
// `Branch({source, alt})` selects a port. A case `Close` collects the
// branches back together. The compile target is an `if/else if/else`
// chain with a `let v_close` per Close, assigned in each branch.
// =====================================================================

// A do-nothing discriminator that assumes the input is already
// `{tag, value}`-shaped.
let identity = arrowExpr([p("x")], id("x"))

// (1) Maybe-double: if Just, double the int; if Nothing, return 0.
//     Test both alternatives.
let maybeDouble = (input: JsAst.expr): Expr.expr => {
  let inputE = lit(input)
  let opened = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE,
  )
  let justB = branch_(opened, "Just")
  let nothingB = branch_(opened, "Nothing")
  caseClose([
    {altName: Some("Just"), flow: justB, value: app(double, [justB])},
    {altName: Some("Nothing"), flow: nothingB, value: lit(int_(0))},
  ])
}

runTest(
  ~name="case-split: Maybe-double of Just(42)",
  ~expr=maybeDouble(obj([("tag", str("Just")), ("value", int_(42))])),
  ~expected=int_(84),
)

runTest(
  ~name="case-split: Maybe-double of Nothing",
  ~expr=maybeDouble(obj([("tag", str("Nothing"))])),
  ~expected=int_(0),
)

// (2) Either-with-different-result-types: take an Either<string, int>;
//     for Left return its length, for Right return it doubled.
{
  let inputE = lit(obj([("tag", str("Left")), ("value", str("hello"))]))
  let opened = open_(
    CaseSplit({alts: ["Left", "Right"], discriminator: identity}),
    inputE,
  )
  let leftB = branch_(opened, "Left")
  let rightB = branch_(opened, "Right")
  let lengthFn = arrowExpr([p("s")], member(id("s"), "length"))
  runTest(
    ~name="case-split: Either<string,int> — Left.length / Right * 2",
    ~expr=caseClose([
      {altName: Some("Left"), flow: leftB, value: app(lengthFn, [leftB])},
      {altName: Some("Right"), flow: rightB, value: app(double, [rightB])},
    ]),
    ~expected=int_(5),
  )
}

// (3) Multi-close on a case-split: produce two outputs from the same
//     CaseSplit Open. One returns "tag-or-zero", another returns the
//     payload-or-empty-string. Both share the same if/else chain.
{
  let inputE = lit(obj([("tag", str("Just")), ("value", int_(7))]))
  let opened = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE,
  )
  let justB = branch_(opened, "Just")
  let nothingB = branch_(opened, "Nothing")
  let valOrZero = caseClose([
    {altName: Some("Just"), flow: justB, value: justB},
    {altName: Some("Nothing"), flow: nothingB, value: lit(int_(0))},
  ])
  let tagOnly = caseClose([
    {altName: Some("Just"), flow: justB, value: lit(str("present"))},
    {altName: Some("Nothing"), flow: nothingB, value: lit(str("absent"))},
  ])
  runTest(
    ~name="case-split: multi-close — value-or-zero + tag",
    ~expr=app(bundle2("v", "tag"), [valOrZero, tagOnly]),
    ~expected=obj([("v", int_(7)), ("tag", str("present"))]),
  )
}

// (4) Case-split on a sign predicate: positive → x*x, negative → -x.
//     The discriminator is a real function (not identity) that maps the
//     raw int into a tagged shape.
{
  let signDisc = arrowExpr(
    [p("x")],
    cond(
      gte(id("x"), int_(0)),
      obj([("tag", str("Pos")), ("value", id("x"))]),
      obj([("tag", str("Neg")), ("value", neg(id("x")))]),
    ),
  )
  let mkProg = (n: int): Expr.expr => {
    let inputE = lit(int_(n))
    let opened = open_(
      CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
      inputE,
    )
    let posB = branch_(opened, "Pos")
    let negB = branch_(opened, "Neg")
    let square = arrowExpr([p("x")], mul(id("x"), id("x")))
    caseClose([
      {altName: Some("Pos"), flow: posB, value: app(square, [posB])},
      {altName: Some("Neg"), flow: negB, value: negB}, // -x is already in the value port via the disc
    ])
  }
  runTest(
    ~name="case-split: sign disc — Pos(5) -> 25",
    ~expr=mkProg(5),
    ~expected=int_(25),
  )
  runTest(
    ~name="case-split: sign disc — Neg(-7) -> 7",
    ~expr=mkProg(-7),
    ~expected=int_(7),
  )
}

// (5) Case-split inside a list iteration: for each element of a list of
//     Maybes, return either `value*2` or `0`, collecting into a list.
{
  let input = lit(array_([
    obj([("tag", str("Just")), ("value", int_(1))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(5))]),
  ]))
  let opened = open_(ListIter, input)
  // Per element: case-split.
  let inner = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(inner, "Just")
  let nothingB = branch_(inner, "Nothing")
  let perElemResult = caseClose([
    {altName: Some("Just"), flow: justB, value: app(double, [justB])},
    {altName: Some("Nothing"), flow: nothingB, value: lit(int_(0))},
  ])
  runTest(
    ~name="case-split inside list iter: [Just(1), Nothing, Just(5)] -> [2, 0, 10]",
    ~expr=close_(opened, perElemResult),
    ~expected=array_([int_(2), int_(0), int_(10)]),
  )
}

// (6) Shared computation across branches: both branches reference a
//     value computed once outside the if. Verify it's emitted once at
//     the parent scope.
{
  let inputE = lit(obj([("tag", str("Just")), ("value", int_(10))]))
  let bonus = lit(int_(100))  // shared between Just and Nothing
  let opened = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE,
  )
  let justB = branch_(opened, "Just")
  let nothingB = branch_(opened, "Nothing")
  runTest(
    ~name="case-split: shared `bonus` used in both branches",
    ~expr=caseClose([
      {altName: Some("Just"), flow: justB, value: app(jsAdd, [justB, bonus])},
      {altName: Some("Nothing"), flow: nothingB, value: bonus},
    ]),
    ~expected=int_(110),
  )
}

// (7) Nested case-splits: outer split of a Maybe<Either<…>>. Just
//     branch contains another split.
{
  let inputE = lit(obj([
    ("tag", str("Just")),
    ("value", obj([("tag", str("Right")), ("value", int_(7))])),
  ]))
  let outerSplit = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE,
  )
  let justB = branch_(outerSplit, "Just")
  let nothingB = branch_(outerSplit, "Nothing")
  // Inside Just: split again.
  let innerSplit = open_(
    CaseSplit({alts: ["Left", "Right"], discriminator: identity}),
    justB,
  )
  let leftB = branch_(innerSplit, "Left")
  let rightB = branch_(innerSplit, "Right")
  let innerResult = caseClose([
    {altName: Some("Left"), flow: leftB, value: lit(int_(-1))},
    {altName: Some("Right"), flow: rightB, value: app(double, [rightB])},
  ])
  let outerResult = caseClose([
    {altName: Some("Just"), flow: justB, value: innerResult},
    {altName: Some("Nothing"), flow: nothingB, value: lit(int_(0))},
  ])
  runTest(
    ~name="case-split: nested Maybe<Either<_, int>> — Just(Right(7)) -> 14",
    ~expr=outerResult,
    ~expected=int_(14),
  )
}

// =====================================================================
// Filter — the case-split-in-list analogue of Join. Wraps a Branch and
// tells the consuming Close to push inside that alt's if-body, putting
// the output array at the surrounding list's parent scope. Lets you
// keep only the elements whose case matches the filtered alt.
// =====================================================================

// (1) Basic filter: keep only Justs from a list of Maybes, doubled.
{
  let input = lit(array_([
    obj([("tag", str("Just")), ("value", int_(1))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(5))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(3))]),
  ]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(split, "Just")
  runTest(
    ~name="filter: keep only Justs, doubled",
    ~expr=close_(filter_(justB), app(double, [justB])),
    ~expected=array_([int_(2), int_(10), int_(6)]),
  )
}

// (2) Filter to identity: just collect the inner values of all Justs.
{
  let input = lit(array_([
    obj([("tag", str("Just")), ("value", int_(7))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(11))]),
  ]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(split, "Just")
  runTest(
    ~name="filter: identity — extract Just values",
    ~expr=close_(filter_(justB), justB),
    ~expected=array_([int_(7), int_(11)]),
  )
}

// (3) Filter with no matches: input has no Justs.
{
  let input = lit(array_([
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Nothing"))]),
  ]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(split, "Just")
  runTest(
    ~name="filter: no Justs in input -> []",
    ~expr=close_(filter_(justB), app(double, [justB])),
    ~expected=array_([]),
  )
}

// (4) Filter with a real predicate: keep only positive numbers from a
//     list of ints. Discriminator splits Pos vs Neg; we filter to Pos
//     and square.
{
  let signDisc = arrowExpr(
    [p("x")],
    cond(
      gte(id("x"), int_(0)),
      obj([("tag", str("Pos")), ("value", id("x"))]),
      obj([("tag", str("Neg")), ("value", neg(id("x")))]),
    ),
  )
  let input = lit(array_([int_(3), int_(-2), int_(5), int_(0), int_(-7), int_(4)]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
    opened,
  )
  let posB = branch_(split, "Pos")
  let square = arrowExpr([p("x")], mul(id("x"), id("x")))
  runTest(
    ~name="filter: positives only, squared (Pos/Neg disc, [3,-2,5,0,-7,4] -> [9,25,0,16])",
    ~expr=close_(filter_(posB), app(square, [posB])),
    ~expected=array_([int_(9), int_(25), int_(0), int_(16)]),
  )
}

// (5) Multi-filter — partition: one filter per alt. Two output lists,
//     one for each branch. Single for-of with an if/else-if chain
//     pushing to the right output per alt.
{
  let input = lit(array_([
    obj([("tag", str("Just")), ("value", int_(1))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(5))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(3))]),
  ]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(split, "Just")
  let nothingB = branch_(split, "Nothing")
  let justs = close_(filter_(justB), app(double, [justB]))
  let nothings = close_(filter_(nothingB), lit(int_(99)))
  runTest(
    ~name="multi-filter: partition Maybes into doubled-Justs and 99-per-Nothing",
    ~expr=app(bundle2("justs", "nothings"), [justs, nothings]),
    ~expected=obj([
      ("justs", array_([int_(2), int_(10), int_(6)])),
      ("nothings", array_([int_(99), int_(99)])),
    ]),
  )
}

// (5b) Filter under joined nested lists. The case-split's input is a
//      Join-wrapped inner list iter, so the filter close compiles to
//      two nested for-ofs followed by an if. The output is a single
//      flat list, filtered to only the Justs and doubled.
{
  let input = lit(array_([
    array_([
      obj([("tag", str("Just")), ("value", int_(1))]),
      obj([("tag", str("Nothing"))]),
    ]),
    array_([
      obj([("tag", str("Just")), ("value", int_(5))]),
      obj([("tag", str("Nothing"))]),
      obj([("tag", str("Just")), ("value", int_(3))]),
    ]),
    array_([]),
  ]))
  let outer = open_(ListIter, input)
  let inner = open_(ListIter, outer)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    join_(inner),
  )
  let justB = branch_(split, "Just")
  runTest(
    ~name="filter under joined nested lists: flatten + filter Justs, doubled",
    ~expr=close_(filter_(justB), app(double, [justB])),
    ~expected=array_([int_(2), int_(10), int_(6)]),
  )
}

// (6) Multi-filter targeting the same alt — two filter closes both
//     filtering "Pos", producing two parallel output lists. Each push
//     happens inside the same Pos if-body.
{
  let signDisc = arrowExpr(
    [p("x")],
    cond(
      gte(id("x"), int_(0)),
      obj([("tag", str("Pos")), ("value", id("x"))]),
      obj([("tag", str("Neg")), ("value", neg(id("x")))]),
    ),
  )
  let input = lit(array_([int_(2), int_(-3), int_(4), int_(-1)]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
    opened,
  )
  let posB = branch_(split, "Pos")
  let posDoubled = close_(filter_(posB), app(double, [posB]))
  let posSquared = close_(
    filter_(posB),
    app(arrowExpr([p("x")], mul(id("x"), id("x"))), [posB]),
  )
  runTest(
    ~name="multi-filter: same alt, two parallel outputs (doubled + squared)",
    ~expr=app(bundle2("doubled", "squared"), [posDoubled, posSquared]),
    ~expected=obj([
      ("doubled", array_([int_(4), int_(8)])),
      ("squared", array_([int_(4), int_(16)])),
    ]),
  )
}

// (7) Mixing — filter and exhaustive case-close on the SAME
//     case-split. The case-close produces a per-iteration value
//     (doubled if Just, 0 if Nothing); a list close on the outer
//     iter pushes that per-iter value into a "doubled" array. The
//     filter close on the same case-split's Just alt also pushes
//     the just-values into a separate "justs" array. One discriminator
//     call, one if/else-if chain shared by both, one for-of loop.
{
  let input = lit(array_([
    obj([("tag", str("Just")), ("value", int_(1))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(5))]),
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Just")), ("value", int_(3))]),
  ]))
  let opened = open_(ListIter, input)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened,
  )
  let justB = branch_(split, "Just")
  let nothingB = branch_(split, "Nothing")
  let perIter = caseClose([
    {altName: Some("Just"), flow: justB, value: app(double, [justB])},
    {altName: Some("Nothing"), flow: nothingB, value: lit(int_(0))},
  ])
  let doubledList = close_(opened, perIter)
  let justsList = close_(filter_(justB), justB)
  runTest(
    ~name="mix: case-close + filter on same case-split (doubled vs justs)",
    ~expr=app(bundle2("doubled", "justs"), [doubledList, justsList]),
    ~expected=obj([
      ("doubled", array_([int_(2), int_(0), int_(10), int_(0), int_(6)])),
      ("justs", array_([int_(1), int_(5), int_(3)])),
    ]),
  )
}

Console.log("==== Summary ====")
Console.log(
  Int.toString(passCount.contents) ++
  " passed, " ++
  Int.toString(failCount.contents) ++ " failed",
)
