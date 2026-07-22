# Types — or, validity without a type system

Status: exploration — this chapter teaches a worked proposal that has
not been adopted; nothing here is implemented. It works out what falls
cleanly out of the existing design, lays out the options where a real
choice exists, and records the rest as open questions. Read it as
"here is a candidate for how validity could work, and the case for
it." The code samples use the textual syntax of
`textual-representation-design.md`.

## A program that can't mean anything

Here is a short program with a mistake in it:

```
xs -> open list -> double -~> collect => ys   -- ys offers list-shaped
ys -> add(1)                                  -- clash: add demands numeric,
                                              --   ys's source offers list-shaped
```

The first line is fine: open a list, double each element, collect the
results back into a list named `ys`. The second line is the mistake.
`add` only makes sense for numbers, and `ys` is a list — adding 1 to
a list means nothing.

Look at the words the comments use, because they are most of this
chapter's vocabulary. `add` **demands** something of its inputs: they
must be numeric. The collect **offers** something about its output:
it is list-shaped. Between the two nodes runs one wire, and along
that wire the offer travels forward until it meets the demand. They
contradict each other — a thing is not both a number and a list — and
that contradiction is called a **clash**. The two nodes at either end
(the collect that established the shape, and the `add` that demanded
otherwise) plus the wire between them are the clash's **witness**:
every part of the explanation is something you can point at on the
diagram.

That is the whole proposal in miniature. The rest of this chapter
makes it precise, follows it as far as it reaches, and is honest
about its edges.

## Now, you might wonder: why doesn't the language have a type system?

Because some notion of validity clearly exists — the example above is
wrong, and something should say so. So why not do what other
languages do and give every value a type?

It turns out a conventional type system collides with the language's
own design criteria, all four ways at once. Types are unwelcome here
because:

- they are secret extra information you don't see in the program
  structure;
- they are not visual;
- they can surprise you with errors whose rules were never on screen;
- and they add complexity.

All four complaints are already design criteria elsewhere in the
repo. The iteration-rail notes reject any mechanism where "meaning
lives entirely in what's wired to" an otherwise blank construct. The
commute notes reject "a context-sensitive linearity rule the user has
to discover by hitting the error." A conventional type system is both
of those at once. (This stance is settled — please don't re-propose
importing a conventional type system without new evidence.)

But refusing the type system does not make the validity question go
away. Plus only makes sense for numbers; option uncollect only makes
sense for an option; reduce-close only makes sense for an associative
operator. Not every node combines with every other node, and a
language that lets you draw the combination anyway has only deferred
the error, not avoided it.

So the goals, up front:

1. **Show the user as little as possible.** No annotations in
   programs; no obligatory signature ceremony; nothing you must write
   before writing the concrete thing.
2. **Fit the value language — wires and nodes, visual.** Where type
   information is shown at all, it should annotate the program in its
   existing shape, not appear as a second notation beside it.

## Three jobs, kept apart

Conventional types do several jobs at once, and it is worth refusing
the bundle before designing anything. The jobs are:

1. **Validity** — telling a valid program from an invalid one. That
   is what the opening example needed.
2. **Summarization** — describing a program compactly ("this takes a
   list to a list") without reading its whole body. Explaining a type
   *error* is a special case: summarizing why two parts of the
   program cannot coexist.
3. **Placeholder building** — working with a value whose source you
   haven't decided yet but about which you know something ("I don't
   know where this comes from, but it will be a list"), with ready
   access to the operations that knowledge unlocks.

(A fourth job — compiler optimization — is out of scope. The compile
pipeline already runs property-shaped analyses of its own, e.g. the
consumer-set analysis in the stream placement design, and can grow
more without anything here changing.)

Traditional design serves all three jobs with a single mechanism:
**every value has exactly one complete type.** This chapter takes the
opposite position — the three jobs are three different *read-outs* of
one shared substrate, and the substrate is not one-complete-type.
Each read-out gets its own section below.

## You might also wonder: why not one complete type per value?

Even without annotations, couldn't the checker simply infer one
complete type for every value, the way ML-family languages do? Two
motivations are usually given for that discipline, and it turns out
neither survives this language's goals.

**"You need something compact to show the user."** Only if you want
the user to see *all* type information about a value. Goal 1 says the
opposite: what the user sees is a *summary*, partial by design, at a
detail level chosen when it is shown. Once the displayed thing is
officially incomplete, there is no pressure for the underlying thing
to be a single displayable artifact.

**"You need it for modular checking."** The real requirement is
weaker: a reusable diagram needs *some* boundary artifact, computed
once, that call sites can check against without re-examining the
interior. That artifact does not have to be one complete type; it has
to be whatever the checker propagates, projected onto the diagram's
ports (see "Reuse without one complete type" below).

There is a third, usually unstated motivation — the closed-world
guarantee that a well-typed program has *nothing else* to go wrong.
The honest version for this language is scoped: every operation node
states what it needs, and checking means no node ever receives
something it didn't ask for. That is soundness relative to the node
catalog, which is the only soundness a language with a JS boundary
can offer anyway (see "The JS boundary").

Beyond the practical arguments, one-complete-type fails two of the
language's philosophy tests directly:

- **Example first, then generalise.** Declared types are structure
  declared upfront, before the concrete computation — exactly the
  shape the first principle rules out. Whatever general knowledge the
  system holds should be *read off* the concrete program, the way the
  design reads iteration off a concrete feedback step.
- **No bottlenecks.** A complete type is a product bottleneck at the
  meta level: every fact about a value — shape, capabilities,
  relationships — packed into one artifact to pass a boundary, then
  unpacked on the other side. The language's answer to bottlenecks is
  to let things pass through *as themselves*. Facts about values can
  do the same: each property travels individually along the wires it
  is about.

(This too is a settled rejection within this proposal — the substrate
is properties on wires, not one type per value; don't re-propose the
latter without new evidence.)

## The language already checks things

Before designing anything new, notice that the design record already
contains a validity architecture. Naming it is most of the work of
fitting types into it.

**Three enforcement tiers**, in order of preference:

1. **Unrepresentable** — ill-formed things you cannot draw.
   `flowRef`'s constructors make "App a flow" and "branch off a Lit"
   unwritable; value wires and flow wires are disjoint sorts; the
   Commute node carries no value ports, so a program distinguishing
   map-then-commute from commute-then-map cannot be expressed; there
   is no bare read of a var.
2. **Whole-diagram quotient constraints** — enforced as a check, not
   by construction. This is the family that already holds alt
   matching, the no-crossing rule, and the Delay productivity check.
   Type checking is a new member of it. Checks are the sanctioned
   mechanism precisely because by-construction enforcement would
   force upfront declaration and break example-first authoring.
3. **Trusted** — hazards left as documentation, not checks:
   no-time-travel (today), closed-scope leakage, infinite-stream
   commutes, race nondeterminism. Some await a checker; others are
   *deliberate* non-errors and should stay that way.

**The flow side is already typed — property-style.** Everything
type-shaped in the design attaches properties to flows and gates
operations on them:

- The **flow-kind table** (now / later / always × zero-or-one /
  exactly-one / many, plus the failability dimension) is a kind
  system whose cells are ruled in or out by observability arguments,
  and whose kinds carry defining properties ("a var must always be
  readable").
- The **wrapper-stack shape discipline**
  (`lazy-stream-commute-design.md`) is a small working type system:
  each stage of a `Joined`/`Filtered`/`Commuted` stack has a
  requirement ("at least two layers remaining", "the per-element
  value must be option-shaped"), and a stack is well-formed iff every
  stage's requirement is met when reached — an ill-formed stack is
  rejected at compile time, not given a fallback meaning. What is
  threaded is layers-remaining plus a per-element *shape*.
  "Option-shaped" is a property, not a complete type.
- **Capability gating**: reduce-close exists only for operators with
  an associative monoid — "no monoid, no node"; cutoff needs an
  equality on the value; transpose needs rectangularity;
  commutativity of custom flows is *inferred*,
  most-restrictive-wins, no user annotation.
- **Bundle provenance** (which conditional bundle a flow came from)
  is the oldest open checking problem in the record, now worked out
  in `bundle-provenance-design.md`.

**Value wires are the deliberately unfilled hole.** The spec states
that value types — what kind of data flows through value wires — are
outside its scope and will be addressed separately. This chapter is
that "separately."

So the task is not to import a type system. It is to extend the
existing property-shaped, check-based style from flows to value
wires.

## The substrate: demands and offers

You have already seen a demand and an offer in the opening example.
Here is the general shape. Every operation node, as part of its
catalog entry, states two kinds of facts:

- **Demands** on its input ports: what must be true of a value
  arriving there for the node to make sense. Plus demands *numeric*
  of both inputs. Option uncollect demands *option-shaped*.
  Disaggregate demands *has field f*. A CaseSplit uncollect demands
  *alternative-shaped with alts {A, B, C}*.
- **Offers** on its output ports: what the node establishes about
  what leaves. Plus offers *numeric*. A list collect offers
  *list-shaped*. A literal offers whatever its payload is.

Between nodes, properties travel along wires. Offers propagate
forward (source to consumers); demands propagate backward (consumer
to source). Structural nodes *transport* rather than demand: a list
uncollect moves the element-properties of the incoming list onto the
element wire; a collect moves the element wire's properties into the
outgoing list's element-properties; aggregate/disaggregate route
properties through fields; Delay transports its value properties
around the back-edge (making propagation a fixpoint over cycles,
which is fine — the domain is finite and propagation is monotone;
note the cycle set this fixpoint runs over depends on which flow
binds the Delay, an open question about what a Delay *is* —
`delay-ontology-design.md`).

No value "has a type." A wire has whatever properties are derivable
at it — possibly none.

Three consequences do the load-bearing work.

**Wires are the type variables.** Textual type systems need invented
variables (`'a`, `T`) because in text, two uses of the same unknown
are connected only by a name, and the checker must reconstruct the
sharing. Here the sharing is drawn: a wire *is* the shared unknown,
and fan-out from one port *is* the constraint that all consumers talk
about the same thing. The constraint network the solver runs on is
the diagram itself, not a shadow structure derived from it. This is
what goal 2 means concretely — there is nothing beside the program,
because the program's own wiring is the entire type structure. (It
also answers "elements remain of the same type": in text that claim
needs a type variable appearing twice; here it is the observation
that the output's element wire traces back to the input's element
wire.)

**The property layer derives; it never adds.** Every property at
every wire is computed from two visible sources: the catalog entries
of the nodes present, and the wiring between them. The checker holds
no fact about the program that a reader who knows what each node is
couldn't in principle read off the diagram. This is the answer to
"secret extra information" — the property layer is a derived view, in
exactly the sense of "abstraction is the source of truth;
concreteness is a derived view." Derived views are read-only, lazily
computed, never edited. There is no type artifact to keep in sync,
because there is no type artifact.

**Checking joins the quotient-constraint family.** Demands-are-met is
a whole-diagram check over the assembled graph, not a by-construction
discipline that blocks drawing. You can wire anything to anything
while building; the check tells you what the result means. This
keeps example-first authoring intact and makes partial diagrams
(first-class in the spec) unremarkable: an unmet demand in a
half-built diagram is not an error, it is the edge of the
construction (read-out 3).

### Now, you might wonder: why can't plus also join strings?

Many languages overload their operators — `+` adds numbers and
concatenates strings, and the type system picks the meaning. Why
doesn't this language do the same?

It turns out overloading would cost the checker its most important
property. Here, one node has one meaning: plus is numeric addition;
string concatenation is a different node. If a node's demands
depended on which of several instances applied, propagation would
need search — choose an instance, backtrack on failure — and search
is where surprise lives: errors reported far from their cause, rules
the user never saw. The language already wants "one obvious reading
per program"; the checker gets to want it too. This is the single
most important simplicity commitment here: **the solver is monotone
propagation to a fixpoint, with no choice points.** Anything that
would require search to establish is outside the checker's remit,
full stop — the same move the design already makes when it leaves
infinite-stream footguns as documentation. (Settled within this
proposal: no overloading — please don't re-propose it without new
evidence.)

## Read-out 1: validity

With the substrate in place, when is a program invalid? In exactly
two ways.

1. **A clash** — a demand meets an offer that contradicts it. Shape
   properties are mutually disjoint (a thing is not both numeric and
   list-shaped), so *numeric* demanded of a wire whose traced-back
   source offers *list-shaped* is a contradiction with two
   identifiable anchors: the node that established the shape, and
   the node that demanded otherwise.
2. **An unmet demand at a concrete source** — a demand propagates
   back to a fully-known source that does not satisfy it: *has field
   f* arriving at an aggregate with no field `f`. (Capability
   properties like *equality-comparable* never clash with anything;
   they can only go unmet.)

A clash is concrete — it is the opening example. `add` demands
*numeric* of both inputs; a list collect offers *list-shaped*:

```
xs -> open list -> double -~> collect => ys   -- ys offers list-shaped
ys -> add(1)                                  -- clash: add demands numeric,
                                              --   ys's source offers list-shaped
```

The witness is two anchors — the collect (offers list-shaped) and the
`add` (demands numeric) — and the single wire between them.

Every violation carries such a **witness**: the anchor node(s) plus
the wire path the properties travelled to meet. Because propagation
has no choice points, the witness is unique and walkable — each hop
is a real wire in the program, and the explanation of the error is a
walk along it (read-out 2). This is what unification-based inference
famously lacks: when unification fails, the blamed location is an
accident of traversal order and the explanation mentions variables
the user never wrote. Here provenance is not a diagnostic
afterthought; it is the propagation itself.

**Severity tiers.** Clashes are errors. But the design record also
has an advisory tier: the zipper soundness check *warns and degrades*
("cannot verify termination, using lazy evaluation") rather than
rejecting. Keep the distinction between *this cannot mean anything*
(clash — reject, as the wrapper-stack discipline rejects) and *this
is beyond what I can check* (warn, stay out of the way). The
deliberate non-errors of tier 3 stay non-errors.

**The flow-dependency check is the same machinery.** The oldest
validity rule in the record: every value has an associated flow
dependency — the flow context(s) it belongs to — and flow
dependencies must be aligned before values can be combined. That is
a demand/offer rule where the property is the value's flow-context
chain: opens offer it, combining nodes demand alignment. The
currently *trusted* no-time-travel rule (`deeper(a, b)` quietly
picks one context for unrelated scopes) becomes a checked clash with
a drawable witness — the two sibling opens are the anchors:

```
listA -> open list => a, ~A
listB -> open list => b, ~B     -- sibling opens; unrelated contexts
a, b -> add                     -- clash: a and b have no canonical pairing;
                                --   witness = the two opens
```

This is the first check worth implementing — one the compiler is
already silently assuming (see "Smallest first step"). Its
refinement into full bundle provenance is
`bundle-provenance-design.md`.

### The JS boundary

Lit payloads, App functions, and discriminators are arbitrary JS.
What they offer is *asserted* by their catalog registration or the
literal's visible payload, not verified — a discriminator registered
as producing alts {Just, Nothing} could return anything at runtime.
This is the honest edge of the system: soundness is relative to the
catalog, and the catalog's own claims about JS are trusted. (Open
question: whether discriminators and primitives should register
through a schema that keeps the assertions in one auditable place.)

## Read-out 2: summaries, and types as generalized programs

Suppose you want to describe a sort function without reading its
body. Here it is at three levels of detail:

    [list] ──▶ (sort) ──▶ [list]                 shape only
    [list of e] ──▶ (sort) ──▶ [list of e]       + element link
    [something] ──▶ (sort) ──▶ [something]       shapes withheld

All three are true. "Takes a list to a list." "…and the elements are
unchanged." "Takes something to something." That is the constraint
summarization has and validity doesn't: **there is no one right level
of detail.** Which details matter depends on what the user is doing,
so detail must be chosen at *display time*, not baked in at
definition time. (In the middle line, the two `e`s are one drawn
wire, not a shared name.)

Now, you might wonder whether a "type" could simply *be* such a
simplified, generalized program — collapse the nodes not expected to
carry useful information, replace specific values with "generic
number," and call the result the value's type. It turns out this
candidate is right about the *form* and wrong only if taken as the
*substrate*: a generalized program fixes one level of collapse, and
summaries need the level to be a free parameter. The resolution
(this is a dissolution, not a rejection — the idea survives in a
different role): **properties are the substrate; generalized
programs are the display format.**

A summary of a diagram at a chosen detail level is derived, on
demand, as:

- collapse interior structure below the chosen level (the
  interface-summarization rewrites — sequential collapse, identity
  elimination, data-operation hiding — are the existing,
  meaning-preserving machinery);
- keep the boundary ports, annotated with a chosen *subset* of their
  derived properties (shape only; shape plus capabilities; nothing
  at all — "something to something");
- draw the relational links that survive the collapse (the
  output-element-traces-to-input-element wire is what "elements
  remain the same type" *is*).

The result is itself a diagram — same nodes-and-wires vocabulary, no
second notation. Summaries obey the lens discipline: read-only
derived views, lazily materialized, never edited, never the source
of truth. When the system must pick a default level it should follow
"each version reads at the highest level that is true of it" — show
the strongest properties actually derived, collapse the rest — but
defaults are UI policy, not meaning, and belong to the
(out-of-scope) editor design.

### Error explanation as summarization

A type error is a clash between two parts of the program, so its
explanation is a summary of the witness: highlight the two anchor
nodes, draw the connector along the transport path, and caption each
end with the one property in conflict ("list-shaped, from here" /
"numeric, needed here"). The error display annotates the program in
its existing shape — goal 2 applied to errors — and every step of
the explanation is something the user can point at.

Flow-side errors get the same treatment and mostly have it already:
a crossing without a commute has a geometric witness (the crossing);
a time-travel clash has the two sibling opens; a bundle-mixing error
has the two flows and their common bundle
(`bundle-provenance-design.md`). The requirement across both sides:
**no error without a witness drawable on the diagram.** A rule that
can only be stated as prose about invisible context — the commute
doc's rejected Option 7 is the canonical example — is not a rule
this checker gets to have.

## Read-out 3: placeholders

Suppose you know a value will be a list, but you haven't decided
where it comes from. You can start building anyway:

```
src : list => xs          -- schematic source, offers list-shaped (spelling provisional)
xs -> open list -> price -> add(tax) -~> collect => out
                          -- demands accumulate back at src:
                          --   "list of {price: numeric}"
```

`src` here is a placeholder — a **schematic source**: a node with no
computation behind it, carrying whatever offers the user chooses —
possibly none. Two propagation behaviors fall out with no new
mechanism:

- **Offers unlock operations.** Declaring "this will be a list"
  offers *list-shaped*; list uncollect's demand is met, and the
  whole list vocabulary is available downstream before any source
  exists.
- **Demands accumulate into an interface.** An unmet demand that
  propagates back to a schematic source is not an error — it is
  absorbed as part of the placeholder's inferred description. Build
  the pipeline first, and the placeholder ends up knowing it must be
  "a list of things with field `price`, numeric" — read off the
  concrete program, never declared.

This is example-first applied to interfaces: the generalization is
identified after the concrete case, exactly as the link identifies
iteration after the concrete step.

The language is arguably already built this way. The iteration
rail's `elem` is "the element at the current position" — every
per-element body is authored against a schematic value whose only
known facts are properties. And the spec supports partially
constructed diagrams as first-class. Placeholders are the same
condition, made available on demand rather than only inside flows.

**Reusable diagrams are the same story.** A diagram's value inputs
are schematic sources; the demands that reach them, plus the offers
at its outputs, plus the relational links between ports, *are* its
signature — inferred, not written. Slot signatures (today: port
names only) are the natural attachment point for the same
information on the caller-supplies-a-diagram side.

**Editor assistance, carefully scoped.** The demands at an open wire
end describe what would fit there, and an editor could filter its
palette accordingly. This does not cross the "no implicit magic"
line, which bans *relying on type inference or constraint solving to
determine behavior*: behavior is still determined only by explicit
nodes the user places. Checking validates choices; suggestion
narrows menus; neither chooses.

## Reuse without one complete type

The modularity worry, taken seriously: a complicated diagram used in
many places should not be re-propagated at every use.

The answer is **boundary projection**. Propagation inside a diagram
interacts with the outside world only through the diagram's ports —
that is what being a diagram means. So run propagation over the
interior once, then project the resulting store onto the boundary:
residual demands on each input port, offers on each output port,
relational links among ports. Call that the diagram's **principal
property signature.** Checking a call site uses only the signature;
the interior is never re-examined. It is computed once per diagram
*version* — and since programs are persistent structures where every
change builds a new version sharing untouched parts, property stores
memoize the same way: an edit re-propagates only the region whose
nodes changed, and untouched subdiagrams keep their signatures. The
step-DAG design and this checker are unusually good for each other.

The projection plays exactly the role a principal type plays in
conventional systems — the reusable distillate — without being one
complete type: it is a *set* of properties and links, each traveling
its own wire at the call site, each independently absent-able.
(Precedent: constraint-based formulations of inference check against
a constraint set simplified at the boundary; structural/row-typed
systems show port-projected requirement sets composing at scale.
Nothing here is novel type theory; the novelty is only that the
constraint graph is the visible program.)

Two honest strains:

- **Slots.** A diagram with a slot has a signature *conditional on*
  the slot's: "for any filler whose output offers P, my output
  offers Q." That is an implication, one step up in complexity from
  a property set. It is also unavoidable — slots are the language's
  higher-order boundary, precisely where one-complete-type systems
  pay their highest costs (function types). Needs its own design
  round; flagged open.
- **Relational blowup.** Links are pairwise facts among ports; a
  diagram with many ports could in principle carry many. In practice
  links exist only where a wire actually threads from port to port,
  so the signature is bounded by real connectivity — but this should
  be checked against real examples, not asserted.

## A starter property inventory

Method: sample the demands the design actually makes; do not filter
for interesting cases or design to a theory's categories. Every row
below is a demand some existing construct already places.

| Property                        | Demanded by                          | Offered / established by            |
|---------------------------------|--------------------------------------|-------------------------------------|
| numeric                         | arithmetic primitives                | numeric Lits, arithmetic outputs    |
| string-shaped, bool-shaped      | string ops; conditionals' tests      | Lits, comparisons                   |
| list-shaped (of E)              | list uncollect                       | list Lits, list collect             |
| option-shaped (of E)            | option uncollect; `Commuted` stage   | option-producing sources            |
| alternative-shaped, alts {…}    | CaseSplit uncollect; alt matching    | discriminator registrations         |
| struct with field f (of F)      | Disaggregate                         | Aggregate, struct Lits              |
| equality-comparable             | cutoff                               | per-shape (structural)              |
| associative, has-identity       | reduce-close (of its operator)       | operator catalog entries            |
| flow-context chain              | any multi-input combining node       | opens (the context each creates)    |
| same-as (relational link)       | — (never demanded; only displayed)   | transport through structural nodes  |

Notes:

- **Shapes are disjoint**; capabilities are independent of shapes;
  links are relations, not unary facts. Three different sorts, and
  keeping them separate is what keeps the algebra shallow: no
  entailment lattice, no user-defined implications, no subtyping —
  initially. Each addition to the algebra should be earned by a
  construct that demands it, the way every row above is.
- **Operator properties attach to operators, not values** —
  "associative" is a fact about a catalog entry. The open question
  of how identities attach to operators (a registry, a property on
  the operator node, something the user can extend) is a question
  *inside* this table.
- **Alt matching is subsumed.** The existing quotient check that a
  case collect covers its uncollect's alts is this system applied to
  the alternative-shaped property — evidence the substrate is the
  right shape, since the language's oldest check is an instance of
  it. Likewise the wrapper-stack discipline is this system applied
  at flow-annotation stacks.
- **Flow kinds stay where they are.** The now/later/always table and
  per-kind operation legality are the flow side's own discipline.
  This chapter's substrate is the value-wire sibling; the two meet
  at nodes (an open's demand on its value input, its offer on its
  element output) but are not merged.
- Now, you might wonder why the table has no numeric refinements —
  no "0 to 100" on a wire. **Numeric refinements are out of remit**
  for now, by the no-search rule — range reasoning is arithmetic,
  not propagation. This is set aside, not rejected: the instinct to
  write them at ports can be honored as *documentation* on a port,
  unchecked, which is what those annotations were anyway.

## What this deliberately is not

A short list of things a reader might expect from the word "types"
that this proposal deliberately does not include:

- **Not annotations.** No program contains a type. Placeholders and
  slot signatures may *carry* chosen offers, but they are nodes and
  ports — program structure, not metadata.
- **Not nominal.** Structs and alternatives are structural, as the
  spec already has them (a StructType is a field list; an
  AlternativeType is a list of alt names). Two struct types with the
  same fields are not distinguished. If nominal identity is ever
  wanted, argue for it separately.
- **Not inference-that-chooses.** Propagation never picks a node, an
  instance, or a meaning. No overloading, no coercions, no
  defaulting.
- **Not a completeness guarantee.** The checker verifies demanded
  properties and nothing else; JS-boundary assertions are trusted;
  deliberate non-errors remain runtime hazards. "Well-checked" means
  every node gets what it asked for — no more.
- **Not a second artifact.** Nothing is stored that the diagram plus
  catalog doesn't determine; everything shown is a derived view;
  nothing shown is edited.

## Smallest first step

The compile pipeline can grow the substrate's skeleton with no UI
and most of the inventory absent:

1. **Flow-context alignment** (the time-travel check). The compiler
   already computes each binding's scope; the check that an App's
   args' scopes form a chain — with a real error naming the two
   offending opens, instead of `deeper` silently picking — is the
   demand/offer machinery for exactly one property, and it converts
   the design's largest *trusted* rule into a *checked* one. The
   README already lists this as a next step; here it is reframed as
   the first types feature.
2. **Shape propagation for the existing node kinds.** Lit shapes
   from payloads; App demands/offers from a small registry keyed by
   the fn expression; transport through Open/Close/Branch (Branch
   dissolves under ports-migration step 2; the transport role moves
   to the alt ports). Enough to make "plus applied to a list" a
   compile-time clash with a two-anchor witness in test output.
3. **A schematic source node kind** with declared offers, so
   placeholder-driven construction is exercisable in tests —
   including the interface-accumulation direction (assert on the
   residual demands the checker reports at a placeholder).

Each step is independently testable in `Main.res` style (build an
Expr, expect either a compile or a specific clash), and none touches
the visual layer.

## Open questions

The language hasn't decided any of the following yet.

1. **Naming.** "Type" is the word this chapter avoids; "demand",
   "offer", "property", "clash", "witness", "signature" are
   placeholders themselves. Whether the user-facing vocabulary
   should ever say "type" is a real choice — there is an argument
   for keeping the familiar word for the summary views and reserving
   the new words for the machinery.
2. **Recursive shapes.** Trees and other recursive ADTs
   (`trees-and-recursion.md`) need shape descriptions that mention
   themselves, and transport through recursive structure is where
   propagation earns or loses its simplicity. Needs a worked design
   round; the disciplined move is to wait for the iteration/tree
   constructs to land in the repo first.
3. **Slots and higher-order signatures.** Conditional signatures
   ("for any filler offering P…") — how they are represented,
   propagated, and displayed. The language's function-type question,
   deliberately deferred. One consolidation since filed: the
   function-boundary round (`function-boundary-design.md`,
   exploration) proposes dissolving the slot into the late-bound
   op pair, so the conditional-signature design is owed once — for
   the pair — and slots would inherit it. The design itself remains
   deferred.
4. **The catalog schema.** How primitives, operators (with their
   monoid facts), and discriminators declare demands/offers — and
   whether discriminator registrations can be made honest (e.g.
   generated together with the JS they describe).
5. **Bundle provenance.** Worked out in
   `bundle-provenance-design.md`. Both hunches held: it uses the
   same propagation skeleton (the relational "same bundle" relation
   dissolves into per-wire context paths compared at demand time),
   and the same witness treatment (the shared construct plus two
   cell edges). It is a flow-side property, not a value-wire one — a
   sibling to this design.
6. **Summary defaults and the tower.** Are generalized-program
   summaries level-1 citizens — derived views with port
   correspondences, like expansions — or editor ephemera? The lens
   discipline suggests the former, which would give "the summary of
   a version" a place in the step-DAG. Interacts with the
   (out-of-scope) editor design.
7. **Advisory-tier contents.** Which currently-trusted hazards
   graduate to warnings once the machinery exists (closed-scope
   leakage seems ripe; infinite-stream commutes explicitly should
   not), and whether warn-and-degrade ever applies on the value side
   the way it does for zipper soundness.
8. **Equality's fine print.** *Equality-comparable* is offered
   "per-shape (structural)" above, but structural equality over
   which shapes, and whether users can substitute an equivalence, is
   unresolved — the first capability whose definition is itself a
   design problem.
