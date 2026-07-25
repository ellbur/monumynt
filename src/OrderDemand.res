// The order-demand check — which flows supply a "next iteration".
//
// Design: plans/delay-ontology-design.md. The PER-KIND HALF is ADOPTED
// (2026-07-23): the owned-order criterion, the order-demand check, and the
// hold identification. The linearization residue (which order a register
// walks a multi-axis product in — plans/product-linearization-design.md)
// and the value-in-context model remain EXPLORATION; nothing here may
// prejudge them.
//
// This module is no longer a pure stub: `orderOf` — the kinds-table lookup —
// is IMPLEMENTED for the flow constructors the representation has today
// (list / option / case uncollects, Join, Cross, Commute, a partial
// collect's merged flow). The rule that consumes it lives in `Check.res`
// (`checkOrderDemand`), beside the other witness rules and mirroring how
// `checkCross` consumes `Annotate.crossViolation` — the table is the fact,
// the witness is the check. The rows for flow kinds that do not exist yet
// (stream, async, incremental, the sever→settle body flow, divide-flow
// siblings, saturation members) are recorded below and land with their
// kinds.
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
// Integration points:
//   - Check.res: `checkOrderDemand` joins the witness rules (invoked from
//     Pipeline after annotate, like the others). A register whose driving
//     flow does not own a total order is witnessed, not crashed.
//   - The kinds table below is the lookup the rule reads; new flow kinds
//     (Stream.res, Async.res, Incremental.res) add their rows as they land.

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

// --- The kinds table, cashed (delay-ontology-design.md) ---------------------
//
// A Join flattens its two operands into one walk: outer-then-inner, so the
// order is lexicographic and is owned exactly when both operands' are. The
// two shapes that occur today are `join(list, list)` — the flattened walk,
// Owned ⊗ Owned — and `join(list, case-alt)` — the filtered sub-flow, Owned ⊗
// Degenerate, which is the table's "segment / filtered sub-flow" row: the
// parent's order restricted, and the sub-order of a sequence is a sequence.
// A missing order dominates a present one; a SURPLUS operand stays surplus
// (a product under a join is the linearization residue, not resolved here —
// the doc's "Join the product" joins its AXES, each of which owns an order).
let joinOrder = (outer: orderClass, inner: orderClass): orderClass =>
  switch (outer, inner) {
  | (NoOrder, _) | (_, NoOrder) => NoOrder
  | (Incidental, _) | (_, Incidental) => Incidental
  | (Surplus, _) | (_, Surplus) => Surplus
  | (Degenerate, Degenerate) => Degenerate
  | (Owned, _) | (_, Owned) => Owned
  }

// The kinds-table lookup, as the structural provenance walk the design calls
// for ("every flow constructor states what its output's order is … so 'does
// this flow own an order' is a provenance walk — the check is structural, no
// analysis"). No program-wide analysis is consulted; the `program` argument is
// kept because the later rows (a served facet's exchange flow, a divide-flow
// instance) are stated by a node elsewhere in the graph.
let rec orderOf = (p: Program.program, f: Program.flowRef): orderClass =>
  switch f {
  | Program.FlowPort(n, port) =>
    switch n.kind {
    // "list walk | yes | walk order of the opened data" — the paradigm row.
    | Uncollect({flowKind: List}) => Owned
    // "case / option, bare | degenerate | ≤1 firing; `prev` reads the seed."
    // A Delay here is well-formed but inert, which is a property of CARDINALITY,
    // not of the kind — the same reason nobody writes "Delay is meaningless over
    // options" as a kind fact.
    | Uncollect({flowKind: Option}) => Degenerate
    | Uncollect({flowKind: Case(_)}) => Degenerate
    | Join({outer, inner}) => joinOrder(orderOf(p, outer), orderOf(p, inner))
    // "product {X, Y} | surplus | every axis order real, none privileged."
    // Not disorder but an embarrassment of orders: the register's demand for ONE
    // is the linearization residue, located here as the surplus cell rather than
    // resolved (product-linearization-design.md is unadopted).
    | Cross(_) => Surplus
    // A commute transposes two layers; each output port re-delivers the order of
    // the operand it swapped with (inherited — the firings are the same firings,
    // re-grouped).
    | Commute({outer, inner}) =>
      switch port {
      | "outer" => orderOf(p, inner)
      | "inner" => orderOf(p, outer)
      | _ => failwith("OrderDemand.orderOf: unknown Commute port " ++ port)
      }
    // A partial collect's merged flow is a SEGMENT of the flow the split lives
    // in — the parent's order restricted to the covered cells (inherited). Its
    // exterior's innermost layer is that parent; an empty exterior means one
    // firing at the top level, which is degenerate.
    | Collect(_) =>
      let exterior = Context.flowContext(f)
      switch exterior[Array.length(exterior) - 1] {
      | Some(parent) => orderOf(p, parent)
      | None => Degenerate
      }
    | Lit(_) | App(_) | DelayRead(_) | DelayWrite(_) | Aggregate(_) | Disaggregate(_) =>
      failwith(
        "OrderDemand.orderOf: node kind " ++
        Program.kindName(n.kind) ++ " has no flow ports (ref to port " ++ port ++ ")",
      )
    }
  }

// The order-demand check itself — "a Delay's flow must own a total order" —
// lives in `Check.res` (`checkOrderDemand`), where it joins the other witness
// rules and reads this table, the way `checkCross` reads Annotate's invariance
// fact. Its complement is the productivity check; together they are the whole
// discipline of drawn state: productivity says a cycle must cross a Delay, the
// order demand says a Delay must sit on an order-owning flow. State is legal
// exactly where a drawn order can carry it.

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
