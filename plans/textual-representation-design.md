# Textual Representation Design

Status: draft for discussion. This document proposes a textual form
for programs — something that can be parsed and generated, sitting
beside the visual form. Nothing here changes the representation
(`visual-language-description/visual-language-spec.md`,
`first-class-ports-design.md`): the text is a serialization of the
same nodes, ports, and wires, not a new semantic layer.

## Why a textual form

Two reasons.

**Rapid development.** We need to write and read concrete programs
faster than we can perfect a visual editor. Today the only authoring
path is ReScript smart constructors in `Main.res`; the only reading
path is `ExprPrint`, which is a log renderer, not a language (it is
lossy — `#N` labels are renumbered per render, literals are inlined
heuristically, and there is no parser).

**Automated generation.** Tools — Claude Code among them — work in
text. Even once the visual editor exists, a parse/print pair is the
door through which external tools read, generate, and diff programs.

Requirements that fall out:

- **Parseable**: text → representation, total on well-formed text.
- **Printable**: representation → text, total on every program the
  representation can hold — including under-committed and even
  ill-formed programs, because you must be able to print a program
  in order to talk about what is wrong with it.
- **Round-trip**: `parse(print(p))` is the same program as `p` (same
  nodes, same ports, same wiring — same ids, when ids are printed).
  And `print(parse(t)) = t` on canonical text, so diffs are
  meaningful.
- **Readable**: a human reads a program top to bottom in execution
  order, without reconstructing a graph in their head.
- **Not a second source of truth.** The program of record is the
  representation (eventually the step-DAG of
  `transformation-levels-design.md`). The text is a faithful
  projection that can also author. Per "abstraction is the source of
  truth," anything the text renders that the user did not author
  (completions, derived views) must be visibly derived.

## What makes this hard

Restating the challenges this document has to answer:

1. **The program is a graph, not a tree.** Many nodes have multiple
   output ports — an open has a value port *and* a flow port; a case
   split has a pair per alt; a race has a pair per contender. Trees,
   the shape parsers love, have one route to each subterm. And with
   registers (Delay), the graph is not even acyclic.
2. **Edge lists are complete but unreadable.** Any graph flattens to
   `edge(n1.p1, n2.p2)` triples; nobody can read that.
3. **No visual crossing signal.** In the diagram, using a flow out of
   order *looks* wrong — wires cross. Text has no 2D plane; some
   analogue of that immediate signal is worth capturing.
4. **No bottlenecks.** Joins and races are barriers with
   pairwise-corresponding inputs and outputs. The text must show
   which input lane an output belongs to without packing values into
   a tuple or tagged union — the exact thing the principle forbids.
5. **Levels.** Level-1 operations (expand, recognize, completion,
   history operations) are statements *about* programs, and derived
   views expose ports you can reference. How does text indicate what
   level a construct lives at, and how does it reference into a
   derived view?

## The central observation: the graph is a tree with seams

The ASG is tree-shaped exactly where nodes have one output port and
one consumer — which is most of value land (literals, applications,
aggregates). It stops being a tree at exactly three kinds of seam:

- **Multi-output nodes**: opens, splits, barriers, registers. One
  node, several ports, several downstream consumers.
- **Fan-out**: one port consumed by several nodes (sharing — which
  is opt-in and semantically load-bearing).
- **Back-edges**: a register's `step → prev` crossing, the one edge
  species that crosses an iteration boundary.

So the syntax should be **nested expressions exactly where the graph
is a tree, and named flat statements exactly at the seams**. Value
computation reads like ordinary code (`double(a) + 1`); everything
multi-port, shared, or cyclic gets a name and a statement of its own.
The text is exactly as flat as the program is graph-like, and no
flatter.

This is also why the "edge list" fear resolves: a statement *is* an
edge list entry — one line per node, inputs referenced inline — just
factored so that the tree-shaped majority collapses into readable
expressions, and ordered so the flat minority reads in execution
order.

## Principles

**P1. A name is a wire.** A statement binds names to output ports of
the one node it constructs. Names are single-assignment, never
shadowed, global to the diagram. Referencing a name twice is fan-out
from one port — the same node, not a copy. Conversely, writing the
same expression twice makes two nodes: sharing is opt-in via naming,
exactly as it is opt-in via ReScript binding today. This carries the
types-design insight into text: "wires are the type variables" —
text reintroduces the burden the diagram avoided (a name must
faithfully denote one wire), and single-assignment global names are
the discipline that pays it.

**P2. Two lexical sorts.** Value references and flow references are
lexically distinct: flow references carry a `~` sigil (`~L`,
`~cs.Just`). Confusing the sorts is a parse error, mirroring how
`expr` vs `flowRef` catches misuse syntactically in `Expr.res`. The
sigil is provisional and cheap to change; what is not negotiable is
that the sorts are distinguishable without name resolution. (A third
species may arrive if the visible state thread of
`iteration-with-state-design.md` becomes a wire of its own kind;
reserve room, don't design it now.)

**P3. No lexical scope.** Statements are flat. There are no blocks:
"inside the loop" is a *derived* fact — a statement is per-iteration
because its inputs are — never a syntactic region. This is the
inside-out principle applied to text: a block syntax would make an
expression's interior scope differ from its exterior, reintroduce
magic names, and be unable to express what the language allows
(multi-close on one opener, a close consuming a flow two levels up,
a value read out of a flow by a join). Indentation exists only as
printer output (see "The crossing signal"), never as parser input.

**P4. Statement order is time.** Statements appear in a topological
order of the dataflow: definition strictly before use, no forward
references. This is always possible, even for cyclic programs,
because of how cycles enter the language: every cycle passes through
a register, and a register's write half is its own node
(`first-class-ports-design.md`, "the write half is a node") wired in
a later, separate act. The one back-edge is therefore always spelled
as a *late statement referring back to an earlier name* — text stays
define-before-use while the semantic graph cycles. Reading top to
bottom is reading time-forward, the same convention `ExprPrint`
chose.

**P5. Barriers are labeled rows.** A multi-in multi-out barrier is
written as one statement with one row per lane. The lane label
appears once at the input row and again in every output reference —
correspondence by shared label, no tuple, no tagged union. (Details
under "Barriers".)

**P6. Authored and inferred structure are distinguished.** Structure
the user did not write — a completion's inserted incorporates and
commutes, a lens's derived view — prints prefixed with `+`, the
textual analogue of the editor's faint rendering
(`time-travel-programs-design.md`). A complete program prints with
no `+` lines; parse ignores `+` lines (they are re-derived, not
stored).

**P7. A statement is a step.** Most statements construct one node —
these are the 1:1 steps of the step-DAG, where "the node *is* the
step seen at level 0." Native level-1 operations (expand, undo,
cherry-pick) are statements too, distinguished not by an annotation
but by what their operands are: names of nodes and steps rather than
wires. Level is read off the operand sort, matching the admission
test ("an operation belongs at level 1 iff its content is a
statement about level-0 programs rather than about values").

## The notation

Comments are `--` to end of line, as in the design docs.

### Value expressions: the tree fragment

Where the graph is a tree, the text is an expression:

```
b = double(a) + offset
pair = { lo: min(x, y), hi: max(x, y) }
```

Literals (`5`, `"s"`, `true`, `[1, 2, 3]`, `{a: 1}`), application
`f(x, y)`, and operator sugar (`+`, `*`, …) for the corresponding
primitives — one node, one meaning, no overloading (types-design:
plus is numeric addition; string concatenation is a different node).

Host functions enter through an explicit escape hatch while the
primitive catalog is small (this is the `JsAst.expr` payload of
today's `Lit`/`App`/discriminators):

```
extern double = js "x => x * 2"
extern isJust = js "m => m"          -- discriminator, identity-shaped
b2 = js "x => x * 3"(a)              -- inline form
```

Every subexpression mints a node; writing `double(a)` twice mints two
App nodes. To share, name it — the textual reflection of "bind once
and reuse":

```
d = double(a)
out = add(d, d)
```

### Binders, node names, and ports

A statement's binder names the node it constructs. Ports are reached
by two rules:

- The **bare name** denotes the node's principal value port (its
  `value`/`result`/`element`/`prev` — the one value port, for nodes
  that have exactly one). `~name` denotes the principal flow port.
- **Projection** reaches named ports: `cs.Just` is the value port
  named `Just`; `~cs.Just` is the flow port named `Just`. The sigil
  states the sort of the reference; the checker verifies the node's
  kind inventory has that port. This is `ValuePort(node, name)` /
  `FlowPort(node, name)` from `first-class-ports-design.md`, spelled.

For the common two-port opens there is tuple-binder sugar naming both
principal ports at once. These are equivalent:

```
it = open list xs          -- it = element, ~it = flow
a, ~L = open list xs       -- a = element, ~L = flow
```

The printer prefers the tuple form for opens and the node-name form
for splits and barriers (whose ports are per-alt and better reached
by projection).

Port inventories are per-kind and irregular (Commute has no value
ports; a register's read half has no flow outputs) — the syntax
never assumes a fixed shape, it just lets binders and projections
name whatever the kind's inventory declares.

### Opens

```
a, ~L = open list xs
v, ~O = open option m
y, ~Y = open list ys in ~L        -- nested inside ~L, explicitly
```

`open <kind> <input>` — the flow kind is part of the node (explicit
over implicit; there is no type inference to discover it). Future
kinds slot in without new syntax shapes: `open async p`,
`open stream s`, `open var v`, `open pool(3) work`.

The `in ~L` clause is the spec's `outerFlows`: an explicit
declaration of which existing flow the new flow nests inside,
outermost to innermost when there are several (`in ~A, ~B`). When
the nesting is already implied by the value input (opening a value
that is itself per-iteration of `~L`), the clause is redundant and
omitted. When it is neither implied nor stated, the program is
*under-committed* — see "Under-commitment and completion."

### Case splits

```
cs = split m by isJust of Just | Nothing
```

One statement binds the node; the per-alt pairs are projections:
`cs.Just` (the alt's payload value), `~cs.Just` (the alt's flow).
There is no Branch construct in the text — as in the first-class
ports design, a branch *is* a reference to one output port of the
split, so projection replaces the satellite node. The alt inventory
(`of Just | Nothing`) is stated on the node, where the bundle's cell
inventory lives.

### Collects

One construct. Each branch is `<flowref>: <value expression>`,
branches separated by `|`. The kind of close is read off the flows,
and coverage is read off the cells — the exhaustive case collect and
the partial collect are one node whose port inventory follows from
coverage (`partial-collect-design.md`):

```
out = collect ~L: double(a)                 -- list close
out = collect ~O: v * 2                     -- option close

out = collect ~cs.Just: double(cs.Just)     -- case close, exhaustive
            | ~cs.Nothing: 0

-- partial collect: branches cover only some cells, so the node has
-- a merged-flow output as well as a value output — the binder
-- arity shows the coverage.
errStatus, ~err = collect ~h.ClientError: h.ClientError
                        | ~h.ServerError: h.ServerError
```

A flow name may be consumed by any number of collect statements —
multi-close is just several statements naming the same flow:

```
a, ~L = open list xs
doubled = collect ~L: double(a)
tripled = collect ~L: triple(a)
```

### Join and filter

Join is the binary flow node with asymmetric operands; the keyword
order carries the asymmetry (`inner` first, `into outer`), because
join operand order is semantic and must never look symmetric:

```
~f = join ~I into ~L        -- flatten: inner list flow into outer
flat = collect ~f: double(x)
```

Filter is not separate syntax: it is a join whose inner operand is
an alt flow (the representation-level fact that `Filtered` dissolves
into Join):

```
a, ~L = open list xs
c = split a by parity of Even | Odd
~keep = join ~c.Even into ~L
evens = collect ~keep: a
```

Multi-level flatten is a chain — depth is spelled structurally, no
numeric levels:

```
~f1 = join ~L3 into ~L2
~f2 = join ~f1 into ~L1
deep = collect ~f2: x
```

(Adjacency — each join's operands must be nesting-adjacent — is a
checker rule, not a parser rule; see "Well-formedness.")

### Commute

Flow wires only, per the reconciled node: no value ports, so nothing
but flow operations can consume its outputs, and the naturality
quotient (map-then-commute = commute-then-map) holds in text for
free — there is no place to write "before the commute."

```
c = commute ~err out of ~loop
-- ~c.outer : the flow that was inner (now outermost)
-- ~c.inner : the flow that was outer (now inside)
```

The defer-the-error idiom then reads: close `~c.inner` now, leave
`~c.outer` open for a later collect statement.

### Barriers: race and concurrent join

The no-bottleneck constructs. A race is one statement, one labeled
row per contender; each contender's output pair is reached by
projecting the *same label*:

```
r = race fetch:   fetchD
       | timeout: after(30)

out = collect ~r.fetch:   some(process(r.fetch))
            | ~r.timeout: none
```

The lane identity that the diagram carries by wire continuity, the
text carries by the label appearing at the input row and at every
output reference. No tagged union exists between the race and its
collect — `r.fetch` *is* contender `fetch`'s value, on `fetch`'s
flow. Reconvergence is the ordinary (partial or covering) collect
over the race's bundle, inherited unchanged from case splits.

The concurrent join (product barrier) merges sibling flows; in the
current lean it is flow-only and values simply become combinable in
the merged context:

```
~ab = join all ~A | ~B
sum = collect ~ab: x + y
```

If barrier value rows land (the open question shared by spec-Join,
race, and partial collect — "k branches × m value rows"), rows
extend the same shape, each row binding its crossing by label:

```
x2, y2, ~ab = join all ~A(x => x2) | ~B(y => y2)
```

This is noted as an option, not committed.

### Registers: delay and write-back

The read half and the write half are two statements, matching the
two-phase construction (mint the read; wire the step later). The
write half is spelled with `<-`, the one back-edge marker in the
language:

```
a, ~L = open list xs
sum = delay on ~L init 0        -- read half; bare `sum` = prev
total = sum <- sum + a          -- write half; binder = final value
```

Reading: `sum` names the register; used in value position it is the
previous iteration's value (`prev`), `init 0` is the outside-the-flow
initial value (kept syntactically apart from per-iteration inputs —
the misplacement that got `stateful(initial, update)` rejected), and
`sum <- e` wires `e` into the register's step, yielding the final
value as the write node's output.

Cross-referencing registers are just wires — Fibonacci:

```
n, ~L = open list steps
fa = delay on ~L init 1
fb = delay on ~L init 1
lastA = fa <- fb
lastB = fb <- fa + fb
```

A write statement's binder may be omitted when the final value is
unused:

```
sum <- sum + a
```

This is legal and important: a write half can be root-unreachable in
a complete program, which is exactly why **a program is a node set
with distinguished outputs, not a root expression** — and why the
textual form is a statement list with declared outputs rather than
"the last expression is the result."

Text never forward-references even here: the write statement refers
*back* to `sum`. The productivity check (every cycle crosses a
register) is what guarantees a define-before-use ordering always
exists. The same `<-` spelling extends to the incremental kind's
`hold` if its cyclic uses (a var updated by events computed from its
own previous value) get the same read/write split.

### Diagram boundary

A file holds one or more diagrams. A diagram declares its boundary
ports; outputs are explicit statements (there is no implicit "return
value" — see the node-set point above):

```
diagram sumOf
  in xs
  a, ~L = open list xs
  sum = delay on ~L init 0
  t = sum <- sum + a
  out total = t
end
```

Flow parameters use the sigil: `in ~io`, `out ~io2 = ~c.outer`.
Slots and `use`/calls of other diagrams follow the same shape as the
spec's FunctionCall (named args); this section stays deliberately
thin until diagrams are the top-level structure in the code.

For the sandbox, a bare statement list with one `out` is a
one-diagram file.

### Under-commitment and completion

A program whose flow structure is under-committed is *writable* —
sibling opens with no declared order, a combining node over
incomparable contexts:

```
a, ~A = open list listA
b, ~B = open list listB       -- sibling opens; no order authored
s = a + b                     -- contexts incomparable
perA = collect ~A: s
out = collect ~B: perA
```

Its meaning is its completion; the printer renders the derived
insertions as `+` lines anchored where they apply (the convention
`time-travel-programs-design.md` already uses):

```
a, ~A = open list listA
+ listB2 = incorporate listB in ~A
+ b, ~B = open list listB2 in ~A
s = a + b
perA = collect ~A: s
out = collect ~B: perA
```

`+` lines are derived, deterministic, and not stored: parse discards
them and re-derivation reproduces them (the completion laws —
conservativity, idempotence, determinism — do the work). To override
an inference, author the operator solid: write the line without the
`+`. A contradictory program (directed constraints cycle) has no
completion; it still parses and prints, and the *error* is what
carries the witness.

## The crossing signal: spans, nesting, indentation

The diagram shows an out-of-order flow use as a wire crossing. The
text has an analogue in one dimension: **statement order plus flow
lifetimes**.

A flow name's *span* runs from its binding statement to its last
consuming statement (its terminations). Because statement order is
time (P4), the well-formedness facts become visible as interval
facts:

- **Nesting shows as containment.** An inner flow's span sits inside
  its outer flow's span. Well-nested programs look well-nested.
- **Crossing shows as overlap.** Two *structural* flows whose spans
  overlap without containment — statements of one interleaved with
  statements of the other — is exactly the interleaving that needs
  an explicit relation (a join, a commute, a declared `in`). Effect
  flows are exempt: they commute freely, and their spans may
  interleave without remark ("most restrictive wins" for bundles).
- The **span lint** flags un-nested overlap of structural flows.
  This is a presentation-level early warning of the same facts the
  provenance check establishes properly (context paths compared at
  combining nodes); it adds no semantics.

On top of this, the **canonical printer indents each statement by
the depth of its flow context** (the length of its context path).
Indentation is derived — the parser ignores it entirely (P3) — but
on a well-formed program it reproduces the block structure a scoped
language would have had, without ever being scope:

```
row, ~R = open list rows
    x, ~I = open list row
    perRow = collect ~I: double(x)
out = collect ~R: perRow
```

And on a time-travel program, no consistent indentation exists —
the printer falls back to flat and the completion's `+` lines say
why. That failure-to-indent is the textual cousin of the visible
crossing: not a check (the checker owns that), but the same
immediate "this doesn't sit right" signal the 2D layout gives.

Whether indentation should ever be parser-significant was
considered and rejected: significant whitespace would make
indentation *authoritative*, and the one thing indentation must not
be is a second statement of nesting that can disagree with the
wiring. One source of truth; indentation is a view.

## Levels

Two senses of "level" need textual answers; they are different
things and get different answers.

**Flow nesting depth** gets no numerals and no annotation. Depth is
structural: an open `in ~L`, a chain of binary joins, a chain of
commutes. "Level-2 join" is two join statements. This follows the
binary-join correction — the old `Joined(Joined(...))` wrapper
counting is superseded by naming both operands explicitly.

**Transformation levels** are the real question. The stored program
is one step-DAG whose 1:1 steps read as node declarations — which is
exactly what a statement is (P7). So:

- A **snapshot file** (the common interchange case — "the program at
  this head") is a statement list containing only level-0
  statements. Every statement mints nodes; the file is the node set.
- **Level-1 statements** are the built-in catalog entries, written
  as statements whose operands are *names of nodes/steps*, not
  wires:

  ```
  sumX = expand sum          -- materialize sum's expansion, named
  w = sum!acc                -- lens reference: DerivedPort(sum, acc)
  ```

  `expand` is a recorded step (its parts become addressable — the
  materialize mode); `!` is the lens mode — referencing a principal
  port of the *derived view* without materializing anything.
  `sum!acc` is the textual `DerivedPort(nodeId, portName)`, and only
  principal ports are addressable through it, so ill-formed
  references stay unrepresentable. No level marker is written or
  needed: `expand sum` is level-1 because its operand is a node, by
  the admission test.

- **History files** — serializing the full step-DAG including undo
  and cherry-pick — are deferred. The design intent is only pinned:
  the snapshot grammar must remain a strict subset of the history
  grammar (a snapshot is a history with only 1:1 steps), so nothing
  chosen here paints over that door.

**Stable identity.** Node ids are load-bearing across versions
(diff, blame, completion hints anchored to ids). Names carry
identity *within* a file; across versions, the printer can be asked
to emit ids as suffixes:

```
sum@n42 = delay on ~L init 0
```

Default output omits them (humans don't want them); tools that diff
or patch request them. Parse of an id-less file mints fresh ids —
which is correct for generated-from-scratch programs and is the
reason round-tripping *with* ids matters for edits.

## Worked examples

The core fragment (everything the code implements today), then
design-only constructs.

Map with a hoisted shared constant, flattened:

```
rows = [[1, 2], [3]]
row, ~R = open list rows
x, ~I = open list row
ten = 10
~f = join ~I into ~R
out = collect ~f: x + ten          -- [11, 12, 13]
```

Maybe-double (case split inside a list iteration):

```
m, ~L = open list maybes
cs = split m by isJust of Just | Nothing
perElem = collect ~cs.Just: double(cs.Just)
              | ~cs.Nothing: 0
out = collect ~L: perElem          -- [2, 0, 10]
```

Partition by two filter joins (multi-way output, one pass):

```
a, ~L = open list xs
c = split a by parity of Even | Odd
~ke = join ~c.Even into ~L
~ko = join ~c.Odd into ~L
evens = collect ~ke: a
odds  = collect ~ko: a
```

Running sum (register):

```
a, ~L = open list xs
sum = delay on ~L init 0
total = sum <- sum + a
```

Timeout race (design-only):

```
r = race fetch:   fetchD
       | timeout: after(30)
out = collect ~r.fetch:   some(process(r.fetch))
            | ~r.timeout: none
```

HTTP status partial collect (design-only):

```
h = split resp by status of Ok | Redirect | ClientError | ServerError
errCode, ~err = collect ~h.ClientError: h.ClientError
                      | ~h.ServerError: h.ServerError
report = collect ~h.Ok: "ok"
               | ~h.Redirect: "moved"
               | ~err: describe(errCode)
```

## Well-formedness: parser vs checker

The parser owns only what is lexically decidable:

- sort discipline (`~` where a flow is required, none where a value
  is);
- single assignment, definition before use;
- statement arity/shape per keyword (binder counts, clause order).

Everything else stays where it belongs — checks on the
representation, shared with every other authoring path:

- port existence (a projection names a port in the kind's
  inventory);
- flow-borne locality (a per-iteration value referenced only from
  within its flow);
- join operand adjacency;
- collect coverage and partial-collect cell disjointness;
- productivity (every cycle crosses a register) and one-write-per-
  register;
- provenance comparability at combining nodes, with its two clash
  flavors (time travel — completable; bundle mixing — not).

The text adds *no* checks of its own; the span lint and the
indentation signal are presentation-level renderings of checker
facts. A file can parse and still be ill-formed — necessarily so,
since printing ill-formed programs (to show the witness) is a
requirement.

## Correspondence to the representation

For the fragment the code implements, the mapping to `Expr.res` is
direct:

| text | representation |
|---|---|
| `5`, `js "…"` | `Lit(JsAst.expr)` |
| `f(x, y)` | `App({fn, args})` |
| `a, ~L = open list e` | `Open({flow: ListIter, input})`; `a` = the node in value position, `~L` = `NodeFlow(node)` |
| `v, ~O = open option e` | `Open({flow: OptionIter, input})` |
| `cs = split e by d of A \| B` | `Open({flow: CaseSplit({alts, discriminator}), input})` |
| `cs.A` / `~cs.A` | `branch_(NodeFlow(cs), "A")` in value / flow position (until first-class ports, when both become port refs) |
| `~f = join ~I into ~O` + `collect ~f: e` | `close_(join_(NodeFlow(inner)), e)` — the parser checks the `into` operand matches the opener chain |
| `~k = join ~cs.A into ~L` + `collect ~k: e` | `close_(filter_(NodeFlow(branch)), e)` |
| `collect ~cs.A: e \| ~cs.B: e2` | `caseClose([{altName, flow, value}, …])` |

Under the first-class-ports migration the right column simplifies
(projections become `ValuePort`/`FlowPort` refs; Join becomes the
binary node and the parser's adjacency bookkeeping moves to the
checker), and the text does not change — which is the point of
writing the text against ports and names rather than against the
current wrapper encoding.

## Alternatives considered

**Raw edge list / JSON dump.** Complete, trivially parseable,
unreadable — rejected as the primary form. (A mechanical JSON
projection of the node set may still exist for tooling; it needs no
design.)

**S-expressions.** Tree-biased: sharing and cycles need labels
anyway (`#n#`/`#n=` or `letrec`), at which point the notation has
all of this design's machinery with less readability. The tree bias
also invites writing programs as expression trees, which the
language specifically is not.

**Block structure (loop bodies as indented scopes).** The tempting
one, and rejected on principle, not taste: blocks make the interior
of a construct syntactically different from its exterior (the
inside-out violation), require magic names or parameters for the
element value, and cannot express the language's non-tree moves —
multi-close on one opener, a close on a joined flow two levels up,
partial collects whose branches originate in different "blocks," a
race's contenders continuing as themselves. Every one of those
would need an escape hatch; the escape hatch would become the
language.

**Keep authoring in ReScript (status quo).** Fine for the test
suite, useless for external tools: not parseable without a ReScript
toolchain, not printable back, and the smart-constructor layer is an
authoring convenience, not a stable interchange surface.

## Open questions

1. **Sigil and keyword spellings.** `~` for flows, `!` for lens
   references, `<-` for write-back, `in`/`into`/`out of` — all
   cheap to change, chosen here for readability. The naming
   deferrals in the flow-kind docs (race vs select, etc.) surface
   here as keyword choices; keep them cheap.
2. **Alt-port naming scheme.** Bare alt name on both value and flow
   side (as here, disambiguated by sigil) vs `(alt, Value)`/`(alt,
   Flow)` pairs — should match whatever the spec's `outputName`
   settles on, so text and spec never need a translation table.
3. **How much the printer inlines.** When does a single-consumer
   value node print inline vs named? (`ExprPrint`'s heuristics are a
   starting point.) Canonical-form stability matters more than the
   particular choice.
4. **Barrier value rows.** If Join/race/partial-collect grow the
   general "k lanes × m value rows" shape, the row syntax sketched
   under "Barriers" needs committing. Blocked on the representation
   question, correctly.
5. **Ids in interchange.** Is `@id` on every statement acceptable
   for tool-to-tool round-trips, or does edit-patching want a
   separate sidecar (name ↔ id map)?
6. **History serialization.** Undo/cherry-pick/materialize as
   statements are sketched, not designed; the snapshot-⊂-history
   grammar constraint is the only commitment.
7. **Effect-flow threading sugar.** Effect operations rebind their
   flow (`~io2 = effect print ~io "hi"`); the docs' prime convention
   suggests wanting lighter threading for long effect chains.
   Deferred until effect flows are closer to implementation.

## Implementation path

Baby steps, each independently useful:

1. **Core-fragment printer.** `TextPrint.res`: render any current
   `Expr.expr` in this notation (total; named ports; canonical
   ordering and indentation). Coexists with `ExprPrint` (which
   stays as the compact log form) until it clearly supersedes it.
2. **Core-fragment parser.** `TextParse.res`: the grammar covering
   exactly today's `Expr.res` (lit/app/extern, list/option opens,
   case split with projections, join/filter via `join … into …`,
   collects). Output: `Expr.expr`.
3. **Round-trip tests.** For each of the 80 suite programs:
   `print → parse → compile → run` agrees with building the Expr
   directly; and `print(parse(t)) = t` on the printed text. Pin a
   few golden files.
4. **Span lint + indentation.** The presentation-level crossing
   signal, once the printer exists to host it.
5. Then track the representation: first-class ports (projections
   become port refs), partial collect, `+`-completion printing —
   each lands in the text the day it lands in the representation.
