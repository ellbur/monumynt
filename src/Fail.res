// Failure payloads — the fail node, the endings inventory, the JS edge
// stance, and the discharge barrier — ARCHITECTURE STUB.
//
// Design: plans/failure-payloads-design.md — ADOPTED (2026-07-23): the fail
// node (with the ontology note and the commute-completion ruling), the edge
// stance with the background-super-flow amendment, and the inventory
// account. Plus plans/barrier-value-crossing-design.md corner 4 (resolved):
// the one-closer discharge MINTS OUTCOME CELLS directly.
// RESIDUE owing a worked round: tag identity across reuse boundaries
// (leaning: a tag is scoped to its minting diagram unless deliberately
// shared through a signature).
//
// The three-verb table this node completes (all binary flow operations with
// asymmetric (subject, alt-flow) operands):
//
//   join (filter) | firings where the alt fires
//   end-when      | firings before the first alt firing; ends Stopped(v)
//   fail          | firings before the first alt firing; ends Fail(e)
//
// fail is a SIBLING node of end-when, not a tag parameter on it: it has NO
// inclusive/exclusive bit (the cut is always exclusive — a failing firing
// has no value to keep), and its everyday reading differs (a fail's collect
// usually binds nothing and propagates). Ontology: fail is the MINTING half
// of the applicative sequence, whose commute half is the propagating
// whole-flow close. In a once-firing context it derives the failable value.
//
// Integration points:
//   - Program.res: `kind` gains Fail below; the discharging Collect grows
//     outcome cells (see the discharge section).
//   - Check.res: exhaustive discharge = alt matching against the derived
//     inventory (missing lane = clash, dead lane = advisory).
//   - Annotate.res or a sibling pass: the inventory computation below.
//   - Property.res: catalog rows carry declared throw lanes (throwability
//     is part of what a row asserts; declared throws are lanes, the row is
//     their minting site).
//   - Codegen.res: bodies are TOTAL — no ambient try/catch is ever emitted;
//     collecting the background super flow is drawn and compiles to a
//     try/catch around the collected region.

type plannedFail =
  | FailOp({subject: Program.flowRef, bad: Program.flowRef})

// --- The endings inventory (a DERIVED analysis, not a node) ---------------
//
// A lane is a set of MINTING SITES grouped by tag — "not a type and not an
// exception class; a set of places in the program". The inventory derivable
// at any consumer is computed by the same monotone propagation as every
// other property (Property.res): union at stacking, nesting, and chained
// closes; no coercion, no subset-to-superset conversion (Zig's error-set
// algebra is what the substrate computes, not what the user manipulates).
// The fixpoint is finite, including over a divide-flow link cycle (monotone
// over the powerset of the finitely many drawn sites). A flow is failable
// iff its derived inventory is nonempty. Every lane carries its WITNESS —
// a walkable path back to its minting sites. Payload shapes ride the lanes;
// where one tag's sites disagree on shape, the shape property is simply
// absent. Payload mapping is drawn where meaning changes (discharge,
// transform, re-fail).
type mintingSite =
  | FailSite({nodeId: int})
  | EndWhenSite({nodeId: int}) // Stopped + payload
  | InterruptSite({nodeId: int}) // Interrupted(e)
  | CatalogRowSite({rowName: string}) // a declared-throw / failable row
  | StrandSite // Cancelled — the one non-drawn site; no payload
  | BareEnd // Nil / RanOut — the subject's own end

type lane = {tag: string, sites: array<mintingSite>}

let inventory: (Program.program, Program.flowRef) => array<lane> = (_p, _f) =>
  failwith("stub: endings inventory — failure-payloads-design.md, 'The terminator inventory' (monotone fixpoint over drawn minting sites)")

// --- The JS edge stance + the background super flow -----------------------
//
// Bodies are total; program raises are DRAWN (one Fail node per raise
// site). Declared throws convert by catalog row. An UNDECLARED throw is an
// edge breach, quarantined (not excluded): it lands on the BACKGROUND SUPER
// FLOW — distinguished, runtime-owned; silently commutes out of everything
// and joins with itself (all background failures are ONE flow); absent from
// ordinary inventories; its silent commutes are never rendered (the one
// recognized boundary of the commute-completion ruling — no lawful
// alternative exists, so drawing it carries zero information); always
// nameable and collectable (availability-as-addressability); payload = the
// caught JS value, one lane, no shape. Attribution kept: the firing carries
// WHICH ROW LIED. Owed edges: the collect's region anchor (likely the
// necessity-frontier vocabulary); the async face; whether Cancelled and the
// super flow share machinery.
//
// The commute-completion ruling (general, not failure-specific): an
// implicitly inferred commute is time travel — it must be inferred by
// published rule AND available for the author to see, faint, never merely
// absent. The IO commute is mandatory and unique; the ERROR commute is a
// genuine choice, which is precisely why it must be visible.

// --- The discharge barrier (barrier-value-crossing corner 4) --------------
//
// Governing principle: when a loop's result has one consumer, ONE construct
// closes the loop flow. The discharging collect's discharge half mints
// OUTCOME CELLS directly — a bundle with one cell per lane of the flow's
// derived inventory PLUS the bare-end cell. The `terminator` value output
// DOES NOT EXIST; `=> prefix, term` + split is demoted to the packed
// interim spelling/lowering (a level-1 recognition candidate). The cells
// ARE the split; exhaustiveness = the inventory check (the closer's cell
// set must match the derived inventory; an unwired cell is an unhandled
// lane). The folded value is an OPTIONAL SIBLING output, readable inside
// the cells by availability. The exactly-one kind re-reads the same way:
// success and failure cells, the success cell minting the resolved value —
// no settled-sum output.
//
// Owed details (do not decide in a fill-in without the round): authored
// site->closer inputs vs cells derived from the inventory with viewable
// witnesses; per-site or per-tag cells; the bare-end cell's exact form;
// whether the super flow and Cancelled can feed it where collected.
let checkDischargeExhaustive: Program.program => array<Check.witness> = _p =>
  failwith("stub: discharge exhaustiveness = inventory match — failure-payloads-design.md + barrier-value-crossing-design.md corner 4")

// --- Settled rejections (a fill-in must not reintroduce) ------------------
//
//   - Ambient bodies-raise (auto-converting throws kills the inventory).
//   - Nominal payload types with coercion; mandatory declared sets at
//     boundaries (pinning is a choice, checked both ways when pinned).
//   - One dynamic catch-all payload as the model (survives only as the
//     super flow's floor lane).
//   - Cause-chain wrapping as vocabulary (provenance is derived).
//   - A packed Ok(x)|Bad(e) flow fed to a drawn commute (the sum bottleneck
//     in sequence's clothes).
//   - An inclusive/exclusive bit on fail; fail as a tag parameter on
//     end-when.
//   - A (prefix, terminator) TUPLE output (product bottleneck); the absorb
//     collect (error-swallowing total fold); a settled-sum output on the
//     exactly-one discharge.
