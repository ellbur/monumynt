// Focused update — transform selected loci of a nested value, preserving
// the rest — ARCHITECTURE STUB.
//
// Design: plans/focused-update-design.md — EXPLORATION (a leaning, not a
// decision). The one real structural artifact is the GETTER -> SETTER
// MIRROR TABLE: a structural selection is read as a round trip, and the
// write-back is FULLY DETERMINED BY THE PATH — the setter is a derived
// view of the getter, never separately authored. Loci are fixed by shape
// BEFORE any atom is read (the commuting law holds because loci don't move
// when contents change).
//
// The load-bearing rule: focused update BY PREDICATE is a CASE SPLIT WITH
// AN IDENTITY BRANCH, NEVER A FILTER — filter discharges the provenance
// that names the unselected positions. Multi-locus is the base; the single
// locus is the degenerate once-firing flow. Conflicts: disjoint by
// construction for structural paths; last-most wins for the multi-path fan
// (scatter filed as a named sub-case, not part of the base).
//
// Integration points:
//   - The getter stages already exist as nodes (Uncollect list, Disaggregate
//     field, Uncollect case); the NEW pieces the drawn vocabulary does not
//     yet emit are the two setter-side forms: record projection as a lens
//     setter ({...rec, field: v} — an Aggregate-with-spread) and the
//     MIRROR COLLECT (exhaustive, order/length/sibling-preserving).
//   - Open (do not harden): whether the path is a first-class value or only
//     a chain shape read two ways (co-location wants to know which node the
//     mirror hangs on); the write-back collect's spelling; the reversible-
//     view catalog. The compact spellings (`|=`, `->*`) COLLIDE with
//     reserved glyphs — sketches only, never parseable text.

// A path stage and its mirror (the table: open list <-> exhaustive list
// collect; .field <-> spread-update; split <-> exhaustive case collect;
// reversible views — reshape/transpose/reverse — admissible because each
// has a known inverse; per-view catalog deferred).
type pathStage =
  | OpenListStage
  | FieldStage({field: string})
  | SplitStage({alts: array<string>, selected: string}) // identity branch
  // on the unselected alts — never a filter
  | ViewStage({viewName: string}) // must carry a known inverse

// The derived write-back for one stage — the mirror read off the table.
type setterStage =
  | ExhaustiveListCollect // preserves order and length
  | SpreadUpdate({field: string}) // preserves siblings
  | ExhaustiveCaseCollect // preserves untouched alts
  | InverseView({viewName: string})

let mirror: array<pathStage> => array<setterStage> = _path =>
  failwith("stub: the getter->setter mirror — focused-update-design.md, 'the mirror table'")

// Delta output (later): a touched-loci flow emitted beside the result
// (Immer patches); update loci double as invalidation keys for the
// incremental layer.
//
// Settled rejections: a separate update-side setter DSL; value-dependent
// selection as a filter; scalar single-locus as the base; a live probe
// evaluated during write-back (loci are data before any write);
// materializing the virtual recursion tree; walk-style recursive deep
// rewrite here (that is the divide flow's lift — this round is fixed-depth
// only).
