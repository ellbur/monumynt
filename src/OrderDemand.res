// The order-demand check — which flows supply a "next iteration".
//
// Design: plans/delay-ontology-design.md. The PER-KIND HALF is ADOPTED
// (2026-07-23): the owned-order criterion, the order-demand check, and the
// `hold` identification. The linearization residue (which order a register
// walks a multi-axis product in — plans/product-linearization-design.md)
// and the value-in-context model remain EXPLORATION; nothing here may
// prejudge them.
//
// The criterion: a flow supplies a "next iteration" exactly when its
// firings are totally ordered BY THE FLOW'S OWN MEANING — an OWNED order.
// A Delay is a demand for the previous firing under its flow's owned total
// order. The load-bearing clause: it is not enough that an order HAPPENS;
// the order must be DRAWN (incidental runtime order is barred — weakening
// this re-opens concurrent-collect's dead end 3 and breaks naive/semi-naive
// as lowerings of one saturation drawing).
//
// The check is STRUCTURAL — a provenance walk, no analysis: every flow
// constructor states what its output's order is (inherits one, mints one,
// states none, or states several). Its complement is the productivity
// check ("every cycle crosses a Delay"), which is order-generic; the CLOCK
// is a parameter supplied by the flow's order-deliverer (walk step / pull /
// event-loop turn / handle exchange). Nothing is owed per kind.
//
// LIVE as of the register-over-products round: `orderOf` below is the kinds
// table cashed for the flow constructors that exist today, and `Check.res`
// hosts the rule that reads it (`checkOrderDemand`, rule name
// "order-demand"). The split is a dependency direction, not a change of
// plan: witnesses are Check's type, so the rule lives there and the table
// lives here, where new flow kinds (Stream.res, Async.res, Incremental.res)
// add their rows as they land. This is `product-flows-design.md`'s
// "smallest first step" 1 for registers over products — "the check rejects
// a whole-product register with the 'no order' witness, the remedy being
// 'fold one axis or Join'" — steps 2/3/4 (reduce along an axis, the running
// view, full reduction as an axis permutation) having landed ahead of it.
//
// NOT covered, deliberately: the context-read extension ("a raw `prev` on a
// wire whose flow owns no order is exactly as ill-formed as a register
// there"), which the doc makes conditional on the value-in-context model's
// adoption — that model is unadopted, so the rule stays on Delays.

open Program

// The five-way classification of a flow's order:
type orderClass =
  | Owned // Delay legal (list walk, stream, self-driven opener, segment /
  // filtered sub-flow — parent's order restricted; async stream — arrival
  // order; completions flow — settlement order, MINTED by settle; sequenced
  // facet's exchange flow — handle order; keyed lane's interior)
  | NoOrder // ill-formed (concurrent bodies between sever and settle;
  // sibling divide-flow instances; an unordered facet's exchanges; a
  // saturation round's members)
  | Incidental // ill-formed — the load-bearing clause (pre-settle
  // settlement order; a saturation lowering's worklist order; a var's
  // recomputation order — a Delay there would observe cutoffs)
  | Degenerate // well-formed but inert: <=1 firing, prev only reads the
  // seed (case/option bare, async value, race settlement) — "async supplies
  // no next" is CARDINALITY, not async-ness
  | Surplus // a product {X,Y}: every axis order real, none privileged —
  // the linearization residue's home; do not resolve here

// Where an owned order comes from (order provenance):
type orderProvenance =
  | InheritedOrder // filter sub-flow, split-when segment, keyed lane
  | MintedOrder // settle's completions; a sequenced facet's handle; a
  // merge's output; the self-driven opener
  | AmbientOrder // the event loop's arrival order as kind content

let orderClassName = (c: orderClass): string =>
  switch c {
  | Owned => "owned"
  | NoOrder => "none"
  | Incidental => "incidental"
  | Degenerate => "degenerate"
  | Surplus => "surplus"
  }

// How bad a class is when two of them meet on one flow (a Join). The
// combination is "the worst operand wins", which cashes the kinds table's
// rows for the composite constructors rather than adding rows of its own:
// Owned+Degenerate = Owned is the "segment / filtered sub-flow" row (the
// parent's order, restricted — join(list, case-alt) folds the Some-
// subsequence), Owned+Owned = Owned is the flattened sequence (the fork
// "dissolves on sequences", delay-ontology-design.md), Degenerate+
// Degenerate stays degenerate (<=1 firing either way), and a surplus or
// ill-formed operand poisons — nothing today linearizes a product.
let severity = (c: orderClass): int =>
  switch c {
  | NoOrder => 4
  | Incidental => 3
  | Surplus => 2
  | Owned => 1
  | Degenerate => 0
  }

let worse = (a: orderClass, b: orderClass): orderClass =>
  severity(a) >= severity(b) ? a : b

// The kinds table, cashed for the constructors that exist today
// (delay-ontology-design.md, "The kinds table, cashed"). Structural: the
// walk reads each constructor's own statement about its output's order, so
// no program-wide analysis is needed and the argument is the flow ref, not
// the program.
//
//   list walk           owned      walk order of the opened data
//   option / case alt   degenerate <=1 firing; `prev` reads the seed
//   join                inherited  the worst of its two operands (above)
//   commute             inherited  each swapped layer keeps its operand's
//                                  order (the swap reorders the PAIR, not
//                                  either layer's own firings; the
//                                  sequence-vs-transpose commute split —
//                                  Stream.res — may refine this)
//   partial merged flow degenerate the covered cells are disjoint, so the
//                                  merge fires <=1 time per parent firing;
//                                  its order arrives from the Join that
//                                  puts it on an ordered parent
//   cross               surplus    every axis order real, none privileged
//
// Rows owed by kinds that are not represented yet (stream, async stream,
// completions, event stream, exchange flow, keyed lane, var, sever->settle
// bodies, divide-flow siblings, saturation members) land with their
// species.
let rec orderOf = (f: flowRef): orderClass =>
  switch f {
  | FlowPort(n, port) =>
    switch n.kind {
    | Uncollect({flowKind: List}) => Owned
    | Uncollect({flowKind: Option | Case(_)}) => Degenerate
    | Join({outer, inner}) => worse(orderOf(outer), orderOf(inner))
    | Commute({outer, inner}) =>
      // Ports: "outer" is the flow that WAS inner, "inner" the ex-outer.
      switch port {
      | "outer" => orderOf(inner)
      | "inner" => orderOf(outer)
      | _ => failwith("OrderDemand.orderOf: unknown Commute port " ++ port)
      }
    | Collect(_) => Degenerate
    | Cross(_) => Surplus
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) =>
      failwith(
        "OrderDemand.orderOf: node kind " ++
        kindName(n.kind) ++ " has no flow ports (ref to port " ++ port ++ ")",
      )
    }
  }

// Where an owned order came from — the serializer taxonomy
// (delay-ontology-design.md, "Serializers: where owned order comes from").
// Descriptive: the check reads `orderOf`, not this. It is what a diagram
// would point at to show WHERE the synchronisation is ("a register is legal
// exactly downstream of the point where order becomes owned, and the
// order-minting construct is where the diagram shows the synchronisation").
let provenanceOf = (f: flowRef): option<orderProvenance> =>
  switch orderOf(f) {
  | Owned =>
    switch f {
    | FlowPort(n, _) =>
      switch n.kind {
      // The opener states the walk order of the data it opens — the order is
      // its kind content, not something it restricts from elsewhere.
      | Uncollect(_) => Some(MintedOrder)
      // A join flattens or restricts orders that already exist; a commute
      // re-delivers its operand's.
      | Join(_) | Commute(_) => Some(InheritedOrder)
      | _ => None
      }
    }
  | NoOrder | Incidental | Degenerate | Surplus => None
  }

// The sentence a witness says about a flow's class, and the remedy the
// design record names for it.
let classSummary = (c: orderClass): string =>
  switch c {
  | Owned => "owns a total order"
  | Degenerate => "fires at most once, so its order is degenerate"
  | NoOrder => "owns no firing order"
  | Incidental => "has only an incidental order — the runtime's schedule, which a program may not observe"
  | Surplus => "has SURPLUS order: every axis order is real and none is privileged"
  }

let remedy = (c: orderClass): string =>
  switch c {
  | Surplus => "fold one axis — name that axis's flow on the delay — or Join first"
  | Owned | Degenerate => ""
  | NoOrder | Incidental => "put the register downstream of the construct that mints an order"
  }

// --- The hold identification (adopted) ------------------------------------
//
// hold(init, events) IS the register on the event stream whose step is the
// projection onto the new value (prev ignored), read on any containing
// frame. The initial value plays the register seed's exact double duty; and
// hold is NOT order-free — last-write-wins reads the order ("latest" is an
// order word), so even carrying-nothing state demands an owned order. The
// identification is SEMANTIC; the compile may treat the mutation boundary
// specially (Incremental.res). Caveat: its read-range fine print leans on
// the straddle section, which is worked-with-leanings, NOT adopted.
//
// Settled rejections: wire-threading a Delay (no mutual temporal sequence
// to encode); extent-fixedness or async-ness as the criterion; runtime
// serialisation as sufficient; per-kind register modes (one construct, one
// check, one clock parameter); a Delay on the IO handle.
