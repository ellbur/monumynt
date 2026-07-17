// Pass 4 of the compile pipeline: the recursive, memoised, context-passing
// code generator (compile-strategy-design.md).
//
// STATUS: signature only. Programs currently reach JavaScript through
// LegacyBridge -> src/Compile.res, whose emitted shapes are this pass's
// starting spec: when this body is written, the legacy outputs become the
// golden files and the bridge is deleted.
//
// The architecture this stub pins down (so the bridge never grows into a
// second compiler):
//
//   compile : (state, context, ref) -> (state, result)
//
//   - PURE. No emission into shared mutable buffers; a compile result is a
//     record carrying the expression to reference the node by, the
//     statements it wants emitted, and the context each statement must
//     live in (let-floating: owners keep statements addressed to them and
//     float the rest upward in their own results).
//   - CONTEXT is the ordered stack of open flows on the consumer chain
//     (Context.res paths). Upstream decides the set (annotate's
//     flow-variable facts); downstream decides the order (complete's
//     verdict, handed down) — codegen itself never looks downstream.
//   - MEMO keys on (node id, context); a stored entry is reusable when its
//     context is a prefix of the requesting one (the legacy `isAncestor`
//     scan, re-plumbed). Lits memoise at the empty context. A node reached
//     in two incomparable contexts lifts to the product context as a
//     point-indexed table — that case arrives with the Cross compile and
//     must not be reachable before the checker admits products.
//   - PLACEMENT is a pure check-and-tag: a node's required context is the
//     deepest prefix of the current context covering its flow-variable
//     set; anything else is an ill-formed reference pass 1 should have
//     caught — assert here.
//   - DISPATCH is on Annotate.species, not on Program.kind, so richer
//     annotations (strictness, consumer sets, stream/async cells) change
//     emitted shapes without restructuring this pass.
//
// Runtime: the three inlined helpers (__lazy__/__lazyDone__/__force__)
// survive as the eager fragment's prelude; the prelude stops being three
// lines when stream cells land, at which point the inline-vs-imported
// packaging question (compile-strategy open question 3) must be answered.

// Target signature. `outputs` come back as named forced expressions so the
// caller (Pipeline) can wrap one or many into an IIFE / module.
type generated = {
  stmts: array<JsAst.stmt>,
  outputs: array<(string, JsAst.expr)>,
}

let codegen = (_ann: Annotate.annotations, _p: Program.program): generated =>
  failwith(
    "Codegen: not implemented — the pipeline currently compiles through " ++
    "LegacyBridge (see src/next/ARCHITECTURE.md, 'What runs today')",
  )
