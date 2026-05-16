// Compile an Expr.expr to JavaScript.
//
// Architecture: the visual language has two cooperating types in
// Expr.res — `expr` (value-typed) and `flowRef` (references to flows).
// The compiler mirrors that split with two entry points:
//
//   - `go(ctx, e)`        — value-port compile for an `expr`. Returns
//                            `(JsAst.expr, option<scopeRef>)`.
//   - `flowFor(ctx, fr)`  — flow-port compile for a `flowRef`. Returns
//                            an `openFlow` (lazily constructed and
//                            memoised by the underlying node id for
//                            NodeFlow refs).
//
// `go` dispatches by node kind:
//   - Lit:    emits a `const v_N = <literal>` into ctx.hoistedLits.
//   - App:    emits `const v_N = fn(...)` into the deepest of args'
//             scopes.
//   - Open ListIter:  triggers `flowFor(NodeFlow(e))` to construct the
//                     loop; the memo holds the per-iteration element
//                     binding.
//   - Branch (value port):  triggers `flowFor(NodeFlow(e))` to get the
//                           BranchOf; returns the per-alt v binding.
//   - Close:  calls consumeClose, which dispatches by inspecting the
//             first branch's flow kind (after peeling Joineds).
//   - Open CaseSplit:  failwith — no single value port (use Branch).
//
// `flowFor` dispatches by flowRef:
//   - NodeFlow(e):  look up e.id in flowMemo; on miss, construct based
//                   on e.kind:
//                   - Open ListIter:   ListLoop {scope, elemName,
//                                       parentBuf, placeholder,
//                                       preLoopBuf, …}.
//                   - Open CaseSplit:  CaseDispatch {parentScope,
//                                       parentBuf, placeholder,
//                                       splitName, alts, altScopes,
//                                       preDispatchBuf, …}.
//                   - Branch:          BranchOf {source = the
//                                       CaseDispatch, alt, valueName,
//                                       altScope}. Per-(CaseDispatch,
//                                       alt) cached so distinct Branch
//                                       nodes share one v binding.
//                   - Lit / App / Close:  failwith — these nodes have
//                                          no flow output port (this
//                                          is the remaining hole the
//                                          Expr types can't catch
//                                          without GADTs).
//   - Joined(inner):   pure structural wrapper; just constructs
//                      Joined({inner: flowFor(inner)}). No emission.
//                      Allowed inners: ListLoop, another Joined,
//                      Filtered (Joined-on-Filtered = filter-under-
//                      joined-lists; the Joined lifts the output a
//                      level higher).
//   - Filtered(inner): pure structural wrapper. Allowed inner: BranchOf.
//
// Consumers (Closes) attach lazily — no preprocess, no group
// coordination:
//   - consumeListClose — branch.flow = Joined^N(NodeFlow(opener)).
//     Walks Joineds to count joinDepth; walks `joinDepth` Open.input
//     levels up to find the outermost loop; pushes `const out = []`
//     into that loop's preLoopBuf; compiles the per-iteration value;
//     pushes into the innermost loop's body.
//   - consumeCaseClose — branch.flow = NodeFlow(branch). Validates
//     each branch references the same CaseDispatch and covers each
//     alt once; flips dispatch.demandsExhaustive on; pushes
//     `let v_close;` into the dispatch's preDispatchBuf; for each
//     branch, compiles the per-alt value into the alt's scope, appends
//     `v_close = value`.
//   - consumeFilterClose — branch.flow = Joined^N(Filtered(NodeFlow
//     (branch))). Walks Joineds to count joinDepth; finds the
//     innermost surrounding list loop via
//     flowFor(NodeFlow(dispatch.dispInputNode)); walks `joinDepth`
//     ListLoop levels up; pushes `const out = []` into that outermost
//     loop's preLoopBuf; compiles the value into the alt's scope;
//     pushes.
//
// Mixing case-close + filter-close on the same case-split: both
// attach to the same CaseDispatch via shared BranchOf flow entries.
// The case-close flips demandsExhaustive (so the if-chain ends with
// `else throw`); the filter-close just adds its push to the matching
// alt body.
//
// Finalisation. ListLoop and CaseDispatch each own a placeholder
// stmt they pushed into their parent buffer at construction time.
// After go(root) returns, finalizeLoops / finalizeDispatches walks
// the pendingLoops / pendingDispatches arrays and uses splice +
// reference equality on the placeholder to:
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
  // The case-split's `input` Expr — used by filter consumers to find
  // the surrounding list loop via flowFor(NodeFlow(dispInputNode)).
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

// Peel any Joined wrappers off a flowRef; return the inner flowRef and
// the number of Joineds peeled.
let unwrapJoinedRef = (fr: Expr.flowRef): (Expr.flowRef, int) => {
  let rec aux = (fr: Expr.flowRef, n: int): (Expr.flowRef, int) =>
    switch fr {
    | Joined(inner) => aux(inner, n + 1)
    | _ => (fr, n)
    }
  aux(fr, 0)
}

// Peel any Joined wrappers off a flowRef and require the result to be
// a NodeFlow on an Open ListIter; return that Open and the join depth.
// Used when constructing a CaseDispatch whose input is a Joined
// list-iter (the filter-under-joined-lists case).
let unwrapJoinedListIterNode = (fr: Expr.flowRef): option<(Expr.expr, int)> => {
  let (inner, depth) = unwrapJoinedRef(fr)
  switch inner {
  | NodeFlow(e) =>
    switch e.kind {
    | Open({flow: ListIter}) => Some((e, depth))
    | _ => None
    }
  | _ => None
  }
}

// --- Lazy flow construction & value-port compile (mutually recursive) ---

let rec flowFor = (ctx: compileCtx, fr: Expr.flowRef): openFlow =>
  switch fr {
  | NodeFlow(e) =>
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
        // Sentinel placeholder; replaced at finalisation. Each
        // SBlock([]) is a unique JS object by reference, so
        // Array.indexOfOpt finds it later.
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
        // Memoise the value port: per-iteration element binding lives
        // in the loop scope.
        ctx.memo->Map.set(e.id, (JsBuild.id(elemName), Some(scope)))
        ctx.pendingLoops->Array.push(f)
        f

      | Open({flow: CaseSplit({alts, discriminator}), input}) =>
        // The case-split's input is a value-port `expr`. For the
        // filter-under-joined-lists case, the diagram models the
        // join depth *on the input flow* — but we can't represent
        // that as a flowRef on the value-position input. Instead we
        // detect the pattern here: if input is the per-iter element
        // of a nested list iter, we record the join depth by looking
        // at how many Open ListIter levels are stacked under it.
        //
        // Concretely, today we trust the Expr author to supply the
        // *innermost* list's element as `input`; we compile the input
        // value normally (which triggers the inner ListLoop) and
        // record inputJoinDepth = 0 by default. The
        // filter-under-joined-lists pattern instead uses an explicit
        // Joined flowRef inside the close branch; consumeFilterClose
        // walks Joineds and lifts the output appropriately.
        let (inputJsExpr, parentScope) = go(ctx, input)
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
            dispInputNode: input,
            demandsExhaustive: false,
            altBranchCache: Map.make(),
          }),
        }
        ctx.pendingDispatches->Array.push(f)
        f

      | Branch({source, alt}) =>
        let dispatchFlow = flowFor(ctx, source)
        let dispatchData = switch dispatchFlow.kind {
        | CaseDispatch(d) => d
        | _ =>
          failwith(
            "Branch (id=" ++
            Int.toString(e.id) ++
            ") must reference a CaseSplit Open flow, but references a " ++
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
        // This is the remaining hole the user flagged: a flowRef of
        // shape NodeFlow(e) is legitimate as a syntax, but the node
        // might not have a flow output port. Without GADTs in the
        // Expr type, we can only catch this at compile time, here.
        failwith(
          "flowRef NodeFlow refers to node (id=" ++
          Int.toString(e.id) ++
          ") that has no flow output port. Only Open and Branch nodes " ++
          "have flow output ports.",
        )
      }
      ctx.flowMemo->Map.set(e.id, f)
      f
    }

  | Joined(inner) =>
    let innerFlow = flowFor(ctx, inner)
    switch innerFlow.kind {
    // Valid wraps: a list iter (basic join), an already-Joined (for
    // stacked joins), or a Filtered (filter under joined lists — the
    // Joined lifts the output above one more list level).
    | ListLoop(_) | Joined(_) | Filtered(_) => ()
    | _ =>
      failwith(
        "Joined wraps a flow that isn't a list iter or filter — Joined " ++
        "is only meaningful on ListLoop, another Joined, or a Filtered.",
      )
    }
    {id: -1, kind: Joined({inner: innerFlow})}

  | Filtered(inner) =>
    let innerFlow = flowFor(ctx, inner)
    switch innerFlow.kind {
    | BranchOf(_) => ()
    | _ =>
      failwith(
        "Filtered wraps a flow that isn't a Branch — Filtered is only " ++
        "meaningful on BranchOf.",
      )
    }
    {id: -1, kind: Filtered({inner: innerFlow})}
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
      let _ = flowFor(ctx, NodeFlow(e))
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
      let bof = flowFor(ctx, NodeFlow(e))
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
    // Peel any Joineds off the first branch's flow to determine the
    // close style. A list close has ListLoop underneath; a filter
    // close has Filtered; a case close has BranchOf (and shouldn't
    // have Joineds on top).
    let firstFlow = flowFor(ctx, (branches->Array.getUnsafe(0)).flow)
    let rec underlying = (f: openFlow) =>
      switch f.kind {
      | Joined({inner}) => underlying(inner)
      | _ => f
      }
    let under = underlying(firstFlow)
    switch under.kind {
    | BranchOf(_) => consumeCaseClose(ctx, close, branches)
    | Filtered(_) => consumeFilterClose(ctx, close, branches)
    | ListLoop(_) => consumeListClose(ctx, close, branches)
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
    curr := flowFor(ctx, NodeFlow(inputNode))
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
  // Per-close info: (alt, value, altScope, dispatchFlow, joinDepth).
  // Each branch's flow is Joined^N(Filtered(NodeFlow(branch))) where
  // N is the number of nested lists to lift the output above.
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
    let (filterRef, joinDepth) = unwrapJoinedRef(b.flow)
    let filterFlow = flowFor(ctx, filterRef)
    let bof = switch filterFlow.kind {
    | Filtered({inner}) => inner
    | _ =>
      failwith(
        "Filter close branch.flow (after peeling Joineds) is not a " ++
        "Filtered.",
      )
    }
    switch bof.kind {
    | BranchOf({alt, branchScope, source}) =>
      (alt, b.value, branchScope, source, joinDepth)
    | _ => failwith("Internal: Filtered inner is not a BranchOf")
    }
  })

  if Array.length(perCloseInfo) != 1 {
    failwith(
      "A filter close currently must have exactly one branch, but " ++
      "Close (id=" ++ Int.toString(close.id) ++ ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let (_, value, altScope, dispatchFlow, joinDepth) =
    perCloseInfo->Array.getUnsafe(0)
  let dispatchData = switch dispatchFlow.kind {
  | CaseDispatch(d) => d
  | _ => failwith("Internal")
  }

  // Find the innermost surrounding list loop: it's the ListLoop whose
  // per-iter value port IS the case-split's input. We construct (or
  // find) it via flowFor(NodeFlow(dispInputNode)).
  let innermostListFlow = flowFor(ctx, NodeFlow(dispatchData.dispInputNode))
  switch innermostListFlow.kind {
  | ListLoop(_) => ()
  | _ =>
    failwith(
      "Filter requires the case-split's input to be an Open ListIter, " ++
      "but it isn't.",
    )
  }
  let innermostLoopScope = switch innermostListFlow.kind {
  | ListLoop({scope}) => scope
  | _ => failwith("Internal")
  }

  // Walk up `joinDepth` ListLoop levels (via inputNode chain) to find
  // the outermost list whose parent scope is where the output array
  // should live.
  let curr = ref(innermostListFlow)
  for _ in 1 to joinDepth {
    let inputNode = switch (curr.contents).kind {
    | ListLoop({inputNode}) => inputNode
    | _ => failwith("Internal")
    }
    curr := flowFor(ctx, NodeFlow(inputNode))
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
  let outScope = walkUp(Some(innermostLoopScope), joinDepth + 1)
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
