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
    | Lit(_) | App(_) | Collect(_) | Aggregate(_) | Disaggregate(_) => LazyCell
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
// determine its firing STRUCTURE, as sets of flow keys (Context.flowKey):
//
//   introducedAxes(f) — the uncollect axes flow f itself ranges over (its
//                       "own" iteration layers).
//   sourceAxes(f)     — the axes that determine how f fires: its source value
//                       and its outer nesting, but NOT its own introduced axis.
//   valueAxes(v)      — the axes a value varies over.
//
// The walks themselves live in `Context` (they return flow REFS there, because
// `Context.valueContext` needs to name the fibering axes a partial product
// traversal leaves standing); these are the key-set views the checks read.
//
// Unlike Context's paths these NEVER merge — they union raw flow keys, order-
// and comparability-free — so they are defined even where Context.merge would
// raise Incomparable. That is exactly the sibling case Cross exists to combine:
// the invariance demand has to be answerable on two incomparable flows.

let flowKey = Context.flowKey

let introducedAxes = (f: flowRef): array<string> =>
  Context.introducedAxisFlows(f)->Array.map(flowKey)

let sourceAxes = (f: flowRef): array<string> => Context.sourceAxisFlows(f)->Array.map(flowKey)

// Every axis a flow touches: what it ranges over plus what determines it.
let axesOf = (f: flowRef): array<string> => Context.axisFlows(f)->Array.map(flowKey)

let valueAxes = (v: valueRef): array<string> => Context.valueAxisFlows(v)->Array.map(flowKey)

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

// A REPEATED axis is a violation too, and for the poset's own reason: one axis
// reached through both operands is the repeated-flow diamond (`Poset.res` — "an
// N is always a repeated-flow DIAMOND … the incoherent middle, which the checker
// witnesses rather than representing"), left unresolved between align (zip) and
// cross. It is stated separately from the source-vs-introduced demand because
// the two say different things: that one rejects a dependent nesting, this one
// rejects an operand pair that is not two axes at all.
let crossViolation = (left: flowRef, right: flowRef): option<string> =>
  switch firstShared(introducedAxes(left), introducedAxes(right)) {
  | Some(k) => Some(k)
  | None =>
    switch firstShared(sourceAxes(left), introducedAxes(right)) {
    | Some(k) => Some(k)
    | None => firstShared(sourceAxes(right), introducedAxes(left))
    }
  }
