# Time travel programs

Or: programs that leave their loop order unsaid, and how the editor
fills the gap in.

Status: mixed — **2026-08-12 update**: the sibling-opens completion
core (Worked Example 1 below — inserting a Cross for sibling list
opens) is implemented, in `Complete.res`, and tested at any rank (Main
tests 10/10c/10e–10h; see `src/ARCHITECTURE.md`'s Complete row). The
rest of the chapter remains design-only: the canonical-commute table
(Worked Example 2) and the heuristic ordering (Worked Example 3) are
not implemented — read those sections as "here is a candidate and the
case for it." It takes up the old
`flow_language_design.md`'s Future Work #1 ("pull-based to explicit
transformation") in current vocabulary; that doc is retired, its core
now in `core-model.md`. Throughout, "uncollect" and "collect" name
what the code still calls Open/Close, per `lazy-stream-join-design.md`.

The idea in one sentence: an under-committed program — one that leaves
some of its flow nesting unsaid — is a *legal thing to author*, its
meaning is the fully-committed program the published rules complete it
to, that completion is shown faint and compiled by translation only,
and no reading ever violates no-time-travel.

## A program that leaves something unsaid

You have two lists of numbers, and you want to add elements of one to
elements of the other. Here is the program you would naturally draw:

```
listA -> open list => a, ~A
listB -> open list => b, ~B      -- sibling opens; no order authored
a, b -> add => s
s -~> collect ~A => perB         -- collect A's flow first…
perB -~> collect ~B => out       -- …then B's
```

(A quick word on the notation, which is from
`textual-representation-design.md`: opening a list produces two
outputs, so `=> a, ~A` names both — `a` is the element, one at a
time, and `~A` is the flow, the "once per element of A" context those
elements arrive in. `collect ~A` gathers a value back up over that
flow.)

Read the program as the gesture it is: *here are the elements of A,
here are the elements of B, add them, gather up the sums.* Perfectly
natural. But notice what the program never says: **which loop is
inside which.** The two opens sit side by side — they are *sibling
opens*, with no drawn nesting — and at the moment you drew the `add`,
nothing anywhere said whether A's iteration runs inside B's or the
other way around.

This chapter's proposal is that the editor accepts this program and
fills in the missing piece for you, displayed in a fainter color so
you can always tell what you drew from what was inferred. In the
textual form, faint is a leading `+`:

```
listA -> open list => a, ~A
listB -> open list => b, ~B
+ ~A, ~B -> cross => ~A2, ~B2    -- A2 nested inside B2; orientation from collect order
a, b -> add => s
s -~> collect ~A2 => perB
perB -~> collect ~B2 => out
```

The inserted `cross` nests A's iteration inside B's — you will see
below exactly what forced that orientation (short version: your
collects did). The reading of the completed program: for each `b`,
the list of `a + b` over all of A; `out` is a list of lists.

A program like the authored one — legal to draw, but leaving some of
its flow structure uncommitted — is what this chapter calls a **time
travel program**. The name comes from the rule it appears to bend,
which you need to meet before anything else makes sense.

## The rule this program bends

The **no time travel** rule (`core-model.md`, "No time travel") is the
oldest structural law in the design:

> Flow ordering and nesting are fixed at construction time, never
> determined retroactively by an operation added later.

Under that rule as originally stated, the program you just drew is
*forbidden*. Walk through why. At `add`, `~A` and `~B` have no
ordering relationship — nothing yet says whether A's iteration runs
inside B's or the other way around. Which loop body the `add` lives in
is undefined at the point it is drawn. Only the collects settle it:
`perB` (the collect of `~A`) is itself collected over `~B`, so `perB`
must live in `~B`'s context, so `~A` must be nested inside `~B` — A is
the inner loop. A downstream consumer clarified an upstream node's
meaning. That is the time travel, and the rule bans it: as drawn, the
program is ill-formed. The sanctioned fix under the strict rule is to
bring `listA` into B's flow — capture it and uncollect it there — so
the nesting exists at the moment the `add` is drawn.

The rule is right, and nothing in this chapter weakens what it
protects. What it protects is the **reading**: one program, one
obvious meaning, fixed by structure that is on the diagram, every
semantic fact owned by a drawable witness. The whole downstream
architecture leans on it. Context paths are read off the construction
(`bundle-provenance-design.md`); the compiler trusts nesting so
completely that `deeper(a, b)` never checks it (the "honoured semantic
limitations" list); and the first check `types-design.md` schedules is
exactly the one that would make that trust explicit.

So the question this chapter answers is: how do you keep everything
the rule protects, while still letting you draw the program the
natural way?

## Why you'd want to draw it that way at all

The observation this chapter takes seriously: **at authoring time you
want the opposite rule.** It is easier to program that way.

**"The elements of A" behaves like a value.** The inside-out principle
says cases are values you flow through, not scopes you write inside.
Applied to iteration: the element wire of an uncollect is a value you
compute with, and computing with it should not first require settling
which loop encloses which. The program above is the natural gesture —
*here are the elements of A, here are the elements of B, add them* —
yet the strict rule's sanctioned form makes you decide the loop
structure before you may write the addition. That is structure
declared upfront, before the concrete computation: the exact shape
example-first suspects everywhere else. Under-committed authoring is
example-first applied to flow structure — write the value computation
concretely, let the nesting be identified afterward from what you did
with the results.

**Deferred error flows** are the stronger version of the same wish. A
pipeline whose per-element step can fail (an option or result flow
opened inside a loop) reads best as: compute with the successful value
as if failure didn't exist, and collect the dangling error flows at
the very end, outside everything. The vocabulary for the *result*
already exists — the spec's Commute node plus the "defer the error"
idiom (`visual-language-spec.md`, Commute) is exactly "commute the
error flow out of the loop, close the loop, handle the error flow
later." The wish is to author the idiom without drawing the commute.
(You will see this worked in full below.)

**This is a known, well-liked shape.** In conventional languages you
have already met it. Java's unchecked exceptions thread the error path
through every frame without any frame mentioning it. Koka's effect
rows are commutative — every pair of effects has a canonical commute,
so the user never orders them and the system's ordering choices are
unobservable by construction. The common structure: an implicit
mechanism is safe when its resolution is **canonical** — fixed by
rule, not searched for — so the user's ignorance of the details can
never change which program they get.

And in fact, the design has quietly been moving this way already:

- **Capture is already implicit.** The old design demanded an explicit
  CAPTURE node to bring a constant into a flow; the implemented
  compiler never asks for one. A Lit is memoised at the top level and
  referenced from any loop body; an App binding is placed at
  `deeper(args)` and referenced from deeper bodies freely.
  Auto-capture is a canonical elaboration the compile has performed
  silently from the start, and nobody has ever missed drawing a
  CAPTURE node.
- **Marker × marker commutes are free.** The commute-variant taxonomy
  (`lazy-stream-commute-design.md`) already contains the Koka
  observation: where neither flow has runtime content, commutativity
  is free and no node is needed.
- **The naturality quotient.** The Commute node carries no value
  ports, so map-then-commute and commute-then-map are the same
  diagram — sliding a commute along the value chain changes nothing,
  because there is no value chain through it. (This
  everything-slides-freely property is called *naturality*.) When a
  commute is *inserted*, there is therefore no spurious freedom about
  where along the value chain it goes — the syntax has already
  quotiented that choice away.
- **`deeper` is a degenerate elaborator.** Handed a time-travel
  program today, the compiler does not reject it — it silently picks a
  nesting (whichever scope compares deeper) and emits JS whose meaning
  is an accident of the comparison. Read uncharitably, the honoured
  limitation is an unprincipled version of exactly this feature. The
  job is to make the pick principled, canonical, and visible.

## The reconciliation: the rule governs readings, not gestures

The philosophy already contains the resolution: **many authoring
paths, few readings.** Discoverability (many ways to write) and
readability (one way to read) live at different layers and are not in
tension.

So: a **time travel program** is an *authoring-level* artifact — a
program whose flow structure is under-committed. Opens with no drawn
nesting; error flows collected outside the flows they were opened in;
combining nodes whose operands' contexts are not yet comparable. Its
**meaning** is its **completion**: the no-time-travel program obtained
by inserting the missing flow structure. The rule is not repealed; it
is relocated. It remains the unconditional law of the *reading* —
every completion satisfies it — and stops being a constraint on the
*gesture*.

Three commitments, fixed up front:

1. **Zero runtime.** Time travel programs are compiled solely by
   translation to no-time-travel programs. There is no runtime
   representation of "unresolved nesting," no dynamic dispatch on flow
   order. The compiler consumes the completion exactly as it consumes
   every other derived view ("the compiler is just another consumer of
   the derived view," `transformation-levels-design.md`).
2. **The completion is derived, never edited.** The time travel
   program is the program of record — the *more abstract* form in the
   philosophy's sense: less committed, the highest-level true
   description. The completion is a read-only lens on it, always
   available, lazily materialized. Derivation is free and downward,
   and completion *is* the downward direction: dropping "combine these
   elements" to "…with A's iteration inside B's" is derivation;
   recovering the uncommitted form by eliding canonical structure is
   the earned upward direction.
3. **The completion is deterministic — ruled, never searched.**
   Completion is total up to contradiction: except where the
   constraints genuinely cycle, every program gets exactly one
   completion, produced by published rules — the forced consequences
   of authored structure, then the canonical table, then the heuristic
   order. The elaborator (the machinery that computes the completion)
   never scores or backtracks over candidate programs. It does *pick*
   where the program leaves genuine freedom, and where a pick is only
   a heuristic the design says so plainly. Predictability is the
   product: same program, same completion, every pick on screen.

What makes the arrangement safe is the lens. **The editor displays the
inferred operators in place, in a fainter color**, so inferred and
authored structure are distinguishable at a glance. There is no accept
or reject gesture, because none is needed. If you like where an
operator was inferred, you do nothing — it is already there and it
already is the reading. If you want it placed differently, you draw a
real commute or incorporate where you want it; the more specific
program necessarily excludes the inference you didn't like, and the
lens re-derives around the authored operator. You never say "that
inference was wrong" — only ever what you mean. Explicit structure
always preempts insertion, and a complete program completes to itself.

In the textual form the faint rendering is the `+` prefix
(`textual-representation-design.md`, P6): completion's inserted lines
print with a leading `+`, a complete program has none, and parse
discards `+` lines because they are re-derived, not stored.

## What completion inserts, and what forces it

### The insertion inventory

Completion inserts **flow bookkeeping only** — two families:

- **Incorporate.** Making a value more *context-specific* — its
  value-level shadow is the identity: incorporation changes what
  context a value is available in, never the value. Two axes, one
  relation: bringing a *value* into a flow's context (the old design's
  CAPTURE), and narrowing a value across a **bundle** to a more
  specific cell set. The cell-axis case completes an overlapping-bundle
  *combine*: two values at incomparable sets `{A,B}` and `{B,C}`
  combine at the meet `{B}`, reached by incorporating each operand
  there (`bundle-provenance-design.md`, "Revision: overlap is
  incorporate, not a clash"). Both axes obey the "last available
  opportunity" rule — incorporate as late / as agnostically as
  possible, keeping computation outside the loop — and both surface as
  the same faint derived node, elided when obvious (a constant in a
  loop, a subset narrowing) and shown when surprising.
- **Cross.** Nesting two *sibling* opens — two independently opened
  flows with no drawn nesting. This is what turns "sibling opens" into
  "nested opens," and it is what the opening example's faint line
  inserted.

  Now, you might wonder why the language doesn't just use Incorporate
  here too — bring one open's source into the other's flow and be done
  with it. It turns out this would cause problems: incorporating an
  uncollect source would erase a fact the authored program carried.
  Sibling opens are mutually invariant by construction — neither's
  elements depend on the other's — and the incorporated form would
  read as dependent nesting, indistinguishable from an inner source
  computed from the outer element. Cross nests the flows while keeping
  the mutual-constant relationship, and passes the same
  identity-shadow admission test (`product-flows-design.md`).
  Incorporate remains for the value case only; Cross owns the
  flow–flow case. (This is a settled rejection — please don't
  re-propose incorporate-for-siblings without new evidence.)
- **Commute chains.** Commute nodes lifting a flow across enclosing
  flows toward its canonical position. Value-level shadow: none at
  all — the node has no value ports, and naturality means the
  insertion carries no placement choice along the value chain.

Yes, that was three bullets for "two families" — Cross is the
flow-flow sibling of Incorporate, and the two together are the first
family (context assignment); commute chains are the second (lifting).

And, by design, two **non-families**. You might wonder why completion
stops at bookkeeping — why, if it can see that a flow was never
closed, it doesn't helpfully insert the missing collect, or a join, or
a filter. It turns out this would cross a line the design holds
firmly: joins, filters, and collects change **firing structure** —
which iterations happen, what gets kept — and firing structure is
meaning the user must draw. So:

- **Never value nodes.** Completion inserts nothing a value wire
  passes through.
- **Never joins, filters, or collects.** Every termination in the
  completion is one the user authored; completion only makes the
  authored terminations well-placed.

(This is a settled boundary — completion inserts bookkeeping, never
meaning; please don't re-propose inserted terminations without new
evidence.)

The principled line: **completion inserts only operations whose
value-level shadow is the identity.** (This is the same species of
pure-structure content that makes a conversion irreducibly level-1 in
`transformation-levels-design.md` — a first hint that completion
belongs in the level-1 catalog; see "Where it sits.")

One honest wrinkle on "identity shadow": inserting a Cross (or an
incorporate) assigns a multiplicity — crossing `~A` inside `~B` means
A's uncollect now fires per B-element, n×m in total. That is not the
insertion changing a defined meaning; the authored program had no
defined multiplicity, and the terminations the user drew are what
force this one. Completion never *overrides* an authored meaning; it
*supplies* the meaning the authored structure left open — forced where
the constraints force it, canonical or heuristic where they don't.

### The rules, in strength order

What exactly is unknown in an under-committed program? The authored
opens form contexts, but the context *tree* is incomplete — some
contexts have no drawn parent. Completion is the assignment of the
missing tree structure (each assignment realized as a Cross or
incorporate insertion, so the result is drawable, not annotated), plus
the commute chains that reconcile authored terminations with the tree.

The constraints, in strength order:

1. **Explicit structure is fixed.** Drawn incorporates, crosses,
   joins, commutes, and the input-derivation chain ("this inner list
   is produced by the outer flow") are never revisited. A complete
   program is its own completion, verbatim.
2. **Terminations direct.** A collect converts a flow's firings into a
   value at the flow's parent context; where that value is *consumed*
   therefore pins the parent. In the two-lists program, `perB` is
   collected over `~B`, so `~A`'s parent must be `~B`'s context — a
   directed edge, A inside B. This is the retroactive determination
   the rule forbade, now read deliberately as an authoring signal. It
   is exactly `bundle-provenance-design.md`'s collecting-node demand
   ("each branch's value path is a prefix of its cell's path") run in
   reverse: instead of verifying the path, solve for it.
3. **Authored flow operations direct.** Join is not symmetric — its
   operands are (outer, inner) — so a drawn join between flows whose
   contexts are not yet related *orders* them: the inner operand's
   flow must end up nested within the outer's. Commute likewise names
   both operands and which is which. Two independently opened flows
   brought to a join are ordered by the join itself; there is no
   separate ambiguity to resolve.
4. **Combining nodes connect.** An ordinary multi-input node whose
   operands live in incomparable contexts contributes an *undirected*
   edge: the two contexts must end up on one root-to-leaf line, either
   way around. This is the comparability demand of
   `bundle-provenance-design.md`, relaxed from "verify" to "achieve."
5. **Canonical commutes break ties that carry meaning.** Per flow-kind
   pair, a canonical direction, applied only where 1–4 leave the order
   free. The inaugural entry: **option/error flows commute outward** —
   a dangling failure flow collected outside the flows it was opened
   within lifts across each of them via inserted Commutes. This is the
   Koka move: the canonical direction is part of the language
   definition, a fixed table, not a per-program judgment.
6. **Heuristics break the rest.** Even after 1–5 fix the context tree,
   more than one arrangement of the inserted operators can realize
   it — genuinely distinct no-time-travel programs with nothing
   principled to choose between them. A published, ordered list of
   heuristics picks one. Inaugural entry: **join as early as
   possible** — when a drawn join's operands could be joined either
   before or after an inserted commute chain, join first and commute
   the combined flow. In the cases seen so far the candidates a
   heuristic chooses among are naturality-equivalent — related by
   sliding commutes and joins past each other, so the pick is closer
   to a spelling than a behavior — but it is a heuristic, not a
   principle, and the design says so plainly. What it buys is
   predictability: the user can learn the rule and the faint rendering
   shows its every application.

Solving is partial-order extension over a finite set — arranging a
finite set of contexts into a tree consistent with the directed
edges — with every tie broken by a fixed published rule rather than by
search. No scoring, no backtracking, no per-program judgment. That is
the form of `types-design.md`'s no-search commitment that survives
here: the solver never *finds* a completion among alternatives; it
*computes* the one the rules name.

### The four dispositions

A comparability failure — the thing the checker would report as a
time-travel clash — now lands in one of four bins:

1. **Determined.** Constraints 1–4 force a unique completion. The
   two-lists program from the opening: the collect order directs,
   completion inserts one Cross, done. No canonicity needed.
2. **Canonically completed.** The order is genuinely free but a
   canonical rule covers it. The deferred-option program (worked
   example 2 below): nothing in the terminations says where the error
   flow sits except "outside," and the canonical outward commute
   supplies the exact chain. Why the table's first entry is safe:
   option-against-option ordering is observationally symmetric —
   running either order, you cannot tell them apart —
   `join(option, option)` fires iff both fire, an AND, and a
   payload-free None carries no information about *which* absence
   occurred — so any consistent pick is sound, the same argument Koka
   makes for commutative effect rows. The moment payloads appear the
   symmetry breaks and a pick becomes observable; it is still made,
   and still rendered faint.
3. **Heuristically completed.** More than one completion survives 1–5
   and the heuristic order picks (worked example 3 below). Now, you
   might wonder why the language doesn't simply refuse here — report
   "ambiguous, please draw the commutes yourself" instead of picking.
   It turns out refusing would make the most natural authoring
   gestures dead ends: a program in this bin *has* readings, and
   declining to pick would leave a perfectly reasonable gesture with
   no reading at all. So completion picks, labels the rule a
   heuristic, renders the result faint, and is excluded the moment the
   user draws the operators where they actually want them. (This is a
   settled decision — completion always picks; the open questions
   below record what remains genuinely open about the heuristic list
   itself.)
4. **Contradictory.** The directed constraints cycle: one
   combining-and-collecting chain forces A inside B, another forces B
   inside A. No completion exists. This is a clash in the full
   `types-design.md` sense — *this cannot mean anything* — with a
   two-anchor witness: the two termination chains whose directions
   collide.

   This disposition mostly **dissolves**. When the colliding chains'
   flows are mutually invariant sibling opens, both orders are
   legitimate readings of one product, and completion inserts a single
   Cross (plus a faint Commute for the reversed chain); nothing is
   duplicated, neither opens nor work (`product-flows-design.md`).
   What remains genuinely contradictory: constraints that cycle
   *within one termination chain*, a reversed-order demand on a
   genuinely dependent nesting (no product exists to transpose), and
   bundle mixing.

On that last item: you might wonder whether completion could rescue
**bundle mixing** too — after all, it rescues ordering clashes, and
bundle mixing is the other clash flavor. It turns out it cannot, and
the reason is worth stating because it retroactively justifies the
care `bundle-provenance-design.md` took in keeping the two clash
flavors distinct. Two sibling *cells* of one case split (a Just-value
and a Nothing-value of the same dispatch) have a canonical pairing and
never coexist — no insertion of crosses or commutes can create a joint
firing, so there is nothing for completion to complete. Time travel is
elaborable because the missing fact is an *ordering*; bundle mixing is
uncompletable because the missing fact is an *execution that doesn't
exist*. (Settled: bundle mixing stays an error, always.)

## Worked examples

### 1. Sibling lists (determined)

This is the opening program, now with its constraint walk. Authored:

```
listA -> open list => a, ~A
listB -> open list => b, ~B      -- sibling opens; no order authored
a, b -> add => s
s -~> collect ~A => perB         -- collect A's flow first
perB -~> collect ~B => out
```

Constraint walk: the collect of `~A` outputs `perB` at `~A`'s parent;
`perB` is collected over `~B`, so that parent is `~B`'s context (rule
2, directed). The `add`'s comparability edge (rule 4) is satisfied by
the same assignment. Unique tree: root → `~B` → `~A`.

Completion (inserted structure faint, marked `+`; Cross spelling
provisional — a textual form for Cross is owed when that design
lands):

```
listA -> open list => a, ~A
listB -> open list => b, ~B
+ ~A, ~B -> cross => ~A2, ~B2    -- A2 nested inside B2; orientation from collect order
a, b -> add => s
s -~> collect ~A2 => perB
perB -~> collect ~B2 => out
```

Reading: for each b, the list of `a + b` over all of A; `out` is a
list of lists. Had you collected in the other order, the same
machinery would have derived B-inside-A — the authored gesture is
symmetric, and the terminations are the commitment. The Cross
preserves the two flows' mutual invariance instead of lowering to a
dependent-looking nesting; an incorporate would have read as "A
computed from b," which is a different program.

### 2. Deferred errors (canonically completed)

Authored — parse every element, use the parsed values as if parsing
never failed, deal with failure at the very end:

```
items -> open list => item, ~L
item -> parse -> open option => val, ~E   -- option flow, opened inside ~L
val -> process => r
r -~> collect ~L => results               -- close the list flow, in place
results -> summarize -~> collect ~E => final   -- close ~E at the root, outside
```

`~E` is opened inside `~L` but terminated outside it: the collect over
`~L` holds a value that lives under `~E`, and `~E`'s own collect is
consumed at the root. No termination *direction* is in question (rule
2 pins everything); what is missing is the lift. The canonical outward
commute (rule 5) supplies it:

```
+ ~E ~> commute out of ~L => x   -- error now outer (x.outer), loop inner (x.inner)
r -~> collect x.inner => results
results -> summarize -~> collect x.outer => final
```

This is letter-for-letter the spec's defer-the-error idiom — the
completion *is* the idiom; the time-travel form is the idiom with the
commute left unsaid. Meaning: fail-fast — `final` is the error if any
element's parse failed, the processed results otherwise, compiled by
the already-designed commuted-collect output construction with its
short-circuit.

Worth pausing on how this preserves one-obvious-reading. Fallible-
per-element has exactly three readings, and each keeps a distinct
authored form:

- **Failure as data** — collect the option flow *in place* (output
  consumed per-element, inside `~L`): a list of options.
- **Failure as filter** — join the option flow into the list flow
  (binary join, option inner): the defined values only.
- **Failure as failure** — defer: collect the error flow outside. The
  time-travel form, canonically completed to fail-fast.

The unmarked, most natural gesture gets the fail-fast meaning; the
other two remain explicit, cheap, and visually distinct. No reading
became unreachable and none became ambiguous.

### 3. Join and commute out of a list (heuristically completed)

Two option flows opened inside a list flow (the second nested in the
first); the list collected; the *join* of the two option flows
collected at the end:

```
list -> open list => a, ~L
a -> open option => b, ~Y         -- option opened inside ~L
b -> open option => c, ~Z         -- option opened inside ~Y
c -~> collect ~L => d             -- collect the list flow
~Y, ~Z ~> join => ~w              -- join the two option flows (operands: outer, inner)
d -~> collect ~w => result        -- collect the joined option flow
```

The context tree is fully pinned by rules 1–4 (`~Z` inside `~Y` inside
`~L` by derivation; the terminations put the option material outside
`~L`). What is *not* pinned is the arrangement of the inserted
commutes relative to the authored join. Two completions realize the
same tree:

Choice 1 — commute each option flow out, then join outside (two
inserted commutes):

```
+ ~Y ~> commute out of ~L => ...
+ ~Z ~> commute out of ~L => ...
c -~> collect ~L => d
... join the lifted flows ...
d -~> collect ~w => result
```

Choice 2 — join first, then commute the combined flow out (one
inserted commute):

```
~Y, ~Z ~> join => ~w             -- still inside ~L
+ ~w ~> commute out of ~L => ...
c -~> collect ~L => d
d -~> collect ~w => result
```

Behavior-wise there is little between them — the naturality of commute
and join sees to that — but they are different no-time-travel
programs, and the compiler needs exactly one. No constraint or
canonical rule prefers either; refusing would leave a perfectly
reasonable gesture with no reading. So the heuristic picks: **join as
early as possible** → Choice 2, whose one faint commute (versus Choice
1's two) the editor displays between the authored join and the
authored collects. The rule is learnable, its application is visible,
and a user who wants Choice 1 draws its commutes solid — after which
there is nothing left to infer.

Two notes to close this example.

**What is *not* ambiguous nearby.** Two options opened independently —
no derivation between them — and joined:

```
o1 -> open option => a1, ~x1
o2 -> open option => a2, ~x2
~x1, ~x2 ~> join => ~x3
```

Now, you might wonder whether sibling deferred flows like these are
the paradigm ambiguity — which one is outer? It turns out the
ambiguity dissolves on inspection: join is not symmetric — its
operands are (outer, inner) — so the authored join itself directs the
nesting (rule 3): `~x2` must be the inner flow. The two opens being
mutually invariant siblings, the insertion is a Cross, oriented by the
join's operand order. The ambiguity was an artifact of imagining the
flows brought together by nothing in particular; any actual
bringing-together carries an operand order, and the order is the
answer. (Dissolved, not rejected — there was never a real question
here to decide.)

**Where a heuristic pick is observable.** Sibling flows whose *values*
combine but whose flows never reach one operation that orders them
(each collected separately at the end) still need a nesting direction,
and there the pick can be observable — with payload-carrying result
flows, which error wins when both fail depends on it. The pick is
still made, by the same published order, and rendered faint like every
pick; the fainter color is precisely the cue that the program, not the
user, chose which error wins — answered, as always, by drawing the
operator solid the intended way around.

### 4. Crossed terminations (contradictory, mostly dissolved)

```
a, b -> f => s;  s -~> collect ~A => sPerB;  sPerB -~> collect ~B => out1
a, b -> g => t;  t -~> collect ~B => tPerA;  tPerA -~> collect ~A => out2
```

The first chain forces A inside B; the second forces B inside A.
Cycle; no completion; clash with the two chains as witness.

For *this* example the contradiction **dissolves**: `~A` and `~B` are
mutually invariant sibling opens, so both chains are readings of one
product. Completion inserts one Cross and a faint Commute for the
reversed chain — nothing duplicated, neither opens nor work
(`product-flows-design.md`). The example remains the template for the
cases that stay genuinely contradictory only when no product exists: a
within-chain cycle, a reversed order on genuinely dependent nesting,
and bundle mixing.

Now, you might wonder why the language doesn't rescue the
truly-contradictory residue by completing each consumer path
independently — duplicating the opens so `out1` gets A-in-B and `out2`
gets B-in-A. It turns out this is *expressible* — multi-collect
consumers already compile to independent thunks — but it doubles the
iteration structure behind the user's back, and performing it silently
is over the line. (Settled: never performed silently. Whether it
should ever be *offered* as an explicit hint rather than performed is
an open question below.)

## Safety: the completion is a lens

Everything the user-facing story needs already exists in the
transformation-levels machinery:

- **Always-on derived view.** The completion is a lens on the program
  of record, materialized lazily. The "editor hints" are nothing more
  than this lens rendered in place: inferred operators drawn at their
  sites in a fainter color. (The graphical side is out of scope in
  this repo; here "hint" means the completion is a derived artifact
  addressed to authored node ids — a list of insertions each naming
  its anchor — which is what an editor would render and a test runner
  can print.)
- **There is no accept gesture.** You might expect an "accept this
  inference?" prompt. There isn't one: if the user likes where an
  operator was inferred, they do nothing — the faint operator is
  already part of the reading and the compiler already consumes it.
  Satisfaction is the default state, not a confirmation step.
- **There is no reject gesture either.** A user who wants a different
  completion places a real commute or incorporate where they meant it.
  The more specific program necessarily excludes the inference they
  didn't like (rule 1), and the lens re-derives around the authored
  operator. Overriding is just authoring; the elaborator only ever
  fills the holes that remain.

The laws that make this trustworthy, stated as obligations on any
implementation:

1. **Conservativity** (nothing invented for complete programs): a
   no-time-travel program is its own completion, node for node.
2. **Idempotence** (completing twice is completing once): completing a
   completion changes nothing.
3. **Determinism.** Same program, same completion — no search, no
   scoring, no tie-breaking outside the published canonical table and
   heuristic order.
4. **Solidification stability.** Drawing, as authored structure,
   exactly what the lens shows changes nothing about the reading — the
   operator goes from faint to solid and the completion is otherwise
   identical. More generally, adding explicit structure *consistent*
   with the current completion never changes the reading; only
   structure that contradicts an inference moves it.

The one genuine cost, named honestly: **completion is a whole-diagram
inference, so a distant edit can change insertions elsewhere.** Adding
one more collect, or deferring one more error flow, can flip an
inferred nesting three constructs away — the unchecked-exceptions
cost, where a deep `throw` silently changes every caller. The
mitigations are real but partial: the reading never changes *silently*
(the lens re-renders, and hints are visible structure, so a flipped
insertion is a visible diff), and the step-DAG's id discipline makes
"diff the completion across versions" well-defined and cheap. Whether
the editor should actively flag completion diffs on edit is an open
question; that it *can* is a direct payoff of programs being
persistent structures.

## Where it sits in the architecture

**The enforcement tiers gain a disposition.** `types-design.md`'s
three tiers — unrepresentable / checked / trusted — implicitly assumed
every detected violation is an error. Time travel was tier-3 (trusted,
awaiting a checker) and headed for tier 2 as the "smallest first step"
check. This design gives the check a third outcome: neither trusted
nor rejected but **completed**. The full inventory: unrepresentable
things you cannot draw; clashes that mean nothing (bundle mixing,
contradictory orderings); incompletenesses that mean exactly one thing
(completed, with the lens as receipt); trusted hazards as before.

**The checker comes first, unchanged.** The elaborator consumes
precisely the analysis the checker runs — context paths compared at
combining and collecting nodes (`bundle-provenance-design.md`) — and
adds a solver over the failures. `types-design.md`'s "smallest first
step" is untouched: implement flow-context alignment as a check; the
completion pass is that check's second consumer, turning a subset of
its findings from errors into insertions. Detection *is* the front
half of completion.

**Completion is a level-1 catalog entry.** It passes the admission
test verbatim: its content is a statement about level-0 programs (this
incomplete one means that complete one), and its value shadow is the
identity. Pattern: a time-travel program with a defined completion.
Expansion: the completion. Port correspondence: identity on authored
ports; inserted nodes are expansion-internal, with the inserted flows'
ports (a commute-derived error flow, say) as principal derived ports
addressable through the lens. Of the two invocation modes in
`transformation-levels-design.md`, completion leans almost entirely on
the lens: no interaction *requires* materialize, because overriding an
inference is authoring, not editing the view. The upward direction
exists too: recognizing that an authored commute chain is exactly what
the canonical table would insert, and collapsing the program to the
more abstract time-travel form, is a `recognize`-family entry, partial
as ever.

**Well-formedness restated.** A program is well-formed iff its
completion is defined (dispositions 1–3 everywhere; no cycles, no
bundle mixing). This is a whole-diagram quotient check in the
established family — alt matching, no-crossing, Delay productivity —
with the one novelty that passing it produces an artifact (the
completion) rather than mere absence of error.

**Reuse.** A reusable diagram may be a time-travel program — in fact
the placeholder story of `types-design.md` predicts it: a diagram
authored against schematic sources accumulates residual *demands*; a
diagram authored with uncommitted flow structure accumulates residual
*ordering constraints*, projected onto its boundary the same way. Its
principal property signature then carries both: "a list of things with
field `price`" and "this input's flow must end up enclosing that one."
Call-site checking composes the caller's orderings with the callee's
residue, interior never re-examined. One consequence worth pinning
now: within a reusable diagram, canonical rules and heuristics should
fire only on freedom the boundary cannot see — an ordering a caller
could still direct travels outward as residue and is picked, if still
free, where no further constraint can arrive. Picking early would turn
a caller's legitimate direction into a contradiction.

**The compiler.** Zero changes to the runtime and zero to the emitted
JS, by commitment 1. The one repo-level consequence is a new pass —
Expr-level completion — in front of the existing compile, plus the
check it depends on. The current `deeper` behavior becomes an
assertion that the input is complete, which after the pass it always
is.

## What this deliberately is not

- **Not a runtime feature.** No lazy nesting resolution, no reified
  flow order, no new emitted forms. Translation only.
- **Not silent inference.** The old ban — *"relying on type inference
  or constraint solving to determine behavior"* — is genuinely
  amended, and the amendment is owned rather than smuggled: completion
  derives structure the user didn't draw, and where the constraints
  leave freedom it *picks*, by canonical rule or by honest heuristic.
  What keeps it on the right side: every pick is ruled and published
  (never searched, never scored, never a per-program judgment), every
  pick is on screen in the fainter color (nothing behaves differently
  than shown), and every pick is excludable by ordinary authoring.
  What is genuinely given up: "the authored strokes alone show the
  full flow structure." The reading now lives in
  authored-strokes-plus-lens — the same trade Koka and unchecked
  exceptions made, bought back here by the lens being *structure*, not
  prose.
- **Not a repeal of no time travel.** Every reading — every
  completion — satisfies the rule. No program's *meaning* involves
  retroactive determination; there are only programs whose *notation*
  leaves canonical bookkeeping unsaid.
- **Not layout-driven.** Making the editor's geometry (vertical
  position as an elaboration input) another constraint source is
  possible but belongs to the visual side and is out of scope here;
  the constraint model above neither needs nor mentions position.
  (Set aside as out of scope, not rejected.)

## Philosophy check

- **Example first, then generalise.** The whole feature is this
  principle applied to flow structure: the concrete value computation
  is written first; the nesting is identified afterward from what was
  done with the results — read off the program, never declared. The
  completion is the identified generalisation, derived structure the
  user can inspect.
- **Inside-out / cases as values.** "The elements of A" is a value you
  compute with, not a scope you must first enter. Completion cashes
  that out without giving any interior a different meaning from its
  exterior — the inserted structure is ordinary visible wiring, no
  magic names, no context-sensitive readings.
- **Foundations before features.** On paper: the canonical table
  starts with one entry and the heuristic order with one heuristic,
  each admitted only with a worked program behind it. A heuristic,
  once shipped, determines readings and is thereafter as hard to
  change as any other piece of the language's meaning — cheaper to
  reject candidates here.
- **Building blocks at the programmer's abstraction level.** "Add the
  elements of these two lists," "handle all the errors at the end"
  *are* the programmer's abstractions. One reading per program
  survives because every alternative reading kept its own explicit
  spelling (the three fallible-element forms).
- **No bottlenecks.** Nothing is packed to pass a structural point:
  insertions are crosses, incorporates, and commutes, which pass value
  wires through as themselves — commute doesn't even have value ports
  to bottleneck.
- **Abstraction is the source of truth; concreteness is a derived
  view.** The time-travel program is the record and the most abstract
  true description; the completion is a read-only lens, compiled from
  and never edited; overriding an inference is authoring into the
  record; eliding canonical structure is recognize. The feature is
  almost a corollary of this principle — the strongest sign it belongs
  in the language.

## Smallest first step

The repo can grow the skeleton with no UI and no streams:

1. **The check** (unchanged from `types-design.md` step 1):
   flow-context alignment with a two-anchor error, converting the
   trusted rule into a checked one. Prerequisite: `scopeRef` origins,
   per `bundle-provenance-design.md`'s sharpening.
2. **Directed completion for sibling list opens.** An Expr→Expr pass:
   where the check finds sibling opens, harvest the directed
   constraints from the authored collects (rule 2), and where they
   force a unique nesting, rewrite by inserting a Cross (not by
   re-rooting the inner open's source — re-rooting erases the mutual
   invariance the authored program carried,
   `product-flows-design.md`) and report the insertion in test output
   (ExprPrint the completed program alongside the original). Where
   more than one nesting survives, the heuristic order picks and the
   report labels the pick heuristic; where the constraints cycle, the
   check's error.
3. **Canonical option-outward commute** waits for stream flows and the
   Commute implementation — deferred, not dropped; its design is done
   here and in `lazy-stream-commute-design.md`, and step 2's
   constraint harvest is written to extend to it.

Each step is testable in `Main.res` style: build a time-travel Expr,
expect either a specific completion (compare compiled output against
the hand-completed program — they must be identical, which is
commitment 1 as a test) or a specific clash.

## Open questions

The language hasn't decided these yet.

1. **The heuristic order.** Decided: completion always picks —
   refusing would make the most natural gestures dead ends. Open: the
   contents and ordering of the list beyond
   join-as-early-as-possible; whether heuristics can be *required* to
   pick within a naturality-equivalence class whenever one exists
   (making the pick a spelling choice, confining observable picks to
   cases where no equivalence is available); and versioning — changing
   a heuristic changes existing readings, so the heuristic order is
   part of the language's meaning and must be versioned as such.
2. **The canonical table's contents.** Option/error outward is the
   inaugural entry. Result-out-of-sequenceable presumably joins it
   (fail-fast with payload — same direction; non-sibling result flows
   are ordered by their nesting already). Async and incremental kinds
   need their own rounds; the commute-variant taxonomy is the map of
   which pairs even have a commute to canonicalize. The table is
   language definition, versioned with it — and growing it is *not*
   automatically safe: since completion always picks, a new canonical
   entry re-classifies picks that were previously heuristic and
   changes any it disagrees with. Same versioning discipline as the
   heuristic order; the two lists are one semantic surface.
3. **Completion diffs on edit.** Should the editor actively flag "this
   edit changed the completion over there," and at what granularity?
   The id discipline makes the diff cheap; the UX is the question.
   (This is the unchecked-exceptions cost center; whatever the answer,
   it should be designed against example programs, not in the
   abstract.)
4. **Per-consumer completion.** The crossed-terminations rescue —
   duplicating opens so each consumer path gets its own consistent
   nesting — is expressible but multiplies iteration structure. The
   case that motivated it now completes with a single inserted Cross
   (no duplication; worked example 4), so no duplicating rescue
   remains wanted for any known program. If one ever is, the
   constraint it must satisfy is recorded here: drawn, never silent.
5. **Boundary residue representation.** How a reusable diagram's
   unresolved ordering constraints appear in its principal property
   signature, and how they compose at call sites — including whether a
   caller can discharge a callee's residue (probably yes: the caller's
   structure directs the callee's siblings) and whether that
   recomposes lazily.
6. **Recognize-side ergonomics.** Should the editor offer to collapse
   authored-but-canonical structure ("this commute chain is exactly
   what deferral would insert — elide it?"), and does that ever fight
   a user who drew it deliberately for emphasis? Same tension as eager
   recognition in `transformation-levels-design.md`; likely the same
   answer.
7. **Naming.** "Time travel program" is a vivid internal name and an
   alarming user-facing one. "Deferred flow structure," "schematic
   nesting," or never naming the state (the editor just shows hints)
   are candidates. Interacts with whether the user-facing vocabulary
   ever says "type" (`types-design.md`, open question 1); the two
   vocabularies should be decided together.
