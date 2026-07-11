# Learning from other languages: Flix

Status: comparison study — extracts problems, decides nothing. Demands
are handed to the owning design docs; the design itself stays in the
design conversations.

This is one of a series of studies (`effekt-comparison.md`,
`raku-grammars-comparison.md`, `xquery-jq-comparison.md`) that read
another language's real programs against how this record approaches the
same problems. The output is always **problems** — programs that must be
writable, demands backed by evidence — never mechanisms. Copying Flix
would produce Flix, which already exists and is good at being Flix.

Corpus: the Flix example suite (github.com/flix/flix, `examples/`) —
roughly 190 programs. The distinctive sections were read in full
(datalog, concurrency-and-parallelism, restrictable variants, the
effects-and-handlers ecosystem, functional/imperative style, records,
traits, structs, tail-recursion); the repetitive per-effect koan files
representatively; plus the three small applications (`apps/`: weather,
tic-tac-toe, langcensus) and the static-analysis programs (IFDS and the
lattice domains).

## Reading rules for this corpus

Three standing cautions, with the direction each biases, plus two
specific to Flix:

1. **What's out there is already out there.** The output is problems,
   not mechanisms. Duplicating a language teaches nothing new.
2. **Different core; bolting on clashes.** Flix's *premise* is actually
   shared with ours — the context a computation runs in (its effects,
   its mutation, its dependencies) should be explicit and checkable
   rather than ambient. But its *mechanism* is types where ours is drawn
   structure, and its loops are recursion where ours are
   uncollect/collect. Where Flix is stronger, the question is what the
   drawn, inside-out form of the same capability is — never how to graft
   theirs. The clash record collects the specific grafts that fail.
3. **Maturity polish.** This is the language authors' own example suite:
   curated to flatter the mechanisms. Frequencies here mean nothing.
4. **Mixed curation levels.** The corpus spans koan-style single-feature
   files, ported benchmark programs (Souffle's topsort and 2-sat), and
   three small but real applications. The applications' *incidental*
   code — the folds and merges nobody was showcasing — is the closest
   this genre has come to field style. Sightings from the apps are noted
   as such; they are still not random-sample evidence.
5. **Flix is a combination language.** It is deliberately several
   orthogonal mechanisms at once: purity-tracking effect types, an
   effect-handler ecosystem, first-class Datalog, channels and
   processes, regions, traits, extensible records, restrictable
   variants. Each is read against the record separately rather than
   forced into one center.

## What Flix does

A pure functional core where every function type carries its effect set
(`Int32 -> Int32 \ IO`; pure is the default, spelled `\ {}`), with
higher-order functions able to demand purity or be effect-polymorphic
(`\ ef` flows the argument's effects to the result). On top of that,
algebraic effects and handlers — but grown past a technique into a
*standard-library ecosystem*. `FileSystem`, `Http`, `Sleep`, `Logger`,
`Console` and friends are stdlib effects, each shipping a default real
handler (`runWithIO`), stdlib test doubles (`withInMemoryFS`,
`withSleepNoOp`), and a family of stdlib **middleware** — `withRetry`,
`withCircuitBreaker`, `withRateLimiting`, `withBaseUrl`, `withDryRun`,
`withReadOnly`, `withChroot`, `withAtomicWrite`, `withBackup`,
`withLogging` — cross-cutting policies interposed between a program and
its providers, composed by stacking `with` clauses at the edge. Mutation
is scoped by **regions** (`region rc { ... }`): a function may allocate
and mutate freely inside and stay pure outside, with escape checked in
types. Concurrency is Go-shaped — `spawn e @ rc` (thread lifetime bounded
by the region), channels, `select` with timeout channels and default
arms — plus `par ... yield` fork-join for pure parallelism.

The most distinctive claim is **first-class Datalog**. A `#{ ... }`
constraint set is an ordinary value — composed with `<+>`, built by
recursive functions, returned, stored — with `inject` turning
collections into facts and `query ... select` turning fixpoints back
into vectors. Rules may carry guards calling (pure) Flix functions,
stratified negation, and *lattice semantics*: `Dist(x; d)` merges
duplicate keys by least-upper-bound instead of accumulating tuples, so
shortest-distance is two rules. `pquery ... with {Edge}` is a
*provenance* query — not "what is derivable" but *why*: the witness facts
behind a derived fact. Finally, restrictable variants index an enum by
the set of cases possibly present, and `choose` narrows and transforms
that set through a program.

## The examples, against the record

### 1. Datalog — closure under rules, the corpus's sharpest gap

**Flix.** Graph reachability is three lines: seed fact, step rule, query.

```
Reach(x, y) :- Edge(x, y).
Reach(x, z) :- Reach(x, y), Edge(y, z).
```

Transitive closure, cycle detection, topological sort, 2-SAT,
class-hierarchy and taint analyses are all the same shape. With lattices,
shortest-distance is `Dist(src; Down(0))` plus `Dist(y; d + Down(w)) :-
Dist(x; d), Edge(x, w, y)`, where the min-merge is the lattice's job.
Dependency-resolution adds stratified negation (`Missing` = required but
`not Satisfied`) and provenance for a "why was this needed" chain. And
ford-fulkerson interleaves the layers per-iteration: a functional driver
loop (find augmenting path → update flows → recurse) whose expensive step
is a fresh Datalog fixpoint each round, over a path-carrying lattice.

**The record.** Take a rule body apart and most of it is drawn vocabulary
we already have. `Path(x, y), Edge(y, z)` over fact sets is two
uncollects; the shared variable `y` is a constraint between their value
ports (Flix spells that constraint by *name coincidence* inside the
braces — the drawn form is a wire; see the clash record); the head is a
map to a tuple; the collect target is a set (dedup — the collect
family's territory). One *round* of rule application is a program we can
draw today.

What nothing in the record owns is the **feedback**: the collected output
of a round is also the opened input of the next, iterated until nothing
new appears. This is not the register. The register
(`iteration-with-state-design.md`) feeds a *value* back along one walk
whose extent is fixed by the opened data; here the *extent of iteration
itself* is fed back — firings mint future firings, and termination is
"the set stopped growing." End-when supplies the reading ("stop when no
change") but not the construct.

The imperative encoding is the frontier/worklist loop — seed, pop,
derive, test-against-seen, push — and it is the same diagnosis the record
has made before under other names (the flag as end-when's terminator, the
count as a boundary, the state machine as a phase structure): **the
seen-set and the queue are the assembly language of a saturation the
programmer states declaratively.** Flix's whole Datalog story is the
demonstration that the declarative statement is enough, and its fixpoint
block composes with ordinary code per-call, not as a separate language
stage.

Two dimensions attach to the same gap:

- *Lattice merge* is a **keyed collect whose collisions merge by an
  operator with laws** — the operator-identity question the record
  already carries (hand-rolled monoid folds in the surveys; the collect
  family's spelling round) reappears here as the center of a paradigm.
  Shortest-distance *is* keyed-min-collect plus feedback, nothing else.
- *Provenance* — `pquery`'s "why is this fact in the fixpoint," answered
  with witness facts — is our own instinct surfacing at runtime: drawable
  witnesses (`types-design.md`), derivation free and downward (principle
  6). Whatever construct owns saturation must answer what an *explanation*
  of a fixpoint member looks like — presumably a highlighted subgraph of
  the firings that derived it. Neither Effekt nor Raku raised this; it is
  the most novel scope item here.

Relation to the earlier studies: Effekt's build system is the
*top-down, demand-driven* dual of this bottom-up saturation —
`need(key)` recursion discovering a dependency graph downward, rules
saturating a relation upward. Both are keyed computation over a graph
discovered at runtime; the two demands should be worked aware of each
other.

Field-evidence honesty: no closure/saturation shape appeared in the three
random surveys (sixty loops, thirty orchestration sites) — the
"worklist" sightings there (textwrap, the CSS tokenizer) are
variable-rate consumption, a different animal. The everyday clients are
domain-concentrated: package/build/import tooling, program analysis,
graph features inside products. By the 80/20 rule that makes this a
breadth obligation, not an effortlessness demand — and the frequency
question is a sample-reality hook.

### 2. The effect ecosystem — providers, doubles, and the policy layer

**Flix.** Three layers, all stdlib. *Providers*: every IO-ish capability
is an effect with a default handler; the weather app's `main` runs under a
six-provider stack assembled at the edge, and each module is written
against operations it does not implement:

```
def main(): Unit \ IO =
    run { weatherReport() }
      with Weather.weatherWithHttpAndFile
      with Location.locationWithHttp
      with Display.displayWithIO
      with HttpWithResult.runWithIO
```

*Doubles*: swapping a test double is one `with` line
(`with FileSystem.withInMemoryFS`, `with Sleep.withSleepNoOp`), and the
doubles ship in the standard library. *Middleware*: the operation
boundary is where cross-cutting policy lives — retry strategies, circuit
breaker, rate limiting, base-url rewriting, dry-run, read-only, chroot,
backup, atomic-write, jitter, logging — each a handler that intercepts,
transforms, and re-raises, composed by stacking, with stack order
meaningful (`withCircuitBreaker` outside `withBaseUrl` behaves
differently than inside). There are also effect *hierarchies*: leaf
effects (`FileExists`) run into parent effects (`FileTest`), so a
consumer can demand the narrowest capability it needs.

**The record.** This is the third independent language whose center of
mass lands on late-bound operations (after Effekt's handlers and Raku's
action classes), and the test-double demand (raised in the Effekt study)
now has its strongest witness: not a six-line technique but
*standard-library furniture*, which is what "a language for beginners
cannot lack this" looks like when a language acts on it.

New here is the **policy layer**: operational concerns (retry, throttle,
sandbox, atomicity, audit) written once, attached at the boundary,
composed by stacking. In the record's leaning — an unbound operation is a
request/response port pair on the diagram boundary, and binding is wiring
a provider on — a middleware is a **sub-diagram spliced into the provider
wiring**: requests flow through it on the way to the provider, responses
on the way back. That is interposition *by drawing*, and it turns the
stack-order sensitivity (invisible-wire territory in handler-land) into
visible nesting: which policy wraps which is simply where the splice
sits. Structurally we should be *better* at this than text languages. The
demand goes to the functions/reuse/facets row alongside late-bound
operations.

One dependency: the retry middleware is sleep-between-attempts —
**pacing**, the concurrency row's named semantic hole
(`translation-exercise.md` finding 3). The policy vocabulary is blocked
on it; this is a further sighting, as stdlib vocabulary rather than field
code.

### 3. Purity and effect polymorphism — the typed mirror of drawn effects

**Flix.** Purity is the default and tracked everywhere. `twice(f: Int32
-> Int32)` *rejects* an impure argument at compile time; `twice(f: Int32
-> Int32 \ ef): Int32 \ ef` works for both and its effect is its
argument's. Trait instances vary effects: the `Dividable` trait has an
associated effect, empty for `Float64`, `DivByZero` for `Int32` — same
interface, one implementation failable, one not. Datalog guards and many
library positions *require* purity.

**The record.** The mirror image. For us purity is not an annotation but
an *absence you can see*: a sub-diagram with no effect wiring is pure, and
there is nothing to infer. Two demands fall out:

- **The function boundary must pass a filler's effect and failability
  wires through visibly.** Effect polymorphism is structural for us — a
  hole whose boundary lets whatever wires the filler has flow through —
  and the associated-effect example is per-provider failability, which
  propagate-by-default failability already leans toward (confirmation for
  `async-flow-design.md`'s uniform-dimension stance).
- **"This hole demands a pure filler" is a demand** in the demands/offers
  vocabulary (`types-design.md`). Flix is evidence that requiring purity
  at specific positions (guards, comparators) is everyday, useful
  vocabulary, not type-system exotica.

And the standing confirmation: every Flix example freely interleaves
`println` and `Ref.put` mid-computation — the same outside witness Effekt
gave that the Tier-1 IO/effects hole gates ordinary programs.

### 4. Channels, select, spawn, par — the concurrency row, confirmed piecewise

**Flix.** `select { case m <- recv(r1) => ...; case m <- recv(r2) => ...
}` races receivers; a timeout is not special — `Channel.timeout(5,
Milliseconds)` returns an ordinary receiver you select against; a default
arm makes the select non-blocking (poll). `spawn e @ rc` binds thread
lifetime to the region scope. `par (x <- e1; y <- e2) yield (x, y)` is
annotation-explicit fork-join; `parMap` recurses it over a list.
Long-lived producers (`mooo`, `meow`) are recursive send loops.

**The record.** Mostly confirmations, each landing on a specific open
item:

- Select-with-cases is the race barrier with drawn contenders, and
  timeout-as-ordinary-contender is exactly `race-barrier-design.md`'s
  derived timeout.
- The **default arm** is a variant that round's vocabulary hasn't named:
  a poll is a race with one immediately-settled contender that loses every
  tie (well-defined for free under the drawn-order tie law). Handed to the
  race round as a small scope item.
- `spawn @ region` is scope-bound task lifetime as a mainstream default —
  a confirmation for the cancellation half of the Tier-1 row and the
  concurrent collect's lifecycle outputs (survey 3 measured the demand;
  Flix builds the bound in).
- `par yield` is the mirror confirmation again: they annotate to get the
  fork-join our DAG gives for free.
- Recursive channel producers are self-driven sources — a further outside
  witness that the missing source opener blocks the canonical producer
  program.

Channels-and-processes as an architecture is the served-flow /
server-program question, still unworked; nothing new beyond the sighting.

### 5. Restrictable variants — case sets in types vs bundles in structure

**Flix.** An enum indexed by the set of cases possibly present. `choose`
requires only the cases that can occur (`eval` omits `Var` because its
input type subtracts it); `choose*` tracks the *output* set, so
`simplify` proves Xor is gone, `subst` proves Var became Cst, and the
composition `simplify >> subst >> fasteval` type-checks. The Seq example
makes one type serve as Option/List/NonEmptyList by index (`head` demands
`rvsub <Seq.Nil>`). The cost is visible in the same file: `zip`'s result
index is a three-way Boolean expression over `rvadd`/`rvand` that takes
longer to read than the function.

**The record.** For one level of case structure, the drawn program
*carries this information structurally*: opening a case-typed value yields
a bundle; the alts a consumer engages are exactly the wired ones; a
partial collect is partial by drawing (`partial-collect-design.md` —
their case-omitting `choose` is our partial engagement); and "only Red or
Blue reaches here" is readable off the wiring, no index algebra needed.

Where Flix is genuinely ahead is **recursion**: `simplify` tracks the
case set of every node of a *tree* through construction, and our bundles
speak only of the flow level being opened. Recursive shape properties are
the checking row's open question. Restrictable variants are the strongest
prior art yet that (a) recursive case-set properties are trackable and
pay for themselves (eval-without-Var is the payoff), and (b) the algebra
gets illegible at scale (`zip`) — which supports the checking row's
drawable-witnesses stance over imported index algebra: propagate the
property, show the witness, skip the Boolean expressions. Adjacent: Raku's
proto-regex finding (extensible alternation) is extension of a case
vocabulary; restriction is its dual, and a future round on either should
hold both.

### 6. The decorated tree — the AST typing problem

**Flix.** `Expr[r]` is polymorphic in a record row on every node; the
untyped AST is `Expr[()]`; `typeCheck: Expr[r] -> Expr[(tpe = Type | r)]`
adds a `tpe` decoration to every node while preserving whatever other
decorations were present. Passes stack decorations; consumers demand only
the labels they read (`typeOf: Expr[(tpe = Type | r)] -> Type`).

**The record.** This is facets territory (`facets-design-notes.md`:
attachable, authorable extra structure) meeting the trees row — a second
independent arrival at "one structure, many decorations." The demand for
the functions/reuse/facets row: **a pass adds per-node data to a tree
without editing the node type or its existing consumers, and consumers
demand only the decorations they read.** Their mechanism (row
polymorphism) is type machinery we would not import; the drawn question is
what a decoration *is* on a drawn tree — likely a facet attached to the
tree vocabulary, possibly a derived view
(`transformation-levels-design.md`) when the decoration is computed.
Recorded as a demand with its owner.

### 7. Regions, structs, and internal mutability

**Flix.** `deduplicate` allocates a `MutSet` in a region, mutates freely
in `List.filter`'s lambda, and is pure outside; escape is checked by the
region variable in types. Structs are mutable records in regions; the
binary search tree mutates children under `r`.

**The record.** Confirmation, not a gap. Operationally our compile
already works this way (each collect's thunk is a private mutable scope);
semantically, state is per-construct (registers, collects) and escape is
the closed-scope/provenance guard, checked on drawn structure rather than
in types. The specific example — dedup-by-seen-set — is a keyed operation
the collect family should own as vocabulary (a set collect / distinct).
Mutable trees land on the trees row's eventual mutation question.

### 8. The applications — the game loop, and merges in the wild

- **tic-tac-toe.** The gameplay loop is a recursion carrying `(board,
  symbol)`, three end reasons (win, draw, plus invalid-move-retry which
  continues), per-firing IO (display, prompt), and an `Interface` effect
  swappable console/GUI/test. One beginner-everyday program that
  simultaneously exercises the record's top open areas: the loop-state
  surface, end-when's multi-reason readout, per-firing effects, the
  self-driven source, and the provider swap. A strong candidate
  **acceptance program** — the interactive-app counterpart to the
  event-loop breadth item.
- **langcensus.** The analysis module hand-rolls the same merge three
  times: fold with `Map.insertWith(⊕)` where ⊕ is pairwise addition — a
  keyed collect with a merge operator, exactly the shape the lattice side
  of §1 needs. Per reading rule 4 these are the corpus's most field-like
  sightings.
- **weather.** The provider-stack architecture is §2's app-scale witness;
  its JSON drilling (`forM` chains over `getAtKey`) is ordinary failable
  pipeline code — comfortable in failability's propagate-by-default
  vocabulary, modulo the Tier-1 effects hole.

### 9. Smaller sightings

- **`@Terminates` / `@Tailrec`.** Opt-in, compiler-checked termination
  and tail-position annotations. For us structural collects terminate by
  construction and the open story is the divide flow's; prior art that
  termination is *declared and checked* vocabulary, not an ambient hope.
- **`foreach (a <- l; b <- k; if p) yield`.** Comprehensions with guards
  and dependent nesting — uncollect nesting plus filter joins; we read
  equal or better. Flix's own docs note the functional spelling "has a bit
  more visual noise" — the same pressure our drawn form dissolves
  differently.
- **Type-level programming** (4-bit adder, De Morgan proofs, tracked list
  emptiness). Impressive and deliberately not our direction:
  proof-by-type-algebra is the search-shaped checking `types-design.md`
  explicitly declines; our answer stays property propagation with drawable
  witnesses. Recorded so the direction isn't re-litigated from this
  corpus.
- **Advanced handler examples** (backtracking via a `Rewind` effect
  storing continuations in a map; n-queens with `pick`/`fail`). A re-run
  of Effekt's continuation catalog; the speculation row already owns the
  capability. The `Rewind` example is the clash record's sharpest exhibit.

## The yield

Indexed by topic, with importance/breadth scores for the target rows of
`open-problems.md`:

- **Saturation — closure under rules. New open problem (I 5, W 3).**
  Compute the closure of a seed set under derivation rules — graph
  reachability/cycles/ordering, dependency resolution, dataflow and
  program analysis, 2-SAT — with two attached dimensions: keyed merge by a
  lawful operator (shortest-distance is keyed-min-collect plus feedback)
  and **explanation as an output** (provenance: why is this member in the
  closure — witness firings, drawable). One round of rule application is
  drawable today (uncollects, the shared-variable constraint as a wire,
  set collect); what nothing owns is flow-level feedback — firings minting
  future firings, termination when the set stops growing. Distinct from
  the register (value feedback along a fixed walk) and from the divide
  flow (recursion over virtual *nested* structure); dual to Effekt's
  demand-driven build system, which should be worked aware of it. The
  imperative encoding (frontier queue + seen-set) is the standing
  "assembly language" diagnosis in another costume. Breadth obligation
  (absent from all three random surveys; clients domain-concentrated),
  with the frequency question left to a sample.
- **The provider ecosystem: test double is stdlib furniture; the policy
  layer is a new demand.** Third independent language centered on
  late-bound operations; the test double now witnessed as
  standard-library furniture and as the assembly architecture of ordinary
  applications (the weather app's six-provider stack). New: **middleware**
  — cross-cutting operational policy written once and interposed at the
  operation boundary, composable, order-sensitive. In the record's leaning
  (operations as request/response port pairs), middleware is a sub-diagram
  spliced into the provider wiring — interposition by drawing, stack order
  made visible as nesting. Demands to the functions/reuse/facets row: the
  policy layer, plus §6's decorated tree. Score movement withheld: three
  curated corpora converging argues W 4 → 5, but per the standing method
  that move should come from an application-level sample (does real
  application code swap providers?) — the row's W stays 4 with the
  condition recorded. Dependency: retry policy is blocked on the
  concurrency row's pacing hole.
- **Purity is the typed mirror of drawn effects; two demands.** The
  function boundary must pass a filler's effect/failability wires through
  visibly (effect polymorphism as structure; associated effects =
  per-provider failability, confirming propagate-by-default), to the
  functions row; and "this hole demands a pure filler" as demands/offers
  vocabulary, to the checking row.
- **Concurrency: piecewise confirmations and one small scope item.**
  Timeout-as-ordinary-contender confirms the race round's derived
  timeout; the **default arm (poll)** is a derived form that round hasn't
  named (handed to `race-barrier-design.md`). `spawn @ region` is
  mainstream confirmation for the cancellation half of Tier 1 and the
  concurrent collect's lifecycle outputs. `par yield` re-confirms the
  mirror. Recursive channel producers are another outside witness on the
  missing source opener.
- **Restrictable variants: structure beats types at one level; recursion
  is the real prior art.** Case-set narrowing over one open is what
  bundles and the partial collect already carry, and we read better (no
  index algebra). The recursive half — tracking a tree's per-node case set
  through transformation — is the strongest prior art yet for the checking
  row's recursive-shapes question, together with its warning: the type
  algebra goes illegible at scale (their `zip`). Extensible alternation
  (Raku) and restriction are duals; work them together.
- **Keyed merge collects keep arriving.** Three hand-rolled
  `Map.insertWith` merge folds in langcensus's incidental code, plus the
  lattice aggregation at the center of saturation. The collect family's
  joint spelling-and-identity round gains its strongest cluster of
  sightings; a set/distinct collect sighted as `deduplicate`.
- **Confirmations, briefly.** Regions are the typed analog of the
  closed-scope/provenance guard; per-construct state covers the
  capability. `@Terminates` is termination as declared, checked
  vocabulary, noted for the divide flow. The tic-tac-toe game loop is a
  candidate acceptance program exercising the top open areas at once.
  Comprehensions with guards are comfortable drawn vocabulary already. The
  decorated tree gives the facets notes their second independent witness.

## The clash record: what must not be imported

None of these are criticisms of Flix — they are the reasons a graft
fails, and each capability needs its own inside-out form.

- **Operations reaching handlers dynamically** — the invisible wire.
  Flix's edge-stacked `with` clauses at least write the stack in one
  place, but the interior `do`-to-handler jump is still meaning-by-
  position; the drawn form remains ports and wired providers.
- **Continuations as user values** — the `Rewind` backtracking example
  stores continuations in a mutable map keyed by strings and rewinds by
  lookup, with `?unreachable` holes where control tears. The speculation
  row keeps the capability with control drawn.
- **Unification by name coincidence** — inside `#{}`, two atoms sharing a
  variable name are joined; meaning by spelling. The drawn form makes the
  shared key a wire.
- **Type algebra as the safety story** — Boolean effect formulas,
  restrictable-variant index expressions, type-level adders: the checking
  row's declined direction. Our form is property propagation with drawable
  witnesses, and Flix's own illegible-at-scale types are the supporting
  evidence.
- **Loops as recursion with accumulator-and-reverse idioms** (and the
  tail-call machinery they require) — the assembly language
  uncollect/collect dissolves; nothing to import.

## What this study changes in `open-problems.md`

- **New Tier-2 row**: saturation — closure under rules (the
  worklist/fixpoint). I 5 (a name and a demand, nothing worked), W 3
  (breadth obligation; absent from random samples, domain-concentrated
  clients). Carries the keyed-merge and provenance-explanation scope items
  and the duality note with the served flow's recursive provider.
- **Functions, reuse, and facets**: remaining list gains the **policy
  layer** (middleware as spliced sub-diagrams) and the **decorated tree**
  (facets' second witness); late-bound operations and the test double gain
  their strongest witness (stdlib furniture; app architecture). W held at
  4 with the recorded condition: the owed application-level sample decides
  the move to 5.
- **Concurrency row**: note the default-arm/poll variant for the race
  round's derived vocabulary; `spawn @ region` as mainstream scope-bound
  lifetime; another source-opener witness; the retry-middleware pacing
  sighting. Scores unchanged.
- **Checking row**: restrictable variants as prior art for recursive
  shapes with the illegibility warning favoring drawable witnesses; purity
  demands on holes; `@Terminates` as checked-termination prior art. Scores
  unchanged.
- **Loop-carried state row**: the operator-identities item gains the
  keyed-merge sightings cluster. Scores unchanged.
- **IO/effects (Tier 1)**: confirmation only (purity mirror; every example
  interleaves effects; scope-bound spawn touches the cancellation half).
- **Evidence owed**: the saturation frequency question — a domain sample
  (package/build/import tooling, analysis code, graph features in
  applications) measuring how often closure-shaped computation occurs and
  in what costume.

## Next rounds of this genre

The standing candidate list is unchanged: a dataflow/reactive language
(the closest relatives, where differentiation matters most); an APL-family
language (the uncollect/collect story stress-read from the array side); a
beginner-first language (where the discoverability bar is the whole
language). This study strengthens the case for the dataflow one: Flix is
the third language whose *non*-dataflow core keeps re-deriving
capabilities (providers, purity visibility, structured lifetimes) that
should be trivial for a drawn dataflow core — reading an actual dataflow
language would show which of these advantages survive contact with a
shipped implementation. And the uses-not-showcases variant applies here
too: real Flix Datalog in the wild, or real Souffle/Datalog deployments,
would supply the field sightings this curated corpus cannot.
