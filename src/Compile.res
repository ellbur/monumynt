// Compile an Expr.expr to JavaScript using runtime laziness.
//
// Model: every Expr node compiles to a `lazy` JS binding; every
// reference forces. The compiler decides almost nothing about
// placement — each binding goes in the scope its inputs deem (eager
// `deeper(args)`), and runtime laziness handles "compute only when
// needed" and "compute only once" automatically.
//
// Each Close becomes a lazy whose thunk runs the iteration logic.
// Multi-close on one opener compiles to one lazy per close; each
// thunk iterates independently. Sharing across iterations of one
// close is preserved (forced values cache). Sharing across separate
// closes' loops is not — this is the cost of the simple model.
//
// Runtime helpers emitted at the top of every IIFE:
//
//   const __lazy__ = (t) => ({v: undefined, t, c: false});
//   const __lazyDone__ = (v) => ({v, t: null, c: true});
//   const __force__ = (z) => {
//     if (!z.c) { z.v = z.t(); z.t = null; z.c = true; }
//     return z.v;
//   };
//
// A simpler / tighter compile lived here through commit 750b14c —
// consumer-driven placement with loop-depth-bounded sinking, the
// "value used only inside a conditional sinks into its body" trick,
// and the placeholder-move-on-first-consume ordering bookkeeping.
// See `plans/placement-algorithm-notes.md` for the design and why
// it was retired in favour of runtime laziness. It's a plausible
// future optimisation pass once the language semantics stabilises.

// --- Compile-side types ---

type rec bodyRef = {
  buffer: array<JsAst.stmt>,
  depth: int,
  parent: option<bodyRef>,
}

type compileCtx = {
  outerStmts: array<JsAst.stmt>,
  fresh: unit => string,
  // Per Expr.id, the bindings that have been emitted, each with the
  // body it lives in. compileExpr scans for a binding whose body is
  // an ancestor of (or equal to) the requested currentBody and reuses
  // it; if no accessible binding exists, a fresh one is emitted in
  // the appropriate body.
  memo: Map.t<int, array<(option<bodyRef>, string)>>,
}

// --- Body helpers ---

let depthOf = (b: option<bodyRef>): int =>
  switch b {
  | Some(s) => s.depth
  | None => 0
  }

let deeper = (
  a: option<bodyRef>,
  b: option<bodyRef>,
): option<bodyRef> =>
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

let bufferOf = (ctx: compileCtx, b: option<bodyRef>): array<JsAst.stmt> =>
  switch b {
  | Some(s) => s.buffer
  | None => ctx.outerStmts
  }

let mkBody = (parent: option<bodyRef>): bodyRef => {
  buffer: [],
  depth: depthOf(parent) + 1,
  parent,
}

let rec isAncestor = (
  anc: option<bodyRef>,
  desc: option<bodyRef>,
): bool =>
  switch (anc, desc) {
  | (None, _) => true
  | (Some(_), None) => false
  | (Some(a), Some(d)) =>
    if d === a {
      true
    } else {
      isAncestor(anc, d.parent)
    }
  }

let lookupMemo = (
  ctx: compileCtx,
  id: int,
  currentBody: option<bodyRef>,
): option<string> =>
  switch ctx.memo->Map.get(id) {
  | None => None
  | Some(entries) =>
    entries
    ->Array.find(((body, _)) => isAncestor(body, currentBody))
    ->Option.map(((_, name)) => name)
  }

let recordMemo = (
  ctx: compileCtx,
  id: int,
  body: option<bodyRef>,
  name: string,
): unit => {
  let arr = switch ctx.memo->Map.get(id) {
  | Some(a) => a
  | None =>
    let a = []
    ctx.memo->Map.set(id, a)
    a
  }
  arr->Array.push((body, name))
}

// --- JS lazy expression builders ---

let lazyOf = (thunk: array<JsAst.stmt>): JsAst.expr =>
  JsBuild.call(JsBuild.id("__lazy__"), [JsBuild.arrow([], thunk)])

let lazyDoneOf = (v: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__lazyDone__"), [v])

let forceOf = (v: JsAst.expr): JsAst.expr =>
  JsBuild.call(JsBuild.id("__force__"), [v])

// --- Flow-ref helpers ---

// Peel any Joineds, returning the inner flowRef and the join depth.
let unwrapJoinedRef = (fr: Expr.flowRef): (Expr.flowRef, int) => {
  let rec aux = (fr, n) =>
    switch fr {
    | Expr.Joined(inner) => aux(inner, n + 1)
    | _ => (fr, n)
    }
  aux(fr, 0)
}

// Walk a chain of openers: starting from `opener` (innermost),
// follow `.input` for `depth` more steps. Returns [innermost, ...,
// outermost], length depth + 1.
let walkOpenerChain = (opener: Expr.expr, depth: int): array<Expr.expr> => {
  let chain = [opener]
  let curr = ref(opener)
  for _ in 1 to depth {
    let next = switch (curr.contents).kind {
    | Open({input}) => Expr.nodeOf(input)
    | _ =>
      failwith(
        "walkOpenerChain: a Joined flow expects each level's input to " ++
        "also be an Open, but ran out of Opens before reaching the " ++
        "requested join depth.",
      )
    }
    chain->Array.push(next)
    curr := next
  }
  chain
}

// --- The main compile entry: produce a name (and side-effect: emit) ---

let rec compileExpr = (
  ctx: compileCtx,
  e: Expr.expr,
  currentBody: option<bodyRef>,
): string =>
  switch lookupMemo(ctx, e.id, currentBody) {
  | Some(name) => name
  | None =>
    switch e.kind {
    | Lit(js) => emitLit(ctx, e.id, js)
    | App({fn, args}) => emitApp(ctx, e.id, fn, args, currentBody)
    | Open(_) =>
      // Opens have value ports only inside their consuming Close's
      // thunk, where the Close manually memoises them. Reaching one
      // here means the Expr referenced an Open's value outside any
      // of its Closes.
      failwith(
        "Open (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value outside any consuming Close. An " ++
        "Open's value port (per-iter element, some-value, or per-alt " ++
        "payload) is only meaningful inside the corresponding Close's " ++
        "thunk.",
      )
    | Branch(_) =>
      // Same logic as Open: Branch's value port is memoised by the
      // surrounding case-close compile inside the alt's body.
      failwith(
        "Branch (id=" ++
        Int.toString(e.id) ++
        ") was reached as a value outside its containing case-close's " ++
        "alt body.",
      )
    | Close({branches}) =>
      emitClose(ctx, e.id, branches, currentBody)
    }
  }

// Compile the node behind a value ref. All refs name their node's one
// "value" port today, so this is just a projection; per-port dispatch
// arrives with migration step 2.
and compileValueRef = (
  ctx: compileCtx,
  r: Expr.valueRef,
  currentBody: option<bodyRef>,
): string => compileExpr(ctx, Expr.nodeOf(r), currentBody)

// --- Per-kind emitters ---

and emitLit = (ctx: compileCtx, id: int, js: JsAst.expr): string => {
  let name = ctx.fresh()
  // Lits are pure constants; emit at outerStmts. Wrap in lazyDone so
  // every binding looks uniform (just an already-computed lazy).
  ctx.outerStmts->Array.push(JsBuild.const(name, lazyDoneOf(js)))
  recordMemo(ctx, id, None, name)
  name
}

and emitApp = (
  ctx: compileCtx,
  id: int,
  fn: JsAst.expr,
  args: array<Expr.valueRef>,
  currentBody: option<bodyRef>,
): string => {
  // Compile every arg first to know each arg's body.
  let argNames = args->Array.map(a => compileValueRef(ctx, a, currentBody))
  // Each arg's body = the body its memo entry lives in.
  let argBodies = args->Array.map(a =>
    switch ctx.memo->Map.get(Expr.nodeOf(a).id) {
    | Some(entries) =>
      entries
      ->Array.find(((body, _)) => isAncestor(body, currentBody))
      ->Option.map(((b, _)) => b)
      ->Option.getOr(currentBody)
    | None => currentBody
    }
  )
  let target = argBodies->Array.reduce(None, deeper)
  let name = ctx.fresh()
  // const v = __lazy__(() => fn(__force__(arg1), __force__(arg2), …))
  let body = JsBuild.call(
    fn,
    argNames->Array.map(n => forceOf(JsBuild.id(n))),
  )
  // Single-expression arrow keeps the JS readable.
  let thunk = JsBuild.arrowExpr([], body)
  let lazyExpr = JsBuild.call(JsBuild.id("__lazy__"), [thunk])
  bufferOf(ctx, target)->Array.push(JsBuild.const(name, lazyExpr))
  recordMemo(ctx, id, target, name)
  name
}

and emitClose = (
  ctx: compileCtx,
  closeId: int,
  branches: array<Expr.closeBranch>,
  currentBody: option<bodyRef>,
): string => {
  // Dispatch by examining branches[0].flow (after peeling Joineds)
  // exactly the same way previous compiles did. The shape decides
  // whether this is a list/option/case/filter close.
  let firstBranchFlow = (branches->Array.getUnsafe(0)).flow
  let (peeledFirst, _) = unwrapJoinedRef(firstBranchFlow)
  switch peeledFirst {
  | Expr.NodeFlow(e) =>
    switch e.kind {
    | Open({flow: ListIter}) | Open({flow: OptionIter}) =>
      emitIterClose(ctx, closeId, branches, currentBody)
    | Branch(_) =>
      emitCaseClose(ctx, closeId, branches, currentBody)
    | _ =>
      failwith(
        "Close (id=" ++
        Int.toString(closeId) ++
        ") branches[0].flow's underlying node has no flow output port.",
      )
    }
  | Expr.Filtered(_) =>
    emitFilterClose(ctx, closeId, branches, currentBody)
  | Expr.Joined(_) =>
    failwith("Internal: unwrapJoinedRef left a Joined on top.")
  }
}

// Iter close (handles any chain of ListIter and OptionIter openers,
// with any number of Joineds on top). The thunk wraps the innermost
// value in for-of / if statements per the chain composition. Output
// form follows the "any list in chain → list" rule: if any iter is
// a list, output is `const out = []` + push; if all options, output
// is `let out;` + assign.
and emitIterClose = (
  ctx: compileCtx,
  closeId: int,
  branches: array<Expr.closeBranch>,
  currentBody: option<bodyRef>,
): string => {
  if Array.length(branches) != 1 {
    failwith(
      "An option close must have exactly one branch, but Close (id=" ++
      Int.toString(closeId) ++
      ") has " ++ Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let branch = branches->Array.getUnsafe(0)
  let (innerFlow, joinDepth) = unwrapJoinedRef(branch.flow)
  let innermostOpener = switch innerFlow {
  | NodeFlow(e) => e
  | _ =>
    failwith(
      "Option close's branch.flow (after peeling Joineds) is not a " ++
      "NodeFlow.",
    )
  }
  let chain = walkOpenerChain(innermostOpener, joinDepth)
  // Classify each level (List or Option) by its Open's flow kind.
  let isListAt = chain->Array.map(e =>
    switch e.kind {
    | Open({flow: ListIter}) => true
    | Open({flow: OptionIter}) => false
    | _ =>
      failwith(
        "Option close chain expected each level to be an Open ListIter " ++
        "or OptionIter, found something else.",
      )
    }
  )
  let anyList = isListAt->Array.some(b => b)
  let outermost = chain->Array.getUnsafe(joinDepth)
  let outermostInput = switch outermost.kind {
  | Open({input}) => input
  | _ => failwith("Internal: outermost is not an Open.")
  }
  let inputName = compileValueRef(ctx, outermostInput, currentBody)

  let outName = ctx.fresh()
  let thunkBody =
    if anyList {
      [JsBuild.const(outName, JsBuild.array_([]))]
    } else {
      [JsBuild.letDecl(outName)]
    }

  let rec buildLevel = (
    level: int,
    outerBody: option<bodyRef>,
    inLevelJs: JsAst.expr,
    parentBuf: array<JsAst.stmt>,
  ): unit => {
    let openerNode = chain->Array.getUnsafe(joinDepth - level)
    let isList = isListAt->Array.getUnsafe(joinDepth - level)
    if isList {
      let iterName = ctx.fresh()
      let vElemName = ctx.fresh()
      let forBodyRef = mkBody(outerBody)
      forBodyRef.buffer->Array.push(
        JsBuild.const(vElemName, lazyDoneOf(JsBuild.id(iterName))),
      )
      recordMemo(ctx, openerNode.id, Some(forBodyRef), vElemName)
      if level < joinDepth {
        buildLevel(
          level + 1,
          Some(forBodyRef),
          forceOf(JsBuild.id(vElemName)),
          forBodyRef.buffer,
        )
      } else {
        emitInnerPushOrAssign(
          ctx, branch, anyList, outName, forBodyRef, forBodyRef.buffer,
        )
      }
      parentBuf->Array.push(
        JsBuild.forOf(iterName, inLevelJs, forBodyRef.buffer),
      )
    } else {
      // Option level: hoist `const v_inner = force(inLevelJs);` just
      // before the if, then `if (v_inner !== undefined) { const
      // v_elem = lazyDone(v_inner); … }`.
      let vElemName = ctx.fresh()
      let ifBodyRef = mkBody(outerBody)
      let innerName = ctx.fresh()
      parentBuf->Array.push(JsBuild.const(innerName, inLevelJs))
      ifBodyRef.buffer->Array.push(
        JsBuild.const(vElemName, lazyDoneOf(JsBuild.id(innerName))),
      )
      recordMemo(ctx, openerNode.id, Some(ifBodyRef), vElemName)
      if level < joinDepth {
        buildLevel(
          level + 1,
          Some(ifBodyRef),
          forceOf(JsBuild.id(vElemName)),
          ifBodyRef.buffer,
        )
      } else {
        emitInnerPushOrAssign(
          ctx, branch, anyList, outName, ifBodyRef, ifBodyRef.buffer,
        )
      }
      parentBuf->Array.push(
        JsBuild.if_(
          JsBuild.neq(JsBuild.id(innerName), JsBuild.undefined),
          ifBodyRef.buffer,
        ),
      )
    }
  }
  buildLevel(0, currentBody, forceOf(JsBuild.id(inputName)), thunkBody)
  thunkBody->Array.push(JsBuild.ret(JsBuild.id(outName)))

  let name = ctx.fresh()
  bufferOf(ctx, currentBody)->Array.push(
    JsBuild.const(name, lazyOf(thunkBody)),
  )
  recordMemo(ctx, closeId, currentBody, name)
  name
}

// Shared inner-push helper for option close: either push to the list
// accumulator (when the chain has a list) or assign to the let
// accumulator (when the whole chain is options).
and emitInnerPushOrAssign = (
  ctx: compileCtx,
  branch: Expr.closeBranch,
  anyList: bool,
  outName: string,
  innerBodyRef: bodyRef,
  innerBuf: array<JsAst.stmt>,
): unit => {
  let valueName = compileValueRef(ctx, branch.value, Some(innerBodyRef))
  let pushOrAssign = if anyList {
    JsBuild.call(
      JsBuild.member(JsBuild.id(outName), "push"),
      [forceOf(JsBuild.id(valueName))],
    )
  } else {
    JsBuild.assign(JsBuild.id(outName), forceOf(JsBuild.id(valueName)))
  }
  innerBuf->Array.push(JsBuild.exprStmt(pushOrAssign))
}

// Case close.
//
//   const v_close = __lazy__(() => {
//     const v_split = __force__(disc_lazy);
//     // But split has no lazy of its own — we compute disc(input) per
//     // dispatch. Actually we wrap it: const v_split = disc(force(input)).
//     let v_out;
//     if (v_split.tag === alt0) {
//       const v_v0 = __lazyDone__(v_split.value);
//       … compile alt0's value …
//       v_out = __force__(value0);
//     } else if (v_split.tag === alt1) { … } else { throw … }
//     return v_out;
//   });
and emitCaseClose = (
  ctx: compileCtx,
  closeId: int,
  branches: array<Expr.closeBranch>,
  currentBody: option<bodyRef>,
): string => {
  // The dispatch we're closing — look at the first branch's flow
  // (NodeFlow(branch_node)) and follow to its source.
  let firstBranch = branches->Array.getUnsafe(0)
  let firstBranchNode = switch firstBranch.flow {
  | NodeFlow(e) =>
    switch e.kind {
    | Branch(_) => e
    | _ =>
      failwith(
        "Case close (id=" ++
        Int.toString(closeId) ++
        ") branches[0].flow's underlying node is not a Branch.",
      )
    }
  | _ => failwith("Internal")
  }
  let firstBranchSource = switch firstBranchNode.kind {
  | Branch({source}) => source
  | _ => failwith("Internal")
  }
  let caseSplitOpen = switch firstBranchSource {
  | NodeFlow(e) =>
    switch e.kind {
    | Open({flow: CaseSplit(_)}) => e
    | _ => failwith("Branch.source must be NodeFlow on a CaseSplit Open.")
    }
  | _ => failwith("Branch.source must be NodeFlow on a CaseSplit Open.")
  }
  let (alts, discriminator, caseSplitInput) = switch caseSplitOpen.kind {
  | Open({flow: CaseSplit({alts, discriminator}), input}) =>
    (alts, discriminator, input)
  | _ => failwith("Internal")
  }

  // Validate: every branch references a Branch on this CaseSplit,
  // altName covers each alt exactly once.
  branches->Array.forEach(b =>
    switch b.altName {
    | Some(_) => ()
    | None =>
      failwith(
        "A case close's branches must each have altName=Some(name), " ++
        "but Close (id=" ++ Int.toString(closeId) ++
        ") has a branch with altName=None.",
      )
    }
  )
  alts->Array.forEach(altName => {
    let count = branches->Array.reduce(0, (acc, b) =>
      switch b.altName {
      | Some(name) if name == altName => acc + 1
      | _ => acc
      }
    )
    if count != 1 {
      failwith(
        "Case close (id=" ++ Int.toString(closeId) ++
        ") must have exactly one branch for alt \"" ++ altName ++
        "\" (found " ++ Int.toString(count) ++ ").",
      )
    }
  })

  let inputName = compileValueRef(ctx, caseSplitInput, currentBody)

  let thunkBody: array<JsAst.stmt> = []
  let splitName = ctx.fresh()
  thunkBody->Array.push(
    JsBuild.const(
      splitName,
      JsBuild.call(discriminator, [forceOf(JsBuild.id(inputName))]),
    ),
  )
  let outName = ctx.fresh()
  thunkBody->Array.push(JsBuild.letDecl(outName))

  // Build the if-chain in reverse.
  let elseClause: option<JsAst.stmt> = Some(
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
  let chain = ref(elseClause)
  for i in Array.length(alts) - 1 downto 0 {
    let altName = alts->Array.getUnsafe(i)
    // Each branch's value subtree compiles inside this alt's body.
    let altBodyRef = mkBody(None)
    // Find this alt's branch.
    let branchOpt = branches->Array.find(b =>
      switch b.altName {
      | Some(n) => n == altName
      | None => false
      }
    )
    switch branchOpt {
    | Some(b) =>
      // For each Branch node referencing (caseSplitOpen, altName)
      // in this close's value subtrees, memoise the Branch's id to
      // a shared `const v = lazyDone(force(v_split).value)` binding
      // inside this alt body. compileExpr will resolve the Branch
      // via lookupMemo when it walks into the value subtree.
      let vAltValName = ctx.fresh()
      altBodyRef.buffer->Array.push(
        JsBuild.const(
          vAltValName,
          lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")),
        ),
      )
      let collected = []
      collectBranchesByAlt(
        Expr.NodeFlow(firstBranchNode),
        b.value,
        caseSplitOpen.id,
        altName,
        collected,
      )
      collected->Array.forEach((branchNode: Expr.expr) =>
        recordMemo(ctx, branchNode.id, Some(altBodyRef), vAltValName)
      )
      let valueName = compileValueRef(ctx, b.value, Some(altBodyRef))
      altBodyRef.buffer->Array.push(
        JsBuild.exprStmt(
          JsBuild.assign(
            JsBuild.id(outName),
            forceOf(JsBuild.id(valueName)),
          ),
        ),
      )
    | None => failwith("Internal: validated above.")
    }
    chain :=
      Some(
        JsAst.SIf({
          test: JsBuild.eq(
            JsBuild.member(JsBuild.id(splitName), "tag"),
            JsBuild.str(altName),
          ),
          cons: JsAst.SBlock(altBodyRef.buffer),
          alt: chain.contents,
        }),
      )
  }
  switch chain.contents {
  | Some(s) => thunkBody->Array.push(s)
  | None => ()
  }
  thunkBody->Array.push(JsBuild.ret(JsBuild.id(outName)))

  let name = ctx.fresh()
  bufferOf(ctx, currentBody)->Array.push(
    JsBuild.const(name, lazyOf(thunkBody)),
  )
  recordMemo(ctx, closeId, currentBody, name)
  name
}

// Walk an Expr / flowRef subtree, collecting every Branch node whose
// (source.id, alt) matches the given (caseSplitId, alt). Used by
// emitCaseClose to pre-memoise all alt-specific Branch nodes to the
// alt's shared `v = split.value` binding.
and collectBranchesByAlt = (
  flowRef: Expr.flowRef,
  value: Expr.valueRef,
  caseSplitId: int,
  alt: string,
  acc: array<Expr.expr>,
): unit => {
  let visited: Map.t<int, bool> = Map.make()
  let rec visitExpr = (e: Expr.expr) =>
    if !(visited->Map.has(e.id)) {
      visited->Map.set(e.id, true)
      switch e.kind {
      | Lit(_) => ()
      | App({args}) => args->Array.forEach(visitValueRef)
      | Open({input}) => visitValueRef(input)
      | Close({branches}) =>
        branches->Array.forEach(b => {
          visitFlowRef(b.flow)
          visitValueRef(b.value)
        })
      | Branch({source, alt: a}) =>
        // Is this Branch's (source, alt) the one we're after?
        switch source {
        | NodeFlow(srcE) when srcE.id == caseSplitId && a == alt =>
          acc->Array.push(e)
        | _ => ()
        }
        visitFlowRef(source)
      }
    }
  and visitFlowRef = (fr: Expr.flowRef) =>
    switch fr {
    | NodeFlow(e) => visitExpr(e)
    | Joined(inner) => visitFlowRef(inner)
    | Filtered(inner) => visitFlowRef(inner)
    }
  and visitValueRef = (r: Expr.valueRef) => visitExpr(Expr.nodeOf(r))
  let _ = flowRef
  visitValueRef(value)
}

// Filter close. Compiles to a list-style accumulator inside a
// for-of containing the case-dispatch; the push happens inside the
// matching alt's if-body.
and emitFilterClose = (
  ctx: compileCtx,
  closeId: int,
  branches: array<Expr.closeBranch>,
  currentBody: option<bodyRef>,
): string => {
  if Array.length(branches) != 1 {
    failwith(
      "A filter close currently must have exactly one branch, but " ++
      "Close (id=" ++ Int.toString(closeId) ++ ") has " ++
      Int.toString(Array.length(branches)) ++ ".",
    )
  }
  let branch = branches->Array.getUnsafe(0)
  // branch.flow = Joined^N(Filtered(NodeFlow(branch_node))).
  let (filterRef, joinDepth) = unwrapJoinedRef(branch.flow)
  let branchNode = switch filterRef {
  | Filtered(NodeFlow(e)) =>
    switch e.kind {
    | Branch(_) => e
    | _ => failwith("Filtered must wrap a Branch.")
    }
  | _ => failwith("Filter close's flow (peeled) is not a Filtered.")
  }
  let (alt, branchSource) = switch branchNode.kind {
  | Branch({source, alt}) => (alt, source)
  | _ => failwith("Internal")
  }
  let caseSplitOpen = switch branchSource {
  | NodeFlow(e) =>
    switch e.kind {
    | Open({flow: CaseSplit(_)}) => e
    | _ => failwith("Filter's Branch must reference a CaseSplit Open.")
    }
  | _ => failwith("Filter's Branch must reference a CaseSplit via NodeFlow.")
  }
  let (alts, discriminator, caseSplitInput) = switch caseSplitOpen.kind {
  | Open({flow: CaseSplit({alts, discriminator}), input}) =>
    (alts, discriminator, input)
  | _ => failwith("Internal")
  }
  if !(alts->Array.includes(alt)) {
    failwith("Filter alt \"" ++ alt ++ "\" not in CaseSplit's alts.")
  }
  // The CaseSplit's input must be an Open ListIter (so the filter has
  // a containing list to iterate); the join depth lifts the output
  // up across that many ancestor list iters.
  let innerListOpener = Expr.nodeOf(caseSplitInput)
  switch innerListOpener.kind {
  | Open({flow: ListIter}) => ()
  | _ =>
    failwith(
      "Filter requires the case-split's input to be an Open ListIter.",
    )
  }
  let chain = walkOpenerChain(innerListOpener, joinDepth)
  let outermost = chain->Array.getUnsafe(joinDepth)
  let outermostInput = switch outermost.kind {
  | Open({input}) => input
  | _ => failwith("Internal")
  }
  let inputName = compileValueRef(ctx, outermostInput, currentBody)

  let outName = ctx.fresh()
  let thunkBody = [JsBuild.const(outName, JsBuild.array_([]))]

  let rec buildLevel = (
    level: int,
    outerBody: option<bodyRef>,
    iterInputJs: JsAst.expr,
    parentBuf: array<JsAst.stmt>,
  ): unit => {
    let openerNode = chain->Array.getUnsafe(joinDepth - level)
    let iterName = ctx.fresh()
    let vElemName = ctx.fresh()
    let forBodyRef = mkBody(outerBody)
    forBodyRef.buffer->Array.push(
      JsBuild.const(vElemName, lazyDoneOf(JsBuild.id(iterName))),
    )
    recordMemo(ctx, openerNode.id, Some(forBodyRef), vElemName)
    if level < joinDepth {
      buildLevel(
        level + 1,
        Some(forBodyRef),
        forceOf(JsBuild.id(vElemName)),
        forBodyRef.buffer,
      )
    } else {
      // Innermost list: dispatch, if matching alt, compile + push.
      let splitName = ctx.fresh()
      forBodyRef.buffer->Array.push(
        JsBuild.const(
          splitName,
          JsBuild.call(discriminator, [forceOf(JsBuild.id(vElemName))]),
        ),
      )
      let altBodyRef = mkBody(Some(forBodyRef))
      let vAltValName = ctx.fresh()
      altBodyRef.buffer->Array.push(
        JsBuild.const(
          vAltValName,
          lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")),
        ),
      )
      let collected = []
      collectBranchesByAlt(
        Expr.NodeFlow(branchNode),
        branch.value,
        caseSplitOpen.id,
        alt,
        collected,
      )
      collected->Array.forEach((bn: Expr.expr) =>
        recordMemo(ctx, bn.id, Some(altBodyRef), vAltValName)
      )
      let valueName = compileValueRef(ctx, branch.value, Some(altBodyRef))
      altBodyRef.buffer->Array.push(
        JsBuild.exprStmt(
          JsBuild.call(
            JsBuild.member(JsBuild.id(outName), "push"),
            [forceOf(JsBuild.id(valueName))],
          ),
        ),
      )
      forBodyRef.buffer->Array.push(
        JsBuild.if_(
          JsBuild.eq(
            JsBuild.member(JsBuild.id(splitName), "tag"),
            JsBuild.str(alt),
          ),
          altBodyRef.buffer,
        ),
      )
    }
    parentBuf->Array.push(
      JsBuild.forOf(iterName, iterInputJs, forBodyRef.buffer),
    )
  }
  buildLevel(0, currentBody, forceOf(JsBuild.id(inputName)), thunkBody)
  thunkBody->Array.push(JsBuild.ret(JsBuild.id(outName)))

  let name = ctx.fresh()
  bufferOf(ctx, currentBody)->Array.push(
    JsBuild.const(name, lazyOf(thunkBody)),
  )
  recordMemo(ctx, closeId, currentBody, name)
  name
}

// --- Runtime helpers emitted at the top of every IIFE ---

let lazyRuntimeStmts: array<JsAst.stmt> = [
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
              JsBuild.assign(
                JsBuild.member(JsBuild.id("z"), "t"),
                JsBuild.null,
              ),
            ),
            JsBuild.exprStmt(
              JsBuild.assign(
                JsBuild.member(JsBuild.id("z"), "c"),
                JsBuild.bool_(true),
              ),
            ),
          ],
        ),
        JsBuild.ret(JsBuild.member(JsBuild.id("z"), "v")),
      ],
    ),
  ),
]

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
    fresh,
    memo: Map.make(),
  }
  let rootName = compileExpr(ctx, root, None)
  let body = Array.concat(lazyRuntimeStmts, ctx.outerStmts)
  (body, forceOf(JsBuild.id(rootName)))
}

let compileToIIFE = (e: Expr.expr): JsAst.expr => {
  let (stmts, value) = compileToBody(e)
  let body = [...stmts, JsBuild.ret(value)]
  JsBuild.call(JsBuild.arrow([], body), [])
}
