// Printer: Program.program -> text (textual-representation-design.md,
// implementation path step 1).
//
// v0 is TOTAL but not yet pretty: every node prints as one named forward
// statement (the "edge list, factored" the design doc notes the statement
// form fundamentally is), in canonical order (DFS from the outputs, then
// root-unreachable remainder — same order as Program.dump). What v0 does
// NOT yet do, deliberately deferred to keep this a printing core:
//
//   - chain compression (single-consumer runs joining into one line) and
//     junction taps for local fan-out — ExprPrint's greedy-chain machinery
//     is the seed; this is the "printer implicitness thresholds" open
//     question and should be one focused round;
//   - derived indentation by flow depth, and the span lint;
//   - `+` completion lines (Complete produces no insertions yet).
//
// Totality over prettiness is the right order: the printer must render
// under-committed and even ill-formed programs (you have to print a
// program to talk about what is wrong with it), and every pass output
// becomes testable the day the printer exists.
//
// Parse coverage note: most of what v0 emits reparses (that is the
// round-trip test), now including lane groups for case collects. Emitted
// forms still ahead of the parser, matching design-only constructs:
// `commute out of` and `cross with` standalone forms. They print so the
// constructs can be *seen*; parsing them is listed in ARCHITECTURE.md's
// growth path.

open Program

@val external jsonStringify: string => string = "JSON.stringify"

// --- naming ------------------------------------------------------------------

type namer = {
  names: Map.t<string, string>, // "nodeId:port" or "node:nodeId" -> name
  mutable counter: int,
}

let portKey = (n: node, port: string): string => Int.toString(n.id) ++ ":" ++ port
let nodeKey = (n: node): string => "node:" ++ Int.toString(n.id)

// Nodes whose refs print as projections off a node name.
let namedAsNode = (n: node): bool =>
  switch n.kind {
  | Uncollect({flowKind: Case(_)}) | Commute(_) => true
  | _ => false
  }

let fresh = (nm: namer, prefix: string): string => {
  nm.counter = nm.counter + 1
  prefix ++ Int.toString(nm.counter)
}

let nodeName = (nm: namer, n: node): string =>
  switch Map.get(nm.names, nodeKey(n)) {
  | Some(s) => s
  | None => {
      let prefix = switch n.kind {
      | Uncollect({flowKind: Case(_)}) => "cs"
      | Commute(_) => "c"
      | _ => "n"
      }
      let s = fresh(nm, prefix)
      Map.set(nm.names, nodeKey(n), s)
      s
    }
  }

let portName = (nm: namer, n: node, port: string, prefix: string): string =>
  switch Map.get(nm.names, portKey(n, port)) {
  | Some(s) => s
  | None => {
      let s = fresh(nm, prefix)
      Map.set(nm.names, portKey(n, port), s)
      s
    }
  }

let valueText = (nm: namer, r: valueRef): string =>
  switch r {
  | ValuePort(n, port) =>
    if namedAsNode(n) {
      nodeName(nm, n) ++ "." ++ port
    } else {
      let prefix = switch n.kind {
      | Uncollect(_) => "e"
      | DelayRead(_) => "d"
      | DelayWrite(_) => "w"
      | _ => "n"
      }
      portName(nm, n, port, prefix)
    }
  }

let flowText = (nm: namer, r: flowRef): string =>
  // without the '~' sigil; callers prepend it
  switch r {
  | FlowPort(n, port) =>
    if namedAsNode(n) {
      nodeName(nm, n) ++ "." ++ port
    } else {
      let prefix = switch n.kind {
      | Join(_) => "j"
      | Cross(_) => "x"
      | Collect(_) => "pf" // a partial collect's merged flow
      | _ => "f"
      }
      portName(nm, n, port, prefix)
    }
  }

// --- literal rendering ----------------------------------------------------------

let rec litIsLeaf = (e: JsAst.expr): bool =>
  switch e {
  | ENum(_) | EStr(_) => true
  | EArray(elems) =>
    elems->Array.every(el =>
      switch el {
      | AElem(inner) => litIsLeaf(inner)
      | _ => false
      }
    )
  | _ => false
  }

let litText = (e: JsAst.expr): string =>
  switch e {
  | ERaw(code) => "js " ++ jsonStringify(code)
  | _ =>
    if litIsLeaf(e) {
      JsPrint.printExpr(e)
    } else {
      // Structured payloads round-trip through the escape hatch. (They
      // come back as ERaw — the payload's printed JS is the identity that
      // survives, which is fine for an escape hatch.)
      "js " ++ jsonStringify(JsPrint.printExpr(e))
    }
  }

// --- statements -------------------------------------------------------------------

let print = (p: program): string => {
  let nm = {names: Map.make(), counter: 0}

  // Same canonical order as Program.dump.
  let order: array<node> = []
  let seen: Map.t<int, bool> = Map.make()
  let rec visit = (n: node): unit =>
    if !Map.has(seen, n.id) {
      Map.set(seen, n.id, true)
      let ins = inputs(n)
      ins.values->Array.forEach(v => visit(nodeOfValue(v)))
      ins.flows->Array.forEach(f => visit(nodeOfFlow(f)))
      ins.pairedReads->Array.forEach(visit)
      Array.push(order, n)
    }
  p.outputs->Array.forEach(o => visit(nodeOfValue(o.source)))
  p.nodes->Array.forEach(visit)

  // Pre-claim output names for their source ports so the defining
  // statement binds the user-visible name directly.
  p.outputs->Array.forEach(o =>
    switch o.source {
    | ValuePort(n, port) =>
      if !namedAsNode(n) && !Map.has(nm.names, portKey(n, port)) {
        Map.set(nm.names, portKey(n, port), o.name)
      }
    }
  )

  let lines: array<string> = []
  order->Array.forEach(n => {
    switch n.kind {
    | Lit(js) =>
      Array.push(lines, valueText(nm, ValuePort(n, "value")) ++ " = " ++ litText(js))
    | App({fn, args}) => {
        let argsTxt = args->Array.map(v => valueText(nm, v))->Array.join(", ")
        let head = if Array.length(args) === 0 {
          // Zero-arg application: no topic to put on the left. Prints as a
          // call; not yet parseable (grammar growth path).
          valueText(nm, fn) ++ "()"
        } else {
          argsTxt ++ " -> " ++ valueText(nm, fn)
        }
        Array.push(lines, head ++ " => " ++ valueText(nm, ValuePort(n, "value")))
      }
    | Uncollect({flowKind, input, nesting}) => {
        let inputTxt = valueText(nm, input)
        let nestTxt = switch nesting {
        | Some(f) => " in ~" ++ flowText(nm, f)
        | None => ""
        }
        switch flowKind {
        | List | Option => {
            let word = flowKind == List ? "list" : "option"
            Array.push(
              lines,
              inputTxt ++
              " -> open " ++
              word ++
              nestTxt ++
              " => " ++
              valueText(nm, ValuePort(n, "element")) ++
              ", ~" ++
              flowText(nm, FlowPort(n, "flow")),
            )
          }
        | Case({alts, discriminator}) =>
          Array.push(
            lines,
            inputTxt ++
            " -> split " ++
            valueText(nm, discriminator) ++
            " of " ++
            alts->Array.join(", ") ++
            nestTxt ++
            " => " ++
            nodeName(nm, n),
          )
        }
      }
    | Collect({branches}) =>
      switch branches {
      | [{flow, value}] =>
        Array.push(
          lines,
          valueText(nm, value) ++
          " -~> collect ~" ++
          flowText(nm, flow) ++
          " => " ++
          valueText(nm, ValuePort(n, "value")),
        )
      | many => {
          // lane group gathered by a postfix collect (case collect,
          // full or partial)
          many->Array.forEach(b =>
            Array.push(lines, "~" ++ flowText(nm, b.flow) ++ ": " ++ valueText(nm, b.value))
          )
          let flowOut = switch classifyCollect(branches) {
          | CasePartial(_) => ", ~" ++ flowText(nm, FlowPort(n, "flow"))
          | _ => ""
          }
          Array.push(
            lines,
            "-~> collect => " ++ valueText(nm, ValuePort(n, "value")) ++ flowOut,
          )
        }
      }
    | Join({outer, inner}) =>
      Array.push(
        lines,
        "~" ++
        flowText(nm, inner) ++
        " ~> join into ~" ++
        flowText(nm, outer) ++
        " => ~" ++
        flowText(nm, FlowPort(n, "flow")),
      )
    | Commute({outer, inner}) =>
      Array.push(
        lines,
        "~" ++
        flowText(nm, inner) ++
        " ~> commute out of ~" ++
        flowText(nm, outer) ++
        " => " ++
        nodeName(nm, n),
      )
    | Cross({left, right}) =>
      // Textual spelling for Cross is still owed at the design level
      // (product-flows-design.md); this placeholder keeps the printer total.
      Array.push(
        lines,
        "~" ++
        flowText(nm, left) ++
        " ~> cross with ~" ++
        flowText(nm, right) ++
        " => ~" ++
        flowText(nm, FlowPort(n, "flow")),
      )
    | DelayRead({flow, init}) =>
      Array.push(
        lines,
        "~" ++
        flowText(nm, flow) ++
        " ~> delay init " ++
        valueText(nm, init) ++
        " => " ++
        valueText(nm, ValuePort(n, "prev")),
      )
    | DelayWrite({read, step}) =>
      Array.push(
        lines,
        valueText(nm, step) ++
        " -> step of " ++
        valueText(nm, ValuePort(read, "prev")) ++
        " => " ++
        valueText(nm, ValuePort(n, "final")),
      )
    }
  })

  p.outputs->Array.forEach(o => {
    let bound = switch o.source {
    | ValuePort(n, port) =>
      if namedAsNode(n) {
        valueText(nm, o.source)
      } else {
        portName(nm, n, port, "n")
      }
    }
    if bound === o.name {
      Array.push(lines, "out " ++ o.name)
    } else {
      Array.push(lines, "out " ++ o.name ++ " = " ++ bound)
    }
  })

  lines->Array.join("\n") ++ "\n"
}
