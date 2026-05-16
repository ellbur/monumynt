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
//   - NodeFlow(e):  look up e.id in flowMemo; on miss, construct
//                   based on e.kind:
//                   - Open ListIter:    ListLoop(iterLoopData).
//                                        Wrapper at finalise is for-of.
//                   - Open OptionIter:  OptionLoop(iterLoopData).
//                                        Emits `const v_elem =
//                                        disc(input)` at construction;
//                                        wrapper at finalise is
//                                        `if (v_elem !== undefined)`.
//                                        Body runs zero or one times.
//                   - Open CaseSplit:   CaseDispatch {…}.
//                   - Branch:           BranchOf {source = the
//                                        CaseDispatch, alt, valueName,
//                                        altScope}. Per-(CaseDispatch,
//                                        alt) cached so distinct Branch
//                                        nodes share one v binding.
//                   - Lit / App / Close:  failwith — these nodes have
//                                          no flow output port (this
//                                          is the remaining hole the
//                                          Expr types can't catch
//                                          without GADTs).
//   - Joined(inner):   pure structural wrapper. Allowed inners: any
//                      iter flow (ListLoop / OptionLoop), another
//                      Joined (stacked), or a Filtered. Mixed iter
//                      chains are fine — what makes joins between
//                      option and list flows work.
//   - Filtered(inner): pure structural wrapper. Allowed inner: BranchOf.
//
// Consumers (Closes) attach lazily — no preprocess, no group
// coordination. consumeListClose and consumeOptionClose share the
// same shape via the `consumeIterClose` helper; they differ only in
// the iter-kind check and the output allocation / push form (array +
// .push vs let + assign):
//   - consumeListClose — branch.flow = Joined^N(NodeFlow(opener)).
//     Walks Joineds to count joinDepth; walks `joinDepth` iter levels
//     up via the inputNode chain to find the outermost iter (which
//     may itself be a ListLoop or OptionLoop); pushes `const out =
//     []` into that outermost's preLoopBuf; compiles the per-iter
//     value; pushes into the innermost loop's body.
//   - consumeOptionClose — same shape but `let out;` and `out =
//     value`. The body runs zero or one times.
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
  // A list iter — `for (const elem of input) { ... }`. Consumer
  // pushes via `out.push(value)`; output is `const out = []`.
  | ListLoop(iterLoopData)
  // An option iter — `if (elem !== undefined) { ... }` where `elem`
  // is the discriminator's result, bound just above the if. Consumer
  // pushes via `out = value`; output is `let out;` (undefined by
  // default). Body runs zero or one times.
  | OptionLoop(iterLoopData)
  | CaseDispatch(caseDispatchData)
  | Joined({inner: openFlow})
  | BranchOf(branchOfData)
  | Filtered({inner: openFlow})
// Data shared by ListLoop and OptionLoop — both are "iter flows" with
// the same scope / preLoopBuf / placeholder bookkeeping; they differ
// only in their finalisation target (for-of vs if) and in the push
// semantics their consumers use.
and iterLoopData = {
  // The iter body scope (loop body or if body). Push consumers append
  // into this buffer.
  scope: scopeRef,
  // For ListLoop: identifier bound by the for-of header.
  // For OptionLoop: identifier bound just before the if to the
  // discriminator's result (the some-value or undefined).
  elemName: string,
  // The buffer the for-of / if statement will be spliced into.
  parentBuf: array<JsAst.stmt>,
  // Sentinel pushed into parentBuf at construction; replaced at
  // finalisation by [...preLoopBuf, for-of-or-if].
  placeholder: JsAst.stmt,
  // Bindings that need to live above the for-of / if (e.g., output
  // arrays / let-decls). Spliced in immediately before the wrapper
  // statement at finalise.
  preLoopBuf: array<JsAst.stmt>,
  // For ListLoop: the compiled JS expression for the loop's input
  // list. For OptionLoop: unused (the elem binding already holds the
  // disc result).
  inputJsExpr: JsAst.expr,
  // The Expr.expr the Open's `input` field pointed to. Used to walk
  // further up an iter chain by re-flowFor-ing.
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

// --- Lazy flow construction & value-port compile (mutually recursive) ---
//
// Forward declaration order: walkUpListLoopChain references flowFor;
// they're together inside the mutual recursion block below.

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
        ctx.pendingLoops->Array.push(f)
        f

      | Open({flow: OptionIter({discriminator}), input}) =>
        // Compile the input, emit `const v_elem = disc(input)` (the
        // some-value or undefined), push a placeholder for the if
        // statement.
        let (inputJsExpr, parentScope) = go(ctx, input)
        let parentBuf = bufferOf(ctx, parentScope)
        let elemName = ctx.fresh()
        parentBuf->Array.push(
          JsBuild.const(elemName, JsBuild.call(discriminator, [inputJsExpr])),
        )
        let scope = {
          buffer: [],
          depth: depthOf(parentScope) + 1,
          parent: parentScope,
        }
        let placeholder = JsAst.SBlock([])
        parentBuf->Array.push(placeholder)
        let f = {
          id: e.id,
          kind: OptionLoop({
            scope,
            elemName,
            parentBuf,
            placeholder,
            preLoopBuf: [],
            inputJsExpr,
            inputNode: input,
          }),
        }
        ctx.pendingLoops->Array.push(f)
        f

      | Open({flow: CaseSplit({alts, discriminator}), input}) =>
        // Compile the input value (which for the case-split-in-list
        // pattern triggers an inner ListLoop's construction); emit
        // `const split = disc(input)` into that scope; allocate per-
        // alt scopes; push a placeholder for the if-chain.
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
    // Valid wraps: any iter flow (ListLoop, OptionLoop), an already-
    // Joined (for stacked joins), or a Filtered (filter under joined
    // lists — the Joined lifts the output above one more list level).
    | ListLoop(_) | OptionLoop(_) | Joined(_) | Filtered(_) => ()
    | _ =>
      failwith(
        "Joined wraps a flow that isn't an iter or filter — Joined " ++
        "is only meaningful on ListLoop, OptionLoop, another Joined, " ++
        "or a Filtered.",
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
      // The per-iter element binding *is* the value port; flowFor
      // constructs the loop and exposes both.
      switch (flowFor(ctx, NodeFlow(e))).kind {
      | ListLoop({scope, elemName}) => (JsBuild.id(elemName), Some(scope))
      | _ =>
        failwith(
          "Internal error: flowFor for an Open ListIter (id=" ++
          Int.toString(e.id) ++ ") didn't return a ListLoop.",
        )
      }

    | Open({flow: OptionIter(_)}) =>
      // The per-some elem binding (= disc result) is the value port.
      // Note: it lives at the parent scope but is only semantically
      // meaningful inside the if body — we report it as living in
      // the if's scope so consumers' deeper(...) keeps them inside.
      switch (flowFor(ctx, NodeFlow(e))).kind {
      | OptionLoop({scope, elemName}) => (JsBuild.id(elemName), Some(scope))
      | _ =>
        failwith(
          "Internal error: flowFor for an Open OptionIter (id=" ++
          Int.toString(e.id) ++ ") didn't return an OptionLoop.",
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
      // The per-alt v = split.value binding *is* the value port;
      // flowFor constructs (or finds) the BranchOf and exposes it.
      switch (flowFor(ctx, NodeFlow(e))).kind {
      | BranchOf({valueName, branchScope}) =>
        (JsBuild.id(valueName), Some(branchScope))
      | _ =>
        failwith(
          "Internal error: flowFor for a Branch (id=" ++
          Int.toString(e.id) ++ ") didn't return a BranchOf.",
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
    | OptionLoop(_) => consumeOptionClose(ctx, close, branches)
    | _ =>
      failwith(
        "Close (id=" ++
        Int.toString(close.id) ++
        ") branches[0].flow has an unrecognised flow kind.",
      )
    }
  | _ => failwith("Internal error: consumeClose called on non-Close.")
  }

// Walk up N iter-flow levels via the `inputNode` chain. Each step
// expects the current flow to be a ListLoop or OptionLoop and the
// next level (looked up by flowFor on the current's inputNode) to
// also be one; raises with a clear message otherwise. Mixed
// List/Option chains are fine — that's what makes joins between
// option and list flows work.
and walkUpIterChain = (
  ctx: compileCtx,
  start: openFlow,
  depth: int,
): openFlow => {
  let iterInputNode = (f: openFlow) =>
    switch f.kind {
    | ListLoop({inputNode}) | OptionLoop({inputNode}) => Some(inputNode)
    | _ => None
    }
  let curr = ref(start)
  for _ in 1 to depth {
    let inputNode = switch iterInputNode(curr.contents) {
    | Some(n) => n
    | None =>
      failwith(
        "Internal error: walkUpIterChain step from a non-iter flow.",
      )
    }
    curr := flowFor(ctx, NodeFlow(inputNode))
    if iterInputNode(curr.contents) == None {
      failwith(
        "Walking up the iter chain expected a ListLoop or OptionLoop " ++
        "at each level, but the chain ran out before the requested depth.",
      )
    }
  }
  curr.contents
}

// Extract the preLoopBuf from any iter flow (ListLoop or OptionLoop).
and iterPreLoopBuf = (f: openFlow): array<JsAst.stmt> =>
  switch f.kind {
  | ListLoop({preLoopBuf}) | OptionLoop({preLoopBuf}) => preLoopBuf
  | _ => failwith("Internal: iterPreLoopBuf called on non-iter flow.")
  }

// Helper for both list and option closes: validate single branch,
// walk Joineds, find innermost iter flow + joinDepth + innermost
// scope, find outermost flow in the chain, allocate the output
// binding in the outermost's preLoopBuf, register the close in
// ctx.memo, compile the value, and push via `emitPush`.
//
// `expectInnermost` is "list" or "option" — controls the kind check
// and the close-style label used in error messages.
// `allocOut` allocates the output stmt (e.g. `const v = []` or
// `let v;`) and returns the name.
// `emitPush` produces the push stmt given the out name and the
// compiled value expression.
and consumeIterClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
  closeStyle: string,
  expectInnermost: openFlow => option<scopeRef>,
  allocOut: string => JsAst.stmt,
  emitPush: (string, JsAst.expr) => JsAst.stmt,
): unit => {
  if Array.length(branches) != 1 {
    failwith(
      "A " ++ closeStyle ++ " close must have exactly one branch, " ++
      "but Close (id=" ++ Int.toString(close.id) ++ ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let branch = branches->Array.getUnsafe(0)
  switch branch.altName {
  | None => ()
  | Some(name) =>
    failwith(
      "A " ++ closeStyle ++ " close's branch must have altName=None, " ++
      "but Close (id=" ++ Int.toString(close.id) ++
      ")'s branch has altName=Some(\"" ++ name ++ "\").",
    )
  }

  // Walk Joineds to find the innermost iter flow and the joinDepth.
  let flow = flowFor(ctx, branch.flow)
  let rec unwrapIter = (f: openFlow, depth: int) =>
    switch f.kind {
    | Joined({inner}) => unwrapIter(inner, depth + 1)
    | _ => (f, depth)
    }
  let (innermost, joinDepth) = unwrapIter(flow, 0)
  let innerScope = switch expectInnermost(innermost) {
  | Some(s) => s
  | None =>
    failwith(
      "Internal error: " ++ closeStyle ++ "-close innermost flow has " ++
      "the wrong kind.",
    )
  }

  // Walk `joinDepth` levels up to find the outermost iter in the
  // chain; its preLoopBuf is where the output binding goes.
  let outermost = walkUpIterChain(ctx, innermost, joinDepth)
  let outermostPreLoopBuf = iterPreLoopBuf(outermost)

  // Allocate the output binding in the outermost iter's preLoopBuf.
  let outName = ctx.fresh()
  outermostPreLoopBuf->Array.push(allocOut(outName))
  let outScope = walkUp(Some(innerScope), joinDepth + 1)
  ctx.memo->Map.set(close.id, (JsBuild.id(outName), outScope))

  // Compile the per-iteration value, push at the deeper of innermost
  // iter scope and value scope.
  let (valueExpr, valueScope) = go(ctx, branch.value)
  let pushBuf = bufferOf(ctx, deeper(Some(innerScope), valueScope))
  pushBuf->Array.push(emitPush(outName, valueExpr))
}

and consumeListClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit =>
  consumeIterClose(
    ctx,
    close,
    branches,
    "list",
    f =>
      switch f.kind {
      | ListLoop({scope}) => Some(scope)
      | _ => None
      },
    name => JsBuild.const(name, JsBuild.array_([])),
    (name, value) =>
      JsBuild.exprStmt(
        JsBuild.call(
          JsBuild.member(JsBuild.id(name), "push"),
          [value],
        ),
      ),
  )

and consumeOptionClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit =>
  consumeIterClose(
    ctx,
    close,
    branches,
    "option",
    f =>
      switch f.kind {
      | OptionLoop({scope}) => Some(scope)
      | _ => None
      },
    name => JsBuild.letDecl(name),
    (name, value) =>
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(name), value)),
  )

and consumeCaseClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit => {
  // Resolve each branch's flow to a BranchOf, simultaneously checking
  // that all branches reference the same CaseDispatch and recording
  // (altName, BranchOf) per branch.
  let dispatchFlow = ref(None)
  let perBranch = branches->Array.map(b => {
    let altName = switch b.altName {
    | Some(n) => n
    | None =>
      failwith(
        "A case close's branches must each have altName=Some(name), " ++
        "but Close (id=" ++ Int.toString(close.id) ++
        ") has a branch with altName=None.",
      )
    }
    let source = switch (flowFor(ctx, b.flow)).kind {
    | BranchOf({source}) => source
    | _ =>
      failwith(
        "Case close (id=" ++ Int.toString(close.id) ++
        ") has a branch (alt=\"" ++ altName ++
        "\") whose flow is not a Branch node.",
      )
    }
    switch dispatchFlow.contents {
    | None => dispatchFlow := Some(source)
    | Some(d) =>
      if source.id != d.id {
        failwith(
          "Case close (id=" ++ Int.toString(close.id) ++
          ") has branches whose flows reference different CaseSplit Opens.",
        )
      }
    }
    (altName, b.value)
  })
  let dispatchFlow = Option.getOrThrow(dispatchFlow.contents)
  let dispatchData = switch dispatchFlow.kind {
  | CaseDispatch(d) => d
  | _ => failwith("Internal: case close's source isn't a CaseDispatch.")
  }

  // Exhaustiveness: every alt must be covered exactly once.
  dispatchData.alts->Array.forEach(altName => {
    let count = perBranch->Array.reduce(0, (acc, (name, _)) =>
      if name == altName { acc + 1 } else { acc }
    )
    if count != 1 {
      failwith(
        "Case close (id=" ++ Int.toString(close.id) ++
        ") must have exactly one branch for alt \"" ++ altName ++
        "\" (found " ++ Int.toString(count) ++ ").",
      )
    }
  })

  // Tell the dispatch its if-chain ends with an else-throw.
  dispatchData.demandsExhaustive = true

  // Allocate `let v_close;` in the dispatch's preDispatchBuf.
  let resultName = ctx.fresh()
  dispatchData.preDispatchBuf->Array.push(JsBuild.letDecl(resultName))
  ctx.memo->Map.set(
    close.id,
    (JsBuild.id(resultName), dispatchData.dispParentScope),
  )

  // For each branch: compile its value into the alt's scope and
  // append the `v_close = value` assignment.
  perBranch->Array.forEach(((altName, value)) => {
    let altIdx = dispatchData.alts->Array.findIndex(a => a == altName)
    let altScope = dispatchData.altScopes->Array.getUnsafe(altIdx)
    let (valueExpr, _) = go(ctx, value)
    altScope.buffer->Array.push(
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(resultName), valueExpr)),
    )
  })
}

and consumeFilterClose = (
  ctx: compileCtx,
  close: Expr.expr,
  branches: array<Expr.closeBranch>,
): unit => {
  // Today a filter close has exactly one branch. The shape is
  // `Joined^N(Filtered(NodeFlow(branch)))` where N is how many list
  // scopes up to lift the output array. (Multi-filter on different
  // alts of one case-split is expressed by separate filter Closes
  // sharing the case-split; they attach independently.)
  if Array.length(branches) != 1 {
    failwith(
      "A filter close currently must have exactly one branch, but " ++
      "Close (id=" ++ Int.toString(close.id) ++ ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let branch = branches->Array.getUnsafe(0)
  switch branch.altName {
  | None => ()
  | Some(name) =>
    failwith(
      "A filter close's branch must have altName=None, but Close (id=" ++
      Int.toString(close.id) ++
      ")'s branch has altName=Some(\"" ++ name ++ "\").",
    )
  }

  // Peel Joineds for joinDepth; underneath must be Filtered(BranchOf).
  let (filterRef, joinDepth) = unwrapJoinedRef(branch.flow)
  let (altScope, dispatchFlow) = switch (flowFor(ctx, filterRef)).kind {
  | Filtered({inner}) =>
    switch inner.kind {
    | BranchOf({branchScope, source}) => (branchScope, source)
    | _ => failwith("Internal: Filtered inner is not a BranchOf.")
    }
  | _ =>
    failwith(
      "Filter close branch.flow (after peeling Joineds) is not a Filtered.",
    )
  }
  let dispatchData = switch dispatchFlow.kind {
  | CaseDispatch(d) => d
  | _ => failwith("Internal: filter's source is not a CaseDispatch.")
  }

  // The innermost surrounding list loop is the ListLoop whose
  // per-iter value port IS the case-split's input; flowFor finds it
  // (constructing if needed). Walk `joinDepth` up to find the
  // outermost loop whose parent is where the output array lives.
  let innermostListFlow = flowFor(ctx, NodeFlow(dispatchData.dispInputNode))
  let innermostLoopScope = switch innermostListFlow.kind {
  | ListLoop({scope}) => scope
  | _ =>
    failwith(
      "Filter requires the case-split's input to be an Open ListIter, " ++
      "but it isn't.",
    )
  }
  let outermost = walkUpIterChain(ctx, innermostListFlow, joinDepth)
  let outermostPreLoopBuf = iterPreLoopBuf(outermost)

  let outName = ctx.fresh()
  outermostPreLoopBuf->Array.push(JsBuild.const(outName, JsBuild.array_([])))
  let outScope = walkUp(Some(innermostLoopScope), joinDepth + 1)
  ctx.memo->Map.set(close.id, (JsBuild.id(outName), outScope))

  // Compile value, push into the alt's body.
  let (valueExpr, _) = go(ctx, branch.value)
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
  ctx.pendingLoops->Array.forEach(loopFlow => {
    // Common bookkeeping: locate the placeholder, build the wrapper
    // statement, splice in [...preLoopBuf, wrapper].
    let (parentBuf, placeholder, preLoopBuf, wrapperStmt, label) =
      switch loopFlow.kind {
      | ListLoop({parentBuf, placeholder, preLoopBuf, scope, elemName, inputJsExpr}) => (
          parentBuf,
          placeholder,
          preLoopBuf,
          JsBuild.forOf(elemName, inputJsExpr, scope.buffer),
          "ListLoop",
        )
      | OptionLoop({parentBuf, placeholder, preLoopBuf, scope, elemName}) =>
        // if (v_elem !== undefined) { ... }
        let test = JsBuild.neq(JsBuild.id(elemName), JsBuild.undefined)
        (
          parentBuf,
          placeholder,
          preLoopBuf,
          JsBuild.if_(test, scope.buffer),
          "OptionLoop",
        )
      | _ =>
        failwith(
          "Internal: pendingLoops entry is not a ListLoop or OptionLoop.",
        )
      }
    let idx = switch parentBuf->Array.indexOfOpt(placeholder) {
    | Some(i) => i
    | None =>
      failwith(
        "Internal error: " ++ label ++ " placeholder not found in its " ++
        "parent buffer at finalisation time.",
      )
    }
    let replacement = Array.concat(preLoopBuf, [wrapperStmt])
    parentBuf->Array.splice(~start=idx, ~remove=1, ~insert=replacement)
  })

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
