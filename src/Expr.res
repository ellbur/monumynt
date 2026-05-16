// Expression representation for the visual flow language.
//
// Every node carries an `id`. The id is what distinguishes nodes: two
// values whose `id` matches *are* the same node, regardless of structural
// equality on the rest of the payload. The compiler uses this to detect
// sharing — a node referenced from multiple parents is compiled exactly
// once.
//
// Smart constructors mint fresh ids from a module-local counter. To share
// a node between multiple consumers, bind it once and reuse the binding:
//
//     let x = lit(int_(5))
//     let y = app(addFn, [x, x])     // the two args are the same node
//
// Records are also constructable directly when you need a specific id
// (e.g. when ids come from a diagram serialisation):
//
//     let n: Expr.expr = {id: 42, kind: Lit(int_(5))}
//
// Node kinds:
//
//   - Lit:    a literal constant. Holds a JsAst.expr describing the JS value.
//
//   - App:    a function application. `fn` is a JsAst.expr; `args` are
//             sub-expressions in this language.
//
//   - Open:   opens a flow. `flow` describes what kind:
//               - `ListIter` — open a list for element-by-element iteration.
//               - `CaseSplit({alts, discriminator})` — open a value for
//                 case-by-case dispatch. The discriminator is a JS
//                 function `(input) => {tag, value}` that tells the
//                 compiler which alt this input belongs to and what
//                 per-alt payload to expose.
//
//             A ListIter Open has one value output (the per-iteration
//             element) and one flow output (the iteration). A CaseSplit
//             Open has *N* value outputs and *N* flow outputs (one per
//             alt). The way to refer to a specific port is via Branch.
//
//   - Close:  closes one or more flows. Carries a `branches` array, each
//             entry a {altName, flow, value} triple:
//               - For a list close: exactly one branch with altName =
//                 None, flow = the opener (an Open ListIter, possibly
//                 wrapped in Joins), value = the per-iteration
//                 expression to push.
//               - For a case close: one branch per alt with altName =
//                 Some(name), flow = a Branch node referencing the
//                 alt's flow port, value = the per-alt expression.
//
//             The kind of close is determined by the underlying Open it
//             consumes (Open ListIter ⇒ list close, Open CaseSplit ⇒
//             case close); the compiler dispatches on that.
//
//   - Join:   pure flow operation; takes a list-iteration opener and
//             returns an opener tagged "joined" — the consuming Close
//             flattens one level on output. Stacking gives more levels.
//             A Join has only a flow output port; calling `go` on one
//             raises.
//
//   - Branch: picks a specific output port from a CaseSplit Open. The
//             same Branch node serves both roles — value port (used in
//             App args, etc.) or flow port (used as a case Close's
//             branch.flow). Context determines. A Branch reached by
//             `go` outside its alt's case-close scope raises.
//
//   - Filter: pure flow operation analogous to Join, but for a
//             case-split nested inside a list flow. Wraps a Branch and
//             tells the consuming Close to push *inside that alt's
//             if-body* and put the output array at the surrounding
//             list's parent scope. Lets you express filters: only
//             elements matching the filtered alt contribute to the
//             output. Filter has only a flow output port.
//
// Currently supported flow combinations:
//   - (Open ListIter, list Close) — possibly with Joins on the opener.
//   - (Open CaseSplit, case Close) — exhaustive over the alts.
//   - (Filter(Branch(Open CaseSplit)), list-style Close) — for a
//     CaseSplit nested directly inside a ListIter; "filters" the list
//     to only the rows whose case matches the filtered alt.
//
// Other flow kinds (configuration scopes, effects, …) and richer
// combinations (commutes, joining a case-split flow, multi-filter on
// one case-split, filter under joined lists, …) will be added later.

type rec expr = {id: int, kind: kind}
and kind =
  | Lit(JsAst.expr)
  | App({fn: JsAst.expr, args: array<expr>})
  | Open({flow: openFlow, input: expr})
  | Close({branches: array<closeBranch>})
  | Join({inner: expr})
  | Branch({source: expr, alt: string})
  | Filter({inner: expr})

and openFlow =
  | ListIter
  | CaseSplit({alts: array<string>, discriminator: JsAst.expr})

and closeBranch = {
  altName: option<string>,
  flow: expr,
  value: expr,
}

// --- Identity minting ---

let nextId = ref(0)

let freshId = (): int => {
  let n = nextId.contents
  nextId := n + 1
  n
}

// --- Smart constructors ---

let lit = (js: JsAst.expr): expr => {id: freshId(), kind: Lit(js)}

let app = (fn: JsAst.expr, args: array<expr>): expr => {
  id: freshId(),
  kind: App({fn, args}),
}

let open_ = (flow: openFlow, input: expr): expr => {
  id: freshId(),
  kind: Open({flow, input}),
}

// Single-branch Close (a list close). `opener` is an Open ListIter,
// possibly wrapped in any number of Joins.
let close_ = (opener: expr, value: expr): expr => {
  id: freshId(),
  kind: Close({branches: [{altName: None, flow: opener, value: value}]}),
}

// Multi-branch Close (a case close). Each branch supplies altName, flow
// (a Branch node referencing the alt's flow port), and the per-alt
// value expression.
let caseClose = (branches: array<closeBranch>): expr => {
  id: freshId(),
  kind: Close({branches: branches}),
}

let join_ = (inner: expr): expr => {id: freshId(), kind: Join({inner: inner})}

let branch_ = (source: expr, alt: string): expr => {
  id: freshId(),
  kind: Branch({source, alt}),
}

let filter_ = (inner: expr): expr => {
  id: freshId(),
  kind: Filter({inner: inner}),
}
