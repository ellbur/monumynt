// Context paths — the ordered stack of flows a value lives under.
//
// This is bundle-provenance-design.md's context path, computed structurally
// (root outward; one segment per flow layer). It is the shared substrate
// for three consumers:
//
//   - Check: flow-context alignment (combining values from incomparable
//     contexts is the time-travel / bundle-mixing clash).
//   - Annotate: the flow-variable set handed to codegen (the
//     generalisation of the `deeper` placement rule).
//   - TextResolve: seeding a chain's implicit flow stack from a named
//     value's context.
//
// v0 limitations, deliberate:
//   - Merging is by prefix rule only: of two contexts one must be a prefix
//     of the other. Incomparable contexts raise `Incomparable` — genuinely
//     incomparable-but-meaningful combinations are the product case, which
//     lands with the Cross compile (compile-strategy-design.md, "a node
//     reached in two contexts"); until then the raise IS the (blunt)
//     alignment check.
//   - Case-alt segments: an alt *value* port's context gets the alt flow as
//     its innermost segment. That is what lets Check classify an incomparable
//     merge: two divergent segments on the *same* case node are sibling cells
//     (bundle mixing); the `Incomparable` payload carries the paths so the
//     classifier can see this. A bundle step is now a cell SET (`cellSet`
//     below), so a merged flow's step compares by containment — the remaining
//     cell-set gap is partial OVERLAP (`{A,B}` vs `{B,C}`, which meets at
//     `{B}` as an inferred incorporate), still the poset round's.
//   - No memoisation yet; programs are test-sized. When Annotate becomes a
//     real pass it should compute these once per (node, port) and hand them
//     down, per the pipeline discipline.

open Program

// Carries the two offending context PATHS (not just their rendering) so the
// alignment check can classify the clash — walk to the last common context and
// look at the first divergent pair of steps (bundle-provenance-design.md, "one
// check, two clash flavors"). `where` names the combining node.
exception Incomparable({left: array<flowRef>, right: array<flowRef>, where: string})

let flowKey = (f: flowRef): string =>
  switch f {
  | FlowPort(n, port) => Int.toString(n.id) ++ ":" ++ port
  }

let contextToString = (ctx: array<flowRef>): string =>
  "[" ++ ctx->Array.map(flowKey)->Array.join(" > ") ++ "]"

// --- Cell sets (bundle-provenance-design.md, "Sketch: merged branches as cell
//     sets"; partial-collect-design.md, "The merged flow as parent scope") -----
//
// A bundle step in a context path is not always a single cell. A case-alt flow
// is the singleton `{A}`; a partial collect's merged flow spans the UNION of its
// branches' cells, `{A, B}`. The set is computed by WALKING, never stored
// (partial-collect-design.md, "the cell set is computed by walking"), and only
// cells the program actually engaged ever appear — the full inventory lives on
// the Open node, not in any path.
//
// `None` for a flow that is not a bundle step at all (a list/option axis, a
// join, a product): those steps compare by identity exactly as before.
//
// The walk itself is `Program.branchCells` (the one the coverage classification
// reads); here the cells are keyed as alt FLOW keys, so two bundles with
// same-named alts never compare equal.
let cellSet = (f: flowRef): option<array<string>> =>
  branchCells(f)->Option.map(((split, cells)) =>
    cells->Array.map(c => flowKey(FlowPort(split, c)))
  )

// The containment theorem (partial-collect-design.md, "The merged flow as parent
// scope"): a value borne on a bundle step with cell set S is available inside any
// step whose cell set is a SUBSET of S — `{A} ⊆ {A, B}`, so a merged value is
// directly usable inside either of its constituent cells, by the same rule that
// lets a root-context value into any cell. No capture node, no scope
// declaration: "parent scope" is subset order doing what it always did.
//
// The relation is strictly one-directional. It never moves a value OUT of a
// constituent — getting a value to the merged context from inside cells is
// exactly what the partial collect's value threading is for, and coarsening
// happens only at that explicit node.
//
// Sibling cells (`{A}` vs `{B}`) contain each other in neither direction, so
// bundle mixing is untouched. Partial OVERLAP (`{A,B}` vs `{B,C}`) is likewise
// not containment: that combination lives at the meet `{B}` as an inferred
// incorporate (bundle-provenance-design.md, "Revision: overlap is incorporate,
// not a clash"), which is still the poset round's.
let cellContains = (outer: flowRef, inner: flowRef): bool =>
  switch (cellSet(outer), cellSet(inner)) {
  | (Some(o), Some(i)) => i->Array.every(c => o->Array.includes(c))
  | _ => false
  }

// A path step is matched either by identity or by cell containment: the step the
// value asks for is available at the step the context actually opens.
let stepAvailableAt = (required: flowRef, open_: flowRef): bool =>
  flowKey(required) === flowKey(open_) || cellContains(required, open_)

let isPrefix = (shorter: array<flowRef>, longer: array<flowRef>): bool => {
  Array.length(shorter) <= Array.length(longer) &&
  shorter->Array.everyWithIndex((f, i) =>
    switch longer[i] {
    | Some(g) => stepAvailableAt(f, g)
    | None => false
    }
  )
}

// The MEET of two bundle steps (bundle-provenance-design.md, "Revision: overlap
// is incorporate, not a clash"): two values on partially overlapping cell sets —
// `{A, B}` and `{B, C}` — DO combine, at `{A,B} ∩ {B,C} = {B}`, "the greatest
// cell set contained in both, the intersection in the subset lattice, and it is
// *unique*". Only a DISJOINT meet is bundle mixing.
//
// The meet has to be a set the program CONSTRUCTED, exactly as a sibling
// combine's home has to be a constructed product (`Poset.merge`, "an
// under-determined cross is just another time-travel program"). A SINGLE cell
// always is — the split's own alt flow port, engaged by both merges — and that
// is the case resolved here. A wider meet would need a partial collect the
// program actually built spanning those cells, which no local walk can find, so
// it stays `Incomparable` and `Check` reports it by name.
let cellMeetStep = (l: flowRef, r: flowRef): option<flowRef> =>
  switch (branchCells(l), branchCells(r)) {
  | (Some((sa, ca)), Some((sb, cb))) if sa.id === sb.id =>
    switch ca->Array.filter(c => cb->Array.includes(c)) {
    | [one] => Some(FlowPort(sa, one))
    | _ => None // disjoint (bundle mixing) or a wider, unconstructed meet
    }
  | _ => None
  }

// Two paths of the same depth combined step by step: the narrower step wins
// where one is available at the other, and a partial cell overlap descends to
// its meet. `None` when any step pair has no common home.
let meetPath = (a: array<flowRef>, b: array<flowRef>): option<array<flowRef>> =>
  if Array.length(a) !== Array.length(b) {
    None
  } else {
    let out: array<flowRef> = []
    let ok = ref(true)
    a->Array.forEachWithIndex((l, i) =>
      switch b[i] {
      | Some(r) =>
        if stepAvailableAt(l, r) {
          Array.push(out, r)
        } else if stepAvailableAt(r, l) {
          Array.push(out, l)
        } else {
          switch cellMeetStep(l, r) {
          | Some(m) => Array.push(out, m)
          | None => ok := false
          }
        }
      | None => ok := false
      }
    )
    ok.contents ? Some(out) : None
  }

// Prefix-rule merge: the deeper context wins if the other is its prefix; failing
// that, two equally deep contexts meet if every step pair has a common home (the
// cell meet above). Otherwise incomparable.
let merge = (~where: string, a: array<flowRef>, b: array<flowRef>): array<flowRef> =>
  if isPrefix(a, b) {
    b
  } else if isPrefix(b, a) {
    a
  } else {
    switch meetPath(a, b) {
    | Some(m) => m
    | None => throw(Incomparable({left: a, right: b, where}))
    }
  }

// --- Poset wiring (product-flows-design.md, "The context model") -------------
//
// The linear path model above is the all-nesting (all-Series) special case of
// the series-parallel poset (Poset.res). A Cross constructs a PRODUCT context —
// two sibling axes with no order between them — which no linear path can hold.
// These functions lift the linear machinery to the poset for exactly the one
// question the alignment check asks of a sibling combine: does a constructed
// Cross give it a home? (`crossProduct` is defined below `flowContext`, since it
// needs the operands' exteriors.)

// A linear context path is a chain: outer axes first, keyed by flowKey.
let pathToPoset = (path: array<flowRef>): Poset.t =>
  Poset.series(path->Array.map(f => Poset.Axis(flowKey(f))))

// --- Flow-variable sets (as flow refs) ---------------------------------------
//
// The invariance fact of product-flows-design.md ("smallest first step" 1):
// per-flow sets of the uncollect axes a flow ranges over vs the axes that
// determine its firing STRUCTURE. `Annotate` re-exports these as key sets (its
// `introducedAxes` / `sourceAxes` / `axesOf` / `valueAxes`); they live HERE, and
// return flow REFS rather than keys, because `valueContext` needs to *name* the
// axes a collect's branch value varies over but does not iterate — the fibering
// axes of a partial product traversal, below.
//
// Unlike the context paths these NEVER merge — they union raw axes, order- and
// comparability-free — so they are defined even where `merge` would raise
// Incomparable. That is exactly the sibling case Cross exists to combine: the
// invariance demand has to be answerable on two incomparable flows.
//
// Precise for the shapes the demand actually inspects — list/option uncollects
// (possibly nested), case splits, and the values built over them. The
// compositional kinds (Join/Cross/Commute operands) are unioned conservatively:
// an over-approximation can only over-report a dependence.

let dedupFlows = (fs: array<flowRef>): array<flowRef> => {
  let out: array<flowRef> = []
  fs->Array.forEach(f =>
    if !(out->Array.some(g => flowKey(g) === flowKey(f))) {
      Array.push(out, f)
    }
  )
  out
}

let rec introducedAxisFlows = (f: flowRef): array<flowRef> =>
  switch f {
  | FlowPort(n, _) =>
    switch n.kind {
    | Uncollect(_) => [f]
    | Join({outer, inner}) => Array.concat(introducedAxisFlows(outer), introducedAxisFlows(inner))
    | Cross({left, right}) => Array.concat(introducedAxisFlows(left), introducedAxisFlows(right))
    | Commute({outer, inner}) =>
      Array.concat(introducedAxisFlows(outer), introducedAxisFlows(inner))
    | Collect(_) => [f] // a partial collect's merged flow: its own option axis
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) => []
    }
  }

and sourceAxisFlows = (f: flowRef): array<flowRef> =>
  switch f {
  | FlowPort(n, _) =>
    switch n.kind {
    | Uncollect({input, nesting}) =>
      let fromInput = valueAxisFlows(input)
      switch nesting {
      | Some(outer) => Array.concat(fromInput, axisFlows(outer))
      | None => fromInput
      }
    | Join({outer, inner}) => Array.concat(axisFlows(outer), sourceAxisFlows(inner))
    | Cross({left, right}) => Array.concat(axisFlows(left), axisFlows(right))
    | Commute({outer, inner}) => Array.concat(axisFlows(outer), sourceAxisFlows(inner))
    | Collect({branches}) =>
      switch branches[0] {
      | Some({flow}) => sourceAxisFlows(flow) // the merged cells' exterior
      | None => []
      }
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) => []
    }
  }

// Every axis a flow touches: what it ranges over plus what determines it.
and axisFlows = (f: flowRef): array<flowRef> =>
  Array.concat(sourceAxisFlows(f), introducedAxisFlows(f))

and valueAxisFlows = (v: valueRef): array<flowRef> =>
  switch v {
  | ValuePort(n, port) =>
    switch n.kind {
    | Lit(_) => []
    | App({fn, args}) =>
      args->Array.reduce(valueAxisFlows(fn), (acc, a) => Array.concat(acc, valueAxisFlows(a)))
    | Uncollect({flowKind}) =>
      // element (list/option) or an alt payload (case): varies over its own
      // flow's axis and everything determining that flow.
      let ownFlow = switch flowKind {
      | List | Option => FlowPort(n, "flow")
      | Case(_) => FlowPort(n, port)
      }
      axisFlows(ownFlow)
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      // A partial collect's value is the merged (option-borne) value.
      | CasePartial(_) => axisFlows(FlowPort(n, "flow"))
      // A full collect's value is the result at the flow's exterior — the
      // iterated axis is gone, only its source survives — PLUS any axis the
      // branch value varies over that the collect does not iterate (a partial
      // product traversal: collecting one axis of a product leaves the others
      // standing, so the result is one value per point of them).
      | _ =>
        let base = switch branches[0] {
        | Some({flow}) => sourceAxisFlows(flow)
        | None => []
        }
        branches->Array.reduce(base, (acc, b) =>
          Array.concat(acc, collectRemainderFlows(b.flow, b.value))
        )
      }
    | Join(_) | Commute(_) | Cross(_) => [] // no value ports
    | DelayRead({flow}) => axisFlows(flow)
    | DelayWrite({read, step}) =>
      switch read.kind {
      // The iterated axis is folded away; its source survives — plus any axis
      // the step varies over that the driving flow does not supply (the fiber
      // a register-along-one-axis-of-a-product leaves standing).
      | DelayRead({flow}) =>
        Array.concat(sourceAxisFlows(flow), collectRemainderFlows(flow, step))
      | _ => []
      }
    | Aggregate({fields}) =>
      fields->Array.reduce([], (acc, (_, v)) => Array.concat(acc, valueAxisFlows(v)))
    | Disaggregate({struct_}) => valueAxisFlows(struct_)
    }
  }

// The axes a collect branch's value varies over that the branch's flow neither
// iterates (introduced) nor is determined by (source) — the fibering axes that
// SURVIVE the collect. Empty for every ordinary collect; non-empty exactly when
// the branch value spans a sibling axis of a product the collect does not
// traverse (product-flows-design.md, "reduce along an axis, fibered over the
// rest").
and collectRemainderFlows = (flow: flowRef, value: valueRef): array<flowRef> => {
  let excluded = Array.concat(introducedAxisFlows(flow), sourceAxisFlows(flow))
  // "Supplied by the flow" is availability, not identity: a value borne on a
  // merged `{A, B}` is supplied by a collect that iterates the single cell `{A}`,
  // since `{A} ⊆ {A, B}` (the containment theorem). `stepAvailableAt` is key
  // equality plus that containment, so this is the identity test it generalises.
  dedupFlows(valueAxisFlows(value))->Array.filter(g =>
    !(excluded->Array.some(e => stepAvailableAt(g, e)))
  )
}

let rec valueContext = (r: valueRef): array<flowRef> =>
  switch r {
  | ValuePort(n, port) =>
    switch n.kind {
    | Lit(_) => []
    | App({fn, args}) =>
      let where = "App node " ++ Int.toString(n.id)
      args->Array.reduce(valueContext(fn), (acc, a) =>
        merge(~where, acc, valueContext(a))
      )
    | Uncollect({flowKind}) =>
      // "element" (list/option) or an alt payload (case): per-iteration —
      // the exterior context plus this node's own flow layer.
      let ownFlow = switch flowKind {
      | List | Option => FlowPort(n, "flow")
      | Case(_) => FlowPort(n, port) // the alt's flow
      }
      Array.concat(flowContext(ownFlow), [ownFlow])
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      | CasePartial(_) =>
        // A partial collect's value is the MERGED value — per-firing of the
        // collect's own merged flow (option-kind relative to the parent), not
        // a result at the exterior. So it is flow-borne on that merged flow.
        // (A full collect's value, below, is the result at the exterior.)
        let merged = FlowPort(n, "flow")
        Array.concat(flowContext(merged), [merged])
      | _ =>
        switch branches[0] {
        | None => []
        | Some({flow, value}) =>
          // Normally a full collect's value is the result at the flow's
          // exterior. But a collect whose branch value varies over an axis it
          // does NOT iterate does not return a value there: that axis survives,
          // one result per point of it — product-flows-design.md's "a collect
          // over a crossed axis reports {Y}". Where SEVERAL axes survive (a
          // rank-3 product collected over one axis leaves `{Y, Z}` standing)
          // the surviving context is a genuine product, and this linear path
          // is its *flattening*: see `remainderPath`.
          remainderPath(flow, value)
        }
      }
    | Join(_) | Commute(_) | Cross(_) =>
      failwith("Context.valueContext: flow-only node has no value ports")
    | DelayRead({flow}) =>
      // `prev` is available at each firing of the driving flow. For a plain
      // uncollect that firing point is the element's own layer; for a JOINED
      // (flattened) driving flow it is the join's INTERIOR — the innermost
      // element depth — so `prev` aligns with the element the step combines it
      // with (a register over a flattened sequence, iteration-with-state /
      // delay-ontology "the fork dissolves on sequences"). `flowInterior`
      // collapses to `flowContext(flow) ++ [flow]` for a non-join flow, so the
      // single-level register is unchanged.
      flowInterior(flow)
    | DelayWrite({read, step}) =>
      switch read.kind {
      | DelayRead({flow}) =>
        // `final` is the accumulator after the driving flow completes — at the
        // flow's exterior. But a register whose STEP varies over axes the
        // driving flow neither iterates nor sources folds per FIBER of those
        // axes (product-flows-design.md, "reduce along an axis, fibered over the
        // rest": state never crosses axes, so there is one final per point of
        // the surviving fiber). Same report as the collect above.
        remainderPath(flow, step)
      | _ => failwith("Context.valueContext: DelayWrite whose read is not a DelayRead")
      }
    | Aggregate({fields}) =>
      // A struct lives where its fields jointly live — the same prefix-rule
      // merge an App does over its arguments.
      let where = "Aggregate node " ++ Int.toString(n.id)
      fields->Array.reduce([], (acc, (_, v)) => merge(~where, acc, valueContext(v)))
    | Disaggregate({struct_}) => valueContext(struct_)
    }
  }

// The context in which a flow itself was opened (its exterior).
and flowContext = (r: flowRef): array<flowRef> =>
  switch r {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({input, nesting}) =>
      let fromInput = valueContext(input)
      switch nesting {
      | Some(outer) =>
        merge(
          ~where="Uncollect nesting, node " ++ Int.toString(n.id),
          fromInput,
          Array.concat(flowContext(outer), [outer]),
        )
      | None => fromInput
      }
    | Join({outer}) => flowContext(outer)
    | Commute({outer, inner}) =>
      // After the swap the ex-inner is outermost. Exterior of the pair is
      // the ex-outer's exterior.
      switch port {
      | "outer" => flowContext(outer)
      | "inner" => Array.concat(flowContext(outer), [FlowPort(n, "outer")])
      | _ => {
          let _ = inner
          failwith("Context.flowContext: unknown Commute port " ++ port)
        }
      }
    | Cross({left, right}) =>
      // Exterior of a product: the common prefix of the operands'
      // exteriors. v0: require one to be a prefix of the other.
      merge(
        ~where="Cross node " ++ Int.toString(n.id),
        flowContext(left),
        flowContext(right),
      )
    | Collect({branches}) =>
      // Partial collect's merged flow: lives where the split's parent does.
      switch branches[0] {
      | Some({flow}) =>
        switch flow {
        | FlowPort(split, _) =>
          switch split.kind {
          | Uncollect({input}) => valueContext(input)
          | _ => flowContext(flow)
          }
        }
      | None => []
      }
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) =>
      failwith(
        "Context.flowContext: node kind " ++
        kindName(n.kind) ++ " has no flow ports (ref to port " ++ port ++ ")",
      )
    }
  }

// The context report for a collect (or a register's `final`) whose branch value
// varies over axes its flow does not supply: the SURVIVING axes, each with its
// own exterior, as one path — product-flows-design.md's "a collect over a
// crossed axis reports {Y}", generalised to the whole remainder.
//
// With one surviving axis the report is exact: the fiber is a single layer and a
// linear path holds it. With several — a rank-3 product collected over one axis
// leaves `{Y, Z}` — the true context is a PRODUCT, which no linear path can
// hold, and this path is its flattening in the combine's own operand order (the
// order `valueAxisFlows` walks, the same fact `Complete` reads when it mints a
// product's stored orientation — a property of the wiring, not of node ids).
// Consumers must therefore read a multi-axis report as the SET of axes that must
// be open, not as a nesting: the consuming chain supplies the order it chose,
// and `Codegen.matchChain` matches these flows set-wise for exactly that reason.
// (The poset-VALUED report — `Poset.t` in place of this path, so the axes'
// order-freedom is in the type rather than in a convention — stays with the rest
// of the poset round; this is the linear projection of it, which is all the
// placement question needs.)
and remainderPath = (flow: flowRef, value: valueRef): array<flowRef> =>
  switch collectRemainderFlows(flow, value) {
  | [] => flowContext(flow)
  | gs => gs->Array.reduce([], (acc, g) => dedupFlows(Array.concat(acc, Array.concat(flowContext(g), [g]))))
  }

// The INTERIOR context of a flow: the context at its innermost element, i.e.
// where a nesting-adjacent inner flow opens. For an Uncollect (list/option/alt)
// this is its own layer over its exterior — `flowContext(f) ++ [f]`. For a Join
// it is the interior of the *inner* operand: a join flattens outer and inner
// into one flow whose elements live at the inner's full depth, so a subsequent
// adjacent flow opens there, NOT at a single "join layer". Recurses through
// stacked joins. (The join-adjacency check uses this; without it a join whose
// outer is itself a join — a nested flatten, e.g. flatten-then-filter — is
// wrongly rejected as non-adjacent, though Codegen's per-level spine walk
// compiles it fine. Also backs a register's `prev` context, above.)
and flowInterior = (r: flowRef): array<flowRef> =>
  switch r {
  | FlowPort(n, _) =>
    switch n.kind {
    | Join({inner}) => flowInterior(inner)
    | _ => Array.concat(flowContext(r), [r])
    }
  }

// --- Commute over a crossed pair: transpose ---------------------------------
//
// Commute swaps two nesting-adjacent layers, and over a CROSSED pair that swap
// is TRANSPOSE — total, value-preserving, and confluent
// (product-flows-design.md, theorem 2 "commute is total on crossed pairs";
// lazy-stream-commute-design.md's taxonomy row "Transpose", the lawful
// exception to the same-kind commute it otherwise declines). Transpose RE-READS
// a product in the other order rather than restructuring anything, so a commute
// output port simply DENOTES one of its operand flows: "outer" is the ex-inner,
// now read outermost; "inner" the ex-outer, now read innermost. Stacked
// commutes resolve by recursion.
//
// That is the whole of the transposing commute's compilation: resolving through
// it makes a transposed consumer an ordinary product chain in its own order,
// and the shared point-indexed table already serves every k! reading, so the
// transpose costs nothing (Codegen's `matchProductChain`).
//
// The lawfulness GATE is at the call sites, not here: only the product matchers
// resolve, and they then require the resolved flows to be axes of ONE
// constructed product. A commute over a genuine (dependent) nesting — the
// option-out-of-stream SEQUENCE operation, which is directed, short-circuits,
// and is a different operation wearing the same name (lazy-stream-commute-
// design.md, "it currently names two operations") — resolves to flows no Cross
// crosses, so its chain declines exactly as before.
let rec throughCommutes = (f: flowRef): flowRef =>
  switch f {
  | FlowPort(n, port) =>
    switch n.kind {
    | Commute({outer, inner}) =>
      switch port {
      | "outer" => throughCommutes(inner)
      | "inner" => throughCommutes(outer)
      | _ => f
      }
    | _ => f
    }
  }

// The full poset context of a flow operand of a Cross: its exterior chain plus
// the axis (or axes) it opens. A plain Uncollect opens ONE axis, so this is the
// linear path made into a Series (`pathToPoset(flowContext(f) ++ [f])`). A Cross
// OUTPUT flow opens its two operands' axes side by side, so this recurses into a
// PARALLEL — which is how a *nested* Cross (`cross(cross(x, y), z)`) flattens to
// a flat product `{X || Y || Z}` rather than treating the inner cross's output
// as one opaque axis. Parallel is order-free and its members carry their own
// exteriors, so a redundant shared prefix washes out under Poset's axis/order
// algebra, exactly as the two-operand case relied on.
let rec fullPoset = (f: flowRef): Poset.t =>
  switch f {
  | FlowPort(n, _) =>
    switch n.kind {
    | Cross({left, right}) => Poset.parallel([fullPoset(left), fullPoset(right)])
    | _ => pathToPoset(Array.concat(flowContext(f), [f]))
    }
  }

// The product context a Cross node constructs: the PARALLEL composition of its
// two operands' full contexts (each operand's exterior plus its own axis, or its
// own sub-product for a nested cross). For two top-level sibling opens this is
// `{X || Y}`; for siblings sharing an outer loop L it is `L > {X || Y}` — the
// shared prefix stays series, the divergent axes go parallel (Poset's
// axis-set/order-set algebra makes the redundant L in both operands wash out);
// for a nested cross `fullPoset` flattens it to the flat product of all its
// axes. Still raises Incomparable when an operand's own EXTERIOR is a product
// (a cross whose operand opens inside another product — the deeper poset round),
// which `productsIndex` skips.
let crossProduct = (left: flowRef, right: flowRef): Poset.t =>
  Poset.parallel([fullPoset(left), fullPoset(right)])

// Poset-aware value context: like `valueContext`, but a combine of two sibling
// axes is resolved through the program's constructed `products` (Poset.merge)
// rather than the linear prefix rule (Context.merge, which raises on the FIRST
// sibling pair and so never sees the rest of the combine). Because it reaches
// EVERY combine in a value, a value spanning axes that no single constructed
// product covers raises `Poset.Incomparable` at the uncovered step — the
// full-span check the linear `valueContext` cannot do (it stops at the first
// coverable pair). This is what lets `checkAlignment` witness an under-covered
// n-ary consumer (e.g. `f(x, y, z)` with only `{X, Y}` crossed) at the Check
// level instead of admitting it and leaving the gap to Codegen.
//
// Only the leaf kinds a combining value is built from are handled directly (Lit,
// App, an Uncollect element/alt payload — the axis-bearing leaves). Any other
// kind falls back to the linear path lifted to a poset; its own alignment is
// checked by `valueContext` in the ordinary way, so nothing new is witnessed
// there. A `Series` path can only widen a `merge` need, never satisfy a product
// exactly, so the fallback is sound for the full-span question.
let rec posetValueContext = (~products: array<Poset.t>, r: valueRef): Poset.t =>
  switch r {
  | ValuePort(n, port) =>
    switch n.kind {
    | Lit(_) => Poset.Root
    | App({fn, args}) =>
      args->Array.reduce(posetValueContext(~products, fn), (acc, a) =>
        Poset.merge(~products, acc, posetValueContext(~products, a))
      )
    | Aggregate({fields}) =>
      fields->Array.reduce(Poset.Root, (acc, (_, v)) =>
        Poset.merge(~products, acc, posetValueContext(~products, v))
      )
    | Disaggregate({struct_}) => posetValueContext(~products, struct_)
    | Uncollect({flowKind}) =>
      let ownFlow = switch flowKind {
      | List | Option => FlowPort(n, "flow")
      | Case(_) => FlowPort(n, port)
      }
      fullPoset(ownFlow)
    | _ => pathToPoset(valueContext(r))
    }
  }

// Every product context a Cross node in the program constructs — the index
// `Poset.merge` consults to decide whether a sibling combine has an exact home
// (a combine's home is exact, not a covering superset — product-flows-design.md).
let productsIndex = (p: program): array<Poset.t> =>
  p.nodes->Array.filterMap(n =>
    switch n.kind {
    | Cross({left, right}) =>
      try {Some(crossProduct(left, right))} catch {
      | Incomparable(_) => None // operand exterior is itself a product: poset round
      }
    | _ => None
    }
  )
