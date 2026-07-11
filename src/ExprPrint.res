// Human-readable rendering of Expr.expr for test logs and debugging.
//
// Format: time-forward (inputs first), flat (no nesting), one statement
// per line. Single-input ops chain together with `->`; multi-input ops
// list their inputs at the start of a line and produce one new value.
//
// FlowRefs (Joined, Filtered) are written as postfix `-> join` and
// `-> filter` on the underlying flow's source; they don't have ids,
// so no `#N` labels.
//
// Close renders as `close`. The source list distinguishes the
// styles:
//   - List close:   `<flow>, <value>` — the (flow, value) pair.
//   - Case close:   `Just: <flow>/<value>, Nothing: <flow>/<value>, …`
//                   — one labelled (alt: flow/value) per branch.
//
// Open kinds:
//   - ListIter → `open`
//   - CaseSplit({alts, discriminator}) → `caseSplit({alts}, <disc>)`
//
// Branches are rendered as `.<altName>` (a single-input op that picks
// an alt off its source flow).
//
// Sharing: nodes referenced from a different chain than their own get
// labels `#1`, `#2`, … (renumbered per-render in encounter order).
// Trivially-used literals are inlined into their consumer's source list.

// Collect every expr reachable from a flowRef.
let rec flowRefExprs = (fr: Expr.flowRef): array<Expr.expr> =>
  switch fr {
  | NodeFlow(e) => [e]
  | Joined(inner) => flowRefExprs(inner)
  | Filtered(inner) => flowRefExprs(inner)
  }

let topoSort = (root: Expr.expr): array<Expr.expr> => {
  let result: array<Expr.expr> = []
  let visited: Map.t<int, bool> = Map.make()
  let rec visit = (e: Expr.expr) =>
    if !(visited->Map.has(e.id)) {
      visited->Map.set(e.id, true)
      switch e.kind {
      | Lit(_) => ()
      | App({args}) => args->Array.forEach(r => visit(Expr.nodeOf(r)))
      | Open({input}) => visit(Expr.nodeOf(input))
      | Close({branches}) =>
        branches->Array.forEach(b => {
          flowRefExprs(b.flow)->Array.forEach(visit)
          visit(Expr.nodeOf(b.value))
        })
      | Branch({source}) => flowRefExprs(source)->Array.forEach(visit)
      }
      result->Array.push(e)
    }
  visit(root)
  result
}

// The (immediate) Expr inputs of a node, in source order. For Close,
// this is a flat sequence: branch[0].flow's exprs, branch[0].value,
// branch[1].flow's exprs, branch[1].value, … For Branch it's the
// source flowRef's exprs.
let inputsOf = (e: Expr.expr): array<Expr.expr> =>
  switch e.kind {
  | Lit(_) => []
  | App({args}) => args->Array.map(Expr.nodeOf)
  | Open({input}) => [Expr.nodeOf(input)]
  | Close({branches}) =>
    branches->Array.flatMap(b =>
      Array.concat(flowRefExprs(b.flow), [Expr.nodeOf(b.value)])
    )
  | Branch({source}) => flowRefExprs(source)
  }

// Greedy chain detection.
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

  let chainIdxOf: Map.t<int, int> = Map.make()
  chains->Array.forEachWithIndex((chain, i) =>
    chain->Array.forEach(n => chainIdxOf->Map.set(n.id, i))
  )

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

  // Op token (just the operation's name/payload).
  let opToken = (e: Expr.expr): string =>
    switch e.kind {
    | Lit(js) => JsPrint.printExpr(js)
    | App({fn}) => JsPrint.printExpr(fn)
    | Open({flow: ListIter}) => "open"
    | Open({flow: OptionIter}) => "openOption"
    | Open({flow: CaseSplit({alts, discriminator})}) =>
      "caseSplit({" ++
      alts->Array.join(", ") ++
      "}, " ++
      JsPrint.printExpr(discriminator) ++ ")"
    | Close(_) => "close"
    | Branch({alt}) => "." ++ alt
    }

  let renderOp = (e: Expr.expr): string => {
    let base = opToken(e)
    if needsLabel->Map.has(e.id) {
      base ++ " (" ++ getLabel(e.id) ++ ")"
    } else {
      base
    }
  }

  let referenceTo = (e: Expr.expr): string =>
    if inlineable->Map.has(e.id) {
      opToken(e)
    } else {
      getLabel(e.id)
    }

  // Render a flowRef as a string, with Joined / Filtered wrappers
  // appended as postfix `-> join` / `-> filter` decorations.
  let rec renderFlowRef = (fr: Expr.flowRef): string =>
    switch fr {
    | NodeFlow(e) => referenceTo(e)
    | Joined(inner) => renderFlowRef(inner) ++ " -> join"
    | Filtered(inner) => renderFlowRef(inner) ++ " -> filter"
    }

  let shouldEmit = (chain: array<Expr.expr>): bool =>
    !(Array.length(chain) == 1 && inlineable->Map.has((chain->Array.getUnsafe(0)).id))

  // Render the source-list that prefixes a chain. Case closes (whose
  // first branch's flow ref is a NodeFlow on a Branch node) get a
  // structured form like `Just: flow/value, Nothing: flow/value`;
  // everything else is a plain comma-separated list. For Close, the
  // flow part uses renderFlowRef so Joined/Filtered wrappers show.
  let renderSource = (head: Expr.expr): string => {
    let isCaseClose = switch head.kind {
    | Close({branches}) =>
      switch (branches->Array.getUnsafe(0)).flow {
      | NodeFlow(e) =>
        switch e.kind {
        | Branch(_) => true
        | _ => false
        }
      | _ => false
      }
    | _ => false
    }
    switch head.kind {
    | Close({branches}) if isCaseClose =>
      branches
      ->Array.map(b => {
        let altLabel = switch b.altName {
        | Some(name) => name
        | None => "?"
        }
        altLabel ++
        ": " ++
        renderFlowRef(b.flow) ++
        "/" ++
        referenceTo(Expr.nodeOf(b.value))
      })
      ->Array.join(", ")
    | Close({branches}) =>
      branches
      ->Array.map(b =>
        renderFlowRef(b.flow) ++ ", " ++ referenceTo(Expr.nodeOf(b.value))
      )
      ->Array.join(", ")
    | Branch({source}) => renderFlowRef(source)
    | _ => inputsOf(head)->Array.map(referenceTo)->Array.join(", ")
    }
  }

  let renderChain = (chain: array<Expr.expr>): string => {
    let head = chain->Array.getUnsafe(0)
    let opStrs = chain->Array.map(renderOp)
    let opChain = opStrs->Array.join(" -> ")
    switch inputsOf(head) {
    | [] => opChain
    | _ => renderSource(head) ++ " -> " ++ opChain
    }
  }

  chains
  ->Array.filter(shouldEmit)
  ->Array.map(renderChain)
  ->Array.join("\n")
}
