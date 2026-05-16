// Compile an Expr.expr to JavaScript.
//
// Strategy for the value-only fragment (Lit, App):
//
//   Each node compiles to one `const v_N = <rhs>;` statement. Sharing is
//   detected via node identity (`expr.id`): a memo table records the
//   already-compiled result per node, so a node visited more than once
//   compiles to a single binding and subsequent encounters return the
//   cached value.
//
// Strategy for the list-iteration flow (Open ListIter / Close ListCollect):
//
//   A pre-pass walks the entire root tree and groups every Close by the
//   id of its *underlying* Open (peeled out of any surrounding Joins).
//   When the main recursion encounters the first Close in a group, it
//   compiles the entire group atomically.
//
//   `go(ctx, e)` returns `(JsAst.expr, option<scopeRef>)` — the JS
//   expression naming the value, and the innermost loop scope the value
//   lives in. A scopeRef carries a body buffer, a depth, and a parent
//   pointer (so we can walk up at close time without scanning a stack
//   per binding).
//
//   Bindings emitted by Lit and App land directly in their innermost
//   scope's buffer (or `outerStmts` if scope is None). Every other
//   binding (output arrays, for-of statements, pushes) goes through the
//   same scope-typed buffer choice.
//
//   Joins. `Close.opener` is allowed to be a chain of `Join` wrappers
//   around an Open. The number of Joins on the chain is the close's
//   "join count": it tells the compiler how many additional outer Opens
//   to set up loops for, and how many extra levels up the output array
//   should be allocated. Mechanically:
//
//     - For a close with join count N:
//         * The opener chain is walked: `underlying`, `underlying.input`,
//           `…input.input`, … for N+1 Opens total (innermost +
//           N outers). Each must be an Open ListIter.
//         * The outermost Open's input is compiled in whatever scope it
//           naturally lives in; its scope becomes the parent of the
//           outermost loop.
//         * N+1 nested loop scopes are created; each Open's id is
//           memoised with its loop variable.
//         * The output array is allocated N+1 levels above the innermost
//           loop (i.e. `walkUp(innermost, N+1)`) — that's the *parent*
//           of the outermost loop. With N=0, this is just the
//           innermost's parent (current/non-joined behaviour). With N=1,
//           it's the outermost's parent.
//         * The push happens at the deeper of `innermost` and the
//           value's own computation scope.
//         * The `for…of`s are emitted from innermost to outermost,
//           each into its parent's buffer.
//
//   Within one group, closes may have different join counts — joined
//   and unjoined closes can coexist on the same opener. Each close gets
//   its own output array at its own joined-out scope; all pushes happen
//   in the innermost loop body. The output of an unjoined close lives
//   at one parent scope (only valid inside its containing iteration);
//   the output of a joined close lives further out.
//
//   Loop reuse. When a `compileGroup` walks its opener chain, an Open
//   may already be active because some outer `compileGroup` is in the
//   middle of compiling its own value (which references this group's
//   close). In that case we *reuse* the existing scope and loop
//   variable from the memo rather than creating a new one. Only the
//   freshly-created scopes get a `for…of` emitted at the end, and only
//   their opener memo entries are cleaned up; reused ones belong to the
//   outer compileGroup and it's responsible for them.
//
//   Open and Join nodes are never compiled "directly". An Open's element
//   is bound by the surrounding compileGroup (memoised before its value
//   subtree runs); a Join has no value port at all. Reaching either via
//   `go` raises with a clear message.
//
// Honoured limitations:
//   - One Open may be closed by many Closes; one Close points to exactly
//     one (possibly Join-wrapped) opener.
//   - Nested list flows are supported.
//   - Joined list flows are supported, with arbitrary join depth, as
//     long as the input chain is all Opens.
//   - Mixed join counts within a group are supported — joined and
//     unjoined closes can coexist on the same opener.
//   - No commutes, no other flow kinds.

type rec scopeRef = {
  buffer: array<JsAst.stmt>,
  depth: int,
  parent: option<scopeRef>,
}

type compileResult = (JsAst.expr, option<scopeRef>)

type compileCtx = {
  outerStmts: array<JsAst.stmt>,
  fresh: unit => string,
  memo: Map.t<int, compileResult>,
  closeGroups: Map.t<int, array<Expr.expr>>,
}

// Per-Open data computed by `establishScopes`, consumed by the rest of
// `compileGroup` and by `cleanupOpeners` / `emitForOfs`.
type scopeBundle = {
  scopeFor: Map.t<int, scopeRef>,
  elemFor: Map.t<int, string>,
  // True for openers this compileGroup created a fresh scope for; false
  // for openers whose scope was reused from an enclosing compileGroup.
  createdHere: Map.t<int, bool>,
  innermost: scopeRef,
}

let deeper = (
  a: option<scopeRef>,
  b: option<scopeRef>,
): option<scopeRef> =>
  switch (a, b) {
  | (None, None) => None
  | (None, Some(s)) => Some(s)
  | (Some(s), None) => Some(s)
  | (Some(sa), Some(sb)) =>
    if sa.depth >= sb.depth {
      Some(sa)
    } else {
      Some(sb)
    }
  }

let bufferOf = (
  ctx: compileCtx,
  innermost: option<scopeRef>,
): array<JsAst.stmt> =>
  switch innermost {
  | Some(s) => s.buffer
  | None => ctx.outerStmts
  }

let depthOf = (innermost: option<scopeRef>): int =>
  switch innermost {
  | Some(s) => s.depth
  | None => 0
  }

// Walk N parent links upward. n=0 returns the input unchanged; n=1 returns
// the input's parent; etc. Returns None once the chain runs out.
let rec walkUp = (s: option<scopeRef>, n: int): option<scopeRef> =>
  if n <= 0 {
    s
  } else {
    switch s {
    | None => None
    | Some(scope) => walkUp(scope.parent, n - 1)
    }
  }

// Strip any Join wrappers off an opener; return the underlying Open expr
// and the number of Joins peeled off (= the join count of this opener).
let unwrapJoinedOpener = (e: Expr.expr): (Expr.expr, int) => {
  let rec aux = (e: Expr.expr, n: int): (Expr.expr, int) =>
    switch e.kind {
    | Join({inner}) => aux(inner, n + 1)
    | _ => (e, n)
    }
  aux(e, 0)
}

// Walk the input chain of Opens starting at `start` and going outward
// `joinDepth` steps. Result has length `joinDepth + 1`: chain[0] is the
// innermost (= `start`), chain[joinDepth] is the outermost. Every step
// must traverse another Open ListIter; otherwise raises with a clear
// error.
let gatherOpenerChain = (start: Expr.expr, joinDepth: int): array<Expr.expr> => {
  let chain = [start]
  let curr = ref(start)
  for _ in 1 to joinDepth {
    let nextInput = switch (curr.contents).kind {
    | Open({input}) => input
    | _ =>
      failwith(
        "Internal error: chain walker arrived at a non-Open node while " ++
        "expecting an Open chain.",
      )
    }
    switch nextInput.kind {
    | Open(_) => ()
    | _ =>
      failwith(
        "Join requires the inner Open's input to also be an Open. The " ++
        "input chain ran out of Opens before reaching the requested join " ++
        "depth.",
      )
    }
    chain->Array.push(nextInput)
    curr := nextInput
  }
  chain
}

// Pre-pass: walk the tree, group every Close by the id of its underlying
// Open. Within each group, Closes appear in tree-walk discovery order.
let preprocessCloseGroups = (root: Expr.expr): Map.t<int, array<Expr.expr>> => {
  let groups: Map.t<int, array<Expr.expr>> = Map.make()
  let visited: Map.t<int, bool> = Map.make()
  let rec walk = (e: Expr.expr) =>
    if !(visited->Map.has(e.id)) {
      visited->Map.set(e.id, true)
      switch e.kind {
      | Lit(_) => ()
      | App({args}) => args->Array.forEach(a => walk(a))
      | Open({input}) => walk(input)
      | Join({inner}) => walk(inner)
      | Close({opener, value}) =>
        let (underlying, _) = unwrapJoinedOpener(opener)
        let group = switch groups->Map.get(underlying.id) {
        | Some(g) => g
        | None =>
          let g = []
          groups->Map.set(underlying.id, g)
          g
        }
        group->Array.push(e)
        walk(opener)
        walk(value)
      }
    }
  walk(root)
  groups
}

// Small helper: look up a Map entry that we know must be present.
let mustGet = (m: Map.t<'k, 'v>, k: 'k, msg: string): 'v =>
  switch m->Map.get(k) {
  | Some(v) => v
  | None => failwith(msg)
  }

let rec go = (ctx: compileCtx, e: Expr.expr): compileResult =>
  switch ctx.memo->Map.get(e.id) {
  | Some(r) => r
  | None =>
    let r = switch e.kind {
    | Lit(js) =>
      let name = ctx.fresh()
      ctx.outerStmts->Array.push(JsBuild.const(name, js))
      (JsBuild.id(name), None)
    | App({fn, args}) =>
      let argResults = args->Array.map(a => go(ctx, a))
      let argExprs = argResults->Array.map(((expr, _)) => expr)
      let innermost =
        argResults->Array.reduce(None, (acc, (_, s)) => deeper(acc, s))
      let name = ctx.fresh()
      bufferOf(ctx, innermost)->Array.push(
        JsBuild.const(name, JsBuild.call(fn, argExprs)),
      )
      (JsBuild.id(name), innermost)
    | Open(_) =>
      failwith(
        "Open node (id=" ++
        Int.toString(e.id) ++
        ") was reached outside of any of its Closes. " ++
        "An Open's value (the per-iteration element) is only meaningful " ++
        "inside one of its Closes' value subtrees.",
      )
    | Join(_) =>
      failwith(
        "Join node (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value. A Join is a pure flow operation — it " ++
        "has only a flow output port, no value output port — and should " ++
        "appear only in the `opener` field of a Close.",
      )
    | Close({opener}) =>
      let (underlying, _) = unwrapJoinedOpener(opener)
      let group = mustGet(
        ctx.closeGroups,
        underlying.id,
        "Internal error: Close (id=" ++
        Int.toString(e.id) ++
        ") has no entry in closeGroups for its underlying opener (id=" ++
        Int.toString(underlying.id) ++
        "). The pre-pass should have created one.",
      )
      compileGroup(ctx, underlying, group)
      mustGet(
        ctx.memo,
        e.id,
        "Internal error: Close (id=" ++
        Int.toString(e.id) ++
        ") was not memoised by compileGroup. The pre-pass likely missed it.",
      )
    }
    ctx.memo->Map.set(e.id, r)
    r
  }

and compileGroup = (
  ctx: compileCtx,
  underlying: Expr.expr,
  group: array<Expr.expr>,
): unit => {
  // Validate the underlying Open.
  switch underlying.kind {
  | Open({flow: ListIter}) => ()
  | _ =>
    failwith(
      "Unsupported flow: a Close's `opener` must (after stripping Joins) " ++
      "be an Open ListIter node.",
    )
  }

  // Validate each close, peel its own join count, and gather its parts.
  let closesData = group->Array.map(c =>
    switch c.kind {
    | Close({flow: ListCollect, opener: closeOpener, value}) =>
      let (_, joinCount) = unwrapJoinedOpener(closeOpener)
      (c, value, joinCount)
    | _ =>
      failwith(
        "Unsupported flow: only ListCollect is implemented for closing.",
      )
    }
  )

  // Determine how many outer loops we need to set up — enough to cover
  // the deepest joined close. (Closes within a group may have different
  // join counts; each gets its own output array at its own scope.)
  let maxJoinCount =
    closesData->Array.reduce(0, (acc, (_, _, jc)) => if jc > acc { jc } else { acc })

  // Gather all the Opens we'll iterate, innermost first.
  let chain = gatherOpenerChain(underlying, maxJoinCount)

  // Compile the outermost Open's input. Whatever scope it lives in is
  // the parent of the loop chain we're about to build.
  let outermostInputExpr = switch (chain->Array.getUnsafe(maxJoinCount)).kind {
  | Open({input}) => input
  | _ => failwith("Internal error: outermost chain entry is not an Open.")
  }
  let (outerInputExpr, outermostParent) = go(ctx, outermostInputExpr)

  // Set up loop scopes for every Open in the chain (with reuse for any
  // already-active Open).
  let setup = establishScopes(ctx, chain, outermostParent)

  // Allocate one output array per close, at its own joined-out scope.
  let outNames = closesData->Array.map(((c, _, joinCount)) => {
    let outScope = walkUp(Some(setup.innermost), joinCount + 1)
    let outBuffer = bufferOf(ctx, outScope)
    let name = ctx.fresh()
    outBuffer->Array.push(JsBuild.const(name, JsBuild.array_([])))
    ctx.memo->Map.set(c.id, (JsBuild.id(name), outScope))
    name
  })

  // Compile each close's value and emit its push. The push lands at the
  // deeper of the innermost loop and the value's own computation scope —
  // for non-joined closes these are equal; for joined closes the value
  // is also computed in the innermost loop body; and for value subtrees
  // that don't depend on the iteration at all we still push per inner
  // iteration into the loop body (just pushing the same value each time).
  closesData->Array.forEachWithIndex(((_, value, _), i) => {
    let (valueExpr, valueScope) = go(ctx, value)
    let pushBuffer = bufferOf(ctx, deeper(Some(setup.innermost), valueScope))
    let outName = outNames->Array.getUnsafe(i)
    pushBuffer->Array.push(
      JsBuild.exprStmt(
        JsBuild.call(
          JsBuild.member(JsBuild.id(outName), "push"),
          [valueExpr],
        ),
      ),
    )
  })

  // Tear down the openers we created (a reused opener's memo entry
  // belongs to an enclosing compileGroup that's still using it). Then
  // emit our `for…of`s.
  cleanupOpeners(ctx, chain, setup.createdHere)
  emitForOfs(ctx, chain, setup, outerInputExpr)
}

// Set up loop scopes for every Open in `chain`, from outermost to
// innermost. If an Open is already in the memo (because an enclosing
// compileGroup is mid-compile and put it there), reuse the existing
// scope and loop variable rather than create a duplicate. Returns a
// bundle so the caller can drive cleanup and for-of emission with
// per-Open knowledge of created vs reused.
and establishScopes = (
  ctx: compileCtx,
  chain: array<Expr.expr>,
  outermostParent: option<scopeRef>,
): scopeBundle => {
  let scopeFor: Map.t<int, scopeRef> = Map.make()
  let elemFor: Map.t<int, string> = Map.make()
  let createdHere: Map.t<int, bool> = Map.make()
  let nLevels = Array.length(chain)
  let parent = ref(outermostParent)
  for i in nLevels - 1 downto 0 {
    let openNode = chain->Array.getUnsafe(i)
    let scope = switch ctx.memo->Map.get(openNode.id) {
    | Some((existingExpr, Some(existingScope))) =>
      // Reuse: an enclosing compileGroup already set this Open up.
      let elemName = switch existingExpr {
      | JsAst.EId(name) => name
      | _ =>
        failwith(
          "Internal error: opener memo entry should hold an EId, but got " ++
          "something else.",
        )
      }
      scopeFor->Map.set(openNode.id, existingScope)
      elemFor->Map.set(openNode.id, elemName)
      createdHere->Map.set(openNode.id, false)
      existingScope
    | _ =>
      // Fresh scope.
      let elemName = ctx.fresh()
      let s = {
        buffer: [],
        depth: depthOf(parent.contents) + 1,
        parent: parent.contents,
      }
      scopeFor->Map.set(openNode.id, s)
      elemFor->Map.set(openNode.id, elemName)
      createdHere->Map.set(openNode.id, true)
      ctx.memo->Map.set(openNode.id, (JsBuild.id(elemName), Some(s)))
      s
    }
    parent := Some(scope)
  }
  let innermost = mustGet(
    scopeFor,
    (chain->Array.getUnsafe(0)).id,
    "Internal error: missing innermost scope.",
  )
  {scopeFor, elemFor, createdHere, innermost}
}

// Remove memo entries for openers we created here so that any later
// (mistaken) reference to them fails cleanly. Reused openers belong to
// an enclosing compileGroup and are left alone.
and cleanupOpeners = (
  ctx: compileCtx,
  chain: array<Expr.expr>,
  createdHere: Map.t<int, bool>,
): unit =>
  chain->Array.forEach(o =>
    switch createdHere->Map.get(o.id) {
    | Some(true) => let _ = ctx.memo->Map.delete(o.id)
    | _ => ()
    }
  )

// Emit `for…of`s for every Open we created scopes for, innermost first.
// Each one lands in its parent scope's buffer (the innermost's parent
// is the next outer loop's body, or `outerStmts` for a single-level
// loop; the outermost's parent is wherever the data source lives).
// Reused scopes are skipped — the enclosing compileGroup that owns
// them will emit (or already emitted) their for-of.
and emitForOfs = (
  ctx: compileCtx,
  chain: array<Expr.expr>,
  setup: scopeBundle,
  outermostInputExpr: JsAst.expr,
): unit => {
  let nLevels = Array.length(chain)
  for i in 0 to nLevels - 1 {
    let openNode = chain->Array.getUnsafe(i)
    switch setup.createdHere->Map.get(openNode.id) {
    | Some(true) =>
      let scope = mustGet(
        setup.scopeFor,
        openNode.id,
        "Internal error: missing scope for chain Open.",
      )
      let elemName = mustGet(
        setup.elemFor,
        openNode.id,
        "Internal error: missing elem name.",
      )
      let parentBuf = bufferOf(ctx, scope.parent)
      let inputExpr = if i == nLevels - 1 {
        outermostInputExpr
      } else {
        // This loop iterates the next-outer Open's element.
        let outerOpen = chain->Array.getUnsafe(i + 1)
        JsBuild.id(mustGet(
          setup.elemFor,
          outerOpen.id,
          "Internal error: missing outer elem name.",
        ))
      }
      parentBuf->Array.push(JsBuild.forOf(elemName, inputExpr, scope.buffer))
    | _ => ()
    }
  }
}

let compileToBody = (root: Expr.expr): (array<JsAst.stmt>, JsAst.expr) => {
  let counter = ref(0)
  let fresh = () => {
    let n = counter.contents
    counter := n + 1
    "v" ++ Int.toString(n)
  }
  let ctx: compileCtx = {
    outerStmts: [],
    fresh,
    memo: Map.make(),
    closeGroups: preprocessCloseGroups(root),
  }
  let (final, _) = go(ctx, root)
  (ctx.outerStmts, final)
}

let compileToIIFE = (e: Expr.expr): JsAst.expr => {
  let (stmts, value) = compileToBody(e)
  let body = [...stmts, JsBuild.ret(value)]
  JsBuild.call(JsBuild.arrow([], body), [])
}
