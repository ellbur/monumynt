// Pass 4 of the compile pipeline: the recursive, memoised, context-passing
// code generator (compile-strategy-design.md).
//
// STATUS: the machinery is real and running — pure let-floating placement,
// the (node, port, context) memo with prefix reuse, per-thunk context
// instantiation. Emitters cover the value fragment (Lit, App), iter collects
// (list/option chains with binary Join), case and filter collects, partial
// collects, registers (the Delay pair), and the whole-table Cross at any rank.
// The emitters that still raise `Todo` are genuine gaps owned by the poset
// round (commute, cross of non-top-level / non-list axes and the
// partial/sub-product consumer, partial's merged-context computation,
// registers over a dispatched/filtered or product driving flow — a register
// over a flattened SEQUENCE now compiles) — a `Todo` means "no emitter yet",
// not "fall back elsewhere": there is no other engine.
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
//     memo-reused in the other (bodyRef object identity would do this
//     imperatively; tags are the pure spelling). Cross-thunk sharing
//     of per-iteration work is therefore still not preserved — the
//     documented cost of the eager model, unchanged.
//   - MEMO keys on (node id, port); each entry stores the instantiated
//     context the binding was placed in. Lookup reuses an entry whose
//     context is a PREFIX of the requesting one (an ancestor scan, plumbed
//     as a prefix check). Lits memoise at the empty context, so they are
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
// Error discipline: `Todo` = an emitter that is not written yet (surfaced to
// the caller as a compiler gap). `failwith` = a compiler bug or an ill-formed
// program that pass 1 should have witnessed — never user-facing.

open Program

exception Todo(string)

// --- Context: instantiated paths ------------------------------------------

// One open flow on the consumer chain, tagged with the collect node whose
// emitted thunk owns the corresponding JS scope. `idxVar` is the loop's index
// variable when the layer is a PRODUCT AXIS traversed by index — the coordinate
// a partial product traversal nested inside this loop indexes the shared table
// with (product-flows-design.md, "reduce along an axis, fibered over the rest").
// None for every ordinary for-of / option layer; it is scope bookkeeping, never
// part of a segment's identity.
type seg = {flow: flowRef, thunkOf: int, idxVar: option<string>}

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
// chain context: the SHORTEST PREFIX of `ctx` that opens every flow the path
// names. This is the "deepest prefix covering the flow-variable set" rule —
// let-floating stated directly. A structural flow the chain does not open at all
// means the reference is ill-formed and pass 1 should have witnessed it.
//
// The flows are matched as a SET, not as a sequence, which is the rule as
// stated. Two reasons it must be: the chain is allowed to carry segments the
// path does not mention (a fibering axis is a sibling, so it sits on no linear
// path, yet a value compiled inside a fibered traversal legitimately has it
// open), and a path may NAME sibling axes, which have no order between them — a
// collect over one axis of a rank-3 product reports the surviving `{Y, Z}`
// flattened in the combine's operand order while the consuming chain opens them
// in whatever order it chose (`Context.remainderPath`). Ordered matching would
// reject the transposed reading of a product for no reason but the flattening's
// arbitrary order. For an all-nesting program the path is exactly a prefix and
// both readings agree, so this is the plain prefix rule it replaces.
//
// A step is matched by `Context.stepAvailableAt`, not by raw key equality: a
// BUNDLE step is a cell SET, and a value borne on a merged flow `{A, B}` is
// available inside each constituent cell the chain opens (`{A} ⊆ {A, B}` — the
// containment theorem, partial-collect-design.md "The merged flow as parent
// scope"). That is what lets a merged-context computation — the doc's
// `logAndFallback` step — be emitted per arm of a partial collect's dispatch,
// where the chain opens one alt rather than the merged flow itself. Code
// duplicated across arms, evaluation still once: exactly one arm runs.
let matchChain = (structural: array<flowRef>, ctx: ctxPath): option<int> => {
  let pos = ref(0)
  let ok = ref(true)
  structural->Array.forEach(f => {
    let j = ctx->Array.findLastIndex(s => Context.stepAvailableAt(f, s.flow))
    if j < 0 {
      ok := false
    } else if j + 1 > pos.contents {
      pos := j + 1
    }
  })
  ok.contents ? Some(pos.contents) : None
}

// Does the chain so far open every flow of a structural exterior, in order? The
// adjacency assert asks this of each level it opens.
let chainOpens = (structural: array<flowRef>, ctx: ctxPath): bool =>
  Option.isSome(matchChain(structural, ctx))

let instantiate = (~what: string, structural: array<flowRef>, ctx: ctxPath): ctxPath =>
  switch matchChain(structural, ctx) {
  | Some(pos) => ctx->Array.slice(~start=0, ~end=pos)
  | None =>
    failwith(
      "Codegen: " ++
      what ++
      " requires flow context " ++
      Context.contextToString(structural) ++
      " which the current chain does not open — an ill-formed reference " ++
      "(or early product) that Check should have witnessed",
    )
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

// The axes a Cross operand contributes: a single supported axis, or — for a
// nested Cross (`cross(cross(x, y), z)`) — the flattened axes of the whole
// sub-product, left-first (the stored orientation). None if any leaf is not a
// supported axis. This is why a rank-n product is authored by nesting binary
// Crosses: the meaning is the flat, order-free axis set (product-flows-design.md,
// "Associativity: the nesting tree is how you wrote it; the axis set is what it
// means").
let rec productAxesOf = (f: flowRef): option<array<productAxis>> =>
  switch productAxisOf(f) {
  | Some(a) => Some([a])
  | None =>
    switch f {
    | FlowPort(n, "flow") =>
      switch n.kind {
      | Cross({left, right}) =>
        switch (productAxesOf(left), productAxesOf(right)) {
        | (Some(la), Some(ra)) => Some(Array.concat(la, ra))
        | _ => None
        }
      | _ => None
      }
    | _ => None
    }
  }

// The product a Cross node constructs, when all its leaf operands are supported
// axes. A nested cross flattens to its full axis set; a two-of-three-axis inner
// cross is ALSO a product in its own right (the author naming a sub-product), so
// every Cross node in the tree contributes one entry to `st.products`.
let productOf = (n: node): option<product> =>
  switch n.kind {
  | Cross(_) =>
    switch productAxesOf(FlowPort(n, "flow")) {
    | Some(axes) if Array.length(axes) >= 2 => Some({crossId: n.id, axes})
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
        // The dispatch is over the underlying case split's cells, found by
        // walking (a branch may itself be another partial collect's merged
        // flow, so the split is not always the branch flow's own node).
        switch branchCells(f) {
        | Some((split, _)) => [PartialLevel({collect: n, split, branches})]
        | None =>
          failwith(
            "Codegen.spine: a partial collect's merged flow names no bundle cells — " ++
            "Check's coverage rule should have witnessed this",
          )
        }
      | _ =>
        failwith("Codegen.spine: a Collect with no flow port reached as a flow — Check's port-exists rule should have witnessed this")
      }
    | Join({outer, inner}) => Array.concat(spine(outer), spine(inner))
    | Commute(_) =>
      throw(Todo("commute in a collect chain — the swapped-orientation walk (lazy-stream-commute-design.md)"))
    | Cross(_) =>
      throw(Todo("cross in a collect chain — the point-indexed table (product-flows-design.md)"))
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) =>
      failwith("Codegen.spine: node kind has no flow ports — Check's port-exists rule should have witnessed this")
    }
  }

// Per-level assembly plan for an iter collect (see emitIterCollect).
type levelPlan = {
  uncollect: node,
  isList: bool,
  bodyCtx: ctxPath,
  feedName: string, // binding whose forced value is the collection / option
  iterVar: string, // list: the for-of variable (or the index, when `indexed`);
  //                  option: the tested const
  elemName: string, // the __lazyDone__ element binding, memoised at bodyCtx
  // A PRODUCT AXIS is traversed by index instead of by for-of, so a partial
  // product traversal nested inside this loop can index the shared table at this
  // coordinate. Carries the forced-array binding the index runs over.
  indexed: option<string>,
}

// Per-alt assembly plan for a case collect (see emitCaseCollect).
type altPlan = {
  altName: string,
  altCtx: ctxPath, // exterior ++ [this alt's flow tagged with the collect]
  payloadName: string, // the __lazyDone__(split.value) binding, memoised at altCtx
  valueName: string, // the compiled branch value, forced into `out`
}

// Per-level assembly plan for a filter / filter-then-flatmap collect (see
// emitCellChain): iter levels (loops) and dispatch levels (case-alt
// guards) interleaved in any order. An `FIter` opens a for-of (list) or
// defined-check (option); an `FAlt` computes `s = disc(input)` then guards its
// alt, binding the payload for iter levels nested *inside* the dispatch.
type filterPlan =
  | FIter({uncollect: node, isList: bool, bodyCtx: ctxPath, feedName: string, iterVar: string, elemName: string})
  | FAlt({
      split: node,
      alt: string,
      altCtx: ctxPath, // parent ++ [this alt's flow tagged with the collect]
      splitName: string, // the `const s = disc(input)` binding, in the parent body
      discName: string, // the discriminator wire, forced at the dispatch
      inputName: string, // the value dispatched, forced at the dispatch
      payloadName: string, // the __lazyDone__(s.value) binding, memoised at altCtx
    })

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

// --- The running view (scanl) ------------------------------------------------
//
// A register (Delay pair) is a feature of a flow, not a threaded wire
// (delay-ontology-design.md). Its running value is readable at each firing as
// the `prev` port. A SIBLING collect over the SAME driving flow may read that
// `prev` to build the running-view list (a scan / prefix-fold: [init, init⊕x₀,
// init⊕x₀⊕x₁, …]). In the eager model each consumer gets its OWN loop and
// re-runs the fold — the documented per-consumer cost — so the reading collect
// is emitted as a register-driven loop that PUSHES the branch value each firing
// instead of only returning the final accumulator (emitRunningCollect). The
// write half's `final` output, if also present, still emits its own loop
// (emitRegister); the two fold independently.

// The DelayRead nodes whose `prev` a value reads, walked through the value cone
// (App / Aggregate / Disaggregate); deduped by id, order-preserving.
let readsPrevRegs = (v: valueRef): array<node> => {
  let acc: array<node> = []
  let rec go = (v: valueRef): unit =>
    switch v {
    | ValuePort(n, port) =>
      switch n.kind {
      | DelayRead(_) =>
        if port === "prev" && !(acc->Array.some(x => x.id === n.id)) {
          Array.push(acc, n)
        }
      | App({fn, args}) => {
          go(fn)
          args->Array.forEach(go)
        }
      | Aggregate({fields}) => fields->Array.forEach(((_, fv)) => go(fv))
      | Disaggregate({struct_}) => go(struct_)
      | Lit(_) | Uncollect(_) | Collect(_) | Join(_) | Commute(_) | Cross(_) | DelayWrite(_) => ()
      }
    }
  go(v)
  acc
}

// A recognized product-consumer chain: k nested collects over the k axes of one
// product, terminating in a value that spans exactly that product. `chainAxes`
// is outer-first — one axis per collect in the chain, the order the consumer
// traverses (its own reading of the shared table).
type productMatch = {
  product: product,
  chainAxes: array<productAxis>, // outer-first, one per collect in the chain
  sVal: valueRef, // the product-spanning value the chain carries through
}

// Unwind a nested single-branch collect chain: gather each collect's flow
// (outer-first) and the terminal non-collect value it carries.
let rec chainFlows = (v: valueRef): (array<flowRef>, valueRef) =>
  switch v {
  | ValuePort(n, "value") =>
    switch n.kind {
    | Collect({branches: [{flow, value}]}) =>
      let (rest, term) = chainFlows(value)
      (Array.concat([flow], rest), term)
    | _ => ([], v)
    }
  | _ => ([], v)
  }

let sameKeySet = (a: array<string>, b: array<string>): bool =>
  a->Array.every(k => b->Array.includes(k)) && b->Array.every(k => a->Array.includes(k))

// Does this collect head a product-consumer chain the whole-table emitter
// handles? It must be `collect(f0, collect(f1, … collect(f_{k-1}, s)))` where
// f0…f_{k-1} are the k DISTINCT axes of one constructed product and s varies
// over EXACTLY that product (all k axes). Returns None for every other shape —
// ordinary linear collects (whose value never spans a sibling axis), and partial
// consumers that collect only some of a product's axes (holding the rest), which
// the direct whole-table emitter does not yet handle.
let matchProductChain = (st: state, cn: node): option<productMatch> =>
  switch cn.kind {
  | Collect({branches: [{flow: f0, value: v1}]}) =>
    let (rest, sVal) = chainFlows(v1)
    let flows = Array.concat([f0], rest)
    let keys = flows->Array.map(Context.flowKey)
    // Distinct axes only — a chain that revisits an axis is not a product read.
    let distinct = keys->Array.everyWithIndex((k, i) => keys->Array.indexOf(k) === i)
    // A terminal that reads a register's `prev` is not a per-point function of
    // the product: its value at a point depends on the fold so far along the
    // register's axis, so it must be emitted by the running-view loop, not
    // evaluated cell-by-cell into a table.
    if !distinct || Array.length(readsPrevRegs(sVal)) > 0 {
      None
    } else {
      st.products
      ->Array.find(p => sameKeySet(keys, p.axes->Array.map(a => a.axisKey)))
      ->Option.flatMap(p => {
        // s must vary over exactly the product's axes (the full-table consumer).
        let need = p.axes->Array.map(a => a.axisKey)
        let sAxes = Annotate.valueAxes(sVal)
        if sameKeySet(need, sAxes) {
          // The chain's axes in traversal order (outer-first), each resolved
          // against the product's stored axis records.
          let chainAxes = flows->Array.filterMap(f => {
            let k = Context.flowKey(f)
            p.axes->Array.find(a => a.axisKey === k)
          })
          if Array.length(chainAxes) === Array.length(flows) {
            Some({product: p, chainAxes, sVal})
          } else {
            None
          }
        } else {
          None
        }
      })
    }
  | _ => None
  }

// Is this uncollect an axis of some product the program constructs? Such a level
// is traversed by INDEX rather than by for-of, so that a partial product
// traversal nested inside it can index the shared table at this coordinate.
let isProductAxisNode = (st: state, uncollect: node): bool =>
  st.products->Array.some(p => p.axes->Array.some(a => a.uncollect.id === uncollect.id))

// A PARTIAL product traversal: a collect chain over a proper, non-empty subset of
// one product's axes, whose terminal spans the whole product. This is
// product-flows-design.md's "reduce along an axis, fibered over the rest" in
// collect form — collecting the X axis of an {X, Y} product yields one list per
// y, i.e. a value that still varies with Y ("a collect over a crossed axis
// reports {Y}", the context model). The axes the chain does NOT collect are
// HELD: they must already be open in the current chain context as indexed
// product-axis loops, whose index variables the emitted thunk reads to index the
// shared table.
//
// Any number of axes may be held. With one, the fiber is a single layer; with
// several — a rank-3 product collected over one axis holds `{Y, Z}` — the fiber
// is a genuine product context, and what places this collect's consumers inside
// BOTH holding loops is `Context.remainderPath` naming both surviving axes plus
// `matchChain` matching them set-wise (siblings have no order; the chain
// supplies the one it chose). Either way the emitted read is the same: index the
// one shared table at the held coordinates.
type partialProductMatch = {
  pProduct: product,
  pChainAxes: array<productAxis>, // outer-first, one per collect in the chain
  pHeld: array<(productAxis, string)>, // held axis -> the enclosing loop's index var
  pSVal: valueRef,
  pPlaceCtx: ctxPath, // the shortest prefix of ctx that opens every held axis
}

let matchPartialProductChain = (st: state, ctx: ctxPath, cn: node): option<partialProductMatch> =>
  switch cn.kind {
  | Collect({branches: [{flow: f0, value: v1}]}) =>
    let (rest, sVal) = chainFlows(v1)
    let flows = Array.concat([f0], rest)
    let keys = flows->Array.map(Context.flowKey)
    let distinct = keys->Array.everyWithIndex((k, i) => keys->Array.indexOf(k) === i)
    // As above: a `prev`-reading terminal belongs to the running-view loop.
    if !distinct || Array.length(readsPrevRegs(sVal)) > 0 {
      None
    } else {
      let sAxes = Annotate.valueAxes(sVal)
      let found = ref(None)
      st.products->Array.forEach(p =>
        if Option.isNone(found.contents) {
          let axisKeys = p.axes->Array.map(a => a.axisKey)
          let held = p.axes->Array.filter(a => !(keys->Array.includes(a.axisKey)))
          // The chain must read only this product's axes, hold at least one of
          // them (holding none is the FULL chain, matchProductChain's), and its
          // terminal must span the whole product.
          if (
            keys->Array.every(k => axisKeys->Array.includes(k)) &&
            Array.length(held) >= 1 &&
            Array.length(keys) >= 1 &&
            sameKeySet(axisKeys, sAxes)
          ) {
            // Every held axis must be an indexed loop already open on this chain.
            let resolved = held->Array.filterMap(a =>
              ctx
              ->Array.find(s =>
                Context.flowKey(s.flow) === a.axisKey && Option.isSome(s.idxVar)
              )
              ->Option.flatMap(s => s.idxVar->Option.map(iv => (a, iv)))
            )
            let chainAxes = flows->Array.filterMap(f => {
              let k = Context.flowKey(f)
              p.axes->Array.find(a => a.axisKey === k)
            })
            if (
              Array.length(resolved) === Array.length(held) &&
              Array.length(chainAxes) === Array.length(flows)
            ) {
              // Place the traversal in the shortest prefix of ctx that opens
              // every held axis — deeper than that would recompute it per
              // unrelated iteration, shallower would put the index out of scope.
              let deepest = ref(0)
              ctx->Array.forEachWithIndex((s, i) =>
                if held->Array.some(a => Context.flowKey(s.flow) === a.axisKey) {
                  deepest := i + 1
                }
              )
              found :=
                Some({
                  pProduct: p,
                  pChainAxes: chainAxes,
                  pHeld: resolved,
                  pSVal: sVal,
                  pPlaceCtx: ctx->Array.slice(~start=0, ~end=deepest.contents),
                })
            }
          }
        }
      )
      found.contents
    }
  | _ => None
  }

// A single-branch collect chain whose terminal value has NO linear context — its
// args live on incomparable sibling axes — but which `matchProductChain` did not
// resolve to a full constructed product. Since Check's full-span alignment now
// WITNESSES the case where no product spans the terminal's axes at all (an
// under-covered n-ary combine, e.g. `f(x,y,z)` with only {X,Y} crossed —
// Pipeline returns those witnesses before codegen runs), what reaches this
// backstop is the OTHER shape: a terminal whose span IS covered by a constructed
// product, but which the chain collects over only SOME of its axes while holding
// the rest (a partial / sub-product traversal). The whole-table emitter needs the
// EXACT product spanning the CHAIN's axes, which is a sub-product that a flat
// cross never built; compiling it would reach a sibling element port outside its
// flow (a raw failwith). This predicate lets the router decline with a clean Todo
// instead, leaving that traversal to the rest of the poset round (the general
// poset-valued context). A value with a linear context (an ordinary nested
// collect) returns false and compiles normally.
let underCoveredProduct = (cn: node): bool =>
  switch cn.kind {
  | Collect({branches: [{value}]}) =>
    let (_, terminal) = chainFlows(value)
    // A `prev`-reading terminal is a running view, not a table read: its
    // product-spanning combine is emitted inside the register's own loop
    // (emitRunningCollect), so an incomparable context here is expected.
    if Array.length(readsPrevRegs(terminal)) > 0 {
      false
    } else {
      switch Context.valueContext(terminal) {
      | _ => false
      | exception Context.Incomparable(_) => true
      }
    }
  | _ => false
  }

// The opener/dispatch a spine level stands on, as a key — used to compare a
// register's driving flow to a collect's flow (they scan the same sequence iff
// their spines stand on the same levels in the same order). An alt level carries
// its ALT NAME as well as the split id: two different alts of one split are two
// different subsequences, so a register folding the Keep alt is not scanned by a
// collect over the Drop alt.
// A PARTIAL level is the same key at width k: the split plus the CELL SET it
// keeps, so two merges of different cells over one split are two different
// subsequences, exactly as two alts of one split are.
let levelKey = (l: level): string =>
  switch l {
  | IterLevel({uncollect}) => Int.toString(uncollect.id)
  | AltLevel({split, alt}) => Int.toString(split.id) ++ ":" ++ alt
  | PartialLevel({split, branches}) =>
    Int.toString(split.id) ++
    ":" ++
    switch classifyCollect(branches) {
    | CasePartial(cells) => cells->Array.toSorted(String.compare)->Array.join("|")
    | _ => "partial"
    }
  }

let sameLevelKeys = (a: array<string>, b: array<string>): bool =>
  Array.length(a) === Array.length(b) &&
  a->Array.everyWithIndex((x, i) => b[i] === Some(x))

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
      | Aggregate({fields}) => emitAggregate(st, ctx, n, fields)
      | Disaggregate({struct_}) => emitDisaggregate(st, ctx, n, struct_, port)
      | Collect({branches}) =>
        switch matchProductChain(st, n) {
        | Some(m) => emitProductChain(st, ctx, n, m)
        | None =>
          switch matchPartialProductChain(st, ctx, n) {
          | Some(pm) => emitPartialProductChain(st, n, pm)
          | None =>
            if underCoveredProduct(n) {
              throw(
                Todo(
                  "an under-determined / partially-covered n-ary product consumer — the " ++
                  "whole-table emitter needs a constructed product whose axes the chain " ++
                  "either spans or holds all but one of (product-flows-design.md's N-ary " ++
                  "section; the poset round's context-model check owns the rest)",
                ),
              )
            } else {
              emitCollect(st, ctx, n, branches)
            }
          }
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
        // (emitRegister) and the running-view emitter (emitRunningCollect) both
        // pre-memoise `prev` into their own driving loop before compiling what
        // reads it, so a memo miss here means `prev` was read by a foreign
        // consumer whose loop the emitters do not (yet) supply — an IterCollect
        // scanl is handled by emitRunningCollect, but a case / partial / product
        // running view, or `prev` read by a value that no collect gathers, is
        // deferred (the shared-loop-skeleton case; ARCHITECTURE worklist item 6).
        // Check guarantees the program is well-formed (a boundary `prev` is
        // witnessed by the flow-borne rule), so this is a clean gap, not a bug.
        throw(
          Todo(
            "register `prev` read outside a supported driving loop — the running " ++
            "view is compiled only for an IterCollect sibling that scans the " ++
            "register's own flow (emitRunningCollect); a case / partial / product " ++
            "running view is the shared-loop-skeleton case (ARCHITECTURE worklist " ++
            "item 6, iteration-with-state-design.md running view)",
          ),
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
  // call forces it. Treating fn as a wire rather than an embedded expression
  // is what lets an App apply a computed function, not just a named extern.
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

// Struct construction: an object literal whose field values force their wires.
// Placement mirrors emitApp — a struct lives where its fields jointly live, and
// a product-context struct (fields on incomparable sibling axes) is placed at
// the current (product) context, the same Incomparable admission emitApp makes.
and emitAggregate = (
  st: state,
  ctx: ctxPath,
  n: node,
  fields: array<(string, valueRef)>,
): compiled => {
  let fieldCs = fields->Array.map(((k, v)) => (k, compileValue(st, ctx, v)))
  let required = switch Context.valueContext(ValuePort(n, "value")) {
  | structural =>
    instantiate(~what="Aggregate node " ++ Int.toString(n.id), structural, ctx)
  | exception Context.Incomparable(_) => ctx
  }
  let name = st.fresh()
  let objJs = JsBuild.obj(fieldCs->Array.map(((k, c)) => (k, Runtime.forceOf(JsBuild.id(c.name)))))
  recordMemo(st, n.id, "value", required, name)
  let own = {at: required, stmt: JsBuild.const(name, Runtime.lazyOfExpr(objJs))}
  {
    name,
    floated: Array.concat(fieldCs->Array.map(((_, c)) => c.floated)->Array.flat, [own]),
  }
}

// Struct projection: `force(struct).field`. `port` is the field being read; the
// struct wire is compiled once and each projection is its own memoised binding
// (sharing across fields is opt-in, like any node). The context is the struct's
// own — projection introduces no new axis.
and emitDisaggregate = (st: state, ctx: ctxPath, n: node, struct_: valueRef, port: string): compiled => {
  let sc = compileValue(st, ctx, struct_)
  let required = switch Context.valueContext(ValuePort(n, port)) {
  | structural =>
    instantiate(~what="Disaggregate node " ++ Int.toString(n.id), structural, ctx)
  | exception Context.Incomparable(_) => ctx
  }
  let name = st.fresh()
  let accessJs = JsBuild.member(Runtime.forceOf(JsBuild.id(sc.name)), port)
  recordMemo(st, n.id, port, required, name)
  let own = {at: required, stmt: JsBuild.const(name, Runtime.lazyOfExpr(accessJs))}
  {name, floated: Array.concat(sc.floated, [own])}
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
      // A branch that reads a register's `prev` is a running view (scanl) over
      // the same driving flow — it re-runs the fold, pushing the running value.
      let readsPrev = Array.length(readsPrevRegs(branch.value)) > 0
      if readsPrev {
        emitRunningCollect(st, ctx, cn, branch, levels)
      } else if hasPartial || hasAlt {
        emitCellChain(st, ctx, cn, branch, levels)
      } else {
        emitIterCollect(st, ctx, cn, branch, levels)
      }
    }
  | CaseFull => emitCaseCollect(st, ctx, cn, branches)
  | CasePartial(_) =>
    // A partial collect's value output is the MERGED value — flow-borne on its
    // own merged flow. The emitters that OPEN that flow (emitCellChain,
    // emitCaseCollect) pre-memoise it per arm, so reaching it here means it was
    // read from inside one of its cells by a chain that opened that cell some
    // OTHER way — an ordinary filter on one alt, say. That is well-formed by the
    // containment theorem (`{A} ⊆ {A, B}`), and inside cell A the merged value
    // IS A's branch value, so resolve it on demand: place it at the cell segment
    // the chain has open and bind the covering branch's value there.
    // (The merged flow consumed AS a flow is `spine`'s job, not this one.)
    let structural = Context.valueContext(ValuePort(cn, "value"))
    let armCtx = instantiate(
      ~what="Partial collect node " ++ Int.toString(cn.id) ++ "'s merged value",
      structural,
      ctx,
    )
    let cell = switch armCtx->Array.last {
    | Some({flow: FlowPort(_, port)}) => port
    | None =>
      failwith(
        "Codegen: partial collect node " ++
        Int.toString(cn.id) ++
        "'s merged value reached at the top level — Check's flow-borne rule should have witnessed this",
      )
    }
    let floated = memoiseMergedValues(st, armCtx, FlowPort(cn, "flow"), cell)
    switch lookupMemo(st, cn.id, "value", armCtx) {
    | Some(name) => {name, floated}
    | None =>
      failwith(
        "Codegen: partial collect node " ++
        Int.toString(cn.id) ++
        " covers no cell open on the chain — Check's flow-borne rule should have witnessed this",
      )
    }
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
  // Where the collect's own result lives — `Context.valueContext` of its value
  // port, which is the flow's exterior for an ordinary collect and the SURVIVING
  // (fibering) axes for a collect whose branch value varies over axes it does not
  // iterate: collecting the X axis of an {X, Y} product returns one list per y,
  // so the thunk belongs inside the loop holding y, not at the top level
  // (product-flows-design.md, "a collect over a crossed axis reports {Y}"). This
  // is the same report `emitRegister` places a fibered `final` by; for every
  // non-fibered collect it IS `flowContext(branch.flow)`, unchanged.
  let exterior = instantiate(
    ~what="Collect node " ++ Int.toString(cn.id),
    Context.valueContext(ValuePort(cn, "value")),
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
        // Adjacency: each level must open where the chain so far already is
        // (Check's join-adjacency rule; assert per check-and-tag). Stated as
        // "the chain opens every flow of this level's exterior" rather than
        // as path equality, so a fibering axis the chain also holds — a
        // product's sibling, on no linear path — does not read as a break.
        if !chainOpens(Context.flowContext(own), parentCtx.contents) {
          failwith(
            "Codegen: level " ++
            Int.toString(uncollect.id) ++
            " is not nesting-adjacent to the chain — Check's join-adjacency rule should have witnessed this",
          )
        }
        let feedC = compileValue(st, parentCtx.contents, input)
        feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        // A product axis is traversed by INDEX, so a partial product traversal
        // nested inside this loop has the coordinate it needs to index the
        // shared table (and the index agrees with the table's rows, both running
        // over the one memoised feed).
        let indexed = if isList && isProductAxisNode(st, uncollect) {
          Some(st.fresh())
        } else {
          None
        }
        let iterVar = st.fresh()
        let bodyCtx = Array.concat(
          parentCtx.contents,
          [
            {
              flow: own,
              thunkOf: cn.id,
              idxVar: switch indexed {
              | Some(_) => Some(iterVar)
              | None => None
              },
            },
          ],
        )
        let elemName = st.fresh()
        recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
        Array.push(
          plans,
          {uncollect, isList, bodyCtx, feedName: feedC.name, iterVar, elemName, indexed},
        )
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
    let elemSource = switch p.indexed {
    | Some(arrName) => JsBuild.index(JsBuild.id(arrName), JsBuild.id(p.iterVar))
    | None => JsBuild.id(p.iterVar)
    }
    let body = Array.concat(
      [JsBuild.const(p.elemName, Runtime.lazyDoneOf(elemSource))],
      Array.concat(bucket, nested.contents),
    )
    nested :=
      switch p.indexed {
      | Some(arrName) => [
          JsBuild.const(arrName, Runtime.forceOf(JsBuild.id(p.feedName))),
          cForArr(p.iterVar, arrName, body),
        ]
      | None =>
        if p.isList {
          [JsBuild.forOf(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName)), body)]
        } else {
          [
            JsBuild.const(p.iterVar, Runtime.forceOf(JsBuild.id(p.feedName))),
            JsBuild.if_(JsBuild.neq(JsBuild.id(p.iterVar), JsBuild.undefined), body),
          ]
        }
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

// The running view (scanl): a collect whose branch value reads one or more
// registers' `prev` over the SAME driving flow it iterates. Emitted as a
// register-driven loop that re-runs the fold and PUSHES the branch value each
// firing (the running list), rather than only returning the final accumulator
// (emitRegister). The levels are walked by `buildChain`, the same walk
// emitRegister and emitCellChain use, so a FILTERED driving flow
// (`join(list, case-alt)`) scans the kept subsequence: one output element per
// KEPT firing, carrying the running value at that firing — the running view of
// the register delay-ontology-design.md's route (b) already folds ("the
// register only updates when the option is Some"). A PARTIAL (cell-set) driving
// flow is that same scan at width k: the kept subsequence is the firings landing
// in any covered cell, and the walk branches into one arm per cell, each pushing
// and advancing inside its own arm. The two halves stay consistent because they
// walk the levels the same way — the view is placed by `levelKey`, which names a
// partial level by its CELL SET, so a view over `{A, B}` is not offered the
// register that folds `{A, C}`. Still deferred with a clean Todo: a product
// driving flow (`spine` raises before this) and a register whose driving flow
// the collect does not directly scan (ARCHITECTURE worklist item 6).
and emitRunningCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branch: collectBranch,
  levels: array<level>,
): compiled => {
  // Iter levels loop, alt levels guard one cell, partial levels k of them.
  let collectIds = levels->Array.map(levelKey)
  // Each register must (a) have a write half (its step) and (b) scan exactly the
  // same sequence this collect iterates — same spine levels in the same order.
  let regs = readsPrevRegs(branch.value)
  let stepOf = (reg: node): option<valueRef> =>
    st.ann.writeIndex
    ->Map.get(reg.id)
    ->Option.flatMap(wn =>
      switch wn.kind {
      | DelayWrite({step}) => Some(step)
      | _ => None
      }
    )
  let regScansSameFlow = (reg: node): bool =>
    switch reg.kind {
    | DelayRead({flow}) =>
      switch spine(flow) {
      | rl => sameLevelKeys(collectIds, rl->Array.map(levelKey))
      | exception Todo(_) => false // a product/commute driving flow — deferred
      }
    | _ => false
    }
  let supported =
    Array.length(regs) > 0 &&
    regs->Array.every(r => stepOf(r)->Option.isSome && regScansSameFlow(r))
  if !supported {
    throw(
      Todo(
        "running-view collect: `prev` is read over a product driving flow, or over " ++
        "a flow this collect does not directly scan — the shared-loop-skeleton case " ++
        "(ARCHITECTURE worklist item 6, iteration-with-state-design.md running view)",
      ),
    )
  }

  // Where the re-run fold lives. Normally the driving flow's exterior — but a
  // running view over a register that folds along ONE AXIS OF A PRODUCT lives at
  // the fiber, exactly where that register's `final` does: the scan keeps the
  // FULL product shape, the value at each point being the accumulation so far
  // along the folded axis *within that point's fiber* (product-flows-design.md,
  // "The running view keeps the shape"). A `DelayRead` does not name its step,
  // so the fiber is read off the write half; for a non-fibered register this is
  // the driving flow's exterior and nothing changes.
  let regFinalContext = (reg: node): array<flowRef> =>
    switch st.ann.writeIndex->Map.get(reg.id) {
    | Some(wn) => Context.valueContext(ValuePort(wn, "final"))
    | None => Context.flowContext(branch.flow)
    }
  let structuralExterior = switch regs->Array.get(0) {
  | Some(r) => regFinalContext(r)
  | None => Context.flowContext(branch.flow)
  }
  // Several registers over one flow must share a fiber (they share this loop).
  let oneFiber =
    regs->Array.every(r =>
      Context.contextToString(regFinalContext(r)) ===
        Context.contextToString(structuralExterior)
    )
  if !oneFiber || !chainOpens(structuralExterior, ctx) {
    throw(
      Todo(
        "running-view collect: the registers do not share one fiber, or the view " ++
        "is read outside the fiber its register folds over (product-flows-design.md, " ++
        "\"The running view keeps the shape\")",
      ),
    )
  }
  let exterior = instantiate(
    ~what="Running-view collect node " ++ Int.toString(cn.id),
    structuralExterior,
    ctx,
  )

  // One accumulator per register, declared outside all the loops; its init is
  // loop-invariant, compiled at the exterior and floated out of the thunk.
  let floatedAcc: array<placed> = []
  let regPlans = regs->Array.map(reg => {
    let (init, step) = switch (reg.kind, stepOf(reg)) {
    | (DelayRead({init}), Some(step)) => (init, step)
    | _ => failwith("Codegen.emitRunningCollect: register lost its init/step after the support check")
    }
    let initC = compileValue(st, exterior, init)
    initC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    (reg, st.fresh(), initC.name, step)
  })

  // The any-list rule (lazy-compile-design.md), as everywhere else: any list
  // level ⇒ the view is a list (push per firing); an all-option / all-dispatch
  // scan is option-shaped (`let out;`, assigned on the firing that reaches it).
  let anyList = levels->Array.some(l =>
    switch l {
    | IterLevel({isList}) => isList
    | AltLevel(_) | PartialLevel(_) => false
    }
  )
  let outName = st.fresh()

  // The innermost payload, emitted once per innermost context the chain reaches
  // — once per covered cell where a partial level branches. `prev` is the
  // running value at the top of the body; the push carries the branch value
  // (which reads it); `reg = force(step)` advances at the bottom, so the pushed
  // value is the running total BEFORE this firing's step. Statements addressed
  // to this context are claimed here rather than floated into the level's
  // bucket, which keeps the `prev` decls ahead of everything that reads them.
  let mkPayload = (innerCtx: ctxPath) => {
    // Every `prev` is memoised before any step or the branch value compiles, so
    // a step (or another register's step) that reads `prev` resolves.
    let prevDecls = regPlans->Array.map(((reg, regName, _, _)) => {
      let prevName = st.fresh()
      recordMemo(st, reg.id, "prev", innerCtx, prevName)
      JsBuild.const(prevName, Runtime.lazyDoneOf(JsBuild.id(regName)))
    })
    let mine: array<JsAst.stmt> = []
    let rest: array<placed> = []
    let claim = (fl: array<placed>) =>
      fl->Array.forEach(pl =>
        if ctxPathKey(pl.at) === ctxPathKey(innerCtx) {
          Array.push(mine, pl.stmt)
        } else {
          Array.push(rest, pl)
        }
      )
    let regAssigns = regPlans->Array.map(((_, regName, _, step)) => {
      let stepC = compileValue(st, innerCtx, step)
      claim(stepC.floated)
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(regName), Runtime.forceOf(JsBuild.id(stepC.name))))
    })
    let valueC = compileValue(st, innerCtx, branch.value)
    claim(valueC.floated)
    let pushStmt = if anyList {
      JsBuild.exprStmt(
        JsBuild.call(JsBuild.member(JsBuild.id(outName), "push"), [Runtime.forceOf(JsBuild.id(valueC.name))]),
      )
    } else {
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(outName), Runtime.forceOf(JsBuild.id(valueC.name))))
    }
    (
      Array.concat(prevDecls, Array.concat(mine, Array.concat([pushStmt], regAssigns))),
      rest,
    )
  }

  // The level walk is `buildChain`, the same one the register's own fold walks,
  // so the view and the fold agree on which firings are kept — and on a partial
  // driving flow both the push and the advance sit inside the arm that fired.
  let (stmts, escaped) = buildChain(st, cn.id, exterior, levels, mkPayload)
  let escaped = Array.concat(floatedAcc, escaped)

  let accDecl = if anyList {
    JsBuild.const(outName, JsBuild.array_([]))
  } else {
    JsBuild.letDecl(outName)
  }
  let regDecls = regPlans->Array.map(((_, regName, initName, _)) =>
    JsBuild.let_(regName, Runtime.forceOf(JsBuild.id(initName)))
  )
  let thunkBody = Array.concat(
    Array.concat([accDecl], regDecls),
    Array.concat(stmts, [JsBuild.ret(JsBuild.id(outName))]),
  )

  let name = st.fresh()
  recordMemo(st, cn.id, "value", exterior, name)
  {
    name,
    floated: Array.concat(escaped, [{at: exterior, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}]),
  }
}

// The containment theorem, operationally (partial-collect-design.md, "The merged
// flow as parent scope"): inside cell `alt`, the merged value of a partial
// collect covering that cell IS that collect's own branch value for it — "the
// merged value is bound per arm (each arm binds the same name to its branch's
// value; exactly one arm runs)". Walks the whole chain of partial collects from
// `flow` down to the cell and pre-memoises each merged-value port at `ctx`,
// INNERMOST FIRST, so an outer merged value computed from an inner one resolves.
// Returns the statements that floated; a no-op when `flow` is a direct alt port.
and memoiseMergedValues = (st: state, ctx: ctxPath, flow: flowRef, alt: string): array<placed> =>
  switch flow {
  | FlowPort(n, _) =>
    switch n.kind {
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      | CasePartial(_) =>
        switch branches->Array.find(b =>
          switch branchCells(b.flow) {
          | Some((_, cs)) => cs->Array.includes(alt)
          | None => false
          }
        ) {
        | None =>
          failwith(
            "Codegen: partial collect node " ++
            Int.toString(n.id) ++
            " has no branch covering cell \"" ++
            alt ++
            "\" — the consuming collect's coverage should have witnessed this",
          )
        | Some(b) =>
          let inner = memoiseMergedValues(st, ctx, b.flow, alt)
          let c = compileValue(st, ctx, b.value)
          recordMemo(st, n.id, "value", ctx, c.name)
          Array.concat(inner, c.floated)
        }
      | CaseFull | IterCollect | Malformed(_) => []
      }
    | _ => []
    }
  }

// One self-contained thunk per case collect (multi-close independence):
// `const s = force(disc)(force(input)); let out;` then an exhaustive if-chain
// on `s.tag`, one arm per alt, ending in else-throw. Each arm pre-memoises the
// alt's payload port (split.id, alt) to a shared `const v = __lazyDone__(s.value)`
// binding at the alt's context, compiles the branch value there, and assigns
// `out`. Statements addressed to an alt body are bucketed into it; loop-
// invariant work (the discriminator extern, exterior-context bindings) floats
// out of the thunk. The discriminator is a wire forced at the call, like
// emitApp forces fn.
//
// Branches are keyed by CELL SETS, not by single alts: a branch's flow may be a
// partial collect's merged flow spanning several cells, so the covering collect
// of the design's HTTP program — two singletons and a pair — is this emitter,
// with the pair's arm-per-cell each binding the merged value ("the exhaustive
// case collect is not a sibling construct to the partial collect; it is the
// covering configuration of the same node"). Dispatch stays one arm per cell,
// which is what makes the per-arm merged-value binding fall out; the doc's
// alternative spelling (`s.tag === "ClientError" || s.tag === "ServerError"`,
// one arm for the pair) would need that binding hoisted and buys nothing.
and emitCaseCollect = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branches: array<collectBranch>,
): compiled => {
  let branch0 = branches->Array.getUnsafe(0)
  let split = switch branchCells(branch0.flow) {
  | Some((s, _)) => s
  | None =>
    failwith(
      "Codegen.emitCaseCollect: branch flow names no bundle cells — " ++
      "Check's coverage rule should have witnessed this",
    )
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
      switch branchCells(b.flow) {
      | Some((t, cs)) => t.id === split.id && cs->Array.includes(altName)
      | None => false
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
    let altCtx = Array.concat(exterior, [{flow: altFlow, thunkOf: cn.id, idxVar: None}])
    let payloadName = st.fresh()
    recordMemo(st, split.id, altName, altCtx, payloadName)
    // A merged-flow branch: bind every partial collect's merged value on the
    // path down to this cell, so the branch value (computed at the merged
    // context) resolves inside the arm.
    memoiseMergedValues(st, altCtx, branch.flow, altName)->Array.forEach(pl =>
      Array.push(floatedAcc, pl)
    )
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

// Walk a spine of iter (list/option) and case-alt dispatch levels
// outermost-in, building the per-level `filterPlan` and the statements to
// float. Each level opens its own body context (tagged with `ownerId`, the
// thunk that owns the emitted JS scope) and pre-memoises the binding its
// interior resolves — an iter level's element, a dispatch's alt payload.
// Feeds (an iter input, a split's discriminator + dispatched value) compile in
// the context built so far and float to where they belong. Shared by
// emitCellChain (the accumulator is a collect) and emitRegister (the
// accumulator is a register fold), so the alt-guard logic is written once.
and walkFilterLevels = (
  st: state,
  exterior: ctxPath,
  levels: array<level>,
  ownerId: int,
): (array<filterPlan>, array<placed>) => {
  let floatedAcc: array<placed> = []
  let plans: array<filterPlan> = []
  let parentCtx = ref(exterior)
  levels->Array.forEach(l =>
    switch l {
    | PartialLevel(_) =>
      failwith("Codegen.walkFilterLevels: PartialLevel — caller must guard it out")
    | IterLevel({uncollect, isList}) => {
        let input = switch uncollect.kind {
        | Uncollect({input}) => input
        | _ => failwith("Codegen.walkFilterLevels: IterLevel is not an Uncollect")
        }
        let own = FlowPort(uncollect, "flow")
        if !chainOpens(Context.flowContext(own), parentCtx.contents) {
          failwith(
            "Codegen: level " ++
            Int.toString(uncollect.id) ++
            " is not nesting-adjacent to the chain — Check's join-adjacency rule should have witnessed this",
          )
        }
        let feedC = compileValue(st, parentCtx.contents, input)
        feedC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let bodyCtx = Array.concat(parentCtx.contents, [{flow: own, thunkOf: ownerId, idxVar: None}])
        let iterVar = st.fresh()
        let elemName = st.fresh()
        recordMemo(st, uncollect.id, "element", bodyCtx, elemName)
        Array.push(plans, FIter({uncollect, isList, bodyCtx, feedName: feedC.name, iterVar, elemName}))
        parentCtx := bodyCtx
      }
    | AltLevel({split, alt}) => {
        let (discriminator, csInput) = switch split.kind {
        | Uncollect({flowKind: Case({discriminator}), input}) => (discriminator, input)
        | _ => failwith("Codegen.walkFilterLevels: alt level's node is not a case split — placement bug")
        }
        // The dispatched value and the discriminator compile in the context
        // built so far (`s = disc(input)` is recomputed per firing there); a
        // Lit discriminator floats out to the top level via emitLit.
        let inputC = compileValue(st, parentCtx.contents, csInput)
        inputC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let discC = compileValue(st, parentCtx.contents, discriminator)
        discC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
        let altFlow = FlowPort(split, alt)
        let altCtx = Array.concat(parentCtx.contents, [{flow: altFlow, thunkOf: ownerId, idxVar: None}])
        let payloadName = st.fresh()
        recordMemo(st, split.id, alt, altCtx, payloadName)
        let splitName = st.fresh()
        Array.push(
          plans,
          FAlt({split, alt, altCtx, splitName, discName: discC.name, inputName: inputC.name, payloadName}),
        )
        parentCtx := altCtx
      }
    }
  )
  (plans, floatedAcc)
}

// --- The cell chain: filter, partial collect, and everything between ---------
//
// One emitter for every `join` chain that DISPATCHES somewhere. Its levels are
// iter levels (list / option loops) and dispatch levels, interleaved in any
// order, at least one of which dispatches. One thunk = an accumulator, then the
// levels nested outermost-in:
//
//   - a list level loops (for-of); an option level is a defined-check (an absent
//     option skips its body, contributing nothing);
//   - a CASE-ALT level keeps one cell —
//
//       const s = force(disc)(force(input));
//       if (s.tag === alt) { const payload = __lazyDone__(s.value); … }
//
//   - a PARTIAL level keeps k cells, one arm each, additionally binding every
//     merged value on the path down to that cell (`memoiseMergedValues` — the
//     containment theorem, "each arm binds the same name to its branch's
//     value"). NON-exhaustive: an uncovered cell makes the merged flow not fire.
//
// The two dispatch levels are the same construct at two widths, which is why
// they share an emitter: a case-alt level is the all-singletons instance, and
// `partial-collect-design.md`'s three terminations (join-absorbed filter,
// collected alone, covering) differ only in the accumulator and in who owns the
// arms. The trailing case `join(list, case-alt)` is the plain filter; a
// NON-trailing dispatch (`join(join(list, case-alt), inner-list)`) is
// filter-then-flatmap, iterating the kept cell's payload; a partial level may be
// non-trailing too — `join(partial, inner-list)`, "for each error firing,
// iterate its details".
//
// Each level pre-memoises the binding its interior resolves (an iter element, a
// cell payload, a merged value) at that level's context; loop-invariant work
// floats out of the thunk. The any-list rule (lazy-compile-design.md) decides
// the accumulator — any list level ⇒ a list (push per kept firing), an all-
// option chain ⇒ an option (`let out;` assign, which is also the collected-alone
// reading of a merged flow).

// Assemble a level chain into the statements that belong in `exterior`'s scope,
// calling `mkPayload` at each innermost context the chain reaches.
//
// A PARTIAL level BRANCHES, and that is the one thing the flat plan-then-
// assemble walk could not express: every level after it — and the payload — is
// assembled once per covered cell, under that cell's own context and its own
// bindings. So the walk is recursive: levels up to the first partial go through
// the flat `walkFilterLevels`, the partial becomes a k-arm dispatch, and each
// arm recurses on the rest. A chain with no partial level recurses zero times
// and is exactly the flat walk it was before.
//
// Returns the statements to emit at `exterior`, plus the `placed` statements
// addressed to `exterior` or shallower, which the caller places (an arm claims
// those addressed to itself; the top-level caller floats them out of the thunk).
and buildChain = (
  st: state,
  ownerId: int,
  exterior: ctxPath,
  levels: array<level>,
  mkPayload: ctxPath => (array<JsAst.stmt>, array<placed>),
): (array<JsAst.stmt>, array<placed>) => {
  let partialAt = levels->Array.findIndex(l =>
    switch l {
    | PartialLevel(_) => true
    | IterLevel(_) | AltLevel(_) => false
    }
  )
  let pre = partialAt < 0 ? levels : levels->Array.slice(~start=0, ~end=partialAt)
  let (plans, floatedAcc) = walkFilterLevels(st, exterior, pre, ownerId)
  let innerCtx = switch plans->Array.get(Array.length(plans) - 1) {
  | Some(FIter({bodyCtx})) => bodyCtx
  | Some(FAlt({altCtx})) => altCtx
  | None => exterior
  }

  // One bucket per level body, plus one per dispatch arm below.
  let buckets: Map.t<string, array<JsAst.stmt>> = Map.make()
  plans->Array.forEach(p =>
    switch p {
    | FIter({bodyCtx}) => Map.set(buckets, ctxPathKey(bodyCtx), [])
    | FAlt({altCtx}) => Map.set(buckets, ctxPathKey(altCtx), [])
    }
  )

  // Compile everything that goes *inside* the innermost level first, so the
  // buckets are complete before any body is assembled. Either the payload
  // (no partial level) or the k arms, each carrying the rest of the chain.
  let armData = if partialAt < 0 {
    None
  } else {
    let (partialCollect, split, pbranches) = switch levels->Array.getUnsafe(partialAt) {
    | PartialLevel({collect, split, branches}) => (collect, split, branches)
    | IterLevel(_) | AltLevel(_) => failwith("Codegen.buildChain: partialAt is not a PartialLevel")
    }
    let (discriminator, csInput) = switch split.kind {
    | Uncollect({flowKind: Case({discriminator}), input}) => (discriminator, input)
    | _ =>
      failwith(
        "Codegen.buildChain: a partial level's split is not a case split — " ++
        "`spine` resolves it through `branchCells`, so this is a compiler bug",
      )
    }
    let cells = switch classifyCollect(pbranches) {
    | CasePartial(cs) => cs
    | _ => failwith("Codegen.buildChain: a partial level's collect is not partial")
    }
    let post = levels->Array.slice(~start=partialAt + 1, ~end=Array.length(levels))
    // The dispatched value and the discriminator compile in the context built so
    // far (`s = disc(input)` is recomputed per firing there).
    let inputC = compileValue(st, innerCtx, csInput)
    inputC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    let discC = compileValue(st, innerCtx, discriminator)
    discC.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    let splitName = st.fresh()
    let arms = cells->Array.map(cell => {
      let armCtx = Array.concat(
        innerCtx,
        [{flow: FlowPort(split, cell), thunkOf: ownerId, idxVar: None}],
      )
      Map.set(buckets, ctxPathKey(armCtx), [])
      let payloadName = st.fresh()
      recordMemo(st, split.id, cell, armCtx, payloadName)
      memoiseMergedValues(
        st,
        armCtx,
        FlowPort(partialCollect, "flow"),
        cell,
      )->Array.forEach(pl => Array.push(floatedAcc, pl))
      let (armStmts, armFloated) = buildChain(st, ownerId, armCtx, post, mkPayload)
      armFloated->Array.forEach(pl => Array.push(floatedAcc, pl))
      (cell, armCtx, payloadName, armStmts)
    })
    Some((splitName, discC.name, inputC.name, arms))
  }
  let payloadStmts = switch armData {
  | Some(_) => []
  | None => {
      let (stmts, fl) = mkPayload(innerCtx)
      fl->Array.forEach(pl => Array.push(floatedAcc, pl))
      stmts
    }
  }

  // Partition: each level body and each arm claims what is addressed to it;
  // everything at `exterior` or shallower goes back to the caller.
  let escaped: array<placed> = []
  floatedAcc->Array.forEach(pl =>
    switch Map.get(buckets, ctxPathKey(pl.at)) {
    | Some(bk) => Array.push(bk, pl.stmt)
    | None =>
      if isCtxPrefix(pl.at, exterior) {
        Array.push(escaped, pl)
      } else {
        failwith(
          "Codegen: a statement floated to a context unrelated to the chain " ++
          "being assembled — placement bug",
        )
      }
    }
  )

  // The innermost statements: the payload, or the k-arm cell dispatch built in
  // reverse — NON-exhaustive, no else, so an uncovered cell drops.
  let core = switch armData {
  | None => payloadStmts
  | Some((splitName, discName, inputName, arms)) => {
      let chain = ref(None)
      for i in Array.length(arms) - 1 downto 0 {
        let (cell, armCtx, payloadName, armStmts) = arms->Array.getUnsafe(i)
        let bucket = Map.get(buckets, ctxPathKey(armCtx))->Option.getOr([])
        let body = Array.concat(
          [
            JsBuild.const(
              payloadName,
              Runtime.lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")),
            ),
          ],
          Array.concat(bucket, armStmts),
        )
        chain :=
          Some(
            JsAst.SIf({
              test: JsBuild.eq(JsBuild.member(JsBuild.id(splitName), "tag"), JsBuild.str(cell)),
              cons: JsAst.SBlock(body),
              alt: chain.contents,
            }),
          )
      }
      Array.concat(
        [
          JsBuild.const(
            splitName,
            JsBuild.call(
              Runtime.forceOf(JsBuild.id(discName)),
              [Runtime.forceOf(JsBuild.id(inputName))],
            ),
          ),
        ],
        switch chain.contents {
        | Some(s) => [s]
        | None => []
        },
      )
    }
  }

  // Wrap in the walked levels, innermost-out.
  let nested = ref(core)
  for i in Array.length(plans) - 1 downto 0 {
    switch plans->Array.getUnsafe(i) {
    | FIter({isList, bodyCtx, feedName, iterVar, elemName}) => {
        let bucket = Map.get(buckets, ctxPathKey(bodyCtx))->Option.getOr([])
        let body = Array.concat(
          [JsBuild.const(elemName, Runtime.lazyDoneOf(JsBuild.id(iterVar)))],
          Array.concat(bucket, nested.contents),
        )
        nested :=
          if isList {
            [JsBuild.forOf(iterVar, Runtime.forceOf(JsBuild.id(feedName)), body)]
          } else {
            [
              JsBuild.const(iterVar, Runtime.forceOf(JsBuild.id(feedName))),
              JsBuild.if_(JsBuild.neq(JsBuild.id(iterVar), JsBuild.undefined), body),
            ]
          }
      }
    | FAlt({alt, altCtx, splitName, discName, inputName, payloadName}) => {
        let bucket = Map.get(buckets, ctxPathKey(altCtx))->Option.getOr([])
        let altBody = Array.concat(
          [
            JsBuild.const(
              payloadName,
              Runtime.lazyDoneOf(JsBuild.member(JsBuild.id(splitName), "value")),
            ),
          ],
          Array.concat(bucket, nested.contents),
        )
        nested := [
          JsBuild.const(
            splitName,
            JsBuild.call(
              Runtime.forceOf(JsBuild.id(discName)),
              [Runtime.forceOf(JsBuild.id(inputName))],
            ),
          ),
          JsBuild.if_(
            JsBuild.eq(JsBuild.member(JsBuild.id(splitName), "tag"), JsBuild.str(alt)),
            altBody,
          ),
        ]
      }
    }
  }
  (nested.contents, escaped)
}

// The thunk around a cell chain: the accumulator, the nested levels, the return.
and emitCellChain = (
  st: state,
  ctx: ctxPath,
  cn: node,
  branch: collectBranch,
  levels: array<level>,
): compiled => {
  if (
    !(
      levels->Array.some(l =>
        switch l {
        | AltLevel(_) | PartialLevel(_) => true
        | IterLevel(_) => false
        }
      )
    )
  ) {
    failwith("Codegen.emitCellChain: no dispatch level — routed to emitIterCollect upstream")
  }
  // The any-list rule (lazy-compile-design.md): any list level ⇒ a list output
  // (push per kept firing); an all-option chain ⇒ an option output (`let out;`
  // assigned only when every option fires and a covered cell matches).
  let anyList = levels->Array.some(l =>
    switch l {
    | IterLevel({isList}) => isList
    | AltLevel(_) | PartialLevel(_) => false
    }
  )
  let exterior = instantiate(
    ~what="Cell chain collect node " ++ Int.toString(cn.id),
    Context.flowContext(branch.flow),
    ctx,
  )
  let outName = st.fresh()
  // Compiled once per innermost context the chain reaches — once per covered
  // cell where a partial level branches (code duplicated, evaluation still once:
  // exactly one arm runs).
  let mkPayload = (innerCtx: ctxPath) => {
    let valueC = compileValue(st, innerCtx, branch.value)
    let action = if anyList {
      JsBuild.exprStmt(
        JsBuild.call(
          JsBuild.member(JsBuild.id(outName), "push"),
          [Runtime.forceOf(JsBuild.id(valueC.name))],
        ),
      )
    } else {
      JsBuild.exprStmt(JsBuild.assign(JsBuild.id(outName), Runtime.forceOf(JsBuild.id(valueC.name))))
    }
    ([action], valueC.floated)
  }
  let (stmts, escaped) = buildChain(st, cn.id, exterior, levels, mkPayload)
  let accDecl = if anyList {
    JsBuild.const(outName, JsBuild.array_([]))
  } else {
    JsBuild.letDecl(outName)
  }
  let thunkBody = Array.concat([accDecl], Array.concat(stmts, [JsBuild.ret(JsBuild.id(outName))]))
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
// innermost element to `__lazyDone__(x)`, both inside the loop body, so the step
// subtree re-runs each iteration (a register is the one place laziness must NOT
// cache across firings — the bindings live in the body, never hoisted).
//
// The driving flow may be a single uncollect OR a **flattened (joined) sequence**
// (`spine` = several list/option levels, e.g. a running sum over a list-of-lists):
// the levels nest as loops and the ONE accumulator lives outside them all, so a
// join folds the whole flattened firing order into one register (the fork
// dissolves on sequences — iteration-with-state / delay-ontology). The levels
// may also include a case-alt **dispatch** — a register over a FILTERED
// sequence (`join(list, case-alt)`): the register walks the Some-subsequence,
// advancing only on the firings whose alt matches (delay-ontology-design.md,
// route (b) "filter inside": the Delay's flow is the kept subsequence, so the
// register "only updates when the option is Some"). The dispatch may equally be
// a PARTIAL level — a merged flow of k cells — which is the same construct at
// width k: the kept subsequence is the firings landing in any covered cell, and
// `OrderDemand.orderOf` already reads a merged flow's order as "the parent's,
// restricted". The whole skeleton is therefore `buildChain`, the same recursive
// level walk emitCellChain assembles: the k arms each carry their own copy of
// the step subtree (exactly one runs per firing), the merged value resolving in
// each arm by the containment theorem, while the ONE `let reg` lives outside
// every loop, guard, and arm. Still Todo: a register over a genuine PRODUCT (a
// grid — `spine` raises on a Cross before reaching here; ill-formed for the
// ordinary reason, which Check's order-demand rule witnesses first).
and emitRegister = (st: state, ctx: ctxPath, wn: node, read: node, step: valueRef): compiled => {
  let (flow, init) = switch read.kind {
  | DelayRead({flow, init}) => (flow, init)
  | _ =>
    failwith("Codegen.emitRegister: DelayWrite's read is not a DelayRead — Check should have witnessed this")
  }
  // Normally the driving flow's exterior. For a register folding along ONE axis
  // of a product, `Context.valueContext` reports the surviving (fibering) axis
  // instead, so the loop is emitted INSIDE the holding loop and runs once per
  // fiber — "reduce along an axis, fibered over the rest"
  // (product-flows-design.md): state never crosses axes, so this is the ordinary
  // register with the other axis as its surrounding context.
  let exterior = instantiate(
    ~what="Register final, node " ++ Int.toString(wn.id),
    Context.valueContext(ValuePort(wn, "final")),
    ctx,
  )
  // Iter (list/option) levels loop; a case-alt level guards one cell and a
  // partial level k of them. A Cross/Commute already raised in `spine`.
  let levels = spine(flow)

  // init is loop-invariant — compiled at the exterior, floats out of the thunk.
  let initC = compileValue(st, exterior, init)
  let regName = st.fresh()

  // The innermost payload, emitted once per innermost context the chain reaches
  // — once per covered cell where a partial level branches (code duplicated,
  // evaluation still once: exactly one arm runs per firing). `prev` is declared
  // FIRST, so the step subtree's own per-firing bindings (which read it) follow
  // it in the body; hence this claims the statements addressed to its own
  // context instead of floating them into the level's bucket, which is emitted
  // ahead of the payload.
  let mkPayload = (innerCtx: ctxPath) => {
    let prevName = st.fresh()
    recordMemo(st, read.id, "prev", innerCtx, prevName)
    let stepC = compileValue(st, innerCtx, step)
    let mine: array<JsAst.stmt> = []
    let rest: array<placed> = []
    stepC.floated->Array.forEach(pl =>
      if ctxPathKey(pl.at) === ctxPathKey(innerCtx) {
        Array.push(mine, pl.stmt)
      } else {
        Array.push(rest, pl)
      }
    )
    let stmts = Array.concat(
      [JsBuild.const(prevName, Runtime.lazyDoneOf(JsBuild.id(regName)))],
      Array.concat(
        mine,
        [JsBuild.exprStmt(JsBuild.assign(JsBuild.id(regName), Runtime.forceOf(JsBuild.id(stepC.name))))],
      ),
    )
    (stmts, rest)
  }

  // The level walk is `buildChain`, shared with emitCellChain: iter levels nest
  // as loops, dispatch levels as guards, and a partial level branches (each arm
  // re-assembling everything below it under that cell's own context). The one
  // `let reg` lives at the thunk top, outside all of them.
  let (stmts, escaped) = buildChain(st, wn.id, exterior, levels, mkPayload)
  let thunkBody = Array.concat(
    [JsBuild.let_(regName, Runtime.forceOf(JsBuild.id(initC.name)))],
    Array.concat(stmts, [JsBuild.ret(JsBuild.id(regName))]),
  )
  let escaped = Array.concat(initC.floated, escaped)

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
    let segs = p.axes->Array.map(a => {flow: a.flow, thunkOf: p.crossId, idxVar: None})
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

    // Assemble the n-dimensional cube innermost-out. Each axis j contributes a
    // level: the outer levels accumulate rows, the innermost pushes force(val).
    // `product-flows-design.md`, N-ary: "The table indexing generalises verbatim
    // … a point-indexed structure, one entry per point" — the two-axis nested
    // for-of becomes n nested index-loops over the same shape.
    let n = Array.length(p.axes)
    let tName = st.fresh()
    let bucketFor = (i: int): array<JsAst.stmt> =>
      Map.get(buckets, ctxPathKey(segs->Array.slice(~start=0, ~end=i + 1)))->Option.getOr([])
    // buildLevel(j, accName): the loop over axis j, pushing into `accName`. At the
    // innermost axis it pushes the computed value; otherwise it opens a fresh row,
    // builds the next axis into it, and pushes that row.
    let rec buildLevel = (j: int, accName: string): JsAst.stmt => {
      let aj = arrNames->Array.getUnsafe(j)
      let ij = idxVars->Array.getUnsafe(j)
      let ej = elemNames->Array.getUnsafe(j)
      let head = Array.concat(
        [JsBuild.const(ej, Runtime.lazyDoneOf(JsBuild.index(JsBuild.id(aj), JsBuild.id(ij))))],
        bucketFor(j),
      )
      let tail = if j === n - 1 {
        [
          JsBuild.exprStmt(
            JsBuild.call(JsBuild.member(JsBuild.id(accName), "push"), [Runtime.forceOf(JsBuild.id(valC.name))]),
          ),
        ]
      } else {
        let childAcc = st.fresh()
        [
          JsBuild.const(childAcc, JsBuild.array_([])),
          buildLevel(j + 1, childAcc),
          JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(accName), "push"), [JsBuild.id(childAcc)])),
        ]
      }
      cForArr(ij, aj, Array.concat(head, tail))
    }
    let thunkBody = Array.concat(
      Array.concat(
        feedCs->Array.mapWithIndex((c, j) =>
          JsBuild.const(arrNames->Array.getUnsafe(j), Runtime.forceOf(JsBuild.id(c.name)))
        ),
        [JsBuild.const(tName, JsBuild.array_([])), buildLevel(0, tName)],
      ),
      [JsBuild.ret(JsBuild.id(tName))],
    )

    let tableName = st.fresh()
    Map.set(st.tableMemo, tkey, tableName)
    (
      tableName,
      Array.concat(escaped, [{at: [], stmt: JsBuild.const(tableName, Runtime.lazyOf(thunkBody))}]),
    )
  }
}

// A product-consumer chain: k nested collects reading one shared table in a
// chosen order (product-flows-design.md, "each consumer traverses the shared
// table in its own order"). Every axis is traversed by index, so all k! readings
// of the product index the same point-indexed table — the transpose (and, at
// rank 3+, every permutation) is free. Output is k-deep nested lists (the
// any-list rule: k list axes ⇒ k nesting levels).
and emitProductChain = (st: state, ctx: ctxPath, cn: node, m: productMatch): compiled =>
  emitTableTraversal(
    st,
    ~place=ctx,
    ~cn,
    ~p=m.product,
    ~chainAxes=m.chainAxes,
    ~held=[],
    ~sVal=m.sVal,
  )

// A partial product traversal: the same table read, but over only SOME of the
// product's axes — the rest are HELD by enclosing indexed loops, so the result is
// one value per point of them ("reduce along an axis, fibered over the rest",
// product-flows-design.md). The held coordinates come from the enclosing loops'
// index variables, which is the whole difference from the full chain: the
// traversal, the table, and its once-per-point computation are shared.
and emitPartialProductChain = (st: state, cn: node, m: partialProductMatch): compiled =>
  emitTableTraversal(
    st,
    ~place=m.pPlaceCtx,
    ~cn,
    ~p=m.pProduct,
    ~chainAxes=m.pChainAxes,
    ~held=m.pHeld,
    ~sVal=m.pSVal,
  )

and emitTableTraversal = (
  st: state,
  ~place: ctxPath,
  ~cn: node,
  ~p: product,
  ~chainAxes: array<productAxis>,
  ~held: array<(productAxis, string)>,
  ~sVal: valueRef,
): compiled => {
  let floatedAcc: array<placed> = []
  let (tableName, tableFloated) = getOrBuildTable(st, p, sVal)
  tableFloated->Array.forEach(pl => Array.push(floatedAcc, pl))

  let k = Array.length(chainAxes)
  // The consumer's per-axis feeds, in traversal order — the same list sources,
  // memo-shared with the table build, so they compile once.
  let feedCs = chainAxes->Array.map(a => {
    let c = compileValue(st, place, a.feed)
    c.floated->Array.forEach(pl => Array.push(floatedAcc, pl))
    c
  })
  let idxVars = chainAxes->Array.map(_ => st.fresh())
  let arrNames = chainAxes->Array.map(_ => st.fresh())
  let tbl = st.fresh()

  // Index the table in its STORED orientation: each stored product axis is
  // indexed by whichever chain loop iterates it — or, for a held axis, by the
  // enclosing loop's index (so this chain's order, and its fibering, are just a
  // different indexing of the one shared table).
  let indexFor = (a: productAxis): JsAst.expr => {
    let j = chainAxes->Array.findIndex(ca => ca.axisKey === a.axisKey)
    if j >= 0 {
      JsBuild.id(idxVars->Array.getUnsafe(j))
    } else {
      switch held->Array.find(((ha, _)) => ha.axisKey === a.axisKey) {
      | Some((_, iv)) => JsBuild.id(iv)
      | None =>
        failwith(
          "Codegen: product axis neither collected nor held — matchPartialProductChain bug",
        )
      }
    }
  }
  let lookup = p.axes->Array.reduce(JsBuild.id(tbl), (acc, a) => JsBuild.index(acc, indexFor(a)))

  // buildLevel(j, accName): the loop over chain axis j, pushing into `accName` —
  // the table lookup at the innermost level, an accumulated row otherwise.
  let rec buildLevel = (j: int, accName: string): JsAst.stmt => {
    let aj = arrNames->Array.getUnsafe(j)
    let ij = idxVars->Array.getUnsafe(j)
    let body = if j === k - 1 {
      [JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(accName), "push"), [lookup]))]
    } else {
      let childAcc = st.fresh()
      [
        JsBuild.const(childAcc, JsBuild.array_([])),
        buildLevel(j + 1, childAcc),
        JsBuild.exprStmt(JsBuild.call(JsBuild.member(JsBuild.id(accName), "push"), [JsBuild.id(childAcc)])),
      ]
    }
    cForArr(ij, aj, body)
  }

  let outName = st.fresh()
  let thunkBody = Array.concat(
    Array.concat(
      [JsBuild.const(tbl, Runtime.forceOf(JsBuild.id(tableName)))],
      feedCs->Array.mapWithIndex((c, j) =>
        JsBuild.const(arrNames->Array.getUnsafe(j), Runtime.forceOf(JsBuild.id(c.name)))
      ),
    ),
    [JsBuild.const(outName, JsBuild.array_([])), buildLevel(0, outName), JsBuild.ret(JsBuild.id(outName))],
  )

  let name = st.fresh()
  recordMemo(st, cn.id, "value", place, name)
  {
    name,
    floated: Array.concat(
      floatedAcc,
      [{at: place, stmt: JsBuild.const(name, Runtime.lazyOf(thunkBody))}],
    ),
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
  // compiles once — single-module multi-output compilation.
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
