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
//   - Lit:   a literal constant. Holds a JsAst.expr describing the JS value.
//
//   - App:   a function application. `fn` is a JsAst.expr; `args` are
//            sub-expressions in this language.
//
//   - Open:  opens a flow. `flow` describes how the flow is opened (currently
//            only `ListIter` — open a list for element-by-element iteration).
//            `input` is the value being opened (currently a list).
//
//            An Open's "value" is the per-iteration current element. That
//            value is only meaningful inside the corresponding Close's
//            `value` subtree. Referencing an Open from anywhere else is an
//            error and the compiler will fail.
//
//   - Close: closes a flow. `opener` must be an opener-shaped node — an
//            Open, or an Open wrapped in one or more Joins. The Close's
//            `flow` (currently only `ListCollect`) must be compatible
//            with the underlying Open's. `value` is the per-iteration
//            expression whose results are accumulated; the Close's
//            overall value is the collected list (flattened by N levels
//            if its opener is wrapped in N Joins).
//
//   - Join:  pure flow operation; takes an opener and returns an opener.
//            Conceptually `join : flow → flow`. Doesn't touch values.
//            Wrapping an opener in `Join` (and stacking gives more
//            levels) tells the consuming Close that its output array
//            should be allocated one level higher per Join — so a
//            `Close(Join(Open(Open(input))), …)` collects the
//            inner-elements into one flat list rather than a list of
//            lists. The loops are still nested; only the output
//            placement changes.
//
//            A Join has no value output port. Calling `go` on a Join is
//            meaningless and the compiler raises if it ever happens.
//
// Only the (Open ListIter, Close ListCollect) flow combination is
// supported by the compiler at the moment. Future flow kinds (case
// splits, configuration scopes, effects, …) and richer combinations
// (commutes, mixed-join multi-close groups, …) will be added later.

type rec expr = {id: int, kind: kind}
and kind =
  | Lit(JsAst.expr)
  | App({fn: JsAst.expr, args: array<expr>})
  | Open({flow: openFlow, input: expr})
  | Close({flow: closeFlow, opener: expr, value: expr})
  // Pure flow operation: wraps an opener (Open or another Join) in a
  // "joined" tag. Has only a flow output port — no value output port —
  // so a Join is meaningful only as the `opener` field of a Close.
  // Calling the compiler's `go` on a Join raises (it would be using a
  // flow wire as a value, which is meaningless).
  | Join({inner: expr})

and openFlow =
  | ListIter

and closeFlow =
  | ListCollect

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

let close_ = (flow: closeFlow, opener: expr, value: expr): expr => {
  id: freshId(),
  kind: Close({flow, opener, value}),
}

let join_ = (inner: expr): expr => {id: freshId(), kind: Join({inner: inner})}
