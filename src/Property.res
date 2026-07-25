// Validity without a type system — properties on wires, demands and
// offers, the catalog row, and the boundary projection — ARCHITECTURE
// STUB.
//
// Design: plans/types-design.md — EXPLORATION, but its smallest first step
// (flow-context alignment with a two-anchor witness) is already implemented
// in Check.res; this module plans steps 2-3 (shape propagation over a small
// demands/offers catalog; the schematic-source node kind). Highest-leverage
// unbuilt substrate: the editor-state query layer, the boundary signature,
// the endings inventory (Fail.res), and the collect ladder
// (CollectFamily.res) all consume it.
//
// The single most important simplicity commitment: THE SOLVER IS MONOTONE
// PROPAGATION TO A FIXPOINT, WITH NO CHOICE POINTS. No overloading, no
// search, no entailment lattice, no subtyping, no user-defined
// implications — initially. Offers propagate forward, demands backward;
// structural nodes TRANSPORT rather than demand (uncollect moves
// element-properties onto the element wire, collect moves them back,
// Aggregate/Disaggregate route through fields, Delay transports around the
// back-edge, making propagation a fixpoint). Exactly two invalidity modes:
// a CLASH (demand meets contradicting offer) and an UNMET demand at a
// concrete source; capability properties never clash, only go unmet.
// Requirement carried from the doc: no error without a witness drawable on
// the diagram (anchors plus the wire path the properties travelled — unique
// and walkable because propagation has no choice points).

// --- The starter property inventory (the doc's 10-row table) --------------
//
// Three sorts kept separate: SHAPES (disjoint), CAPABILITIES (independent),
// LINKS (relations, never demanded, only displayed).
type property =
  // shapes
  | Numeric
  | StringShaped
  | BoolShaped
  | ListShaped // of an element property set
  | OptionShaped_ // of an element property set
  | AlternativeShaped({alts: array<string>})
  | StructWithField({field: string})
  // capabilities
  | EqualityComparable
  | Associative
  | HasIdentity // the identity VALUE rides the catalog row as witness
  | FlowContextChain // the alignment property Check.res already computes
  // links
  | SameAs // relational; displayed, never demanded

// A demand on an input port / an offer on an output port.
type portFact = {port: string, facts: array<property>}

// --- The catalog row -------------------------------------------------------
//
// The concrete record by which a node kind or a registered function (an App
// extern, an external source, a foreign operation) declares what it demands
// and offers. This is the ONE catalog several rounds converge on — the
// trusted JS edge. Beyond demands/offers it carries, per the later rounds:
//   - identityWitness: the monoid identity value (CollectFamily's ladder —
//     has-identity carries the value the empty collect yields).
//   - throwLanes: declared failure lanes (Fail.res — declared throws are
//     lanes; the row is their minting site; an undeclared throw is an edge
//     breach quarantined on the background super flow).
//   - cancelTranslation: the foreign edge's cancel word (Async.res /
//     cancellation-design.md: fetch -> AbortSignal, timer -> clearTimeout;
//     schema open — idempotence, promptness, post-cancel state).
//   - coalescing: write as a monoid homomorphism (within-firing-effects:
//     where present, segment-boundary placement is pure efficiency; where
//     absent — chunked encoding, datagrams — the boundary is observable
//     meaning).
type catalogRow = {
  rowName: string,
  rowDemands: array<portFact>,
  rowOffers: array<portFact>,
  identityWitness: option<JsAst.expr>,
  throwLanes: array<string>,
  cancelTranslation: option<string>,
  coalescing: bool,
}

// --- Propagation, witnesses, and the boundary projection ------------------

// A clash / unmet-demand witness: anchor node(s) plus the wire path the
// properties travelled. Renders through Check's witness surface.
type propertyWitness = {anchors: array<int>, path: array<string>, clash: string}

let propagate: (Program.program, array<catalogRow>) => array<propertyWitness> = (_p, _catalog) =>
  failwith("stub: monotone demand/offer propagation to fixpoint — types-design.md, 'the substrate'")

// The boundary projection / principal property signature: run propagation
// over a diagram's interior once, project onto the boundary — residual
// demands per in-port, offers per out-port, relational links among ports.
// Checked once per VERSION, memoised along the step-DAG (Edit.res). This is
// also where a divide link's pinned payload set lives (Fail.res residue)
// and what Boundary.res's reusability check projects.
type signature = {
  residualDemands: array<portFact>,
  boundaryOffers: array<portFact>,
  links: array<(string, string)>,
}

let boundarySignature: Program.program => signature = _p =>
  failwith("stub: principal property signature — types-design.md, 'Boundary projection'")

// --- The schematic source --------------------------------------------------
//
// A node kind with no computation, carrying chosen offers (possibly none).
// Offers unlock operations; unmet demands propagating back are ABSORBED as
// the placeholder's inferred description, NOT errors. Program-editing open
// q.9 leans toward unifying this with Edit.res's Hole.
type plannedSchematicSource =
  | SchematicSource({chosenOffers: array<property>})

// Settled rejections: importing a conventional type system; one complete
// type per value (the substrate is properties on wires); anything requiring
// search (overloading, coercions, defaulting, numeric refinements/ranges);
// a second stored artifact (nothing the diagram + catalog don't determine);
// checking that blocks drawing (it joins the whole-diagram
// quotient-constraint family).
