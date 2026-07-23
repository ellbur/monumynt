// Typed authoring layer over Program.res — "strings below, typed handles
// above" (first-class-ports-design.md).
//
// Two jobs:
//
//   1. Handles. Smart constructors return records of pre-built refs, so
//      ReScript authoring never spells a port-name string. A typo'd port is
//      unwritable, not a runtime error.
//   2. The node set. Because a program is a node set (not a root
//      expression), something has to *collect* the nodes — a write half can
//      hang off nothing downstream. The builder is that something: every
//      constructor registers its node, and `finish` closes the set with the
//      distinguished outputs. This replaces the interim
//      `compileToBody(root, ~writes)` spelling the ports doc floated: the
//      honest signature from the start, as compile-strategy recommends.
//
// Handle-shape decision (ports doc open question 5): flat records per
// construct, plus a trusting `alt` accessor (raises on a bad alt name —
// alts are per-split data, so the handle type stays finite). Sharing is
// opt-in exactly as before: bind a handle once and reuse its refs.

open Program

type b = {mutable nodes: array<node>, mutable nextId: int}

let make = (): b => {nodes: [], nextId: 0}

let mint = (bld: b, kind: kind): node => {
  let n = {id: bld.nextId, kind}
  bld.nextId = bld.nextId + 1
  Array.push(bld.nodes, n)
  n
}

// --- Handles --------------------------------------------------------------

// Single-value-port nodes (Lit, App, Collect full-coverage).
type vHandle = {node: node, value: valueRef}

// List/Option uncollect.
type iterHandle = {node: node, element: valueRef, flow: flowRef}

// Case-split uncollect: project alts with `alt(h, "Just")`.
type splitHandle = {node: node, alts: array<string>}
type altHandle = {altValue: valueRef, altFlow: flowRef}

type joinHandle = {node: node, flow: flowRef}
type commuteHandle = {node: node, outerFlow: flowRef, innerFlow: flowRef}
type delayHandle = {node: node, prev: valueRef}
type writeHandle = {node: node, final: valueRef}

// Disaggregate exposes one value port per projected field; `field(h, name)`
// projects it (trusting, like `alt` — the field set is per-node data).
type disaggregateHandle = {node: node, fields: array<string>}

let vHandleOf = (n: node): vHandle => {node: n, value: ValuePort(n, "value")}

// --- Constructors ----------------------------------------------------------

let lit = (bld: b, js: JsAst.expr): vHandle => vHandleOf(mint(bld, Lit(js)))

// A verbatim-JS extern — the `js "..."` escape hatch of the textual form.
let raw = (bld: b, code: string): vHandle => lit(bld, JsAst.ERaw(code))

let app = (bld: b, fn: valueRef, args: array<valueRef>): vHandle =>
  vHandleOf(mint(bld, App({fn, args})))

let uncollect = (bld: b, flowKind: flowKind, ~nesting: option<flowRef>=?, input: valueRef): node =>
  mint(bld, Uncollect({flowKind, input, nesting}))

let uncollectList = (bld: b, ~nesting: option<flowRef>=?, input: valueRef): iterHandle => {
  let n = uncollect(bld, List, ~nesting?, input)
  {node: n, element: ValuePort(n, "element"), flow: FlowPort(n, "flow")}
}

let uncollectOption = (bld: b, ~nesting: option<flowRef>=?, input: valueRef): iterHandle => {
  let n = uncollect(bld, Option, ~nesting?, input)
  {node: n, element: ValuePort(n, "element"), flow: FlowPort(n, "flow")}
}

let caseSplit = (
  bld: b,
  ~alts: array<string>,
  ~discriminator: valueRef,
  ~nesting: option<flowRef>=?,
  input: valueRef,
): splitHandle => {
  let n = uncollect(bld, Case({alts, discriminator}), ~nesting?, input)
  {node: n, alts}
}

let alt = (h: splitHandle, name: string): altHandle => {
  if !(h.alts->Array.includes(name)) {
    failwith("Build.alt: case split has no alt named " ++ name)
  }
  {altValue: ValuePort(h.node, name), altFlow: FlowPort(h.node, name)}
}

// Iter/filter collect: one branch. `flow` is the one flow this collect
// terminates (a Join's output for flatten/filter chains).
let collect = (bld: b, ~flow: flowRef, value: valueRef): vHandle =>
  vHandleOf(mint(bld, Collect({branches: [{flow, value}]})))

// Case collect (full or partial — coverage is read off the branches).
let collectCases = (bld: b, branches: array<(flowRef, valueRef)>): vHandle =>
  vHandleOf(
    mint(bld, Collect({branches: branches->Array.map(((flow, value)) => {flow, value})})),
  )

let join = (bld: b, ~outer: flowRef, ~inner: flowRef): joinHandle => {
  let n = mint(bld, Join({outer, inner}))
  {node: n, flow: FlowPort(n, "flow")}
}

let commute = (bld: b, ~outer: flowRef, ~inner: flowRef): commuteHandle => {
  let n = mint(bld, Commute({outer, inner}))
  {node: n, outerFlow: FlowPort(n, "outer"), innerFlow: FlowPort(n, "inner")}
}

let cross = (bld: b, ~left: flowRef, ~right: flowRef): joinHandle => {
  let n = mint(bld, Cross({left, right}))
  {node: n, flow: FlowPort(n, "flow")}
}

let delay = (bld: b, ~flow: flowRef, ~init: valueRef): delayHandle => {
  let n = mint(bld, DelayRead({flow, init}))
  {node: n, prev: ValuePort(n, "prev")}
}

// The write half. `read` is the delayHandle whose register this writes;
// exactly-one-write-per-read is a Check rule, not enforced here.
let writeBack = (bld: b, ~read: delayHandle, ~step: valueRef): writeHandle => {
  let n = mint(bld, DelayWrite({read: read.node, step}))
  {node: n, final: ValuePort(n, "final")}
}

// Struct construction: combine named field values into one struct value.
let aggregate = (bld: b, ~fields: array<(string, valueRef)>): vHandle =>
  vHandleOf(mint(bld, Aggregate({fields: fields})))

// Struct projection: one node splits a struct into its named fields.
let disaggregate = (bld: b, ~fields: array<string>, struct_: valueRef): disaggregateHandle => {
  let n = mint(bld, Disaggregate({struct_: struct_, fields: fields}))
  {node: n, fields}
}

let field = (h: disaggregateHandle, name: string): valueRef => {
  if !(h.fields->Array.includes(name)) {
    failwith("Build.field: disaggregate has no field named " ++ name)
  }
  ValuePort(h.node, name)
}

let finish = (bld: b, ~outputs: array<(string, valueRef)>): program => {
  nodes: bld.nodes,
  outputs: outputs->Array.map(((name, source)) => {name, source}),
}
