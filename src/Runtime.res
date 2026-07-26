// The emitted runtime: the prelude every compiled output carries, plus the
// builders generated code uses to reference it.
//
// Today this is the eager fragment's three lazy helpers — the piece of the
// runtime that compile-strategy-design.md says survives every later growth of
// the compiler.
//
// The STREAM cells have since landed here too (`streamPreludeStmts` —
// lazy-stream-placement-design.md's implementation step 1), which is where
// the packaging question (compile-strategy-design.md, open question 3) first
// became real: the prelude stops being three lines. The answer taken for now
// is the cheapest honest one — the prelude is still INLINE per output, but a
// LAYER is only emitted when the program uses it, so the eager fragment's
// generated JS is byte-for-byte what it was and a stream program pays for the
// stream cells alone (`Codegen.codegen` picks the layers). An imported runtime
// module stays the target; nothing here presumes against it, since the layers
// are already separate arrays.
//
// Still planned, in the recorded dependency order: Async.asyncPreludeStmts
// (__asyncCell__/__startAsync__; later the frontier's strand event, the one new
// piece cancellation needs), then Incremental.incrementalPreludeStmts
// (root/derived cells + the generation word). Registers need no runtime at all
// — they compile to a `let` in the loop skeleton.

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

// --- Builders for the stream layer ----------------------------------------
//
// `Delayed` is a SECOND cell type beside `__lazy__`, not a replacement: the
// eager layer's cell answers "compute at most once", the stream layer's cell
// answers that *and* "my result may be another cell" (the redirect a
// become-the-rest step produces). Keeping them apart is what lets a stream
// value sit inside the eager layer unchanged — a stream is just a value, and
// the collect that builds one is a `__lazy__` binding like every other node.

// __delayed__(() => value) — a memoised cell whose thunk yields a VALUE.
let delayedOf = (e: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__delayed__"), [JsBuild.arrowExpr([], e)])

// __ready__(v) — an already-resolved cell.
let readyOf = (v: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__ready__"), [v])

let forceDOf = (d: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__forceD__"), [d])

// __dflatMap__(d, f) — derivation: f's result is another cell (a redirect).
let dFlatMapOf = (d: JsAst.expr, f: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__dflatMap__"), [d, f])

// __dflatMap__(rest, (s) => s) — collapse the fold's one-Delayed-deep `rest`
// into the continuation a stage returns (the sketches' `rest->flatMap(s => s)`).
let restOf = (rest: JsAst.expr): JsAst.expr =>
  dFlatMapOf(rest, JsBuild.arrowExpr([JsBuild.p("s")], JsBuild.id("s")))

let sconsOf = (h: JsAst.expr, t: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__scons__"), [h, t])

let snil: JsAst.expr = JsBuild.id("__snil__")

let zipStreamOf = (source: JsAst.expr, atNil: JsAst.expr, atCons: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__zipStream__"), [source, atNil, atCons])

// __listToStream__(a) — the bridge for a list-valued source (the design's
// own primitive: "listToStream(list) — bridge for list-valued sources").
let listToStreamOf = (a: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__listToStream__"), [a])

let streamToArrayOf = (s: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__streamToArray__"), [s])

let streamTakeOf = (s: JsAst.expr, n: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__streamTake__"), [s, n])

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

// --- The stream layer (lazy-stream-placement-design.md, step 1) -------------
//
// The prototype's cells, SYNCHRONOUS: no promise, no `tick()`, no event-loop
// integration. Stripping `tick()` is what *creates* the stack hazard the doc
// names, so both of its hard requirements land right here, in the primitive
// rather than in any stage:
//
//   (a) ITERATIVE FORCE. A become-the-rest step returns another cell (a
//       REDIRECT), and a run of K skipped elements nests K of them. `__forceD__`
//       follows redirects in a `while` loop — the standard lazy-runtime
//       indirection-following loop — so a sparse filter over a long source
//       costs O(K) time and O(1) stack instead of O(K) stack.
//   (b) PATH COMPRESSION. While walking, every visited redirect cell is
//       rewritten to the final result, so a retained reference into a skipped
//       run does not keep O(K) indirection objects alive along with it.
//
// A cell is `{s, v, t, r}`:
//   s = 0 unforced (t is the thunk) | 1 in progress | 2 done (v is the value)
//     | 3 redirect (v is the cell to continue at)
//   r = does this cell's thunk yield another cell (a redirect) or a value?
// The in-progress state is not decoration: a self-referential stream would
// otherwise spin, and the design's open question 1 (recursive streams) is
// exactly the shape that would reach it. Today it is a diagnosed error.
//
// A stream is the prototype's two constructors and no more — `SFail` / a
// tagged end is a SETTLED REJECTION as a laziness trick for commute
// (lazy-stream-commute-design.md); the failable terminator is Async's, and a
// different proposal:
//   __snil__            the empty stream (one shared object — it carries no
//                       payload, so identity is free)
//   __scons__(h, t)     head value, `t` a Delayed<stream> tail
//
// The two ends of the eager bridge (`__listToStream__` / `__streamToArray__`,
// `__streamTake__`) are runtime, not language: whether list↔stream conversion
// is a drawable CONSTRUCT is a separate design question the placement doc
// explicitly parks ("Eager–stream interaction … a separate design question").
// `__listToStream__` is the one the doc does name, as the bridge a list-valued
// source opens through; the other two are how a stream-valued output is
// observed (the smoke suite reads a stream by taking a prefix, which is also
// how it *measures* the on-demand pull).
let streamPreludeStmts: array<JsAst.stmt> = {
  let cell = (s: JsAst.expr, v: JsAst.expr, t: JsAst.expr, r: JsAst.expr) =>
    JsBuild.obj([("s", s), ("v", v), ("t", t), ("r", r)])
  let f = (o: string, p: string) => JsBuild.member(JsBuild.id(o), p)
  let set = (o: string, p: string, v: JsAst.expr) =>
    JsBuild.exprStmt(JsBuild.assign(f(o, p), v))
  [
    // const __delayed__ = (t) => ({s: 0, v: undefined, t, r: false});
    JsBuild.const(
      "__delayed__",
      JsBuild.arrowExpr(
        [JsBuild.p("t")],
        cell(JsBuild.int_(0), JsBuild.undefined, JsBuild.id("t"), JsBuild.bool_(false)),
      ),
    ),
    // const __delayedR__ = (t) => ({s: 0, v: undefined, t, r: true});
    JsBuild.const(
      "__delayedR__",
      JsBuild.arrowExpr(
        [JsBuild.p("t")],
        cell(JsBuild.int_(0), JsBuild.undefined, JsBuild.id("t"), JsBuild.bool_(true)),
      ),
    ),
    // const __ready__ = (v) => ({s: 2, v, t: null, r: false});
    JsBuild.const(
      "__ready__",
      JsBuild.arrowExpr(
        [JsBuild.p("v")],
        cell(JsBuild.int_(2), JsBuild.id("v"), JsBuild.null, JsBuild.bool_(false)),
      ),
    ),
    // const __forceD__ = (d) => { ...iterative walk, then path-compress... };
    JsBuild.const(
      "__forceD__",
      JsBuild.arrow(
        [JsBuild.p("d")],
        [
          JsBuild.const("path", JsBuild.array_([])),
          JsBuild.let_("cur", JsBuild.id("d")),
          JsBuild.while_(
            JsBuild.bool_(true),
            [
              JsBuild.if_(JsBuild.eq(f("cur", "s"), JsBuild.int_(2)), [JsAst.SBreak(None)]),
              JsBuild.if_(
                JsBuild.eq(f("cur", "s"), JsBuild.int_(3)),
                [
                  JsBuild.exprStmt(
                    JsBuild.call(JsBuild.member(JsBuild.id("path"), "push"), [JsBuild.id("cur")]),
                  ),
                  JsBuild.exprStmt(JsBuild.assign(JsBuild.id("cur"), f("cur", "v"))),
                  JsAst.SContinue(None),
                ],
              ),
              JsBuild.if_(
                JsBuild.eq(f("cur", "s"), JsBuild.int_(1)),
                [
                  JsBuild.throw_(
                    JsBuild.new_(
                      JsBuild.id("Error"),
                      [JsBuild.str("__forceD__: cyclic stream cell")],
                    ),
                  ),
                ],
              ),
              set("cur", "s", JsBuild.int_(1)),
              JsBuild.const("out", JsBuild.call(f("cur", "t"), [])),
              set("cur", "t", JsBuild.null),
              JsBuild.ifElse(
                f("cur", "r"),
                [
                  set("cur", "s", JsBuild.int_(3)),
                  set("cur", "v", JsBuild.id("out")),
                  JsBuild.exprStmt(
                    JsBuild.call(JsBuild.member(JsBuild.id("path"), "push"), [JsBuild.id("cur")]),
                  ),
                  JsBuild.exprStmt(JsBuild.assign(JsBuild.id("cur"), JsBuild.id("out"))),
                ],
                [set("cur", "s", JsBuild.int_(2)), set("cur", "v", JsBuild.id("out"))],
              ),
            ],
          ),
          JsBuild.const("val", f("cur", "v")),
          JsBuild.forOf(
            "c",
            JsBuild.id("path"),
            [set("c", "s", JsBuild.int_(2)), set("c", "v", JsBuild.id("val")), set("c", "t", JsBuild.null)],
          ),
          JsBuild.ret(JsBuild.id("val")),
        ],
      ),
    ),
    // const __dmap__ = (d, f) => __delayed__(() => f(__forceD__(d)));
    JsBuild.const(
      "__dmap__",
      JsBuild.arrowExpr(
        [JsBuild.p("d"), JsBuild.p("f")],
        JsBuild.call(
          JsBuild.id("__delayed__"),
          [
            JsBuild.arrowExpr(
              [],
              JsBuild.call(JsBuild.id("f"), [forceDOf(JsBuild.id("d"))]),
            ),
          ],
        ),
      ),
    ),
    // const __dflatMap__ = (d, f) => __delayedR__(() => f(__forceD__(d)));
    JsBuild.const(
      "__dflatMap__",
      JsBuild.arrowExpr(
        [JsBuild.p("d"), JsBuild.p("f")],
        JsBuild.call(
          JsBuild.id("__delayedR__"),
          [
            JsBuild.arrowExpr(
              [],
              JsBuild.call(JsBuild.id("f"), [forceDOf(JsBuild.id("d"))]),
            ),
          ],
        ),
      ),
    ),
    // const __snil__ = {n: true, h: undefined, t: null};
    JsBuild.const(
      "__snil__",
      JsBuild.obj([("n", JsBuild.bool_(true)), ("h", JsBuild.undefined), ("t", JsBuild.null)]),
    ),
    // const __scons__ = (h, t) => ({n: false, h, t});
    JsBuild.const(
      "__scons__",
      JsBuild.arrowExpr(
        [JsBuild.p("h"), JsBuild.p("t")],
        JsBuild.obj([("n", JsBuild.bool_(false)), ("h", JsBuild.id("h")), ("t", JsBuild.id("t"))]),
      ),
    ),
    // const __zipStream__ = (s, atNil, atCons) => __delayedR__(() => {
    //   const c = __forceD__(s);
    //   return c.n ? atNil : atCons(c.h, __ready__(__zipStream__(c.t, atNil, atCons)));
    // });
    // `rest` is handed to atCons ONE DELAYED LAYER DEEP so a stage may decline to
    // continue at all (abandon-the-rest); emit-and-continue and become-the-rest
    // collapse it with `__dflatMap__(rest, s => s)`. All three of the design's
    // runtime moves are that one primitive — "a fold step may continue with any
    // Delayed continuation, not just a cons of its own making".
    JsBuild.const(
      "__zipStream__",
      JsBuild.arrowExpr(
        [JsBuild.p("s"), JsBuild.p("atNil"), JsBuild.p("atCons")],
        JsBuild.call(
          JsBuild.id("__delayedR__"),
          [
            JsBuild.arrow(
              [],
              [
                JsBuild.const("c", forceDOf(JsBuild.id("s"))),
                JsBuild.ret(
                  JsBuild.cond(
                    f("c", "n"),
                    JsBuild.id("atNil"),
                    JsBuild.call(
                      JsBuild.id("atCons"),
                      [
                        f("c", "h"),
                        readyOf(
                          zipStreamOf(f("c", "t"), JsBuild.id("atNil"), JsBuild.id("atCons")),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    // const __listToStream__ = (a) => {
    //   const go = (i) => i >= a.length ? __snil__ : __scons__(a[i], __delayed__(() => go(i + 1)));
    //   return go(0);
    // };
    JsBuild.const(
      "__listToStream__",
      JsBuild.arrow(
        [JsBuild.p("a")],
        [
          JsBuild.const(
            "go",
            JsBuild.arrowExpr(
              [JsBuild.p("i")],
              JsBuild.cond(
                JsBuild.gte(JsBuild.id("i"), JsBuild.member(JsBuild.id("a"), "length")),
                snil,
                sconsOf(
                  JsBuild.index(JsBuild.id("a"), JsBuild.id("i")),
                  delayedOf(JsBuild.call(JsBuild.id("go"), [JsBuild.add(JsBuild.id("i"), JsBuild.int_(1))])),
                ),
              ),
            ),
          ),
          JsBuild.ret(JsBuild.call(JsBuild.id("go"), [JsBuild.int_(0)])),
        ],
      ),
    ),
    // const __streamTake__ = (s, n) => {
    //   const out = []; let c = s; let k = n;
    //   while (k > 0 && !c.n) { out.push(c.h); k = k - 1; if (k > 0) { c = __forceD__(c.t); } }
    //   return out;
    // };
    // The `if (k > 0)` is load-bearing: holding cell K means value K is already
    // computed (that is what `SCons(value, Delayed<tail>)` says), so taking n
    // elements must not step to cell n and compute one more than it was asked for.
    JsBuild.const(
      "__streamTake__",
      JsBuild.arrow(
        [JsBuild.p("s"), JsBuild.p("n")],
        [
          JsBuild.const("out", JsBuild.array_([])),
          JsBuild.let_("c", JsBuild.id("s")),
          JsBuild.let_("k", JsBuild.id("n")),
          JsBuild.while_(
            JsBuild.and_(JsBuild.gt(JsBuild.id("k"), JsBuild.int_(0)), JsBuild.not_(f("c", "n"))),
            [
              JsBuild.exprStmt(
                JsBuild.call(JsBuild.member(JsBuild.id("out"), "push"), [f("c", "h")]),
              ),
              JsBuild.exprStmt(
                JsBuild.assign(JsBuild.id("k"), JsBuild.sub(JsBuild.id("k"), JsBuild.int_(1))),
              ),
              JsBuild.if_(
                JsBuild.gt(JsBuild.id("k"), JsBuild.int_(0)),
                [JsBuild.exprStmt(JsBuild.assign(JsBuild.id("c"), forceDOf(f("c", "t"))))],
              ),
            ],
          ),
          JsBuild.ret(JsBuild.id("out")),
        ],
      ),
    ),
    // const __streamToArray__ = (s) => {
    //   const out = []; let c = s;
    //   while (!c.n) { out.push(c.h); c = __forceD__(c.t); }
    //   return out;
    // };
    JsBuild.const(
      "__streamToArray__",
      JsBuild.arrow(
        [JsBuild.p("s")],
        [
          JsBuild.const("out", JsBuild.array_([])),
          JsBuild.let_("c", JsBuild.id("s")),
          JsBuild.while_(
            JsBuild.not_(f("c", "n")),
            [
              JsBuild.exprStmt(
                JsBuild.call(JsBuild.member(JsBuild.id("out"), "push"), [f("c", "h")]),
              ),
              JsBuild.exprStmt(JsBuild.assign(JsBuild.id("c"), forceDOf(f("c", "t")))),
            ],
          ),
          JsBuild.ret(JsBuild.id("out")),
        ],
      ),
    ),
  ]
}
