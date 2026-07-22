# The function boundary: a cut, not a container

Status: exploration — a worked proposal with leanings, prepared for a
design conversation and *not* adopted. This is the round three worked
rounds jointly demanded ("one decision, three clients"): the divide
flow needs the **level boundary** as its link's anchor
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

The one-sentence result, stated up front so the rest can argue for
it: **a function is not a container of nodes but a remembered cut
through the wiring — a named correspondence of ports — and
everything else about functions (what a call is, what recursion is,
what is per-call and what is shared, what the interface shows, where
an `op` pair lives) is derived from the cut rather than declared
beside it.**

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

## What a call is: the link's non-cyclic case

The divide flow defined its link as "a node with input ports
corresponding pairwise to the problem wires and output ports
corresponding pairwise to the level's answer wires," each firing
minting an instance (`divide-flow-design.md`, "The link"). Read that
sentence against the boundary just built: it *is* a call. Problem
wires are in-ports; answer wires are out-ports; the pairwise
correspondence is the cut's crossing list.

This round therefore proposes the unification the divide flow's open
question 1 asked for:

> **A call and the link are one node species: a reference to a
> boundary, with wires bound pairwise to its ports. The divide flow
> is what that species does when the reference cycle is nonempty.**

Concretely, mergesort loses its provisional `level of` spelling and
recursion becomes calling your own name:

```
diagram mergesort
  in xs
  xs -> split singleton? of Base, Divide => s
  s.Divide -> splitInHalf => subA, subB
  subA -> mergesort => sortedA        -- the link: a call of this boundary
  subB -> mergesort => sortedB
  sortedA, sortedB -> mergeSorted => merged
  ~s.Base:   s.Base
  ~s.Divide: merged
  -~> collect => sorted
  out sorted = sorted
end
```

Everything the divide round worked transfers without restatement,
because it was already phrased boundary-first: per-instance
membership is downstream-of-in-port (identical rule, now shared);
instance contexts nest because a boundary crossing appends a segment
to the context path (`bundle-provenance-design.md`'s vocabulary,
one segment species for call and link alike); a leaf is an alt that
fires no calls; laziness runs only the demanded lane's cone.

Three distinctions keep the unification honest:

- **This is not dead end 2 returning.** The divide round rejected
  "recursion by self-calling function *values*" — the fixpoint
  combinator, a callable on a wire. A call here references a
  boundary *by identity*, the way the write half references its read
  half: structural, drawn, nothing on any wire. The settled
  first-class-function rejection is untouched.
- **`level of` survives as the anonymous form.** A one-off recursive
  level nobody will reuse doesn't need a name; `level of xs` is a
  call whose boundary is the enclosing cut itself, referenced
  deictically. Named and anonymous are one species, as with every
  other construct that has an inline and an extracted form.
- **The measure discipline attaches to cycles, not to calls.** A
  non-recursive call needs no measure. The check is on the *call
  graph*: every cycle of boundary references must carry a measure
  (shrink, progress, or fuel — the divide round's three species,
  unchanged). This is the third member of a family the record built
  one at a time and can now state as one sentence:

> **Every cycle crosses a guard.** A cycle in value wiring crosses a
> register, and productivity is the guard
> (`iteration-with-state-design.md`). A cycle in flow feedback
> crosses a dedup collect, and convergence is the guard
> (`saturation-design.md`). A cycle in boundary references crosses a
> measure, and descent is the guard (`divide-flow-design.md`). Same
> shape three times: the back-edge is a drawn node, and the guard is
> structural.

**Mutual recursion** (divide open question 2) becomes stateable, and
its easy half falls out. Two boundaries referencing each other are
simply a call-graph cycle of length two:

```
diagram expr                          -- expression grammar
  in pos
  pos -> parseTerm => t1              -- call into the sibling boundary
  t1.rest -> match("+") of Yes, No => m
  m.Yes -> expr => t2                 -- and back into this one
  …
end

diagram parseTerm
  in pos
  pos -> match("(") of Paren, Atom => p
  p.Paren -> expr => inner            -- the mutual reference
  …
end
```

The cycle `expr → parseTerm → expr` must carry a joint measure —
here progress (the cursor strictly advances somewhere on every trip
around the cycle), which is exactly the check whose violation is
left recursion. What this round does *not* work: the joint measure's
fine print (which edges of the cycle must advance, how the check
composes when cycles share edges). That stays with the divide row,
now unblocked by having a construct to state it over.

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

## One species, four costumes

With the cut in hand, four things the record treated as separate
kinds of program turn out to be one species wearing different
bindings:

- **A function** is a named boundary whose ports are mostly bound at
  call sites.
- **A level** (the divide flow's) is a boundary in a reference
  cycle, its calls carrying a measure.
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
  FunctionCall shape. The link spelling becomes the call spelling;
  `level of` remains for the anonymous self-reference. `op`,
  `serve`, `with … = …` are unchanged from the late-bound round.
  All spellings remain provisional and owed to the textual catch-up
  — but the *decision they were waiting on* (what they all
  reference: a boundary, one species) is this round's proposal, so
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
  node species (the boundary reference) absorbs two provisional ones
  (the call, the link), one port story absorbs five, and the slot
  species retires. Almost everything here is recognizing that
  worked rounds had already built the parts.
- **Building blocks at the programmer's abstraction level.** "Make
  this a function" is one gesture (draw the cut); "this function
  recurses" is calling its own name; "run it against a fake" is a
  binding. Each is the user's own sentence, one stroke each.
- **No bottlenecks.** The argument list was the product bottleneck's
  oldest costume; the boundary is a barrier with pairwise crossings,
  so a multi-value call passes each wire as itself, and an algebra
  crosses as per-operation lanes (the late-bound round's
  no-tagged-request rule, inherited).
- **Abstraction is the source of truth.** The authored program keeps
  the call; inlining is a derived view (materialise to edit, a
  recorded step); the interface is a lens at a display-time collapse
  level, never a second stored artifact.
- **Building blocks must build — the +1 ladder.** Inline code → cut
  drawn (program unchanged plus one named boundary) → second call
  site (one reference) → one more port (one more crossing wire) →
  a binding removed (an op pair opens; callers now bind or
  re-export) → self-reference (recursion: same call node plus a
  measure) → a second boundary in the cycle (mutual recursion). No
  rung rewrites the program in a different vocabulary; the cliff
  conventional languages put between "expression," "function,"
  "recursive function," and "interface" is four rungs of one
  ladder.
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

Can the construct be said in one sentence? *A function is a
remembered cut: a named correspondence of ports whose computation is
the derived cone between them; calling rebinds the crossings, and
the cut — not any node set — is what has identity.* The tell that
this is the right ontology rather than a paraphrase: it selected
answers where results alone did not force them. Membership had two
candidate readings (authored set vs derived cone) that agree on
complete well-formed programs and disagree on the constant-above-
the-cut — the cut ontology picks shared-once, which is also what the
implemented compiler already does. The call/link identity had two
readings (two species with similar ports vs one) that compute
identically on non-recursive programs — the cut ontology picks one
species, which is what makes mutual recursion stateable at all. And
identity-by-boundary (rather than by node set) is what lets a
boundary's implementation be edited under callers — the
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
2. **Two boundary species — function vs level.** The divide flow's
   level boundary and the function boundary, kept separate because
   one recurses. Dissolved: recursion is a property of the reference
   graph (a cycle), not of the boundary; splitting the species would
   make "this function now recurses" a rewrite across a species
   line, violating graceful expansion. (Dissolution, this round.)
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
   owned by op pairs (behavior parameterisation) and boundary
   references (recursion).
6. **The argument list as a value.** Packing a call's inputs into a
   tuple/record to cross the boundary — the product bottleneck;
   rejected by principle 5. Genuine record values remain fine as
   data; the bottleneck is packing *merely to cross the cut*.
   (Settled by principle 5; stated here because calls are where
   every conventional language does it.)

## Open questions

The language hasn't decided any of these.

1. **The adoption conversation.** Joint, as the clients required:
   with the divide flow's round (the link is a call), the late-bound
   round (op pairs are ports of a cut; the spelling family), and the
   textual catch-up (one reference form). The served round's
   adoption conversation already declared itself joint with the
   late-bound one; this round joins the same table.
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
6. **The joint measure's fine print.** Mutual recursion's check —
   which edges of a call cycle must advance, composition when cycles
   share edges, what the diagnostic names — stays with the divide
   row (its questions 2 and 5), now stateable over call-graph
   cycles.
7. **Spec bookkeeping.** The Diagram record's reconciliation: ports
   as crossings (one list, sorted, directed), slots removed in
   favour of op-pair ports, FunctionCall and the link as one node
   species, membership's `nodes` field re-read as organizational
   (still needed for partial programs and rendering). Owed to
   `visual-language-spec.md` and `first-class-ports-design.md`'s
   migration plan when this round is adopted.
8. **Evidence.** The function-unit sample: draw real functions (the
   standing method names them sampleable) and classify — call-site
   counts (once vs many), recursion (self, mutual, none), behavior
   parameters (would be op pairs), flow threading (would be flow
   ports), capture patterns (would be prefix reads). This measures
   what the boundary's ergonomics must make effortless and carries
   the functions row's existing W-condition (does application code
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
  miniature); recursive boundaries take the divide round's
  one-named-recursive-function form. Decide in code
  (`compile-strategy-design.md`).
- **The graphical rendering of a cut** — out of scope in this repo,
  as ever.
