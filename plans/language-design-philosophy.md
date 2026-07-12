# Language design philosophy

Seven principles run through the language design. They are the criteria
against which new primitives and constructs are evaluated; a proposal that
violates one needs either revision or a very good argument. Read this
before evaluating any new construct.

## 1. Example first, then generalise

You should be able to write a program starting from a concrete example,
and generalise *after the fact* — not by declaring structure upfront.
Conventional languages force the general form first: function parameters,
a fold's signature, type annotations. This language inverts that. Write
the specific case, then identify the relationship that makes it general. A
proposed primitive that requires declaring structure before you can write
the concrete computation is suspect.

The worked instance is the "link" in `iteration-with-state-design.md`: you
write one step of the computation concretely, then the link turns the
feedback into iteration.

The principle constrains *obligation*, not *option*. Writing abstract
structure first — a facet, a schema — is fine as planning, the way an
OCaml programmer writes type definitions first to document what the code
is meant to do. What the principle rules out is a construct that
*requires* the general form: everything you can do with a general schema
should also be reachable by a concrete-first path (write the concrete
thing, extract the abstraction after). It is a direction the language
works toward, not an absolute; "force" is the operative word.

## 2. Inside-out — cases are values, not scopes

The language avoids constructs that make the *interior scope* of an
expression differ from its exterior. Cases (branches, alts) are values you
inspect and flow through, not scopes that change the meaning of
expressions written "inside" them.

This is why `stateful(initial, update)` was rejected for loop-carried
state: `prev` would only be in scope inside the second argument, so that
expression's meaning depended on where it was written. The same test rules
out magic names in general — anything readable at a position must arrive
there by a visible wire.

## 3. Foundations before features

Getting the building blocks right takes priority over adding features
fast. A wrong primitive compounds: everything built on it inherits the
flaw. It is cheaper to critique and reject candidates on paper than to
implement the wrong thing and correct it later. Once the foundations are
right, building on them should be fast and unsurprising.

In practice this is why the docs under `plans/` are long option analyses —
nine options for commute-on-lists, five candidates for iteration state —
where most candidates die on paper.

## 4. Building blocks at the programmer's abstraction level

The language does not follow the Lisp philosophy of minimal primitives.
When the building blocks are much simpler than the programmer's own
vocabulary, there is no single obvious way to write a given program, and
readers must decode intent rather than read it. The test for a building
block is not "is this the simplest possible primitive?" but "does this
meet the programmer at the level of their own abstractions?" The goal is
**one obvious way to read a given program**, which is what makes programs
readable across authors and time.

This concerns the *reading*, not the writing. Many authoring paths may
converge on the same reading, so discoverability (many ways to write) and
readability (few ways to read) are not in tension. See
`transformation-levels-design.md`, "Many authoring paths, few readings."

## 5. No bottlenecks — neither product nor sum

When several wires pass through a combining construct, they pass through
*as themselves*. They are not packed into an intermediate data structure
on one side and unpacked on the other.

The **product** form of the bottleneck is the tuple. Forcing a
multi-value join or a multi-accumulator fold through a tuple loses each
value's individual identity — the functional-language bottleneck, where
multi-accumulator iteration packs its state into a tuple at every level.
The join barrier and the one-rail-per-accumulator designs exist to avoid
it.

The **sum** form is the mirror image: a race that produced a tagged union,
immediately case-split, would sever the visual thread between each
contender and its case — the wires survive only as tag names. See
`async-flow-design.md`, "Racing is a barrier, not a value."

The resolution: combining constructs are **barriers** with
pairwise-corresponding inputs and outputs. The concurrent join is the
product barrier (all threads continue together); race is the sum barrier
(exactly one continues). Tuples and tagged unions remain perfectly fine as
genuine data — the bottleneck is constructing one merely to pass a
structural point.

## 6. Abstraction is the source of truth; concreteness is a derived view

The authored program keeps the highest-level description. Every
more-concrete form — a running-iteration expansion of a sum, any
operation's lowering — is a read-only *derived view*: always available for
inspection and reference, never the thing you edit. This makes high-level
building blocks **durable**: the abstraction is not compiled away in the
program you hold. You build on a derived view by referencing its ports,
not by materialising it.

The corollary is a direction. Derivation is free and downward: dropping to
a concrete form is total and automatic, so a block never traps you.
Abstraction is earned and upward: recovering a high-level form from a
concrete one is partial recognition. This rests on a homogeneous tower —
one language in which operations carry levels, and a program is the data
of the level above it (`transformation-levels-design.md`).

Nothing is ever edited in place. Every change *builds*, producing a new
program version that shares its untouched parts with the old one — programs
are a persistent, functional data structure, and the construction history
is the program of record. To *add* to a sum, reference the ports of its
derived view; to *change* its interior, materialise the expansion (a
recorded step) and build a new loop from the parts. The sum, and every
earlier version, remain in the history. The level-1 operations that make
this work — conversions, recognition, undo, cherry-pick — are built-in
catalog entries, not user-written macros.

## 7. Building blocks must build (graceful expansion)

A construct that serves the common case earns its place only if the
complex cases are reachable *from it* by adding structure — never by
abandoning it and rewriting in a different vocabulary. A building block
that doesn't build is not much help. Two facets:

**Expansion continuity.** The program one step more complex than the
simple case should be the simple program *plus something* — one more link,
one more collect, a commute, a condition wired into an existing port — not
a translation into a different construct. The canonical counterexample,
which earned this principle: conventional `.map()` and `.filter()` are
virtually impossible to build on. The moment a walk acquires one carried
value, nothing transfers — the program must be rewritten as a `fold`, and
the fold's tuple bottleneck then punishes every further accumulator. Each
rung of that ladder is a cliff; the vocabulary is a set of islands, not a
ramp.

**Discoverability.** Beginners learn the simple constructs, and the simple
constructs are what teach the language. If the complex construct is a
different species, the simple one taught nothing about it — mastery of the
common case leaves the user stranded exactly when their program grows.
When expansion is additive, the gradient is learnable: the complex drawing
*looks like* the simple drawing with more visible structure, so the
picture itself teaches the next step. In a visual language this has teeth.

The record's existing choices already embody the principle, which is
evidence it was implicit all along:

- **Multi-close**: a second output of a loop is added beside the first;
  the loop is untouched.
- **Commute**: nesting is reordered by an explicit added node, not by
  rewriting the loops.
- **The link**: a second accumulator is a second independent link — the
  iteration-state candidates beat `fold` precisely by this measure.
- **Derived-port reference**: a sum grows a lockstep `max` by referencing
  the sum's derived combined flow; the reduce-close is never lowered.

Test for a proposed construct: enumerate its simple use's **+1 steps** —
one more accumulator, one more output, a carry that turns conditional,
termination that becomes data-driven, a consumption rate that stops being
one-per-firing — and check that each is an *addition to the drawing*, not
a rewrite into something else. Where a +1 step forces a species change,
that boundary is a designed cliff and needs either removal or a very good
argument.

---

## A standing method: sample reality

This is a method, not an eighth principle — it is how the principles above
get their contact with the world.

Design conversations have a known failure mode: designing to the theory's
existing categories rather than to what real code actually looks like. The
counterweight is **seeded random sampling of real code**. Draw programs
nobody chose, read each whole and in context, classify against the current
and candidate vocabulary, and let the frequencies reweight the agenda.

The first execution (`real-loop-survey.md`) shows the yield. It confirmed
the center (uncollect/collect covered half of everything). It overturned
an assumed weighting: the running-sum scan, the anchor example of the
iteration-state conversation, occurred zero times in thirty draws while
early termination dominated. It gave a candidate rule its first contact
evidence (the one-writeback rule survived). And it surfaced a question no
conversation had produced (the running view of a collect).

**Use it frequently** — whenever a construct's importance is being assumed
rather than measured, an inventory needs ranking, a proposed rule needs
contact with cases nobody constructed for it, or a design round has gone
several exchanges without touching code that exists. Sampling is cheap
relative to one wrong primitive.

The rules that make its results trustworthy:

- **Seeded and documented.** The protocol — corpora, what counts as an
  instance, the seed, the selection procedure — is recorded, so the draw
  is reproducible and demonstrably unchosen.
- **No hand-picking, no filtering for interesting.** Boring instances are
  the finding; their proportion is the point.
- **Biases stated, not hidden.** Corpus skew, protocol exclusions, sample
  size — and each bias's *direction*, so undercounts and overcounts are
  readable.
- **Evidence separated from decision.** A survey decides nothing; it
  reweights. Decisions stay in the design conversations, citing the
  survey.
- **Frequency is not importance — the 80/20 counterweight.** A sample
  measures how *often* a shape occurs, not how much time or pain it costs.
  Most writing time concentrates in the rare hard cases, so the most
  annoying loop to write can break the language even when every common
  case is trivial. Read frequencies in two directions: **high frequency
  ranks what must be effortless** (the defaults, the one-gesture paths);
  **low frequency plus high pain ranks what must be possible without too
  much pain** — breadth. A shape drawn once is a breadth obligation, not a
  deprioritisation candidate. Frequency may *promote* a construct
  (end-when's everyday demand) but never *demote* one on rarity alone.

This is why sampling complements rather than replaces the stress-test
method (`tough-use-cases-design.md`): the sample finds what is common; the
tough use cases find what breaks. A survey's singleton hard draws are
randomly-harvested members of the same set the tough use cases construct
deliberately.

New samples extend the record rather than starting over: reuse the
protocol shape, vary the corpus or the unit sampled (loops were first;
functions, error paths, data declarations, concurrent sections are all
sampleable the same way). The second survey — domain corpora fetched from
package registries — demonstrated why extension matters: it overturned the
first survey's most striking finding (the scan, absent in infrastructure
code, is the dominant loop shape in numerics), exactly along the bias the
first survey had flagged. Corpora need not be preinstalled; pip/npm
fetches of real projects work and keep the domain choice deliberate.

## A standing lens: what does it mean?

Also a method, not a principle. Where "sample reality" keeps the design in
contact with real *code*, this keeps it in contact with *meaning*.
Designing a construct is not only assembling rules that compute the right
results; a construct also has to **mean** something — an ontology a person
can hold — and two constructs that compute identically can still differ in
what they *are*. Figuring out what a thing means is design work, not
philosophy layered on top of it.

The worked instance is Delay (`iteration-with-state-design.md`, "What a
Delay is"). The register pair's *results* were fully pinned by the
equivalence round, yet a prior question survived: what is a Delay, and which
flow does its "next iteration" refer to? It is answerable only by ontology —
a Delay is a *delayed computation bound by its collect*, not a computation
that taps a flow wire (IO's shape, which is justified there by a temporal
sequence Delay lacks) nor one that reads secret flow data off its value wire
(which the uncollect's fiction forbids). Crucially, the ontological choice
**selects the behaviour**: it changes what the construct does exactly where
more than one flow is in reach (a commute; a product's axes). So meaning is
not decoration on the rules — it decides them.

Reach for the lens when a construct is fully pinned at the level of results
but you still cannot say, in one sentence, what it *is* — that gap is
usually hiding a decision the results did not force but a second context
will. The two rejected Delay alternatives (wire-tapping; ancestor-uncollect
reference) were each killed by an ontology clash, not a wrong output, which
is the tell that this lens catches things the result-level rules do not.
