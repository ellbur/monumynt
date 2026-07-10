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
//
// Tests build programs through the smart-constructor handles: `x.value`
// wires a node's value port, `NodeFlow(x.node)` its flow port.

open JsBuild
open Expr

@val external evalJs: string => 'a = "eval"
@val external jsonStringify: 'a => string = "JSON.stringify"

let evalExpression = (code: string): 'a => evalJs("(" ++ code ++ ")")

let passCount = ref(0)
let failCount = ref(0)

let runTest = (~name: string, ~expr: Expr.handle, ~expected: JsAst.expr) => {
  let (stmts, _) = Compile.compileToBody(expr.node)
  let stmtCount = Array.length(stmts)
  let exprRendering = ExprPrint.render(expr.node)
  let iife = Compile.compileToIIFE(expr.node)
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

let litI = (n: int): Expr.handle => lit(int_(n))
let litS = (s: string): Expr.handle => lit(str(s))
let litB = (b: bool): Expr.handle => lit(bool_(b))

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
  ~expr=app(jsAdd, [litI(2).value, litI(3).value]),
  ~expected=int_(5),
)
runTest(
  ~name="Math.sqrt(16)",
  ~expr=app(mathSqrt, [litI(16).value]),
  ~expected=int_(4),
)
runTest(
  ~name="Math.max(3, 7, 2, 5)",
  ~expr=app(mathMax, [litI(3).value, litI(7).value, litI(2).value, litI(5).value]),
  ~expected=int_(7),
)
runTest(
  ~name="Math.abs(-42)",
  ~expr=app(mathAbs, [litI(-42).value]),
  ~expected=int_(42),
)
runTest(
  ~name="string concat",
  ~expr=app(jsConcat, [litS("hello ").value, litS("world").value]),
  ~expected=str("hello world"),
)
runTest(
  ~name="Array.of(1, 2, 3)",
  ~expr=app(arrayOf, [litI(1).value, litI(2).value, litI(3).value]),
  ~expected=array_([int_(1), int_(2), int_(3)]),
)
runTest(
  ~name="makePoint(3, 4)",
  ~expr=app(makePoint, [litI(3).value, litI(4).value]),
  ~expected=obj([("x", int_(3)), ("y", int_(4))]),
)
runTest(
  ~name="2*3 + 4*5",
  ~expr=app(jsAdd, [
    app(jsMul, [litI(2).value, litI(3).value]).value,
    app(jsMul, [litI(4).value, litI(5).value]).value,
  ]),
  ~expected=int_(26),
)
runTest(
  ~name="sqrt(7 + 9)",
  ~expr=app(mathSqrt, [app(jsAdd, [litI(7).value, litI(9).value]).value]),
  ~expected=int_(4),
)
runTest(
  ~name="Math.pow(2, 8)",
  ~expr=app(mathPow, [litI(2).value, litI(8).value]),
  ~expected=int_(256),
)
runTest(
  ~name="sqrt(3*3 + 4*4)",
  ~expr=app(mathSqrt, [
    app(jsAdd, [
      app(jsMul, [litI(3).value, litI(3).value]).value,
      app(jsMul, [litI(4).value, litI(4).value]).value,
    ]).value,
  ]),
  ~expected=int_(5),
)
runTest(
  ~name="minOfTwo(minOfTwo(7, 4), 10)",
  ~expr=app(jsMinOfTwo, [
    app(jsMinOfTwo, [litI(7).value, litI(4).value]).value,
    litI(10).value,
  ]),
  ~expected=int_(4),
)
runTest(
  ~name="sub(5, 8) -> -3",
  ~expr=app(jsSub, [litI(5).value, litI(8).value]),
  ~expected=int_(-3),
)

let getX = arrowExpr([p("p")], member(id("p"), "x"))
runTest(
  ~name="getX(makePoint(add(1, 2), add(3, 4)))",
  ~expr=app(getX, [
    app(makePoint, [
      app(jsAdd, [litI(1).value, litI(2).value]).value,
      app(jsAdd, [litI(3).value, litI(4).value]).value,
    ]).value,
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
    app(jsMul, [litI(2).value, litI(3).value]).value,
    app(jsMul, [litI(2).value, litI(3).value]).value,
  ]),
  ~expected=int_(12),
)

// (1') Same expression, but 2*3 built once and shared as both args.
{
  let twoThree = app(jsMul, [litI(2).value, litI(3).value])
  runTest(
    ~name="shared: (2*3) + (2*3) — single 2*3 bound and reused",
    ~expr=app(jsAdd, [twoThree.value, twoThree.value]),
    ~expected=int_(12),
  )
}

// (2) Diamond: a literal node feeds two siblings of an outer node.
{
  let x = litI(7)
  runTest(
    ~name="diamond: add(x, x) where x = lit(7)",
    ~expr=app(jsAdd, [x.value, x.value]),
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
    ~expr=app(triple, [x.value, x.value, x.value]),
    ~expected=int_(15),
  )
}

// (4) A non-trivial shared literal: Math.PI used twice.
{
  let pi = lit(member(id("Math"), "PI"))
  runTest(
    ~name="shared Math.PI: Math.PI + Math.PI",
    ~expr=app(jsAdd, [pi.value, pi.value]),
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
  let rsq = app(jsMul, [r.value, r.value])
  let area = app(jsMul, [pi.value, rsq.value])
  let twoPi = app(jsMul, [two.value, pi.value])
  let circumference = app(jsMul, [twoPi.value, r.value])
  runTest(
    ~name="circle metrics: area and circumference share pi and r",
    ~expr=app(bundle2("area", "circ"), [area.value, circumference.value]),
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
  let leaf = app(jsMul, [litI(2).value, litI(3).value]) // = 6, computed once
  let plusOne = arrowExpr([p("a")], add(id("a"), int_(1)))
  let timesTwo = arrowExpr([p("a")], mul(id("a"), int_(2)))
  let combine = arrowExpr(
    [p("a"), p("b"), p("c")],
    add(id("a"), add(id("b"), id("c"))),
  )
  runTest(
    ~name="deep diamond: combine(leaf, plusOne(leaf), timesTwo(leaf))",
    ~expr=app(combine, [
      leaf.value,
      app(plusOne, [leaf.value]).value,
      app(timesTwo, [leaf.value]).value,
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
  let opened = open_(ListIter, input.value)
  runTest(
    ~name="list iter: identity map of [1,2,3]",
    ~expr=close_(NodeFlow(opened.node), opened.value),
    ~expected=array_([int_(1), int_(2), int_(3)]),
  )
}

// (2) Map double — a single transformation applied per element.
let double = arrowExpr([p("x")], mul(id("x"), int_(2)))
{
  let input = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, input.value)
  runTest(
    ~name="list iter: map double over [1,2,3]",
    ~expr=close_(NodeFlow(opened.node), app(double, [opened.value]).value),
    ~expected=array_([int_(2), int_(4), int_(6)]),
  )
}

// (3) Empty input — the loop body simply doesn't run.
{
  let input = lit(array_([]))
  let opened = open_(ListIter, input.value)
  runTest(
    ~name="list iter: map double over []",
    ~expr=close_(NodeFlow(opened.node), app(double, [opened.value]).value),
    ~expected=array_([]),
  )
}

// (4) Element shared inside the loop body — the per-iteration element is
//     used twice in `square = elem * elem`. The `square` binding lives
//     inside the loop, but the element is referenced (not recomputed) for
//     each use.
{
  let input = lit(array_([int_(2), int_(3), int_(4)]))
  let opened = open_(ListIter, input.value)
  let square = app(jsMul, [opened.value, opened.value])
  runTest(
    ~name="list iter: square — element shared inside body",
    ~expr=close_(NodeFlow(opened.node), square.value),
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
  let opened = open_(ListIter, input.value)
  let ten = lit(int_(10))
  runTest(
    ~name="list iter: loop-invariant constant hoisted out",
    ~expr=close_(
      NodeFlow(opened.node),
      app(jsAdd, [ten.value, opened.value]).value,
    ),
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
  let opened = open_(ListIter, input.value)
  let mapped = close_(
    NodeFlow(opened.node),
    app(jsAdd, [k.value, opened.value]).value,
  )
  runTest(
    ~name="list iter: shared k=100 used both inside and outside loop",
    ~expr=app(bundle2("base", "mapped"), [k.value, mapped.value]),
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
  let opened = open_(ListIter, input.value)
  let mapped = close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  runTest(
    ~name="list iter: post-process — length of mapped result",
    ~expr=app(lengthOf, [mapped.value]),
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
  let opened = open_(ListIter, input.value)
  let doubled = close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  let tripled = close_(NodeFlow(opened.node), app(triple, [opened.value]).value)
  runTest(
    ~name="multi-close: doubled and tripled, one loop two pushes",
    ~expr=app(bundle2("doubled", "tripled"), [doubled.value, tripled.value]),
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
  let opened = open_(ListIter, input.value)
  let asIs = close_(NodeFlow(opened.node), opened.value)
  let dbl = close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  let inc = close_(NodeFlow(opened.node), app(plusOne, [opened.value]).value)
  runTest(
    ~name="multi-close: identity + double + +1, one loop three pushes",
    ~expr=app(bundle3("a", "b", "c"), [asIs.value, dbl.value, inc.value]),
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
  let opened = open_(ListIter, input.value)
  let square = app(jsMul, [opened.value, opened.value])
  let one = lit(int_(1))
  let two = lit(int_(2))
  let close1 = close_(
    NodeFlow(opened.node),
    app(jsAdd, [square.value, one.value]).value,
  )
  let close2 = close_(
    NodeFlow(opened.node),
    app(jsMul, [square.value, two.value]).value,
  )
  runTest(
    ~name="multi-close: shared intermediate (square computed once per iter)",
    ~expr=app(bundle2("plusOne", "timesTwo"), [close1.value, close2.value]),
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
  let opened = open_(ListIter, input.value)
  let ten = lit(int_(10))
  let hundred = lit(int_(100))
  let plus10 = close_(
    NodeFlow(opened.node),
    app(jsAdd, [ten.value, opened.value]).value,
  )
  let plus100 = close_(
    NodeFlow(opened.node),
    app(jsAdd, [hundred.value, opened.value]).value,
  )
  runTest(
    ~name="multi-close: each Close has its own loop-invariant constant",
    ~expr=app(bundle2("p10", "p100"), [plus10.value, plus100.value]),
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
  let openedA = open_(ListIter, inputA.value)
  let resultA = close_(
    NodeFlow(openedA.node),
    app(double, [openedA.value]).value,
  )
  let inputB = lit(array_([int_(10), int_(20)]))
  let openedB = open_(ListIter, inputB.value)
  let resultB = close_(
    NodeFlow(openedB.node),
    app(triple, [openedB.value]).value,
  )
  runTest(
    ~name="two independent loops in sequence",
    ~expr=app(bundle2("first", "second"), [resultA.value, resultB.value]),
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
  let opened = open_(ListIter, input.value)
  let doubled = close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  let tripled = close_(NodeFlow(opened.node), app(triple, [opened.value]).value)
  runTest(
    ~name="multi-close: one Close used twice downstream + sibling Close",
    ~expr=app(bundle3("d1", "d2", "t"), [
      doubled.value,
      doubled.value,
      tripled.value,
    ]),
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  let innerClosed = close_(
    NodeFlow(innerOpened.node),
    app(double, [innerOpened.value]).value,
  )
  let outerClosed = close_(NodeFlow(outerOpened.node), innerClosed.value)
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  let innerClosed = close_(
    NodeFlow(innerOpened.node),
    app(double, [innerOpened.value]).value,
  )
  let outerClosed = close_(NodeFlow(outerOpened.node), innerClosed.value)
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  let innerDoubled = close_(
    NodeFlow(innerOpened.node),
    app(double, [innerOpened.value]).value,
  )
  let innerTripled = close_(
    NodeFlow(innerOpened.node),
    app(triple, [innerOpened.value]).value,
  )
  let perOuter = app(bundle2("d", "t"), [innerDoubled.value, innerTripled.value])
  let outerClosed = close_(NodeFlow(outerOpened.node), perOuter.value)
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  runTest(
    ~name="join: nested map flattened — [[1,2],[3,4]] -> [2,4,6,8]",
    ~expr=close_(
      join_(NodeFlow(innerOpened.node)),
      app(double, [innerOpened.value]).value,
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  runTest(
    ~name="join: flatten of [[1,2],[],[3]] -> [1,2,3]",
    ~expr=close_(join_(NodeFlow(innerOpened.node)), innerOpened.value),
    ~expected=array_([int_(1), int_(2), int_(3)]),
  )
}

// (3) Empty outer — no inner iterations happen at all, result is [].
{
  let input = lit(array_([]))
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  runTest(
    ~name="join: empty outer -> []",
    ~expr=close_(join_(NodeFlow(innerOpened.node)), innerOpened.value),
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
  let outerOpened = open_(ListIter, input.value)
  let innerOpened = open_(ListIter, outerOpened.value)
  let ten = lit(int_(10))
  runTest(
    ~name="join: with hoisted constant — flat list of x+10",
    ~expr=close_(
      join_(NodeFlow(innerOpened.node)),
      app(jsAdd, [ten.value, innerOpened.value]).value,
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
  let l1 = open_(ListIter, input.value)
  let l2 = open_(ListIter, l1.value)
  let l3 = open_(ListIter, l2.value)
  runTest(
    ~name="join x2: flatten of [[[1,2],[3]],[[4]]] mapped *2 -> [2,4,6,8]",
    ~expr=close_(
      join_(join_(NodeFlow(l3.node))),
      app(double, [l3.value]).value,
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
  let openOuter1 = open_(ListIter, input.value)
  let openInner1 = open_(ListIter, openOuter1.value)
  let nested = close_(
    NodeFlow(openOuter1.node),
    close_(
      NodeFlow(openInner1.node),
      app(double, [openInner1.value]).value,
    ).value,
  )
  let openOuter2 = open_(ListIter, input.value)
  let openInner2 = open_(ListIter, openOuter2.value)
  let flat = close_(
    join_(NodeFlow(openInner2.node)),
    app(double, [openInner2.value]).value,
  )
  runTest(
    ~name="join vs nested side-by-side on the same input",
    ~expr=app(bundle2("nested", "flat"), [nested.value, flat.value]),
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
  let outer = open_(ListIter, input.value)
  let inner = open_(ListIter, outer.value)
  let unjoined = close_(NodeFlow(inner.node), app(double, [inner.value]).value)
  let flat = close_(
    join_(NodeFlow(inner.node)),
    app(double, [inner.value]).value,
  )
  let nested = close_(NodeFlow(outer.node), unjoined.value)
  runTest(
    ~name="mixed: unjoined + joined on one opener; nested wraps unjoined",
    ~expr=app(bundle2("nested", "flat"), [nested.value, flat.value]),
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
  let outer = open_(ListIter, input.value)
  let inner = open_(ListIter, outer.value)
  let body = app(double, [inner.value]) // shared between both closes
  let unjoined = close_(NodeFlow(inner.node), body.value)
  let flat = close_(join_(NodeFlow(inner.node)), body.value)
  let nested = close_(NodeFlow(outer.node), unjoined.value)
  runTest(
    ~name="mixed (shared body): one double per iter, two pushes",
    ~expr=app(bundle2("nested", "flat"), [nested.value, flat.value]),
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
let maybeDouble = (input: JsAst.expr): Expr.handle => {
  let inputE = lit(input)
  let opened = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE.value,
  )
  let justB = branch_(NodeFlow(opened.node), "Just")
  let nothingB = branch_(NodeFlow(opened.node), "Nothing")
  caseClose([
    {
      altName: Some("Just"),
      flow: NodeFlow(justB.node),
      value: app(double, [justB.value]).value,
    },
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(int_(0)).value,
    },
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
    inputE.value,
  )
  let leftB = branch_(NodeFlow(opened.node), "Left")
  let rightB = branch_(NodeFlow(opened.node), "Right")
  let lengthFn = arrowExpr([p("s")], member(id("s"), "length"))
  runTest(
    ~name="case-split: Either<string,int> — Left.length / Right * 2",
    ~expr=caseClose([
      {
        altName: Some("Left"),
        flow: NodeFlow(leftB.node),
        value: app(lengthFn, [leftB.value]).value,
      },
      {
        altName: Some("Right"),
        flow: NodeFlow(rightB.node),
        value: app(double, [rightB.value]).value,
      },
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
    inputE.value,
  )
  let justB = branch_(NodeFlow(opened.node), "Just")
  let nothingB = branch_(NodeFlow(opened.node), "Nothing")
  let valOrZero = caseClose([
    {altName: Some("Just"), flow: NodeFlow(justB.node), value: justB.value},
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(int_(0)).value,
    },
  ])
  let tagOnly = caseClose([
    {
      altName: Some("Just"),
      flow: NodeFlow(justB.node),
      value: lit(str("present")).value,
    },
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(str("absent")).value,
    },
  ])
  runTest(
    ~name="case-split: multi-close — value-or-zero + tag",
    ~expr=app(bundle2("v", "tag"), [valOrZero.value, tagOnly.value]),
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
  let mkProg = (n: int): Expr.handle => {
    let inputE = lit(int_(n))
    let opened = open_(
      CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
      inputE.value,
    )
    let posB = branch_(NodeFlow(opened.node), "Pos")
    let negB = branch_(NodeFlow(opened.node), "Neg")
    let square = arrowExpr([p("x")], mul(id("x"), id("x")))
    caseClose([
      {
        altName: Some("Pos"),
        flow: NodeFlow(posB.node),
        value: app(square, [posB.value]).value,
      },
      // -x is already in the value port via the disc
      {altName: Some("Neg"), flow: NodeFlow(negB.node), value: negB.value},
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
  let opened = open_(ListIter, input.value)
  // Per element: case-split.
  let inner = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(inner.node), "Just")
  let nothingB = branch_(NodeFlow(inner.node), "Nothing")
  let perElemResult = caseClose([
    {
      altName: Some("Just"),
      flow: NodeFlow(justB.node),
      value: app(double, [justB.value]).value,
    },
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(int_(0)).value,
    },
  ])
  runTest(
    ~name="case-split inside list iter: [Just(1), Nothing, Just(5)] -> [2, 0, 10]",
    ~expr=close_(NodeFlow(opened.node), perElemResult.value),
    ~expected=array_([int_(2), int_(0), int_(10)]),
  )
}

// (6) Shared computation across branches: both branches reference a
//     value computed once outside the if. Verify it's emitted once at
//     the parent scope.
{
  let inputE = lit(obj([("tag", str("Just")), ("value", int_(10))]))
  let bonus = lit(int_(100)) // shared between Just and Nothing
  let opened = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inputE.value,
  )
  let justB = branch_(NodeFlow(opened.node), "Just")
  let nothingB = branch_(NodeFlow(opened.node), "Nothing")
  runTest(
    ~name="case-split: shared `bonus` used in both branches",
    ~expr=caseClose([
      {
        altName: Some("Just"),
        flow: NodeFlow(justB.node),
        value: app(jsAdd, [justB.value, bonus.value]).value,
      },
      {
        altName: Some("Nothing"),
        flow: NodeFlow(nothingB.node),
        value: bonus.value,
      },
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
    inputE.value,
  )
  let justB = branch_(NodeFlow(outerSplit.node), "Just")
  let nothingB = branch_(NodeFlow(outerSplit.node), "Nothing")
  // Inside Just: split again.
  let innerSplit = open_(
    CaseSplit({alts: ["Left", "Right"], discriminator: identity}),
    justB.value,
  )
  let leftB = branch_(NodeFlow(innerSplit.node), "Left")
  let rightB = branch_(NodeFlow(innerSplit.node), "Right")
  let innerResult = caseClose([
    {
      altName: Some("Left"),
      flow: NodeFlow(leftB.node),
      value: lit(int_(-1)).value,
    },
    {
      altName: Some("Right"),
      flow: NodeFlow(rightB.node),
      value: app(double, [rightB.value]).value,
    },
  ])
  let outerResult = caseClose([
    {
      altName: Some("Just"),
      flow: NodeFlow(justB.node),
      value: innerResult.value,
    },
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(int_(0)).value,
    },
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  runTest(
    ~name="filter: keep only Justs, doubled",
    ~expr=close_(
      filter_(NodeFlow(justB.node)),
      app(double, [justB.value]).value,
    ),
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  runTest(
    ~name="filter: identity — extract Just values",
    ~expr=close_(filter_(NodeFlow(justB.node)), justB.value),
    ~expected=array_([int_(7), int_(11)]),
  )
}

// (3) Filter with no matches: input has no Justs.
{
  let input = lit(array_([
    obj([("tag", str("Nothing"))]),
    obj([("tag", str("Nothing"))]),
  ]))
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  runTest(
    ~name="filter: no Justs in input -> []",
    ~expr=close_(
      filter_(NodeFlow(justB.node)),
      app(double, [justB.value]).value,
    ),
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
    opened.value,
  )
  let posB = branch_(NodeFlow(split.node), "Pos")
  let square = arrowExpr([p("x")], mul(id("x"), id("x")))
  runTest(
    ~name="filter: positives only, squared (Pos/Neg disc, [3,-2,5,0,-7,4] -> [9,25,0,16])",
    ~expr=close_(
      filter_(NodeFlow(posB.node)),
      app(square, [posB.value]).value,
    ),
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  let nothingB = branch_(NodeFlow(split.node), "Nothing")
  let justs = close_(
    filter_(NodeFlow(justB.node)),
    app(double, [justB.value]).value,
  )
  let nothings = close_(filter_(NodeFlow(nothingB.node)), lit(int_(99)).value)
  runTest(
    ~name="multi-filter: partition Maybes into doubled-Justs and 99-per-Nothing",
    ~expr=app(bundle2("justs", "nothings"), [justs.value, nothings.value]),
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
  let outer = open_(ListIter, input.value)
  let inner = open_(ListIter, outer.value)
  // The case-split sees the inner element. The filter close's flow
  // is Joined(Filtered(...)) — the Joined lifts the output one level
  // up, past the outer list.
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    inner.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  runTest(
    ~name="filter under joined nested lists: flatten + filter Justs, doubled",
    ~expr=close_(
      join_(filter_(NodeFlow(justB.node))),
      app(double, [justB.value]).value,
    ),
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Pos", "Neg"], discriminator: signDisc}),
    opened.value,
  )
  let posB = branch_(NodeFlow(split.node), "Pos")
  let posDoubled = close_(
    filter_(NodeFlow(posB.node)),
    app(double, [posB.value]).value,
  )
  let posSquared = close_(
    filter_(NodeFlow(posB.node)),
    app(arrowExpr([p("x")], mul(id("x"), id("x"))), [posB.value]).value,
  )
  runTest(
    ~name="multi-filter: same alt, two parallel outputs (doubled + squared)",
    ~expr=app(bundle2("doubled", "squared"), [posDoubled.value, posSquared.value]),
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
  let opened = open_(ListIter, input.value)
  let split = open_(
    CaseSplit({alts: ["Just", "Nothing"], discriminator: identity}),
    opened.value,
  )
  let justB = branch_(NodeFlow(split.node), "Just")
  let nothingB = branch_(NodeFlow(split.node), "Nothing")
  let perIter = caseClose([
    {
      altName: Some("Just"),
      flow: NodeFlow(justB.node),
      value: app(double, [justB.value]).value,
    },
    {
      altName: Some("Nothing"),
      flow: NodeFlow(nothingB.node),
      value: lit(int_(0)).value,
    },
  ])
  let doubledList = close_(NodeFlow(opened.node), perIter.value)
  let justsList = close_(filter_(NodeFlow(justB.node)), justB.value)
  runTest(
    ~name="mix: case-close + filter on same case-split (doubled vs justs)",
    ~expr=app(bundle2("doubled", "justs"), [doubledList.value, justsList.value]),
    ~expected=obj([
      ("doubled", array_([int_(2), int_(0), int_(10), int_(0), int_(6)])),
      ("justs", array_([int_(1), int_(5), int_(3)])),
    ]),
  )
}

// =============================================================
// Option-flow tests.
// =============================================================
//
// Open OptionIter takes no extra payload; the input itself is the
// option (undefined for None, anything else for the Some-value).

// (1) Basic option iter: Some(5) → doubled = 10; default via `?? "none"`.
{
  let optClose = (input: JsAst.expr) => {
    let inE = lit(input)
    let opened = open_(OptionIter, inE.value)
    close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  }
  // Wrap to default undefined → "none" so jsonStringify gives a string.
  let withDefault = (closeExpr: Expr.handle) =>
    app(
      arrowExpr([p("v")], nullish(id("v"), str("none"))),
      [closeExpr.value],
    )
  runTest(
    ~name="option iter: Some(5) doubled",
    ~expr=withDefault(optClose(int_(5))),
    ~expected=int_(10),
  )
  runTest(
    ~name="option iter: None (undefined) → 'none'",
    ~expr=withDefault(optClose(undefined)),
    ~expected=str("none"),
  )
}

// (2) Multi-close on one option: doubled and tripled in parallel.
{
  let inE = lit(int_(7))
  let opened = open_(OptionIter, inE.value)
  let doubled = close_(NodeFlow(opened.node), app(double, [opened.value]).value)
  let tripled = close_(NodeFlow(opened.node), app(triple, [opened.value]).value)
  runTest(
    ~name="option iter: multi-close (doubled + tripled from Some(7))",
    ~expr=app(bundle2("d", "t"), [doubled.value, tripled.value]),
    ~expected=obj([("d", int_(14)), ("t", int_(21))]),
  )
}

// (3) Option<Option<X>> joined. Inner option's close, joined, lifts
//     output to outer option's parent. Result is Some only if both
//     outer and inner options fire.
{
  let optOptDoubled = (input: JsAst.expr) => {
    let inE = lit(input)
    let outer = open_(OptionIter, inE.value)
    let inner = open_(OptionIter, outer.value)
    let result = close_(
      join_(NodeFlow(inner.node)),
      app(double, [inner.value]).value,
    )
    app(
      arrowExpr([p("v")], nullish(id("v"), str("none"))),
      [result.value],
    )
  }
  runTest(
    ~name="option<option>: Some(Some(5)) joined-inner doubled → 10",
    ~expr=optOptDoubled(int_(5)),
    ~expected=int_(10),
  )
  runTest(
    ~name="option<option>: Some(undefined) joined-inner → 'none'",
    ~expr=optOptDoubled(undefined),
    ~expected=str("none"),
  )
}

// (4) Option<List<X>> joined: inner list close, joined, lifts output
//     list above the if. Result is List<X> (empty if outer option
//     didn't fire).
{
  let optListDoubled = (input: JsAst.expr) => {
    let inE = lit(input)
    let outer = open_(OptionIter, inE.value)
    let inner = open_(ListIter, outer.value)
    close_(join_(NodeFlow(inner.node)), app(double, [inner.value]).value)
  }
  runTest(
    ~name="option<list>: Some([1,2,3]) joined-inner doubled → [2,4,6]",
    ~expr=optListDoubled(array_([int_(1), int_(2), int_(3)])),
    ~expected=array_([int_(2), int_(4), int_(6)]),
  )
  runTest(
    ~name="option<list>: None joined-inner → []",
    ~expr=optListDoubled(undefined),
    ~expected=array_([]),
  )
}

// (5) List<Option<X>> joined: inner option close, joined past the
//     outer list. Because the chain contains a list, the output is
//     a list — one element per outer iter where the inner option
//     fires, skipped when it doesn't. (Reads like filter-on-option.)
{
  let listOptList = (input: JsAst.expr) => {
    let inE = lit(input)
    let outer = open_(ListIter, inE.value)
    let inner = open_(OptionIter, outer.value)
    close_(join_(NodeFlow(inner.node)), app(double, [inner.value]).value)
  }
  runTest(
    ~name="list<option>: [u,3,u,7,u] joined-inner doubled → [6,14]",
    ~expr=listOptList(array_([undefined, int_(3), undefined, int_(7), undefined])),
    ~expected=array_([int_(6), int_(14)]),
  )
  runTest(
    ~name="list<option>: [u,u,u] joined-inner → []",
    ~expr=listOptList(array_([undefined, undefined, undefined])),
    ~expected=array_([]),
  )
}

// =============================================================
// Consumer-driven placement (sinking) tests.
// =============================================================
//
// These tests check that a value used only inside a conditional
// (option-some body, case-split alt) is sunk into that body, even
// when its inputs would otherwise place it at a shallower scope.

// (1) Per-element expensive computation that's only used inside an
//     option-some body. The "expensive" call takes the outer list's
//     element (loop scope), but its only use is by the option
//     close's per-iter value — so it should sink into the if-body
//     and run only on iterations where the option fires.
{
  // disc: keep only even numbers. Returns x when even, undefined when odd.
  let evenDisc = arrowExpr(
    [p("x")],
    cond(eq(mod_(id("x"), int_(2)), int_(0)), id("x"), undefined),
  )
  let times10 = arrowExpr([p("x")], mul(id("x"), int_(10)))

  let inE = lit(array_([int_(1), int_(2), int_(3), int_(4), int_(5)]))
  let outer = open_(ListIter, inE.value)
  let optOnEven = app(evenDisc, [outer.value])
  let inner = open_(OptionIter, optOnEven.value)
  // The per-iter value uses `outer` (the list elem) directly, NOT
  // `inner` (the option's some-value). Its eager scope is therefore
  // the loop body — the test of sinking is whether the compiler
  // moves the times10 call into the option's if-body, where it's
  // computed only on Some-iters.
  let expensive = app(times10, [outer.value])
  let innerClose = close_(NodeFlow(inner.node), expensive.value)
  // Wrap each per-iter result (some-value or undefined) into a list.
  let outerClose = close_(NodeFlow(outer.node), innerClose.value)
  runTest(
    ~name="sink: per-elem App used only inside option-some sinks into if",
    ~expr=outerClose,
    // Odd elements: option fires None → undefined slot → null in JSON.
    // Even elements: times10 → 20, 40.
    ~expected=array_([null, int_(20), null, int_(40), null]),
  )
}

// (2) The flip side: an App that depends only on outer values but is
//     used inside a loop body MUST NOT sink into the loop (that would
//     turn a once-per-program computation into a once-per-iteration
//     one). The loopDepth cap on the sink pass guarantees this. The
//     generated JS for this test has the `const v_magic = ...` line
//     OUTSIDE the for-of.
{
  let l1 = lit(int_(100))
  let l2 = lit(int_(50))
  let magic = app(jsAdd, [l1.value, l2.value])
  let inE = lit(array_([int_(1), int_(2), int_(3)]))
  let opened = open_(ListIter, inE.value)
  let perIter = app(jsAdd, [magic.value, opened.value])
  runTest(
    ~name="sink: outer-only App used inside loop stays outside (loopDepth cap)",
    ~expr=close_(NodeFlow(opened.node), perIter.value),
    ~expected=array_([int_(151), int_(152), int_(153)]),
  )
}

Console.log("==== Summary ====")
Console.log(
  Int.toString(passCount.contents) ++
  " passed, " ++
  Int.toString(failCount.contents) ++ " failed",
)
