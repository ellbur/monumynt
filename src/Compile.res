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
// Strategy for flow nodes (Open, Close, Join, Branch):
//
//   `go(ctx, e)` returns `(JsAst.expr, option<scopeRef>)` — the JS
//   expression naming the value, and the innermost scope the value
//   lives in. A scopeRef carries a body buffer, a depth, and a parent
//   pointer (so we can walk up at close time without scanning a stack
//   per binding). Per-binding dispatch goes through `bufferOf`.
//
//   A pre-pass groups every Close by its underlying opener id (the
//   underlying is found by stripping any Join wrappers, or by reading
//   the source of a Branch — see `underlyingOpenerFor`). When `go`
//   first hits any Close in a group, the appropriate compileGroup
//   compiles the entire group atomically.
//
//   - `compileListGroup` — for groups whose underlying is `Open ListIter`.
//     Sets up nested for-of loops (one per Join in the chain), emits
//     each Close's output array at its own joined-out scope, pushes
//     each per-iteration value at the deeper of innermost-loop and
//     value-scope. Reuses already-active scopes from the memo so that
//     mixed nested + multi-close + joined patterns work.
//
//   - `compileCaseGroup` — for groups whose underlying is `Open CaseSplit`.
//     Calls the discriminator on the input to get a `{tag, value}`
//     split. Allocates a `let` result variable per Close. For each alt:
//     creates a fresh branch scope, memoises every Branch node
//     referencing (this Open, this alt) to a fresh `const v = split.value;`
//     binding, compiles each Close's per-alt value subtree, and emits
//     the per-Close assignment. Then builds an `if (split.tag === alt0)
//     { ... } else if (...) { ... } else { throw }` chain in the parent
//     scope.
//
//   Open, Branch, and Join nodes are never compiled "directly". An
//   Open's element / a Branch's value port is bound by the surrounding
//   compileGroup (memoised before its value subtree runs); a Join has
//   no value port at all. Reaching any of them via `go` raises with a
//   clear message.
//
// Honoured limitations:
//   - Nested list flows are supported.
//   - Joined list flows are supported, with arbitrary join depth.
//   - Mixed join counts within a list-flow group are supported.
//   - Case-split (Open CaseSplit / Close CaseJoin) is supported with
//     exhaustive branches.
//   - Joining a case-split flow is not supported (Joins are list-only
//     for now).
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
  // For each CaseSplit Open's id, a map from alt name to the Branch
  // nodes that reference (this Open, this alt). Built by the pre-pass
  // and consumed by compileCaseGroup to know which Branch ids to
  // memoise inside each alt's branch scope.
  branchesBySource: Map.t<int, Map.t<string, array<Expr.expr>>>,
}

// Per-Open data computed by `establishScopes`, consumed by the rest of
// `compileListGroup` and by `cleanupOpeners` / `emitForOfs`.
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

// Walk N parent links upward.
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
// and the number of Joins peeled off.
let unwrapJoinedOpener = (e: Expr.expr): (Expr.expr, int) => {
  let rec aux = (e: Expr.expr, n: int): (Expr.expr, int) =>
    switch e.kind {
    | Join({inner}) => aux(inner, n + 1)
    | _ => (e, n)
    }
  aux(e, 0)
}

// Walk Open.input outward to gather `joinDepth + 1` Opens (innermost
// first). Each step must be an Open ListIter; otherwise raises.
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

// Given a Close, find the underlying Open it ultimately consumes:
//   - For ListCollect: peel any Joins off branches[0].flow.
//   - For CaseJoin: branches[0].flow must be a Branch node; its source
//     is the underlying CaseSplit Open. (All branches must reference
//     the same source — validated separately at compile time.)
let underlyingOpenerForClose = (close: Expr.expr): Expr.expr =>
  switch close.kind {
  | Close({flow: ListCollect, branches}) =>
    let firstFlow = (branches->Array.getUnsafe(0)).flow
    let (u, _) = unwrapJoinedOpener(firstFlow)
    u
  | Close({flow: CaseJoin, branches}) =>
    let firstFlow = (branches->Array.getUnsafe(0)).flow
    switch firstFlow.kind {
    | Branch({source}) => source
    | _ =>
      failwith(
        "CaseJoin Close must have each branch's flow be a Branch node " ++
        "referencing the underlying CaseSplit Open.",
      )
    }
  | _ =>
    failwith(
      "Internal error: underlyingOpenerForClose called on a non-Close.",
    )
  }

// Pre-pass: walk the tree once, building both the close-group map
// (Close exprs grouped by their underlying opener's id) and the
// branches-by-source map (Branch exprs grouped by their source's id
// then by alt name).
let preprocess = (
  root: Expr.expr,
): (
  Map.t<int, array<Expr.expr>>,
  Map.t<int, Map.t<string, array<Expr.expr>>>,
) => {
  let groups: Map.t<int, array<Expr.expr>> = Map.make()
  let branchesBySource: Map.t<int, Map.t<string, array<Expr.expr>>> = Map.make()
  let visited: Map.t<int, bool> = Map.make()
  let rec walk = (e: Expr.expr) =>
    if !(visited->Map.has(e.id)) {
      visited->Map.set(e.id, true)
      switch e.kind {
      | Lit(_) => ()
      | App({args}) => args->Array.forEach(a => walk(a))
      | Open({input}) => walk(input)
      | Join({inner}) => walk(inner)
      | Branch({source, alt}) =>
        let altMap = switch branchesBySource->Map.get(source.id) {
        | Some(m) => m
        | None =>
          let m = Map.make()
          branchesBySource->Map.set(source.id, m)
          m
        }
        let arr = switch altMap->Map.get(alt) {
        | Some(a) => a
        | None =>
          let a = []
          altMap->Map.set(alt, a)
          a
        }
        arr->Array.push(e)
        walk(source)
      | Close({branches}) =>
        let underlying = underlyingOpenerForClose(e)
        let group = switch groups->Map.get(underlying.id) {
        | Some(g) => g
        | None =>
          let g = []
          groups->Map.set(underlying.id, g)
          g
        }
        group->Array.push(e)
        branches->Array.forEach(b => {
          walk(b.flow)
          walk(b.value)
        })
      }
    }
  walk(root)
  (groups, branchesBySource)
}

// Look up a Map entry that we know must be present.
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
        ") was reached outside of any of its consumers (Close, Branch). " ++
        "An Open's value (the per-iteration element, or per-alt payload) " ++
        "is only meaningful inside a containing Close or Branch's body.",
      )
    | Join(_) =>
      failwith(
        "Join node (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value. A Join is a pure flow operation — it " ++
        "has only a flow output port, no value output port — and should " ++
        "appear only in the `flow` field of a ListCollect Close's branch.",
      )
    | Branch(_) =>
      failwith(
        "Branch node (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value outside its case-close scope. A Branch's " ++
        "value port is only meaningful inside the corresponding alt's " ++
        "branch in a CaseJoin Close.",
      )
    | Close({flow}) =>
      let underlying = underlyingOpenerForClose(e)
      let group = mustGet(
        ctx.closeGroups,
        underlying.id,
        "Internal error: Close (id=" ++
        Int.toString(e.id) ++
        ") has no entry in closeGroups for its underlying opener (id=" ++
        Int.toString(underlying.id) ++
        ").",
      )
      switch (flow, underlying.kind) {
      | (ListCollect, Open({flow: ListIter})) =>
        compileListGroup(ctx, underlying, group)
      | (CaseJoin, Open({flow: CaseSplit(_)})) =>
        compileCaseGroup(ctx, underlying, group)
      | _ =>
        failwith(
          "Mismatched Close flow and underlying Open flow for Close id=" ++
          Int.toString(e.id),
        )
      }
      mustGet(
        ctx.memo,
        e.id,
        "Internal error: Close (id=" ++
        Int.toString(e.id) ++
        ") was not memoised by its compileGroup.",
      )
    }
    ctx.memo->Map.set(e.id, r)
    r
  }

and compileListGroup = (
  ctx: compileCtx,
  underlying: Expr.expr,
  group: array<Expr.expr>,
): unit => {
  // Validate underlying Open.
  switch underlying.kind {
  | Open({flow: ListIter}) => ()
  | _ =>
    failwith(
      "Internal error: compileListGroup expects an Open ListIter underlying.",
    )
  }

  // Each list-collect Close has exactly one branch (altName=None,
  // flow=opener-with-joins, value=per-iteration expression).
  let closesData = group->Array.map(c =>
    switch c.kind {
    | Close({flow: ListCollect, branches}) =>
      if Array.length(branches) != 1 {
        failwith(
          "ListCollect Close must have exactly one branch, but Close (id=" ++
          Int.toString(c.id) ++
          ") has " ++
          Int.toString(Array.length(branches)) ++ ".",
        )
      }
      let branch = branches->Array.getUnsafe(0)
      let (_, joinCount) = unwrapJoinedOpener(branch.flow)
      (c, branch.value, joinCount)
    | _ =>
      failwith(
        "Internal error: compileListGroup got a non-ListCollect Close.",
      )
    }
  )

  // Determine how many outer loops we need to set up.
  let maxJoinCount =
    closesData->Array.reduce(0, (acc, (_, _, jc)) => if jc > acc { jc } else { acc })

  // Gather all the Opens we'll iterate, innermost first.
  let chain = gatherOpenerChain(underlying, maxJoinCount)

  // Compile the outermost Open's input.
  let outermostInputExpr = switch (chain->Array.getUnsafe(maxJoinCount)).kind {
  | Open({input}) => input
  | _ => failwith("Internal error: outermost chain entry is not an Open.")
  }
  let (outerInputExpr, outermostParent) = go(ctx, outermostInputExpr)

  // Set up nested loop scopes (with reuse for any already-active Open).
  let setup = establishScopes(ctx, chain, outermostParent)

  // Allocate one output array per Close.
  let outNames = closesData->Array.map(((c, _, joinCount)) => {
    let outScope = walkUp(Some(setup.innermost), joinCount + 1)
    let outBuffer = bufferOf(ctx, outScope)
    let name = ctx.fresh()
    outBuffer->Array.push(JsBuild.const(name, JsBuild.array_([])))
    ctx.memo->Map.set(c.id, (JsBuild.id(name), outScope))
    name
  })

  // Compile each Close's value and emit its push.
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

  cleanupOpeners(ctx, chain, setup.createdHere)
  emitForOfs(ctx, chain, setup, outerInputExpr)
}

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

// CaseSplit / CaseJoin compile.
//
//   const v_split = disc(input);
//   let v_close_0;
//   let v_close_1;
//   if (v_split.tag === alt0) {
//     const v_b0_0 = v_split.value;     // Branch nodes for alt0
//     const v_b0_1 = v_split.value;
//     ...
//     v_close_0 = <value0a>;
//     v_close_1 = <value1a>;
//   } else if (v_split.tag === alt1) {
//     ...
//   } else {
//     throw new Error("Unmatched: " + v_split.tag);
//   }
//
and compileCaseGroup = (
  ctx: compileCtx,
  underlying: Expr.expr,
  group: array<Expr.expr>,
): unit => {
  let (alts, discriminator, openInput) = switch underlying.kind {
  | Open({flow: CaseSplit({alts, discriminator}), input}) =>
    (alts, discriminator, input)
  | _ =>
    failwith(
      "Internal error: compileCaseGroup expects an Open CaseSplit underlying.",
    )
  }

  // Validate every Close's branches: CaseJoin, all branch.flow are
  // Branch nodes referencing this underlying Open, and altNames cover
  // every alt exactly once.
  group->Array.forEach(c =>
    switch c.kind {
    | Close({flow: CaseJoin, branches}) =>
      branches->Array.forEach(b =>
        switch b.flow.kind {
        | Branch({source}) =>
          if source.id != underlying.id {
            failwith(
              "CaseJoin Close (id=" ++
              Int.toString(c.id) ++
              ") has a branch whose flow's source is a different Open " ++
              "than the rest of the group's underlying.",
            )
          }
        | _ =>
          failwith(
            "CaseJoin Close (id=" ++
            Int.toString(c.id) ++
            ") branch.flow must be a Branch node.",
          )
        }
      )
      // Every alt must be covered exactly once.
      alts->Array.forEach(altName => {
        let count = branches->Array.reduce(0, (acc, b) =>
          switch b.altName {
          | Some(name) when name == altName => acc + 1
          | _ => acc
          }
        )
        if count != 1 {
          failwith(
            "CaseJoin Close (id=" ++
            Int.toString(c.id) ++
            ") must have exactly one branch for alt \"" ++
            altName ++
            "\" (found " ++
            Int.toString(count) ++ ").",
          )
        }
      })
    | _ =>
      failwith(
        "Internal error: compileCaseGroup got a non-CaseJoin Close.",
      )
    }
  )

  // Compile the input. The split happens at parentInnermost.
  let (inputExpr, parentInnermost) = go(ctx, openInput)
  let parentBuffer = bufferOf(ctx, parentInnermost)

  // Apply the discriminator: const v_split = disc(input);
  let splitName = ctx.fresh()
  parentBuffer->Array.push(
    JsBuild.const(splitName, JsBuild.call(discriminator, [inputExpr])),
  )
  let splitExpr = JsBuild.id(splitName)

  // Allocate a let-bound result variable per Close. Memoise each Close
  // to its result name, with parent scope as the value's scope.
  let resultNames = group->Array.map(c => {
    let name = ctx.fresh()
    parentBuffer->Array.push(JsBuild.letDecl(name))
    ctx.memo->Map.set(c.id, (JsBuild.id(name), parentInnermost))
    name
  })

  // Look up the Branch nodes registered for this underlying Open.
  let branchesByAlt =
    ctx.branchesBySource->Map.get(underlying.id)->Option.getOr(Map.make())

  // For each alt, build a branch scope and compile every Close's
  // per-alt value into it.
  let altBodies = alts->Array.map(altName => {
    let branchBody: array<JsAst.stmt> = []
    let branchScope = {
      buffer: branchBody,
      depth: depthOf(parentInnermost) + 1,
      parent: parentInnermost,
    }

    // Memoise every Branch node for (this Open, this alt) to a fresh
    // const-bound v = split.value.
    let branchesForAlt =
      branchesByAlt->Map.get(altName)->Option.getOr([])
    branchesForAlt->Array.forEach(branchExpr => {
      let bname = ctx.fresh()
      branchBody->Array.push(
        JsBuild.const(bname, JsBuild.member(splitExpr, "value")),
      )
      ctx.memo->Map.set(
        branchExpr.id,
        (JsBuild.id(bname), Some(branchScope)),
      )
    })

    // Compile each Close's per-alt value subtree and emit the
    // assignment to that Close's result variable.
    group->Array.forEachWithIndex((c, ci) =>
      switch c.kind {
      | Close({branches: cbranches}) =>
        let branchOpt = cbranches->Array.find(b =>
          switch b.altName {
          | Some(name) => name == altName
          | None => false
          }
        )
        switch branchOpt {
        | Some(b) =>
          let (valueExpr, _) = go(ctx, b.value)
          branchBody->Array.push(
            JsBuild.exprStmt(
              JsBuild.assign(
                JsBuild.id(resultNames->Array.getUnsafe(ci)),
                valueExpr,
              ),
            ),
          )
        | None =>
          failwith(
            "Internal error: validated above, but branch for alt \"" ++
            altName ++ "\" not found.",
          )
        }
      | _ => ()
      }
    )

    // Cleanup Branch memos for this alt — the per-iter bindings go
    // out of scope at the end of the if-block.
    branchesForAlt->Array.forEach(branchExpr => {
      let _ = ctx.memo->Map.delete(branchExpr.id)
    })

    (altName, branchBody)
  })

  // Build the if/else-if chain in reverse (innermost else-clause is
  // the throw, then wrap each alt around the previous accumulator).
  let elseClause = JsAst.SThrow(
    JsBuild.new_(
      JsBuild.id("Error"),
      [JsBuild.add(
        JsBuild.str("Unmatched case: "),
        JsBuild.member(splitExpr, "tag"),
      )],
    ),
  )
  let chainStmt = ref(elseClause)
  for i in Array.length(altBodies) - 1 downto 0 {
    let (altName, body) = altBodies->Array.getUnsafe(i)
    chainStmt := JsAst.SIf({
      test: JsBuild.eq(JsBuild.member(splitExpr, "tag"), JsBuild.str(altName)),
      cons: JsAst.SBlock(body),
      alt: Some(chainStmt.contents),
    })
  }
  parentBuffer->Array.push(chainStmt.contents)
}

let compileToBody = (root: Expr.expr): (array<JsAst.stmt>, JsAst.expr) => {
  let counter = ref(0)
  let fresh = () => {
    let n = counter.contents
    counter := n + 1
    "v" ++ Int.toString(n)
  }
  let (closeGroups, branchesBySource) = preprocess(root)
  let ctx: compileCtx = {
    outerStmts: [],
    fresh,
    memo: Map.make(),
    closeGroups,
    branchesBySource,
  }
  let (final, _) = go(ctx, root)
  (ctx.outerStmts, final)
}

let compileToIIFE = (e: Expr.expr): JsAst.expr => {
  let (stmts, value) = compileToBody(e)
  let body = [...stmts, JsBuild.ret(value)]
  JsBuild.call(JsBuild.arrow([], body), [])
}
