// Expression representation for the visual flow language (minimal first
// cut, with explicit node identity).
//
// Every node carries an `id`. The id is what distinguishes nodes: two
// values whose `id` matches *are* the same node, regardless of structural
// equality on the rest of the payload. The compiler uses this to detect
// sharing — a node referenced from multiple parents is compiled exactly
// once.
//
// Smart constructors `lit` and `app` mint a fresh id from a module-local
// counter. To share a node between multiple consumers, bind it once and
// reuse the binding:
//
//     let x = lit(int_(5))
//     let y = app(addFn, [x, x])     // the two args are the same node
//
// To express deliberate non-sharing — two structurally identical but
// distinct values — call the smart constructor twice:
//
//     let y = app(addFn, [lit(int_(5)), lit(int_(5))])  // two distinct ids
//
// Records are also constructable directly when you need a specific id
// (e.g. when ids come from a diagram serialisation):
//
//     let n: Expr.expr = {id: 42, kind: Lit(int_(5))}
//
// Two kinds of nodes for now:
//
//   - Lit: a literal constant. Holds a JsAst.expr describing the JS value
//          the constant denotes (any constant JS expression is acceptable).
//
//   - App: a function application. The function being invoked is specified
//          directly as a JsAst.expr (typically an identifier or member
//          access); the arguments are sub-expressions in this language.
//
// Flows are not yet represented.

type rec expr = {id: int, kind: kind}
and kind =
  | Lit(JsAst.expr)
  | App({fn: JsAst.expr, args: array<expr>})

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
