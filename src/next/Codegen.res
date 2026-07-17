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

type state = {
  fresh: unit => string,
  ann: Annotate.annotations,
  // (node id ++ ":" ++ port) -> emitted bindings, each with the context it
  // was placed in.
  memo: Map.t<string, array<(ctxPath, string)>>,
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

let rec spine = (f: flowRef): array<level> =>
  switch f {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: List}) => [IterLevel({uncollect: n, isList: true})]
    | Uncollect({flowKind: Option}) => [IterLevel({uncollect: n, isList: false})]
    | Uncollect({flowKind: Case(_)}) => [AltLevel({split: n, alt: port})]
    | Join({outer, inner}) => Array.concat(spine(outer), spine(inner))
    | Commute(_) =>
      throw(Todo("commute in a collect chain — the swapped-orientation walk (lazy-stream-commute-design.md)"))
    | Cross(_) =>
      throw(Todo("cross in a collect chain — the point-indexed table (product-flows-design.md)"))
    | Collect(_) =>
      throw(Todo("a partial collect's merged flow consumed downstream (partial-collect-design.md)"))
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
      | Collect({branches}) => emitCollect(st, ctx, n, branches)
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
      | DelayRead(_) | DelayWrite(_) =>
        // Registers: the read compiles to a loop-skeleton `let` (init
        // before the driving flow's loop, read at top of body), the write
        // to assign-at-bottom, `final` readable after — which means the
        // driving collect's emitter must emit them into ITS skeleton, via
        // st.ann.writeIndex. Growth-path: registers.
        throw(Todo("registers (DelayRead/DelayWrite) — first-class-ports-design.md, the pair section"))
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
  let required = instantiate(
    ~what="App node " ++ Int.toString(n.id),
    Context.valueContext(ValuePort(n, "value")),
    ctx,
  )
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
      let hasAlt = levels->Array.some(l =>
        switch l {
        | AltLevel(_) => true
        | IterLevel(_) => false
        }
      )
      if hasAlt {
        // The filter shape: join(list flow, case-alt flow). One thunk =
        // accumulator + the Iter levels' loops + `const s = disc(force(elem));
        // if (s.tag === alt) { <alt payload pre-memoised as lazyDone(s.value)>
        // ...value...; out.push(force(value)) }`. Mirror Compile.emitFilterClose;
        // the AltLevel carries the split node and alt name.
        throw(Todo("filter collect (a case-alt level in an iter chain) — mirror Compile.emitFilterClose"))
      }
      emitIterCollect(st, ctx, cn, branch, levels)
    }
  | CaseFull =>
    // One thunk: `const s = force(disc)(force(input)); let out;` then an
    // if-chain on s.tag, one arm per branch (exhaustive, else-throw). Each
    // arm pre-memoises the alt's payload port (split.id, alt) to a shared
    // `const v = __lazyDone__(s.value)` at context exterior ++ [alt flow
    // tagged with this collect], compiles its branch value there, assigns
    // out. Mirror Compile.emitCaseClose (note: the discriminator is a wire
    // here — force it like emitApp forces fn).
    throw(Todo("case collect — mirror Compile.emitCaseClose"))
  | CasePartial(_) =>
    // The three arm shapes of partial-collect-design.md, dispatched by
    // coverage; the merged "flow" port of the collect is itself a flow
    // other spines may consume. Lands after case collect.
    throw(Todo("partial collect — partial-collect-design.md"))
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
    | AltLevel(_) => failwith("Codegen.emitIterCollect: alt level — dispatched to the filter emitter upstream")
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
  let st: state = {fresh, ann, memo: Map.make()}
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
