// Pass 0 of the compile pipeline: derive — run level-1 structure down to
// level-0 (transformation-levels-design.md; compile-strategy-design.md,
// "Multi-level programs").
//
// v0 is the identity, and honestly so: no abstract node species exist in
// the representation yet, so every program is already level-0 and is its
// own derivation (the conservativity property the real pass must keep).
//
// The architecture the real pass must honour, when the first catalog entry
// (reduce-close) arrives:
//
//   - A CATALOG of abstract species, each entry a pattern -> expansion ->
//     port correspondence. Derive replaces each abstract node with its
//     expansion and rewires consumers through the correspondence.
//   - Expansions may contain abstract nodes; derive RECURSES until the
//     program is level-0 ("run" lowers by exactly one level).
//   - Manufactured nodes get DETERMINISTIC COMPOSITE IDS — (host node id,
//     expansion-internal name), never a counter — so the same program
//     derives to the identical core every time. These ids are
//     compile-internal; nothing leaks into the program of record.
//   - Alongside the core, derive returns an ORIGINS MAP from manufactured
//     nodes back to (authored node, internal name), so a witness Check
//     finds in derived structure remains addressable to the authored
//     program. When this pass grows a body, its return type grows that map
//     and Pipeline threads it into Check's witness rendering.
//   - The history never enters here: derive is a function of one version's
//     node set, not of the step-DAG.

let derive = (p: Program.program): Program.program => p

// --- The catalog architecture (ARCHITECTURE STUBS) -------------------------
//
// Staged types for the header's record, so the first entry (reduce-close,
// which rides the collect-family round — CollectFamily.res owns its
// availability semantics) lands against a shape instead of a comment.
// transformation-levels-design.md is EXPLORATION and a reach goal; only
// this compiler-facing slice is planned here. The step-DAG storage half
// (undo, cherry-pick, merge — and the `step` type's real content) is NOT on
// the compilation path and waits for a reason to exist in code; what must
// be protected meanwhile is determinism and the id discipline only.

// A reference to a port of a derived (expansion-internal) node, written
// nodeId!portName. Resolves against the expansion's SHAPE (structural,
// cheap; values force lazily), and portName is drawn from the entry's
// declared principal ports — an ill-formed ref is unrepresentable, not
// checked. DerivedPort must never reach derivation internals beyond the
// declared list.
type derivedPort = DerivedPort({hostNodeId: int, portName: string})

// The catalog entry, three fields plus the principal-port declaration.
// Two invocation modes consume it: LENS (automatic, always-on, read-only,
// principal ports only) and MATERIALIZE (a recorded step, all expansion
// nodes addressable) — the difference is addressability, not mutability.
// Settled rejections the shape must keep: no editable lowerings /
// bidirectional update; no per-level stored readings (store only the
// non-degenerate core); no user-authored level-1 operations (the catalog
// is built-in); a conversion is a directional computation run on demand,
// not a witness object holding both forms in sync.
type catalogEntry = {
  // the pattern: which abstract node species this entry runs down
  speciesName: string,
  // the expansion: level-0 structure; manufactured nodes carry the
  // deterministic composite ids the header describes
  expand: Program.node => array<Program.node>,
  // the port correspondence: abstract port -> expansion port. Read forward
  // it rebuilds consumers; read in reverse it is what makes conversions
  // cherry-pickable.
  portCorrespondence: array<(string, derivedPort)>,
  // the only ports a DerivedPort may name
  principalPorts: array<string>,
}

// The inaugural entry: reduce-close (fully specified down to the port list
// in transformation-levels-design.md — uncollect U with seed, step, and the
// exposing collect). Its operator-identity demand reads the catalog row
// (Property.res / CollectFamily.res).
let reduceCloseEntry: unit => catalogEntry = () =>
  failwith("stub: reduce-close, the first catalog species — transformation-levels-design.md")
