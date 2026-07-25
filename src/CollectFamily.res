// The collect family — the availability ladder, the empty collect, and the
// keyed partition — ARCHITECTURE STUB.
//
// Design: plans/collect-family-design.md — MIXED: the AVAILABILITY LADDER
// is ADOPTED (2026-07-23); spellings and the keyed collect are still
// exploration.
//
// The adopted framing: THE IDENTITY QUESTION IS THE EMPTY-COLLECT QUESTION
// — the empty-collect value is the only thing an identity is for.
//
// Integration points:
//   - Property.res: classification lives on the operator's CATALOG ROW
//     (property `associative`, or `associative + has-identity(v)` where the
//     identity VALUE is the witness — the offer that unlocks a total
//     reduce-close is exactly the value the empty collect yields). Nothing
//     is a node property; nothing is annotated in programs. User extension
//     is an algebra facet minting a catalog row — authored and trusted,
//     NEVER inferred or verified (associativity is a theorem, not a
//     propagatable property; no search).
//   - Check.res / Annotate.res: a reduce-close node DEMANDS `associative`
//     (and `has-identity` if its output is consumed as total).
//   - Derive.res: reduce-close is the first catalog species; named collects
//     (`collect set`, any, all, last, min/max, `by <op>`) are catalog ROWS,
//     not node species (a separate dedup node is a settled dead end).
//   - Codegen.res: the empty-collect emit reads the ladder.

// The availability ladder — what a reduce-close may yield, read off the
// operator's catalog row:
type availability =
  // Associative with identity (monoid: + 0, * 1, and true, or false,
  // ++ [], set-union {}): reduce-close available, output TOTAL; the empty
  // flow yields the identity witness.
  | TotalCollect
  // Associative without identity (semigroup: first, last, min, max):
  // reduce-close available, output OPTION-SHAPED — fires iff the flow had
  // at least one firing.
  | OptionShaped
  // Not associative: NO reduce-close. Fall back to the AUGMENT — explicit
  // seed, explicit asymmetry. A supplied seed is not a parameter of the
  // reduce-close; it is a CHANGE OF CONSTRUCT (no third form exists;
  // per-use empty values on the collect are a settled dead end).
  | AugmentOnly

let classify: Property.catalogRow => availability = _row =>
  failwith("stub: ladder classification off the catalog row — collect-family-design.md, 'The availability ladder'")

// Filed TODO (simplify) from the doc: when an augment's step is a catalog
// monoid applied symmetrically, seed the augment from the catalog and
// reserve authored seeds for genuinely asymmetric S x E -> S steps.

// --- The keyed partition (EXPLORATION — shape only) -----------------------
//
// The primary construct is the PARTITION, not "a collect that builds a
// map": in = subject flow + a per-firing key computed by ordinary drawn
// code; out = a two-level nesting — an outer LANES flow (one firing per
// distinct key, the key riding as a per-lane value wire) + an inner
// WITHIN-LANE flow. Every non-key wire crosses as itself. Cells are
// DATA-DETERMINED (exist at runtime, per key seen); one sub-diagram is
// drawn against the within-lane flow and instantiated per lane — per-cell
// wiring is a settled dead end ("uniform wiring over dynamic cells;
// distinct wiring over static alts").
//
// Interactions: a lane is never empty, so semigroup operators are TOTAL in
// keyed position; the keyed collect as a whole is its own monoid fold with
// identity {} (seedable: `collect keyed from seedMap by add`, the seed an
// ordinary value input outside the flow). Collisions dissolve into ordinary
// multi-firing lanes (collision-as-error and silent last-wins are both dead
// ends); lane order leaning: first appearance.
type plannedKeyedPartition =
  | KeyedPartition({subject: Program.flowRef, key: Program.valueRef})

// The four readouts of a partition (an enum of derived consumers, not node
// species): collapse (the keyed collect proper), pass-through (per-firing
// readout in subject order), flatMap, whole-lane engagement (partial
// engagement at the lanes flow). Plus lane-as-value (a re-openable
// sub-list).
type keyedReadout = Collapse | PassThrough | FlatMap | WholeLane

// Settled rejections (do not reintroduce): runtime error on empty for
// identity-less operators (the DOMAIN ERROR pole); -inf/+inf as fake
// identities for min/max (representation artifacts); inferring or
// verifying associativity; per-use empty values on the collect; a separate
// dedup node; per-cell wiring of a keyed partition; `mean` as a
// reduce-close (it is not one — blessed-names open question).
