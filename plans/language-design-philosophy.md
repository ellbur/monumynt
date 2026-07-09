# Language Design Philosophy

Six principles run through the language design. They are the
criteria against which new primitives and constructs are evaluated;
a proposal that violates one needs either revision or a very good
argument. Each was earned in a specific design conversation, noted
alongside.

## Example first, then generalise

Programs should be writable starting from a concrete example, with
generalisation applied after the fact — not declared upfront.
Conventional languages force you to write the general form first
(function parameters, fold signatures, type annotations). This
language inverts that: you write the specific case, then identify
the relationship that makes it general. A proposed primitive that
requires declaring structure upfront before writing the concrete
computation is suspect.

The link transformation in `iteration-with-state-design.md` is the
worked instance: you write one step of the computation concretely,
then the link turns the feedback into iteration.

## Inside-out / cases as values

The language avoids constructs that make the *interior scope* of an
expression different from its exterior. Cases (branches, alts)
should be values you inspect and flow through, not scopes that
influence the meaning of expressions written inside them.

This is why `stateful(initial, update)` was rejected in the
iteration-state design: `prev` was only in scope inside the second
argument, making that expression's meaning depend on where it
appeared. The same test rules out magic names generally — anything
readable in a position must arrive there by a visible wire.

## Foundations before features

Getting the right building blocks takes priority over accumulating
features quickly. A wrong primitive compounds — everything built on
it inherits the flaw. It is cheaper to spend time critiquing and
rejecting candidates than to implement the wrong thing and correct
it later. Once foundations are right, building on them should be
fast and unsurprising.

In practice this looks like the design docs under `plans/`: long
option analyses (nine options for commute-on-lists, five candidates
for iteration state) where most candidates die on paper.

## Building blocks at the programmer's abstraction level

The language does not subscribe to the Lisp philosophy of minimal
primitives. When building blocks are much simpler than the
programmer's vocabulary, there is no one obvious way to write a
given program — readers must decode intent rather than read it
directly. The criterion for a building block is not "is this the
simplest possible primitive?" but "does this meet the programmer at
the level of their own abstractions?" The goal is one obvious way
to express a given program, which is what makes programs readable
across authors and time.

Note this concerns the *reading*: many authoring paths may converge
to one result-level reading, so discoverability (many ways to
write) and readability (few ways to read) are not in tension. See
`transformation-levels-design.md`, "Many authoring paths, few
readings."

## No bottlenecks — neither product nor sum

When several wires pass through a combining construct, they pass
through *as themselves*; they are not packed into an intermediate
data structure on one side and unpacked on the other.

The **product** form of the bottleneck is the tuple: forcing
multi-value joins or multi-accumulator folds through a tuple loses
each value's individual identity. This is the functional bottleneck
problem (`iteration-with-state-design.md`) — functional languages
make multi-accumulator iteration pack its state into a tuple at
every level; the 2D join and the one-rail-per-accumulator designs
exist to avoid it.

The **sum** form is the alternative: a race that produced a tagged
union, immediately case-split, would sever the visual thread
between each contender and its case — the wires survive only as
tag names. See `async-flow-design.md`, "Racing is a barrier, not a
value."

Combining constructs are instead *barriers* with
pairwise-corresponding inputs and outputs: the concurrent join is
the product barrier (all threads continue together), race is the
sum barrier (exactly one continues). Tuples and alternatives remain
perfectly fine as genuine data; the bottleneck is constructing one
merely to pass a structural point.

## Abstraction is the source of truth; concreteness is a derived view

The authored program keeps the highest-level description. Every
more-concrete form (a `sum`'s running-iteration expansion, any
operation's lowering) is a read-only *derived view* — always
available for inspection and reference, never the thing you edit.
This makes high-level building blocks *durable*: the abstraction is
not compiled away in the program you hold. You build on a derived
view by referencing its ports, not by materialising it.

Corollary: derivation is free and downward (dropping to a concrete
form is total and automatic, so a block never traps you);
abstraction is earned and upward (recovering a high-level form from
a concrete one is partial recognition). This rests on a homogeneous
tower — one language where operations carry levels and programs are
the data of the level above. See `transformation-levels-design.md`
for the full treatment.

Sharpening: nothing is ever edited — every change *builds*, yielding
a new program version that shares untouched parts with the old one
(programs are a persistent, functional data structure; the
construction history is the program of record — indeed the program
and its history are aspects of one stored step-DAG, not two
structures). Each version reads
at the highest level that is true of it: to *add* to a `sum`,
reference its derived view's principal ports; to *change* its
interior, materialize the expansion (a recorded construction step)
and build a new loop from the parts — the sum, and every earlier
version, remain in the history. Removing a conversion later while
keeping work built after it is a cherry-pick, translated through the
port correspondence. Level-1 operations (conversions, recognition,
history operations like undo and cherry-pick) are built-in catalog
entries, not user-written macros.

---

## A standing method: sample reality

*(Adopted 2026-07-09, after the first real-loop survey. This is a
method, not a seventh principle — it is how the principles above get
their contact with the world.)*

The principles are applied in design conversations, and design
conversations have a known failure mode, named in the rail notes
before the method existed: designing to the theory's existing
categories rather than to what real code actually looks like. The
counterweight is **seeded random sampling of real code**: draw
programs nobody chose, read each whole and in context, classify
against the current and candidate vocabulary, and let the frequencies
reweight the agenda.

The first execution (`real-loop-survey.md`) demonstrated the yield: it
confirmed the center (uncollect/collect covered half of everything,
before counting the combinators the protocol excluded), overturned an
assumed weighting (the running-sum scan, the anchor example of the
iteration-state conversation, occurred zero times in thirty draws
while early termination dominated), gave a candidate rule its first
contact evidence (the one-writeback rule survived), and surfaced a
question no conversation had produced (the running view of a
collect).

**Use it frequently.** Specifically, whenever a construct's importance
is being assumed rather than measured, an inventory needs ranking, a
proposed rule needs contact with cases nobody constructed for it, or
a design round has gone several exchanges without touching code that
exists. Sampling is cheap relative to one wrong primitive — this is
"foundations before features" applied to evidence.

The method's rules, which are what make its results trustworthy:

- **Seeded and documented.** The protocol (corpora, what counts as an
  instance, seed, selection procedure) is recorded so the draw is
  reproducible and demonstrably unchosen.
- **No hand-picking, no filtering for interesting.** Boring instances
  are the finding — their proportion is the point.
- **Biases stated, not hidden.** Corpus skew, protocol exclusions,
  sample size; and each bias's *direction* noted, so undercounts and
  overcounts are readable.
- **Evidence separated from decision.** A survey decides nothing; it
  reweights. Design decisions stay in the design conversations, with
  the survey cited.
- **Frequency is not importance — the 80/20 counterweight.**
  *(Recorded on review of the first two surveys, 2026-07-09.)* A
  sample measures how often a shape occurs, not how much time or pain
  it costs. Per the 80/20 rule, most writing time concentrates in the
  rare hard cases — so the most annoying loop to write can break the
  language even when every common case is trivial. Read frequencies
  in two directions: **high frequency ranks what must be effortless**
  (the defaults, the one-gesture paths); **low frequency plus high
  pain ranks what must be possible without too much pain** — breadth.
  A shape drawn once is a breadth obligation, not a deprioritization
  candidate; frequency arguments may promote a construct (end-when's
  everyday demand) but never demote one on rarity alone. This is also
  why sampling complements rather than replaces the stress-test
  method (`tough-use-cases-design.md`): the sample finds what is
  common; the tough use cases find what breaks — a survey's singleton
  hard draws are randomly-harvested members of the same set the tough
  use cases construct deliberately.

New samples extend the record rather than starting over: reuse the
protocol shape, vary the corpus or the unit sampled (loops were
first; functions, error paths, data declarations, concurrent
sections are all sampleable the same way). The second survey (same
day, domain corpora fetched from package registries) demonstrated the
extension pattern — and demonstrated why extension matters: it
overturned the first survey's most striking finding (the scan,
absent in infrastructure code, is the dominant loop shape in
numerics), exactly along the bias the first survey had flagged.
Corpora need not be preinstalled; pip/npm fetches of real projects
work and keep the domain choice deliberate.
