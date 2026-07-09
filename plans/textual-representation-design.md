# Textual Representation Design

Status: draft, revised after design discussion (2026-07-08). This
document proposes a textual form for programs — something that can
be parsed and generated, sitting beside the visual form. Nothing
here changes the representation
(`visual-language-spec.md`,
`first-class-ports-design.md`): the text is a serialization of the
same nodes, ports, and wires, not a new semantic layer.

Revision note: the first draft used conventional name-first,
head-first syntax (`b = double(a)`). Discussion identified that as
inconsistent about reading direction (see "Reading direction") and
it was replaced by the forward canonical form described here; the
conventional spellings survive as accepted input. The first draft's
brace-delimited fan-out was rejected outright (see "Alternatives").

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
   `edge(n1.p1, n2.p2)` triples; nobody can read that. The related
   failure is over-naming: if every seam forces a name, the code
   goes flat — a list of bindings instead of structure. We want
   structure like Lisp's, but for a graph rather than a tree.
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

So the syntax should be **nested/chained exactly where the graph is
a tree, with heavier machinery reserved for the seams** — and the
machinery is graded. Three reference tiers, cheapest first:

- **Chains** — the linear backbone. A value flows stage to stage;
  its flow context rides along (marked, see the arrow family); no
  names at all.
- **Pronouns** — short-range anaphora for local seams: junction
  taps (`|`) for nearby fan-out, lane labels for a split's
  branches, `~` / `~^` for the innermost flows. All of these
  desugar at parse; the representation never contains one.
- **Names** — for anything shared or distant. A name is the mark of
  sharing: anonymous is linear, named is shared, which restates the
  language's own "sharing is opt-in via binding" as a fact the text
  displays.

There is a crisp way to say what the tiers achieve: a graph's text
can nest along its *dominator tree* — everything reachable only
through one point can be written inside that point's chain,
including local fan-out (taps and lanes). Names are needed exactly
for edges that escape dominance.

## Reading direction

A conventional syntax is inconsistent about whether moving forward
through the text moves forward or backward in dependency order:
naming moves backward (`a = …`), application moves backward
(`f(arg)` — the consumer before its inputs), yet statement order
moves forward. This form resolves it: **the canonical text is
consistently forward** — postfix application, chains, right-hand
naming. Forward notation is post-order traversal: producers before
consumers at every scale, so "token order is time," not just
"statement order is time."

This is not a novelty for this repo. The design docs' informal
notation is already forward (`list -> $ => a, xL`, with `->` for
wiring and `=>` for naming), and `ExprPrint` is already a post-order
renderer — sources first, then the op, chains for single-consumer
runs. The first draft's `name = f(x)` was the deviation.

(Prefix notation's claim to naturalness is an artifact of which
natural languages designed the existing programming languages;
head-final order — arguments before the operation — is the most
common clause order across human languages.)

**The grammar is permissive; the printer is canonical.** By "many
authoring paths, few readings," parse accepts prefix (`f(x, y)`),
postfix (`x, y -> f`), infix for the operators conventionally
written that way (`a + b`), and both assignment directions (`name =
…` and `… => name`), as in R. The canonical printer emits: chains
and all flow structure forward; small pure-value leaves in
conventional infix/prefix; left assignment for short leaf
definitions (externs, constants), right assignment for chain
results. Printer rules are deterministic, so there is still one
reading.

Right assignment never needs column alignment, because any chain
stage may start a new line — `=>` is just the last stage:

```
xs -> open list
   -> double
  -~> collect
=> doubled
```

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
`~cs.Just`), and the arrows are sorted too (see the arrow family).
Confusing the sorts is a parse error, mirroring how `expr` vs
`flowRef` catches misuse syntactically in `Expr.res`. The sigil is
provisional and cheap to change; what is not negotiable is that the
sorts are distinguishable without name resolution. (A third species
may arrive if the visible state thread of
`iteration-with-state-design.md` becomes a wire of its own kind;
reserve room, don't design it now.)

**P3. No lexical scope.** There are no blocks and no delimited
regions: "inside the loop" is a *derived* fact — a statement is
per-iteration because its inputs are — never a syntactic region.
This is the inside-out principle applied to text: a block syntax
would make an expression's interior differ from its exterior,
reintroduce magic names, and be unable to express what the language
allows (multi-close on one opener, a close on a joined flow two
levels up, a race's contenders continuing as themselves).
Indentation exists only as printer output, never as parser input.

**P4. Token order is time.** The canonical text is a post-order
rendering: every producer appears before its consumers, within a
line and across lines. No forward references exist — even for
cyclic programs, because of how cycles enter the language: every
cycle passes through a register, and a register's write half is its
own node (`first-class-ports-design.md`, "the write half is a
node") wired in a later act. The one back-edge is always spelled as
a later statement referring back to an earlier name.

**P5. Barriers are labeled lanes.** A multi-in multi-out barrier is
written one lane per line; the lane label carries the pairwise
input↔output correspondence. No tuple, no tagged union.

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
but by what their operands are: names of nodes and steps rather
than wires. Level is read off the operand sort, matching the
admission test ("an operation belongs at level 1 iff its content is
a statement about level-0 programs rather than about values").

**P8. Pronouns desugar at parse.** Taps, lane labels, and flow
anaphora are resolved to explicit wiring by the parser; the
representation is always fully explicit. This is what keeps
`$_`-style convenience from becoming `$_`-style fragility: the
pronoun is never runtime or representation state, only reference
resolution. Correspondingly, all pronoun binding is **ordinal,
never spatial** — nothing in the grammar depends on columns or
alignment.

## The notation

Comments are `--` to end of line, as in the design docs.

### The arrow family

Three arrows, one per wire-sort combination:

- `->` — a value wire. Ordinary application, open inputs.
- `~>` — a flow wire. Wiring a flow into a stage with no value
  involved: `~L ~> delay init 0`, `~c.Even ~> join into ~L`.
- `-~>` — a value **with its flow**. Into `collect` (which consumes
  both), and into `join`/`commute` (which act on the flow while the
  value rides through).

The third arrow earns its keep by fixing a level-mixing problem. A
value in a chain has a *context path* — the stack of flows it lives
under, derivable from the dataflow. It is tempting to let a plain
`->` into a `collect` silently reach for that context, but then the
wire is being used to mean not the value it carries but the wire
itself, as a key for a different associated wire — do you mean the
variable or its value? `-~>` is the honest spelling: it
acknowledges, in the syntax, that a flow is entering the stage. The
stage still needs no *operand* (see "The implicit flow stack" — the
adjacency rules determine which flow), but the arrow says a flow is
entering at all.

Soundness of the ride-through: `-~>` into a join or commute claims
the value passes through a node that, representationally, has no
value ports. That is exactly the naturality quotient — "before vs
after the commute" is unrepresentable, so the desugaring (value
refs keep pointing at their producer; the flow ops rewire context)
loses nothing the language considers real.

### Chains, lines, and naming

A chain is stages joined by arrows. A stage is a construct keyword
(`open list`, `split`, `collect`, `join`, `commute`, …) or a value
operation. Any stage may start a new line; a leading arrow
continues the previous line's chain. `=> names` is the naming
stage — it may bind several outputs (`=> a, ~L`) and may stand on
its own line. Left assignment `name = …` is the short form for leaf
definitions.

Value operations in chain position take the chain's value as their
first input; extra inputs go in parentheses: `-> add(ten)` is
`add(topic, ten)`. When the topic is not the first argument, use
the full form: `ten, x -> sub`.

```
double = js "x => x * 2"          -- extern: the JsAst escape hatch
[1, 2, 3] -> open list -> double -~> collect => out
```

Writing `double(a)` twice mints two App nodes; to share, name it or
tap it (below).

### Ports and projections

A binder names the node. The bare name denotes the node's principal
value port (its `value`/`result`/`element`/`prev`); `~name` the
principal flow port. Projection reaches named ports: `cs.Just` is
the value port named `Just`, `~cs.Just` the flow port — the sigil
states the sort of the reference, the checker verifies the kind's
inventory has the port. This is `ValuePort(node, name)` /
`FlowPort(node, name)` from `first-class-ports-design.md`, spelled.
There is no Branch construct in the text: a branch *is* a reference
to one output port of the split, so projection replaces the
satellite node.

Port inventories are per-kind and irregular (Commute has no value
ports; a register's read half has no flow outputs) — the syntax
never assumes a fixed shape.

### The implicit flow stack

Because a chain's value carries its context path, flow stages in
chain position need no operands:

- `-~> collect` closes the **innermost** layer of the incoming
  value's path.
- `-~> join` merges the **two innermost** layers (inner into outer).
- `-~> commute` swaps the **two innermost** layers.

Flatten-map, with no names at all:

```
rows -> open list -> open list -> double -~> join -~> collect => flat
```

This is well-defined, not merely convenient, because of the
adjacency requirement: binary join's operands must be
nesting-adjacent, and in a chain the inner operand can only be the
value's innermost unconsumed layer — the value couldn't cross it
otherwise. There is nothing to disambiguate. Reaching a *deeper*
layer is not done by naming it; it is done by more commutes, which
is semantically honest: commute variants exist per flow-kind pair,
and where no variant exists, reordering is rightly inexpressible.
The flow stack is a stack whose only rotation operator has real
semantics.

The old flowRef wrapper stack was this all along:
`Commuted(Joined(NodeFlow(…)))` read inside-out is postfix stage
order, and `ExprPrint` already renders joins as postfix `-> join`.

Flow stages accept an explicit operand when the implicit one is
unavailable or under-committed: `-~> collect ~O` (required when the
value is context-free — e.g. collecting a constant: `5 -~> collect
~L` builds a list of fives; the constant has no path to read the
flow off). Standalone, fully explicit forms also exist:
`~c.Even ~> join into ~L => ~keep`.

### Flow anaphora

For statements that are not in a chain and take a flow operand with
no value input to derive it from (`delay on`, `open … in`), bare
`~` denotes the innermost live flow at this point in the text and
`~^` the one outside it — de Bruijn indices over the textual open
stack. The span property (see "The crossing signal") makes them
trustworthy: in a well-formed program the textual open stack agrees
with the semantic context path, so the anaphora cannot lie except
in programs that are already ill-formed. Per P8 they desugar at
parse. The printer emits them sparingly (short range only).

### Junction taps: fan-out without names

A `|` mid-chain mints a **tap** — a junction on the wire at that
point. A line whose chain begins with `|` resumes from a tap:

```
a -> | b -> c -> d
| -> e                      -- a also goes to e
```

Generalized, multiple taps per line, `;` separating resumed chains:

```
a -> | b -> c -> | d
| -> e; | -> f              -- a goes to e, c's result goes to f
```

Mechanics:

- Binding is **ordinal**: the k-th leading `|` on a line binds to
  the k-th tap of the antecedent line. Never by column (P8);
  alignment is printer cosmetics.
- **Antecedent range**: leading `|`s refer to the taps of the
  nearest preceding line that minted any. Several consecutive
  continuation lines may reuse the same taps — pronouns bear
  repetition, so fan-out to three consumers is three `|` lines. A
  line that mints new taps replaces the antecedents. Anything that
  must reach further wants a name: pronouns for adjacency, names
  for distance.
- On the page, the leading `|` *draws the wire*: a junction dot on
  one line, the wire dropping a row to the next. The notation
  recovers a strip of the diagram's second dimension — vertical
  wire segments — in a form that is still ordinal, not spatial.

Multi-close on one opener, zero names:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Both bare `collect`s close the list flow; the tap carries the
element to both chains; the opener is shared through the tap.

### Lanes: labeled lines

Branch-shaped constructs — case splits, races, multi-branch
collects — are written one lane per line, `label:` first, no
separator (this frees `|` to mean exactly one thing, the wire
junction). A lane line's chain starts from that lane's value port.

A case split used linearly, with reconverging lanes gathered by an
exhaustive collect:

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                  -- gathers the lanes: the case close
-~> collect                  -- closes the list flow
=> out
```

Lanes that terminate independently (each ends in its own `=>`) —
the partition idiom, where each lane's bare `join` is the filter
(alt flow into list flow, both implicit):

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens
  Odd:  -~> join -~> collect => odds
```

The **gather rule** (stated without reference to indentation, per
P3/P8). A *lane line* is `label: chain` — the label either a bare
alt name or an explicit flow reference — or `value~` (an implicit
branch; see below). A *lane group* is a maximal run of lane lines.
Bare-alt labels resolve against an antecedent multi-port stage (the
statement the group follows); flow-ref labels and implicit branches
are self-identifying, so groups made of them need no antecedent.
The first arrow-led line after the group consumes the group's
branches (subsequent arrow-led lines continue the chain normally) —
except that a lane ending in a naming stage (`=> name`) is
*deferred*: it contributes no branch to the gather, and its flow
must be terminated elsewhere, by name. A lane may also terminate
its flow within its own chain (the partition idiom above); if every
lane is deferred or self-terminating, no gather follows and the
next line is a fresh statement. Provisional restriction: a lane's
chain is one logical line — a lane complex enough to span lines
should name the split and use projections. This rule is the one
place the notation leans on line structure rather than pure wiring;
it is flagged under "Open questions."

Standalone (non-fused) branch collects label lanes by flow
reference instead of bare alt name — used when the split is named
because its ports are consumed non-linearly. Flow-ref lanes are
self-identifying, so the group needs no antecedent and the collect
is written postfix, as the gather:

```
resp -> split status of Ok, Redirect, ClientError, ServerError => h
~h.ClientError: h.ClientError
~h.ServerError: h.ServerError
-~> collect => errCode, ~err   -- partial collect: value + merged flow
~h.Ok:       "ok"
~h.Redirect: "moved"
~err:        errCode -> describe
-~> collect => report
```

(A keyword-first spelling — `collect` above its lanes — is accepted
input, like prefix application; the postfix gather is canonical.)

Coverage is read off the cells, and the binder arity shows it — a
partial collect has the merged-flow output, a covering one does not
(`partial-collect-design.md`: one node, port inventory read off
coverage).

**Implicit branches.** A branch value that carries context can
supply its flow implicitly — read off its path, like every other
implicit flow. Inline, no new mark is needed: the `-~>` arrow sorts
the whole comma list, so `y, (~cs.Nothing: 0) -~> collect` says
each unlabeled item crosses with its flow. On a lane line there is
no arrow to do the sorting, so the mark is a suffix sigil,
`value~`. The suffix is the noun form of the arrow: prefix `~y` is
*the flow port of node y*; suffix `y~` is *the value y together
with the flow it lives in* — different things, mirror-image marks.
A context-free branch value (a constant) has no path to read, so it
must stay labeled; the checker demands of read-off flows exactly
what it demands of labeled ones (cells of one bundle, pairwise
disjoint, coverage read off the cells). Large collects probably
shouldn't be written this way — labels document the branch-to-cell
correspondence — but the form is consistent with the other implicit
areas, and consistency is what makes them learnable as one rule.

The fused lane form is sugar for this named form — lanes mint the
split's reference internally and each label is the projection. The
named form is the general one, and it honors P3 fully: nothing
requires a split's branches to be described together. One alt's
work can be built, unrelated statements can intervene, and the
other alts and the collect can come later — membership is dataflow,
not adjacency:

```
m -> split isJust of Just, Nothing => cs
cs.Just -> double => x
-- … unrelated statements …
~cs.Just:    x
~cs.Nothing: 0
-~> collect => out
```

Mixing is fine too: an alt handled as a fused lane deferred by
naming, the rest supplied at the eventual collect — the deferred
lane contributes no branch to a gather (the gather rule), so this
parses correctly even with the lanes adjacent:

```
m -> split isJust of Just, Nothing => cs
  Just: -> double => y
y~
~cs.Nothing: 0
-~> collect => out
``` Spread-out authoring is a path, not a
reading — the representation keeps only the wiring, so the
canonical reprint regroups statements into its own order ("many
authoring paths, few readings" applied to statement order itself).
And an unrelated flow opened and closed between the split and its
collect raises no false crossing signal: its span is contained, and
the derived indentation follows semantic depth, so it prints at its
own depth, visibly not nested in the alts.

Races are lanes too — the lane label carries the pairwise
correspondence across the barrier (P5); no tagged union exists
between the race and its collect. A race's lane labels *declare*
lane names (interpreted by the gather line's keyword) rather than
referencing an existing split, and its gather arrow is plain `->`
— contenders are values with no flow riding:

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

The concurrent join (product barrier) merges sibling flows —
genuinely not on one path, so its operands are named; in the
current lean it is flow-only and values combine in the merged
context:

```
~A, ~B ~> join all => ~ab
x, y -> add -~> collect => sums
```

If barrier value rows land (the open question shared by spec-Join,
race, and partial collect — "k branches × m value rows"), lanes
extend the same way, each row binding its crossing by label. Noted,
not committed.

### Opens, nesting, commute

```
xs -> open list => a, ~L
m -> open option => v, ~O
ys -> open list in ~L => y, ~Y     -- explicit outer-nesting
```

`open <kind> <input>` — the flow kind is part of the node (explicit
over implicit; no inference discovers it). Future kinds slot in
without new shapes: `open async`, `open stream`, `open var`,
`open pool(3)`, `open config sort`. The `in` clause is the spec's
`outerFlows`; when nesting is implied by the value input (opening a
value that is itself per-iteration), it is omitted; when neither
implied nor stated, the program is under-committed (below).

Commute in chain position is bare (`-~> commute`, swapping the two
innermost layers); standalone it names both operands, inner first —
join and commute operand order is semantic and must never look
symmetric:

```
~err ~> commute out of ~loop => c
-- ~c.outer : the flow that was inner (now outermost)
-- ~c.inner : the flow that was outer (now inside)
```

The defer-the-error idiom in chain form: `-~> commute -~> collect`
closes the loop first, leaving the option layer open for a later
collect.

### Registers: delay and write-back

The read half and the write half are two statements, matching the
two-phase construction (mint the read; wire the step later). The
write-back reads forward — compute, then deposit into the
register's step; the write node's output is the final value:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum          -- read half; bare `sum` = prev
sum, a -> add -> step of sum => total   -- write half; binder = final
```

`init` is the outside-the-flow initial value, kept syntactically
apart from per-iteration inputs (the misplacement that got
`stateful(initial, update)` rejected). Cross-referencing registers
are ordinary wires — Fibonacci:

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA
fa, fb -> add -> step of fb => lastB
```

A write statement's binder may be omitted when the final value is
unused (`sum, a -> add -> step of sum`). This is legal and
important: a write half can be root-unreachable in a complete
program, which is exactly why **a program is a node set with
distinguished outputs, not a root expression** — and why the
textual form is a statement list with declared outputs rather than
"the last expression is the result."

Even here text never forward-references: the write statement refers
*back* to `sum`. The productivity check (every cycle crosses a
register) is what guarantees a define-before-use ordering always
exists. The same spelling extends to the incremental kind's `hold`
if its cyclic uses (a var updated by events computed from its own
previous value) get the same read/write split.

### Diagram boundary

A file holds one or more diagrams. A diagram declares its boundary
ports; outputs are explicit statements (no implicit return — see
the node-set point above):

```
diagram sumOf
  in xs
  xs -> open list => a, ~L
  ~L ~> delay init 0 => sum
  sum, a -> add -> step of sum => t
  out total = t
end
```

Flow parameters use the sigil: `in ~io`, `out ~io2 = ~c.outer`.
Slots and calls of other diagrams follow the spec's FunctionCall
shape (named args); this section stays deliberately thin until
diagrams are the top-level structure in the code. For the sandbox,
a bare statement list with one `out` is a one-diagram file.

### Under-commitment and completion

A program whose flow structure is under-committed is *writable* —
sibling opens with no declared order, a combining node over
incomparable contexts. The closes name their flows explicitly
(nothing else could say which close is which):

```
listA -> open list => a, ~A
listB -> open list => b, ~B      -- sibling opens; no order authored
a, b -> add => s
s -~> collect ~A => inner
inner -~> collect ~B => out
```

Its meaning is its completion. The authored close order pins the
nesting — `inner` (the close of `~A`) is consumed by the close of
`~B`, so `~A`'s parent is inside `~B` — and the printer renders the
derived insertions as `+` lines (the convention
`time-travel-programs-design.md` already uses), reordering
statements as needed to restore token-order-is-time:

```
listB -> open list => b, ~B
+ listA -> incorporate in ~B
+   -> open list => a, ~A
a, b -> add => s
s -~> collect ~A => inner
inner -~> collect ~B => out
```

> *Correction (2026-07-09).* The inserted operator shown above
> follows the pre-Cross completion. Per `product-flows-design.md`
> (which revised the sibling-opens completion the same day this
> draft was written), sibling opens complete with a single inserted
> **Cross** — orientation from the authored close order — not an
> incorporate, which would erase their mutual independence.
> Incorporate remains the completion for bringing a *value* into a
> flow context. A textual spelling for Cross is owed when that
> design lands.

`+` lines are derived, deterministic, and not stored: parse
discards them and re-derivation reproduces them (conservativity,
idempotence, determinism). To override an inference, author the
line solid. A contradictory program (directed constraints cycle)
has no completion; it still parses and prints, and the *error*
carries the witness.

## The crossing signal: spans, verticals, indentation

The diagram shows an out-of-order flow use as a wire crossing. The
text has analogues in one dimension:

- **Spans.** A flow's *span* runs from the statement that opens it
  to its last termination. Because token order is time (P4),
  nesting shows as span containment and crossing shows as overlap:
  two *structural* flows whose statements interleave without
  containment is exactly the interleaving that needs an explicit
  relation (a join, a commute, a declared `in`). Effect flows are
  exempt — they commute freely and may interleave without remark
  ("most restrictive wins"). The **span lint** flags un-nested
  overlap of structural flows: a presentation-level early warning
  of the facts the provenance check establishes properly.
- **Verticals.** Junction taps and lane labels already draw the
  short vertical wire segments — local fan-out is *visible* as the
  `|` margin.
- **Indentation.** The canonical printer indents each statement by
  the depth of its flow context. Indentation is derived — the
  parser ignores it entirely (P3) — but on a well-formed program it
  reproduces the shape a scoped language would have had, without
  being scope. On a time-travel program, no consistent indentation
  exists; the printer falls back to flat and the completion's `+`
  lines say why. That failure-to-indent is the textual cousin of
  the visible crossing.

Significant whitespace was considered and rejected: indentation
must not become a second, authoritative statement of nesting that
can disagree with the wiring. One source of truth; indentation is a
view.

## Levels

Two senses of "level" need textual answers; they are different
things and get different answers.

**Flow nesting depth** gets no numerals and no annotation. Depth is
structural: an open `in ~L`, chained joins, chained commutes.
"Level-2 join" is two join stages. This follows the binary-join
correction — the old `Joined(Joined(…))` wrapper counting is
superseded by explicit staging.

**Transformation levels** are the real question. The stored program
is one step-DAG whose 1:1 steps read as node declarations — which
is exactly what a statement is (P7). So:

- A **snapshot file** (the common interchange case — "the program
  at this head") is a statement list containing only level-0
  statements. Every statement mints nodes; the file is the node
  set.
- **Level-1 statements** are the built-in catalog entries, written
  as statements whose operands are *names of nodes/steps*, not
  wires:

  ```
  sum -> expand => sumX      -- materialize sum's expansion, named
  sum!acc -> double => w     -- lens reference: DerivedPort(sum, acc)
  ```

  `expand` is a recorded step (its parts become addressable — the
  materialize mode); `!` is the lens mode — referencing a principal
  port of the *derived view* without materializing anything.
  `sum!acc` is the textual `DerivedPort(nodeId, portName)`, and
  only principal ports are addressable through it, so ill-formed
  references stay unrepresentable. No level marker is written or
  needed: `expand` is level-1 because its operand is a node, by the
  admission test.
- **History files** — serializing the full step-DAG including undo
  and cherry-pick — are deferred. Only the constraint is pinned:
  the snapshot grammar must remain a strict subset of the history
  grammar (a snapshot is a history with only 1:1 steps).

**Stable identity.** Node ids are load-bearing across versions
(diff, blame, completion hints anchored to ids). Names carry
identity *within* a file; across versions, the printer can be asked
to emit ids as suffixes (`=> sum@n42`). Default output omits them;
tools that diff or patch request them. Parse of an id-less file
mints fresh ids — correct for generated-from-scratch programs, and
the reason round-tripping *with* ids matters for edits.

## Worked examples

The core fragment (everything the code implements today):

Flatten with a shared constant:

```
ten = 10
[[1, 2], [3]] -> open list -> open list -> add(ten) -~> join -~> collect
=> out                                            -- [11, 12, 13]
```

Maybe-double (case split inside a list iteration, fused lanes):

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect
-~> collect
=> out                                            -- [2, 0, 10]
```

Multi-close via a tap:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Partition by filter joins (independent lane terminations):

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens
  Odd:  -~> join -~> collect => odds
```

Design-only constructs:

Running sum (register):

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
```

Timeout race:

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

HTTP status partial collect: see "Lanes" above.

Defer-the-error (commute):

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option layer still open
perElem -> summarize -~> collect => report
```

## Well-formedness: parser vs checker

The parser owns only what is lexically decidable:

- sort discipline (the right sigil and the right arrow where each
  sort is required);
- single assignment, definition before use;
- statement/stage shape per keyword;
- pronoun resolution (taps, lanes, `~`/`~^`) — all desugared to
  explicit wiring per P8, with their ordinal binding rules.

Everything else stays where it belongs — checks on the
representation, shared with every other authoring path: port
existence, flow-borne locality, join operand adjacency, collect
coverage and partial-collect cell disjointness, productivity and
one-write-per-register, provenance comparability with its two clash
flavors (time travel — completable; bundle mixing — not). The text
adds *no* checks of its own; the span lint and the indentation
signal are presentation-level renderings of checker facts. A file
can parse and still be ill-formed — necessarily so, since printing
ill-formed programs (to show the witness) is a requirement.

## Correspondence to the representation

For the fragment the code implements, the mapping to `Expr.res` is
direct:

| text | representation |
|---|---|
| `5`, `js "…"` | `Lit(JsAst.expr)` |
| `x, y -> f` (or `f(x, y)`) | `App({fn, args})` |
| `xs -> open list => a, ~L` | `Open({flow: ListIter, input})`; `a` = the node in value position, `~L` = `NodeFlow(node)` |
| `m -> open option => v, ~O` | `Open({flow: OptionIter, input})` |
| `-> split d of A, B => cs` | `Open({flow: CaseSplit({alts, discriminator}), input})` |
| `cs.A` / `~cs.A` | `branch_(NodeFlow(cs), "A")` in value / flow position (until first-class ports, when both become port refs) |
| `-~> join` (then `-~> collect`) | `close_(join_(NodeFlow(inner)), value)` — the chain determines the opener chain the compiler walks |
| lane `Even: -~> join -~> collect` | `close_(filter_(NodeFlow(branch)), value)` |
| lane group gathered by `-~> collect` | `caseClose([{altName, flow, value}, …])` |
| tap `\|` / anaphora `~` | nothing — desugared to shared references |

Under the first-class-ports migration the right column simplifies
(projections become `ValuePort`/`FlowPort` refs; Join becomes the
binary node and the chain's adjacency bookkeeping moves to the
checker), and the text does not change — the point of writing the
text against ports, chains, and names rather than against the
current wrapper encoding.

## Alternatives considered

**Conventional name-first, head-first syntax** (`b = double(a)`;
the first draft). Familiar — to people and to the LLMs that are
half the audience — but inconsistent about reading direction:
naming and application move backward through dependencies while
statement order moves forward. Rejected as the canonical form;
retained in full as accepted input, which recovers most of the
familiarity benefit at zero cost to the one-reading property.

**Brace-delimited fan-out** (`-> { -> f => a | -> g => b }`; also
first draft). Rejected twice over. First, braces read as scope in a
language whose defining move is that there is no interior scope
(P3). Second, the closing brace asserts a non-fact: it says "this
wire is not used again," but the language expresses the end of
interest in a value by silence — termination of a *flow* is
semantic and explicit (a collect, a join); termination of interest
costs nothing and should say nothing. Junction taps and lanes
replace it.

**Significant alignment.** Horizontal alignment as syntax (matching
taps by column, lanes by position on the page) is attractive and a
known disaster; all pronoun binding is ordinal (P8).

**Raw edge list / JSON dump.** Complete, trivially parseable,
unreadable — rejected as the primary form. (A mechanical JSON
projection of the node set may still exist for tooling; it needs no
design.) Note the statement form *is* an edge list, factored: one
line per node, inputs referenced inline — with the tree-shaped
majority collapsed into chains.

**S-expressions.** Tree-biased: sharing and cycles need labels
anyway, at which point the notation has all of this design's
machinery with less readability, and the tree bias invites writing
programs as expression trees, which the language specifically is
not.

**Keep authoring in ReScript (status quo).** Fine for the test
suite, useless for external tools: not parseable without a ReScript
toolchain, not printable back, and the smart-constructor layer is
an authoring convenience, not a stable interchange surface.

## Open questions

1. **The gather rule.** The rule as stated (lane lines — labeled,
   flow-ref, or `value~`; self-identifying groups need no
   antecedent; deferred lanes contribute no branch; race-style
   gathers interpret declaring labels) is ordinal throughout, but
   it is the one place the notation leans on line structure rather
   than pure wiring — the place a critic could say the syntax grew
   a scope after all. Needs the most careful specification; the
   provisional one-logical-line restriction on lanes (name the
   split for anything bigger) keeps it small until then.
2. **Tap antecedent range.** Proposed: nearest preceding
   tap-minting line; consecutive continuation lines may reuse; a
   new tap-minting line replaces. Alternatives (per-paragraph
   scope, explicit tap counts) exist if the proposed rule proves
   too subtle in practice.
3. **Glyph budget.** `->`/`~>`/`-~>`, `=>`/`=`, `|`, `~`/`~^`, the
   branch suffix `value~`, `!`, `@`, `+`. Each is cheap to respell;
   the family structure (sorted arrows, one meaning per glyph — `|`
   is only ever a junction) is the commitment. Watch `-~>` vs `~>`
   legibility, and whether the prefix/suffix `~` mirror (`~y` the
   flow port, `y~` the value with its flow) is mnemonic or too
   subtle in practice — alternatives: `y&`, a headless `y -~`.
4. **Stage extra-argument convention.** `-> f(e)` = topic-first.
   Fine for the current catalog; revisit if operations with
   non-leading principal inputs appear.
5. **Printer implicitness thresholds.** When to chain vs tap vs
   name; when to emit `~` anaphora (rarely or never); when a value
   leaf prints infix. ExprPrint's inlining heuristics are the seed.
   Canonical-form stability matters more than the particular
   choices.
6. **Alt-port naming scheme.** Bare alt name on both value and flow
   side (disambiguated by sigil) vs `(alt, Value)`/`(alt, Flow)`
   pairs — should match the spec's `outputName` so text and spec
   never need a translation table.
7. **Barrier value rows.** If Join/race/partial-collect grow the
   "k lanes × m value rows" shape, lanes extend by labeled rows;
   blocked on the representation question, correctly.
8. **Ids in interchange.** Is `@id` on every binder acceptable for
   tool round-trips, or does edit-patching want a sidecar (name ↔
   id map)?
9. **History serialization.** Undo/cherry-pick/materialize as
   statements are sketched, not designed; snapshot-⊂-history is the
   only commitment.
10. **Effect-flow threading.** Effect operations rebind their flow;
    the docs' prime convention suggests wanting light threading for
    long effect chains. Deferred until effect flows are closer to
    implementation.

## Implementation path

Baby steps, each independently useful:

1. **Core-fragment printer.** `TextPrint.res`: render any current
   `Expr.expr` in this notation. This grows directly out of
   `ExprPrint` — the topological sort, greedy chain detection, and
   name-at-fan-in machinery transfer; what changes is names instead
   of `#N`, taps for local fan-out, lane groups for case closes,
   and totality. One notation instead of two, eventually.
2. **Core-fragment parser.** `TextParse.res`: the grammar covering
   exactly today's `Expr.res` (lit/app/extern in all three fixities,
   list/option opens, splits with projections and fused lanes,
   bare and explicit join/filter/collect, taps). Output:
   `Expr.expr`.
3. **Round-trip tests.** For each of the 80 suite programs:
   `print → parse → compile → run` agrees with building the Expr
   directly; and `print(parse(t)) = t` on the printed text. Pin a
   few golden files.
4. **Span lint + derived indentation.** The presentation-level
   crossing signal, once the printer exists to host it.
5. Then track the representation: first-class ports (projections
   become port refs), partial collect, `+`-completion printing —
   each lands in the text the day it lands in the representation.
