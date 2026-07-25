// The order-demand check — which flows supply a "next iteration" —
// ARCHITECTURE STUB.
//
// Design: plans/delay-ontology-design.md. The PER-KIND HALF is ADOPTED
// (2026-07-23): the owned-order criterion, the order-demand check, and the
// hold identification. The linearization residue (which order a register
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

let orderOf: (Program.program, Program.flowRef) => orderClass = (_p, _f) =>
  failwith("stub: the kinds-table lookup — delay-ontology-design.md, 'The kinds table, cashed'")

// The order-demand check: a Delay's flow must own a total order. "A
// register is legal exactly downstream of the point where order becomes
// owned, and the order-minting construct is where the diagram shows the
// synchronisation."
let checkOrderDemand: Program.program => array<Check.witness> = _p =>
  failwith("stub: order-demand check — delay-ontology-design.md, 'The order-demand check, named'")

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
