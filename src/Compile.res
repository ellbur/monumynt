// Compile an Expr.expr to JavaScript.
//
// Strategy:
//
//   - Each Expr node compiles to one `const v_N = <rhs>;` statement, with
//     the node's "value" being a JS identifier referencing v_N.
//
//   - Sharing is detected via node identity (`expr.id`). A memo table maps
//     each id to the JsAst.expr that names its result. If a node is reached
//     more than once during traversal, only the first encounter emits a
//     binding; subsequent encounters return the same variable reference,
//     so the JS computation runs exactly once no matter how many parents
//     consume it.
//
//   - The right-hand side of the binding depends on the kind:
//       Lit(js)            → just `js`. The literal expression is bound to
//                            a name. (Even for trivial literals like `5`,
//                            we bind, so that shared literals containing
//                            non-trivial JS — say `Math.PI` or anything
//                            else — evaluate exactly once.)
//       App({fn, args})   → `fn(go(args[0]), go(args[1]), ...)` — args are
//                            recursively compiled, each contributing its
//                            own (possibly already-emitted) variable.
//
// `compileToBody` returns the sequence of statements plus the final value
// expression (the variable naming the root). `compileToIIFE` wraps that
// in `(() => { ...; return v; })()` for direct embedding or evaluation.

let compileToBody = (root: Expr.expr): (array<JsAst.stmt>, JsAst.expr) => {
  let counter = ref(0)
  let fresh = () => {
    let n = counter.contents
    counter := n + 1
    "v" ++ Int.toString(n)
  }
  let stmts: array<JsAst.stmt> = []
  let memo: Map.t<int, JsAst.expr> = Map.make()

  let rec go = (e: Expr.expr): JsAst.expr =>
    switch memo->Map.get(e.id) {
    | Some(v) => v
    | None =>
      let rhs = switch e.kind {
      | Lit(js) => js
      | App({fn, args}) =>
        let argExprs = args->Array.map(a => go(a))
        JsBuild.call(fn, argExprs)
      }
      let name = fresh()
      stmts->Array.push(JsBuild.const(name, rhs))
      let v = JsBuild.id(name)
      memo->Map.set(e.id, v)
      v
    }

  let final = go(root)
  (stmts, final)
}

let compileToIIFE = (e: Expr.expr): JsAst.expr => {
  let (stmts, value) = compileToBody(e)
  let body = [...stmts, JsBuild.ret(value)]
  JsBuild.call(JsBuild.arrow([], body), [])
}
