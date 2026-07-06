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

Sharpening: the source of truth is the *highest description that is
still true*. Reads are free through the derived view; a write into
one forces a splice — the expansion is materialized into the program
of record and the abstract form is given up, deliberately, because
the coming edits would falsify it. Keeping "sum, plus a patch" when
the step is no longer a sum would be fake abstraction. Rule of
thumb: reference the derived view to *add*; splice to *change*.
Level-1 operations (conversions, recognition) are built-in catalog
entries, not user-written macros.
