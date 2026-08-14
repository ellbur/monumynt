# Implementation strategy (retired)

Status: **retired** (2026-08-12). This document was the original
map from the design record to code — five workstreams
(representation, compile pipeline, runtime, checking, text
surface), what blocked what, and a nine-phase sequencing. Roughly
seven of the nine phases are implemented, and the map's role is
carried by `src/ARCHITECTURE.md`, which records how the code is
actually shaped, the decisions taken, and the live worklist; the
remaining phases (async/incremental as new species; the deferred
placement/strictness passes) are tracked there, and the
compiler-specific half of the map remains
`compile-strategy-design.md`.

Retired rather than updated because a standing second sequencing
document is a staleness generator by construction — it described
"about the first fifth of the design record" as implemented long
after the full pipeline landed. The git history holds the
original.
