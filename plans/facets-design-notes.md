# Facets — recorded intuitions

*Recorded 2026-07-10 from a design conversation, prompted by the
Effekt comparison round's test-double finding
(`effekt-comparison.md`, finding 2: "how do you run a diagram that
does IO against fake IO?"). **Intuitions and guiding principles,
deliberately undeveloped** — recorded in the author's own framing
for future development; no round has been run and nothing here is
adopted. This doc extends, and does not supersede, the earlier
facets note (`tough-use-cases-design.md`, addendum "Facets: partial
views against crowding"); the relationship is worked out at the
end. The demand side lives on the functions/reuse/facets row of
`open-problems.md`. Annotations connecting these intuitions to the
rest of the record are bracketed and marked, so the recorded
intuitions stay distinguishable from commentary.*

## The gap this names: concrete vs schematic

The language is very good at the concrete. It is not good at
**schematics** — separating the shape of data, the shape of a
computation, the sequence of steps, the states of a state machine,
from the other details of the program.

The running example: a program that does a bunch of file
operations. One facet is just *the sequence of operations* — not
what they do, but which functions it calls and in what order. Step
back and get more general: it has the facet that *every file that
is opened is closed*.

*[Annotation: this is the same territory the Effekt round hit from
the outside — findings 1–2, late-bound operations and the test
double. Their examples demonstrated the capability; this
conversation names what the capability is an instance of.]*

## Not one carving

Since this is a visual language with (presumably) an interactive
editor, there is a freedom a fully textual language like Effekt
does not have: the code does **not** have to be carved up into
facets in just one way. The user picks which facet it makes sense
to view in the moment.

## A facet can be authored alone

First guiding principle: the user should be able to **write just a
facet**, with nothing concrete.

## The ladder: struct → interface → facet

The worked example is from data, because existing languages are
better at data — but it sets the bar for what "abstract" means
here.

A **struct** is a kind of facet: one facet of this variable is
that it has fields `x` and `y`.

At some point people realized "has fields x and y" was a little
more general than a struct — what if the fields are computed? So
they created the **interface** and said: `x` and `y` are functions
now. But while an interface applies to things the struct couldn't,
**it is not actually more abstract**. It is, concretely, a pair of
functions, and you adapt it to new situations by writing bodies
for those functions.

A real **facet** would be the abstract concept of *having an `x`
and a `y`*. What are they — variables, fields, database columns?
None of these. It is not something concrete you can build. You
can't say "pass me an x-y-haver" — out of context that doesn't
mean anything.

But you *can* say: when you build this database table, give it a
facet saying what the columns are; and when you build this struct,
give it a facet saying what the fields are. And since we know we
used **the same facet** for both, we know we'll be able to store a
database row in the struct.

*[Annotation: note the mechanism — the knowledge arrives from a
drawn identity (both attachments reference one facet), not from
structural matching of two independently-written shapes. That is
exactly the shape `types-design.md`'s no-search stance wants:
identity is checkable by looking; inference over "things that
happen to have an x and a y" would be search. It is also the
visible-wire spirit: the compatibility fact has a place you can
point at.]*

## Facets of code: algebras and state machines

The example was data, but it works for code too:

- You can make an **algebra** out of a set of functions and say
  this code has the facet of *being built out of this algebra*.
- You can design a **state machine** and say this code has the
  facet of *using these states and transitioning on these
  events*.

And then: if you know your production code and your test code use
the same facet, **you learn something about your production code
by testing your test code**.

*[Annotation: this is the inside-out reading of what the Effekt
corpus kept doing. Their `AD[Num]` interface is literally "an
algebra out of a set of functions" with three bindings (forwards,
backwards, symbolic); their from-list lexer and real lexer are two
bindings of one facet, and the shared facet is what makes the test
double informative. The comparison round derived the port-pair
leaning for *binding* (finding 1); this conversation supplies what
the bound thing is.]*

## Holes without breaking

It's trickier with code than with data, because in code you so
often need to **break a clean facet to get real work done**.
You've designed a perfect algebra of file operations, and then
someone says "oh, could you also log how many open files you
have" — and this algebra doesn't have counters; you have to break
the whole thing.

So with code, facets have to **allow for holes without breaking**:
it calls these functions, but it also does other stuff in the
gaps. What other stuff? Well —

*[Annotation: the record has two precedents for showing "there is
more here" without showing it: the function interface's data holes
(`functions-design.md`) and the earlier facets note's marked
escapes (projection route). The demand here is stronger than
either: the hole is not just displayed residue, it's the licensed
difference between the facet and the code that carries it.]*

## Negative constraints

Maybe that's where **negative constraints** come in. I can't tell
you what the code does besides use this algebra of file
operations — but I *can* tell you it will **not** touch the files
in that same directory. Then we can be confident the files in that
directory are accessed according to this algebra; everything else
is a mystery.

Negative constraints like that are rare — possibly never seen in
the wild — and that may be because they are actually useless,
because they are too weak. But it's a thought to keep in mind.
*(Recorded with its stated direction of doubt.)*

*[Annotation: one field sighting worth recording, from the corpus
just studied: Effekt's capture sets are negative constraints in
type form — `() => Unit at {}` says "this block touches nothing
ambient," and their scheduler's safety argument rests on such
absences. The practical form there is possession-shaped rather
than assertion-shaped: the code *was never handed* the capability,
so the absence holds by construction. That form may be unusually
cheap for us: in a language where resources are wires, "will not
touch those files" is "no wire from that resource enters this
region" — a drawable, provenance-checkable fact
(`bundle-provenance-design.md`), not an assertion about behavior.
If negative constraints ever get worked, possession-by-wiring is
the leaning to test first.]*

## What facets are NOT: verification

The goal is **not** formal verification. We are not building Agda.
The compiler is not proving the code sound.

What facets do is create **views**, so the user can look at the
code and see whether it *looks right*. It's a way of simplifying
and summarizing — a better angle on the code that might suppress
some of the noise and make it easier to spot a mistake. Whether
the code is actually correct must still be confirmed the
old-fashioned way (tests, etc.).

*[Annotation: this bounds the checking question before it is ever
asked: whatever "same facet" checking exists should be at the
level `types-design.md` already operates at — properties and
drawable witnesses, no search, no proof obligations. A facet is a
lens for a human, with just enough machinery that the lens isn't
lying about identity.]*

## How this extends the earlier facets note

The addendum in `tough-use-cases-design.md` treats facets as
partial **views** of an existing program, and works the viewing
side: recognition (partial, fragile, "abstraction is earned")
versus projection of authored structure (free, total, the
philosophy's preferred route). This conversation adds a third leg
that the viewing side presupposed but never named: the facet as an
**authorable artifact in its own right** — something that can
exist before and independently of any concrete program, and that
gets **attached** to concrete structure rather than derived from
it or recognized in it. The three legs compose in the obvious
order: author a facet alone; attach it to concrete things (one
facet, many attachments); view a concrete thing through any facet
attached to it. Attachment — what it is representationally, what
identity it creates, what its holes license — is the genuinely new
piece, and the viewing machinery of the addendum applies
downstream of it.

## Open edges (stated, not worked)

1. **Facet-first vs example-first.** "Write just a facet, nothing
   concrete" sits in visible tension with the first principle
   (write the concrete case, then generalise — never declare
   structure upfront). Candidate reconciliation for a future
   round, not decided here: attachment is bidirectional in time —
   a facet can be extracted *from* a concrete program after the
   fact (abstraction earned and upward) just as well as authored
   first; and when the facet is authored first, that's because the
   facet itself *is* the concrete example being worked (you are
   designing the state machine, not the program). Whether that
   dissolves the tension or hides it is for the round to find out.
2. **No single theory.** Explicitly recorded: this is a huge,
   open-ended idea that likely manifests in several unrelated
   ways; "you can't just say 'this is what a facet is' and be
   done with it." The methodological consequence (annotation): a
   future round should work *one* manifestation against a real
   program — the algebra facet with the test double is the one
   with a waiting demand — rather than attempt a general theory.
   That is example-first applied at the meta level.
3. **What attachment is, representationally.** A relationship
   between a facet and a program version — plausibly
   transformation-levels territory (a level-1 relationship that
   survives edits that don't touch the faceted structure, and is
   re-earned by ones that do). Unworked.
4. **Holes and negative constraints against demands/offers.**
   Whether `types-design.md`'s property substrate can already
   express "everything in this region touches resource R only via
   algebra A" (an offer of absence), and whether
   possession-by-wiring makes most negative constraints
   structural rather than asserted. Unworked.
