// Expression representation for the visual flow language.
//
// The language has three cooperating types:
//
//   `expr`     — nodes. Every node carries an `id` and a `kind`.
//   `valueRef` — a reference to a node's value output port:
//                `ValuePort(node, portName)`. Every value input
//                position (an App arg, an Open's input, a Close
//                branch's value) takes a `valueRef`, not a node —
//                wires point at ports. Today every node has at most
//                one value port, named "value"; per-kind port
//                inventories ("element", per-alt names) arrive with
//                the later migration steps of
//                plans/first-class-ports-design.md.
//   `flowRef`  — references to flows. Flows are stateful "scopes" (a
//                list iteration, a case-split dispatch). A `flowRef`
//                names one; consumers like Close take a `flowRef` to
//                attach to.
//
// The types are mutually recursive: a `flowRef` can wrap an `expr`
// (referring to that node's flow output port — Open ListIter's loop,
// Open CaseSplit's dispatch, or a Branch's selected alt), and an
// `expr`'s payload can mention `valueRef`s and `flowRef`s (App's args,
// Open's input, Branch picks an alt off a flow, Close's branches name
// the flow they consume and the value they collect).
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
// and `ValuePort(theNode, "value")` to refer to the value port.
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
//   - `OptionIter`                      — open an option-typed input
//                                         for zero-or-one iteration.
//                                         The input itself is the
//                                         option: `undefined` means
//                                         None, anything else is the
//                                         Some-value. (Convert other
//                                         encodings upstream via App.)
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
// same node* across references — two `valueRef`s to the same node's
// same port are the same wire source (e.g. two App args, or App-arg +
// Close.value compile to one binding referenced twice). To share, bind
// the handle once and reuse its refs:
//
//     let x = lit(int_(5))
//     let y = app(addFn, [x.value, x.value])   // both args are the
//                                              // same node's port
//
// ValueRefs and flowRefs are *not* identity-tagged. Two distinct
// `ValuePort(n, "value")` values naming the same node are the same
// wire source; two distinct `Joined(x)` values are equal-by-shape and
// compile the same way. Both are cheap structural references to the
// node (port) they name.
//
// The smart constructors return a `handle` — `{node, value}` — so
// authoring reads off the handle instead of spelling `ValuePort`:
// `x.value` for the value port, `NodeFlow(x.node)` for the flow port.
// This is the handle layer of plans/first-class-ports-design.md in
// its step-1 form; richer handles (`.flow`, `.alt(name)`) come with
// the later steps.

type rec expr = {id: int, kind: kind}
and kind =
  | Lit(JsAst.expr)
  | App({fn: JsAst.expr, args: array<valueRef>})
  | Open({flow: openFlow, input: valueRef})
  | Close({branches: array<closeBranch>})
  | Branch({source: flowRef, alt: string})

and valueRef = ValuePort(expr, string)

and openFlow =
  | ListIter
  | CaseSplit({alts: array<string>, discriminator: JsAst.expr})
  // Open an option-valued input. The input itself is the option:
  // `undefined` means None, anything else is the Some-value. The
  // body runs zero or one times. (If you have a different encoding —
  // `null`, `{tag: "Some", value}`, etc. — convert it to value-or-
  // undefined upstream via App.)
  | OptionIter

and closeBranch = {
  altName: option<string>,
  flow: flowRef,
  value: valueRef,
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

// The node a valueRef points at. (The port name becomes meaningful in
// migration step 2, when nodes grow more than one value port.)
let nodeOf = (r: valueRef): expr =>
  switch r {
  | ValuePort(node, _) => node
  }

// The handle returned by the smart constructors: the node plus a ref
// to its (single) value output port. Defined outside the `type rec`
// group so its `value` label and closeBranch's don't trip Warning 30.
type handle = {node: expr, value: valueRef}

// --- Identity minting ---

let nextId = ref(0)

let freshId = (): int => {
  let n = nextId.contents
  nextId := n + 1
  n
}

// --- Smart constructors ---

let mkHandle = (kind: kind): handle => {
  let node = {id: freshId(), kind}
  {node, value: ValuePort(node, "value")}
}

let lit = (js: JsAst.expr): handle => mkHandle(Lit(js))

let app = (fn: JsAst.expr, args: array<valueRef>): handle =>
  mkHandle(App({fn, args}))

let open_ = (flow: openFlow, input: valueRef): handle =>
  mkHandle(Open({flow, input}))

// Single-branch Close (a list close or filter close). `opener` is the
// flowRef of the flow being closed — for a list close, NodeFlow(open_)
// or Joined wrappers thereof; for a filter close, Filtered(NodeFlow(
// branch_)).
let close_ = (opener: flowRef, value: valueRef): handle =>
  mkHandle(Close({branches: [{altName: None, flow: opener, value: value}]}))

// Multi-branch Close (a case close). Each branch supplies altName, flow
// (a flowRef — typically NodeFlow of a Branch node), and the per-alt
// value ref.
let caseClose = (branches: array<closeBranch>): handle =>
  mkHandle(Close({branches: branches}))

let join_ = (inner: flowRef): flowRef => Joined(inner)

let branch_ = (source: flowRef, alt: string): handle =>
  mkHandle(Branch({source, alt}))

let filter_ = (inner: flowRef): flowRef => Filtered(inner)
