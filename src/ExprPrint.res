// Human-readable rendering of Expr.expr for test logs and debugging.
//
// Format: time-forward (inputs first), flat (no nesting), one statement
// per line. Each statement either kicks off a chain from a literal or
// from one or more labelled inputs:
//
//     [[1, 2], [3]] -> open -> open (#1) -> join (#2)
//     #1 -> (x => x + 1) (#3)
//     #2, #3 -> close (#4)
//     #1, #3 -> close (#5)
//     #4, #5 -> ((a, b) => ({flat: a, nested: b}))
//
// Each value the program computes maps to a node, and each node ends up
// somewhere in the rendering. Single-input ops chain together when the
// data flow is straightforward — `<source> -> op1 -> op2 -> …` — so a
// short pipeline shows up on one line. Multi-input ops (Close, App with
// more than one arg) start a fresh line and list their inputs as the
// source.
//
// Labels (`#1`, `#2`, …) are assigned per-render in encounter order
// and only to nodes that are referenced from a different chain than
// their own. Single-use values consumed within their chain don't need
// a label.
//
// Trivial inlining: a Lit whose only consumer is a single (different-
// chain) node is inlined directly into that consumer's source list,
// instead of being given its own line. So `2, 3 -> add` rather than
// `2 (#1)` / `3 (#2)` / `#1, #2 -> add`. A Lit with multiple consumer
// nodes still gets a label, since the sharing matters.
//
// JsAst.expr payloads (Lit values, App fns) are rendered inline by
// JsPrint without any wrapping syntax — the JS code stands on its own.

// Topological sort: each node appears after all its dependencies.
let topoSort = (root: Expr.expr): array<Expr.expr> => {
  let result: array<Expr.expr> = []
  let visited: Map.t<int, bool> = Map.make()
  let rec visit = (e: Expr.expr) =>
    if !(visited->Map.has(e.id)) {
      visited->Map.set(e.id, true)
      switch e.kind {
      | Lit(_) => ()
      | App({args}) => args->Array.forEach(visit)
      | Open({input}) => visit(input)
      | Close({opener, value}) =>
        visit(opener)
        visit(value)
      | Join({inner}) => visit(inner)
      }
      result->Array.push(e)
    }
  visit(root)
  result
}

// The (immediate) inputs of a node, in source order.
let inputsOf = (e: Expr.expr): array<Expr.expr> =>
  switch e.kind {
  | Lit(_) => []
  | App({args}) => args
  | Open({input}) => [input]
  | Close({opener, value}) => [opener, value]
  | Join({inner}) => [inner]
  }

// Greedy chain detection: walking the topo-sorted nodes, a 1-input op
// extends the current chain when its input is the previous chain
// element. Anything else starts a fresh chain.
let computeChains = (sorted: array<Expr.expr>): array<array<Expr.expr>> => {
  let chains: array<array<Expr.expr>> = []
  let current: ref<array<Expr.expr>> = ref([])
  let canChain = (n: Expr.expr, prev: Expr.expr): bool => {
    let ins = inputsOf(n)
    Array.length(ins) == 1 && (ins->Array.getUnsafe(0)).id == prev.id
  }
  sorted->Array.forEach(n => {
    let chainable = switch current.contents->Array.last {
    | Some(prev) => canChain(n, prev)
    | None => false
    }
    if chainable {
      current.contents->Array.push(n)
    } else {
      if Array.length(current.contents) > 0 {
        chains->Array.push(current.contents)
      }
      current := [n]
    }
  })
  if Array.length(current.contents) > 0 {
    chains->Array.push(current.contents)
  }
  chains
}

let render = (root: Expr.expr): string => {
  let sorted = topoSort(root)
  let chains = computeChains(sorted)

  // chainIdxOf: node id → index of its chain.
  let chainIdxOf: Map.t<int, int> = Map.make()
  chains->Array.forEachWithIndex((chain, i) =>
    chain->Array.forEach(n => chainIdxOf->Map.set(n.id, i))
  )

  // consumersOf: input id → unique consumer ids that reference it.
  let consumersOf: Map.t<int, array<int>> = Map.make()
  sorted->Array.forEach(consumer =>
    inputsOf(consumer)->Array.forEach(input => {
      let arr = switch consumersOf->Map.get(input.id) {
      | Some(arr) => arr
      | None =>
        let arr = []
        consumersOf->Map.set(input.id, arr)
        arr
      }
      if !(arr->Array.includes(consumer.id)) {
        arr->Array.push(consumer.id)
      }
    })
  )

  // A Lit with exactly one consumer (a single distinct parent), where
  // that consumer is on a different chain, gets inlined into that
  // consumer's source list rather than getting its own line and label.
  let inlineable: Map.t<int, bool> = Map.make()
  sorted->Array.forEach(n =>
    switch n.kind {
    | Lit(_) =>
      let cons = consumersOf->Map.get(n.id)->Option.getOr([])
      if Array.length(cons) == 1 {
        let myChain = chainIdxOf->Map.get(n.id)
        let consChain = chainIdxOf->Map.get(cons->Array.getUnsafe(0))
        if myChain != consChain {
          inlineable->Map.set(n.id, true)
        }
      }
    | _ => ()
    }
  )

  // A node needs a label iff some consumer of it lives on a different
  // chain AND it isn't being inlined.
  let needsLabel: Map.t<int, bool> = Map.make()
  sorted->Array.forEach(consumer => {
    let consumerChain = chainIdxOf->Map.get(consumer.id)
    inputsOf(consumer)->Array.forEach(input => {
      if (
        chainIdxOf->Map.get(input.id) != consumerChain &&
          !(inlineable->Map.has(input.id))
      ) {
        needsLabel->Map.set(input.id, true)
      }
    })
  })

  // Label assignment, in encounter order.
  let labelFor: Map.t<int, string> = Map.make()
  let nextLabel = ref(1)
  let getLabel = (id: int): string =>
    switch labelFor->Map.get(id) {
    | Some(l) => l
    | None =>
      let l = "#" ++ Int.toString(nextLabel.contents)
      nextLabel := nextLabel.contents + 1
      labelFor->Map.set(id, l)
      l
    }

  // Op token (just the operation name, or the JS payload for Lit/App).
  let opToken = (e: Expr.expr): string =>
    switch e.kind {
    | Lit(js) => JsPrint.printExpr(js)
    | App({fn}) => JsPrint.printExpr(fn)
    | Open(_) => "open"
    | Close(_) => "close"
    | Join(_) => "join"
    }

  // The op-token possibly followed by `(#N)` if labelled.
  let renderOp = (e: Expr.expr): string => {
    let base = opToken(e)
    if needsLabel->Map.has(e.id) {
      base ++ " (" ++ getLabel(e.id) ++ ")"
    } else {
      base
    }
  }

  // How to refer to a node from another chain's source list: either an
  // inlined Lit value, or a label.
  let referenceTo = (e: Expr.expr): string =>
    if inlineable->Map.has(e.id) {
      opToken(e)
    } else {
      getLabel(e.id)
    }

  // Whether to emit a chain at all. A singleton chain whose only node
  // is being inlined elsewhere doesn't need its own line.
  let shouldEmit = (chain: array<Expr.expr>): bool =>
    !(Array.length(chain) == 1 && inlineable->Map.has((chain->Array.getUnsafe(0)).id))

  let renderChain = (chain: array<Expr.expr>): string => {
    let head = chain->Array.getUnsafe(0)
    let opStrs = chain->Array.map(renderOp)
    let opChain = opStrs->Array.join(" -> ")
    switch inputsOf(head) {
    | [] =>
      // 0-input head (a Lit). The op-token IS the chain start.
      opChain
    | inputs =>
      let source = inputs->Array.map(referenceTo)->Array.join(", ")
      source ++ " -> " ++ opChain
    }
  }

  chains
  ->Array.filter(shouldEmit)
  ->Array.map(renderChain)
  ->Array.join("\n")
}
