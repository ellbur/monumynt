// Pass 4 of the compile pipeline: the recursive, memoised, context-passing
// code generator (compile-strategy-design.md).
//
// STATUS: the machinery is real and running — pure let-floating placement,
// the (node, port, context) memo with prefix reuse, per-thunk context
// instantiation — with emitters for the value fragment (Lit, App) and iter
// collects (list/option chains with binary Join). The remaining emitters
// raise `Todo`, which Pipeline catches to fall back to the LegacyBridge:
// that is the migration harness. Implement one emitter, and the tests that
// need it silently switch from the bridge to this pass — with NextMain's
// differential check comparing both engines' eval results wherever the
// bridge can also compile. The legacy compiler (src/Compile.res) is the
// SPEC for every emitter here: mirror its emitted shapes (its function
// names are cited at each stub), let the differential harness prove
// agreement, then the shapes can diverge deliberately later.
//
// The architecture, pinned by the working machinery:
//
//   compileValue : (state, context, valueRef) -> {name, floated}
//
//   - PURE PLACEMENT. Nothing is pushed into a shared statement buffer.
//     Every compile returns the statements it wants emitted, each tagged
//     with the context it must live in (`placed`). Owners claim what is
//     addressed to them: a collect emitter buckets statements addressed to
//     its loop bodies into those bodies and floats the rest upward in its
//     own result; the top level (empty context) keeps everything that
//     reaches it. Loop-invariant hoisting is therefore not an analysis —
//     it is what floating does by default.
//   - CONTEXT is the ordered stack of flows open on the consumer chain,
//     with one twist over Context.res's structural paths: each segment is
//     tagged with the collect whose emitted thunk owns that body
//     (`thunkOf`). Two sibling collects over one flow open structurally
//     identical contexts, but their thunks are separate JS scopes — the
//     tag is what keeps a binding emitted in one thunk from being
//     memo-reused in the other (the legacy compiler used bodyRef object
//     identity for this; tags are the pure spelling). Cross-thunk sharing
//     of per-iteration work is therefore still not preserved — the
//     documented cost of the eager model, unchanged.
//   - MEMO keys on (node id, port); each entry stores the instantiated
//     context the binding was placed in. Lookup reuses an entry whose
//     context is a PREFIX of the requesting one (the legacy isAncestor
//     scan, re-plumbed). Lits memoise at the empty context, so they are
//     shared by every consumer everywhere.
//   - REQUIRED CONTEXT is a pure check-and-tag: a node's structural
//     context (Context.valueContext — later handed down by Annotate) is
//     instantiated against the current chain context; a mismatch is an
//     ill-formed reference Check should have witnessed, so it asserts
//     (failwith) here. A node reached in two INCOMPARABLE contexts lifts
//     to a product context as a point-indexed table — that arrives with
//     the Cross emitter and must stay unreachable until the checker
//     admits products.
//   - DISPATCH is by node kind today, with `state.ann` (Annotate's facts)
//     threaded to every emitter. As annotations grow richer — species,
//     strictness, consumer sets, stream/async cells — dispatch and shape
//     choices move onto them without restructuring this pass.
//   - STATE is a mutable map scoped to one codegen invocation behind a
//     pure interface (compile-strategy-design.md allows exactly this):
//     codegen is a function of (annotations, program) — same input, same
//     output — and nothing outside one call observes the mutation.
//
// Error discipline: `Todo` = an emitter that is not written yet (Pipeline
// falls back to the bridge). `failwith` = a compiler bug or an ill-formed
// program that pass 1 should have witnessed — never user-facing.

open Program

exception Todo(string)

// --- Context: instantiated paths ------------------------------------------

// One open flow on the consumer chain, tagged with the collect node whose
// emitted thunk owns the corresponding JS scope.
type seg = {flow: flowRef, thunkOf: int}

type ctxPath = array<seg>

let segKey = (s: seg): string =>
  Context.flowKey(s.flow) ++ "@" ++ Int.toString(s.thunkOf)

let ctxPathKey = (ctx: ctxPath): string => ctx->Array.map(segKey)->Array.join(">")

let isCtxPrefix = (shorter: ctxPath, longer: ctxPath): bool =>
  Array.length(shorter) <= Array.length(longer) &&
  shorter->Array.everyWithIndex((s, i) =>
    switch longer[i] {
    | Some(t) => segKey(s) === segKey(t)
    | None => false
    }
  )

let flowsKey = (flows: array<flowRef>): string =>
  flows->Array.map(Context.flowKey)->Array.join(">")

// Instantiate a structural context (a Context.res path) against the current
// chain context: the prefix of `ctx` carrying the same flows, in the same
// order. This is the "deepest prefix covering the flow-variable set" rule;
// a mismatch means the reference is ill-formed (or a product case arrived
// early) and pass 1 should have witnessed it.
let instantiate = (~what: string, structural: array<flowRef>, ctx: ctxPath): ctxPath => {
  let n = Array.length(structural)
  let matches =
    n <= Array.length(ctx) &&
    structural->Array.everyWithIndex((f, i) =>
      switch ctx[i] {
      | Some(s) => Context.flowKey(s.flow) === Context.flowKey(f)
      | None => false
      }
    )
  if !matches {
    failwith(
      "Codegen: " ++
      what ++
      " requires flow context " ++
      Context.contextToString(structural) ++
      " which is not a prefix of the current chain — an ill-formed reference " ++
      "(or early product) that Check should have witnessed",
    )
  }
  ctx->Array.slice(~start=0, ~end=n)
}

// --- Compile results and state --------------------------------------------

// A statement tagged with the context whose body it must be emitted into.
type placed = {at: ctxPath, stmt: JsAst.stmt}

// The result of compiling one value reference: the binding name to
// reference it by (always via __force__), plus the newly created statements
// not yet claimed by an owner. A memo hit returns empty `floated` — the
// first compile already routed the statements.
type compiled = {name: string, floated: array<placed>}

// --- Products (product-flows-design.md, the whole-table Cross emitter) -------
//
// A Cross constructs a product context — two sibling axes, order-free — that the
// linear ctxPath cannot hold. The eager compile target is the whole-table lazy
// (product-flows-design.md, "Compile"): one lazy builds the full n×m table in
// the Cross's stored orientation, computing each cell's value once, and every
// consuming collect chain indexes that shared table in its own order. This is
// the minimal shape: a binary Cross of two top-level list uncollects, consumed
// by a two-collect chain (both orders supported, sharing one table).

// One axis of a product: its flow key, the uncollect that opens it, and the
// list source feeding it.
type productAxis = {axisKey: string, uncollect: node, feed: valueRef, flow: flowRef}

// A product a Cross node constructs. `axes` is the stored orientation
// (outer-first), read off the Cross's (left, right) operands.
type product = {crossId: int, axes: array<productAxis>}

// A supported product axis: a single top-level list uncollect flow.
let productAxisOf = (f: flowRef): option<productAxis> =>
  switch f {
  | FlowPort(n, "flow") =>
    switch n.kind {
    | Uncollect({flowKind: List, input, nesting: None}) =>
      Some({axisKey: Context.flowKey(f), uncollect: n, feed: input, flow: f})
    | _ => None
    }
  | _ => None
  }

// The product a Cross node constructs, when both operands are supported axes.
let productOf = (n: node): option<product> =>
  switch n.kind {
  | Cross({left, right}) =>
    switch (productAxisOf(left), productAxisOf(right)) {
    | (Some(la), Some(ra)) => Some({crossId: n.id, axes: [la, ra]})
    | _ => None
    }
  | _ => None
  }

type state = {
  fresh: unit => string,
  ann: Annotate.annotations,
  // (node id ++ ":" ++ port) -> emitted bindings, each with the context it
  // was placed in.
  memo: Map.t<string, array<(ctxPath, string)>>,
  // Every product the program's Cross nodes construct.
  products: array<product>,
  // A product-spanning node's shared table: its value memoKey -> table binding
  // name. Keyed separately from `memo` because a table is indexed (force(t)[i][j]),
  // not referenced as a scalar, and it is shared by every consumer chain.
  tableMemo: Map.t<string, string>,
}

let memoKey = (id: int, port: string): string => Int.toString(id) ++ ":" ++ port

let lookupMemo = (st: state, id: int, port: string, ctx: ctxPath): option<string> =>
  switch Map.get(st.memo, memoKey(id, port)) {
  | None => None
  | Some(entries) =>
    entries
    ->Array.find(((stored, _)) => isCtxPrefix(stored, ctx))
    ->Option.map(((_, name)) => name)
  }

let recordMemo = (st: state, id: int, port: string, ctx: ctxPath, name: string): unit => {
  let key = memoKey(id, port)
  let entries = switch Map.get(st.memo, key) {
  | Some(a) => a
  | None => {
      let a: array<(ctxPath, string)> = []
      Map.set(st.memo, key, a)
      a
    }
  }
  Array.push(entries, (ctx, name))
}

// --- Flow spines -----------------------------------------------------------

// The ordered list of layers a collect iterates, outermost first, read off
// its flow operand by flattening the Join tree (Join{outer, inner} = the
// outer layers then the inner ones — the join law). An `AltLevel` is a
// case-alt operand: not a loop but a discriminator dispatch + tag test
// (the filter shape when it is the innermost level of an iter collect).

type level =
  | IterLevel({uncollect: node, isList: bool})
  | AltLevel({split: node, alt: string})
  // A partial collect's merged flow: a k-arm dispatch over the covered alts of
  // one split, each arm carrying its own branch value, feeding the shared
  // merged-value port. Not a loop — an option-kind, non-exhaustive dispatch.
  | PartialLevel({collect: node, split: node, branches: array<collectBranch>})

let rec spine = (f: flowRef): array<level> =>
  switch f {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: List}) => [IterLevel({uncollect: n, isList: true})]
    | Uncollect({flowKind: Option}) => [IterLevel({uncollect: n, isList: false})]
    | Uncollect({flowKind: Case(_)}) => [AltLevel({split: n, alt: port})]
    | Collect({branches}) =>
      // A partial collect's merged flow, consumed downstream (as a join's inner
      // operand for a filter, or terminated alone for an option). It
      // contributes one dispatch level over its underlying split's covered
      // alts; any enclosing loops come from wherever it is nested (a Join, or
      // nothing at the top level) — exactly as a single alt flow does.
      switch classifyCollect(branches) {
      | CasePartial(_) =>
        switch branches->Array.getUnsafe(0) {
        | {flow: FlowPort(split, _)} => [PartialLevel({collect: n, split, branches})]
        }
      | _ =>
        failwith("Codegen.spine: a Collect with no flow port reached as a flow — Check's port-exists rule should have witnessed this")
      }
    | Join({outer, inner}) => Array.concat(spine(outer), spine(inner))
    | Commute(_) =>
      throw(Todo("commute in a collect chain — the swapped-orientation walk (lazy-stream-commute-design.md)"))
    | Cross(_) =>
      throw(Todo("cross in a collect chain — the point-indexed table (product-flows-design.md)"))
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) =>
      failwith("Codegen.spine: node kind has no flow ports — Check's port-exists rule should have witnessed this")
    }
  }

// Per-level assembly plan for an iter collect (see emitIterCollect).
type levelPlan = {
  uncollect: node,
  isList: bool,
  bodyCtx: ctxPath,
  feedName: string, // binding whose forced value is the collection / option
  iterVar: string, // list: the for-of variable; option: the tested const
  elemName: string, // the __lazyDone__ element binding, memoised at bodyCtx
}

// Per-alt assembly plan for a case collect (see emitCaseCollect).
type altPlan = {
  altName: string,
  altCtx: ctxPath, // exterior ++ [this alt's flow tagged with the collect]
  payloadName: string, // the __lazyDone__(split.value) binding, memoised at altCtx
  valueName: string, // the compiled branch value, forced into `out`
}

// A C-style `for (let i = 0; i < arr.length; i++) { body }` over an already-
// forced array binding — the index-based loop the table build and its consumers
// use (a product axis is traversed by index so two orders share one table).
let cForArr = (iv: string, arrName: string, body: array<JsAst.stmt>): JsAst.stmt =>
  JsAst.SFor({
    init: Some(JsAst.FIVar({kind: Let, decls: [{name: iv, init: Some(JsBuild.int_(0))}]})),
    test: Some(JsBuild.lt(JsBuild.id(iv), JsBuild.member(JsBuild.id(arrName), "length"))),
    update: Some(JsAst.EUpdate({op: PostInc, operand: JsBuild.id(iv)})),
    body: JsAst.SBlock(body),
  })

// A recognized product-consumer chain: two nested collects over the two axes of
// one product, terminating in a value that spans exactly that product.
type productMatch = {
  product: product,
  outerAxis: productAxis, // the outer collect's axis
  innerAxis: productAxis, // the inner collect's axis
  sVal: valueRef, // the product-spanning value both collects carry through
}

// Does this collect head a product-consumer chain the whole-table emitter
// handles? It must be `collect(fOuter, collect(fInner, s))` where fOuter and
// fInner are the two axes of one constructed product and s varies over exactly
// that product (both axes). Returns None for every other shape — including
// ordinary linear collects, whose value never spans a sibling axis.
let matchProductChain = (st: state, cn: node): option<productMatch> =>
  switch cn.kind {
  | Collect({branches: [{flow: fOuter, value: ValuePort(innerNode, "value")}]}) =>
    switch innerNode.kind {
    | Collect({branches: [{flow: fInner, value: sVal}]}) =>
      let ko = Context.flowKey(fOuter)
      let ki = Context.flowKey(fInner)
      if ko === ki {
        None
      } else {
        st.products
        ->Array.find(p => {
          let keys = p.axes->Array.map(a => a.axisKey)
          keys->Array.includes(ko) && keys->Array.includes(ki)
        })
        ->Option.flatMap(p => {
          // s must vary over exactly the product's two axes.
          let need = p.axes->Array.map(a => a.axisKey)
          let sAxes = Annotate.valueAxes(sVal)
          let spans =
            need->Array.every(k => sAxes->Array.includes(k)) &&
              sAxes->Array.every(k => need->Array.includes(k))
          let axisFor = k => p.axes->Array.find(a => a.axisKey === k)
          switch (spans, axisFor(ko), axisFor(ki)) {
          | (true, Some(outerAxis), Some(innerAxis)) =>
            Some({product: p, outerAxis, innerAxis, sVal})
          | _ => None
          }
        })
      }
    | _ => None
    }
  | _ => None
  }

// --- The compile ------------------------------------------------------------

let rec compileValue = (st: state, ctx: ctxPath, r: valueRef): compiled =>
  switch r {
  | ValuePort(n, port) =>
    switch lookupMemo(st, n.id, port, ctx) {
    | Some(name) => {name, floated: []}
    | None =>
      switch n.kind {
      | Lit(js) => emitLit(st, n, js)
      | App({fn, args}) => emitApp(st, ctx, n, fn, args)
      | Collect({branches}) =>
        switch matchProductChain(st, n) {
        | Some(m) => emitProductChain(st, ctx, n, m)
        | None => emitCollect(st, ctx, n, branches)
        }
      | Uncollect(_) =>
        // Flow-borne ports (the per-iteration element / per-alt payload)
        // exist only as pre-memoised bindings inside a consuming collect's
        // thunk. A memo miss here = referenced outside its flow.
        failwith(
          "Codegen: flow-borne port \"" ++
          port ++
          "\" of node " ++
          Int.toString(n.id) ++
          " reached outside its flow — Check's flow-borne rule should have witnessed this",
        )
      | DelayWrite({read, step}) => emitRegister(st, ctx, n, read, step)
      | DelayRead(_) =>
        // The register's per-iteration `prev` port. The write half's emitter
        // (emitRegister) pre-memoises it into the driving loop body before
        // compiling the step, so a memo miss here means `prev` was read from
        // outside that loop — a foreign consumer of the register (e.g. a
        // sibling collect over the same flow), which is deferred (the driving
        // collect would have to share the register's loop skeleton; ARCHITECTURE
        // worklist item 6, general case).
        failwith(
          "Codegen: register `prev` port of node " ++
          Int.toString(n.id) ++
          " reached outside its driving loop — Check's flow-borne rule should have witnessed this",
        )
      | Join(_) | Commute(_) | Cross(_) =>
        failwith("Codegen: flow-only node reached as a value — Check's port-exists rule should have witnessed this")
      }
    }
  }

and emitLit = (st: state, n: node, js: JsAst.expr): compiled => {
  // Pure constant: placed at the empty context, shared everywhere.
  let name = st.fresh()
  recordMemo(st, n.id, "value", [], name)
  {name, floated: [{at: [], stmt: JsBuild.const(name, Runtime.lazyDoneOf(js))}]}
}

and emitApp = (st: state, ctx: ctxPath, n: node, fn: valueRef, args: array<valueRef>): compiled => {
  // fn is a wire like any argument (functions are values); the emitted
  // call forces it. This is the one deliberate divergence from the legacy
  // shape (which embedded the fn expression) — it is what lets an App
  // apply a computed function, which the bridge cannot express.
  let fnC = compileValue(st, ctx, fn)
  let argCs = args->Array.map(a => compileValue(st, ctx, a))
  // A product-context value (its args live on incomparable sibling axes) has no
  // linear structural context — Context.valueContext raises. Its home is the
  // current chain, which the product emitter has already made the product
  // context: place the App at the innermost point. (Check admitted the combine
  // via a Cross, so an Incomparable here is a legitimate product, not a bug.)
  let required = switch Context.valueContext(ValuePort(n, "value")) {
  | structural =>
    instantiate(~what="App node " ++ Int.toString(n.id), structural, ctx)
  | exception Context.Incomparable(_) => ctx
  }
  let name = st.fresh()
  let callJs = JsBuild.call(
    Runtime.forceOf(JsBuild.id(fnC.name)),
    argCs->Array.map(c => Runtime.forceOf(JsBuild.id(c.name))),
  )
  recordMemo(st, n.id, "value", required, name)
  let own = {at: required, stmt: JsBuild.const(name, Runtime.lazyOfExpr(callJs))}
  {
    name,
    floated: Array.concat(
      Array.concat(fnC.floated, argCs->Array.map(c => c.floated)->Array.flat),
      [own],
    ),
  }
}

and emitCollect = (st: state, ctx: ctxPath, cn: node, branches: array<collectBranch>): compiled =>
  switch classifyCollect(branches) {
  | IterCollect => {
      let branch = branches->Array.getUnsafe(0)
      let levels = spine(branch.flow)
      let hasPartial = levels->Array.some(l =>
        switch l {
        | PartialLevel(_) => true
        | AltLevel(_) | IterLevel(_) => false
        }
      )
      let hasAlt = levels->Array.some(l =>
        switch l {
        | AltLevel(_) => true
        | PartialLevel(_) | IterLevel(_) => false
        }
      )
      if hasPartial {
        emitPartialCollect(st, ctx, cn, branch, levels)
      } else if hasAlt {
        emitFilterCollect(st, ctx, cn, branch, levels)
      } else {
        emitIterCollect(st, ctx, cn, branch, levels)
      }
    }
  | CaseFull => emitCaseCollect(st, ctx, cn, branches)
  | CasePartial(_) =>
    // A partial collect's value output is the MERGED value — flow-borne on its
    // own merged flow, pre-memoised inside the terminating dispatch's arms
    // (emitPartialCollect). Reaching it here as a plain value means it was
    // consumed outside its flow — Check's flow-borne rule should have witnessed
    // it. (The merged flow itself is handled by `spine`, not here.)
    failwith(
      "Codegen: partial collect node " ++
      Int.toString(cn.id) ++
      "'s merged value reached outside its flow — Check's flow-borne rule should have witnessed this",
    )
  | Malformed(msg) =>
    failwith("Codegen: malformed collect: " ++ msg ++ " — Check's coverage rule should have witnessed this")
  }

// One self-contained thunk per collect (multi-close independence): nested
// for-of / if-defined levels, the any-list rule deciding accumulator form.
// The value subtree compiles under the innermost pushed context; statements
// addressed to a level's body are bucketed into it, everything shallower
// floats out of the thunk (loop-invariant work lands outside — memoised at
// its own required context, so sibling consumers reuse it).
and emitIterCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branch: collectBranch,
  levels: array<level>,
): compiled => {
  let exterior = instantiate(
    ~what="Collect node " ++ Int.toString(cn.id),
    Context.flowContext(branch.flow),
    ctx,
  )

  // Walk the levels outermost-in: compile each level's feed in the context
  // built so far, then open the level's body context (tagged with this
  // collect) and pre-memoise its element binding there.
  let floatedAcc: array<placed> = []
  let plans: array<levelPlan> = []
  let parentCtx = ref(exterior)
  levels->Array.forEach(l =>
    switch l {
    | AltLevel(_) | PartialLevel(_) =>
      failwith("Codegen.emitIterCollect: dispatch level — routed to the filter/partial emitter upstream")
    | IterLevel({uncollect, isList}) => {
        let input = switch uncollect.kind {
        | Uncollect({input}) => input
        | _ => failwith("Codegen.emitIterCollect: IterLevel is not an Uncollect")
        }
        let own = FlowPort(uncollect, "flow")
        // Adjacency: each level must open exactly where the chain so far
        // ends (Check's join-adjacency rule; assert per check-and-tag).
        let parentFlows = parentCtx.contents->Array.map(s => s.flow)
        if flowsKey(Context.flowContext(own)) !== flowsKey(parentFlows) {
          failwith(
            "Codegen: level " ++
            Int.toString(uncollect.id) ++
            " is not nesting-adjacent to the chain — Check's join-adjacency rule should have witnessed this",
          )
        }
        let feedC = compileValue(st, parentCtx.contents, input)
        feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let bodyCtx = Array.concat(parentCtx.contents, [{flow: own, thunkOf: cn.id}])
        let iterVar = st.fresh()
        let elemName = st.fresh()
        recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
        Array.push(plans, {uncollect, isList, bodyCtx, feedName: feedC.name, iterVar, elemName})
        parentCtx := bodyCtx
      }
    }
  )

  let valueC = compileValue(st, parentCtx.contents, branch.value)
  valueC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  // Partition: statements addressed to one of this collect's level bodies
  // are claimed into that body (in compile order — dependencies precede
  // consumers); everything at the exterior or shallower floats onward.
  let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
  plans->Array.forEach(p => Map.set(buckets, ctxPathKey(p.bodyCtx), []))
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    switch Map.get(buckets, ctxPathKey(pl.at)) {
    | Some(b) => Array.push(b, pl.stmt)
    | None =>
      if isCtxPrefix(pl.at, exterior) {
        Array.push(escaped, pl)
      } else {
        failwith("Codegen: a statement floated to a context unrelated to the collect being assembled — placement bug")
      }
    }
  )

  // Assemble innermost-out. Any list in the chain -> list output (push per
  // chain-firing); all options -> `let out;` set iff every level fires.
  let anyList = plans->Array.some(p => p.isList)
  let outName = st.fresh()
  let innerPayload = if anyList {
    JsBuild.exprStmt(
      JsBuild.call(
        JsBuild.member(JsBuild.id(outName), "push"),
        [Runtime.forceOf(JsBuild.id(valueC.name))],
      ),
    )
  } else {
    JsBuild.exprStmt(
      JsBuild.assign(JsBuild.id(outName), Runtime.forceOf(JsBuild.id(valueC.name))),
    )
  }
  let nested = ref([innerPayload])
  for i in Array.length(plans) - 1 downto 0 {
    let p = plans->Array.getUnsafe(i)
    let bucket = Map.get(buckets, ctxPathKey(p.bodyCtx))->Option.getOr([])
    let body = Array.concat(
      [JsBuild.const(p.elemName, Runtime.lazyDoneOf(JsBuild.id(p.iterVar)))],
      Array.concat(bucket, nested.contents),
    )
    nested :=
      if p.isList {
        [JsBuild.forOf(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName)), body)]
      } else {
        [
          JsBuild.const(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName))),
          JsBuild.if_(JsBuild.neq(JsBuild.id(p.iterVar), JsBuild.undefined), body),
        ]
      }
  }
  let accDecl = if anyList {
    JsBuild.const(outName, JsBuild.array_([]))
  } else {
    JsBuild.letDecl(outName)
  }
  let thunkBody = Array.concat([accDecl], Array.concat(nested.contents, [JsBuild.ret(JsBuild.id(outName))]))

  let name = st.fresh()
  recordMemo(st, cn.id, "value", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// One self-contained thunk per case collect (multi-close independence):
// `const s = force(disc)(force(input)); let out;` then an exhaustive if-chain
// on `s.tag`, one arm per alt, ending in else-throw. Each arm pre-memoises the
// alt's payload port (split.id, alt) to a shared `const v = __lazyDone__(s.value)`
// binding at the alt's context, compiles the branch value there, and assigns
// `out`. Statements addressed to an alt body are bucketed into it; loop-
// invariant work (the discriminator extern, exterior-context bindings) floats
// out of the thunk. Mirrors Compile.emitCaseClose — with the discriminator a
// wire that is forced at the call, like emitApp forces fn.
and emitCaseCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branches: array<collectBranch>,
): compiled => {
  let branch0 = branches->Array.getUnsafe(0)
  let split = switch branch0.flow {
  | FlowPort(s, _) => s
  }
  let (alts, discriminator, csInput) = switch split.kind {
  | Uncollect({flowKind: Case({alts, discriminator}), input}) => (alts, discriminator, input)
  | _ =>
    failwith(
      "Codegen.emitCaseCollect: branch flow does not target a case split — " ++
      "Check's coverage rule should have witnessed this",
    )
  }
  let exterior = instantiate(
    ~what="Case collect node " ++ Int.toString(cn.id),
    Context.flowContext(branch0.flow),
    ctx,
  )

  let floatedAcc: array<placed> = []
  // The discriminator (a wire, usually to a Lit extern) and the split input,
  // both compiled at the exterior — recomputed into `s` once per thunk firing.
  let discC = compileValue(st, exterior, discriminator)
  discC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
  let inputC = compileValue(st, exterior, csInput)
  inputC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let splitName = st.fresh()
  let outName = st.fresh()

  // Per alt, in the split's declared order (so dispatch is exhaustive): open
  // the alt body context, pre-memoise the payload port there, compile the
  // branch value under it.
  let plans = alts->Array.map(altName => {
    let branch = switch branches->Array.find(b =>
      switch b.flow {
      | FlowPort(t, p) => t.id === split.id && p === altName
      }
    ) {
    | Some(b) => b
    | None =>
      failwith(
        "Codegen.emitCaseCollect: CaseFull is missing a branch for alt \"" ++
        altName ++
        "\" — Check's coverage rule should have witnessed this",
      )
    }
    let altFlow = FlowPort(split, altName)
    let altCtx = Array.concat(exterior, [{flow: altFlow, thunkOf: cn.id}])
    let payloadName = st.fresh()
    recordMemo(st, split.id, altName, altCtx, payloadName)
    let valueC = compileValue(st, altCtx, branch.value)
    valueC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    {altName, altCtx, payloadName, valueName: valueC.name}
  })

  // Partition: statements addressed to one alt body bucket into it (in compile
  // order — dependencies precede consumers); everything at the exterior or
  // shallower floats out of the thunk.
  let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
  plans->Array.forEach(ap => Map.set(buckets, ctxPathKey(ap.altCtx), []))
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    switch Map.get(buckets, ctxPathKey(pl.at)) {
    | Some(bk) => Array.push(bk, pl.stmt)
    | None =>
      if isCtxPrefix(pl.at, exterior) {
        Array.push(escaped, pl)
      } else {
        failwith(
          "Codegen: a statement floated to a context unrelated to the case " ++
          "collect being assembled — placement bug",
        )
      }
    }
  )

  // Build the if-chain in reverse, ending in the exhaustive else-throw.
  let elseThrow = JsBuild.throw_(
    JsBuild.new_(
      JsBuild.id("Error"),
      [
        JsBuild.add(
          JsBuild.str("Unmatched case: "),
          JsBuild.member(JsBuild.id(splitName), "tag"),
        ),
      ],
    ),
  )
  let chain = ref(Some(elseThrow))
  for i in Array.length(plans) - 1 downto 0 {
    let ap = plans->Array.getUnsafe(i)
    let bucket = Map.get(buckets, ctxPathKey(ap.altCtx))->Option.getOr([])
    let body = Array.concat(
      Array.concat(
        [JsBuild.const(ap.payloadName, Runtime.lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")))],
        bucket,
      ),
      [JsBuild.exprStmt(JsBuild.assign(JsBuild.id(outName), Runtime.forceOf(JsBuild.id(ap.valueName))))],
    )
    chain := Some(JsAst.SIf({
      test: JsBuild.eq(JsBuild.member(JsBuild.id(splitName), "tag"), JsBuild.str(ap.altName)),
      cons: JsAst.SBlock(body),
      alt: chain.contents,
    }))
  }

  let thunkBody = Array.concat(
    [
      JsBuild.const(
        splitName,
        JsBuild.call(Runtime.forceOf(JsBuild.id(discC.name)), [Runtime.forceOf(JsBuild.id(inputC.name))]),
      ),
      JsBuild.letDecl(outName),
    ],
    Array.concat(
      switch chain.contents {
      | Some(s) => [s]
      | None => []
      },
      [JsBuild.ret(JsBuild.id(outName))],
    ),
  )

  let name = st.fresh()
  recordMemo(st, cn.id, "value", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// The filter shape: an iter chain (`join`ed lists/options) whose innermost
// operand is a case-alt flow — `join(list, case-alt)`. One thunk = a list
// accumulator, the leading Iter levels' for-of / if-defined loops (option
// levels skip when absent, contributing nothing to the list), and at the
// innermost body a discriminator dispatch that pushes only in the matching alt:
//
//   const s = force(disc)(force(elem));
//   if (s.tag === alt) { const payload = __lazyDone__(s.value); …value…;
//                        out.push(force(value)) }
//
// The alt payload port is pre-memoised at the alt's context so the value
// subtree resolves it; loop-invariant work floats out of the thunk. Mirrors
// Compile.emitFilterClose (output is always a list — push, not assign).
and emitFilterCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branch: collectBranch,
  levels: array<level>,
): compiled => {
  let n = Array.length(levels)
  let (split, alt) = switch levels->Array.getUnsafe(n - 1) {
  | AltLevel({split, alt}) => (split, alt)
  | IterLevel(_) | PartialLevel(_) =>
    throw(
      Todo(
        "filter chain whose innermost level is not a single case-alt operand — " ++
        "a shape Compile.emitFilterClose does not cover",
      ),
    )
  }
  let iterLevels = levels->Array.slice(~start=0, ~end=n - 1)
  iterLevels->Array.forEach(l =>
    switch l {
    | IterLevel(_) => () // list or option leading level — both are looped below
    | AltLevel(_) | PartialLevel(_) =>
      throw(Todo("filter chain with a non-trailing dispatch level — mirror Compile.emitFilterClose"))
    }
  )
  if Array.length(iterLevels) === 0 {
    failwith("Codegen.emitFilterCollect: a filter needs a list to iterate — Check should have witnessed")
  }
  // The output is a list (push per kept firing), so at least one list level must
  // drive it. An all-option filter's accumulator shape (a list-of-0-or-1 vs an
  // option) is the any-list-rule question in a different guise — a separate round.
  let anyList = iterLevels->Array.some(l =>
    switch l {
    | IterLevel({isList}) => isList
    | AltLevel(_) | PartialLevel(_) => false
    }
  )
  if !anyList {
    throw(Todo("filter over only option levels — the accumulator-shape (list vs option) question, a separate round"))
  }
  let (discriminator, csInput) = switch split.kind {
  | Uncollect({flowKind: Case({discriminator}), input}) => (discriminator, input)
  | _ => failwith("Codegen.emitFilterCollect: alt level's node is not a case split — placement bug")
  }

  let exterior = instantiate(
    ~what="Filter collect node " ++ Int.toString(cn.id),
    Context.flowContext(branch.flow),
    ctx,
  )

  // Walk the Iter levels outermost-in, exactly as emitIterCollect does.
  let floatedAcc: array<placed> = []
  let plans: array<levelPlan> = []
  let parentCtx = ref(exterior)
  iterLevels->Array.forEach(l =>
    switch l {
    | AltLevel(_) | PartialLevel(_) =>
      failwith("Codegen.emitFilterCollect: dispatch level in the iter prefix — sliced off above")
    | IterLevel({uncollect, isList}) => {
        let input = switch uncollect.kind {
        | Uncollect({input}) => input
        | _ => failwith("Codegen.emitFilterCollect: IterLevel is not an Uncollect")
        }
        let own = FlowPort(uncollect, "flow")
        let parentFlows = parentCtx.contents->Array.map(s => s.flow)
        if flowsKey(Context.flowContext(own)) !== flowsKey(parentFlows) {
          failwith(
            "Codegen: level " ++
            Int.toString(uncollect.id) ++
            " is not nesting-adjacent to the chain — Check's join-adjacency rule should have witnessed this",
          )
        }
        let feedC = compileValue(st, parentCtx.contents, input)
        feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let bodyCtx = Array.concat(parentCtx.contents, [{flow: own, thunkOf: cn.id}])
        let iterVar = st.fresh()
        let elemName = st.fresh()
        recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
        Array.push(plans, {uncollect, isList, bodyCtx, feedName: feedC.name, iterVar, elemName})
        parentCtx := bodyCtx
      }
    }
  )

  // At the innermost list body: the case-split input feeds the dispatch, the
  // discriminator is loop-invariant (compiled at the exterior), and the alt
  // payload is pre-memoised at the alt's context so the branch value resolves.
  let innerCtx = parentCtx.contents
  let inputC = compileValue(st, innerCtx, csInput)
  inputC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
  let discC = compileValue(st, exterior, discriminator)
  discC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let altFlow = FlowPort(split, alt)
  let altCtx = Array.concat(innerCtx, [{flow: altFlow, thunkOf: cn.id}])
  let payloadName = st.fresh()
  recordMemo(st, split.id, alt, altCtx, payloadName)
  let valueC = compileValue(st, altCtx, branch.value)
  valueC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  // Partition: each iter body and the alt body claim what is addressed to them;
  // everything at the exterior or shallower floats out of the thunk.
  let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
  plans->Array.forEach(p => Map.set(buckets, ctxPathKey(p.bodyCtx), []))
  Map.set(buckets, ctxPathKey(altCtx), [])
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    switch Map.get(buckets, ctxPathKey(pl.at)) {
    | Some(bk) => Array.push(bk, pl.stmt)
    | None =>
      if isCtxPrefix(pl.at, exterior) {
        Array.push(escaped, pl)
      } else {
        failwith("Codegen: a statement floated to a context unrelated to the filter collect being assembled — placement bug")
      }
    }
  )

  let outName = st.fresh()
  let splitName = st.fresh()
  let altBucket = Map.get(buckets, ctxPathKey(altCtx))->Option.getOr([])
  let altBody = Array.concat(
    Array.concat(
      [JsBuild.const(payloadName, Runtime.lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")))],
      altBucket,
    ),
    [
      JsBuild.exprStmt(
        JsBuild.call(
          JsBuild.member(JsBuild.id(outName), "push"),
          [Runtime.forceOf(JsBuild.id(valueC.name))],
        ),
      ),
    ],
  )
  let dispatch = [
    JsBuild.const(
      splitName,
      JsBuild.call(Runtime.forceOf(JsBuild.id(discC.name)), [Runtime.forceOf(JsBuild.id(inputC.name))]),
    ),
    JsBuild.if_(
      JsBuild.eq(JsBuild.member(JsBuild.id(splitName), "tag"), JsBuild.str(alt)),
      altBody,
    ),
  ]

  // Assemble the loops innermost-out; the dispatch is the innermost payload.
  // A list level loops (for-of); an option level is a single defined-check —
  // an absent option skips its body, so that firing pushes nothing.
  let nested = ref(dispatch)
  for i in Array.length(plans) - 1 downto 0 {
    let p = plans->Array.getUnsafe(i)
    let bucket = Map.get(buckets, ctxPathKey(p.bodyCtx))->Option.getOr([])
    let body = Array.concat(
      [JsBuild.const(p.elemName, Runtime.lazyDoneOf(JsBuild.id(p.iterVar)))],
      Array.concat(bucket, nested.contents),
    )
    nested :=
      if p.isList {
        [JsBuild.forOf(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName)), body)]
      } else {
        [
          JsBuild.const(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName))),
          JsBuild.if_(JsBuild.neq(JsBuild.id(p.iterVar), JsBuild.undefined), body),
        ]
      }
  }
  let thunkBody = Array.concat(
    [JsBuild.const(outName, JsBuild.array_([]))],
    Array.concat(nested.contents, [JsBuild.ret(JsBuild.id(outName))]),
  )

  let name = st.fresh()
  recordMemo(st, cn.id, "value", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// A partial collect's merged flow, terminated downstream (partial-collect-design.md,
// the "direct" slice — worklist item 9). The merged flow is a k-arm dispatch
// over the covered alts of one split, each arm carrying its own branch value
// into the shared merged-value port, then the terminating collect's payload
// action. NON-exhaustive: an uncovered alt makes the merged flow not fire —
// dropped for a list, left unset for an option (the any-list rule again).
//
//   for (const x of feed) {                  // leading levels (from a Join):
//     const elem = __lazyDone__(x);           // list ⇒ for-of, option ⇒ if-defined
//     const s = force(disc)(force(input));
//     if (s.tag === alt1) { const p1 = __lazyDone__(s.value); …v1…; out.push(force(v1)) }
//     else if (s.tag === alt2) { … }         // no else — uncovered alts drop
//   }
//
// Leading levels may be list or option (an absent option skips its firing,
// contributing nothing — mirrors emitFilterCollect); the any-list rule decides
// the accumulator (any list ⇒ push, else the option `let out;` and the arms
// assign, which is also the no-leading-level collected-alone reading). Mirrors
// emitFilterCollect for the leading levels and emitCaseCollect for the per-arm
// payload, minus exhaustiveness. DEFERRED to the poset round: computation AT the merged
// context (the doc's logAndFallback step) lives at a cell-set context the
// linear model cannot represent, so the terminating value must reference the
// merged value directly (its structural context is the merged flow, which does
// not match an alt arm's — a merged-context App would trip `instantiate`).
and emitPartialCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branch: collectBranch,
  levels: array<level>,
): compiled => {
  let n = Array.length(levels)
  let (partialCollect, split, pbranches) = switch levels->Array.getUnsafe(n - 1) {
  | PartialLevel({collect, split, branches}) => (collect, split, branches)
  | IterLevel(_) | AltLevel(_) =>
    failwith("Codegen.emitPartialCollect: innermost level is not a PartialLevel")
  }
  let iterLevels = levels->Array.slice(~start=0, ~end=n - 1)
  iterLevels->Array.forEach(l =>
    switch l {
    | IterLevel(_) => () // list or option leading level — both are looped below
    | AltLevel(_) | PartialLevel(_) =>
      throw(Todo("partial collect with a dispatch leading level — mirror emitFilterCollect's shape"))
    }
  )
  let (discriminator, csInput) = switch split.kind {
  | Uncollect({flowKind: Case({discriminator}), input}) => (discriminator, input)
  | _ => failwith("Codegen.emitPartialCollect: PartialLevel's split is not a case split")
  }

  let exterior = instantiate(
    ~what="Partial collect node " ++ Int.toString(cn.id),
    Context.flowContext(branch.flow),
    ctx,
  )

  // Walk the leading list levels (from a Join), exactly as emitFilterCollect.
  let floatedAcc: array<placed> = []
  let plans: array<levelPlan> = []
  let parentCtx = ref(exterior)
  iterLevels->Array.forEach(l =>
    switch l {
    | IterLevel({uncollect, isList}) => {
        let input = switch uncollect.kind {
        | Uncollect({input}) => input
        | _ => failwith("Codegen.emitPartialCollect: IterLevel is not an Uncollect")
        }
        let own = FlowPort(uncollect, "flow")
        let parentFlows = parentCtx.contents->Array.map(s => s.flow)
        if flowsKey(Context.flowContext(own)) !== flowsKey(parentFlows) {
          failwith(
            "Codegen: level " ++
            Int.toString(uncollect.id) ++
            " is not nesting-adjacent to the chain — Check's join-adjacency rule should have witnessed this",
          )
        }
        let feedC = compileValue(st, parentCtx.contents, input)
        feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let bodyCtx = Array.concat(parentCtx.contents, [{flow: own, thunkOf: cn.id}])
        let iterVar = st.fresh()
        let elemName = st.fresh()
        recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
        Array.push(plans, {uncollect, isList, bodyCtx, feedName: feedC.name, iterVar, elemName})
        parentCtx := bodyCtx
      }
    | AltLevel(_) | PartialLevel(_) =>
      failwith("Codegen.emitPartialCollect: non-iter level in the leading prefix — guarded above")
    }
  )
  let innerCtx = parentCtx.contents

  // The split input feeds the dispatch (once per innermost firing); the
  // discriminator extern is loop-invariant.
  let inputC = compileValue(st, innerCtx, csInput)
  inputC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
  let discC = compileValue(st, exterior, discriminator)
  discC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let splitName = st.fresh()

  // Per covered arm: open the alt's context, pre-memoise the alt payload and the
  // (shared) merged-value port to this arm's branch value, then compile the
  // terminating collect's value (which references the merged value directly).
  let arms = pbranches->Array.map(pb => {
    let alt = switch pb.flow {
    | FlowPort(_, port) => port
    }
    let armCtx = Array.concat(innerCtx, [{flow: FlowPort(split, alt), thunkOf: cn.id}])
    let payloadName = st.fresh()
    recordMemo(st, split.id, alt, armCtx, payloadName)
    let branchValC = compileValue(st, armCtx, pb.value)
    branchValC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    recordMemo(st, partialCollect.id, "value", armCtx, branchValC.name)
    let termC = compileValue(st, armCtx, branch.value)
    termC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    (alt, armCtx, payloadName, termC.name)
  })

  // Partition: each leading level body and each arm claim what is addressed to
  // them; everything at the exterior or shallower floats out of the thunk.
  let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
  plans->Array.forEach(p => Map.set(buckets, ctxPathKey(p.bodyCtx), []))
  arms->Array.forEach(((_, armCtx, _, _)) => Map.set(buckets, ctxPathKey(armCtx), []))
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    switch Map.get(buckets, ctxPathKey(pl.at)) {
    | Some(bk) => Array.push(bk, pl.stmt)
    | None =>
      if isCtxPrefix(pl.at, exterior) {
        Array.push(escaped, pl)
      } else {
        failwith("Codegen: a statement floated to a context unrelated to the partial collect being assembled — placement bug")
      }
    }
  )

  let anyList = plans->Array.some(p => p.isList)
  let outName = st.fresh()
  let payloadAction = (termName: string): JsAst.stmt =>
    if anyList {
      JsBuild.exprStmt(
        JsBuild.call(JsBuild.member(JsBuild.id(outName), "push"), [Runtime.forceOf(JsBuild.id(termName))]),
      )
    } else {
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(outName), Runtime.forceOf(JsBuild.id(termName))))
    }

  // The k-arm if-chain, built in reverse — NON-exhaustive, no else.
  let chain = ref(None)
  for i in Array.length(arms) - 1 downto 0 {
    let (alt, armCtx, payloadName, termName) = arms->Array.getUnsafe(i)
    let bucket = Map.get(buckets, ctxPathKey(armCtx))->Option.getOr([])
    let body = Array.concat(
      Array.concat(
        [JsBuild.const(payloadName, Runtime.lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")))],
        bucket,
      ),
      [payloadAction(termName)],
    )
    chain := Some(JsAst.SIf({
      test: JsBuild.eq(JsBuild.member(JsBuild.id(splitName), "tag"), JsBuild.str(alt)),
      cons: JsAst.SBlock(body),
      alt: chain.contents,
    }))
  }
  let dispatch = Array.concat(
    [
      JsBuild.const(
        splitName,
        JsBuild.call(Runtime.forceOf(JsBuild.id(discC.name)), [Runtime.forceOf(JsBuild.id(inputC.name))]),
      ),
    ],
    switch chain.contents {
    | Some(s) => [s]
    | None => []
    },
  )

  // Wrap in the leading levels, innermost-out; the dispatch is the innermost
  // payload. A list level loops (for-of); an option level is a single
  // defined-check — an absent option skips its body, so that firing contributes
  // nothing (mirrors emitFilterCollect).
  let nested = ref(dispatch)
  for i in Array.length(plans) - 1 downto 0 {
    let p = plans->Array.getUnsafe(i)
    let bucket = Map.get(buckets, ctxPathKey(p.bodyCtx))->Option.getOr([])
    let body = Array.concat(
      [JsBuild.const(p.elemName, Runtime.lazyDoneOf(JsBuild.id(p.iterVar)))],
      Array.concat(bucket, nested.contents),
    )
    nested :=
      if p.isList {
        [JsBuild.forOf(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName)), body)]
      } else {
        [
          JsBuild.const(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName))),
          JsBuild.if_(JsBuild.neq(JsBuild.id(p.iterVar), JsBuild.undefined), body),
        ]
      }
  }
  let accDecl = if anyList {
    JsBuild.const(outName, JsBuild.array_([]))
  } else {
    JsBuild.letDecl(outName)
  }
  let thunkBody = Array.concat([accDecl], Array.concat(nested.contents, [JsBuild.ret(JsBuild.id(outName))]))

  let name = st.fresh()
  recordMemo(st, cn.id, "value", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// A register (Delay pair). The write half doubles as the feedback collect
// (iteration-with-state-design.md, "The write half is a node"): reaching the
// write's `final` port emits the driving loop with a mutable accumulator —
//
//   const vFinal = __lazy__(() => {
//     let reg = __force__(init);
//     for (const x of __force__(feed)) {          // (or `if (x !== undefined)` for an option)
//       const elem = __lazyDone__(x);
//       const prev = __lazyDone__(reg);            // reads the carried value
//       …step subtree…;
//       reg = __force__(step);                     // writes the next value
//     }
//     return reg;                                  // final = init if no iteration ran
//   });
//
// `prev` is pre-memoised to a fresh per-iteration `__lazyDone__(reg)` and the
// element to `__lazyDone__(x)`, both inside the loop body, so the step subtree
// re-runs each iteration (a register is the one place laziness must NOT cache
// across firings — the bindings live in the body, never hoisted). Only a
// single-level driving flow is compiled: a joined / nested / case flow raises
// Todo, because which flow a register's next iteration binds to is the Delay
// ontology open problem (iteration-with-state-design.md).
and emitRegister = (st: state, ctx: ctxPath, wn: node, read: node, step: valueRef): compiled => {
  let (flow, init) = switch read.kind {
  | DelayRead({flow, init}) => (flow, init)
  | _ =>
    failwith("Codegen.emitRegister: DelayWrite's read is not a DelayRead — Check should have witnessed this")
  }
  let exterior = instantiate(
    ~what="Register final, node " ++ Int.toString(wn.id),
    Context.flowContext(flow),
    ctx,
  )
  let (uncollect, isList) = switch spine(flow) {
  | [IterLevel({uncollect, isList})] => (uncollect, isList)
  | _ =>
    throw(
      Todo(
        "register over a joined / nested / case flow — which flow the next " ++
        "iteration binds to is the Delay ontology open problem " ++
        "(iteration-with-state-design.md)",
      ),
    )
  }
  let input = switch uncollect.kind {
  | Uncollect({input}) => input
  | _ => failwith("Codegen.emitRegister: register flow's level is not an Uncollect")
  }
  let ownFlow = FlowPort(uncollect, "flow")
  if flowsKey(Context.flowContext(ownFlow)) !== flowsKey(exterior->Array.map(s => s.flow)) {
    failwith(
      "Codegen.emitRegister: register flow is not nesting-adjacent to its exterior — " ++
      "Check's join-adjacency rule should have witnessed this",
    )
  }

  let floatedAcc: array<placed> = []
  // Feed (the collection / option) and init are loop-invariant — compiled at
  // the exterior, they float out of the thunk.
  let feedC = compileValue(st, exterior, input)
  feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
  let initC = compileValue(st, exterior, init)
  initC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let regName = st.fresh()
  let bodyCtx = Array.concat(exterior, [{flow: ownFlow, thunkOf: wn.id}])
  let iterVar = st.fresh()
  let elemName = st.fresh()
  let prevName = st.fresh()
  recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
  recordMemo(st, read.id, "prev", bodyCtx, prevName)
  let stepC = compileValue(st, bodyCtx, step)
  stepC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  // Partition: step work addressed to the loop body is claimed into it;
  // loop-invariant work floats out of the thunk.
  let bucket: array<JsAst.stmt> = []
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    if ctxPathKey(pl.at) === ctxPathKey(bodyCtx) {
      Array.push(bucket, pl.stmt)
    } else if isCtxPrefix(pl.at, exterior) {
      Array.push(escaped, pl)
    } else {
      failwith("Codegen: a statement floated to a context unrelated to the register being assembled — placement bug")
    }
  )

  let loopBody = Array.concat(
    Array.concat(
      [
        JsBuild.const(elemName, Runtime.lazyDoneOf(JsBuild.id(iterVar))),
        JsBuild.const(prevName, Runtime.lazyDoneOf(JsBuild.id(regName))),
      ],
      bucket,
    ),
    [JsBuild.exprStmt(JsBuild.assign(JsBuild.id(regName), Runtime.forceOf(JsBuild.id(stepC.name))))],
  )
  let loopStmts = if isList {
    [JsBuild.forOf(iterVar, Runtime.forceOf(JsBuild.id(feedC.name)), loopBody)]
  } else {
    [
      JsBuild.const(iterVar, Runtime.forceOf(JsBuild.id(feedC.name))),
      JsBuild.if_(JsBuild.neq(JsBuild.id(iterVar), JsBuild.undefined), loopBody),
    ]
  }
  let thunkBody = Array.concat(
    [JsBuild.let_(regName, Runtime.forceOf(JsBuild.id(initC.name)))],
    Array.concat(loopStmts, [JsBuild.ret(JsBuild.id(regName))]),
  )

  let name = st.fresh()
  recordMemo(st, wn.id, "final", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// The shared table for a product-spanning value (product-flows-design.md, "A
// node whose flow-variable set spans a product's axes memoises at the product
// context, as a point-indexed structure — one entry per point, computed on
// first force"). Built once in the Cross's stored orientation and cached in
// st.tableMemo, so both readings of the product (and any other consumer) share
// it and the user's computation runs once per cell. Returns the binding name
// and the statements to float (the table lazy plus its feeds), or just the name
// if a prior consumer already built it.
and getOrBuildTable = (st: state, p: product, sVal: valueRef): (string, array<placed>) => {
  let (sNode, sPort) = switch sVal {
  | ValuePort(n, port) => (n, port)
  }
  let tkey = memoKey(sNode.id, sPort)
  switch Map.get(st.tableMemo, tkey) {
  | Some(existing) => (existing, [])
  | None =>
    // The product context, stored orientation, tagged with the Cross's id so
    // the two consumer chains share this one table's scope.
    let segs = p.axes->Array.map(a => {flow: a.flow, thunkOf: p.crossId})
    // Feeds (the list sources) are loop-invariant — compiled at the top level.
    let feedCs = p.axes->Array.map(a => compileValue(st, [], a.feed))
    let arrNames = p.axes->Array.map(_ => st.fresh())
    let idxVars = p.axes->Array.map(_ => st.fresh())
    // Pre-memoise each axis's element at its sub-context, so compiling sVal
    // resolves the elements; the bindings are emitted manually into the loops.
    let elemNames = p.axes->Array.mapWithIndex((a, i) => {
      let subCtx = segs->Array.slice(~start=0, ~end=i + 1)
      let elemName = st.fresh()
      recordMemo(st, a.uncollect.id, "element", subCtx, elemName)
      elemName
    })

    let fullCtx = segs
    let floatedAcc: array<placed> = []
    feedCs->Array.forEach(c => c.floated->Array.forEach(pl => Array.push(floatedAcc, pl)))
    let valC = compileValue(st, fullCtx, sVal)
    valC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

    // Bucket sVal's statements into the loop bodies; loop-invariant work floats
    // out of the table thunk (the feeds, the discriminator externs, …).
    let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
    segs->Array.forEachWithIndex((_, i) =>
      Map.set(buckets, ctxPathKey(segs->Array.slice(~start=0, ~end=i + 1)), [])
    )
    let escaped: array<placed> = []
    floatedAcc->Array.forEach(pl =>
      switch Map.get(buckets, ctxPathKey(pl.at)) {
      | Some(bk) => Array.push(bk, pl.stmt)
      | None =>
        if Array.length(pl.at) === 0 {
          Array.push(escaped, pl)
        } else {
          failwith("Codegen: a statement floated to a context unrelated to the product table — placement bug")
        }
      }
    )

    // Assemble innermost-out. This emitter handles the binary product only;
    // n-ary is the poset round's remaining generalisation.
    if Array.length(p.axes) !== 2 {
      throw(Todo("n-ary product table (three or more crossed axes) — product-flows-design.md's flat axis sets"))
    }
    let a0 = arrNames->Array.getUnsafe(0)
    let a1 = arrNames->Array.getUnsafe(1)
    let i0 = idxVars->Array.getUnsafe(0)
    let i1 = idxVars->Array.getUnsafe(1)
    let e0 = elemNames->Array.getUnsafe(0)
    let e1 = elemNames->Array.getUnsafe(1)
    let feed0 = feedCs->Array.getUnsafe(0)
    let feed1 = feedCs->Array.getUnsafe(1)
    let bucket0 = Map.get(buckets, ctxPathKey(segs->Array.slice(~start=0, ~end=1)))->Option.getOr([])
    let bucket1 = Map.get(buckets, ctxPathKey(segs))->Option.getOr([])

    let rowName = st.fresh()
    let tName = st.fresh()
    let innerBody = Array.concat(
      Array.concat(
        [JsBuild.const(e1, Runtime.lazyDoneOf(JsBuild.index(JsBuild.id(a1), JsBuild.id(i1))))],
        bucket1,
      ),
      [JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(rowName), "push"), [Runtime.forceOf(JsBuild.id(valC.name))]))],
    )
    let outerBody = Array.concat(
      Array.concat(
        [JsBuild.const(e0, Runtime.lazyDoneOf(JsBuild.index(JsBuild.id(a0), JsBuild.id(i0))))],
        bucket0,
      ),
      [
        JsBuild.const(rowName, JsBuild.array_([])),
        cForArr(i1, a1, innerBody),
        JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(tName), "push"), [JsBuild.id(rowName)])),
      ],
    )
    let thunkBody = [
      JsBuild.const(a0, Runtime.forceOf(JsBuild.id(feed0.name))),
      JsBuild.const(a1, Runtime.forceOf(JsBuild.id(feed1.name))),
      JsBuild.const(tName, JsBuild.array_([])),
      cForArr(i0, a0, outerBody),
      JsBuild.ret(JsBuild.id(tName)),
    ]

    let tableName = st.fresh()
    Map.set(st.tableMemo, tkey, tableName)
    (
      tableName,
      Array.concat(escaped, [{at: [], stmt: JsBuild.const(tableName, Runtime.lazyOf(thunkBody))}]),
    )
  }
}

// A product-consumer chain: two nested collects reading one shared table in a
// chosen order (product-flows-design.md, "each consumer traverses the shared
// table in its own order"). Both axes are traversed by index so out1 and its
// transpose out2 index the same [i0][i1] table. Output is a list of lists (the
// any-list rule: two list axes ⇒ nested lists).
and emitProductChain = (st: state, ctx: ctxPath, cn: node, m: productMatch): compiled => {
  let floatedAcc: array<placed> = []
  let (tableName, tableFloated) = getOrBuildTable(st, m.product, m.sVal)
  tableFloated->Array.forEach(pl => Array.push(floatedAcc, pl))

  // The consumer's outer/inner feeds — the same list sources, memo-shared with
  // the table build, so they compile once.
  let feedOuterC = compileValue(st, ctx, m.outerAxis.feed)
  feedOuterC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
  let feedInnerC = compileValue(st, ctx, m.innerAxis.feed)
  feedInnerC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let iOuter = st.fresh()
  let iInner = st.fresh()
  let tbl = st.fresh()
  let aOuter = st.fresh()
  let aInner = st.fresh()

  // Index the table in its stored orientation: each product axis contributes
  // the loop index of whichever collect iterates it.
  let indexFor = (a: productAxis): string =>
    if a.axisKey === m.outerAxis.axisKey {
      iOuter
    } else {
      iInner
    }
  let lookup = m.product.axes->Array.reduce(JsBuild.id(tbl), (acc, a) =>
    JsBuild.index(acc, JsBuild.id(indexFor(a)))
  )

  let innerName = st.fresh()
  let outName = st.fresh()
  let innerBody = [
    JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(innerName), "push"), [lookup])),
  ]
  let outerBody = [
    JsBuild.const(innerName, JsBuild.array_([])),
    cForArr(iInner, aInner, innerBody),
    JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(outName), "push"), [JsBuild.id(innerName)])),
  ]
  let thunkBody = [
    JsBuild.const(tbl, Runtime.forceOf(JsBuild.id(tableName))),
    JsBuild.const(aOuter, Runtime.forceOf(JsBuild.id(feedOuterC.name))),
    JsBuild.const(aInner, Runtime.forceOf(JsBuild.id(feedInnerC.name))),
    JsBuild.const(outName, JsBuild.array_([])),
    cForArr(iOuter, aOuter, outerBody),
    JsBuild.ret(JsBuild.id(outName)),
  ]

  let name = st.fresh()
  recordMemo(st, cn.id, "value", ctx, name)
  {
    name,
    floated: Array.concat(floatedAcc, [{at: ctx, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// --- Entry ------------------------------------------------------------------

// One module's worth of statements plus named forced output expressions.
// The caller (Pipeline) decides packaging — today an IIFE per output for
// the eval harness; a real ES module with several exports is the target
// (compile-strategy-design.md, open question 3).
type generated = {
  stmts: array<JsAst.stmt>,
  outputs: array<(string, JsAst.expr)>,
}

let codegen = (ann: Annotate.annotations, p: Program.program): generated => {
  let counter = ref(0)
  let fresh = () => {
    let n = counter.contents
    counter := n + 1
    "v" ++ Int.toString(n)
  }
  let products = p.nodes->Array.filterMap(productOf)
  let st: state = {fresh, ann, memo: Map.make(), products, tableMemo: Map.make()}
  let topStmts: array<JsAst.stmt> = []
  // Outputs share one state, so a node consumed by several outputs
  // compiles once — single-module multi-output compilation, which the
  // bridge (one legacy compile per output) could not do.
  let outputs = p.outputs->Array.map(o => {
    let c = compileValue(st, [], o.source)
    c.floated->Array.forEach(pl =>
      if Array.length(pl.at) === 0 {
        Array.push(topStmts, pl.stmt)
      } else {
        failwith("Codegen: a statement floated past the top level — placement bug")
      }
    )
    (o.name, Runtime.forceOf(JsBuild.id(c.name)))
  })
  {stmts: Array.concat(Runtime.preludeStmts, topStmts), outputs}
}
