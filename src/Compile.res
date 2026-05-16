// Compile an Expr.expr to JavaScript.
//
// Architecture: every Open / Join / Filter / Branch node has a *flow
// output port*. Flows are first-class entities, constructed lazily and
// memoised by node id (just like value-port results are memoised by id
// in `ctx.memo`). `flowFor(ctx, e)` returns the openFlow for `e`,
// constructing it on first reference.
//
// `go(ctx, e)` is the value-port entry point. It dispatches by node
// kind:
//   - Lit, App: same as before — a `const v_N = …` emitted somewhere.
//   - Open ListIter: triggers flowFor for the loop, returns the per-
//     iteration element binding (and the loop scope).
//   - Branch (value port): triggers flowFor for the BranchOf, returns
//     the per-alt `v = split.value` binding (and the alt scope).
//   - Close: dispatches to the appropriate consumeXxxClose, which
//     attaches outputs/pushes to the relevant flow entities.
//   - Open CaseSplit / Join / Filter: failwith — these have no value
//     port. (Open CaseSplit's per-alt values are reached via Branch.)
//
// `flowFor` constructs:
//   - ListLoop for Open ListIter — sets up a loop scope, captures the
//     parent buffer + a placeholder stmt where the for-of will land,
//     memoises the per-iteration element binding into ctx.memo.
//   - CaseDispatch for Open CaseSplit — emits `const split = disc(…)`,
//     captures parent buffer + placeholder, allocates per-alt scopes.
//     Joined input is allowed (for filter-under-joined-lists): the
//     joins are peeled off before compiling the input value, and the
//     join depth is recorded for filter consumers.
//   - Joined wrapping inner — pure structural wrapper; no emission.
//     List consumers walk through Joineds to count joinDepth.
//   - Filtered wrapping inner BranchOf — pure structural wrapper; no
//     emission. Filter consumers see this and pick filter semantics
//     (output above the surrounding list, push inside the alt body).
//   - BranchOf wrapping inner CaseDispatch — emits a fresh `const v =
//     split.value` at the top of the alt's scope and caches the flow
//     so that other Branch nodes for the same (CaseDispatch, alt)
//     share the same v binding.
//
// Consumers (Closes) attach lazily:
//   - consumeListClose — pushes a `const out = []` into the *outermost*
//     loop's preLoopBuf (one level for non-joined, more for joined),
//     compiles the per-iteration value, pushes into the innermost
//     loop's body.
//   - consumeCaseClose — flips dispatch.demandsExhaustive on, pushes
//     `let v_close;` into the dispatch's preDispatchBuf, compiles each
//     branch value into the matching alt's scope, appends `v_close =
//     value` at the end.
//   - consumeFilterClose — finds the surrounding list's outermost
//     loop via the dispatch's recorded inputJoinDepth, pushes
//     `const out = []` into that loop's preLoopBuf, compiles the
//     value inside the alt body, pushes.
//
// Mixing is uniform: case-close + filter-close on the same case-split
// share one CaseDispatch, one if-chain, one `const split = …`. The
// case-close turns on demandsExhaustive (so the if-chain ends with
// `else throw`); the filter-close just adds its push to the matching
// alt body.
//
// Finalisation. ListLoop and CaseDispatch each own a placeholder stmt
// they pushed into their parent buffer at construction time. After
// `go(root)` returns, finalizeLoops / finalizeDispatches walks the
// pendingLoops / pendingDispatches arrays and uses splice + reference
// equality on the placeholder to:
//   - For a loop: replace the placeholder with [...preLoopBuf, for-of].
//   - For a dispatch: replace the placeholder with [...preDispatchBuf,
//     if-chain] (omitting alts whose body is empty if the dispatch is
//     filter-only; including else-throw if any case-close demanded
//     exhaustiveness).
//
// Because we look the placeholder up by reference at finalize time,
// the order of loop/dispatch finalisations doesn't matter — splices
// elsewhere don't move the placeholder, only its index.

type rec scopeRef = {
  buffer: array<JsAst.stmt>,
  depth: int,
  parent: option<scopeRef>,
}
and openFlow = {
  id: int,
  kind: openFlowKind,
}
and openFlowKind =
  | ListLoop(listLoopData)
  | CaseDispatch(caseDispatchData)
  | Joined({inner: openFlow})
  | BranchOf(branchOfData)
  | Filtered({inner: openFlow})
and listLoopData = {
  // The loop body (per-iteration scope). Push consumers append into
  // this buffer.
  scope: scopeRef,
  // Identifier bound by the for-of header.
  elemName: string,
  // The buffer the for-of statement will be spliced into.
  parentBuf: array<JsAst.stmt>,
  // Sentinel pushed into parentBuf at construction; replaced at
  // finalisation by [...preLoopBuf, for-of].
  placeholder: JsAst.stmt,
  // Bindings that need to live above the for-of (e.g., output
  // arrays). Spliced in immediately before the for-of at finalise.
  preLoopBuf: array<JsAst.stmt>,
  // The compiled JS expression for the loop's input list.
  inputJsExpr: JsAst.expr,
  // The Expr.expr the Open's `input` field pointed to. Used to walk
  // further up a list chain by re-flowFor-ing.
  inputNode: Expr.expr,
}
and caseDispatchData = {
  // The scope `const split = disc(input)` and the if-chain live in.
  // None means top-level (outerStmts).
  dispParentScope: option<scopeRef>,
  dispParentBuf: array<JsAst.stmt>,
  dispPlaceholder: JsAst.stmt,
  // The fresh name bound to the discriminator's result.
  splitName: string,
  // The alts as declared on the CaseSplit Open.
  alts: array<string>,
  // Per-alt scopes; one per alt, parallel to `alts`.
  altScopes: array<scopeRef>,
  // `let v_close;` decls from case-close consumers; spliced in
  // immediately before the if-chain at finalise.
  preDispatchBuf: array<JsAst.stmt>,
  // How many Joins were peeled off the case-split's `input`. Used by
  // filter consumers to decide how many list scopes up the output
  // array lives.
  inputJoinDepth: int,
  // The peeled `input` Expr.expr (after Joins). For filter consumers;
  // flowFor'd to find the surrounding list loop.
  dispInputNode: Expr.expr,
  // Set by case-close consumers; finalisation adds an else-throw if
  // true.
  mutable demandsExhaustive: bool,
  // BranchOf flows cached by alt name, so distinct Branch nodes for
  // the same (this CaseDispatch, alt) share one v binding.
  altBranchCache: Map.t<string, openFlow>,
}
and branchOfData = {
  // The CaseDispatch this Branch picks an alt off.
  source: openFlow,
  alt: string,
  // The fresh name bound to `split.value` at the top of the alt scope.
  valueName: string,
  // The alt's body scope (where this Branch's value port lives).
  branchScope: scopeRef,
}

type compileResult = (JsAst.expr, option<scopeRef>)

type compileCtx = {
  outerStmts: array<JsAst.stmt>,
  // Top-level Lit bindings are accumulated here and prepended to
  // outerStmts at the end of compileToBody. This guarantees they're
  // declared before any for-of or if-chain that might use them inside
  // its body — under DFS-driven lazy construction, a Lit emitted while
  // a loop is being filled in would otherwise land in outerStmts after
  // the loop's placeholder, ending up after the for-of (TDZ).
  hoistedLits: array<JsAst.stmt>,
  fresh: unit => string,
  // Memoised value-port compile results, keyed by Expr.expr.id.
  memo: Map.t<int, compileResult>,
  // Memoised flows, keyed by the flow-producing node's id.
  flowMemo: Map.t<int, openFlow>,
  // Loops and dispatches awaiting their placeholders to be replaced
  // at the end of compileToBody.
  pendingLoops: array<openFlow>,
  pendingDispatches: array<openFlow>,
}

// --- Scope helpers ---

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

let rec walkUp = (s: option<scopeRef>, n: int): option<scopeRef> =>
  if n <= 0 {
    s
  } else {
    switch s {
    | None => None
    | Some(scope) => walkUp(scope.parent, n - 1)
    }
  }

// Peel any Join wrappers off an Expr.expr; return the underlying expr
// and the number of Joins peeled.
let unwrapJoinedExpr = (e: Expr.expr): (Expr.expr, int) => {
  let rec aux = (e: Expr.expr, n: int): (Expr.expr, int) =>
    switch e.kind {
    | Join({inner}) => aux(inner, n + 1)
    | _ => (e, n)
    }
  aux(e, 0)
}

// --- Lazy flow construction & value-port compile (mutually recursive) ---

let rec flowFor = (ctx: compileCtx, e: Expr.expr): openFlow =>
  switch ctx.flowMemo->Map.get(e.id) {
  | Some(f) => f
  | None =>
    let f = switch e.kind {
    | Open({flow: ListIter, input}) =>
      let (inputJsExpr, parentScope) = go(ctx, input)
      let parentBuf = bufferOf(ctx, parentScope)
      let elemName = ctx.fresh()
      let scope = {
        buffer: [],
        depth: depthOf(parentScope) + 1,
        parent: parentScope,
      }
      // Sentinel placeholder; replaced at finalisation. Each SBlock([])
      // is a unique JS object by reference, so Array.indexOfOpt finds
      // it later.
      let placeholder = JsAst.SBlock([])
      parentBuf->Array.push(placeholder)
      let f = {
        id: e.id,
        kind: ListLoop({
          scope,
          elemName,
          parentBuf,
          placeholder,
          preLoopBuf: [],
          inputJsExpr,
          inputNode: input,
        }),
      }
      // Memoise the value port: per-iteration element binding lives in
      // the loop scope.
      ctx.memo->Map.set(e.id, (JsBuild.id(elemName), Some(scope)))
      ctx.pendingLoops->Array.push(f)
      f

    | Open({flow: CaseSplit({alts, discriminator}), input}) =>
      // Peel any Joins off the input — these signal that this case-
      // split is being filtered through joined nested lists. Filter
      // consumers read inputJoinDepth at attach time.
      let (realInput, inputJoinDepth) = unwrapJoinedExpr(input)
      let (inputJsExpr, parentScope) = go(ctx, realInput)
      let parentBuf = bufferOf(ctx, parentScope)
      let splitName = ctx.fresh()
      parentBuf->Array.push(
        JsBuild.const(splitName, JsBuild.call(discriminator, [inputJsExpr])),
      )
      let placeholder = JsAst.SBlock([])
      parentBuf->Array.push(placeholder)
      let parentDepth = depthOf(parentScope)
      let altScopes = alts->Array.map(_ => {
        buffer: [],
        depth: parentDepth + 1,
        parent: parentScope,
      })
      let f = {
        id: e.id,
        kind: CaseDispatch({
          dispParentScope: parentScope,
          dispParentBuf: parentBuf,
          dispPlaceholder: placeholder,
          splitName,
          alts,
          altScopes,
          preDispatchBuf: [],
          inputJoinDepth,
          dispInputNode: realInput,
          demandsExhaustive: false,
          altBranchCache: Map.make(),
        }),
      }
      ctx.pendingDispatches->Array.push(f)
      f

    | Join({inner}) =>
      let innerFlow = flowFor(ctx, inner)
      switch innerFlow.kind {
      | ListLoop(_) | Joined(_) => ()
      | _ =>
        failwith(
          "Join (id=" ++
          Int.toString(e.id) ++
          ") must wrap a list-iter flow (or another Join), but its inner " ++
          "is something else.",
        )
      }
      {id: e.id, kind: Joined({inner: innerFlow})}

    | Filter({inner}) =>
      let innerFlow = flowFor(ctx, inner)
      switch innerFlow.kind {
      | BranchOf(_) => ()
      | _ =>
        failwith(
          "Filter (id=" ++
          Int.toString(e.id) ++
          ") must wrap a Branch flow (which references a CaseSplit Open " ++
          "whose input is a list iter), but its inner is something else.",
        )
      }
      {id: e.id, kind: Filtered({inner: innerFlow})}

    | Branch({source, alt}) =>
      let dispatchFlow = flowFor(ctx, source)
      let dispatchData = switch dispatchFlow.kind {
      | CaseDispatch(d) => d
      | _ =>
        failwith(
          "Branch (id=" ++
          Int.toString(e.id) ++
          ") must reference a CaseSplit Open, but references a " ++
          "non-CaseDispatch flow.",
        )
      }
      if !(dispatchData.alts->Array.includes(alt)) {
        failwith(
          "Branch (id=" ++
          Int.toString(e.id) ++
          ") references alt \"" ++
          alt ++
          "\" which is not in the CaseSplit's declared alts.",
        )
      }
      switch dispatchData.altBranchCache->Map.get(alt) {
      | Some(existing) => existing
      | None =>
        let altIdx = dispatchData.alts->Array.findIndex(a => a == alt)
        let altScope = dispatchData.altScopes->Array.getUnsafe(altIdx)
        let valueName = ctx.fresh()
        altScope.buffer->Array.push(
          JsBuild.const(
            valueName,
            JsBuild.member(JsBuild.id(dispatchData.splitName), "value"),
          ),
        )
        let bof = {
          id: e.id,
          kind: BranchOf({
            source: dispatchFlow,
            alt,
            valueName,
            branchScope: altScope,
          }),
        }
        dispatchData.altBranchCache->Map.set(alt, bof)
        bof
      }

    | Lit(_) | App(_) | Close(_) =>
      failwith(
        "Internal error: flowFor called on a non-flow node kind " ++
        "(id=" ++ Int.toString(e.id) ++ ").",
      )
    }
    ctx.flowMemo->Map.set(e.id, f)
    f
  }

and go = (ctx: compileCtx, e: Expr.expr): compileResult =>
  switch ctx.memo->Map.get(e.id) {
  | Some(r) => r
  | None =>
    let r = switch e.kind {
    | Lit(js) =>
      let name = ctx.fresh()
      ctx.hoistedLits->Array.push(JsBuild.const(name, js))
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

    | Open({flow: ListIter}) =>
      // Trigger flow construction; flowFor sets memo to the per-iter
      // element binding.
      let _ = flowFor(ctx, e)
      switch ctx.memo->Map.get(e.id) {
      | Some(v) => v
      | None =>
        failwith(
          "Internal error: ListIter flowFor did not set memo for id=" ++
          Int.toString(e.id) ++ ".",
        )
      }

    | Open({flow: CaseSplit(_)}) =>
      failwith(
        "Open CaseSplit (id=" ++
        Int.toString(e.id) ++
        ") has no single value output port — it has one per alt. " ++
        "Reach an alt's value via Branch.",
      )

    | Branch(_) =>
      // Trigger flow construction; the BranchOf carries the per-alt
      // v binding.
      let bof = flowFor(ctx, e)
      switch bof.kind {
      | BranchOf({valueName, branchScope}) =>
        (JsBuild.id(valueName), Some(branchScope))
      | _ =>
        failwith(
          "Internal error: Branch (id=" ++
          Int.toString(e.id) ++
          ") flow is not a BranchOf.",
        )
      }

    | Join(_) =>
      failwith(
        "Join (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value. A Join is a pure flow operation " ++
        "with no value output port.",
      )

    | Filter(_) =>
      failwith(
        "Filter (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value. A Filter is a pure flow operation " ++
        "with no value output port.",
      )

    | Close(_) =>
      consumeClose(ctx, e)
      switch ctx.memo->Map.get(e.id) {
      | Some(v) => v
      | None =>
        failwith(
          "Internal error: Close (id=" ++
          Int.toString(e.id) ++
          ") consumer did not set memo.",
        )
      }
    }
    ctx.memo->Map.set(e.id, r)
    r
  }

and consumeClose = (ctx: compileCtx, close: Expr.expr): unit =>
  switch close.kind {
  | Close({branches}) =>
    if Array.length(branches) == 0 {
      failwith(
        "Close (id=" ++ Int.toString(close.id) ++ ") has no branches.",
      )
    }
    let firstFlow = flowFor(ctx, (branches->Array.getUnsafe(0)).flow)
    switch firstFlow.kind {
    | BranchOf(_) => consumeCaseClose(ctx, close, branches)
    | Filtered(_) => consumeFilterClose(ctx, close, branches)
    | ListLoop(_) | Joined(_) => consumeListClose(ctx, close, branches)
    | _ =>
      failwith(
        "Close (id=" ++
        Int.toString(close.id) ++
        ") branches[0].flow has an unrecognised flow kind.",
      )
    }
  | _ => failwith("Internal error: consumeClose called on non-Close.")
  }

and consumeListClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit => {
  if Array.length(branches) != 1 {
    failwith(
      "A list close must have exactly one branch, but Close (id=" ++
      Int.toString(close.id) ++
      ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let branch = branches->Array.getUnsafe(0)
  switch branch.altName {
  | None => ()
  | Some(name) =>
    failwith(
      "A list close's branch must have altName=None, but Close (id=" ++
      Int.toString(close.id) ++
      ")'s branch has altName=Some(\"" ++ name ++ "\").",
    )
  }

  let flow = flowFor(ctx, branch.flow)
  // Walk through Joineds to find innermost ListLoop and joinDepth.
  let rec unwrapList = (f: openFlow, depth: int) =>
    switch f.kind {
    | ListLoop(_) => (f, depth)
    | Joined({inner}) => unwrapList(inner, depth + 1)
    | _ =>
      failwith(
        "Internal error: list-close flow is not a ListLoop / Joined chain.",
      )
    }
  let (innermostListFlow, joinDepth) = unwrapList(flow, 0)

  let (innerLoopScope, _) = switch innermostListFlow.kind {
  | ListLoop({scope, elemName}) => (scope, elemName)
  | _ => failwith("Internal")
  }

  // Walk up `joinDepth` Open.input levels to find the outermost loop
  // in the chain. Its preLoopBuf is where the output array goes.
  let curr = ref(innermostListFlow)
  for _ in 1 to joinDepth {
    let inputNode = switch (curr.contents).kind {
    | ListLoop({inputNode}) => inputNode
    | _ => failwith("Internal")
    }
    curr := flowFor(ctx, inputNode)
    switch (curr.contents).kind {
    | ListLoop(_) => ()
    | _ =>
      failwith(
        "Join requires the inner Open's input to also be an Open ListIter, " ++
        "but the input chain ran out of list iters before the requested " ++
        "join depth.",
      )
    }
  }
  let outermostPreLoopBuf = switch (curr.contents).kind {
  | ListLoop({preLoopBuf}) => preLoopBuf
  | _ => failwith("Internal")
  }

  // Allocate output array in outermost loop's preLoopBuf.
  let outName = ctx.fresh()
  outermostPreLoopBuf->Array.push(JsBuild.const(outName, JsBuild.array_([])))
  let outScope = walkUp(Some(innerLoopScope), joinDepth + 1)
  ctx.memo->Map.set(close.id, (JsBuild.id(outName), outScope))

  // Compile the per-iteration value, push at the deeper of innermost
  // loop scope and value scope.
  let (valueExpr, valueScope) = go(ctx, branch.value)
  let pushBuf = bufferOf(ctx, deeper(Some(innerLoopScope), valueScope))
  pushBuf->Array.push(
    JsBuild.exprStmt(
      JsBuild.call(
        JsBuild.member(JsBuild.id(outName), "push"),
        [valueExpr],
      ),
    ),
  )
}

and consumeCaseClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit => {
  // All branches' flows must be Branches on the same CaseDispatch.
  let dispatchFlow = {
    let firstBof = flowFor(ctx, (branches->Array.getUnsafe(0)).flow)
    switch firstBof.kind {
    | BranchOf({source}) => source
    | _ => failwith("Internal: case close branch[0] is not a BranchOf.")
    }
  }
  branches->Array.forEach(b => {
    let bof = flowFor(ctx, b.flow)
    switch bof.kind {
    | BranchOf({source}) =>
      if source.id != dispatchFlow.id {
        failwith(
          "Case close (id=" ++
          Int.toString(close.id) ++
          ") has a branch whose flow source is a different CaseSplit Open " ++
          "than the rest.",
        )
      }
    | _ =>
      failwith(
        "Case close (id=" ++
        Int.toString(close.id) ++
        ") has a branch whose flow is not a Branch node.",
      )
    }
  })

  let dispatchData = switch dispatchFlow.kind {
  | CaseDispatch(d) => d
  | _ => failwith("Internal")
  }

  // Validate altNames: each must be Some(name), name must be in alts,
  // each alt covered exactly once.
  branches->Array.forEach(b =>
    switch b.altName {
    | Some(_) => ()
    | None =>
      failwith(
        "A case close's branches must each have altName=Some(name), " ++
        "but Close (id=" ++
        Int.toString(close.id) ++
        ") has a branch with altName=None.",
      )
    }
  )
  dispatchData.alts->Array.forEach(altName => {
    let count = branches->Array.reduce(0, (acc, b) =>
      switch b.altName {
      | Some(name) if name == altName => acc + 1
      | _ => acc
      }
    )
    if count != 1 {
      failwith(
        "Case close (id=" ++
        Int.toString(close.id) ++
        ") must have exactly one branch for alt \"" ++
        altName ++
        "\" (found " ++
        Int.toString(count) ++ ").",
      )
    }
  })

  // Mark the dispatch as needing exhaustive throw.
  switch dispatchFlow.kind {
  | CaseDispatch(d) => d.demandsExhaustive = true
  | _ => ()
  }

  // Allocate `let v_close;` in the dispatch's preDispatchBuf.
  let resultName = ctx.fresh()
  dispatchData.preDispatchBuf->Array.push(JsBuild.letDecl(resultName))
  ctx.memo->Map.set(
    close.id,
    (JsBuild.id(resultName), dispatchData.dispParentScope),
  )

  // For each branch: compile its value into the alt's scope, append
  // the assignment.
  branches->Array.forEach(b => {
    let altName = switch b.altName {
    | Some(n) => n
    | None => failwith("Internal: validated above")
    }
    let altIdx = dispatchData.alts->Array.findIndex(a => a == altName)
    let altScope = dispatchData.altScopes->Array.getUnsafe(altIdx)
    let (valueExpr, _) = go(ctx, b.value)
    altScope.buffer->Array.push(
      JsBuild.exprStmt(
        JsBuild.assign(JsBuild.id(resultName), valueExpr),
      ),
    )
  })
}

and consumeFilterClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit => {
  // Per-close info: (Close, alt, value, altScope, dispatchFlow).
  let perCloseInfo = branches->Array.map(b => {
    switch b.altName {
    | None => ()
    | Some(name) =>
      failwith(
        "A filter close's branch must have altName=None, but Close (id=" ++
        Int.toString(close.id) ++
        ")'s branch has altName=Some(\"" ++ name ++ "\").",
      )
    }
    let filterFlow = flowFor(ctx, b.flow)
    let bof = switch filterFlow.kind {
    | Filtered({inner}) => inner
    | _ => failwith("Internal: not a Filtered flow")
    }
    switch bof.kind {
    | BranchOf({alt, branchScope, source}) =>
      (alt, b.value, branchScope, source)
    | _ => failwith("Internal: Filter inner is not a BranchOf")
    }
  })

  if Array.length(perCloseInfo) != 1 {
    failwith(
      "A filter close currently must have exactly one branch, but " ++
      "Close (id=" ++ Int.toString(close.id) ++ ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let (alt, value, altScope, dispatchFlow) =
    perCloseInfo->Array.getUnsafe(0)
  let dispatchData = switch dispatchFlow.kind {
  | CaseDispatch(d) => d
  | _ => failwith("Internal")
  }

  // Find the surrounding list chain via dispatch.inputNode (the peeled
  // case-split input). It must be an Open ListIter; the dispatch's
  // inputJoinDepth tells us how many list scopes up to walk.
  let innermostListFlow = flowFor(ctx, dispatchData.dispInputNode)
  switch innermostListFlow.kind {
  | ListLoop(_) => ()
  | _ =>
    failwith(
      "Filter requires the case-split's (peeled) input to be an Open " ++
      "ListIter, but it isn't.",
    )
  }
  let innermostLoopScope = switch innermostListFlow.kind {
  | ListLoop({scope}) => scope
  | _ => failwith("Internal")
  }

  // Walk up `inputJoinDepth` ListLoop levels to find the outermost in
  // the chain.
  let curr = ref(innermostListFlow)
  for _ in 1 to dispatchData.inputJoinDepth {
    let inputNode = switch (curr.contents).kind {
    | ListLoop({inputNode}) => inputNode
    | _ => failwith("Internal")
    }
    curr := flowFor(ctx, inputNode)
    switch (curr.contents).kind {
    | ListLoop(_) => ()
    | _ =>
      failwith(
        "Filter under joined lists requires each level to be an Open " ++
        "ListIter, but the chain ran out before the requested join depth.",
      )
    }
  }
  let outermostPreLoopBuf = switch (curr.contents).kind {
  | ListLoop({preLoopBuf}) => preLoopBuf
  | _ => failwith("Internal")
  }

  // Allocate output array in outermost loop's preLoopBuf.
  let outName = ctx.fresh()
  outermostPreLoopBuf->Array.push(JsBuild.const(outName, JsBuild.array_([])))
  let outScope =
    walkUp(Some(innermostLoopScope), dispatchData.inputJoinDepth + 1)
  ctx.memo->Map.set(close.id, (JsBuild.id(outName), outScope))

  // Compile value (likely references the BranchOf's v binding via
  // Branch.value), push to the alt's scope.
  let (valueExpr, _) = go(ctx, value)
  altScope.buffer->Array.push(
    JsBuild.exprStmt(
      JsBuild.call(
        JsBuild.member(JsBuild.id(outName), "push"),
        [valueExpr],
      ),
    ),
  )
  // Reference alt to avoid unused-warning.
  let _ = alt
}

// --- Finalisation: replace placeholders with for-of / if-chain ---

let finalizeLoops = (ctx: compileCtx): unit =>
  ctx.pendingLoops->Array.forEach(loopFlow =>
    switch loopFlow.kind {
    | ListLoop({parentBuf, placeholder, preLoopBuf, scope, elemName, inputJsExpr}) =>
      let idx = switch parentBuf->Array.indexOfOpt(placeholder) {
      | Some(i) => i
      | None =>
        failwith(
          "Internal error: ListLoop placeholder not found in its parent " ++
          "buffer at finalisation time.",
        )
      }
      let forOfStmt = JsBuild.forOf(elemName, inputJsExpr, scope.buffer)
      let replacement = Array.concat(preLoopBuf, [forOfStmt])
      parentBuf->Array.splice(~start=idx, ~remove=1, ~insert=replacement)
    | _ =>
      failwith("Internal: pendingLoops entry is not a ListLoop.")
    }
  )

let finalizeDispatches = (ctx: compileCtx): unit =>
  ctx.pendingDispatches->Array.forEach(dispatchFlow =>
    switch dispatchFlow.kind {
    | CaseDispatch({
        dispParentBuf,
        dispPlaceholder,
        preDispatchBuf,
        splitName,
        alts,
        altScopes,
        demandsExhaustive,
      }) =>
      // Build the if-chain in reverse. For an exhaustive (case-close)
      // dispatch, every alt is included even if its body is empty,
      // and the chain ends with `else throw`. For a non-exhaustive
      // (filter-only) dispatch, only alts with non-empty bodies are
      // included, and there's no else clause.
      let elseClause = if demandsExhaustive {
        Some(
          JsAst.SThrow(
            JsBuild.new_(
              JsBuild.id("Error"),
              [
                JsBuild.add(
                  JsBuild.str("Unmatched case: "),
                  JsBuild.member(JsBuild.id(splitName), "tag"),
                ),
              ],
            ),
          ),
        )
      } else {
        None
      }
      let chain = ref(elseClause)
      for i in Array.length(alts) - 1 downto 0 {
        let altName = alts->Array.getUnsafe(i)
        let altScope = altScopes->Array.getUnsafe(i)
        let isActive = demandsExhaustive || Array.length(altScope.buffer) > 0
        if isActive {
          chain :=
            Some(
              JsAst.SIf({
                test: JsBuild.eq(
                  JsBuild.member(JsBuild.id(splitName), "tag"),
                  JsBuild.str(altName),
                ),
                cons: JsAst.SBlock(altScope.buffer),
                alt: chain.contents,
              }),
            )
        }
      }
      let chainStmts = switch chain.contents {
      | Some(stmt) => [stmt]
      | None => []
      }
      let replacement = Array.concat(preDispatchBuf, chainStmts)
      let idx = switch dispParentBuf->Array.indexOfOpt(dispPlaceholder) {
      | Some(i) => i
      | None =>
        failwith(
          "Internal error: CaseDispatch placeholder not found in its " ++
          "parent buffer at finalisation time.",
        )
      }
      dispParentBuf->Array.splice(~start=idx, ~remove=1, ~insert=replacement)
    | _ =>
      failwith("Internal: pendingDispatches entry is not a CaseDispatch.")
    }
  )

// --- Entry points ---

let compileToBody = (root: Expr.expr): (array<JsAst.stmt>, JsAst.expr) => {
  let counter = ref(0)
  let fresh = () => {
    let n = counter.contents
    counter := n + 1
    "v" ++ Int.toString(n)
  }
  let ctx: compileCtx = {
    outerStmts: [],
    hoistedLits: [],
    fresh,
    memo: Map.make(),
    flowMemo: Map.make(),
    pendingLoops: [],
    pendingDispatches: [],
  }
  let (final, _) = go(ctx, root)
  finalizeLoops(ctx)
  finalizeDispatches(ctx)
  (Array.concat(ctx.hoistedLits, ctx.outerStmts), final)
}

let compileToIIFE = (e: Expr.expr): JsAst.expr => {
  let (stmts, value) = compileToBody(e)
  let body = [...stmts, JsBuild.ret(value)]
  JsBuild.call(JsBuild.arrow([], body), [])
}
