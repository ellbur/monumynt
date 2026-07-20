// Pass 3 of the compile pipeline: cheap derived facts codegen wants handed
// to it rather than discovered mid-walk (compile-strategy-design.md).
//
// Implemented today:
//   - the WRITE INDEX (register read id -> write node). Buildable only
//     because the entry point is a node set — a write half can be
//     root-unreachable, which is the fact that forced the node-set entry.
//   - SPECIES assignment: which runtime shape each node compiles to. Only
//     the eager species exist yet; stream/async/incremental cells arrive
//     with their runtime layers (workstream C) as new variants here, and
//     codegen dispatches on the annotation, not on the kind.
//   - FLOW-VARIABLE SETS: introducedAxes / sourceAxes / valueAxes and the
//     mutual-invariance demand (crossViolation) — the invariance fact Cross
//     needs (product-flows-design.md, "smallest first step" 1). Computed as
//     pure structural walks (still recomputed on demand, not yet cached in
//     the annotations record — that is the "once per node, handed down"
//     refinement, below); the Cross emitter and zip will lean on the same
//     sets once the poset round lands.
//
// Deferred, slot reserved:
//   - caching the flow-variable sets per (node, port) in the annotations
//     record: a real annotate pass computes them once and hands them down,
//     rather than the on-demand recomputation the checks use today.
//   - strictness tagging and the consumer-set lattice (the deferred
//     placement optimisations; deferred, NOT rejected — see
//     placement-algorithm-notes.md and lazy-stream-placement-design.md).
//     They are more annotations consumed by codegen, changing which shape
//     it emits; reserving the position here is what makes reviving them
//     additive.

open Program

type species =
  | LazyCell // Lit / App / eager collect: one memoised lazy binding
  | FlowOnly // Uncollect / Join / Commute / Cross: no runtime residue of
  //            their own; they steer collect thunks
  | RegisterRead // compiles to loop-skeleton `let` init/read
  | RegisterWrite // compiles to assign-at-bottom; `final` readable after

type annotations = {
  writeIndex: Map.t<int, node>, // DelayRead id -> its DelayWrite node
  speciesOf: node => species,
}

let annotate = (p: program): annotations => {
  let writeIndex: Map.t<int, node> = Map.make()
  p.nodes->Array.forEach(n =>
    switch n.kind {
    | DelayWrite({read}) => Map.set(writeIndex, read.id, n)
    | _ => ()
    }
  )
  let speciesOf = (n: node): species =>
    switch n.kind {
    | Lit(_) | App(_) | Collect(_) => LazyCell
    | Uncollect(_) | Join(_) | Commute(_) | Cross(_) => FlowOnly
    | DelayRead(_) => RegisterRead
    | DelayWrite(_) => RegisterWrite
    }
  {writeIndex, speciesOf}
}

// --- Flow-variable sets ------------------------------------------------------
//
// The invariance fact of product-flows-design.md ("smallest first step" 1):
// per-flow sets of the uncollect axes a flow ranges over vs the axes that
// determine its firing STRUCTURE. Three mutually-recursive walks over the
// ports representation, expressed as sets of flow keys (Context.flowKey):
//
//   introducedAxes(f) — the uncollect axes flow f itself ranges over (its
//                       "own" iteration layers).
//   sourceAxes(f)     — the axes that determine how f fires: its source value
//                       and its outer nesting, but NOT its own introduced axis.
//   valueAxes(v)      — the axes a value varies over.
//
// Unlike Context's paths these NEVER merge — they union raw flow keys, order-
// and comparability-free — so they are defined even where Context.merge would
// raise Incomparable. That is exactly the sibling case Cross exists to combine:
// the invariance demand has to be answerable on two incomparable flows, which
// is why it lives here and not on the context path.
//
// Precise for the shapes the demand actually inspects — list/option uncollects
// (possibly nested), case splits, and the values built over them. The
// compositional kinds (Join/Cross/Commute operands, collect results) are
// unioned conservatively: an over-approximation can only over-report a
// dependence, and crossing those kinds is itself the deferred poset round.

let flowKey = Context.flowKey

let rec introducedAxes = (f: flowRef): array<string> =>
  switch f {
  | FlowPort(n, _) =>
    switch n.kind {
    | Uncollect(_) => [flowKey(f)]
    | Join({outer, inner}) => Array.concat(introducedAxes(outer), introducedAxes(inner))
    | Cross({left, right}) => Array.concat(introducedAxes(left), introducedAxes(right))
    | Commute({outer, inner}) => Array.concat(introducedAxes(outer), introducedAxes(inner))
    | Collect(_) => [flowKey(f)] // a partial collect's merged flow: its own option axis
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) => []
    }
  }

and sourceAxes = (f: flowRef): array<string> =>
  switch f {
  | FlowPort(n, _) =>
    switch n.kind {
    | Uncollect({input, nesting}) =>
      let fromInput = valueAxes(input)
      switch nesting {
      | Some(outer) => Array.concat(fromInput, axesOf(outer))
      | None => fromInput
      }
    | Join({outer, inner}) => Array.concat(axesOf(outer), sourceAxes(inner))
    | Cross({left, right}) => Array.concat(axesOf(left), axesOf(right))
    | Commute({outer, inner}) => Array.concat(axesOf(outer), sourceAxes(inner))
    | Collect({branches}) =>
      switch branches[0] {
      | Some({flow}) => sourceAxes(flow) // the merged cells' exterior
      | None => []
      }
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) => []
    }
  }

// Every axis a flow touches: what it ranges over plus what determines it.
and axesOf = (f: flowRef): array<string> => Array.concat(sourceAxes(f), introducedAxes(f))

and valueAxes = (v: valueRef): array<string> =>
  switch v {
  | ValuePort(n, port) =>
    switch n.kind {
    | Lit(_) => []
    | App({fn, args}) =>
      args->Array.reduce(valueAxes(fn), (acc, a) => Array.concat(acc, valueAxes(a)))
    | Uncollect({flowKind}) =>
      // element (list/option) or an alt payload (case): varies over its own
      // flow's axis and everything determining that flow.
      let ownFlow = switch flowKind {
      | List | Option => FlowPort(n, "flow")
      | Case(_) => FlowPort(n, port)
      }
      axesOf(ownFlow)
    | Collect({branches}) =>
      switch classifyCollect(branches) {
      // A partial collect's value is the merged (option-borne) value.
      | CasePartial(_) => axesOf(FlowPort(n, "flow"))
      // A full collect's value is the result at the flow's EXTERIOR — the
      // iterated axis is gone, only its source survives.
      | _ =>
        switch branches[0] {
        | Some({flow}) => sourceAxes(flow)
        | None => []
        }
      }
    | Join(_) | Commute(_) | Cross(_) => [] // no value ports
    | DelayRead({flow}) => axesOf(flow)
    | DelayWrite({read}) =>
      switch read.kind {
      | DelayRead({flow}) => sourceAxes(flow)
      | _ => []
      }
    }
  }

// Cross's demand (product-flows-design.md, "The construct"): the operands are
// MUTUALLY INVARIANT — "neither flow's source, nor anything determining its
// firings, has the other flow in its flow-variable set." Concretely, a
// violation is one operand's source axes intersecting the OTHER operand's
// introduced axes: that other flow's element determines this flow's firings,
// so the nesting is dependent (true raggedness), not a product, and has no
// transpose. Returns the first offending shared axis key (its node is the
// dependence introducer) so the checker can name it; None when invariant.
//
// Sharing an OUTER axis is not a violation — two siblings inside one common
// loop are still mutually invariant within it — which is why the test is
// source-vs-introduced, not raw set disjointness.
let firstShared = (a: array<string>, b: array<string>): option<string> =>
  a->Array.find(k => b->Array.includes(k))

let crossViolation = (left: flowRef, right: flowRef): option<string> =>
  switch firstShared(sourceAxes(left), introducedAxes(right)) {
  | Some(k) => Some(k)
  | None => firstShared(sourceAxes(right), introducedAxes(left))
  }
