# Learning from other languages: reactive code (Elm and the JS state libraries)

Status: comparison round — read for problems, not mechanisms; demands go
to the owning docs, nothing is decided here.

This is one in a series (begun with `effekt-comparison.md`) that reads
another ecosystem's programs and documentation against how the record
approaches the same problems, extracts *problems* — never mechanisms —
and uses them to reweight `open-problems.md`.

## The brief

The universe of reactive code is Elm and the many JS state-management
libraries — mostly the latter, since the vast majority of reactive code is
JS with some state library. These libraries are superficially similar: a
monad-like interface with varying sugar for creating reactive variables —
**nothing the record doesn't already have in the incremental flow**
(`incremental-flow-design.md`, the design of a variable whose value is
derived and re-derived over time). So the round does not re-litigate the
core. It verifies that premise against the corpus (§0) and then spends its
attention on seven specific questions where the interesting differences
live:

1. Partial updates to a larger structure.
2. Asynchronous inputs, such as over the network.
3. Combining variables with events.
4. Sending new values to structures outside the reactive system, such as
   the DOM.
5. Determining that a variable is not being used and need not be updated.
6. Inhomogeneous variables or event streams — a variable that only updates
   in a certain sequence, an event that can occur only once, events that
   must alternate, events valid only when a variable is in a given state.
7. Huge fan-out where each consumer needs only a tiny subset of changes,
   such as keyed changes.

## What was read

All fetched from primary sources; doc websites are proxy-blocked here, so
markdown was read from the projects' own repositories.

- **Elm**: "A Farewell to FRP" (the 0.17 announcement removing signals)
  and the official guide's architecture, effects (HTTP, time), and ports
  chapters, with complete example programs.
- **Signals world**: the TC39 Signals proposal README (the standards-track
  distillation of the genre); MobX; SolidJS (signals, memos, effects,
  stores, resources, `<For>`/`<Index>`, `on`, `batch`, `untrack`, roots
  and cleanup); Vue (reactivity, computed, watchers); Preact Signals; and
  Reactively's algorithm document (the dirty/check/clean coloring the TC39
  proposal cites).
- **Streams/architecture world**: RxJS 7 guides and the JSDoc semantics of
  the load-bearing operators; Redux (immutable update, normalization,
  selectors) with Immer (produce, patches); XState v5 (transitions,
  guards, final states); React Query (defaults, keys, invalidation); Recoil
  (atomFamily, selectorFamily).

## Reading rules

1. **Output is problems, never mechanisms.** The JS ecosystem's mechanisms
   are additionally shaped by a constraint we don't have — retrofitting
   reactivity onto a host language that hides data flow — so their
   machinery often solves problems our substrate cannot even express.
   Distinguishing "their problem is real for us too" from "their problem is
   JS" is this round's main filter.
2. **Different core, so bolting on clashes** — but here the core is *shared
   at the semantic level* (the incremental flow is exactly this genre's
   cell/computed/effect triad). The *discovery mechanism* differs: they
   infer the dependency graph by tracing execution; we draw it. Most of
   their documentation weight sits on the inference machinery and its
   failure modes — which reads, for us, as a bill for invisible wires.
3. **Maturity polish.** All documentation, all curated. But this
   ecosystem's docs are unusually confession-rich — pitfall pages, "common
   mistakes" sections, capitalized warnings — and those confessions are the
   closest thing documentation offers to field evidence.
4. **The brief's premise is itself a claim to check** (§0), not assume.
5. **One ecosystem, many libraries.** Where several libraries independently
   converge on an answer, that is noted — the strongest signal this corpus
   can produce.

## §0. The premise, verified: the core is the incremental flow

The TC39 Signals proposal — the ecosystem distilling its common core for
standardization — specifies: automatic dependency tracking; **lazy
evaluation** (computations "are only evaluated when their value is
explicitly requested"); **memoization**; custom `equals` (Object.is
default); glitch-freedom by being "pull-based, rather than push-based";
dynamic dependency sets (a change to a value read only on the branch not
taken "will not cause the computed Signal to be recalculated, even when
pulled"); and a "push-pull construction" (pull values, push
notifications). Point for point, this is `incremental-flow-design.md`: the
derived var, laziness, per-generation memoisation, cutoff (open question
2), switch-join as the dynamic dependency, and the frozen-generation
account of glitch-freedom — independently derived, including the reasoning
("At the time the framework schedules the rendering of the UI, it will
pull the appropriate updates"). The premise holds: the monadic core needs
nothing new.

Elm supplies the stronger version of the same verdict: the one language in
the corpus that *had* first-class reactive variables **removed them.** "A
Farewell to FRP" (0.17): "everything related to signals has been replaced
with something simpler and nicer… we had lots of folks who became
excellent Elm programmers without ever really learning much about signals.
They were not necessary." And the self-diagnosis: "I had no idea my thesis
had so much in common with synchronous programming languages at the time,
but the connections are quite striking. I might argue that Elm was *never*
about FRP." (Lucid Synchrone — the same synchronous-dataflow lineage the
register design already cites for its Delay/`pre` precedent.) The
architecture that replaced signals is worked in §8 — it is drawable in the
record's existing vocabulary, one register at its center.

**One structural difference survives the premise, and it is the clash
record's centerpiece (finding 10a).** Every library discovers the
dependency graph by **tracing execution**: MobX tracks any observable
dereferenced during a tracked function; Vue tracks property access through
proxies; Solid warns that a handler passed as a signal "will not respond to
the changes of that signal." The record's stance is that the wiring
already *is* the dependency graph (`incremental-flow-design.md`: "the
diagram the programmer drew *is* that graph"). Auto-tracking is the
invisible-wire costume of that fact, and the ecosystem pays a documented
bill for it:

- **async breaks tracking** — Solid: "By the time the `count` getter is
  triggered within the `setTimeout`, the global scope no longer has a
  registered subscriber"; Vue: "only properties accessed before the first
  `await` tick will be tracked";
- **destructuring silently severs it** — Vue: "we will lose the reactivity
  connection";
- and every library ships escape hatches (`untrack`, `peek`, explicit
  `on`) to *turn the inference off*.

A whole genre of pitfalls that cannot be drawn.

## The seven questions

### Q1. Partial updates to a larger structure

**The ecosystem's answers — five mechanisms, one shape.**
(a) *The hand-written form*: Redux's Immutable Update Patterns page teaches
the spread pyramid as a core skill — updating
`state.first.second[someId].fourth` takes four nested spreads, and the page
admits "each layer of nesting makes this harder to read, and gives more
chances to make mistakes," then catalogs the two canonical bugs (aliased
references; one-level-deep copies).
(b) *The recording proxy*: Immer's `produce` gives a draft, records
mutations, rebuilds with structural sharing — and, decisively,
`produceWithPatches` **returns the changes as data**: `[{op: "replace",
path: ["age"], value: 34}]` plus inverse patches, documented for
"incremental updates with other parties," undo/redo, and *fork-and-rebase*.
(c) *The live proxy graph*: Vue/MobX/Solid stores make the structure itself
reactive, so a nested mutation *is* the update — with per-property
granularity (next paragraph).
(d) *The path setter*: Solid's `setStore("users", [2, 7, 10], "loggedIn",
false)` — multi-locus update by index list, range, or predicate,
auto-batched.
(e) *The boundary diff*: Elm and React don't update partially at all —
recompute the whole view value and let the runtime diff it (§4).

**Against the record.** This is the focused-update row's fourth consecutive
round of witnesses (focused update = writing a result back into a selected
part of a larger structure), in the reactive costume — and the spread
pyramid is exactly the "imperative costume" the row's evidence-owed
question named, here *institutionalized* as an official documentation page
teaching it (documentation, not a field sample; it feeds the frequency
question without discharging it). Two pieces are new for the row.
**Patches close the loop between update and observation**: Immer shows the
focused update's natural output is a *delta as data* (op/path/value +
inverses) — the same path-shaped loci jq computes, now flowing forward as
the thing consumers react to. And **granularity coupling** (with Q7): in a
reactive setting, the update's loci are also the invalidation's keys —
Solid states it exactly ("The path syntax… triggers reactivity only for
effects that depend on the new index or properties," versus the spread
which "triggers reactivity for all effects that depend on the array"). The
focused-update row and the incremental flow's collections layer are two
ends of one pipe: loci in, keyed invalidations out.

### Q2. Asynchronous inputs

**The ecosystem's answers.** RxJS makes the async-arrival policy a *choice
of operator*, and its four flattening strategies are the corpus's sharpest
single artifact:

- **switchMap** — a new inner Observable stops the earlier one
  (replace/interrupt);
- **mergeMap** — all concurrently, with an optional `concurrent` maximum;
- **concatMap** — waiting for each to complete before the next (a serial
  queue), with the doc's own warning: if source values arrive faster than
  the inner Observables complete, "it will result in memory issues as inner
  Observables amass in an unbounded buffer";
- **exhaustMap** — ignores every new projected Observable while the
  previous one is still running (drop-while-busy).

Elm routes all async through data: a `Cmd` issued from `update`, whose
result returns as an ordinary `Msg` (`GotText (Result Http.Error String)`),
folded into a Model that is itself a state union (`Loading | Failure |
Success String`). The resource layer (Solid `createResource`, React Query)
wraps an async source as a var-with-metadata: Solid's Resource carries
`state: "unresolved" | "pending" | "ready" | "refreshing" | "errored"`
**keeping the previous value while refreshing** (`latest`); React Query
adds staleness as policy (cached data stale by default, refetch on
mount/refocus/reconnect, retried 3 times with exponential backoff,
`gcTime`, structural sharing to stabilize references).

**Against the record.** Three rows collect.

- **The four flattening strategies are the concurrency menu shipped as
  *the* async lingua franca**: switchMap is the race/interrupt (survey 3's
  first-of dominance), concatMap is `serial`, mergeMap with `concurrent`
  is `bounded(n)`/`unbounded` — the collect-concurrency dimension (`serial
  | keyed | bounded(n) | unbounded`) appearing operator-for-operator, with
  **exhaustMap a member the record's menu hasn't named**
  (drop-newest-while-busy, a *non-queueing* serial; handed to the
  concurrent collect's round).
- The concatMap warning is the backpressure/pacing hole again — sighting
  six — and React Query's retry-with-backoff is the policy layer (functions
  row) wearing query-config clothes, its second witness as furniture.
- The resource shape — async state as a *case-typed var* with the previous
  value retained across refreshes — confirms
  `incremental-flow-design.md`'s `var<option/result>` stance (the
  absence/failure is data that varies) while adding one demand its
  collections/`changes` questions should hold: **staleness as policy**
  (fresh-until-T, refetch-on-signal) is a shipped vocabulary layer between
  the async source and the hold.

### Q3. Combining variables with events

**The ecosystem's answers.** The distinction itself is stated best by the
corpus: TC39 — "Signals represent a cell of data — just the immediate
current value (which may change), not a stream of data over time. So, if
you write to a state Signal twice in a row… the first write is 'lost'…
This is understood to be a feature rather than a bug — other constructs
(e.g. async iterables, observables) are more appropriate for streams." RxJS
— "an event stream of birthdays is a Subject, but the stream of a person's
age would be a BehaviorSubject" (Subject/BehaviorSubject = event-vs-var as
two classes). The combination forms are a stable trio:

- **combineLatest** — recompute from latest values whenever *any* input
  emits (with the caveat that it "will actually wait for all input
  Observables to emit at least once," losing early values);
- **withLatestFrom** — compute "only when the source emits" (read variables
  at an event);
- **sample** — emit the source's latest at a notifier's firings (read *a
  variable* at an event, dropping the event's own payload).

State accumulates via **scan** ("like reduce, but emits the current
accumulation state after each update," seed optional), and
**distinctUntilChanged** suppresses non-changes. Elm needs no combination
forms at all: every event becomes a `Msg`, every `Msg` folds into the Model
via `update`, and anything "combined" is just two fields of one record.

**Against the record.** Question fully covered, name for name:
combineLatest is the static join of vars (the concurrent join — and its
wait-for-all caveat is independent confirmation that the initial value is
load-bearing: a var must be born readable, which is exactly what
`hold(initial, …)` enforces and combineLatest's lost-early-values behavior
fails); withLatestFrom/sample are the sample-at-event (the incremental
doc's third consumer shape, "a one-shot read"); scan-then-hold is the
mutation boundary's register verbatim (down to the optional seed, matching
the BQN fold finding); distinctUntilChanged is cutoff surfacing as a stream
operator (open question 2's "becomes observable through `changes`" — here
it *is* an operator on the changes side). The hold/changes pair from the
record is the Subject/BehaviorSubject split with the direction of
derivation reversed: they class the *subjects*; we class the *boundary
crossings*. Nothing to add beyond confirmations — this is the question the
record was already strongest on.

### Q4. Sending values outside the reactive system

**The ecosystem's answers.** The standards proposal *declines the
question*: "The Signal API does not include any built-in function like
`effect`. This is because effect scheduling is subtle and often ties into
framework rendering cycles… which JS does not have access to." What it
provides instead is a two-stage watcher (a synchronous `notify` during
which "no Signal can be read or written," expected to schedule real work
later) — scheduling deliberately left to frameworks. The frameworks then
split into two poles:

- **Recompute-and-diff**: Elm and React re-derive the whole view as a value
  and let the runtime compute the minimal DOM change.
- **Fine-grained push**: Solid compiles templates to real DOM nodes and
  updates them with fine-grained reactions — no VDOM; each signal's
  consumers write their DOM nodes directly.

Around both poles, the same apparatus: effects with cleanup (Solid
`onCleanup`, Preact's teardown, RxJS's `unsubscribe`, MobX disposers with
"strongly recommend to always use the disposer… Failing to do so can lead
to memory leaks"), flush-timing knobs (Vue's `flush: 'post'`/`'sync'`;
MobX custom `scheduler`/`delay`; Solid effects "after the current
rendering phase… before the browser paints"), and — everywhere —
**ordering disclaimers**: "MobX does not guarantee the order in which
reactions will be run"; Solid: "The order of runs among multiple effects is
not guaranteed." Elm's outbound boundary is different in kind: **ports** —
typed message channels (`port sendMessage : String -> Cmd msg`), with the
guide's philosophy: "Ports are about creating strong boundaries! Definitely
do not try to make a port for every JS function you need… focus on
questions like 'who owns the state?'"

**Against the record.** This is the Tier-1 IO/effects hole, acknowledged
*by the standards proposal itself* — the ecosystem's common core ships
without an effect construct because scheduling semantics are the hard part.
The record's assets and debts line up precisely: the `changes`-drain
observer is the record's counterpart to the watcher (with the microtask
adapter playing the two-stage scheduler, "push of demand, not push of
values"), and the incremental doc already forbids effects inside tracking
contexts — the same constraint as "no Signal can be read or written during
notify," derived for the same re-entrancy reason. What the corpus adds:

- The two output poles are both *drawn programs* for us —
  recompute-and-diff is a derived view feeding a runtime **focused update**
  (the diff is a patch stream — Q1's loop closing at the output boundary),
  while fine-grained push is per-var `changes` drains — so the pole choice
  is per-consumer wiring, not a language commitment.
- Universal effect-ordering disclaimers are the mirror of the record's IO
  thread (ordering *drawn* where they have a disclaimer).
- The flush-timing knob family (pre/post/sync/custom scheduler) is
  generation granularity (incremental open question 3) surfacing as API —
  evidence the knob is real and per-consumer, not per-graph.
- Elm's ports are the record's FFI source/sink pair with a design stance
  attached (few, owned, message-shaped boundaries — not call-shaped shims).

### Q5. Knowing a variable isn't being used

**The ecosystem's answers.** Convergence is total; only the costume varies.
MobX: computeds "evaluate lazily… If they are not observed by anything,
they suspend entirely" (with `keepAlive` as the documented memory-leak
risk). Preact: "lazy by default and automatically skip signals that no one
listens to," plus watched/unwatched callbacks "useful for… start/stop
expensive background operations." TC39: `watched`/`unwatched` lifecycle
hooks, `hasSinks` liveness introspection, sinks not even linked until
watched, and "only watched Signals need to be cleaned up… unwatched
Signals can be garbage-collected automatically." RxJS: cold-by-default
observables; `refCount` (starts when the first subscriber arrives, stops
when the last leaves); `shareReplay`'s documented footgun (the inner
ReplaySubject "will not be unsubscribed (and potentially run for ever)").
React Query: inactive queries garbage-collected after `gcTime`. Elm: "The
connection is opened if anyone is subscribed to it, and it is closed if no
one needs it anymore." The interior algorithm is also convergent:
Reactively's dirty/check/clean coloring — push a *definitely-changed* flag
to children and *possibly-changed* to descendants, then on read walk up
(`updateIfNecessary`) to find whether any actual change survives the
equality cutoffs — which is TC39's `~dirty~`/`~checked~` state machine,
cited to the same source.

**Against the record.** The necessity frontier
(`incremental-flow-design.md`, "The push model, and the demand problem") is
confirmed as *the* shipped shape of the genre — every library maintains a
watched region with lifecycle events at its edge, exactly the
registration/deregistration events the record derived from pending pulls;
the TC39 watched/unwatched hooks are those events as public API. Two
sharpenings travel back to the row:

- The ecosystem's interior algorithm is the **dirty/check/clean
  refinement**: two grades of staleness (definite vs possible) so
  pull-verification can stop at the first surviving cutoff. This sits
  *between* the record's "value-free dirty bit" (analyzed and found
  insufficient) and full push-with-values, and at UI scale it evidently
  suffices. It belongs in the row's options as the intermediate point,
  with the record's fan-out analysis (dirt still propagates past a cutoff
  that push-with-values would stop at) marking where it stops being enough.
- The GC coupling is stated cleanly by TC39 (watched ⇒ hold alive;
  unwatched ⇒ collectable; "most frameworks today require explicit
  disposal") and by MobX's disposer warnings — the record's linger/teardown
  questions should note that liveness and memory are the same frontier, and
  that the ecosystem's chronic leak class (undisposed observers) is what the
  structural no-bare-read answer exists to prevent.

### Q6. Inhomogeneous variables and event streams

**The ecosystem's answers.** Inside the reactive cores: almost nothing, and
the extraction confirms the absence is real, not a fetch gap. What exists
is scattered and single-purpose — MobX `when` (fire once when a predicate
holds, then dispose), Vue `once: true` watchers, Solid `onMount`, RxJS
`take(1)`/`first` (with the telling nuance that `first` *errors* on an
empty completion where `take(1)` completes), `pairwise`, `concat`. The one
protocol the stream world states is its own lifecycle grammar — the
Observable contract, written as a regex: "`next*(error|complete)?`… If
either an Error or Complete notification is delivered, then nothing else
can be delivered afterwards." Everything more structured lives *outside*
the reactive core in a separate library category: **statecharts.** XState:
"A guarded transition is a transition that is enabled only if its `guard`
evaluates to `true`"; "only the active finite states are checked to see if
any of them have a transition for that event" — events valid only in
certain states, as the category's foundational semantics; and **final
states**: "When a machine reaches the final state, it can no longer receive
any events… Final states can have `output` data, which is sent to the
parent machine when the machine terminates." The rationale is the record's
own bar in different words: "Using state machines makes it easier to find
impossible states and spot undesirable transitions." Elm reaches the same
place with data: the Model *is* the state union (`Loading | Failure |
Success`), the view dispatches on it, and subscriptions are a *function of
the model* (the guide's exercise: pause the clock by turning `Time.every`
off), so the active source set varies with state.

**Against the record.** The question lands on ground the record has been
circling for three rounds: the custom-flows lifecycle pattern ("each
segment a state with its valid operations"), the Raku round's event-grammar
finding, and the **custom-protocol-flows probation** in
`tough-use-cases-design.md` ("one demand; watch for a second"). This corpus
supplies the second demand in the strongest form documentation can: an
entire shipped library *category* exists because reactive cores lack
protocol vocabulary — state-gated events (guards), once-only (final states;
`when`), sequencing (hierarchical states) are its founding features, and
Elm independently re-derives the same structure as the Model-union idiom
plus state-dependent subscription sets. Per the standing rule the
probation's sighting must come from field code (the owed UI sample — which
now carries a third question: how much real event-handling is
statechart-shaped?), but the probation's "watch for a second" should be
read alongside this: the second demand has a whole ecosystem answering it.
Two smaller notes: final-states-with-output is the end-when discharge
(terminator payload to the parent) confirmed from the statechart side; and
state-dependent subscriptions are a *switch-join over source openers* — the
record can already draw Elm's answer, worth recording as a worked
correspondence. The alternating/once-only event *typing* the question asks
about — enforced, not simulated — remains vocabulary nobody in this corpus
has; the record's candidate home (protocol flows as flow kinds with drawn
lifecycles) stays a genuine open, now with sharper demand evidence.

### Q7. Huge fan-out with keyed consumers

**The ecosystem's answers.** Convergent again, in four costumes.

- **Keyed families of variables**: Recoil's `atomFamily` — "a map from the
  parameter to an atom," with the payoff stated exactly: "they all maintain
  their own individual subscriptions. So, updating the value for one element
  will only cause React components that have subscribed to just that atom to
  update"; `selectorFamily` the same for derived values, with cache
  eviction policies.
- **Normalization plus memoized selectors**: Redux's normalized tables
  (`byId` + `allIds`), then reselect memoization — whose documented
  weakness is the point: "createSelector only has a default cache size of
  1… per each unique instance," so keyed reuse requires the
  selector-factory-plus-`useMemo`-per-component dance.
- **Per-key tracking in the store itself**: MobX `observable.map`
  ("Observable maps support observing entries that may not exist"); Vue's
  per-(object, property) subscription maps; Solid stores' lazily-created
  per-property signals.
- **Keyed async**: React Query's hierarchical keys — `['todos', 5]`,
  deterministic hashing, and *prefix invalidation*
  (`invalidateQueries({queryKey: ['todos']})` hits `['todos', {page: 1}]`).

And for keyed *lists*, Solid's `<For>`/`<Index>` pair states a fork the
genre usually leaves implicit: `<For>` is keyed by item identity (the index
is a signal; items move), `<Index>` by position (the item is a signal;
content changes in place).

**Against the record.** This is the incremental-collections layer
(`incremental-flow-design.md` open question 6, deferred "until a use case
forces it") receiving its shipped shapes, and the keyed lane arriving on
the incremental side. The composite picture the corpus draws: a keyed
collection-var wants to be a **family of per-key vars minted on demand**
(atomFamily's map-from-parameter, MobX's observable-absent-keys), whose
consumers subscribe per key (the fan-out answer), whose updates arrive as
path/key-shaped deltas (Q1's patches — the loci/keys coupling), and whose
invalidation composes by key *prefix* (React Query — and a key-path prefix
rule is provenance's prefix rule wearing runtime clothes). The
`<For>`/`<Index>` fork is a real semantic question the layer must answer,
not an implementation detail: tracking by identity vs by position are
different programs (in our vocabulary: is the key the element's identity or
its provenance?). And reselect's cache-size-1 dance is this question's
assembly-language exhibit — a keyed derived var hand-built from a memoizer,
a factory, and a per-consumer hook, three constructs to state "derive per
key." Handed whole to the collections layer's eventual round, jointly with
the keyed-collect material from the prior three rounds (group-as-flows;
classify-then-place; lanes).

## §8. The Elm Architecture, drawn

The corpus's one full *architecture* deserves the worked-example
treatment, because it assembles six of the record's constructs and nothing
else. The loop ("1. Wait for user input. 2. Send a message to `update`. 3.
Produce a new `Model`. 4. Call `view`… 6. Repeat!"), in record vocabulary:

- **Sources** (subscriptions, DOM events, HTTP responses, port messages)
  are source openers; the subscription set is a switch-join over sources,
  selected by the model's current value (`subscriptions : Model -> Sub
  Msg`).
- **`Msg`** is one merged, case-typed event flow (`type Msg = Increment |
  Decrement | GotText (Result …)` — the merge of all sources, tagged).
- **`update`** is the register: a fold over the Msg flow carrying the Model
  — scan-then-hold, exactly the mutation boundary's composition. Its second
  output — the `Cmd` — is **effects as collected values** (the update
  *returns* a description; the runtime performs it; results re-enter as
  Msgs). This is the pending-update-list pole from the XQuery round, second
  shipped witness, now with the loop closed: effect results are ordinary
  events.
- **`Model`** is the single root var; **`view`** is one derived var; the
  runtime's VDOM diff is a focused update computed at the boundary (Q4's
  recompute-and-diff pole).

That the ecosystem's most-taught reactive architecture is *one register
plus one case split plus effects-as-data* — with its author's verdict that
the reactive-variable layer above it "was not necessary" — is the round's
cleanest direction signal: the record's weight distribution (registers,
case flows, and the effects boundary ahead of exotic var combinators)
matches where this ecosystem landed after a decade.

## Findings

**Finding 1 — the premise verified; auto-tracking is the structural
difference, and it bills.** The TC39 core matches
`incremental-flow-design.md` point for point (laziness, memoization,
cutoff-with-equals, dynamic deps as switch-join, pull-model glitch-freedom);
Elm removed reactive variables entirely. The one deep difference: the
ecosystem *infers* the dependency graph from execution traces where the
record draws it — and pays a documented bill (async severs tracking;
destructuring severs it; branch-dependent dep sets surprise;
`untrack`/`peek`/`on` exist to fight the inference). No score movement for
the core; the clash record carries the bill.

**Finding 2 — partial updates: the reactive costume of focused update, plus
the loci/keys coupling.** The spread pyramid institutionalized as official
documentation; Immer's draft-recording with **patches as data**
(op/path/value, inverses, fork-and-rebase); Solid's multi-locus path
setters. New structure for the focused-update row: the update's natural
output is a delta stream, and in a reactive setting **update loci =
invalidation keys** (Solid's own granularity statement) — the focused-update
row and the incremental collections layer are two ends of one pipe. Feeds
(without discharging) the row's frequency condition.

**Finding 3 — the four flattening strategies are the concurrency menu as
async lingua franca.** switchMap/concatMap/mergeMap(+max) map onto
interrupt-race/`serial`/`bounded-unbounded`; **exhaustMap names a member
the record's menu lacks** (drop-newest-while-busy, a non-queueing serial) —
handed to the concurrent collect's round. concatMap's unbounded-buffer
warning is pacing/backpressure sighting six; React Query's
retry/backoff/staleness config is the policy layer's second
witness-as-furniture, and **staleness as policy** (fresh-until,
refetch-on-signal) is a new scope note for the async/incremental boundary.

**Finding 4 — vars × events: fully covered, with shipped names.** TC39's
"lossy" cells and RxJS's birthday/age line state the var/event split;
combineLatest = static join (its lost-early-values caveat confirming the
load-bearing initial value), withLatestFrom/sample = sample-at-event, scan
= the register (optional seed, again), distinctUntilChanged = cutoff
observable on the changes side. Confirmations only — the record's strongest
question.

**Finding 5 — output: the Tier-1 hole acknowledged at standards level; two
poles, both drawable.** TC39 ships no effect construct ("effect scheduling
is subtle") — the ecosystem's common core stops exactly at the record's
biggest open row. Recompute-and-diff (Elm/React) vs fine-grained push
(Solid) are per-consumer wiring choices in drawn vocabulary (derived view +
boundary focused-update vs per-var `changes` drains). Universal
effect-ordering disclaimers are the IO thread's mirror; the flush-timing
knob family is generation granularity (incremental Q3) as per-consumer API;
Elm's ports supply the FFI-boundary stance ("strong boundaries," few and
message-shaped). Elm's `Cmd` is the second shipped witness for
effects-as-collected-values, with the loop closed through ordinary events.

**Finding 6 — liveness: the necessity frontier is the genre's shipped
shape; dirty/check/clean is the intermediate point.** Watched/unwatched
lifecycle hooks (TC39, Preact), computed suspension (MobX), refCount (RxJS),
inactive-query GC (React Query), subscription-driven resources (Elm's
WebSocket) — the frontier with registration events at its edge, everywhere.
The interior algorithm (Reactively's coloring; TC39's `~dirty~`/`~checked~`)
adds a two-grade staleness refinement between the record's rejected
value-free dirty bit and its push-with-values target — adequate at UI
scale, still stopped short of cutoffs by the fan-out analysis. Liveness and
memory are one frontier (watched-holds-alive; the ecosystem's chronic
undisposed-observer leaks are what no-bare-read prevents structurally).

**Finding 7 — protocols: the cores have nothing; the answer is a shipped
library category.** Inside the reactive cores, only scattered once-only
utilities (and the Observable contract's own lifecycle regex). The
structured answer is statecharts — guards (state-gated events),
enabled-transitions-per-active-state, final states with output (= the
end-when discharge, confirmed from a new side), hierarchy — an entire
category founded on what the question asks for; Elm re-derives it as the
Model-union idiom plus model-dependent subscription sets (a switch-join over
source openers, drawable today). The custom-protocol-flows probation gains
its awaited second demand at category strength — pending the field sighting
only the owed UI sample can supply (that sample now carries the
statechart-shaped question explicitly). Enforced once-only/alternating event
*typing* remains open vocabulary everywhere.

**Finding 8 — keyed fan-out: the collections layer's shipped shapes.**
Keyed families of vars minted on demand (atomFamily, observable.map's absent
keys), per-key subscriptions as the fan-out answer, hierarchical keys with
prefix invalidation (provenance's prefix rule in runtime clothes), deltas as
data (Q1's patches), and the `<For>`/`<Index>` identity-vs-position fork as
a semantic question the layer must answer. Reselect's cache-size-1 factory
dance is the question's assembly-language exhibit. Handed to
`incremental-flow-design.md` question 6 jointly with the keyed-collect
material of the prior rounds.

**Finding 9 — The Elm Architecture is one register plus one case split plus
effects-as-data.** Worked in §8; drawable end to end in existing vocabulary
(sources under a model-selected switch-join → merged case-typed Msg flow →
register with a Cmd output → root var → derived view → boundary diff). With
Elm's own verdict that the signal layer above it was unnecessary, this is
the round's direction signal: the record's weight distribution already
matches where the ecosystem landed.

**Finding 10 — what not to import (the clash record).**
(a) *Auto-tracking* — dependency graphs inferred from execution traces: the
invisible wire at ecosystem scale, with a documented footgun bill (async,
destructuring, branches) and dedicated escape hatches to disable it; drawn
wires dissolve the genre.
(b) *Unspecified effect ordering* — "no guarantee" as documented semantics;
ordering belongs drawn (the IO thread).
(c) *Lifetime by refcount convention* — `shareReplay`'s runs-forever
default, `keepAlive` leaks, undisposed observers: liveness rules living in
per-operator flags rather than structure.
(d) *Keys by serialization* — value-equality via `JSON.stringify` (React
Query's deterministic hashing, Recoil's serializable params): meaning by
stringification; keys should be values with an equality, not strings by
convention.
(e) *Proxy identity splits* — "only the proxy is reactive" (Vue),
raw-vs-draft escapes (Immer), `.peek()`: two identities for one datum, each
with different semantics.
(f) *Memoization scoped by call site* — reselect's cache-size-1: sharing
semantics determined by where a function object happens to be allocated.

## What this round changes in `open-problems.md`

- **Incremental flows row**: the evidence round — TC39 point-for-point
  confirmation of the core; the necessity frontier as the genre's shipped
  shape with watched/unwatched hooks as the registration events;
  dirty/check/clean as the intermediate algorithm option; flush-timing knobs
  as per-consumer generation granularity; staleness-as-policy noted; the
  collections question (Q6 there) gains its shipped shapes (keyed var
  families, per-key subscription, prefix invalidation, delta streams, the
  identity-vs-position fork). Scores unchanged; the remaining list is much
  sharper.
- **IO/effects (Tier 1)**: the TC39 punt as standards-level
  acknowledgment; Elm's `Cmd` as the second effects-as-data witness (loop
  closed through events); the two output poles both drawable; ordering
  disclaimers as the IO thread's mirror; ports as FFI-boundary stance.
  Scores unchanged.
- **Focused update row**: the reactive costume (spread pyramid
  institutionalized; Immer patches as deltas-with-inverses; path setters)
  and the loci/keys coupling with the collections layer. Feeds the
  frequency condition without discharging it. Scores unchanged.
- **Concurrency row**: the flattening strategies as the collect-concurrency
  menu shipped; **exhaustMap** added to the species menu as
  drop-while-busy; pacing sighting six (concatMap's buffer warning); served
  flow notes (React Query staleness/retry as policy furniture). Scores
  unchanged.
- **Functions/reuse row**: policy layer's second witness-as-furniture (React
  Query config). Scores unchanged.
- **End-when (Tier 3)**: final-states-with-output as a statechart-side
  discharge confirmation. Scores unchanged.
- **Evidence owed**: the UI/browser sample gains the statechart-shaped
  question (protocols; custom-protocol-flows' probation awaits its field
  sighting there).

## Next rounds of this genre

The standing list is now one: the **beginner-first round** (Scratch/
HyperCard lineage — the discoverability bar as the whole language). The
uses-not-showcases variant remains the right follow-up for the two rounds
with library-shaped corpora (this one and jq): real application state code —
reducers, stores, effect wiring in the wild — is the sample that would
discharge the conditions this round could only feed (the focused-update
frequency question; the statechart-shaped share of event handling; whether
application code actually swaps providers).
