// Program editing — the cursor, atomic edits, holes, the suggestion
// surface — and its state-management companion — ARCHITECTURE STUB.
//
// Design: plans/program-editing-design.md and
// plans/editor-state-management-design.md — both EXPLORATION, but the
// editing doc is the most stub-ready in the record: the types below are
// transcribed, not invented. First vehicle: a curses-style TUI over the
// textual form; the editing MODEL is vehicle-independent and lives here.
//
// The doc's own smallest-first-step order: (1) Hole in Program.res,
// (2) src/Edit.res with the edit inventory, (3) session round-trip,
// (4) scripted sessions, (5) eligible, (6) the TUI shell. The two hard
// eligibility tiers need no property machinery and can land before
// Property.res.
//
// Integration points:
//   - Program.res: `kind` gains Hole below — representable partiality.
//     Slots must NOT become option<ref> to express missing inputs; that is
//     why Hole is a node. Dangling outputs are already legal (node set).
//     Planned wires carry NO semantics — completion never reads them, the
//     compiler never sees them.
//   - Every edit is an ATOMIC PURE FUNCTION preserving the representable
//     tier's structural invariants (refs resolve, ports in inventory,
//     sorts match, ids unique, acyclic); checked-tier properties are
//     FEEDBACK only, never gates. Refusal is whole (no clamping, no
//     auto-repair) and leaves the record unchanged, with a witness.
//   - TextParse/TextPrint: session statements (cursor at/in/on, mark, ?,
//     ~?, ..>, : slot refs) — three serialization tiers: content /
//     presentation / session; only content enters step identity.

// --- Representable partiality ---------------------------------------------

type holeSort = HoleValue | HoleFlow

// The planned Program.kind addition: a hole is a NODE standing where a
// value/flow source is not yet chosen; `planned` is the dotted planned-wire
// annotation (a remembered intention, zero semantics).
type plannedHole =
  | Hole({sort: holeSort, plannedValue: option<Program.valueRef>})

// --- The cursor and the working record ------------------------------------

// Three position sorts — deliberately NO wire sort (a wire is its consumer
// slot) and NO between-statements sort (that is a view position).
type position =
  | Top
  | OnNode({nodeId: int})
  | AtPort({nodeId: int, port: string})
  | InSlot({nodeId: int, slot: string}) // slot names per the per-kind slot
// inventory (arg[k], branch[k].value|flow, ... — mirrors Program's port
// inventories)

type workingRecord = {
  current: Program.program,
  cursor: position,
  // The mark: a single remembered output port, session-tier only. Cursor
  // and mark never enter Program.equal / step identity, and cursor motion
  // is never a history step.
  markRef: option<Program.valueRef>,
}

// --- The edit inventory ----------------------------------------------------

// A refusal witness: the edit did not apply; the record is unchanged.
type refusal = {reason: string}

// Every row of the edit inventory (value edits / flow edits / node-local
// structural edits, each with position-needed and cursor-after) is one pure
// function of this type. Three distinct deletions (consumer-free /
// delete-splice / delete-to-hole); interpose and delete-splice are mutual
// inverses.
type edit = workingRecord => result<workingRecord, refusal>

let applyEdit: (workingRecord, edit) => result<workingRecord, refusal> = (_w, _e) =>
  failwith("stub: atomic pure edit application — program-editing-design.md, 'The edit inventory'")

// --- The suggestion surface (the checker run in reverse) ------------------

// Three-tier eligibility mirroring the validity tiers; property-eligibility
// is SOFT — demote and badge, never hide a clash-inducing candidate. The
// suggester never synthesizes multi-step chains (that is search).
type eligibilityTier =
  | SortEligible // hard
  | StructurallyEligible // hard
  | PropertyEligible // soft — needs Property.res

type candidate = {
  candidateEdit: edit,
  tier: eligibilityTier,
  // ranking signals: specificity of fit, frontier discharge, observed
  // frequency
  rank: float,
}

let eligible: workingRecord => array<candidate> = _w =>
  failwith("stub: Edit.eligible — program-editing-design.md, 'The suggestion surface'")

// --- Editor state (the companion doc's types) -----------------------------
//
// Head-first working record over a step-DAG: program access is head.version,
// O(1); history hangs BEHIND the head and is never traversed by editing
// operations. The governing fiat: the from-scratch implementation is the
// DEFINITION — every mechanism must be a cache of a pure function of the
// version, droppable with no observable change but time. Derived
// computations (checking, eligibility, completion) reuse via memoization
// keyed by the step-DAG's identity discipline — constructive traces, NO
// invalidation (undo and previews are cache hits); the memo unit for cyclic
// structure is the SCC, recomputed from bottom, never warm-started from a
// previous version's solution (the named correctness trap). Cutoff equality
// must be real Program.equal-style equality, never a heuristic. Build order:
// rung 0 (no caches) first, the incremental-vs-from-scratch oracle harness
// BEFORE any memo.
//
// `step` is the transformation-levels edit/derivation step; its exact
// content is UNDESIGNED (what an undo step records, merge, cherry-pick
// replay) — an opaque placeholder here, owned by Derive.res's catalog
// architecture when it grows.
type step = OpaqueStep({description: string})

type rec historyNode = {
  builtBy: step,
  parents: array<historyNode>,
  version: Program.program,
}

type editorState = {
  head: historyNode,
  working: workingRecord,
}

// Settled rejections: a program ZIPPER (flat node set has no depth; a
// zipper puts the focus in the structure's identity — "please don't
// re-propose without a measured access-cost problem"); invalidate/stabilize
// machinery (there is no invalidation, only keying); a store holding
// anything the current version doesn't determine; per-history-node memo
// overlays (reintroduce history traversal); cursor-motion coalescing rules
// (cursor is simply not a step).
