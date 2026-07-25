# Facets — recorded intuitions

Status: recorded intuitions, deliberately undeveloped — guiding
principles for future development, nothing adopted, no design round run.
The framing is the author's own. This doc extends, and does not
supersede, the earlier facets note (`tough-use-cases-design.md`,
addendum "Facets: partial views against crowding"); the relationship is
worked out at the end. The demand for it sits on the
functions/reuse/facets row of `open-problems.md`. Annotations that
connect these intuitions to the rest of the record are bracketed and
marked, so the raw intuitions stay distinguishable from the commentary.

The prompt was a concrete gap the Effekt comparison exposed
(`effekt-comparison.md`, finding 2): how do you run a diagram that does
IO against fake IO? Answering that turns out to need a general capacity
the language lacks, which these notes name.

## The gap this names: concrete vs schematic

The language is very good at the concrete. It is not good at
**schematics** — separating the *shape* of a thing from its details:
the shape of data, the shape of a computation, the sequence of steps,
the states of a state machine.

Take a program that does a bunch of file operations. One facet of it is
just *the sequence of operations* — not what each does, but which
functions it calls and in what order. Step back for a more general
facet: *every file that is opened is closed*. Neither facet is the
program; each is one honest angle on it.

*[Annotation: this is the territory the Effekt round hit from the
outside (findings 1–2, late-bound operations and the test double).
Those examples demonstrated the capability; this names what the
capability is an instance of.]*

## Not one carving

Because this is a visual language with an interactive editor, it has a
freedom a fully textual language like Effekt does not: the code does
**not** have to be carved into facets one fixed way. The user picks
whichever facet is worth viewing in the moment. A facet is a chosen
view, not a commitment baked into the source.

## A facet can be authored alone

First guiding principle: the user should be able to **write just a
facet**, with nothing concrete attached to it yet.

## The ladder: struct → interface → facet

The clearest example comes from data, because existing languages are
better at data — but it sets the bar for what "abstract" should mean
here.

A **struct** is already a kind of facet: one facet of a variable is
that it has fields `x` and `y`.

People noticed "has fields `x` and `y`" was slightly more general than a
struct — what if the fields are computed? So they built the
**interface** and said `x` and `y` are functions now. But an interface,
though it reaches cases a struct can't, **is not actually more
abstract**. It is concretely a pair of functions; you adapt it by
writing bodies for those functions.

A real **facet** is the abstract concept of *having an `x` and a `y`*.
What are they — variables, fields, database columns? None of these. It
is not something concrete you can build or hand around: "pass me an
x-y-haver" means nothing out of context.

What you *can* do is attach the one facet in two places:

```
-- spelling entirely provisional
facet XY has x, y             -- a facet: names two slots, nothing concrete

Point  struct { x, y } with XY    -- attach XY when building the struct
users  table  { x, y } with XY    -- attach XY when building the db table
```

Because both attachments reference the *same* facet `XY`, the editor
knows a `users` row can be stored in a `Point` — the compatibility is a
fact you can point at, not a coincidence to be discovered.

*[Annotation: note the mechanism. The knowledge comes from a drawn
identity — both attachments reference one facet — not from structurally
matching two independently-written shapes. That is exactly what
`types-design.md`'s no-search stance wants: identity is checkable by
looking; inferring over "things that happen to have an x and a y" would
be search. It is also the visible-wire spirit — the compatibility fact
has a place on the diagram you can point at.]*

## Facets of code: algebras and state machines

Facets work for code, not just data:

- Make an **algebra** out of a set of functions and say a piece of code
  has the facet of *being built out of this algebra*.
- Design a **state machine** and say some code has the facet of *using
  these states and transitioning on these events*.

The payoff for code: if your production code and your test code carry
the *same* facet, **you learn something about your production code by
exercising your test code**.

```
-- spelling entirely provisional
facet FileOps = algebra { open, read, close }

realFiles  binds FileOps      -- production: open/read/close hit the disk
fakeFiles  binds FileOps      -- test double: same three, backed by a map
```

The test double and the real thing are two bindings of one facet;
sharing the facet is what makes exercising the double informative about
the production path.

*[Annotation: this is the inside-out reading of what the Effekt corpus
kept doing. Their `AD[Num]` interface is literally "an algebra out of a
set of functions" with three bindings (forwards, backwards, symbolic);
their from-list lexer and real lexer are two bindings of one facet, and
the shared facet is what makes the test double informative. The
comparison round derived the port-pair leaning for *binding* (finding
1); this names what the bound thing is.]*

## Holes without breaking

Code is trickier than data, because in code you constantly need to
**break a clean facet to get real work done**. You design a perfect
algebra of file operations, and then someone says "could you also log
how many files are open" — and the algebra has no counter, so you'd have
to break the whole thing.

So a code facet has to **allow holes without breaking**: the code calls
these functions, and it also does other stuff in the gaps. The hole is
not decorative residue — it is the *licensed difference* between the
facet and the code that carries it. What licenses the gap? That is the
next section.

*[Annotation: the record has two precedents for showing "there is more
here" without showing it — the function interface's data holes
(`functions-design.md`) and the earlier facets note's marked escapes
(the projection route). The demand here is stronger than either: the
hole is not just displayed residue, it is what the facet permits the
code to do beyond the facet.]*

## Negative constraints

Maybe the gap is licensed by **negative constraints**. I can't tell you
what the code does besides use this algebra of file operations — but I
*can* tell you it will **not** touch the files in that same directory.
Then we can be confident those files are accessed only through this
algebra; everything else stays a mystery, and that is fine.

Negative constraints of this form are rare — possibly never seen in the
wild — and that may be because they are too weak to be useful. Recorded
with that direction of doubt, as a thought to keep in mind.

A capture-set type like Effekt's `() => Unit at {}` is **not** a
negative constraint, despite looking like one. It is a *positive*
constraint that hasn't been handed anything: an enumeration of what the
code may touch, with the enumeration empty. A negative constraint is "do
anything except X" — one exclusion asserted over code that is otherwise
a complete mystery. That form remains unsighted.

*[Annotation: the whitelist form and the single-exclusion form differ in
exactly the dimension this doc cares about. A whitelist must enumerate
everything the code *does* touch, which re-creates the counter problem —
add one logging call and the enumeration breaks. The single-exclusion
form coexists with the mystery, which is why it, if anything, fits the
holes-without-breaking story. One drawable candidate spotted so far: a
connectivity absence — "no wire from resource R reaches this region" —
asserts a single exclusion without enumerating anything else, and is
provenance-checkable (`bundle-provenance-design.md`). Whether even that
is useful inherits the doubt above.]*

## What facets are NOT: verification

The goal is **not** formal verification. We are not building Agda. The
compiler is not proving the code sound.

What facets create is **views** — so the user can look at the code and
see whether it *looks right*. A facet simplifies and summarizes: a
better angle that suppresses some of the noise and makes a mistake
easier to spot. Whether the code is actually correct must still be
confirmed the old-fashioned way, with tests.

*[Annotation: this bounds the checking question before it is asked.
Whatever "same facet" checking exists should stay at the level
`types-design.md` already operates at — properties and drawable
witnesses, no search, no proof obligations. A facet is a lens for a
human, with just enough machinery that the lens isn't lying about
identity.]*

## How this extends the earlier facets note

The addendum in `tough-use-cases-design.md` treats facets as partial
**views** of an existing program and works the viewing side:
recognition (partial, fragile — "abstraction is earned") versus
projection of authored structure (free, total, the philosophy's
preferred route). This note adds a third leg the viewing side
presupposed but never named: the facet as an **authorable artifact in
its own right** — something that can exist before and independently of
any concrete program, and that gets **attached** to concrete structure
rather than derived from it or recognized in it.

The three legs compose in the obvious order:

1. author a facet alone;
2. attach it to concrete things (one facet, many attachments);
3. view a concrete thing through any facet attached to it.

Attachment — what it is representationally, what identity it creates,
what its holes license — is the genuinely new piece; the addendum's
viewing machinery applies downstream of it.

## Open edges (stated, not worked)

1. **Facet-first vs example-first.** The apparent tension with the
   example-then-generalise principle dissolves on two points.
   **Extraction** — pulling a facet out of concrete code after the fact
   — is the proper example-first path to a facet. And writing an
   abstract facet first is legitimate as **planning**, the way an OCaml
   programmer writes type definitions first to document what the code is
   hoped to do. The principle itself sharpens here (recorded in
   `language-design-philosophy.md`): example-then-generalise constrains
   *obligation, not option* — it doesn't forbid general schemas; it
   means you shouldn't *have* to write them. Everything doable with
   general schemas should also be doable by a concrete-first path — a
   direction the language works toward, not an absolute honored at all
   costs. Consequence for facets: both authoring directions are wanted
   (author-then-attach; extract-from-concrete), and extraction is the
   one the principle points at.
2. **No single theory.** This is a huge, open-ended idea that likely
   manifests in several unrelated ways; you can't just say "this is what
   a facet is" and be done. Methodological consequence: a future round
   should work *one* manifestation against a real program — the algebra
   facet with the test double is the one with a waiting demand — rather
   than attempt a general theory. That is example-first applied at the
   meta level. The algebra facet has a second waiting client from inside
   the record: the collect family (`collect-family-design.md`) consumes
   it as the authoring surface by which a user operator mints its monoid
   catalog row, with the added constraint that the facet carry a *value*
   witness (the identity element itself), not just a named law; the
   offer is consumed by checking, and the claim's truth is trusted like
   a JS-boundary assertion. *The recommended round has since been run:*
   `late-bound-operations-design.md` works the algebra facet with the
   test double, and pins three things about facets in passing — a facet
   can group operation pairs, carries the sequenced/unordered ordering
   commitment (a handle), and is the identity binding matches on
   (drawn reference, never structural search). Attachment (edge 3
   below) remains unworked.
3. **What attachment is, representationally.** A relationship between a
   facet and a program version — plausibly transformation-levels
   territory (a level-1 relationship that survives edits which don't
   touch the faceted structure and is re-earned by ones that do).
   Unworked.
4. **Holes and negative constraints against demands/offers.** Whether
   `types-design.md`'s property substrate can already express
   "everything in this region touches resource R only via algebra A" (an
   offer of absence), and whether possession-by-wiring makes most
   negative constraints structural rather than asserted. Unworked.

## A tractable core: facets as view toggles (noted 2026-07-23)

The design conversation that set the IO-as-flow direction
(`effects-design.md`) noticed a ladder of facets that are cheap,
obviously implementable, and useful on day one — a tractable core
for this area, below the authored-abstraction ambitions above:

- **Wire-species visibility.** Turn the IO wire off when it is not
  relevant to the current thought process; turn it on to audit
  sequencing. (The failure round's site-picking view and the
  external-ordering facet filed at `effects-design.md` are the
  same species.)
- **Layout-constraint sets.** Toggle "all joins in a vertical
  column in global-flow order" (the rail reading) on and off —
  the facet is a set of layout constraints, not content.
- **Interpretation switches.** Flip the IO wire between its
  handle spelling and its inner-flow spelling — one program, two
  synonymous readings, the facet choosing which is rendered.
- **The general case:** other special sequencing wires that can
  be shown/hidden, each carrying **algebraic layout constraints**
  (like IO join's associativity licensing rebracketing into the
  uniform column) that can be switched on and off.

What makes these tractable: each is a pure derived-view toggle
over the one stored representation — nothing is authored, nothing
attached, nothing verified — so they sidestep open edges 1 and 3
entirely while delivering the "inspect only some aspects" value
this chapter promises. A future round can build the
authored-facet ladder on top of a working toggle substrate rather
than designing attachment in the abstract.
