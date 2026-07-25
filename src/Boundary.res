// The boundary substrate — the remembered cut, the call and the link, the
// op pair, and the served flow's two ends — ARCHITECTURE STUB.
//
// Design: plans/function-boundary-design.md + plans/divide-flow-design.md +
// plans/late-bound-operations-design.md, jointly ADOPTED (2026-07-23),
// under the ANCHOR-IS-IDENTITY constraint (a level/boundary is referenced
// by identity — a label or the boundary object — NEVER by a value wire;
// selecting a wire survives only as an editing gesture that resolves to a
// boundary identity at creation) and with a PROVISIONAL-CONFIDENCE marker
// on exactly one piece: slots dissolve into op pairs (implement it, keep it
// isolable). plans/served-flow-design.md: the two-ends core ADOPTED, the
// rest exploration. plans/configuration-scopes.md: dissolved — a config
// scope is an op pair with an inline splice binding; no ConfigScope node
// species (that would resurrect the slot species this round retires).
//
// The one-sentence result: a function is not a container of nodes but a
// REMEMBERED CUT through the wiring — a named correspondence of ports —
// and everything else is DERIVED from the cut rather than declared beside
// it. Ports come from the cut, never the cut from the ports (read off at
// extraction; declaration is optional planning metadata only).
//
// ONE substrate, FOUR bindings (do not make four types — distinguish by how
// a boundary is referenced/bound, never by shape):
//   function — named cut, ports bound at call sites; exists for reuse only.
//   level    — the substrate's anonymous instantiation-only use, minted by
//              drawing a link; labeled at most page-locally; no interface.
//   provider — a boundary whose facing ports are the server ends of
//              exchange pairs (the provider diagram and the function
//              diagram were never different things).
//   program  — the top level is a boundary too: Program.program's
//              {nodes, outputs} is the degenerate cut whose out-ports are
//              the distinguished outputs and whose in-ports are whatever
//              the deployment binds. "Top level" is a binding fact, not a
//              structural one.
//
// What is STORED: the boundary object (identity + the directed, sorted
// crossing list) and the references to it. What is DERIVED (computed,
// never stored): membership (a node is per-call iff downstream of an
// in-port; everything else the cone reads is shared by the PREFIX rule —
// closure capture dissolves, there is no environment object); the
// signature (Property.res's boundary projection); the flow skeleton (a
// display-time collapse level — the boundary hides DATA detail, never FLOW
// obligation); reusability; call-site admissibility; unbound-op re-export
// (faint, completion-derived). Identity lives on the CUT, not the node set
// — that is what lets an implementation be edited under callers.

// --- The cut ---------------------------------------------------------------

// One directed, sorted crossing list — NOT four port lists plus slots.
type crossingSort =
  | ValueIn
  | ValueOut
  | FlowIn
  | FlowOut
  | OpRequest // the op pair rides the same list (slot dissolution)
  | OpResponse

// A crossing: which wire crosses the cut, of which sort. The wire is named
// by the port it leaves (out-crossings) or feeds (in-crossings); pairwise
// correspondence — each port one wire, no argument list, no tuple packed to
// cross the cut.
type crossing = {sort: crossingSort, ref_: string}

type boundary = {
  boundaryId: int, // identity is the cut's, minted once
  boundaryName: option<string>, // functions are named; levels at most
  // page-locally labeled (the loop-label precedent); spelling owed
  crossings: array<crossing>,
}

// --- The two reference species (one substrate, two constructs) ------------

// A CALL has an interface, is checked against the signature, and renames
// with the function. A LINK has none of these: page-local, anonymous or
// level-labeled, its problem wires check against the level's own in-wires
// (trivially the same wires). Recursion NEVER routes through a named
// function — the link is its own construct on the shared substrate; a
// caller cannot tell whether an implementation recurses.
type boundaryRef =
  | Call({target: int, site: int}) // boundary id, call-site node id
  // The link, tree-shaped (the divide flow): input ports correspond
  // pairwise to the problem wires, output ports pairwise to the level's
  // answer wires; each firing mints an INSTANCE (the tree exists as
  // instances of the drawing, not as a value). Like DelayWrite, the later
  // linking act mints its own node; the object graph stays a DAG; the
  // cycle is recovered from identity. A leaf is an alt with no links —
  // NO base-case construct. There is NO TIME among sibling instances (a
  // register over the divide flow's instances is ill-formed — see
  // OrderDemand.res NoOrder), and no traversal-order modes (orders are
  // combines, not configuration).
  | Link({target: int, problems: array<Program.valueRef>})

// --- The measure discipline (termination for reference cycles) ------------
//
// Every cycle crosses a guard (register / dedup-collect / measure). The
// measure attaches to reference cycles of ANY species: a non-recursive call
// needs none; a link cycle needs one; named mutual recursion between
// reusable functions is legal, its call-graph cycle carrying the same JOINT
// measure (fine print — which edges must advance, composition when cycles
// share edges — is open q.6, unworked).
type measureSpecies =
  | StructuralShrink // sub-problem a strict part of the parent's data
  | CursorProgress // same data, strictly advanced position; violation =
  // left recursion, and the check NAMES the offending wire
  | DrawnFuel // a drawn counter the divide alt strictly decreases, with an
  // alt covering zero — the measure is on the page

type measureRung =
  | CatalogChecked // a catalog division — checked by construction
  | DrawnMeasure // structural check (decrement is a catalog row; split
  // covers zero)
  | WarnedTrust // legal, flagged "may diverge" — the floor. No dependency
  // analysis anywhere.

type measure = {species: measureSpecies, rung: measureRung}

// --- Late-bound operations: the facet, the op pair, the binding -----------
//
// An op puts a REQUEST/RESPONSE port pair on the boundary (OpRequest /
// OpResponse crossings): a question goes out, its answer comes back — one
// use, one exchange; the use site is an ordinary chain stage. A late-bound
// operation is the CLIENT end of a served flow; a provider is its SERVER
// end. Unmet demands travel outward (the caller's boundary grows the pair;
// re-export through an intermediate boundary is derived by published rule,
// shown faint). The response lane is failable like any wire (a catalog row
// entering the client's inventory — Fail.res).
type facet = {
  facetId: int,
  operations: array<string>, // ONE pair per operation — never one tagged
  // pair (the sum bottleneck); narrowing capability = dropping pairs
  sequenced: bool, // sequenced (carries a handle; exchanges arrive in
  // segment order) vs unordered (providers must be exchange-stateless — a
  // register on an unordered serving flow is ill-formed). "Statefulness of
  // the provider and orderedness of the facet are the same bit."
}

// Binding = wiring a provider on. Matches offer to demand BY DRAWN FACET
// IDENTITY, never by structural search, never by ambient/dynamic-scope
// lookup. Two provider forms — splicing (stateless, per exchange) and
// serving (one instance over the exchange flow; state = a register on that
// flow) — DERIVED from the facet's bit, not chosen. Middleware (logging,
// retry, fault injection) is a SPLICE on a binding wire — provider-shaped
// upward, consumer-shaped downward; stack order = drawn nesting. Runtime
// provider choice is ROUTING among wired providers (a case split), never a
// provider value on a wire.
type binding = {
  boundFacet: int,
  operation: string,
  clientEnd: int, // the use site / demanding boundary
  serverEnd: int, // the provider boundary
}

// --- The served flow's two ends (adopted core) ----------------------------
//
// One construct, the exchange pair; the two spellings are its two ends:
// the client end sees a STAGE in its own flow (request = value out,
// response = value received, exactly-once by one wire into the pair); the
// server end sees a FLOW of exchanges (request = value in per firing,
// response = value OWED per firing, exactly-once by the collect's law).
// The flow exists only at the serving end — "served flow" names a VIEW,
// not a flow kind (the kinds table is untouched). Which one is the server
// is a property of a BINDING (an HTTP server is a provider bound to the
// network; the same provider bound to a scripted requester is a test); a
// server program compiles to a REGISTRATION, not a value computation.
// Still exploration (flag, don't harden): the exchange law's fine print,
// the k-operation provider as a pre-split bundle (k static lanes, no
// dispatch drawn because no union was packed), the recursive provider (the
// link in exchange costume — measure applies verbatim), the keyed cache
// (partition + per-lane register middleware; cycle witness = the
// provenance context path).

// --- Derived computations (stubs) -----------------------------------------

// Membership: per-call iff downstream of an in-port.
let membership: (Program.program, boundary) => array<Program.node> = (_p, _b) =>
  failwith("stub: derived membership — function-boundary-design.md, 'What the cut is not: a scope'")

// Reusability: a boundary is reusable iff everything its out-ports' cone
// reads, other than its own in-ports, is prefix-shared (context-free).
// Failure is not an error but a naming: extraction over a per-iteration
// wire SURFACES that wire as a demanded port (accumulate-demands). Partial
// cuts: an uncut wire is a FREE wire; a call site at context C is legal iff
// every uncut wire's context is a prefix of C (a local function, reusable
// at or below the join of its uncut wires' contexts; cutting one more wire
// = one more port). Freedom is input-side only: uncut side-outputs belong
// to the original instance. Linearity forces port-ification.
let checkReusable: (Program.program, boundary) => array<Check.witness> = (_p, _b) =>
  failwith("stub: reusability check with drawable witness — function-boundary-design.md")

// The link's measure check (joint across a cycle group when links form one).
let checkMeasure: Program.program => array<Check.witness> = _p =>
  failwith("stub: measure discipline — divide-flow-design.md, 'Termination'")

// Settled rejections (a fill-in must not reintroduce): recursion routed
// through a named function; anchor-by-value-wire in the stored program;
// functions as first-class values / closures / provider values on wires;
// functions as map/filter bodies (flows do that); the diagram as a
// scope/container (no lexical region, no capture environment); an argument
// list or tuple crossing the cut; an obligatory declared signature; a
// tagged single pair for an algebra (k lanes, never union + dispatch);
// dynamic-scope handler resolution; binding by structural match;
// respond-as-effect (the collect IS the response); "served" as a flow
// kind; correlation IDs (correspondence is provenance); memo as a mode on
// serve; an explicit-stack lowering of the divide flow; materializing the
// virtual tree; traversal-order modes; a base-case construct; the slot
// species (retired into the op pair — provisional marker noted above).
