# Editor state management — incremental computation over history

Status: exploration — a worked proposal for how the interactive
editor's state is represented and how derived computations (the
checker's properties and witnesses, the suggester's eligibility, the
completion lens, eventually codegen) are reused across edits. Nothing
here is implemented for the editor itself, but the design has a
running proof of concept (below). It is the state-architecture companion to
`program-editing-design.md` (which owns the cursor, the edit
inventory, and the TUI) and builds directly on
`transformation-levels-design.md` (the step-DAG) and
`types-design.md` (the propagation this document decomposes). Read
those first; this document re-derives none of them.

A standalone proof of concept of this design now runs in the repo:
`src/EditorPoc.res` / `src/EditorPocTest.res` (`npm run poc`) — see
"Proof of concept" at the end of this document. Nothing is implemented
for the flow language itself.

The one-sentence design: **the basic implementation — the cursored
program as one immutable value, everything recomputed from scratch —
is kept as the *definition* of the editor's semantics, and every
improvement below is a cache of a pure function of the program
version: history is the step-DAG with the current version cached at
the head, the zipper question dissolves because the ports-first node
set has no depth to bury a cursor in, and incrementality is
memoization keyed by the step-DAG's own identity discipline — which
replaces Incremental's invalidate-and-stabilize (a mutable
current-state concept) with keying into a store that serves every
version, so undo, branches, and previews are cache hits rather than
recomputations.**

## The problem

The editor session of `program-editing-design.md` is a working
record `{program, cursor, mark}`; a keystroke selects an edit — a
pure function — and the record is replaced by a new one. Everything
the editor displays beyond the program itself is computed: the
canonical print, the completion lens's `+` lines, the checker's
witnesses, the derived properties at each wire, and the eligibility
menu (the legal next edits at the cursor, ranked). The basic
implementation recomputes all of it from scratch after every edit.

Four pressures on that basic approach:

1. **Reuse.** Most of what was computed for the previous version is
   still true of the next one — an edit touches a handful of nodes.
   Recomputing the world per keystroke wastes almost all of its work,
   and the suggester multiplies the waste: ranking candidates by
   hypothetical checking (`program-editing-design.md`, "Cost of
   hypothetical checking") runs the checker once per candidate per
   keystroke.
2. **Edit locality.** Most edits modify the program near the cursor.
   In a naive root-up representation the cursor may be buried deep,
   and reaching it — let alone rebuilding around it — costs a
   traversal. Is a functional zipper the right structure?
3. **History at the root.** Every edit must leave in place the
   program's history to all levels — its history, the history of its
   history, and so on — while the root of the structure gives ready
   access to the current program without wading through remote
   history levels that are never relevant to the current keystroke.
4. **The governing constraint.** Incrementally computed information
   must match the information that would be computed from scratch —
   exactly, not approximately. A checker witness that exists
   incrementally but not from scratch (or vice versa) is a bug of
   the worst kind: invisible, accumulating, and discovered far from
   its cause.

Requirement 4 is the tough one, and it governs the shape of
everything else. So it is settled first, by fiat.

## The basic implementation is the semantics

The basic implementation is not a straw man to be improved past — it
is the **definition**. The editor's meaning is: the working record is
an immutable value; an edit replaces it; every displayed artifact is
a pure function of the record, conceptually recomputed fresh.

Everything this document adds must be describable as **a cache of
that pure function**: a table that, when consulted, returns exactly
what the function would have returned, and whose complete removal
changes nothing observable but time. Any proposed mechanism that
cannot be described that way — a store holding information the
current version doesn't determine, an update rule whose result
depends on the order edits happened — is wrong *by construction*,
before any bug is found.

This is `transformation-levels-design.md`'s "no staleness, no
run-history, no invalidation — there is no stored result to go stale;
there is the program and its re-derived meaning," adopted here as an
engineering discipline rather than only an ontological stance. It
settles requirement 4 in the only way that survives contact with real
caching bugs: not "we will be careful," but "the cache is
semantically invisible or it is not a cache." The rest of the
document is about making such caches *effective* — high hit rates
under real edits — without ever loosening that definition.

One immediate consequence worth stating: the from-scratch path never
goes away. It is the oracle the incremental path is tested against
(see "The obligation," below), and it is the fallback when a cache is
cold, dropped, or not yet built. The milestones at the end are
ordered so that the editor is *correct and shippable at every rung*,
with each rung adding only cache.

## The zipper question

A functional zipper restructures a tree around a focus: the focused
subtree is at the root, and the context — the path back to the old
root, turned inside out — hangs beside it. It buys three things:
O(1) access to the focus, O(1) edit at the focus, and cheap motion of
the focus to a neighbor. The question is whether the cursored program
should be a zipper over the program.

The answer proposed here: **no — the premise dissolved when the
program stopped being a tree.** But each of the zipper's three
payoffs is real, and each needs its own account of where it comes
from instead.

**The program has no depth to bury a cursor in.** The ports
migration (`first-class-ports-design.md`, implemented in
`Program.res`) made the program a **node set** with distinguished
outputs — a flat collection, not a root expression. There is no
containment: no node is "inside" another, and the cursor
(`OnNode`/`AtPort`/`InSlot`, all keyed by node identity) addresses
its target directly, not through a path from a root. "The cursor may
be buried somewhat deep" is a true worry about expression trees, and
the representation this repo already committed to is the thing that
retires it. Access to the focus: O(1) by construction, no
restructuring needed.

**Edit at the focus is a path copy downstream, and that is
acceptable — measured, not assumed.** Today's `Program.res` refs
embed the producer's *record* (`ValuePort(node, port)` holds the
node value), so a version is an object DAG: replacing a node rebuilds
its transitive consumers down to the outputs
(`transformation-levels-design.md`, "Every change builds" — the
rebuilt path keeps its ids). The cost of an edit is therefore
proportional to the focus's *downstream* cone, not to any burial
depth of the cursor. At editor scale — programs that fit on screens,
paths that fit in tens of nodes — this is nothing. If it ever bites,
the alternative representation is refs-by-id over a persistent map
(edits touch O(log n) map entries, consumer records never rebuilt),
recorded as an open fork below — but the leaning is to keep
refs-by-record, because embedding the producer's record gives the
memoization design its best key for free (next sections), and the
editing doc's edit inventory is already specified against it.

**Motion needs no restructuring because computation is
demand-driven.** The third zipper payoff — the neighborhood of the
focus is cheap to reach — matters when computing *around* the focus
requires having the structure oriented toward it. Here the
orientation is supplied by laziness instead: the editor demands only
what the view shows (the visible print, the witnesses at visible
anchors, the eligibility at the cursor), and the store computes only
what is demanded — the same posture as the lazy compile strategy,
where "the compiler decides almost nothing and laziness handles
compute-only-when-needed." Locality of recomputation is a property
of the *query layer*, not of the data structure's rooting.

So the zipper's payoffs decompose: focus access ← flat node set;
edit locality ← persistent sharing; recomputation locality ←
demand-driven queries. What a literal zipper would *add* is two
liabilities: the focus becomes part of the structure's identity —
exactly what the editing doc's tier layering forbids (the cursor is
session state, kept out of step identity so motion is never a
history step) — and graphs do not zipper the way trees do (fan-out
means a node has no single context to invert; graph zippers exist
but carry real machinery for no payoff still needed). Rejected for
the program. (Please don't re-propose a program zipper without a
measured access-cost problem the flat set demonstrably has.)

Where the zipper *shape* genuinely survives is one level up: the
working record is a **zipper over the step-DAG** — the current
version in focus, the history as its context. That is the next
section.

## The state, tiered — and where history lives

`program-editing-design.md` layered the working record into content /
presentation / session. This document adds a fourth tier and the
history structure around all of them:

```
historyNode = {
  step:    step,                    -- the edit, stored at its native level
  parents: array<historyNode>,      -- the step-DAG (undo targets, merges,
                                    --   cherry-pick provenance)
  version: Program.program,         -- the fold of ancestry, cached here
}

workingRecord = {
  head:   historyNode,              -- program access = head.version, O(1)
  cursor: position,                 -- session tier, as before
  mark:   option<ref>,              -- session tier, as before
  store:  store,                    -- the cache tier — droppable
}
```

The orientation is the important choice, and it is the zipper move
applied at the right level: **head-first.** The current version is
one field read from the root of the structure; the history hangs
*behind* the head as parent pointers, and no editor operation short
of history browsing ever follows them. Remote history is reachable,
never traversed. This is requirement 3's "ready access without
getting bogged down": the program is not found by folding history
from the beginning — the fold is cached at every node, and the head's
cache *is* the working program.

**The infinite levels come from the collapse, not from strata.**
The history of the history — undo steps, undo-of-undo, cherry-picks,
every level up — lives in the *same* DAG, because
`transformation-levels-design.md` already did the hard work: each
step is stored once at its native level, and every higher-level
reading is degenerate, derived, never stored. An ordinary edit is
degenerately its own entry in the history-of-history; only a step
whose native level is higher (undo is level 1 over the history;
undo-of-undo level 2) adds content at that tier. So requirement 3's
"infinity level history" costs exactly one DAG of steps, and the
head node is as close to the program for a thousand-step history as
for a three-step one. Nothing new is designed here — this section
just confirms the editor's state slots into that structure with the
head cached.

Two economies keep the DAG cheap to *keep*:

- **Versions share.** Each `version` is a persistent value sharing
  all untouched structure with its parents; caching one per history
  node costs O(edit) per step, not O(program).
- **Caches evict; steps don't.** A remote node's `version` field can
  be dropped and refolded on demand (the fold is a pure function of
  ancestry), because it is itself only a cache of the fold. The
  steps are the durable record; everything else in the structure
  obeys the cache discipline. The same applies to the `store` — see
  next — and to serialization: a session file needs the steps, the
  session tier, and nothing else.

The **store** is the fourth tier: the memoization state of the next
sections. Its defining property is the fiat above — droppable at any
moment, never serialized as truth (serializing it as a warm-start
optimization is permissible exactly because loading a stale or
foreign store must be *harmless*, only slow, or the design is
wrong). It sits in the working record rather than beside a single
version because its whole point is to be shared **across** versions:
one store serves the head, every undo target, and every hypothetical
preview version at once.

## Incremental's concepts, re-keyed from time to history

Jane Street's Incremental is the reference point for making
recomputation proportional to change. Its model: a DAG of
computation nodes over input variables; setting inputs marks
dependents stale (**invalidation**); **stabilization** recomputes
stale nodes in dependency order; **cutoff** stops propagation where
a recomputed value equals the old one. It is very good at
requirement 4's concern — a stabilized graph is globally consistent,
indistinguishable from recomputation from scratch.

The mismatch is stated by the user's framing exactly: Incremental
(and Salsa, and the self-adjusting-computation family generally)
maintains **the current state**. Stabilization is destructive —
recomputing a node overwrites its previous value; "the graph at the
previous input" no longer exists. That is the right economy for a
spreadsheet or a server, where time only moves forward. The editor's
time doesn't: undo moves backward, branching moves sideways, and the
suggester's previews evaluate dozens of hypothetical versions per
keystroke *without ever committing to any of them*. Under a
current-state engine each of those is a full invalidate-stabilize
round trip — undo costs as much as redo-ing by hand, and previews
thrash the one state the engine has.

The reframe that fits: **drop invalidation entirely; replace it with
keying.** A derived value is a pure function of the version it was
computed from. Store it under a key that identifies *what it read*.
A new version doesn't invalidate anything — it simply poses queries,
and each query's key either matches an existing entry (hit: the
inputs it would read are the same values, so the from-scratch result
is the cached result, by purity) or doesn't (miss: compute, store).
Entries for superseded versions aren't stale — they are correct
answers to questions no longer being asked, garbage-collectable but
never wrong. The Incremental vocabulary maps over:

| Incremental (time-shaped)         | here (history-shaped)                                   |
|-----------------------------------|---------------------------------------------------------|
| input variable, set destructively | a node record in a version; never mutated               |
| stabilization number (the clock)  | the step that built the record (the step is the clock)  |
| invalidate on set                 | nothing — a new version has new keys where it differs   |
| stabilize                         | demand the view's queries at the new head                |
| node's current value              | store entry under (query, key); many may coexist        |
| cutoff (old value = new value)    | result-equality cutoff at query boundaries              |
| dependency graph, height order    | the program's own wiring (and its condensation)         |
| observer                          | whatever the view demands this frame                    |

The build-systems literature has the crisp name for this fork
("Build systems à la carte," Mokhov/Mitchell/Peyton Jones): a
**verifying trace** remembers what a value was computed from and
re-verifies it against the current state — one value per key, the
Salsa/rust-analyzer school, still current-state-shaped. A
**constructive trace** stores the values themselves, keyed by
content, many per key — the cloud-build school (Bazel's remote
cache, Nix). The editor wants constructive traces pointed at its own
history: **undo is a cache hit** (the old version's keys are all
still in the store), branch switching is cache hits plus the
genuinely-different fringe, and a preview is speculative queries
whose entries need no rollback because nothing was invalidated to
make them. Adapton (Hammer et al.) is the nearest incremental-
computation relative — its demanded-computation graphs were built
to handle exactly the "swap between states" workload that defeats
current-state engines — and self-adjusting computation (Acar) is the
common theory. Nothing here is novel incrementality; the novelty is
only that the step-DAG supplies, for free, the two things such
systems work hardest for: a canonical identity for every piece of
input (next section) and an exact enumeration of what changed
between any two states (the step *is* the diff).

## Keys: the step is the clock

Everything above turns on keys that satisfy one discipline: **a
query's key must cover everything the query reads.** A key that
omits a read input admits false hits — the incremental result
silently diverges from scratch, the requirement-4 catastrophe. A key
that includes unread inputs only costs misses. So keys err coarse,
and the design work is making them precise enough to hit.

The step-DAG's identity rules (`transformation-levels-design.md`,
"Node identity") supply the raw material:

- Every node record is built by exactly one step: the step that
  minted its id, or the step whose path copy rebuilt it (same id,
  new record). **(id, building step)** therefore identifies a
  record's *content* exactly: two versions in which node `n42` was
  last rebuilt by the same step hold the same record — by sharing,
  literally the same value.
- **Sharing preserves identity through history motion.** Undo
  restores by derivation, not reconstruction — the restored records
  are the shared old values, carrying their original building steps.
  Likewise the untouched remainder under any edit, and the
  correspondence-translated content of a cherry-pick. So the
  operations that defeat a time-shaped clock (moving backward,
  sideways) preserve this clock's readings, which is exactly why
  their queries hit.
- **The step enumerates its touched set.** An edit step knows
  precisely which ids it minted, rebuilt, or dropped — the edit
  inventory is small and each edit's footprint is part of its
  specification. Moving the store's attention from version v to v'
  never requires diffing structures; the steps between them (in
  either direction along the DAG) list every id at which the
  versions can differ. Everything else is shared, and known shared.

With refs-by-record (today's representation), one more thing comes
free, and it is the reason to keep that representation: **a ref *is*
its upstream cone.** `ValuePort(node, port)` embeds the producer's
record, which embeds *its* producers' records, transitively — so the
ref's value identity (physically, its pointer) already covers the
entire upstream region. For any query whose footprint is
upstream-only, the ref itself is a complete, O(1)-comparable key.
This is Merkle-tree/content-addressing logic with sharing standing
in for hashing — and path copy maintains it: an edit rebuilds
exactly the downstream records, which are exactly the records whose
upstream cones changed, which are exactly the upstream-footprint
queries that may answer differently. The invalidation an
Incremental-style engine would compute is performed *by the
representation*, structurally, as a byproduct of the edit.

Two honest limits, each with its answer:

- **Pointer identity doesn't serialize.** Across save/load, records
  must be re-interned (by id + building step, recorded per step in
  the DAG) for keys to survive — or the store starts cold, which the
  cache discipline makes merely slow. Fine either way; decide when
  session files exist.
- **Provenance is finer than content.** Two records built by
  different steps can be equal in content (an edit applied, undone
  by inverse, re-applied; two branches making the same change), and
  provenance keys miss where content keys would hit. The upgrade is
  hashing (true content addressing). Deferred as an optimisation:
  the operations that matter — undo, preview, ordinary editing —
  hit on provenance alone, because their sharing is real.

## Decomposing the checker into queries

Now the question the prompt is right to press: *use incremental
computation how?* Saying "memoize" is empty until the checker's work
is factored into functions whose keys and footprints make reuse
actually happen. The factoring below is proposed bottom-up: the
atomic functions first, then the composition, then the fixpoint
problem, then the grain sizes.

Three facts about the checking design make it unusually good
material (this is why the types doc could promise "the step-DAG
design and this checker are unusually good for each other" — this
section is that promise cashed):

1. **It is already pure passes.** The pipeline (`Pipeline.res`) is
   pure functions returning witnesses as data; the designed property
   propagation (`types-design.md`) is monotone propagation with no
   choice points. There is no ambient state to thread; the only work
   is grain.
2. **The dependency graph is the program.** Properties travel along
   wires — "the constraint network the solver runs on is the diagram
   itself." A query's footprint is therefore readable off the
   wiring, not discovered by instrumentation: no dynamic dependency
   tracking is needed, which removes the machinery where
   Salsa-family systems spend most of their complexity.
3. **Results are small and comparable.** Property sets, context
   paths, and witness lists are little finite values with cheap
   structural equality — exactly what result-equality cutoff needs.

### The query inventory

Each query is a pure function; its **footprint direction** decides
which keying regime serves it (next subsection).

| query                       | of                    | computes                                          | footprint    |
|-----------------------------|-----------------------|---------------------------------------------------|--------------|
| `record`                    | node id, version      | the node record (the base fact)                   | the entry    |
| `consumers`                 | port, version         | the slots referencing it (reverse index)          | global-ish   |
| `context`                   | ref                   | the flow-context path (`Context.res` / `Poset`)   | upstream     |
| `offers`                    | ref                   | properties established at the port                | upstream     |
| `demands`                   | slot                  | properties required, accumulated from consumers   | downstream   |
| `checkOutput`               | output name           | the witnesses for that output's cone              | the cone     |
| `signature`                 | diagram boundary      | boundary-projected residual demands/offers/links  | the interior |
| `eligible`                  | cursor position       | ranked edit candidates (the suggester)            | mixed        |
| `complete` / `print` / `compile` | version / output | the completion lens, canonical print, emitted JS  | varies       |

The atomic pieces inside `offers`/`demands` are the **catalog
transfer functions**: per node kind, (catalog entry × input
properties) → output properties, and its backward mirror. These are
node-local, trivially pure, and never memoized individually — they
are the loop bodies of the queries above.

### Two directions, two regimes

**Upstream-footprint queries key on the ref.** `offers(ref)` reads
the producing node's record and the `offers` of its input refs —
recursively, an upstream-only footprint. Under refs-by-record the
ref is that footprint's complete identity, so the memo is a weak
table `ref → result` (or, equivalently and more in this repo's
idiom, a **lazy derived field on the record itself** — the
lazy-compile aesthetic applied to the meta level: every record
carries thunks for its derived views, and memoization sharing then
exactly tracks structure sharing, with entries dying when their
records do). `context(ref)` is the same regime; it is upstream-
derived (the openers on the path from sources), and `Context.res`
already computes it as a pure function.

**Downstream-footprint queries key on the version plus maintained
indices.** `demands(slot)` reads the *consumers* of a port — a
footprint that inverts the wiring, which refs-by-record gives no
handle on. Two pieces: the `consumers` reverse index, maintained
incrementally per step (each step's touched set says exactly which
index entries to rebuild — this is where "the step is the diff" does
real work), and the `demands` results themselves, memoized per
(slot, version-region) with dependencies on `demands` of downstream
slots. This is the one place verification-style bookkeeping earns
its keep; it stays cheap because demand chains are short (demands
propagate until absorbed by a concrete source, a schematic source,
or a hole).

An honest asymmetry falls out, worth designing toward rather than
against: forward information (offers, shapes, contexts) is nearly
free to reuse; backward information (demands, the suggester's
interface accumulation) costs index maintenance. The starter
property inventory leans forward-heavy — shapes and contexts do the
clash-finding — so the cheap regime covers the hot path.

### Fixpoints: recompute the component, never seed it

Propagation is a fixpoint where the graph cycles — today only the
register back-edge (Delay transports value properties around it;
`types-design.md`). Fixpoints resist naive per-node memoization
(the queries in a cycle read each other), and they carry this
design's one subtle correctness trap.

The trap: it is tempting to "warm-start" a fixpoint from the
previous version's solution. For a monotone framework that is sound
under *additions* — but an edit can remove structure, and a
solution seeded above the new least fixpoint can stay above it:
converged, consistent-looking, and **wrong relative to
from-scratch**, which is precisely the divergence requirement 4
bans. (This is the incremental-Datalog deletion problem;
`saturation-design.md` meets the same shape at the language level.)

The rule adopted here: **the memo unit for cyclic structure is the
strongly-connected component, recomputed from bottom whenever its
key changes; a component's solution is never seeded from a previous
version's.** The condensation of the program graph is a DAG, on
which the two keying regimes above apply cleanly; within a
component, run the fixpoint from ⊥ — components are small (a
register loop), domains are finite, and the from-scratch equality is
then true by construction, not by argument. Delta-maintenance of
fixpoints under deletion (DRed-style) is recorded as a deferred
optimisation with a warning label: it trades this by-construction
guarantee for algorithmic cleverness, and should not be bought
until a measured component is too big to recompute.

### Cutoff surfaces: where recomputation stops

Result-equality cutoff is what makes locality real: an edit's
downstream cone is *examined*, but recomputation stops at the first
query whose new result equals its old one — and property results
are tiny, so the comparisons are cheap. Two surfaces matter:

- **Per-node**: interposing `double` before a node that already
  received *numeric* changes that node's record (new key) but not
  its offered properties (equal result) — consumers hit, and the
  edit's property-level effect is contained in one step even though
  its structural effect reaches the outputs.
- **Boundary projection, by design.** The types doc's principal
  property signature — propagation projected onto a diagram's
  ports — is not just modularity for reuse of *diagrams*; it is the
  **designed coarse cutoff** for reuse of *computation*. An edit
  inside a region recomputes the region; if the boundary projection
  is unchanged, nothing outside is touched. When
  functions-as-remembered-cuts land, their boundaries become these
  surfaces for free; until then, per-output cones are the coarse
  regions (below).

### Grains: a ladder, not a choice

The same pure function caches at any grain, so grain is an economics
question, decided by measurement per the standing method — and the
ladder is ordered so each rung is strictly "add cache," never
re-architecture:

0. **Whole-record** (the basic implementation): recompute all,
   memoize nothing. Correct; the oracle; shippable.
1. **Per-output cone**: `checkOutput` / `compile` memoized per
   output, keyed on the output's ref (an upstream-footprint key,
   free under refs-by-record). One line of mechanism; already wins
   whenever a program has more than one output and an edit touches
   one cone.
2. **Per-node forward queries**: `offers` / `context` as lazy
   derived fields; clash-finding becomes proportional to the edit's
   downstream cone with cutoff.
3. **Backward queries and indices**: `consumers` maintenance +
   `demands` memoization; the suggester's hypothetical checks go
   incremental.
4. **Region signatures**: boundary-projected cutoff at diagram/
   function boundaries, when those exist.

### A worked keystroke

The surgery example from the editing doc, at rung 2–3. Program:

```
[1, 2, 3] -> open list -> double -~> collect => out
data -> parse -> min => lo                          -- an unrelated second output
```

Edit: interpose `add(ten)` between `double` and the collect. The
step's touched set: the new `add` node, the rebuilt path
{collect, out-binding}. What the store does when the view re-demands:

- Everything in `lo`'s cone: **hit** — no record on that path was
  rebuilt; every key is the shared old value. (Rung 1 already gets
  this whole line.)
- `offers` at `[1,2,3]`, the open's element port, `double`: **hit**
  — upstream of the edit, records shared.
- `offers` at the new `add`: **miss, computed** — one transfer
  function run (demands *numeric*, offered *numeric*; its input's
  offer was a hit).
- `offers` at the rebuilt collect: **miss, recomputed — then
  cutoff**: it offers *list-shaped* exactly as before, so anything
  downstream of `out` (a consumer in a larger program) hits on the
  equal result.
- `demands` back-propagation from `add`: **recomputed along the
  short chain** to the source; the source's accumulated demand
  gains nothing new (*numeric* was already demanded by `double`),
  so cutoff again.
- Witnesses for `out`: recomputed from the memoized pieces; for
  `lo`: hit.

Total work: a handful of transfer functions and equality checks —
against a from-scratch pass that would have re-propagated both
cones. And the same accounting serves the *suggester*: each
candidate in pick mode is a hypothetical version differing by one
step, so per-candidate checking touches per-candidate work only.

## Speculation shares the store

The editing doc promised "preview is apply-print-discard" and priced
hypothetical checking by "persistent sharing plus boundary-projection
memoization." Under this design those come out as theorems rather
than hopes:

- A **hypothetical version** is just a version — an edit applied to
  the head, never appended to the DAG. Its unchanged structure
  shares records with the head, so its queries hit everywhere the
  candidate doesn't reach.
- **Discarding needs no rollback**, because nothing was invalidated
  to compute it: entries minted under a discarded candidate are
  correct answers under their keys, either reused later (the user
  often previews then applies — the apply is then all hits) or
  evicted by ordinary cache policy.
- Ranking all candidates at a position is a batch of such
  hypothetical query sets over one shared store — the palette's
  cost is proportional to the candidates' *differences*, which are
  one edit each.

Eviction is the one genuinely new policy question the store owns
(cache discipline makes any policy *safe*; none is automatically
*good*): weak references tied to record liveness handle the
upstream-keyed tables for free — entries die with their versions —
while step-indexed tables want an explicit policy (LRU over history
distance is the obvious first cut). Open question below.

## The obligation: incremental equals from-scratch, checked

Requirement 4, restated as the discipline the implementation must
carry — three conditions, then a test protocol:

1. **Purity and key coverage.** Every query is a deterministic
   function of inputs its key covers; queries read other program
   state only through other queries or keyed records. (The
   structural-footprint regimes above make this auditable per query
   kind, rather than trusted per call site.)
2. **Fixpoints from ⊥.** Cyclic components recompute whole, never
   seeded — least-fixpoint equality by construction.
3. **Equality is real equality.** Cutoff compares with the same
   equality `Program.equal`-style canonical comparison uses —
   never "probably unchanged" heuristics.

The protocol, in the repo's own testing idiom (`Main.res` smoke
style): **the from-scratch path is the oracle.** Scripted and
seeded-random edit sequences run twice — once through the store,
once recomputing fresh at every step — asserting equal witnesses,
equal properties at every port, equal eligibility lists, at every
intermediate record. The editing doc's scripted worked sessions
(its smallest-first-step 4) are the seed corpus; random sequences
draw from the edit inventory with the same seeded-and-documented
protocol the surveys use. A debug assertion mode keeps the
comparison alive in ordinary development (recompute-and-compare on
every Nth edit), the same posture as the editing doc's "debug
builds re-verify structural invariants after every edit."

This is affordable *because* the basic implementation was kept as
the definition: the oracle is not a second implementation to
maintain — it is the same pure functions with the store removed.

## What the store is

The companion lens — what does it mean? — earns its keep here,
because the ontological one-sentence answer is what picked the
design. **The store is a cache of a pure function of the version:
semantically nothing.** Incremental's state couldn't say that — its
graph holds observers, its stabilization is the semantics of the
system it hosts. This store can be dropped mid-keystroke, rebuilt
cold, shared across branches, or shipped warm in a session file, and
the only observable is latency. That sentence is also the
reconciliation with `transformation-levels-design.md`'s "no
staleness, no invalidation" stance, which might otherwise read as
forbidding incrementality outright: what it forbids is *stored
results with authority* — results something must keep in sync. A
memo entry has no authority; the version does. Nothing is ever in
sync or out of it; it is only present or absent.

## Philosophy check

- **Abstraction is the source of truth; concreteness is a derived
  view.** The store never becomes a source of truth — enforced by
  definition (a cache), not by care. Derived views (properties,
  witnesses, completions) stay read-only and re-derivable at every
  grain rung.
- **Building blocks must build.** The grains ladder is the +1-step
  test applied to the editor's own internals: each rung adds cache
  to the previous rung; no rung rewrites the one below; the basic
  implementation survives at the bottom as the oracle. Likewise the
  query inventory grows per node kind through the same catalog that
  grows the checker and the palette — a new kind brings transfer
  functions and is incrementally checked with no store changes.
- **No bottlenecks.** Properties travel and cache individually —
  per-wire, per-query — never packed into one "analysis result"
  blob invalidated as a unit. The types doc unbundled the type;
  the store inherits the unbundling as its cutoff granularity.
- **Example first, then generalise.** The worked keystroke drove
  the decomposition; the query inventory is read off the checker's
  actual demands, not a theory of incremental computation imported
  wholesale — Incremental's concepts enter only re-keyed to what
  the step-DAG already provides.
- **Sample reality (standing method).** The whole ladder above rung
  0 is *conditional on measurement* (a confirmed lean from the
  design conversation, alongside keeping refs-by-record). At smoke-suite scale,
  from-scratch per keystroke may be fast for a long time; rung 0
  ships with timing instrumentation, and each rung is adopted when
  a measured edit latency demands it — with one stated exception:
  the suggester's per-candidate checking multiplies cost by the
  candidate count and is expected to be the first real pressure
  (the editing doc's open question 12); measure there first.

## Open questions

1. **Refs-by-record vs refs-by-id.** Kept: refs-by-record (free
   upstream keys, editing doc consistency) — a confirmed lean from
   the design conversation. The fork reopens if path-copy cost or
   serialization interning proves painful; refs-by-id + persistent
   map + explicit stamps is the worked alternative, and the query
   layer above is deliberately neutral between them.
2. **Where the memo attaches.** Lazy derived fields on records
   (sharing-tracked, GC-managed) vs external weak tables vs
   per-history-node overlays. Leaning: fields for upstream-footprint
   queries, one external table per downstream-footprint query;
   overlays rejected as reintroducing history traversal on lookup.
3. **Eviction policy** for step-keyed tables and for cached
   `version` folds on remote history nodes. Any policy is safe;
   which is good wants usage data (the instrumented sessions are the
   corpus).
4. **Content-hash keys** — the provenance-to-content upgrade for
   equal-content-different-step reuse. Deferred until a workload
   shows provenance misses that matter (cherry-pick-heavy editing
   is the candidate).
5. **Incremental fixpoint maintenance** (DRed-style) if a cyclic
   component ever grows past recompute-from-⊥. Deferred with a
   warning label: it trades away a by-construction equality.
6. **Which derived views join the store beyond checking.** The
   canonical print is global-ish (naming, statement order) — can it
   be factored per statement-group with a naming boundary, or does
   it stay rung-0 recompute? The completion lens and per-output
   codegen look like ordinary cone queries; confirm when they're
   exercised interactively.
7. **Store serialization** — cold-start-only, or warm session
   files with id+step interning? Decide with the editing doc's
   session-file format (its smallest-first-step 3).
8. **Suggester grain.** Does `eligible`'s ranking need finer
   memoization than the checker's queries it reads (e.g. caching
   per-candidate verdicts across cursor motion), or is
   per-candidate-difference work already interactive? Ties to
   editing open question 12.
9. **The history-browsing view.** Head-first orientation optimizes
   the editing loop; a history *browser* (blame, diff, replay)
   reads the DAG the other way. Its queries (diff two versions by
   id, per transformation-levels) fit the store shape, but nothing
   here designs that view.

## Smallest first step

Ordered so every rung is shippable and the oracle exists before the
first cache does:

1. **Rung 0 with instrumentation.** The editing doc's `Edit.res`
   milestone as specified — immutable working record, from-scratch
   recompute — plus per-keystroke timing counters. This is the
   basic implementation *as the definition*, and the evidence
   source for every later rung.
2. **The step-DAG spine under the editor's undo.** Replace the
   throwaway undo list with `historyNode` (step, parents, cached
   version) — no store yet, but head-first history with cached
   folds, and steps carrying their touched sets. (This is the
   editing doc's "heads into the DAG" landing, scoped to what the
   store will need.)
3. **The oracle harness.** Scripted + seeded-random edit sequences
   with recompute-fresh assertions — built *before* any memo, so it
   is green on rung 0 and stays the gate for every rung after.
4. **Rung 1: per-output cone memo** keyed on output refs — the
   one-line constructive-trace table, first real reuse.
5. **Rung 2: `offers`/`context` as lazy fields** with equality
   cutoff; the worked-keystroke accounting becomes assertable in
   the harness (count transfer-function runs per edit).
6. **Rung 3: `consumers` index + `demands`**, then wire the
   suggester's hypothetical checks through the store — the first
   rung whose adoption should be *demanded by* measurements from
   step 1, per the philosophy check.

## Proof of concept (implemented)

`src/EditorPoc.res` + `src/EditorPocTest.res` (`npm run poc`) are a
working miniature of this design, deliberately **not** built on the
flow language: the host is a simply typed lambda calculus (Int /
Bool / functions, plus Add, If, Let), and the derived information is
types plus type-error witnesses. Small enough that every mechanism
above fits in two files; faithful enough that each mechanism is the
doc's, not an analogue:

| this document                          | in the PoC                                                    |
|----------------------------------------|---------------------------------------------------------------|
| the basic implementation is the semantics | `transfer` (one pure node-local typing function); `checkFresh` = plain recursion over it, the oracle |
| the store as a cache of a pure function | `checkStored` = the *same* `transfer` wrapped in a memo; `dropStore` at any moment changes nothing but counts |
| refs-by-record, ref = upstream cone    | terms embed child records; the memo's outer key is the record pointer (a `WeakMap`, so entries die with versions) |
| keys cover everything read             | inner key = the env restricted to the record's free variables (`envSliceKey`); free vars are themselves a pointer-keyed query |
| path copy, ids kept; the step is the diff | `replaceBuild` returns (new root, replacement record, touched ids) |
| step-DAG, head-first, fold cached      | `historyNode = {step, parents, versionCache}`; caches evict, steps don't — `versionOf` refolds a dropped cache from the step's stored replacement record, reproducing ids and sharing exactly |
| undo / branch switch = cache hits      | asserted: zero transfer runs after warming                    |
| preview = a version never appended     | `previewEdit` / `commitPreview`; commit reuses the previewed version, so applying a previewed edit costs zero transfers |
| cutoff surfaces                        | the env slice: replacing a Let's bound side with a same-typed value recomputes 2 records; with a differently-typed value, exactly 2 + the nodes that read the variable |
| demand-driven locality                 | `typeAt` (the cursor query) computes the cursor's cone only    |
| the obligation, tested                 | scripted scenarios with exact transfer-run counts, plus seeded-random edit/undo/drop/evict sequences asserting incremental == from-scratch at every step |

What it deliberately does not model: the backward regime
(`consumers`/`demands` — trees make consumers trivial), fixpoints
(STLC has no cycles), the suggester's ranking, and content-hash keys
(provenance keys only, as the doc leans). Those stay design-only
until the real editor demands them.

One reading from building it: the worked-keystroke accounting in
this document held exactly — the scenario assertions are equalities
on transfer-run counts, not bounds, and they passed as computed from
the doc's own reasoning (path + fringe; slice-cutoff = readers of
the binding). The env-slice key is the part that earned its
keep — it is what makes "rebuilt binder, unchanged reads" a hit,
the tree-shaped analogue of boundary projection.
