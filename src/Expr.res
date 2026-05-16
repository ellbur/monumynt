// Expression representation for the visual flow language.
//
// The language has two cooperating types:
//
//   `expr`     — value-typed expressions. Every `expr` produces a value
//                that downstream consumers can use as an input.
//   `flowRef`  — references to flows. Flows are stateful "scopes" (a
//                list iteration, a case-split dispatch). A `flowRef`
//                names one; consumers like Close take a `flowRef` to
//                attach to.
//
// The two types are mutually recursive: a `flowRef` can wrap an `expr`
// (referring to that node's flow output port — Open ListIter's loop,
// Open CaseSplit's dispatch, or a Branch's selected alt), and an
// `expr`'s payload can mention a `flowRef` (Branch picks an alt off
// one; Close's branches name the flow they consume).
//
// Some nodes have *both* a value output port and a flow output port:
//   - `Open ListIter` has a flow output (the loop) and a value output
//     (the per-iteration element).
//   - `Open CaseSplit` has a flow output (the dispatch) and a value
//     output *per alt* — accessed via Branch.
//   - `Branch` has a flow output (the selected alt's flow, used as a
//     case-close's branch.flow) and a value output (the per-alt v
//     binding).
//
// For these, you say `NodeFlow(theNode)` to refer to the flow port,
// and just use the expr directly for the value port.
//
// The flow-only operations live on `flowRef` directly:
//   - `Joined(inner)`   — wraps a list-iter flow; the consuming Close
//                          flattens one level on output. Stacking gives
//                          more levels.
//   - `Filtered(inner)` — wraps a Branch flow on a CaseSplit nested in
//                          a list flow; the consuming Close pushes only
//                          when that alt fires.
//
// Open kinds:
//   - `ListIter`                       — open a list for element-by-
//                                         element iteration.
//   - `CaseSplit({alts, discriminator})` — open a value for case-by-
//                                         case dispatch. The
//                                         discriminator is a JS
//                                         function `(input) => {tag,
//                                         value}`.
//   - `OptionIter({discriminator})`     — open an option-typed input
//                                         for zero-or-one iteration.
//                                         The discriminator is a JS
//                                         function `(input) =>
//                                         value-or-undefined`. The
//                                         body runs once iff the
//                                         result is not undefined.
//
// Close kinds. Determined by the shape of `branches[0].flow`:
//   - A `NodeFlow(branchExpr)` (where branchExpr is a Branch node) —
//     case close; each branch is `{altName=Some, flow=NodeFlow(branch),
//     value}`; exhaustive over the case-split's alts.
//   - A `Filtered(...)` — filter close; one branch with `altName=None`,
//     `flow=Filtered(NodeFlow(branch))`, `value` pushed only in that
//     alt's body. Multiple filter closes can share one case-split.
//   - Anything else (NodeFlow(opener) or Joined(...) wrappers thereof)
//     — list close; one branch with `altName=None`, `flow` is the
//     opener flowRef (possibly Joined-wrapped), `value` is the per-
//     iteration push expression.
//
// Every `expr` carries an `id`. Identity is what makes a node *the
// same node* across references — two value-position uses of the same
// `expr` (e.g. two App args, or App-arg + Close.value) compile to one
// binding referenced twice. To share, bind once and reuse:
//
//     let x = lit(int_(5))
//     let y = app(addFn, [x, x])     // both args are the same node
//
// FlowRefs are *not* identity-tagged. Two distinct `Joined(x)` values
// are equal-by-shape and compile the same way; they're cheap
// structural wrappers around the underlying flow they name.

type rec expr = {id: int, kind: kind}
and kind =
  | Lit(JsAst.expr)
  | App({fn: JsAst.expr, args: array<expr>})
  | Open({flow: openFlow, input: expr})
  | Close({branches: array<closeBranch>})
  | Branch({source: flowRef, alt: string})

and openFlow =
  | ListIter
  | CaseSplit({alts: array<string>, discriminator: JsAst.expr})
  // Open an option-valued input. `discriminator` is a JS function
  // `(input) => value-or-undefined` — undefined means None, anything
  // else means Some(value). The body runs zero or one times.
  | OptionIter({discriminator: JsAst.expr})

and closeBranch = {
  altName: option<string>,
  flow: flowRef,
  value: expr,
}

and flowRef =
  // Refers to the flow output port of an expr. Valid when the expr is
  // a node that has a flow output port (Open, Branch). If the expr is
  // a value-only node (Lit, App, Close), the compile will raise.
  | NodeFlow(expr)
  // Wraps a list-iter flow; the consuming list-style Close flattens one
  // level on output. Stacking gives more levels of flatten.
  | Joined(flowRef)
  // Wraps a Branch flow (on a CaseSplit nested in a list); the
  // consuming list-style Close pushes inside the matching alt's body
  // and puts the output array at the surrounding list's parent scope.
  | Filtered(flowRef)

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

// Single-branch Close (a list close or filter close). `opener` is the
// flowRef of the flow being closed — for a list close, NodeFlow(open_)
// or Joined wrappers thereof; for a filter close, Filtered(NodeFlow(
// branch_)).
let close_ = (opener: flowRef, value: expr): expr => {
  id: freshId(),
  kind: Close({branches: [{altName: None, flow: opener, value: value}]}),
}

// Multi-branch Close (a case close). Each branch supplies altName, flow
// (a flowRef — typically NodeFlow of a Branch node), and the per-alt
// value expression.
let caseClose = (branches: array<closeBranch>): expr => {
  id: freshId(),
  kind: Close({branches: branches}),
}

let join_ = (inner: flowRef): flowRef => Joined(inner)

let branch_ = (source: flowRef, alt: string): expr => {
  id: freshId(),
  kind: Branch({source, alt}),
}

let filter_ = (inner: flowRef): flowRef => Filtered(inner)
