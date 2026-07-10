# Learning from other languages: Flix

*Comparison round, 2026-07-10. Third execution of the genre begun
with `effekt-comparison.md` and continued in
`raku-grammars-comparison.md`: read another language's programs
against how the record approaches the same problems, extract
problems — never mechanisms — and reweight `open-problems.md`.
**This round decides nothing**; demands are handed to owning docs,
design stays in the design conversations.*

*Corpus: the Flix language's own example suite (github.com/flix/flix,
`examples/`) — roughly 190 programs, read in full for the distinctive
sections (datalog, concurrency-and-parallelism, restrictable
variants, the effects-and-handlers ecosystem, functional/imperative
style, records, traits, structs, tail-recursion) and representatively
for the repetitive ones (the per-effect koan files) — plus the three
small applications (`apps/`: weather, tic-tac-toe, langcensus) and
the static-analysis programs (IFDS and the lattice domains).*

## Reading rules for this genre

The three standing cautions, with their directions, plus two
specific to this corpus:

1. **What's out there is already out there.** The output is
   problems — programs that must be writable, demands with evidence
   — never mechanisms. Duplicating Flix would produce Flix, which
   exists and is good at being Flix.
2. **Different core; bolting on clashes.** Flix's premise is
   actually *shared* with ours — the context a computation runs in
   (its effects, its mutation, its dependencies) should be explicit
   and checkable rather than ambient — but its mechanism is types
   where ours is drawn structure, and its loops are recursion where
   ours are uncollect/collect. Where their approach is stronger, the
   question is what the drawn, inside-out form of the same
   capability is, not how to graft theirs. The clash record is
   finding 8.
3. **Maturity polish.** This is the language authors' own example
   suite: curated, chosen to flatter the mechanisms. Frequencies
   here mean nothing.
4. **Mixed curation levels.** Unlike Effekt's nine literate case
   studies, this corpus spans koan-style single-feature files, ported
   benchmark programs (Souffle's topsort and 2-sat), and three small
   but real applications whose *incidental* code — the folds and
   merges nobody was showcasing — is the closest this genre has yet
   come to field style. Sightings from the apps are noted as such;
   they still do not count as random-sample evidence.
5. **Flix is a combination language.** Effekt was one move applied
   nine ways; Flix is deliberately several orthogonal mechanisms
   (purity-tracking effect types, an effect-handler ecosystem,
   first-class Datalog, channels and processes, regions, traits,
   extensible records, restrictable variants). The round reads each
   against the record separately rather than forcing one center.

## Flix's moves, in two paragraphs

A pure functional core where every function type carries its effect
set (`Int32 -> Int32 \ IO`; pure is the default and spelled `\ {}`),
with higher-order functions optionally demanding purity or being
effect-polymorphic (`\ ef` flows the argument's effects to the
result). On top of that, algebraic effects and handlers — but grown
past Effekt's technique stage into a *standard-library ecosystem*:
`FileSystem`, `Http`, `Sleep`, `Logger`, `Console` and friends are
stdlib effects, each shipping a default real handler
(`runWithIO`), stdlib test doubles (`withInMemoryFS`,
`withSleepNoOp`), and a family of stdlib **middleware** — `withRetry`,
`withCircuitBreaker`, `withRateLimiting`, `withBaseUrl`, `withDryRun`,
`withReadOnly`, `withChroot`, `withAtomicWrite`, `withBackup`,
`withMaxSleep`, `withJitter`, `withLogging` — cross-cutting policies
interposed between a program and its providers, composable by
stacking `with` clauses at the edge. Mutation is scoped by
**regions** (`region rc { ... }`): a function may allocate and mutate
freely inside and still be pure outside, with escape checked in
types. Concurrency is Go-shaped — `spawn e @ rc` (thread lifetime
bounded by the region), channels, `select` with timeout channels and
default arms — plus `par ... yield` fork-join for pure parallelism.

The most distinctive claim: **first-class Datalog**. A `#{ ... }`
constraint set is an ordinary value — composed with `<+>`, built by
recursive functions, returned, stored — with `inject` turning
collections into facts and `query ... select` turning fixpoints back
into vectors. Rules may carry guards calling (pure) Flix functions,
stratified negation, and *lattice semantics*: `Dist(x; d)` merges
duplicate keys by least-upper-bound instead of accumulating tuples,
so shortest-distance is two rules. `pquery ... with {Edge}` is a
provenance query: not "what is derivable" but *why* — the witness
facts behind a derived fact, used by the train-schedule example to
print an itinerary and by dependency-resolution to print the chain
that pulled in a broken package. Finally, restrictable variants index
an enum by the *set of cases possibly present*, and `choose` narrows
and transforms that set through a program.

## The examples, against the record

### 1. Datalog — closure under rules, the corpus's sharpest gap

**Their approach.** Graph reachability is three lines: seed fact,
step rule, query. Transitive closure, cycle detection, topological
sort, 2-SAT, class-hierarchy and taint analyses are all the same
shape. With lattices, shortest-distance is `Dist(src; Down(0))` plus
`Dist(y; d + Down(w)) :- Dist(x; d), Edge(x, w, y)` — the min-merge
is the lattice's job. Delivery-date runs the same pattern over a
parts hierarchy. Dependency-resolution adds stratified negation
(`Missing` = required but `not Satisfied`) and provenance for the
"why was this needed" chain. And ford-fulkerson shows the layers
interleaved per-iteration, not just at program edges: a functional
driver loop (find augmenting path → update flows → recurse) whose
expensive step is a fresh Datalog fixpoint each round, over a
path-carrying lattice.

**Our approach.** Take a rule body apart and most of it is drawn
vocabulary we already have. `Path(x, y), Edge(y, z)` over fact sets
is two uncollects; the shared variable `y` is a constraint between
their value ports (Flix spells the constraint by *name coincidence*
inside the braces — the drawn form is a wire, or a keyed match; see
the clash record); the head is a map to a tuple; the collect target
is a set (dedup — the collect family's territory). One *round* of
rule application is a program we can draw today.

What nothing in the record owns is the **feedback**: the collected
output of the round is also the opened input of the next, iterated
until nothing new appears. This is not the register. The register
(`iteration-with-state-design.md`) feeds a *value* back along one
walk whose extent is fixed by the opened data; here the *extent of
iteration itself* is fed back — firings mint future firings, and
termination is "the set stopped growing." End-when supplies the
reading ("stop when no change") but not the construct. The
imperative encoding is the frontier/worklist loop — seed, pop,
derive, test-against-seen, push — and it is the same diagnosis the
record has made three times before (the flag was end-when's
terminator, the count was a boundary, the state machine was a phase
structure): **the seen-set and the queue are the assembly language
of a saturation the programmer states declaratively.** Flix's whole
Datalog story is the demonstration that the declarative statement is
enough — and its `genEdges`/ford-fulkerson examples show the
fixpoint block composing with ordinary code per-call, not as a
separate language stage.

Two attachments to the same gap. The lattice variant is a **keyed
collect whose collisions merge by an operator with laws** — the
operator-identity question the record already carries (three
hand-rolled monoid folds in the surveys; the collect family's
spelling round) reappears here as the center of a paradigm:
shortest-distance *is* keyed-min-collect plus feedback, nothing
else. And provenance: `pquery`'s "why is this fact in the fixpoint,"
answered with witness facts, is squarely our instinct set —
drawable witnesses (`types-design.md`), derivation free and
downward (principle 6) — surfacing at runtime: whatever owns
saturation should answer what an *explanation* of a fixpoint member
looks like (presumably a highlighted subgraph of the firings that
derived it). Neither Effekt nor Raku raised this; it is the round's
most novel scope item.

Relation to prior rounds: the Effekt build system (its finding 4)
is the *top-down, demand-driven* dual of this bottom-up saturation —
`need(key)` recursion discovering a dependency graph downward, rules
saturating a relation upward. Both are keyed computation over a
graph discovered at runtime. The two demands should be worked aware
of each other.

Field-evidence honesty: no closure/saturation shape was drawn in
the three random surveys (sixty loops, thirty orchestration sites) —
the "worklist" sightings there (textwrap, the CSS tokenizer) are
variable-rate consumption, a different animal. The everyday clients
are domain-concentrated: package/build/import tooling, program
analysis, graph features inside products. By the 80/20 rule that
makes this a breadth obligation, not an effortlessness demand —
W 3, not 5 — and the frequency question is a sample-reality hook
(finding 1).

### 2. The effect ecosystem — providers, doubles, and the policy layer

**Their approach.** Three layers, all stdlib. *Providers*: every
IO-ish capability is an effect with a default handler; the weather
app's `main` is a computation under a six-provider stack
(`with Weather.weatherWithHttpAndFile with Location.locationWithHttp
with Display.displayWithIO with HttpWithResult.runWithIO ...`) — the
application is assembled at the edge, and each module is written
against operations it does not implement. *Doubles*: the in-memory
filesystem, the no-op sleep, assert-to-logger — swapping a test
double is one `with` line, and the doubles ship in the standard
library. *Middleware*: the operation boundary is where cross-cutting
policy lives — retry strategies (linear, exponential,
transport-only), circuit breaker, rate limiting, base-url and
default-headers rewriting, dry-run, read-only, chroot, backup,
atomic-write, sleep caps, jitter, logging — each a handler that
intercepts, transforms, and re-raises, composed by stacking, with
stack order meaningful (`withCircuitBreaker` outside `withBaseUrl`
behaves differently than inside). There are also effect
*hierarchies*: leaf effects (`FileExists`) run into parent effects
(`FileTest`), so a consumer can demand the narrowest capability it
needs.

**Our approach.** This is the third independent language whose
center of mass lands on late-bound operations — after Effekt's
handlers and Raku's action classes — and the second demand (the test
double, Effekt finding 2) now has its strongest witness yet: not a
six-line technique but *standard-library furniture*, which is what
"a language for beginners cannot lack this" looks like when a
language acts on it. What this corpus adds that the prior two rounds
did not have is the **policy layer**: operational concerns (retry,
throttle, sandbox, atomicity, audit) written once, attached at the
boundary, composed by stacking. In the record's leaning — an unbound
operation is a request/response port pair on the diagram boundary,
binding is wiring a provider on (Effekt finding 1) — a middleware is
a **sub-diagram spliced into the provider wiring**: requests flow
through it on their way to the provider, responses on the way back.
That is interposition *by drawing*, and it turns the stack-order
sensitivity — which in handler-land is invisible-wire territory the
Effekt round flagged — into visible nesting: which policy wraps
which is simply where the splice sits. Structurally we should be
*better* at this than text languages; the demand goes to the
functions/reuse/facets row alongside late-bound operations.

One dependency worth naming: the retry middleware is
sleep-between-attempts — **pacing**, the concurrency row's named
semantic hole (`translation-exercise.md` finding 3). The policy
vocabulary is blocked on it; a fourth sighting, this time as stdlib
vocabulary rather than field code.

### 3. Purity and effect polymorphism — the typed mirror of drawn effects

**Their approach.** Purity is the default and tracked everywhere;
`twice(f: Int32 -> Int32)` *rejects* an impure argument at compile
time; `twice3(f: Int32 -> Int32 \ ef): Int32 \ ef` works for both
and its effect is its argument's. Trait instances vary effects: the
`Dividable` trait has an associated effect, empty for `Float64`,
`DivByZero` for `Int32` — same interface, one implementation
failable, one not. Datalog guards and many library positions
*require* purity.

**Our approach.** The mirror image, once again (Effekt finding 5
was the sequential/concurrent mirror; this is the purity mirror).
For us purity is not an annotation but an *absence you can see*: a
sub-diagram with no effect wiring is pure, and there is nothing to
infer. The two demands this hands the record: (a) **the function
boundary must pass a filler's effect and failability wires through
visibly** — effect polymorphism is structural for us (a hole whose
boundary lets whatever wires the filler has flow through), and the
associated-effect example is per-provider failability, which
propagate-by-default failability already leans toward (confirmation
for `async-flow-design.md`'s uniform-dimension stance); (b) **"this
hole demands a pure filler" is a demand** in the demands/offers
vocabulary (`types-design.md`) — Flix is evidence that requiring
purity at specific positions is everyday, useful vocabulary, not
type-system exotica. And the standing confirmation: every Flix
example freely interleaves `println` and `Ref.put` mid-computation
— the same outside witness Effekt gave that the Tier-1 IO/effects
hole gates ordinary programs.

### 4. Channels, select, spawn, par — the concurrency row, confirmed piecewise

**Their approach.** `select { case m <- recv(r1) => ...; case m <-
recv(r2) => ... }` races receivers; a timeout is not special — 
`Channel.timeout(5, Milliseconds)` returns an ordinary receiver you
select against; a default arm makes the select non-blocking (poll).
`spawn e @ rc` binds thread lifetime to the drawn region scope.
`par (x <- e1; y <- e2) yield (x, y)` is annotation-explicit
fork-join; `parMap` recurses it over a list. Long-lived producers
(`mooo`, `meow`) are recursive send loops.

**Our approach.** Mostly confirmations, each worth a line because
they land on specific open items. Select-with-cases is the race
barrier with drawn contenders, and timeout-as-ordinary-contender is
exactly `race-barrier-design.md`'s derived timeout — outside
witness. The **default arm** is a variant that round's derived
vocabulary hasn't named: a poll is a race with one
immediately-settled contender that loses every tie (under the drawn-
order tie law, a default arm is well-defined for free) — handed to
the race round as a small scope item. `spawn @ region` is
scope-bound task lifetime as a mainstream default — a confirmation
for the cancellation half of the Tier-1 row and the concurrent
collect's lifecycle outputs (survey 3 measured the demand; Flix
shows a language building the bound in). `par yield` is the mirror
confirmation again: they annotate to get the fork-join our DAG gives
for free (their `parSum` is, for us, just the drawing). And the
recursive channel producers are self-driven sources — the **third
outside witness** (after Effekt's generator and the translation
exercise's finding 3) that the missing source opener blocks the
canonical producer program. Channels-and-processes as an
architecture is the served flow / server-program question, still
unworked; nothing new to say beyond the sighting.

### 5. Restrictable variants — case sets in types vs bundles in structure

**Their approach.** An enum indexed by the set of cases possibly
present. `choose` requires only the cases that can occur (`eval`
omits `Var` because its input type subtracts it); `choose*` tracks
the *output* set, so `simplify: Exp[s] -> Exp[... rvsub <Exp.Xor>
...]` proves Xor is gone, `subst` proves Var became Cst, and the
composition `simplify >> subst >> fasteval` type-checks against
`fasteval`'s narrowed input. The Seq example makes one type serve as
Option/List/NonEmptyList by index (`head` demands `rvsub <Seq.Nil>`).
The cost is visible in the same file: `zip`'s result index is a
three-way Boolean expression over `rvadd`/`rvand` that takes longer
to read than the function.

**Our approach.** For one level of case structure, the drawn
program *carries this information structurally*: opening a
case-typed value yields a bundle; the alts a consumer engages are
exactly the wired ones; a partial collect is partial by drawing
(`partial-collect-design.md` — their case-omitting `choose` is our
partial engagement, confirmed); and "only Red or Blue reaches here"
is readable off the wiring, no index algebra needed. Where they are
genuinely ahead is **recursion**: `simplify` tracks the case set of
every node of a *tree*, through construction, and our bundles speak
only of the flow level being opened — recursive shape properties
are the checking row's question 2, explicitly waiting on the tree
constructs. Restrictable variants are the strongest prior art yet
that (a) recursive case-set properties are trackable and pay for
themselves (eval-without-Var is the payoff), and (b) the algebra
gets illegible at scale (`zip`) — which supports the checking row's
drawable-witnesses stance over imported index algebra: propagate
the property, show the witness, skip the Boolean expressions. Also
adjacent: Raku's proto-regex finding (extensible alternation) is
extension of a case vocabulary; restriction is its dual, and a
future round on either should hold both.

### 6. The decorated tree — the AST typing problem

**Their approach.** `Expr[r]` is polymorphic in a record row on
every node; the untyped AST is `Expr[()]`; `typeCheck2: Expr[r] ->
Expr[(tpe = Type | r)]` adds a `tpe` decoration to every node while
preserving whatever other decorations were present. Passes stack
decorations; consumers demand only the labels they read
(`typeOf: Expr[(tpe = Type | r)] -> Type`).

**Our approach.** This is the facets territory
(`facets-design-notes.md`: attachable, authorable extra structure)
meeting the trees row, and it is the second independent arrival at
"one structure, many decorations" — the capability the facets notes
recorded as intuition now has a canonical worked example from
another language. The demand, stated for the functions/reuse/facets
row's remaining list: **a pass adds per-node data to a tree without
editing the node type or its existing consumers, and consumers
demand only the decorations they read.** Their mechanism (row
polymorphism) is type machinery we would not import; the drawn
question is what a decoration *is* on a drawn tree — likely a facet
attached to the tree vocabulary, possibly a derived view
(`transformation-levels-design.md`) when the decoration is computed.
Recorded as a demand with its owner; no design here.

### 7. Regions, structs, and internal mutability

**Their approach.** `deduplicate` allocates a `MutSet` in a region,
mutates freely in `List.filter`'s lambda, and is pure outside;
escape is checked by the region variable in types. Structs are
mutable records in regions; the binary search tree mutates children
under `r`.

**Our approach.** Confirmation, not a gap — and the analog of
Effekt's capture machinery (its finding 6d). Operationally our
compile already works this way (each collect's thunk is a private
mutable scope); semantically, state is per-construct (registers,
collects) and escape is the closed-scope/provenance guard, checked
on drawn structure rather than in types. The specific example —
dedup-by-seen-set — is a keyed operation the collect family should
own as vocabulary (a set collect / distinct), noted for that round.
Mutable trees land on the trees row's eventual mutation question.

### 8. The applications — the game loop, and merges in the wild

**tic-tac-toe.** The gameplay loop is a recursion carrying
`(board, symbol)`, three end reasons (win, draw — plus
invalid-move-retry which continues), per-firing IO (display,
prompt), and an `Interface` effect swappable console/GUI/test. One
beginner-everyday program that simultaneously exercises the record's
top open areas: the loop-state surface, end-when's multi-reason
readout, per-firing effects, the self-driven source, and the
provider swap. A strong candidate **acceptance program** — the
interactive-app counterpart to the event-loop breadth item.

**langcensus.** The analysis module hand-rolls the same merge three
times: fold with `Map.insertWith(⊕)` where ⊕ is pairwise addition —
keyed collect with a merge operator, exactly the shape the lattice
side of §1 needs and the collect family's spelling-and-identity
round owns. Per reading rule 4 these are the corpus's most
field-like sightings (incidental code, not showcase).

**weather.** The provider-stack architecture is §2's app-scale
witness; its JSON drilling (`forM` chains over `getAtKey`) is
ordinary failable pipeline code — comfortable in failability's
propagate-by-default vocabulary, modulo the Tier-1 effects hole.

### 9. Smaller sightings

- **`@Terminates` / `@Tailrec`.** Opt-in, compiler-checked
  termination and tail-position annotations. For us structural
  collects terminate by construction and the open story is the
  divide flow's; prior art that termination is *declared and
  checked* vocabulary, not an ambient hope — noted for the
  recursion/divide row and the checking row.
- **`foreach (a <- l; b <- k; if p) yield`.** Comprehensions with
  guards and dependent nesting — uncollect nesting plus filter
  joins; comfortable, we read equal or better. Their own docs note
  the functional spelling "has a bit more visual noise" — the same
  pressure our drawn form dissolves differently.
- **Type-level programming** (4-bit adder, De Morgan proofs,
  tracked list emptiness). Impressive and deliberately not our
  direction: proof-by-type-algebra is the search-shaped checking
  `types-design.md` explicitly declines; our answer stays property
  propagation with drawable witnesses. Recorded so the direction
  isn't re-litigated from this corpus.
- **The advanced handler examples** (backtracking via a `Rewind`
  effect storing continuations in a map; n-queens with `pick`/`fail`
  directed by the caller). Re-run of Effekt's continuation catalog;
  the speculation row already owns the capability. The `Rewind`
  example is the clash record's sharpest exhibit (below).

## Findings

**Finding 1 — saturation: closure under rules. New open problem.**
Compute the closure of a seed set under derivation rules — graph
reachability/cycles/ordering, dependency resolution, dataflow and
program analysis, 2-SAT — with two attached dimensions: keyed
merge by a lawful operator (the lattice variant; shortest-distance
is keyed-min-collect plus feedback) and **explanation as an output**
(provenance: why is this member in the closure — witness firings,
drawable). One round of rule application is drawable today
(uncollects, the shared-variable constraint as a wire, set collect);
what nothing owns is flow-level feedback — firings minting future
firings, termination when the set stops growing. Distinct from the
register (value feedback along a fixed walk) and from the divide
flow (recursion over virtual *nested* structure); dual to Effekt's
demand-driven build system (finding 4 there), which should be
worked aware of it. The imperative encoding (frontier queue +
seen-set) is the record's standing "assembly language" diagnosis in
a fourth costume. Honest frequency note: absent from all three
random surveys; everyday clients are domain-concentrated — a
breadth obligation (W 3), with the frequency question left to a
sample (below). New row proposed for `open-problems.md`: I 5, W 3.

**Finding 2 — the provider ecosystem: the test double is stdlib
furniture, and the policy layer is a new demand.** Third
independent language centered on late-bound operations; the test
double (Effekt finding 2) now witnessed as standard-library
furniture and as the assembly architecture of ordinary applications
(the weather app's six-provider edge stack). New structure beyond
the prior rounds: **middleware** — cross-cutting operational policy
(retry, circuit-break, throttle, sandbox, atomicity, audit, caps,
jitter, logging) written once and interposed at the operation
boundary, composable, order-sensitive. In the record's leaning
(operations as request/response port pairs), middleware is a
sub-diagram spliced into the provider wiring — interposition by
drawing, with stack order made visible as nesting; structurally we
should be better at this than text languages. Demands handed to the
functions/reuse/facets row: the policy layer, plus §6's decorated
tree. Score movement deliberately withheld: three curated corpora
converging argues W 4 → 5, but per the standing method that move
should come from the owed application-level sample (does real
application code swap providers?) — the row's W stays 4 with the
condition recorded. Dependency noted: policy vocabulary (retry) is
blocked on the concurrency row's pacing hole — a fourth sighting.

**Finding 3 — purity is the typed mirror of drawn effects; two
demands.** Flix tracks purity by annotation and inference; for us
purity is an absence you can see — but only once effects are
drawable at all (Tier-1 confirmation, again). Demands: the function
boundary must pass a filler's effect/failability wires through
visibly (effect polymorphism as structure; associated effects =
per-provider failability, confirming propagate-by-default), to the
functions row; and "this hole demands a pure filler" as
demands/offers vocabulary, to the checking row — requiring purity
at positions (guards, comparators) is everyday, not exotic.

**Finding 4 — concurrency: piecewise confirmations and one small
scope item.** Timeout-as-ordinary-contender confirms the race
round's derived timeout; the **default arm (poll)** is a derived
form that round hasn't named — a race with an immediately-settled
contender that loses all ties (well-defined under the drawn-order
tie law); handed to `race-barrier-design.md`'s derived vocabulary.
`spawn @ region` — task lifetime bounded by a drawn scope — is
mainstream confirmation for the cancellation half of Tier 1 and the
concurrent collect's lifecycle outputs. `par yield` re-confirms the
mirror (they annotate for the fork-join our DAG gives free).
Recursive channel producers are the third outside witness on the
missing source opener.

**Finding 5 — restrictable variants: structure beats types at one
level; recursion is the real prior art.** Case-set narrowing over
one open is what bundles and the partial collect already carry
structurally — their case-omitting `choose` is our partial
engagement, and we read better (no index algebra). The recursive
half — tracking the case set of every node of a tree through
transformation (`simplify` provably eliminating Xor) — is the
strongest prior art yet for the checking row's question 2
(recursive shapes), together with its own warning: the type algebra
goes illegible at scale (their `zip`), supporting drawable
witnesses over imported Boolean indices. Extensible alternation
(Raku finding 5) and restriction are duals; work them together.

**Finding 6 — keyed merge collects keep arriving.** Three
hand-rolled `Map.insertWith` merge folds in langcensus's incidental
code, plus the lattice aggregation at the center of finding 1's
paradigm. The collect family's joint spelling-and-identity round
(keyed/set/last/any collects; operator identities) gains its
strongest cluster of sightings; a set/distinct collect sighted as
`deduplicate`.

**Finding 7 — confirmations, briefly.** (a) Regions are the typed
analog of the closed-scope/provenance guard; per-construct state
covers the capability (Effekt 6d's twin). (b) `@Terminates` —
termination as declared, checked vocabulary; noted for the divide
flow's termination story. (c) The tic-tac-toe game loop is a
candidate acceptance program exercising the top open areas at once
(loop-state surface, end-when readout, per-firing effects, source
opener, provider swap). (d) Comprehensions with guards are
comfortable drawn vocabulary already. (e) The decorated tree gives
the facets notes their second independent witness.

**Finding 8 — what not to import (the clash record).** (a)
*Operations reaching handlers dynamically* — the invisible wire,
verbatim Effekt 7a; Flix's edge-stacked `with` clauses at least
write the stack in one place, but the interior `do`-to-handler jump
is still meaning-by-position; the drawn form remains ports and
wired providers. (b) *Continuations as user values* — the `Rewind`
backtracking example stores continuations in a mutable map keyed by
strings and rewinds by lookup, with `?unreachable` holes where
control tears; the speculation row keeps the capability with
control drawn. (c) *Unification by name coincidence* — inside
`#{}`, two atoms sharing a variable name are joined; meaning by
spelling (Raku 6c's genre); the drawn form makes the shared key a
wire. (d) *Type algebra as the safety story* — Boolean effect
formulas, restrictable-variant index expressions, type-level
adders: the checking row's declined direction; our form is
property propagation with drawable witnesses, and Flix's own
illegible-at-scale types are the supporting evidence. (e) *Loops as
recursion with accumulator-and-reverse idioms* (and the TCE
machinery they require) — the assembly language uncollect/collect
dissolves; nothing to import. As before: none of these are
criticisms of Flix — they are the reasons graft fails and each
capability needs its own inside-out form.

## What this round changes in `open-problems.md`

- **New Tier-2 row**: saturation — closure under rules (the
  worklist/fixpoint) — I 5 (a name and a demand, nothing worked),
  W 3 (breadth obligation; absent from random samples,
  domain-concentrated clients). Carries the keyed-merge and
  provenance-explanation scope items and the duality note with the
  served flow's recursive provider.
- **Functions, reuse, and facets**: remaining list gains the
  **policy layer** (middleware as spliced sub-diagrams on provider
  wiring) and the **decorated tree** (facets' second witness);
  late-bound operations and the test double gain their third and
  strongest witness (stdlib furniture; app architecture). W held at
  4 with the recorded condition: the owed application-level sample
  decides the move to 5.
- **Concurrency row**: dated note — the default-arm/poll variant to
  the race round's derived vocabulary; `spawn @ region` as
  mainstream scope-bound lifetime; third source-opener witness;
  fourth pacing sighting (retry middleware). Scores unchanged.
- **Checking row**: dated note — restrictable variants as prior art
  for recursive shapes (question 2) with the illegibility warning
  favoring drawable witnesses; purity demands on holes;
  `@Terminates` as checked-termination prior art. Scores unchanged.
- **Loop-carried state row**: the operator-identities item gains
  finding 6's sightings cluster (keyed `insertWith` merges; lattice
  aggregation). Scores unchanged.
- **IO/effects (Tier 1)**: confirmation note only (purity mirror;
  every example interleaves effects; scope-bound spawn touches the
  cancellation half).
- **Evidence owed**: add the saturation frequency question — a
  domain sample (package/build/import tooling, analysis code, graph
  features in applications) to measure how often closure-shaped
  computation occurs and in what costume.

## Next rounds of this genre

The standing candidate list (a dataflow/reactive language — the
closest relatives, where differentiation matters most; an
APL-family language — the uncollect/collect story stress-read from
the array side; a beginner-first language — where the
discoverability bar is the whole language) is unchanged, and this
round strengthens the case for the dataflow/reactive one: Flix is
the third language whose *non*-dataflow core keeps re-deriving
capabilities (providers, purity visibility, structured lifetimes)
that should be trivial for a drawn dataflow core — reading an
actual dataflow language would show which of these advantages
survive contact with a shipped implementation. The Raku round's
variant (reading uses rather than showcases) applies here too: real
Flix Datalog use in the wild, or real Souffle/Datalog deployments,
would supply the field sightings reading rule 3 denies this corpus.
