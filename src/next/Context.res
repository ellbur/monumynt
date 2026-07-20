// Context paths — the ordered stack of flows a value lives under.
//
// This is bundle-provenance-design.md's context path, computed structurally
// (root outward; one segment per flow layer). It is the shared substrate
// for three consumers:
//
//   - Check: flow-context alignment (combining values from incomparable
//     contexts is the time-travel / bundle-mixing clash).
//   - Annotate: the flow-variable set handed to codegen (the
//     generalisation of the legacy compiler's `deeper`).
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
//     its innermost segment. Provenance's cell-level disjointness checks
//     (mixing sibling alts) are not implemented yet — Check stubs name them.
//   - No memoisation yet; programs are test-sized. When Annotate becomes a
//     real pass it should compute these once per (node, port) and hand them
//     down, per the pipeline discipline.

open Program

exception Incomparable({left: string, right: string, where: string})

let flowKey = (f: flowRef): string =>
  switch f {
  | FlowPort(n, port) => Int.toString(n.id) ++ ":" ++ port
  }

let contextToString = (ctx: array<flowRef>): string =>
  "[" ++ ctx->Array.map(flowKey)->Array.join(" > ") ++ "]"

let isPrefix = (shorter: array<flowRef>, longer: array<flowRef>): bool => {
  Array.length(shorter) <= Array.length(longer) &&
  shorter->Array.everyWithIndex((f, i) =>
    switch longer[i] {
    | Some(g) => flowKey(f) === flowKey(g)
    | None => false
    }
  )
}

// Prefix-rule merge: the deeper context wins if the other is its prefix.
let merge = (~where: string, a: array<flowRef>, b: array<flowRef>): array<flowRef> =>
  if isPrefix(a, b) {
    b
  } else if isPrefix(b, a) {
    a
  } else {
    throw(
      Incomparable({left: contextToString(a), right: contextToString(b), where}),
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
        | Some({flow}) => flowContext(flow)
        }
      }
    | Join(_) | Commute(_) | Cross(_) =>
      failwith("Context.valueContext: flow-only node has no value ports")
    | DelayRead({flow}) => Array.concat(flowContext(flow), [flow])
    | DelayWrite({read}) =>
      switch read.kind {
      | DelayRead({flow}) => flowContext(flow)
      | _ => failwith("Context.valueContext: DelayWrite whose read is not a DelayRead")
      }
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
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) =>
      failwith(
        "Context.flowContext: node kind " ++
        kindName(n.kind) ++ " has no flow ports (ref to port " ++ port ++ ")",
      )
    }
  }
