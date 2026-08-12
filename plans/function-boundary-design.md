# The function boundary: a cut, not a container

Status: **adopted** (design conversation, 2026-07-23 — the joint
adoption with the divide flow, late-bound operations, and the
served flow's two-ends core). Adopted: the cut ontology (a
function is a remembered cut; ports are the crossing wires, read
off at extraction — no argument list; membership derived;
closure capture dissolved into prefix sharing; reusability a
derived check with a drawable witness); the call/link substrate
sharing with recursion never routing through a named function;
the use-case account (functions exist for reuse only); partial
cuts; and no first-class function values. One piece carries a
**provisional-confidence marker**: the slot-dissolves-into-op-pair
result was adopted as the working position *without the adopting
conversation fully engaging it* — "what we're doing for now,
unless and until looked into further" — so a later look may
reopen that piece specifically without disturbing the rest. One
constraint binds the adoption (recorded 2026-07-23,
at `divide-flow-design.md` open question 1): **a level/boundary is
referenced by identity — a label or the boundary object — never by
a value wire** (the "innumerable 0s" argument: a value can't name a
cut point), and the link's correspondences are thread-species
identity assertions; anchoring-by-wire survives only as an editing
gesture that resolves to a boundary identity at creation.
**Extended (design conversation, 2026-08-04):** the cut re-founded
as a **node set with per-wire cut-or-environment decisions** (the
closed-curve description was topologically incoherent);
**copy-paste instance semantics** with no context memory; **flow
ports** and the drawn call-by-value/call-by-name duality;
containment derivable, never expressed; per-instance checking with
sound-but-partial isolation checking. See "Revision notes
(2026-08-04)" below, which governs where the body differs.
**Amended (2026-08-12,** `divide-flow-design.md` **revision
notes):** the level binding is removed from the substrate — the
divide flow's derived recursive "function" is not a binding of the
cut, exactly as a loop body is not; level labels dissolve (a
site's threads anchor at drawn wires); and the measure discipline
this doc cites is retired (no termination checking). The
divide-flow demand in the next sentence is history — that demand
was withdrawn by that round's "no boundary at all" refinement. The
open questions below keep their own status; nothing is
implemented. This is the round three worked
rounds jointly demanded ("one decision, three clients"): the divide
flow *then* needed the **level boundary** as its link's anchor
(`divide-flow-design.md`, open question 1); late-bound operations put
`op` pairs "on the diagram boundary" without saying what a diagram
boundary *is* (`late-bound-operations-design.md`, open question 1);
and the functions row's own doc (`functions-design.md`) carried the
flow-skeleton interface story on top of an undesigned boundary
construct. The served flow added a fourth client mid-demand: "a
server program is a provider diagram … the same diagram-with-ports
the functions row already has" (`served-flow-design.md`) — also
resting on the undesigned thing.

What this round consumes from the record: derived per-instance
membership and the shared-by-prefix rule (`divide-flow-design.md`,
"What is per-instance, and what is shared";
`bundle-provenance-design.md`); the no-lexical-scope principle P3
(`textual-representation-design.md`); boundary projection and the
principal property signature (`types-design.md`, "Reuse without one
complete type"); the placeholder story (demands accumulate into an
interface — `types-design.md`, read-out 3); interface summarization
as display-time collapse (`types-design.md`, read-out 2); residual
ordering constraints at the boundary
(`time-travel-programs-design.md`, "Reuse"); the node-set consequence
(`first-class-ports-design.md`; `visual-language-spec.md`,
"Diagrams"); the exchange pair and binding
(`late-bound-operations-design.md`); and the settled rejections of
function values and function-bodied map/filter
(`configuration-scopes.md`; `functions-design.md`).

Revision note: the round was revised after its first design
conversation (2026-07-22). The first draft's full call/link merge
("recursion is calling your own name") is withdrawn and recorded as
dead end 2 — the cut is a shared *substrate*, but the link and the
call stay two constructs, and recursion never routes through a
named function. The use-case section ("When is a boundary drawn")
and the partial-cuts section came out of the same conversation.

The one-sentence result, stated up front so the rest can argue for
it: **a function is not a container of nodes but a remembered cut
through the wiring — a named correspondence of ports — and
everything else about functions (what a call is, what is per-call
and what is shared, what the interface shows, where an `op` pair
lives) is derived from the cut rather than declared beside it.**
And one boundary on the result itself: **functions per se are about
code reuse** — sameness across sites. Recursion is the link's
(self-similarity across levels), standing on the same substrate
without becoming a call.

## Your first boundary, extracted

Start where the record's example-first principle says to start: with
no function at all. Here is a concrete program that computes the
same thing twice:

```
price -> mul(2) -> add(shipping) => totalA
fee   -> mul(2) -> add(shipping) => totalB
```

The repetition is the itch. In a conventional language you would now
*declare* a function — name it, list its parameters, restate the body
inside a new scope, and rewrite both call sites. Here the gesture is
different: **select the repeated computation and draw a cut around
one copy of it.**

```
        ┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐
price ──┼─▶ (mul 2) ─▶ (add shipping)┼──▶ totalA
        └╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┆╌╌╌╌╌╌╌╌╌╌┘
                     shipping crosses too
```

The cut is a closed curve through the wiring. Two wires cross it
inward (`price`, `shipping`) and one crosses it outward (the total).
Those crossing wires **are the ports** — nobody declares a parameter
list; the ports are read off the drawing, exactly as the placeholder
story reads a schematic source's interface off the concrete program
(`types-design.md`: "inferred, not written"). Name the cut, and the
second copy of the computation collapses into a reference to it:

```
diagram doubledTotal
  in x
  in shipping
  x -> mul(2) -> add(shipping) => t
  out total = t
end

price, shipping -> doubledTotal => totalA
fee,   shipping -> doubledTotal => totalB
```

(The `diagram … end` spelling is the record's existing provisional
form and survives unchanged; what this round changes is what it
*means* — see "The textual form" below.)

This is the extraction gesture, and it fixes the direction of
authority: **the ports come from the cut, never the cut from the
ports.** Declaring the boundary first — sketch the ports, fill the
interior later — remains available as planning, the way the
philosophy's principle 1 allows schemas as options; what the language
never requires is stating the general form before the concrete
computation exists.

## What the cut is not: a scope

Now, you might wonder whether the region inside the cut is a scope —
a container whose interior nodes "belong to" the function, with the
boundary as its walls. Every conventional language says yes: a
function body is a lexical region, names inside it are private,
values cross only by parameter-passing.

It turns out the cut must *not* be a scope, and the language already
knows why. P3 (`textual-representation-design.md`) rules out
delimited regions in text: "inside the loop" is a derived fact — a
statement is per-iteration because its inputs are — never a
syntactic region. The divide flow applied the same rule one level up:
which parts of a page are "in the recursion" is derived — *a node is
per-instance iff it is downstream of a problem wire* — and
everything else is a single shared value admitted by the prefix rule
(`divide-flow-design.md`). The function boundary is the same rule,
same words:

> **A node is per-call iff it is downstream of one of the boundary's
> in-ports.** Everything else that the boundary's cone reads — a
> constant, a lookup table, a configuration value — is a single
> shared value that every call reads, by the prefix rule. Nothing is
> copied into calls; nothing needs capture machinery.

Two consequences are worth pausing on, because both are things other
languages have to build machinery for and here they are corollaries.

**Call-invariant computation is shared by meaning, not by
optimisation.** Consider a boundary whose interior computes
something from no in-port at all:

```
diagram circumference
  in r
  tau = 3.14159 -> mul(2)        -- reads no in-port
  r -> mul(tau) => c
  out result = c
end
```

`3.14159 -> mul(2)` is not downstream of `r`, so it is not per-call:
it evaluates once and every call shares it. In a scoped language
this is "loop-invariant code motion," an optimisation the compiler
may or may not perform; here it is the stated meaning, and the
implemented compiler already behaves this way for the analogous case
(Lits memoised at top level, shared by every consumer —
`lazy-compile-design.md`). Where the author *wants* per-call
evaluation of something no in-port feeds — a fresh mutable buffer, a
per-call effect — that demand is exactly what the effects row's
per-firing-minted handle is for, and it is visible in the drawing
rather than a semantic accident of placement.

**Closure capture dissolves.** A function that "closes over" an
outer value is, here, just a cone that reads a prefix-shared wire —
the same non-event as a constant appearing inside a nested loop
(`core-model.md`, "Using values from outside the loop"). There is no
environment object, no capture-by-value-vs-reference question,
because there is no scope for the value to be captured *into*.

So the cut carries no walls. What, then, keeps a boundary honest —
what stops a "function" from quietly depending on its surroundings?
A derived check:

> **The reusability check.** A boundary is reusable iff everything
> its out-ports' cone reads, other than the boundary's own in-ports,
> is prefix-shared (context-free — readable from every context a
> call could occupy). A cone that reads a per-firing wire of some
> particular loop is not wrong — it is simply *local to that loop*,
> and the check names the offending wire.

This makes "can this be a function?" a question with a drawable
witness rather than a compile error about escaped variables. And it
makes the extraction gesture safe: cutting around a region that
reads a per-iteration wire doesn't fail — it *surfaces that wire as
a demanded port*, converting an accidental dependency into a visible
parameter. That is the placeholder story's accumulate-demands
behavior, applied to extraction.

## When is a boundary drawn — the use cases

Now, you might wonder how often anyone actually draws one. Most of
what conventional languages use functions for dissolves here, and
it is worth listing the dissolutions in one place because together
they say what remains:

- **Per-element bodies** are flows (`functions-design.md`'s settled
  decision — no function-bodied map/filter).
- **Callbacks** are served flows; the handler is a provider.
- **Behavior parameters** (comparators, predicates, strategies) are
  op pairs and configuration scopes.
- **Organization** — the quiet one. A large share of functions in
  real code are called exactly once; they exist to chunk a long
  program into readable pieces. Here that need is served by *views*
  (collapse a region to its skeleton — the display-time collapse
  level of the interface section below), not by semantics: a
  called-once region gains nothing from per-call instantiation. The
  cut earns its per-call semantics only where reuse exists.
- **Recursion** is the link's, not the function's — the separation
  worked in "One substrate, two constructs" below.

What remains — the cases where a user genuinely draws a named cut:

1. **Site-reuse of a domain computation.** The tax rule used in
   checkout *and* in the reporting batch; the date normalizer at
   every ingestion edge. The distinguishing property: the sites are
   *unrelated*. There is a crisp test, because reuse could always
   be faked with a flow — pack the sites' inputs into a
   manufactured two-element list, open it, compute once per firing.
   That move is wrong exactly when the sites have different
   consumers, different enclosing flows, different timing: then the
   list is a fiction minted purely to share code — the bottleneck
   anti-pattern in flow costume, declaring a relatedness the
   program does not mean. Stated positively: **a flow reuses a
   computation along one extent; a function reuses it across sites
   whose only relationship is the computation itself. The function
   is the honest form exactly where a shared flow would be a lie.**
2. **Providers.** Anything bound onto an op pair — the real
   backend, the test double, a middleware layer — is a diagram with
   a boundary. Every test double anyone writes is a function in
   this sense.
3. **Publication.** Reuse across *programs* — the library case,
   maximally unrelated contexts. The same construct, one more
   binding distance.

So functions should be *rarer* here than conventional intuition
expects — conventional counts are inflated by the dissolved
categories — and that is by design: each dissolved category got a
construct that says more than "call this." The function-unit
sample (open questions) is owed precisely to check this picture
against real populations rather than assume it.

## Ports are the crossing wires — the argument list is a bottleneck

Now, you might wonder why calls here are drawn with several
corresponding wires rather than "arguments" in the usual sense. It
turns out the conventional argument list is the product bottleneck
wearing its oldest costume: a tuple assembled at the call site
purely to cross a structural point, destructured on the far side
into parameters. The record's principle 5 bans exactly this — wires
pass through combining constructs *as themselves*, pairwise — and a
call is a combining construct. So:

- Each in-port is one wire in, each out-port one wire out, the
  correspondence pairwise (textual P5: labeled lanes, no tuple).
- A flow port is a port like any other, wired with its sigil. The
  threading shape from `functions-design.md` survives verbatim:

```
diagram print_string
  in s
  in ~io
  s, ~io ~> put => ~io2
  out ~io2 = ~io2
end
```

  An IO flow enters, a sequenced IO flow leaves; ordering is
  preserved because the flow is threaded, not dropped and remade. A
  boundary can take a flow, return a flow, open one internally, or
  collect one passed in — all just crossings of the cut.

- An `op` pair (`late-bound-operations-design.md`) is likewise
  ports: a request lane outward, a response lane inward, grouped
  under a facet identity. This round adds nothing to that design
  except the answer to its open question 1 — *where* the pair lives.
  It lives on a cut like every other port, and "the demand projects
  onto the caller's own boundary" is now a literal statement:
  an unbound pair's wires keep crossing outward, cut after cut,
  until some binding wires a provider on.

The general statement: **a boundary port is not a kind of node; it
is a crossing.** The Diagram record's four port lists plus slots
(`visual-language-spec.md`) become bookkeeping for one thing — which
wires cross the cut, of which sort, in which direction (value in,
value out, flow in, flow out, op request/response) — rather than
five species. The spec-side reconciliation is owed (open questions).

## One substrate, two constructs: the call and the link

The divide flow defined its link as "a node with input ports
corresponding pairwise to the problem wires and output ports
corresponding pairwise to the level's answer wires," each firing
minting an instance (`divide-flow-design.md`, "The link"). Read
that sentence against the boundary just built and the *machinery*
is identical: problem wires are in-ports, answer wires are
out-ports, the pairwise correspondence is a cut's crossing list.
The round's first draft therefore proposed the full merge — one
node species, recursion as calling your own name.

The round's first design conversation (2026-07-22) rejected the
merge at the construct level, and the correction improved the
design. The claim now:

> **The cut is one substrate carrying two constructs.** Instance
> minting, derived membership, context-path segments, and the
> measure discipline are defined once, over the boundary object.
> But the **link** and the **call** remain distinct constructs,
> because they mean different things: the link asserts
> *self-similarity across levels* — "the same equations hold
> again, one level down" — while the call asserts *sameness across
> sites* — "that remembered computation, here." Recursion never
> routes through a named function; functions per se are about
> reuse.

Three arguments settled it:

- **The register symmetry.** The guard family's other members are
  drawn back-edges, anonymous: a value cycle crosses a register, a
  flow feedback crosses a dedup collect, and neither requires
  naming anything. The running sum did not become "a function" the
  moment its wire tied back. Making the tree back-edge — alone of
  the three — require extracting a named boundary first would
  break the symmetry for nothing.
- **The hidden cliff.** Take one level of mergesort written inline
  in a larger program, and make it recurse. Under
  recursion-as-self-call, the +1 step is extract, name, rewrite
  the site as a call, *then* link — a species change, exactly the
  cliff principle 7 forbids. Under the separation, the +1 step is:
  draw the link. One gesture, purely additive.
- **The conflation has a diagnosable cause.** Conventional
  languages route recursion through the named callable because the
  callable is their *only* abstraction unit — recursion has no
  other door to go through. This language has no such constraint;
  importing the conflation would be adopting a workaround as a
  design.

So mergesort keeps the divide round's drawing — the link is a
gesture on the page, `level of` its spelling, no name in sight:

```
xs -> split singleton? of Base, Divide => s
s.Divide -> splitInHalf => subA, subB
subA -> level of xs => sortedA        -- the link: this, one level down
subB -> level of xs => sortedB
sortedA, sortedB -> mergeSorted => merged
~s.Base:   s.Base
~s.Divide: merged
-~> collect => sorted
```

*Reusing* mergesort is a second, independent act: draw a cut
around the whole thing and name it. Call sites reference the cut;
the link inside is untouched. The two constructs stay
distinguishable at the margins, which is the test that they really
are two:

- **Interfaces.** A function has an interface because callers
  shouldn't read the body; a level has no callers — there is
  nobody to summarize for. And with the separation,
  **recursiveness is an implementation detail**: the link is
  interior to the cone, collapsible like any data chain, so a
  caller cannot tell whether an implementation recurses. (Whether
  *termination* surfaces on the interface as an offered property —
  Flix's `@Terminates` is the prior art — is an open question
  below.)
- **Checking.** A call is checked against a signature; a link's
  problem wires check against the level's own in-wires — the same
  wires, trivially. Self-reference needs no signature matching.
- **Naming.** Renaming a function ripples to call sites; a link
  has no name to rename.

What the substrate shares transfers without restatement, because
the divide round was already phrased boundary-first: per-instance
membership is downstream-of-in-port (one rule, both constructs);
instance contexts nest because a boundary crossing appends a
segment to the context path (`bundle-provenance-design.md`'s
vocabulary, one segment species); a leaf is an alt that fires no
links; laziness runs only the demanded lane's cone. And the divide
round's own dead end 2 — no recursion by self-calling function
*values* — is untouched on both sides: neither a link nor a call
puts anything on a wire.

**Guards on reference cycles (revised 2026-08-12).** A
non-recursive call needs no guard. The family statement survives
in two parts of three: a cycle in value wiring crosses a register,
and productivity is the guard (`iteration-with-state-design.md`);
a cycle in flow feedback crosses a dedup collect, and convergence
is the guard (`saturation-design.md`). The third member — a
measure guarding cycles of boundary references — is retired with
the measure discipline (no termination checking;
`divide-flow-design.md`, revision notes 2026-08-12). Link and call
cycles are legal and unchecked.

**Mutual recursion needs nothing at all (revised 2026-08-12).**
The passage that stood here proposed page-local level labels (the
loop-label precedent) for links naming sibling levels, carrying a
joint measure around the reference cycle. Both the labels and the
measure are gone: mutual recursion reduces by inlining — within a
strongly connected reference group, single-use "calls" are just
wiring (copy-paste), so only the group's back edges are sites —
the reuse residue (both members named and reused from outside) is
two remembered cuts over one node set (this doc's own "any number
of remembered cuts"), and a site's threads anchor at drawn wires,
so nothing needs a name that isn't a wire. See
`divide-flow-design.md`, revision notes 2026-08-12.

## Partial cuts: the locality gradient

Now, you might wonder whether a cut must sever *everything* — or
whether a function can keep reading local values through wires you
chose not to cut. It turns out partial cuts are not a special
feature to be permitted but the general case the round's own rules
already describe, and the "local environment" other languages bolt
on (closures, implicit context, globals) falls out of provenance:

- **An uncut wire is a free wire, and provenance is already the
  theory of free wires.** A call site at context C is legal iff
  every uncut wire's context is a prefix of C — the ordinary
  prefix rule, applied to the call node as to any node. So a
  partial cut yields a **local function**: reusable anywhere at or
  below the join of its uncut wires' contexts. The check that
  polices this is the existing admissibility check, and its
  failure witness is drawable (the uncut wire, the offending call
  site).
- **Local → global is additive.** Widening a local function's
  reach means cutting one more wire, which surfaces it as a port.
  The gradient runs collapsed-view → partial cut → full cut →
  published block, parameterized entirely by how many wires are
  cut; every widening step is a +1 gesture, never a rewrite. This
  also answers a real ergonomic pressure: conventional languages
  force a choice between globals and parameter-threading plague
  (the Allocator-passed-everywhere noise the late-bound round
  absorbed via completion). An uncut config wire is context that
  is *visible but not threaded* — a wire, on screen, with a
  derived validity region.
- **The signature stays honest.** The boundary projection lists
  uncut reads — "this cut also reads these wires, from these
  contexts" — so a call site sees the validity region without
  inspecting the cone.

Ownership was the worry, and it bites in exactly one place:

- **Plain values: no complication.** An uncut value wire is
  evaluated once and shared by every call — the prefix rule's
  normal behavior, the constant-inside-a-nested-loop non-event.
- **State: resolves visibly.** "Fresh per call or persistent?" —
  the static-local ambiguity — dissolves because a register must
  bind a flow, and the drawing shows which: a flow opened *inside*
  the cone gives per-call state; a flow arriving through a port or
  an uncut flow wire gives state persisting along *that flow's*
  firings. This is the late-bound round's "provider state and
  orderedness are the same bit," rederived; no hidden statics are
  expressible.
- **Linear values: the real bite.** An uncut *linear* wire — an
  effect handle, a possessed value — read by a cone with two call
  sites is a fan-out of a linear wire, which is already forbidden.
  So the resolution is not new machinery, but it is a real rule:
  **linearity forces port-ification.** An uncut handle read makes
  a boundary effectively single-call; to reuse it, cut the handle
  into an in/out port pair and thread it — which is precisely the
  `print_string` threading shape, now explained rather than
  exhibited.

One asymmetry: the freedom is input-side only. Uncut side-outputs
of the cone belong to the original instance — the site the cut was
drawn on, which is just the identity binding — while other call
sites read only through out-ports.

Open (filed below): whether uncut reads are simply allowed with
the signature surfacing them (the leaning — it is more inside-out
than parameters-only), or linted toward ports beyond some
visibility distance, since a cone quietly reading a wire from
three contexts up is fine semantically and surprising to a reader.

## The interface: nothing new to design

What does a caller see? The record already contains the whole
answer; this round's contribution is noticing that every piece
attaches to the cut and none needs new mechanism.

- **The signature is the boundary projection.** Run property
  propagation over the cone once, project onto the ports: residual
  demands on in-ports, offers on out-ports, relational links among
  ports — the principal property signature, computed per version,
  memoised by the persistent structure (`types-design.md`, "Reuse
  without one complete type"). Inferred, never written; writable as
  planning.
- **The flow skeleton is the summary at a collapse level.** The
  "flow skeleton with data holes" of `functions-design.md` is
  read-out 2's generalized program displayed at one particular
  level: collapse data chains to holes, keep flow structure. The
  collapse level is a display-time parameter, not a property of the
  boundary — so "interface vs implementation" is not two stored
  artifacts but one cone under two (or any number of) derived
  views. Interface summarization stops being a construct of this
  row and becomes a default the editor picks.
- **Ordering residue projects the same way.** A boundary authored as
  a time-travel program carries residual ordering constraints on its
  ports; canonical rules fire only on freedom the boundary cannot
  see (`time-travel-programs-design.md`, "Reuse" — consumed, not
  changed).
- **Open op pairs are on the interface** because they are ports:
  the caller binds each pair or lets it keep crossing outward.

The load-bearing property, restated from `functions-design.md`
because it is why the skeleton can never collapse to a black box:
flow structure stays visible through the cut. That is what preserves
no-time-travel across calls and lets the checker trace flow
dependencies from caller into callee — the boundary hides *data*
detail, never *flow* obligation.

## Slots dissolve into op pairs

Now, you might wonder about slots — the spec's cut-outs where a
caller supplies a sub-diagram (`visual-language-spec.md`:
SlotSignature, SlotInvocation, slotImplementations), the machinery
configuration scopes were specified with. Doesn't the boundary need
them as a third port species beside values and flows?

It turns out the slot is the op pair, specified before the op pair
existed. Compare the two, piece by piece: a SlotSignature says what
the inserted sub-diagram must offer — that is the facet identity a
binding matches on. A SlotInvocation marks where the caller-supplied
computation runs — that is the use site of an op pair, one exchange
per invocation firing. `slotImplementations` at the call site — that
is binding, `with … = …`. Even the late-bound round's dead end 5
("the operation as a bare value hole") is the same recognition from
the other side: a hole that receives a computation once is the
once-fired special case of the pair that carries exchanges. Multiple
SlotInvocations of one slot are multiple exchanges on one pair;
a slot invoked under a walk is the pair under a walk — cases the
slot machinery would need new rules for and the exchange vocabulary
already owns (ordering by the facet's sequenced/unordered bit,
concurrency by the provider-side collect species, failure by the
response lane's inventory).

So the leaning: **retire the slot as a species; keep the word, if at
all, for the authoring direction** — a slot is an op pair authored
boundary-first (declared before any binding exists), which principle
1 permits as planning. Configuration scopes then sit exactly where
their own doc already placed them: the special case where demand and
binding coincide at one use site, the provider spliced inline
(`configuration-scopes.md`, "Where this pattern sits now").

One honest consequence for the checking row: `types-design.md`'s
open question 3 (slot signatures are conditional signatures — "for
any filler whose output offers P, my output offers Q") does not go
away, but it stops being two questions. The conditional-signature
design is owed once, for the op pair, and slots inherit it by being
op pairs.

## One substrate, three bindings

With the cut in hand, three things the record treated as separate
kinds of program turn out to share the one substrate:

- **A function** is a named cut whose ports are bound at call
  sites. It exists for reuse and only for reuse.
- **A provider** (`late-bound-operations-design.md`,
  `served-flow-design.md`) is a boundary whose facing ports are the
  server ends of exchange pairs; "which one is the server is a
  property of a binding" already said this — the provider diagram
  and the function diagram were never different things.
- **The program** — the top level itself — is a boundary too: the
  node set with distinguished outputs
  (`first-class-ports-design.md`) is a cut whose out-ports are the
  distinguished outputs and whose in-ports are whatever the
  deployment binds (nothing, for a batch computation; the world's
  client end, for a standing server — the served round's
  "registration, not value computation" compile target).

The node-set consequence thus completes: a file's node set carries
any number of remembered cuts over it, one of which the deployment
distinguishes. "Top level" is a binding fact, not a structural one.

(A fourth binding — **a level**, the divide flow's — stood in this
list until 2026-08-12. It is removed: the divide round's "no
boundary at all" refinement makes the recursive "function"
*derived* — whatever is downstream of the link's fed anchors,
exactly as a loop body is whatever is downstream of the uncollect
— and a loop body is not a binding of the cut either. Recursion
rides the port-pair substrate (the site), not the boundary
substrate; see `divide-flow-design.md`, revision notes
2026-08-12.)

## The textual form

No new syntax is proposed; the round's textual content is a change
of *reading* plus one lint.

- `diagram name … in … out … end` survives as the spelling of a
  named cut. But the statement grouping is **organizational, not
  semantic**: it is where the printer chooses to render the cone,
  not a scope. The semantic content is the boundary (name + ports)
  and the derived cone.
- The lint: a statement inside the group whose node is neither in
  the out-ports' cone nor a write half reachable from it is dead —
  same status as any root-unreachable node, reported, legal
  (`program-editing-design.md` permits dangling work in progress).
  Conversely a cone node rendered outside the group is a printer
  choice, not an error; the canonical printer keeps cone and group
  aligned.
- Calls keep the existing chain-stage spelling
  (`5 -> double => ten`), flow ports keep the sigil, multi-port
  calls keep positional-or-named correspondence per the existing
  FunctionCall shape. The link's `level of` spelling is retired
  (2026-08-04, `divide-flow-design.md` open question 1 — the
  replacement uses the thread vocabulary, owed to the textual
  catch-up); mutual recursion needs no labels (dissolved
  2026-08-12 — sites anchor at drawn wires). `op`, `serve`, `with … = …` are
  likewise superseded by the 2026-08-04 revisions (ops dissolve
  into port pairs; `with`-binding rejected —
  `late-bound-operations-design.md`, revision notes). All spellings remain
  provisional and owed to the textual catch-up — but the *decision
  they were waiting on* (what they all reference: the boundary
  substrate, under two constructs) is this round's proposal, so
  the catch-up can proceed once it is adopted.

## Against the philosophy

- **Example first, then generalise.** The construct *is* this
  principle applied to reuse: write the concrete computation, draw
  the cut after, read the ports off the crossings. Declaring the
  boundary first stays available as planning; nothing requires it.
- **Inside-out — no scopes, no magic names.** The cut has no
  interior scope; membership is derived from dataflow (P3 one level
  up), values arrive at every position by visible wires, and outer
  values reach interior nodes by the same prefix rule as everywhere
  else. The one scoped construct in the vicinity — the slot's
  "can only appear within a diagram that defines it" — dissolves
  with the slot.
- **Foundations before features.** The round adds no primitive: one
  substrate carries the instancing, membership, and measure
  machinery of both the call and the link (two constructs, one
  representation), one port story absorbs five, and the slot
  species retires. Almost everything here is recognizing that
  worked rounds had already built the parts.
- **Building blocks at the programmer's abstraction level.** "Make
  this a function" is one gesture (draw the cut); "this computation
  recurses" is drawing the link — no naming toll; "run it against a
  fake" is a binding. Each is the user's own sentence, one stroke
  each.
- **No bottlenecks.** The argument list was the product bottleneck's
  oldest costume; the boundary is a barrier with pairwise crossings,
  so a multi-value call passes each wire as itself, and an algebra
  crosses as per-operation lanes (the late-bound round's
  no-tagged-request rule, inherited).
- **Abstraction is the source of truth.** The authored program keeps
  the call; inlining is a derived view (materialise to edit, a
  recorded step); the interface is a lens at a display-time collapse
  level, never a second stored artifact.
- **Building blocks must build — the +1 ladder.** Two ladders now,
  one per construct, each additive. Reuse: inline code → cut drawn
  (program unchanged plus one named boundary) → second call site
  (one reference) → one more port (one more crossing wire) → a
  binding removed (an op pair opens; callers now bind or
  re-export) → published. Recursion: one level written concretely
  → the site drawn (a second back edge of the group for mutuality
  — labels and measures both retired, 2026-08-12) — and the two
  ladders compose without
  touching each other: a cut around a cone containing a link is a
  recursive reusable function, callers none the wiser. No rung
  rewrites the program in a different vocabulary; the cliff
  conventional languages put between "expression," "function,"
  "recursive function," and "interface" is rungs of these ladders
  — and the first draft's own extract-to-recurse cliff was removed
  by the un-merge.
- **Sample reality.** This round is a unification, and its demand
  evidence is inherited rather than fresh: naming-at-scale
  (`raku-grammars-comparison.md`), four of nine Effekt case studies
  (`effekt-comparison.md`, finding 1), the served flow's
  provider-diagram need. What is *not* yet measured is the shape of
  real function populations — how often functions are called once
  (organization only) vs at many sites, how often recursive, how
  often effectively parameterised by behavior. Functions are a
  sampleable unit by the standing method's own note; filed below as
  evidence owed rather than assumed.

## What it means — the ontology check

Can each construct be said in one sentence? *A function is a
remembered cut: a named correspondence of ports whose computation is
the derived cone between them; calling rebinds the crossings, and
the cut — not any node set — is what has identity.* And the link,
over the same substrate, is a different sentence: *an assertion
that this page's equations hold again, one level down.* The tell
that the ontology is doing work rather than paraphrasing: it
selected answers where results alone did not force them. Membership
had two candidate readings (authored set vs derived cone) that
agree on complete well-formed programs and disagree on the
constant-above-the-cut — the cut ontology picks shared-once, which
is also what the implemented compiler already does. The call and
the link compute identically wherever both are drawable, yet mean
different things — sameness across sites vs self-similarity across
levels — and the meaning selected real behavior: what has an
interface (callers exist for a cut, not for a level), what naming
is for (reuse, never a toll on recursion), and where the +1
gestures land (a link is drawn, not declared). This is the standing
lens's textbook case: the first draft merged the two on identical
mechanics, and the design conversation pulled them apart on
meaning. And identity-by-boundary (rather than by node set) is what
lets a boundary's implementation be edited under callers — the
transformation-levels question of which edits preserve the cut is
real and open, but it is *stateable* only because the cut, not the
cone, carries the identity.

## Dead ends

Recorded in place, each with the reason it should not be
re-proposed.

1. **The diagram as a scope/container.** Walls around the cone —
   private names, capture machinery, interior meaning differing from
   exterior. Rejected by the inside-out principle and P3; membership
   is derived, and every capability walls would provide (privacy of
   detail, per-call freshness) is already supplied by derived views
   and per-firing minting respectively. (Settled by this round,
   pending adoption.)
2. **Recursion routed through a named function — the full
   call/link merge.** This round's own first draft: one node
   species, recursion as calling your own name. Rejected in the
   round's first design conversation (2026-07-22), for three
   reasons recorded in "One substrate, two constructs": it breaks
   the guard family's symmetry (registers and dedup collects are
   anonymous drawn back-edges; only this member would demand a
   name); it makes naming an obligation rather than a reuse
   gesture (structure upfront); and it hides a cliff — an inline
   level cannot recurse without first being extracted, named, and
   its site rewritten as a call. What survives is the *substrate*
   merge: one boundary object carries instancing, membership, and
   the measure for both constructs, so nothing is specified twice.
   (Settled by that conversation.)
3. **The slot as its own species.** Subsumed by the op pair — see
   "Slots dissolve into op pairs." Kept only as a word for
   boundary-first authoring, if kept at all. (Leaning, this round;
   spec reconciliation owed.)
4. **The obligatory declared signature.** Requiring ports/types
   declared before the body exists — rejected by example-first;
   the boundary projection and accumulate-demands machinery exist
   precisely so the interface can be read off the concrete program.
   Declared-first survives as optional planning. (Settled by
   principle 1; restated here because this doc now owns the
   construct.)
5. **First-class functions / closures.** Not re-argued: the settled
   rejection stands (`configuration-scopes.md`,
   `functions-design.md`), and this round strengthens its
   load-bearing wall — with no scope anywhere, there is nothing a
   closure could close over; the capability's remaining uses are
   owned by op pairs (behavior parameterisation) and the link
   (recursion).
6. **The argument list as a value.** Packing a call's inputs into a
   tuple/record to cross the boundary — the product bottleneck;
   rejected by principle 5. Genuine record values remain fine as
   data; the bottleneck is packing *merely to cross the cut*.
   (Settled by principle 5; stated here because calls are where
   every conventional language does it.)

## Revision notes (2026-08-04): node sets, copy-paste, and flow ports

A design conversation re-examined the boundary and settled six
things. The cut ontology survives; its geometry does not.

**The cut is a node set, not a closed curve.** A closed curve
cannot distinguish "crosses and becomes a port" from "used inside
but not a port" — every wire used from outside crosses. The honest
formalization: a sub-diagram is a **set of nodes**, and each wire
with one endpoint inside and one outside is either **cut**
(severed — a port) or **left intact** (environment). An
environment wire stays a literal wire to the one shared
definition, fanning out to every instance — the closure
environment with no capture machinery, as before. The curve
survives as an editor gesture only: cut wires get a port mark
where they meet it, environment wires pass through unmarked.
Partial cuts' "uncut wires are free wires" stated this fact
locally; it is now the general form. One consequence: the
freeze-vs-redo choice on each boundary wire (caller supplies per
call vs all calls share the one value) is a stated per-wire
decision, not something read off curve placement.

**Copy-paste semantics.** Using a sub-diagram has exactly the
behavior of pasting its node set. No interface memory: a severed
wire's flow context is *not* remembered as part of the diagram;
each instance re-derives contexts and kinds from what its caller
wires; Complete completes per instance (a Cross inserted at one
call site and not another is what hand-pasting would produce);
witnesses anchor at the instance they arise in. This is the
use-case account cashing out: sub-diagrams exist for reuse, not
flow control, so their semantics is substitution.

**Flow ports, and the drawn call-by-name.** A flow wire is
typically not incident to an extracted interior (per-firing-ness
rides in on severed value wires' contexts) — but incidence is
editable: insert a no-op identity on the flow wire, include it,
and the flow wire can be severed into a flow in-port and flow
out-port. A pure pass-through is useless; flow ports earn their
place when the diagram **operates on control flow**: e.g., take in
two IO operations as flow wires (the effects round's IO-as-flow),
case-split on data, and emit the chosen operation's flow. Values
are pure — call-by-value; wanting the diagram to manage whether
and when something runs is drawn — a flow port, call-by-name. The
language never chooses a default between them; the distinction is
wiring. Two notes filed from the example: the **flow-level case
selection** it assumes (choose a flow by a data condition, as race
chooses by time — the partial collect's selection lifted to flow
level) is an owed construct, not designed here; and flow in-ports
sit close to the late-bound op pair — plausibly two views of one
substrate, which the slot/op-pair provisional marker's "later
look" should take up.

**Containment is derivable, never expressed.** There is no
vocabulary for "this value port is contained in that flow port,"
deliberately: in any use, containment is derived from the pasted
interior by ordinary context derivation — the wiring either
requires it or it doesn't. The interface-as-poset (ports plus
containment order) exists only as a derived view.

**Generic flow ports are free under copy-paste.** A port the
interior doesn't constrain is generic by absence — template-style
monomorphic instantiation per use, no quantification vocabulary.
(The Koka-row analogy lands on context *segments* — paths in the
poset — if a declared form is ever needed; nothing is declared
now.)

**Checking posture: per-instance, with sound-but-partial isolation
checking.** The passes are pure functions over node sets, and a
sub-diagram is a node set: run Check on the interior with
environment wires resolved and ports treated as unconstrained
unknowns. Every witness found under those assumptions is
*universal* — it appears in every instance — so reporting it at
the diagram is always honest; instance-dependent clashes surface
at instances, the late-witness cost copy-paste accepts. The
further step — rendering the **contract** a diagram's wiring
imposes on its users (project the propagation to the ports:
per-port demands and offers, plus the derived containment order;
genericity as absence of demands) — is types-as-summaries
territory: a derived, never-authored view, deferred to its own
round.

**Addendum (2026-08-04, later in the same conversation series):**
the "later look" the slot/op-pair provisional marker anticipated
has happened — ops dissolve into ordinary port pairs
(`late-bound-operations-design.md`, revision notes 2026-08-04:
`with`-binding rejected; the exchange correspondence derived under
copy-paste; the flow-use marking the one stated exception). The
same round added the **abstract wire** annotation (`out p ... in
q`, provisional — an authored expectation over a derivable
constraint, earning layout and the `-~>` shorthand) and the
**C-shape** rendering: an out port upstream of an in port draws as
a cutout, and a custom flow is a C-shaped sub-diagram used
flow-wise.

## Open questions

The language hasn't decided any of these.

1. **The adoption conversation.** Closed — it happened: the
   status header records the joint adoption (2026-07-23, with the
   divide flow, late-bound operations, and the served two-ends
   core). Kept as a numbered entry only so cross-references to
   "open question 1" still resolve.
2. **The cut's edit gestures.** Drawing a cut on an existing
   program, moving a wire across it (port added/removed), merging
   and splitting boundaries — each must be an atomic
   validity-preserving edit in `program-editing-design.md`'s
   vocabulary, with the reusability check's witness surfacing
   in-place. Owned by the editing round.
3. **Boundary identity across versions.** Which edits preserve the
   cut's identity (so call sites follow) vs mint a new boundary —
   port renames, port additions with defaults, cone rewrites. This
   is transformation-levels territory (the step-DAG already owns
   versioned identity); flagged there rather than worked here. The
   time-travel doc's boundary-residue question (its question 5)
   rides along.
4. **The conditional signature.** A boundary carrying open op pairs
   has a signature conditional on its bindings — `types-design.md`
   question 3, now owed once (for the pair) instead of twice. Still
   needs its own design round; unblocked, not advanced, by this one.
5. **Region-scoped rebinding.** The late-bound round's question 2 —
   bind a *region* of one diagram against a different provider. The
   cut vocabulary suggests a shape (a region is an anonymous
   interior cut; rebinding is a binding at it), but the interaction
   with the facet's one-handle ordering commitment is unworked and
   stays with that round.
6. **The joint measure's fine print.** Retired with the measure
   discipline (2026-08-12) — no termination checking
   (`divide-flow-design.md`, revision notes).
7. **Level labels.** Dissolved (2026-08-12): mutual recursion
   reduces by inlining and sites anchor at drawn wires, so no
   label vocabulary exists (`divide-flow-design.md`, revision
   notes).
8. **Termination on the interface.** Retired with the measure
   discipline (2026-08-12): there is no termination checking, so
   no "terminates" property to offer.
9. **The uncut-read lint.** Whether uncut reads are simply allowed
   with the signature surfacing them (the leaning — more
   inside-out than parameters-only), or linted toward ports beyond
   some visibility distance. A UI-policy-flavored question, but the
   threshold's existence is a language decision.
10. **Spec bookkeeping.** The Diagram record's reconciliation:
    ports as crossings (one list, sorted, directed), slots removed
    in favour of op-pair ports, the call and the link as two
    references to one boundary substrate, membership's `nodes`
    field re-read as organizational (still needed for partial
    programs and rendering). Owed to `visual-language-spec.md` and
    `first-class-ports-design.md`'s migration plan when this round
    is adopted.
11. **Evidence.** The function-unit sample: draw real functions
    (the standing method names them sampleable) and classify —
    call-site counts (once vs many — the once-only share measures
    how much conventional function-writing is organization, i.e.
    views here), recursion (self, mutual, none), behavior
    parameters (would be op pairs), flow threading (would be flow
    ports), capture patterns (would be uncut reads, classified by
    visibility distance for question 9). This measures what the
    boundary's ergonomics must make effortless and carries the
    functions row's existing W-condition (does application code
    swap providers?) alongside.

## What this doesn't address

- **Extensible alternation, the decorated tree, the `across`-style
  authoring gesture** — the functions row's remaining members,
  untouched.
- **Facets' attachment representation** — the facet remains the
  grouping identity for op pairs (consumed from the late-bound
  round); how facets attach to boundaries generally is
  `facets-design-notes.md` open edge 3, unworked.
- **Compile.** The obvious form is one emitted function per
  boundary (in-ports as parameters, out-ports as returns, shared
  cone hoisted — which the Lit memoisation already does in
  miniature); levels take the divide round's
  one-named-recursive-function form — the emitted JS naming a
  function for an unnamed link is lowering, not construct. Decide
  in code (`compile-strategy-design.md`).
- **The graphical rendering of a cut** — out of scope in this repo,
  as ever.
