# Program editing

Status: exploration — a worked design for how programs are edited,
prepared for a design conversation. Nothing here is implemented. The
target vehicle is a curses-style TUI over the textual form
(`textual-representation-design.md`); the graphical editor remains out
of scope in this repo, but the editing *model* below is written to be
vehicle-independent — the TUI and the eventual graphical editor should
drive the same edit functions over the same cursor vocabulary.

The one-sentence design: **an editor session is a working record
`{program, cursor, mark}` over the ports-first node set; the cursor is
a position in a three-sort algebra (node, output port, input slot);
every edit is a pure function from working record to working record
that preserves the representation's structural invariants; partiality
is made representable (dangling outputs are already legal, and a new
`Hole` node kind covers missing inputs) so that atomic validity never
forces an edit to do more than one thing.**

## What this is not

- **Not a text editor.** The TUI displays the canonical print of the
  program, but no keystroke ever edits text. Every action maps to an
  edit on the representation; the display is re-derived. The only
  text-entry anywhere is micro-entry *within one token* — typing a
  literal's payload, an extern's JS string, a name, an alt list.
- **Not the graphical editor.** No geometry, no layout, no mouse. The
  layout docs stay out of scope.
- **Not the history system.** The step-DAG of
  `transformation-levels-design.md` is where edits ultimately live;
  this document designs the edit inventory and cursor so they slot
  into that structure later, but the testable-now milestone keeps
  history as a plain undo list. See "Relation to the step-DAG."

## Requirements

1. **Atomic validity.** Each action transforms the working program
   from one valid configuration to another. "Valid" is defined
   precisely below (structural invariants, not semantic completeness —
   the distinction matters and is argued for).
2. **Functional.** The program in memory is immutable; an edit
   computes a new program from the old one. Persistent-structure
   sharing per `transformation-levels-design.md` ("nothing mutates").
3. **The cursor is data.** It is part of the serialized working
   record: rendered in the textual form, parseable back. A session
   can be saved and resumed as a file.
4. **Semantic anchoring.** The cursor references nodes, ports, and
   slots — never line/column offsets. When an edit reorders the
   canonical print, the cursor does not drift; the view re-renders
   around the same anchor.

## The method

The cursor's shape is decided by the process the design followed, kept
here as the reading order:

1. Enumerate the edits a user makes (the inventory below).
2. For each, write down the position information it needs.
3. Where the position information is unwieldy, either **(a)** derive
   parts of it from what the program already knows, or **(b)** split
   the edit into partial edits so each step needs less — accepting
   that this may require new *representable partiality* so every
   intermediate step is still a valid program.

Both reductions fire repeatedly, and they are what keep the cursor
small. The headline results: a wire needs no identity of its own
(derivable from its consumer end, 3a); flow operands are read off
context paths exactly as the text's implicit flow stack does (3a);
statement placement needs no position at all because statement order
is printer-derived (3a); two-endpoint edits split into mark-then-apply
(3b); and every node-add is completable in one step because
unsupplied inputs mint holes (3b).

## Step 1–2: the edit inventory and what each needs

Value edits:

| edit | position needed | cursor after |
|---|---|---|
| add source (literal, extern) | none — the node set has no "where" | new node's value port |
| append stage (new node consuming the focused value/flow) | one output port | new node's principal port |
| interpose (splice a new node into an existing wire) | one wire = one input slot | new node's principal port |
| delete, consumer-free node | node | its first input's producer port |
| delete-splice (1-in-1-out node; consumers rewired to its input's producer) | node | the surviving producer port |
| delete-to-hole (any node; consumers' slots get fresh holes) | node | the first hole |
| rewire a slot to a different producer | slot + new port | the slot |
| connect (fill a hole / feed a slot from an existing port) | port + slot | the slot |
| edit a literal / extern payload | node | unchanged |
| declare or retract a program output | port (declare), name (retract) | unchanged |

Flow edits (all are node-adds in ports terms, listed for their
operand shapes):

| edit | position needed | derived |
|---|---|---|
| append `collect` at a value carrying context | one value port | the flow operand — innermost layer of the port's context path |
| append `join` / `commute` in chain position | one value port | both flow operands, from the context path (adjacency makes it unambiguous) |
| standalone `join` / `commute` / `cross` | two flow ports | nothing — operand order is semantic; two-endpoint, so mark-then-apply |
| `open <kind>` | one value port (input) | nesting: implied by input's context, or left under-committed (time-travel completion owns it) |
| `split` | one value port + typed alt list + discriminator | discriminator may be a hole |
| `delay init` (register read) | one flow port + init value | init may be a hole |
| `step of` (register write) | one value port (the step) + the read node by name | the pairing is by reference, two-endpoint shape |

Node-local structural edits (position = the node, plus a sub-index
that is itself a slot in the vocabulary below):

| edit | sub-position |
|---|---|
| add / remove an App argument | arg index |
| add / remove a Collect branch | branch index |
| add / remove / rename an alt of a split | alt name |

Two observations before reducing.

First, almost everything is a **node-add**. The language has no
statement forms, no scopes, no declarations beyond nodes and outputs —
so the edit surface is small and uniform, and it grows automatically
as node kinds arrive: a new kind brings its port and slot inventories,
and the generic add/interpose/delete/rewire edits apply to it with no
editor work. This is "building blocks must build" applied to the
editor itself.

Second, the positions that appear are only ever: **nothing**, **a
node**, **an output port**, **an input slot**, or **two of those** —
never a region, never a path, never a textual location.

## Step 3: the reductions

**A wire is its consumer slot (3a).** Every input slot of every node
holds exactly one reference (`Program.inputs` enumerates them). So a
wire is identified by its consumer end alone; the producer end is read
out of the slot. The cursor never needs a wire sort — "on the wire" is
"in the slot."

**Flow operands come from context paths (3a).** The text's implicit
flow stack (`-~> collect` closes the innermost layer; adjacency makes
join/commute unambiguous) is a resolution rule on context paths, and
it transfers to the editor verbatim: with the cursor at a value port,
"append collect" needs zero further position information. The same
`Context.res` computation the checker and resolver share is the
editor's too — a third consumer of one derivation.

**Statement placement is nobody's decision (3a).** The program is a
node set; the canonical printer chooses statement order. Adding a
literal or extern therefore needs *no* position — the cursor's only
involvement is where it lands afterward. There is deliberately no
"between statements" cursor position: that would be a position in the
view, not in the program.

**Two-endpoint edits split via the mark (3b).** Connect, rewire,
standalone join/commute/cross, and the register write pairing all need
two positions. Rather than a fatter cursor (a pair sort, with all its
modal complications), the working record carries one optional
**mark** — a remembered output port. The gesture is: focus the source,
set the mark; move the cursor; apply the edit, which consumes the
mark. Between the two steps the program is unchanged — the mark is
session state, not program content — so atomicity is trivial. The mark
is the wire-level yank register, and one is enough: no surveyed edit
needs three endpoints (the register write's second endpoint is a node
reference, which the mark also covers). The textual form has this
same gesture as a pronoun: the value mark `^`
(`textual-representation-design.md`) is remember-then-use at the
notation's timescale, the session mark at the gesture's — and the two
meet in the display, below.

**Node-adds complete with holes (3b).** `add` needs two inputs but the
cursor supplies one. Instead of a modal "now pick the second operand"
flow (which would hold the program in an unrepresentable half-state,
or block atomicity on a multi-step interaction), the edit completes
immediately with a **hole** in each unsupplied slot: `x, ? -> add`.
The program after the keystroke is whole and printable; the holes are
first-class todo items the cursor can visit. This is the load-bearing
partial-program construct, designed next.

## Partial programs

Editing needs three kinds of "not finished yet," and they get three
different mechanisms — two of which already exist.

**Dangling outputs: already legal.** An unconsumed output port is not
an error — termination of interest costs nothing and says nothing
(the brace-rejection argument in the text doc), and the program being
a **node set with distinguished outputs** means root-unreachable and
not-yet-consumed structure is representable by construction
(`core-model.md`; `src/ARCHITECTURE.md`, "Node set from day one";
`visual-language-spec.md` notes the explicit node set "accommodates
partially constructed diagrams during editing" — this is that
payoff). Forward building — the postfix,
producers-first direction the whole textual design favors — therefore
never needs any partiality construct at all: at every keystroke the
frontier is a dangling output, and dangling outputs are valid. The
effortless path stays effortless.

**Missing inputs: the Hole node.** The dual gap — a slot whose value
is needed but not yet supplied — is not representable today, because
every slot must hold a reference. Rather than making slots optional
(which would put "is it connected?" checks in front of every consumer
of the representation, in every pass), a hole is an ordinary node:

```
| Hole({sort: holeSort})        // holeSort = HoleValue | HoleFlow
```

with port inventory `{value}` or `{flow}` by sort, no inputs, and no
semantics. Slots stay total; sharing works unchanged (two slots
referencing one hole is a real statement: "these two inputs will be
the same wire" — a planned fan-out); holes have ids, print, parse,
diff, and count. The checker gains one witness — `program contains
holes`, listing them — which gates codegen like any other
incompleteness. Value holes print `?`, flow holes `~?`; an anonymous
hole prints inline at its one use site (`x, ? -> add`), and a shared
hole gets a name by the ordinary fan-out rule (`? => h`) — the
naming machinery needs no special case.

One genuinely pleasant interaction: under the lazy compile strategy, a
hole can compile to a thunk that throws. Every binding is forced only
on demand, so **a partial program whose holes are never demanded runs
correctly** — you can test the finished half of a program while the
other half is still holes. Whether this ships as a dev mode or holes
always gate compilation is left open below; the runtime strategy makes
it free either way.

**Intended wiring: the planned wire.** The third kind of partiality is
intent: "this input will ultimately be fed from *that* port, but more
computation belongs in between." That is the dotted line. It is
represented as an annotation on a hole — a planned source:

```
| Hole({sort: holeSort, planned: option<ref>})
```

and printed as a standalone dotted-arrow statement targeting the
(necessarily named) hole:

```
? => h
total ..> h          -- dotted: total is intended to reach h, eventually
x, h -> add => y
```

A planned wire has **no semantics** — completion never reads it, the
compiler never sees it, checks do not enforce it (whether a lint
should warn when a discharged hole's replacement does not descend from
the planned source is an open question). It is authored intent made
visible: the editor renders the dotted line, the "next hole" motion
can prefer holes whose plans are dischargeable from the cursor, and
filling the hole deletes the plan along with it. Session-scale
partiality lives in the program (holes, plans, dangling outputs);
gesture-scale partiality lives in the session (the mark). That is the
boundary between the two mechanisms: the mark evaporates when the
session ends, a planned wire is still there next week.

**What is *not* a new partiality mechanism: under-committed flow
structure.** Sibling opens with no drawn nesting, deferred error
flows, missing `in` clauses — all already legal authoring, with
meaning supplied by the completion lens
(`time-travel-programs-design.md`). Editing composes with it rather
than duplicating it: the TUI renders the completion's `+` lines live
as you edit, which is exactly the editor experience that design was
written for. Holes and under-commitment are orthogonal axes of
partiality — a missing *value* versus an unsaid *ordering* — and they
coexist in one program.

## The cursor

### Definition

```
position =
  | Top                      -- the empty-program / whole-program position
  | OnNode(nodeId)
  | AtPort(nodeId, port)     -- an output port, value or flow sort
  | InSlot(nodeId, slot)     -- an input slot, value or flow sort

workingRecord = {
  program: Program.program,
  cursor: position,
  mark: option<ref>,         -- pending source for two-endpoint edits
}                            -- (the session-timescale value mark; see
                             --  "Rendering" for the display kinship)
```

Slots need names; the inventory mirrors the port inventory, per-kind
and irregular, promoted from the shape `Program.inputs` already
computes:

| kind | value slots | flow slots | node-local data (not slots) |
|---|---|---|---|
| Lit | — | — | payload |
| App | `fn`, `arg[k]` | — | arity |
| Uncollect | `input`; `disc` (case) | `nesting` | flow kind, alt list |
| Collect | `branch[k].value` | `branch[k].flow` | branch count |
| Join / Commute | — | `outer`, `inner` | |
| Cross | — | `left`, `right` | |
| DelayRead | `init` | `flow` | |
| DelayWrite | `step` | — | `read` (node pairing — an edge, not a port ref) |
| Hole | — | — | sort, planned |

Indexed families (`arg[k]`, `branch[k]`) are how node-local structural
edits address their sub-positions — adding a Collect branch is an edit
at `OnNode` that grows the family; the cursor can then descend into
the new `branch[k].flow` slot.

### Why these sorts and not fewer

**Port vs slot is the line-end distinction.** In HTML editing, the end
of one line and the start of the next collapse into one position, and
edits that need the distinction misbehave. The analogue here: in
`f -> g`, the output port of `f` and the input slot of `g` render at
the same arrow — and they are different positions, because edits
distinguish them. Interpose at `InSlot(g, input)` splices into *this
wire only*; a new node at `AtPort(f, value)` sits after `f` for *all*
its consumers (when `f` has one consumer the results coincide, which
is exactly why the positions must not). Similarly, delete-splice
around a node asks about the node; rewire asks about one slot. A
cursor that only knew nodes and wires would collapse these, and the
ambiguity would surface as modal questions at edit time — the failure
mode the position algebra exists to prevent.

**Node is not just "some port."** `OnNode` is where node-local edits
live (payload entry, alt lists, branch/arg arity, delete variants),
and some nodes' ports are all equally non-principal (Commute has two
flow outputs and no value port). The TUI reading: a statement line's
keyword is the node; its binders and projections are ports; its
argument positions and arrows are slots. Motion cycles between them.

**No wire sort** (derived — see the reductions) **and no region
sort.** Multi-node selection is deferred; nothing in the inventory
needs it, and the step-DAG later gives a better substrate for bulk
operations (replay, cherry-pick) than an editor-level selection would.

### What the cursor is not part of: step identity

The requirement says the cursor is part of the serialized
representation, and it is — but one boundary needs drawing carefully.
When the step-DAG lands, cursor *motion must not be a history step*:
polluting the program's identity with every arrow-key press would make
diffs meaningless and histories unreadable. The resolution is a
layering of the working record:

- **content** — the node set and outputs: the program of record, the
  only tier that step identity and `Program.equal` see;
- **presentation** — durable annotations that affect rendering but not
  meaning: authored names (today re-derived by the printer; an
  authored-name table is an open question shared with the text doc),
  planned wires arguably sit here in spirit though they ride on hole
  nodes;
- **session** — cursor and mark.

All three tiers serialize into one file (a session is resumable); only
the content tier is the program. Each recorded edit step *may* carry
its cursor-after as metadata — so undo restores the cursor to where
the edit happened, which is the UX everyone expects — without the
cursor entering any version's identity. This refines the prompt's "the
cursor is part of the program representation": part of the
representation, not part of the program. The alternative (cursor in
content, motion as steps, coalesced later) was considered and
rejected: coalescing rules are exactly the kind of accident-prone
machinery the persistent frame avoids everywhere else.

### Motion

Motion changes only the cursor; it is defined on the graph and merely
*displayed* through the text:

- **upstream / downstream** — from a slot to its producer's port; from
  a port to its consumers' slots (fan-out: ordered by canonical print,
  repeated presses cycle);
- **in / out** — cycle node ↔ its ports ↔ its slots;
- **next / prev statement** — canonical print order (the one motion
  defined off the view; it is stable because the printer is
  deterministic);
- **next hole** — jump to the next Hole node (canonical order). Holes
  are the program's own todo list, and this motion is the top-down
  authoring workflow: rough out the shape with holes, then visit and
  fill them.

Because anchors are semantic, an edit that makes the printer regroup
statements moves text around the cursor, never the cursor within the
program. The TUI keeps the anchor's glyph in view; that is a scrolling
concern, not a cursor concern.

## Atomicity: what "valid configuration" means

Validity is tiered in this design record (parseable / representable /
checked / compilable), and the editing invariant deliberately targets
the representable tier:

**After every edit, the structural invariants hold:** every reference
resolves to a node in the set; every referenced port is in its node's
inventory; reference sorts match slot sorts; ids are unique; the
object graph is acyclic (the register back-edge lives in the
write→read pairing, not the reference graph, so acyclicity is
uniform). These are the invariants `Check` assumes before it starts
and the printer needs to be total — a program satisfying them always
prints, always parses back, always diffs.

**Checked-tier properties are feedback, not gates.** Coverage,
productivity, provenance comparability, hole-freedom — an edit may
freely produce a program that fails these, and the TUI displays the
witnesses live (they are records addressed to node ids — built to be
rendered at anchors, same as the cursor). This is the textual form's
stance ("a file can parse and still be ill-formed — necessarily so")
carried into editing, and it is what the prompt's "partial programs"
concern resolves to: rather than weakening atomic validity, the
representation was extended (holes) so that the natural intermediate
states of editing *are* valid configurations.

Edits that would break a structural invariant are **refused whole**:
each edit is a total function returning the new record or a witness,
and refusal leaves the record unchanged. The two real cases: a rewire
or connect that would create a reference cycle (wiring an ancestor's
slot to a descendant's port), and sort mismatches (which the typed
edit API makes mostly unconstructible anyway). Refusal-with-witness
rather than clamping or auto-repair: the editor never does something
other than what the keystroke meant.

Deletion deserves its one paragraph: it is three edits, not one with
modes. Delete of a consumer-free node just removes it (its inputs'
producers gain a dangling output — legal). Delete-splice applies to
the 1-value-in/1-value-out shape and rewires consumers to the input's
producer — the exact inverse of interpose. Delete-to-hole is total:
consumers' slots get fresh holes of the right sort. All three are
atomic; none can strand a reference. (Under the persistent frame these
"deletions" build new versions that omit the node — nothing is
destroyed, per `transformation-levels-design.md`; consumers rebuilt by
the path copy keep their ids.)

## Rendering and parsing the cursor

Serialization keeps the grammar almost untouched: the working record
prints as the canonical program followed by trailing session
statements, and referenced nodes get id suffixes (`@n42`) exactly as
the text doc's stable-identity machinery already provides:

```
cursor at total@n9          -- AtPort: value-ref syntax (~name for flow ports)
cursor in add@n7:arg[1]     -- InSlot: node : slot-name
cursor on sum@n4            -- OnNode
cursor top
mark double@n3              -- the pending source, if set
```

`:` in slot references and the statements themselves are the only
grammar additions (plus `?`, `~?`, `..>` from the partiality
constructs). Parse accepts a file with or without session statements;
a program-only file loads with `cursor top`.

Display is a separate concern from serialization. The TUI marks the
anchor in place — the examples below use `‸` before the anchored
token. In-place display glyphs are renderer output, never parsed;
the trailing statements are the parseable truth. (Rendering both
would be redundant on screen; a saved file needs only the
statements.)

**Where positions render** is the definition/use distinction itself:

- An **output port** renders at its *definition site* — its binder
  name in a `=>` list, its tap `|`, its value mark `^`, or, for an
  anonymous chain value, the gap immediately after the producing
  stage's token.
- An **input slot** renders at its *use site* — the arrow that feeds
  it, a comma-list item, a `^` use, a stage argument, a leading `|`
  on a resume line.
- A **node** renders at its stage keyword or token.

Reading a chain left to right, the positions therefore interleave
with no collisions — `[node] [port] [slot] [node] …` falls on
`token, post-token gap, arrow, token` — and fan-out does not break
the scheme, because a port has exactly one definition site no matter
how many use sites its wire has. The pronoun tier is what makes this
work for anonymous structure: before the fan-in round, a computed
operand of a multi-input node had no textual site short of a minted
name — the notation's flattening problem and the cursor's anchor
problem were the same problem, and value marks solved both at once.

The **session mark displays as a `^` at the marked port's definition
site** (styled so it cannot be confused with an authored one). That
is not a pun: the session mark *is* a pending value awaiting its use
site, which is exactly what the glyph means in the notation — and
when a connect consumes it, the wire it creates is short-range
fan-in, which the canonical printer spells with the very same `^`.
The pending gesture solidifies into the pronoun. Serialization still
uses the trailing `mark` statement, never a dangling `^`, because an
unconsumed text-mark desugars to nothing and would not round-trip
(the note in `textual-representation-design.md`).

One printer obligation falls out, and it is the second face of the
line-end lesson: **every cursor position must have a textual anchor,
and the printer must materialize one when prettiness would elide it.**
The pretty form drops binders for unused ports, inlines single-use
literals, compresses chains; if the cursor (or a witness, or the mark)
references an elided element, the printer locally de-sugars so the
position is visible — reaching for the *lightest* sufficient anchor
first: break a chain at the stage, mint a tap or a mark, and only
past the pronouns' adjacency range mint a name ("pronouns for
adjacency, names for distance" governs materialization too). Cursor
presence changing the print is acceptable; a cursor with nowhere to
render is not. (This also keeps `print(parse(t)) = t` honest:
canonical-form stability is defined over program + session, and
materialization is deterministic given both.)

## The next step: legal edits, useful edits, and finding them

The inventory says what edits exist; atomicity says which applications
succeed. On top of both sits the discoverability question: at a given
position, **which edits should the editor offer, and in what order** —
how does the user find the step they need? The question has a precise
foundation, because determining whether a program is valid and
determining the valid programs one step away are the same relation
read in opposite directions. The checker (`types-design.md`) asks of
a finished wiring "does every demand meet a compatible offer?"; the
suggester asks of a position "which one-edit extensions would that
checker accept?" — the inverse image of validity, restricted to one
step. The types doc's no-search commitment is what makes the inverse
tractable: because checking is monotone propagation with no choice
points, suggesting is *enumeration* — the candidates are the finite
node catalog plus the program's own finite port set, and each
candidate's verdict is a propagation delta over a hypothetical
program, not a search. (Contrast unification-based systems, where
"what fits here" is a type-inhabitation query — exactly the searchy,
unexplainable shape the checker already refuses to be.)

### Eligibility mirrors the validity tiers

Validity is tiered (unrepresentable / structural invariants /
checked), and edit eligibility mirrors it tier for tier:

- **Sort-eligible** — the edit is constructible at the cursor's sort
  at all: only flow ops at a flow port, node-local edits at `OnNode`,
  interpose only in a slot. Hard tier: an edit that is not
  sort-eligible is not shown, exactly as an ill-sorted reference
  cannot be drawn.
- **Structurally eligible** — the edit's refusal condition would not
  fire: a connect from the mark that would create a cycle, a
  delete-splice on a node without the 1-in-1-out shape. Also hard:
  offering an edit that would be refused whole is offering a button
  that does nothing.
- **Property-eligible** — applying the edit would introduce no
  clash: the candidate node's demand is consistent with the offer
  derived at the cursor's port; the marked port's offer meets the
  slot's demand. This tier is **soft by principle.** Checked-tier
  properties are feedback, not gates ("Atomicity" above), so a
  clash-inducing edit is *ranked down and badged, never hidden*.
  Hiding would let the menu enforce what the check deliberately
  doesn't — and would guess wrong systematically during
  placeholder-driven building, where the demands in force are
  themselves provisional. This sharpens the types doc's scoping line
  ("checking validates choices; suggestion narrows menus; neither
  chooses"): *narrows* means orders and marks at the property tier;
  only the two hard tiers remove.

One consequence comes for free, and it is "building blocks must
build" a third time: the whole surface is generic. A new node kind's
catalog entry — port and slot inventories, demands, offers — is
exactly the data the three tiers consume, so a new kind appears in
the right menus, correctly ranked and badged, with no editor work.
Suggestion quality is a property of the catalog, not of editor code.

### The queries, one per cursor sort

- **At a value port**, with derived offer O: catalog nodes having a
  value slot whose demand is consistent with O — the append menu.
  The demand/offer inventory is the index; at a flow port the
  flow-kind table plays the same role (per-kind operation legality
  is the flow side's existing discipline).
- **In a slot or at a hole**, with accumulated demand D: the dual
  query, in two halves. Which *existing* output ports offer
  something meeting D — the connect candidates, dangling outputs
  first, a planned source first of all. And which catalog nodes'
  *output* offer would meet D — the interpose / build-backward
  candidates.
- **With the mark set**, the dual view travels with the cursor: the
  mark's offer against each slot's demand is one pre-checked
  verdict, so the TUI can render fit or clash on the mark's glyph as
  the cursor moves — and can highlight the slots and holes the
  marked value could legally land in. That is the "where can this
  go?" reading, dual to the palette's "what can go here?".

A hole is where the mirror pays most. The types doc's read-out 3
(placeholders) built the schematic source: a node with no
computation whose knowledge is declared offers and accumulated
demands. A hole is the same object reached from the other end — zero
declared offers, demands accumulated from its consumers — and those
accumulated demands are precisely the search key for its discharge.
"Next hole" plus the connect-candidate list is the top-down workflow
with the palette pre-filtered at every stop. (Whether `Hole` should
simply grow the schematic source's optional declared offers,
unifying the two constructs, is an open question below.)

### Witnesses are suggestions read backwards

The checker's witnesses are records addressed to node ids — built to
render at anchors. Each witness *kind* can carry its mechanical
repairs: a hole witness carries its connect candidates; a
missing-alt witness on a collect carries add-branch-for-that-alt; a
time-travel clash carries the nesting or cross insertions that would
relate the two contexts. A witness thereby becomes actionable —
cursor to its anchor, and pick mode opens on the repairs. This is
the same mirror at witness grain: a failed check names the family of
programs one edit away in which it passes; enumerate them. Not every
witness has a finite mechanical repair set (a shape clash may mean
the program is simply wrong), and the unlisted option is always that
the user redesigns; the repairs offered are the mechanical ones
only.

The symmetry runs the other way too: **suggestions carry positive
witnesses.** Why is `open list` offered here? Because the wire's
source offers *list-shaped*, from the collect there. That is the
same anchors-plus-path display as error explanation with the sign
flipped, so "explain this suggestion" costs nothing the error
renderer doesn't already have — and it keeps the surface honest, in
the record's standing sense: no offer appears without a reason you
can point at on the diagram.

### Useful: ranking without guessing

Legal is large — most of the catalog is sort-eligible at any value
port — and useful is an ordering problem. The ranking signals that
are not editor taste:

1. **Specificity of fit.** Candidates whose demands consume the
   strongest offers actually derived at the cursor rank above
   generic ones: at a wire offering *list-shaped*, `open list` beats
   any shape-indifferent App.
2. **The frontier.** Holes, planned wires, and witnesses are the
   program's own authored todo structure; candidates that discharge
   one rank above candidates that open new frontier.
3. **Observed frequency.** The standing method: sessions are
   serializable records, instrumentation is free, and once a corpus
   exists real edit frequencies rank the menu — read with the 80/20
   counterweight. Frequency decides what sits in the top rows and
   earns a single-keystroke binding; the rare legal edit stays
   findable (the full sort-eligible catalog remains reachable by
   filter), never removed for being rare.

And one boundary, drawn with the checker's own rule: **one step, no
search.** The suggester never synthesizes chains — "to get from this
offer to that demand, insert `parse` then `max`" is type-directed
program synthesis, which is search, the thing the no-choice-points
commitment excludes; and it would cross the scoping line from
narrowing into choosing. Multi-step intent already has an owner: the
user, via planned wires. At a plan the editor's whole role is to
prefer one-step candidates consistent with it — never to complete
it.

### Presentation

Pick mode *is* this computation rendered: rows are the sort- and
structurally-eligible candidates in rank order, clash rows demoted
and badged, filter-as-you-type over the rest of the catalog. The
palette is a derived view — computed from (program, catalog, cursor,
mark), lens discipline, never stored — so there is no suggestion
state to invalidate.

Because edits are pure functions on the record, **preview is
apply-print-discard**: highlighting a candidate can render its
post-state faint at the anchor without touching the real record, and
per-candidate property checking prices the same way (persistent
sharing plus boundary-projection memoization make the hypothetical
checks incremental). The faint preview is kin to the completion
lens's `+` lines and must be styled apart from them, because they
differ in exactly the dimension that matters: a completion is
committed meaning supplied by published rule; a preview is a
candidate carrying no commitment at all.

Gesture discoverability is the smaller sibling of node
discoverability and needs less: the edit inventory is short and
uniform (almost everything is a node-add), so a per-position hint
line listing the sort-eligible *edits* — not nodes — covers it, the
which-key idiom rather than a second palette.

## Worked sessions

Keystrokes are illustrative bindings, not proposals; the display marks
the cursor with `‸`. Assume `double` and `ten` exist:

```
double = js "x => x * 2"
ten = 10
```

**Forward build** — the effortless path, no holes, no mark:

| action | display after (cursor line only) |
|---|---|
| add literal `[1, 2, 3]` | `‸[1, 2, 3]` — cursor at its value port |
| append `open list` | `[1, 2, 3] -> ‸open list` — cursor at the element port |
| append `double` | `[1, 2, 3] -> open list -> ‸double` |
| append `collect` | `… -> double -~> ‸collect` — flow operand derived from context |
| declare output `out` | `… -~> collect => out` |

Every intermediate state is a valid program whose frontier is a
dangling output.

**Surgery** — interpose, then delete-splice, exercising the port/slot
distinction:

```
[1, 2, 3] -> open list -> double -~> collect => out
```

Move upstream from the collect's value slot: cursor lands
`InSlot(collect, branch[0].value)` — displayed on the `-~>` arrow.
Interpose `add(·, ten)`:

```
[1, 2, 3] -> open list -> double -> ‸add(ten) -~> collect => out
```

The second argument was supplied by name; had it not been, the edit
completes as `add(?)` with the cursor sent to the hole. Now
delete-splice the `add` (cursor `OnNode`): consumers rewire to
`double`'s port, restoring the original — interpose and delete-splice
are inverses, which is the shape the step-DAG's groupoid reading will
want edits to have.

**Fan-in** — the user makes graph gestures; the *printer* chooses the
pronouns. Nobody types `^` or `|`; they appear in the view when the
wiring becomes fan-out or short-range fan-in. Building
`range = sub(max(parse(data)), min(parse(data)))` from
`data -> parse` with the cursor at `parse`'s value port:

| action | display after |
|---|---|
| append `min` | `data -> parse -> ‸min` |
| set mark (at the focused port) | `data -> parse -> min ^` — the session mark, displayed with the notation's own glyph, styled |
| move upstream to `parse`'s port; append `max` | fan-out now exists, so the printer renders a tap: `data -> parse -> \| min ^` then `\| -> ‸max` |
| append `sub` | completes with a hole: `\| -> max -> ‸sub(?)` |
| next hole; connect (consumes the mark) | `\| -> max -> sub(‸^)` — the pending mark solidified into the pronoun |
| name the output `range` | `\| -> max -> sub(^) => range` |

Final display, zero minted names beyond the sources — the diamond
from the text doc's shape survey, produced gesture by gesture:

```
data -> parse -> | min ^
| -> max -> sub(^) => range
```

Every intermediate display is the canonical print of a valid program
plus session state; the `^` that marks pending session intent and the
`^` the printer emits for the finished wire are deliberately the same
symbol at two timescales.

**Top-down with holes and a planned wire** — the breadth path:

The user knows the end: a collected sum, but the summing chain isn't
designed yet. Build the collect first, against a hole; record where
its input will ultimately come from:

```
xs -> open list => a, ~L
? => h
h -~> collect ~L => out       -- explicit flow: a hole has no context to read
a ..> h                       -- planned: the chain from a will land in h
```

The `collect ~L` spelling is forced honestly — a hole carries no
context path, so the implicit flow stack has nothing to read, and the
text form already requires the explicit operand for exactly this case
(collecting a context-free value). The session continues by building
from `a` (append stages as in the forward build), and ends with
connect: mark the chain's last port, cursor to `h`'s consumer slot —
or just `next hole` — apply; the hole and its plan vanish, and the
program is the ordinary collected chain. Note the hole is *named*,
not value-marked: a mark is linear, parse-time, and gone on
round-trip, while a hole that persists across a session is durable
program content whose plan must target it by name — pronouns for the
gesture timescale, names for anything that outlives it.

## Relation to the step-DAG (the stretch goal)

`transformation-levels-design.md` already holds the theory the prompt
points at: program and edit history as one step-DAG; every step
stored once at its native level; the history of the history (and so
on — the infinite tower of edits-to-edits) collapsing by degeneracy
into that single structure; undo as a native level-1 step whose
storage aspect is an append and whose program aspect is a reset. This
document adds nothing to that theory and deliberately re-derives none
of it. What it adds is the constraint that makes the theory land
cheaply later:

**The edit inventory above is the candidate catalog of 1:1 steps.**
Each edit is specified as (pattern, result, cursor-after) with the id
discipline already matching the step-DAG's rules — adds mint ids,
path-copied consumers keep ids, delete-splice and interpose are
mutual inverses. When history lands, the edit functions become step
constructors verbatim; the editor's undo list is replaced by heads
into the DAG; nothing in the cursor or the TUI changes, because the
cursor was kept out of step identity from the start (the layering
above). The groupoid structure the prompt wants — edits, inverses of
edits, edits on the history — is then the recorded structure, with
the editing layer as its generator set.

Until then, the testable milestone keeps history as a list of working
records (persistent sharing makes this cheap), with undo/redo as list
navigation. That is deliberately throwaway — the `LegacyBridge`
pattern: a disposable stand-in that must never grow features.

## TUI consequences

Thin by design; everything load-bearing is above. The screen is: the
canonical print with in-place cursor/mark/anchor rendering, the
completion lens's `+` lines faint and live, and a margin for checker
witnesses (addressed to node ids, hence renderable at anchors). The
keyboard maps motions and the edit inventory; the only modes are
micro-entry (typing a payload, a name, an alt list) and a pick mode
for choosing an operation at append/interpose — the render of the
eligibility-and-ranking computation ("The next step" above): a menu
over the node-kind catalog plus named externs, sort-filtered,
rank-ordered, clash rows badged, filterable by typing. The TUI runs
on Node like everything else in the repo (raw-mode stdin + ANSI;
no dependency decisions needed yet).

## Philosophy check

- **Example first, then generalise.** Forward building — concrete
  values first, structure after — is the zero-machinery path;
  top-down structure-first authoring is possible (holes) but is the
  marked case, not the default. The editor's grain matches the
  language's.
- **Inside-out / cases as values.** There is no cursor position
  "inside" anything — positions are nodes, ports, and slots, full
  stop, mirroring the absence of lexical scope. Nothing about a
  position changes meaning by virtue of where it sits.
- **No bottlenecks.** Two-endpoint edits pass their endpoints as
  themselves (mark + cursor); nothing is packed into a compound
  cursor to squeeze through a single-position edit API.
- **Building blocks must build.** The +1 step of every program is an
  edit that adds structure; no edit rewrites the program into a
  different shape to proceed. And the editor itself expands
  gracefully: a new node kind brings its inventories and is
  immediately editable — no per-construct cursor code.
- **Abstraction is the source of truth.** Edits address the program
  of record; text is a derived view; the cursor anchors to identity,
  not to the view. The completion lens stays a lens — editing an
  under-committed program never solidifies inferred structure behind
  the user's back (overriding an inference is authoring, exactly as
  the time-travel design specifies).
- **Sample reality (standing method).** The inventory above was
  derived from the constructs, not from observed editing behavior —
  there is no corpus of sessions to sample yet. The counterpart
  obligation: once the TUI runs, instrument it (sessions are
  serializable records, so logging is free) and let real edit
  frequencies re-rank which gestures must be one keystroke — and,
  from the same corpus, the suggestion rankings above.

## Open questions

1. **Glyphs and spellings.** `?` / `~?` (holes), `..>` (planned
   wire), `:` (slot references), `‸` (display-only anchor), the
   `cursor at/in/on` + `mark` statements. All provisional; the
   commitments are only that holes are nodes, sorts stay lexically
   distinct, and session statements are ordinary statements.
2. **Hole compilation.** Always gate codegen, or ship the
   dev-mode lowering to a throwing thunk (making
   partial-but-undemanded programs runnable under the lazy runtime)?
   Leaning: ship it behind the same flag that prints witnesses rather
   than failing — the TUI wants "run what exists."
3. **Planned-wire discipline.** Purely advisory, or a lint when a
   hole is filled by something that does not descend from its planned
   source? Leaning: advisory; a plan is intent, and intent may
   legitimately change at the moment of discharge.
4. **Authored names.** The presentation tier wants a name table
   (ref → string) so user-chosen names survive reprints; today names
   are printer-minted. Interacts with text-doc open question 8 (ids
   in interchange) and should be decided with it.
5. **Fan-out cycling order** for downstream motion, and generally
   whether motion order should be canonical-print order everywhere
   (leaning: yes — one order, the printer's).
6. **Selection.** Multi-node/region selection is deferred until an
   edit demands it; candidates (extract-to-diagram, bulk delete) all
   look like step-DAG-era features, which may give a better substrate
   (select a step range, not a node region).
7. **Cursor-after conventions.** The table's choices are guesses at
   flow; real sessions (see the sampling note) should tune them —
   this is exactly the kind of question usage data answers better
   than argument.
8. **Micro-entry scope.** Payloads, names, alt lists are typed as
   text. Is an alt-list edit one micro-entry (retype the list) or
   structural (add/remove/rename alt as separate edits, enabling the
   step-DAG to see alt renames)? Leaning: structural — renames want
   identity.
9. **Hole vs schematic source.** Should `Hole` grow the schematic
   source's optional declared offers (`types-design.md` read-out 3),
   unifying two constructs that differ only in which direction their
   knowledge arrived from — declared forward vs accumulated
   backward? Leaning: yes — one node kind, offers optional, demands
   always accumulated; the types doc's placeholder workflow and the
   editor's top-down workflow become the same workflow.
10. **Soft-tier presentation.** Demote-and-badge is the stated
    stance for clash-inducing candidates; should a "strict palette"
    mode exist that filters the property tier, and is it
    default-off? Leaning: the stance as stated; a filter mode is UI
    policy, decidable later against real sessions.
11. **Repair catalogs.** Which witness kinds carry mechanical
    repairs, and is each kind's repair set hand-maintained alongside
    its check or derived from the check's definition? Leaning:
    hand-maintained to start — derivation smells like search, and
    the honest version of "this witness has no mechanical repair" is
    an empty list, not a synthesized one.
12. **Cost of hypothetical checking.** Rank by literally
    applying-and-checking each candidate, or by reading a pre-built
    index of the catalog keyed by demand/offer? Boundary-projection
    memoization may make the former cheap enough at interactive
    rates; if not, the index is an approximation whose divergences
    from the real check need stating. An implementation question,
    but it decides whether ranking signals stay exact.

## Smallest first step

No TUI in step one; the model is testable headless, in the
`Main.res` smoke-suite style:

1. **`Hole` in `Program.res`** — the kind, its inventories, `dump`
   support, the hole-listing check witness.
2. **`src/Edit.res`** — the working record and the edit
   inventory as pure functions with refusal witnesses; structural
   invariants stated as an internal assertion pass (debug builds
   re-verify after every edit).
3. **Session round-trip** — `TextPrint`/`TextParse` grow the session
   statements, `?`/`~?`/`..>`, slot references, and the
   anchor-materialization obligation; `parse(print(record))` equal on
   all three tiers.
4. **Scripted-session smoke tests** — the worked sessions above as
   code: a list of edits applied from the empty record, asserting the
   print after each step (this doubles as the golden record for
   cursor-after conventions).
5. **`Edit.eligible`** — the eligibility computation as a pure
   function `workingRecord => array<candidate>` (candidate = edit +
   tier + rank signals), headless-testable: assert the candidate
   lists at chosen stops in the scripted sessions. The two hard
   tiers need no property machinery and can land first;
   property-tier ranking arrives with the types doc's shape
   propagation (its smallest-first-step 2) and slots in without
   changing the function's shape.
6. **The TUI shell** — a thin loop mapping keys to motions and edits
   and re-printing; by this point it contains no logic worth testing
   through the terminal.

Step 4's artifacts — serialized sessions — are the seed corpus for the
sampling obligation in the philosophy check.
