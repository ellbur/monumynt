// The emitted runtime: the prelude every compiled output carries, plus the
// builders generated code uses to reference it.
//
// Today this is the eager fragment's three lazy helpers — the piece of the
// runtime that compile-strategy-design.md says survives every later growth of
// the compiler.
//
// Growth: when stream cells land (Delayed with iterative force, zipStream,
// cell constructors — lazy-stream-* design docs), they are added HERE, and
// at that point the prelude stops being three lines and the packaging
// question becomes real: inline prelude per output (self-contained, as
// today) vs an imported runtime module (compile-strategy-design.md, open
// question 3 — interacts with the test runner's eval harness).
//
// The growth is planned as stub prelude builders, in the recorded
// dependency order: Stream.streamPreludeStmts (Delayed/stream/zipStream/
// listToStream, with the two hard requirements — iterative force and path
// compression), then Async.asyncPreludeStmts (__asyncCell__/__startAsync__;
// later the frontier's strand event, the one new piece cancellation needs),
// then Incremental.incrementalPreludeStmts (root/derived cells + the
// generation word). Registers need no runtime at all — they compile to a
// `let` in the loop skeleton.

// --- Builders for referencing the runtime from generated code -------------

// __lazy__(() => { ...stmts })
let lazyOf = (thunk: array<JsAst.stmt>): JsAst.expr =>
  JsBuild.call(JsBuild.id("__lazy__"), [JsBuild.arrow([], thunk)])

// __lazy__(() => expr) — single-expression thunk, keeps the JS readable.
let lazyOfExpr = (e: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__lazy__"), [JsBuild.arrowExpr([], e)])

let lazyDoneOf = (v: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__lazyDone__"), [v])

let forceOf = (v: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__force__"), [v])

// --- The prelude ----------------------------------------------------------

let preludeStmts: array<JsAst.stmt> = [
  // const __lazy__ = (t) => ({v: undefined, t, c: false});
  JsBuild.const(
    "__lazy__",
    JsBuild.arrowExpr(
      [JsBuild.p("t")],
      JsBuild.obj([
        ("v", JsBuild.undefined),
        ("t", JsBuild.id("t")),
        ("c", JsBuild.bool_(false)),
      ]),
    ),
  ),
  // const __lazyDone__ = (v) => ({v, t: null, c: true});
  JsBuild.const(
    "__lazyDone__",
    JsBuild.arrowExpr(
      [JsBuild.p("v")],
      JsBuild.obj([
        ("v", JsBuild.id("v")),
        ("t", JsBuild.null),
        ("c", JsBuild.bool_(true)),
      ]),
    ),
  ),
  // const __force__ = (z) => {
  //   if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }
  //   return z.v;
  // };
  JsBuild.const(
    "__force__",
    JsBuild.arrow(
      [JsBuild.p("z")],
      [
        JsBuild.if_(
          JsBuild.not_(JsBuild.member(JsBuild.id("z"), "c")),
          [
            JsBuild.exprStmt(
              JsBuild.assign(
                JsBuild.member(JsBuild.id("z"), "v"),
                JsBuild.call(JsBuild.member(JsBuild.id("z"), "t"), []),
              ),
            ),
            JsBuild.exprStmt(
              JsBuild.assign(JsBuild.member(JsBuild.id("z"), "t"), JsBuild.null),
            ),
            JsBuild.exprStmt(
              JsBuild.assign(JsBuild.member(JsBuild.id("z"), "c"), JsBuild.bool_(true)),
            ),
          ],
        ),
        JsBuild.ret(JsBuild.member(JsBuild.id("z"), "v")),
      ],
    ),
  ),
]
