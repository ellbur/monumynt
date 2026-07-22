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
