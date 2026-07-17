// Resolution: TextAst statements -> Program.program, minting nodes through
// Build. This is where every pronoun desugars (P8) — the representation
// never contains a tap, a lane, or an implicit flow:
//
//   - NAMES are single-assignment and global (P1: a name is a wire).
//     Referencing a name twice is fan-out from one port; writing the same
//     literal twice mints two nodes. Sharing is opt-in via naming, exactly
//     as it is opt-in via ReScript binding.
//   - TAPS: a '|' mid-chain records (value, flow stack) at that point; a
//     line's leading '|'s bind ordinally to the nearest preceding
//     tap-minting line. A minting line replaces the antecedents.
//   - THE IMPLICIT FLOW STACK: a chain carries, next to its running value,
//     the stack of flow layers opened/joined/commuted along it. Bare
//     `collect` closes the innermost layer; bare `join` merges the two
//     innermost; `commute` swaps them. This is chain-local resolver state
//     (the value ref keeps pointing at its producer; flow ops rewire
//     context — the naturality note in the design doc). A named source
//     seeds the stack from its Context path.
//
// The resolver does NO semantic checking beyond what resolution itself
// forces (unknown name, no open flow to collect). Everything else — port
// validity, adjacency, alignment — belongs to Check, shared with every
// authoring path.

open TextAst
open Program

exception ResolveError(string)

let err = (msg: string) => throw(ResolveError(msg))

type entry =
  | EValue(valueRef)
  | EFlow(flowRef)
  | ESplit(Build.splitHandle)

type tapPoint = {tapValue: valueRef, tapStack: array<flowRef>}

type r = {
  bld: Build.b,
  env: Map.t<string, entry>,
  mutable prevTaps: array<tapPoint>,
  mutable outs: array<(string, valueRef)>,
  mutable lastValueBinder: option<(string, valueRef)>,
}

let bindName = (st: r, name: string, e: entry): unit => {
  if Map.has(st.env, name) {
    err("name '" ++ name ++ "' is already bound (names are single-assignment)")
  }
  Map.set(st.env, name, e)
}

// --- leaf terms to JsAst -----------------------------------------------------

let rec leafToJs = (t: term): JsAst.expr =>
  switch t {
  | TNum(f) => JsAst.ENum(f)
  | TStr(s) => JsAst.EStr(s)
  | TJs(code) => JsAst.ERaw(code)
  | TArr(elems) => JsAst.EArray(elems->Array.map(e => JsAst.AElem(leafToJs(e))))
  | TName(n) => err("'" ++ n ++ "' is not a literal (leaf definitions take literals)")
  | TProj(n, p) => err("'" ++ n ++ "." ++ p ++ "' is not a literal")
  }

// --- reference resolution ------------------------------------------------------

let resolveValueTerm = (st: r, t: term): valueRef =>
  switch t {
  | TNum(_) | TStr(_) | TArr(_) | TJs(_) => Build.lit(st.bld, leafToJs(t)).value
  | TName(name) =>
    switch Map.get(st.env, name) {
    | Some(EValue(v)) => v
    | Some(EFlow(_)) => err("'" ++ name ++ "' names a flow; a value is needed here (did you mean ~" ++ name ++ " somewhere else?)")
    | Some(ESplit(_)) =>
      err("'" ++ name ++ "' names a case split; project an alt payload: " ++ name ++ ".<Alt>")
    | None => err("unknown name '" ++ name ++ "'")
    }
  | TProj(name, port) =>
    switch Map.get(st.env, name) {
    | Some(ESplit(h)) => Build.alt(h, port).altValue
    | Some(_) => err("'" ++ name ++ "' is not a case split; '.' projection needs one")
    | None => err("unknown name '" ++ name ++ "'")
    }
  }

let resolveFlowTerm = (st: r, ft: flowTerm): flowRef =>
  switch ft {
  | FName(name) =>
    switch Map.get(st.env, name) {
    | Some(EFlow(f)) => f
    | Some(EValue(_)) => err("'~" ++ name ++ "': '" ++ name ++ "' names a value, not a flow")
    | Some(ESplit(_)) =>
      err("'~" ++ name ++ "' names a case split; project an alt flow: ~" ++ name ++ ".<Alt>")
    | None => err("unknown flow name '~" ++ name ++ "'")
    }
  | FProj(name, port) =>
    switch Map.get(st.env, name) {
    | Some(ESplit(h)) => Build.alt(h, port).altFlow
    | Some(_) => err("'~" ++ name ++ "." ++ port ++ "': '" ++ name ++ "' is not a case split")
    | None => err("unknown name '" ++ name ++ "'")
    }
  }

let contextOf = (v: valueRef): array<flowRef> =>
  try Context.valueContext(v) catch {
  | Context.Incomparable(_) =>
    // Resolution only needs a seed for the implicit stack; a genuinely
    // incomparable context is Check's to witness. Seed empty and let the
    // checker speak.
    []
  }

let sameFlow = (a: flowRef, b: flowRef): bool => Context.flowKey(a) === Context.flowKey(b)

// --- chains ---------------------------------------------------------------------

type chainState = {
  mutable cur: option<valueRef>,
  mutable pendingArgs: array<valueRef>, // >1 sources awaiting an App stage
  mutable flowSource: option<flowRef>, // for flow-sourced statements
  mutable stack: array<flowRef>, // the implicit flow stack
  mutable lastFlows: array<flowRef>, // flows minted by the latest stage, for ~binders
  mutable newSplit: option<Build.splitHandle>,
  mutable newTaps: array<tapPoint>,
}

let theValue = (cs: chainState, what: string): valueRef =>
  switch cs.cur {
  | Some(v) => v
  | None =>
    err(what ++ " needs a value on the chain (no current value here)")
  }

let resolveChain = (
  st: r,
  sources: array<source>,
  stages: array<(arrow, stage)>,
  binders: array<binder>,
): unit => {
  let cs = {
    cur: None,
    pendingArgs: [],
    flowSource: None,
    stack: [],
    lastFlows: [],
    newSplit: None,
    newTaps: [],
  }

  // -- sources --
  let vals: array<valueRef> = []
  let tapIndex = ref(0)
  sources->Array.forEach(s =>
    switch s {
    | SrcTerm(t) => Array.push(vals, resolveValueTerm(st, t))
    | SrcTap => {
        let k = tapIndex.contents
        tapIndex := k + 1
        switch st.prevTaps[k] {
        | Some({tapValue, tapStack}) => {
            Array.push(vals, tapValue)
            cs.stack = Array.copy(tapStack)
          }
        | None =>
          err(
            "leading '|' #" ++
            Int.toString(k + 1) ++ " has no matching tap on the antecedent line",
          )
        }
      }
    | SrcFlow(ft) =>
      switch cs.flowSource {
      | None => cs.flowSource = Some(resolveFlowTerm(st, ft))
      | Some(_) => err("more than one flow source on a line is not supported yet")
      }
    }
  )
  switch vals {
  | [] => ()
  | [v] => {
      cs.cur = Some(v)
      if Array.length(cs.stack) === 0 {
        cs.stack = Array.copy(contextOf(v))
      }
    }
  | many => {
      cs.pendingArgs = many
      // Merge the sources' contexts to seed the stack (prefix rule; the
      // deepest wins — misalignment is Check's business).
      let deepest = many->Array.reduce([], (acc, v) => {
        let c = contextOf(v)
        if Array.length(c) > Array.length(acc) {
          c
        } else {
          acc
        }
      })
      cs.stack = Array.copy(deepest)
      cs.cur = many[0] // topic defaults to the first source (for non-App stages)
    }
  }

  // -- stages --
  stages->Array.forEach(((arrow, stg)) =>
    switch stg {
    | StTap =>
      Array.push(
        cs.newTaps,
        {tapValue: theValue(cs, "a tap '|'"), tapStack: Array.copy(cs.stack)},
      )
    | StApp({fn, extraArgs}) => {
        if arrow != AValue {
          err("an application stage takes '->' (value arrow)")
        }
        let fnRef = resolveValueTerm(st, fn)
        let args = if Array.length(cs.pendingArgs) > 0 {
          cs.pendingArgs
        } else {
          [theValue(cs, "an application stage")]
        }
        let allArgs = Array.concat(args, extraArgs->Array.map(t => resolveValueTerm(st, t)))
        let h = Build.app(st.bld, fnRef, allArgs)
        cs.cur = Some(h.value)
        cs.pendingArgs = []
        cs.lastFlows = []
      }
    | StUncollect({kindWord, nesting}) => {
        if arrow != AValue {
          err("'open' takes '->' (value arrow): the input is a value")
        }
        let input = theValue(cs, "'open'")
        let nestingRef = nesting->Option.map(ft => resolveFlowTerm(st, ft))
        let h = switch kindWord {
        | "list" => Build.uncollectList(st.bld, ~nesting=?nestingRef, input)
        | "option" => Build.uncollectOption(st.bld, ~nesting=?nestingRef, input)
        | other => err("unknown open kind '" ++ other ++ "'")
        }
        cs.cur = Some(h.element)
        Array.push(cs.stack, h.flow)
        cs.lastFlows = [h.flow]
        cs.pendingArgs = []
      }
    | StSplit({disc, alts}) => {
        if arrow != AValue {
          err("'split' takes '->' (value arrow): the input is a value")
        }
        let input = theValue(cs, "'split'")
        let discRef = resolveValueTerm(st, disc)
        let h = Build.caseSplit(st.bld, ~alts, ~discriminator=discRef, input)
        cs.newSplit = Some(h)
        cs.cur = None
        cs.lastFlows = []
      }
    | StCollect({flowArg}) => {
        if arrow != AValueFlow {
          err("'collect' takes '-~>' (the value crosses together with its flow)")
        }
        let value = theValue(cs, "'collect'")
        let flow = switch flowArg {
        | Some(ft) => resolveFlowTerm(st, ft)
        | None =>
          switch cs.stack[Array.length(cs.stack) - 1] {
          | Some(f) => f
          | None =>
            err(
              "bare 'collect' has no open flow on this chain — supply an explicit operand: collect ~F",
            )
          }
        }
        cs.stack = cs.stack->Array.filter(f => !sameFlow(f, flow))
        let h = Build.collect(st.bld, ~flow, value)
        cs.cur = Some(h.value)
        cs.lastFlows = []
      }
    | StJoin({into}) =>
      switch into {
      | Some(outerFt) => {
          // standalone form: ~inner ~> join into ~outer
          if arrow != AFlow {
            err("'join into' takes '~>' (flow arrow) from a flow source")
          }
          let inner = switch cs.flowSource {
          | Some(f) => f
          | None => err("'join into' needs a flow source (~F ~> join into ~G)")
          }
          let outer = resolveFlowTerm(st, outerFt)
          let h = Build.join(st.bld, ~outer, ~inner)
          cs.lastFlows = [h.flow]
          cs.flowSource = Some(h.flow)
        }
      | None => {
          // chain form: merge the two innermost layers
          if arrow != AValueFlow {
            err("bare 'join' takes '-~>' (the value rides through)")
          }
          let len = Array.length(cs.stack)
          if len < 2 {
            err("bare 'join' needs two open flow layers on the chain")
          }
          let inner = cs.stack->Array.getUnsafe(len - 1)
          let outer = cs.stack->Array.getUnsafe(len - 2)
          let h = Build.join(st.bld, ~outer, ~inner)
          cs.stack = cs.stack->Array.slice(~start=0, ~end=len - 2)
          Array.push(cs.stack, h.flow)
          cs.lastFlows = [h.flow]
        }
      }
    | StCommute => {
        if arrow != AValueFlow {
          err("'commute' takes '-~>' (the value rides through)")
        }
        let len = Array.length(cs.stack)
        if len < 2 {
          err("'commute' needs two open flow layers on the chain")
        }
        let inner = cs.stack->Array.getUnsafe(len - 1)
        let outer = cs.stack->Array.getUnsafe(len - 2)
        let h = Build.commute(st.bld, ~outer, ~inner)
        cs.stack = cs.stack->Array.slice(~start=0, ~end=len - 2)
        Array.push(cs.stack, h.outerFlow)
        Array.push(cs.stack, h.innerFlow)
        cs.lastFlows = [h.outerFlow, h.innerFlow]
      }
    | StDelay({init}) => {
        if arrow != AFlow {
          err("'delay' takes '~>' from a flow source (~L ~> delay init 0)")
        }
        let flow = switch cs.flowSource {
        | Some(f) => f
        | None => err("'delay' needs a flow source (~L ~> delay init 0)")
        }
        let initRef = resolveValueTerm(st, init)
        let h = Build.delay(st.bld, ~flow, ~init=initRef)
        cs.cur = Some(h.prev)
        cs.stack = Array.copy(contextOf(h.prev))
        cs.lastFlows = []
      }
    | StStepOf(regName) => {
        if arrow != AValue {
          err("'step of' takes '->' (the step is a value)")
        }
        let step = theValue(cs, "'step of'")
        let readNode = switch Map.get(st.env, regName) {
        | Some(EValue(ValuePort(n, "prev"))) => n
        | Some(_) | None =>
          err("'step of " ++ regName ++ "': '" ++ regName ++ "' is not a register (delay) binder")
        }
        let h = Build.writeBack(
          st.bld,
          ~read={node: readNode, prev: ValuePort(readNode, "prev")},
          ~step,
        )
        cs.cur = Some(h.final)
        cs.stack = Array.copy(contextOf(h.final))
        cs.lastFlows = []
      }
    }
  )

  // -- binders --
  let valueBound = ref(false)
  let flowIdx = ref(0)
  binders->Array.forEach(b =>
    switch b {
    | BValue(name) =>
      switch cs.newSplit {
      | Some(h) => {
          bindName(st, name, ESplit(h))
          cs.newSplit = None
        }
      | None => {
          if valueBound.contents {
            err("more than one value binder on a chain is not supported yet")
          }
          let v = theValue(cs, "binder '" ++ name ++ "'")
          bindName(st, name, EValue(v))
          st.lastValueBinder = Some((name, v))
          valueBound := true
        }
      }
    | BFlow(name) => {
        let f = switch cs.lastFlows[flowIdx.contents] {
        | Some(f) => f
        | None =>
          switch cs.stack[Array.length(cs.stack) - 1] {
          | Some(f) => f
          | None => err("flow binder '~" ++ name ++ "' has no flow to bind")
          }
        }
        flowIdx := flowIdx.contents + 1
        bindName(st, name, EFlow(f))
      }
    }
  )

  if cs.newTaps->Array.length > 0 {
    st.prevTaps = cs.newTaps
  }
}

// --- entry point -------------------------------------------------------------------

let resolve = (statements: array<statement>): program => {
  let st = {
    bld: Build.make(),
    env: Map.make(),
    prevTaps: [],
    outs: [],
    lastValueBinder: None,
  }
  statements->Array.forEach(stmt =>
    switch stmt {
    | LeafDef({name, term}) =>
      switch term {
      | TName(_) | TProj(_, _) =>
        // alias: `a = b` shares b's wire under a second name
        bindName(st, name, EValue(resolveValueTerm(st, term)))
      | _ => bindName(st, name, EValue(Build.lit(st.bld, leafToJs(term)).value))
      }
    | OutDecl({name, from}) => {
        let srcName = from->Option.getOr(name)
        switch Map.get(st.env, srcName) {
        | Some(EValue(v)) => Array.push(st.outs, (name, v))
        | Some(_) => err("output '" ++ name ++ "' must name a value")
        | None => err("output references unknown name '" ++ srcName ++ "'")
        }
      }
    | Chain({sources, stages, binders}) => resolveChain(st, sources, stages, binders)
    }
  )
  let outputs = if Array.length(st.outs) > 0 {
    st.outs
  } else {
    switch st.lastValueBinder {
    | Some((name, v)) => [(name, v)]
    | None => err("program has no outputs (no 'out' declaration and no named chain result)")
    }
  }
  Build.finish(st.bld, ~outputs)
}

let parseProgram = (src: string): program => resolve(TextParse.parse(src))
