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
//
// Deferred, slot reserved:
//   - flow-variable sets per (node, port) — today recomputed on demand via
//     Context; a real annotate pass computes them once and hands them down.
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
