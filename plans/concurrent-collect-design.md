# The Concurrent Collect: Settlement Order and the Completions Flow

Status: exploration — leanings, not adopted.

The problem: you have a walk that spawns async work per element — a server
handling requests, a pool draining devices, a scraper fetching URLs — and
you want the results as they finish, without the walk stalling on each one
in turn. This document works out the one node that provides it. "Concurrent
collect" turns out to be a misleading name (it is not a collect), but it is
the name the problem was filed under (`tough-use-cases-design.md`,
inventory item 1).

Most of what looked like a menu of concurrency species — `serial |
keyed(key) | bounded(n) | unbounded` — dissolves into existing vocabulary.
The exercise here is to finish that dissolution: name the one node that
remains, and follow `bounded(n)`'s resistance to its conclusion. Nothing
here is implemented; the async runtime it presumes does not exist yet.

Terms used throughout: an **async cell** settles (resolves/rejects) once;
**settlement** is that event; **sequential-is-nesting** is the async
model's rule that a body consuming an async value nests inside it
(`async-flow-design.md`); **availability** is how a barrier's per-firing
values cross when provenance already tracks the correspondence
(`barrier-value-crossing-design.md`); a **keyed partition** turns data into
lanes — one sub-diagram against a representative lane
(`collect-family-design.md`); **paced** is the flow op that spaces a walk
by a per-firing async's settlement (`source-openers-design.md`). Spellings
in examples are provisional strawmen.

## What the record already fixes

Five constraints this design must respect:

1. **Most of the species menu is already wiring.** Worked against the
   visual test: `keyed` decomposes into a group-by open with per-lane
   serial drains, lanes concurrent among themselves; `unbounded` is the
   degenerate group-by (every firing its own lane); `serial` is no
   construct at all — the default collect, unmarked; only `bounded(n)`
   resists, as a resource.
2. **The keyed half has its construct.** "Group-by open" is now the
   **keyed partition** — lanes as data-determined cells, uniform wiring
   over a representative lane, first-appearance order, four readouts
   (`collect-family-design.md`). Keyed concurrency should be that
   construct's async instantiation or nothing.
3. **The crossing rules are decided (as leanings).** Product barriers
   carry values by availability; sum barriers and settlements mint; minted
   outputs co-locate on one node exactly when the node's law ties them
   together (`barrier-value-crossing-design.md`). Any port proposed here
   must come from those two mechanisms, not from convenience.
4. **Dynamic contender sets are redirected here.** Race's arity is drawn
   structure; runtime-many cells are not a drawable partition; the flow
   constructs own dynamic sets (`race-barrier-design.md`, dead end 5). So
   this is where settlement observation over a set not known at authoring
   time lives — and there is no drawn lowering to defer to.
5. **Serial composition is structural.** A body that consumes an async
   value nests inside it; sequential is nesting, per firing. Whatever
   "serial vs concurrent" means, it is a difference between drawings, not a
   mode bit.

## Serial is a drawing, and "collect species" was the wrong frame

Start with the unmarked default. A walk whose per-firing work involves an
async value — a handler that awaits a database call, a capture that drains
a device — is drawn with the async uncollect *inside* the walk: open the
firing's async, hang the rest of the body off its value port.

```
open requests => req, ~S
handle(req) in ~S => resp          -- async opened inside the walk
resp -> deliver
```
The walk's next pull happens after the body finishes with this firing —
which, because the body's value is needed, is after settlement. One firing
in flight at a time, and the reader can see why: the settlement is on the
path to the next pull. That is everything `serial` promised, with no
keyword. Survey 3 confirms the practice (finding 3.7: one lock in thirty
draws, hand-enforcing exactly this).

So the real question is the *opposite* one: **what severs that nesting?**
What says "the settlement of firing N's body is *not* on the path to pull
N+1"? It cannot be a mode on a collect — a mode would change which program
the drawing is without changing the drawing. It has to be a node that
visibly reroutes the settlement out of the walk's path. That node is the
subject here.

## The node: settlement order is the mint

**Form.** One node, a binary flow operation in the family of end-when,
interrupt, and paced: a **subject flow** in, plus a per-firing **async
value** (the body) computed in the walk; one flow out — the **completions
flow**.

```
open requests => req, ~S
handle(req) in ~S => body          -- async<Response>, per firing
~S, body ~> settle => ~C, res      -- completions flow + settled result
```
`settle` reroutes each body's settlement off the walk's pull path; `~C`
fires once per body as it settles, `res` carrying that body's result.

**Law.**

- Firing N of the subject demands the body's *construction and start*, not
  its settlement: the walk advances when the body is started (start is
  synchronous), so bodies overlap exactly as far as demand and the source
  allow.
- The completions flow fires **once per subject firing whose body settles,
  at its settlement, in settlement order**. The event loop serialises
  settlements, so a schedule gives a well-defined order; across schedules
  it is not defined, and the language promises nothing more — the same
  honesty stance as race, one level up.
- The completions flow **terminates when the subject flow has terminated
  and every started body has settled** — the drain reading (see
  "Termination").

**What crosses, by the two mechanisms.** Each completion firing
corresponds to exactly one subject firing (the firings-correspond sentence
flatten-join and end-when already own). So the subject walk's per-firing
values — the device path, the minted token, the requester — are readable
per completion firing by **availability**: provenance tracks the
correspondence, and order was never what provenance tracks, so the
reordering costs nothing. What availability cannot supply is the body's
*settled result*: contender-style, the resolution exists nowhere upstream
as a wire. That is the node's **mint**, its shape decided by the crossing
round's exactly-one discharge: one value output per completion firing,
**the settled sum** — `Ok(x) | Fail(e)`, case-split downstream like any
data. A body that fails is a completion *carrying* the failure, not a
propagated terminator: the supervisor consumes failures, it doesn't die of
them — exactly what the pool program asked for, and the per-firing
instantiation of discharge rather than a new rule.

**Co-location.** The completions flow and the settled-sum value are one
node's ports by the criterion: the value is the firing's content — neither
is lawful without the other in hand. Nothing else co-locates; every other
output the original inventory listed dissolves (starts, below) or moves
downstream (the "main result," below).

**Kind.** The completions flow is an async stream — firings minted by
settlements, terminator inherited — so the node adds no row to the kinds
table.

**Primitive, not catalog block.** Merge and interrupt are catalog blocks
over corecursive lowerings that can be drawn. This node's lowering would
carry the **in-flight set** — runtime-many cells — which race's dead end 5
ruled undrawable. So the node is genuinely primitive, like the divide
flow: no lowering, and *that* is why the completions stream kept surfacing
as "a missing output" — dynamic settlement order can be minted nowhere else
in the vocabulary. Its compiled form is the field's callback→stream bridge
(settlements enqueue; the stream is the queue's pull side), built by hand
at this exact seam.

**The family, restated.** Four binary flow operations now share the shape
"the walk's own data reshaping the walk": end-when consumes a per-firing
case and *ends* the walk; interrupt consumes an event and *cuts* it; paced
consumes a per-firing async's settlement and *spaces* it (value
discarded); settle consumes a per-firing async's settlement and *reorders
the walk's output by it* (value delivered). The operand sorts and drawn
grammar are uniform — the strongest sign the cut is right.

## The "main result" moves downstream; output ordering dissolves

Whether the concurrent collect's main output is completion-ordered or
input-ordered was an open question, suspected to need "two collect readings
or an annotation." Under the node above it dissolves — the node has no
main-result port at all, by co-location:

- **Completion-ordered results** are an ordinary collect over the
  completions flow, multiplied as consumers per multi-close. Log lines,
  supervision folds, gather-as-they-finish: all downstream.
- **Input-ordered results** are a *reassembly*: buffer completions until
  the next-in-input-order one arrives, emit, repeat. A real program
  (HTTP/1.1 pipelining), and already a member of a designed family — the
  async doc's commute of async-out-of-stream is start-all, await-in-order,
  the whole-flow version of this reassembly. The incremental version (emit
  element N once bodies 1..N have settled) is a catalog-block candidate in
  the commute family, with its honest cost stated: head-of-line blocking,
  and a buffer bounded only by how far settlement order diverges from input
  order. An open question for the commute taxonomy, not a mode here.

So neither ordering is privileged by the node; the diagram says which a
program means by what it draws downstream. For a served flow the question
is already moot (delivery is per firing at the exchange); a served flow's
concurrent form is the served collect consuming the completions flow, each
completion carrying its requester by availability — "order between sessions
is explicitly not promised" becomes visible structure.

## Termination and the graceful-shutdown ladder

The drain law — completions ends when the subject has ended *and*
in-flight bodies have settled — is chosen over terminate-with-the-subject
deliberately: settlements that will happen are not abandoned by default.
Ending the completions flow at the subject's terminator would silently drop
every in-flight body's result — the absorb-collect mistake (crossing
round, dead end 5) in temporal clothes. If the subject fails, its
terminator **propagates to the completions flow's terminator after the
drain**: the failure is not lost, and neither are the settlements already
owed. A program that genuinely wants to abandon in-flight work says so:
interrupt on the completions flow, existing vocabulary, drawn.

That one law makes the graceful-shutdown backlog program (drawn at random
as aiohttp 2, three escalation stages) a +1 ladder instead of machinery:

1. *Stop accepting*: end-when or interrupt on the **subject** side. New
   firings cease; the completions flow keeps firing as in-flight bodies
   settle.
2. *Bounded drain*: the completions flow drains to its terminator by the
   law — no code — and a deadline is one interrupt on the **completions**
   side with a timer (`race-barrier-design.md`'s whole-walk timeout).
3. *Escalate*: what "cancel harder" means is the Tier-1 cancellation gap,
   untouched here; the lost-cell trigger the race round recorded applies to
   the bodies an interrupt abandons, and this adds no policy on top.

Each stage is one added node on a different side of the one construct. The
hand-rolled version's `shield` — "wait for the thing you are cancelling" —
is stage 2's drain, here the flow's own termination rather than a guarded
await.

## Starts and the registration race, dissolved

The inventory listed a starts stream "though this one is synthesisable
outside." Co-location confirms the parenthetical: a start event per subject
firing *is* the subject flow's own firing, observed by any sibling
consumer — availability, a complete construct of its own, not a port of
this node.

What the field fears is ordering: websockets 2 registers the connection
*before* spawning the handler task (with a four-line comment) because
startup races the bookkeeping; uvicorn 2 maintains the task set by
done-callbacks. In drawn vocabulary the race cannot be drawn: a display
fold consumes `merge(starts, completions)`; the start observation is
available *at* firing N, while firing N's completion settles strictly later
on the event loop (resolution is observed only via the loop, survey finding
3.9); merge observes settlements in arrival order. A completion preceding
its own start is not an interleaving any schedule can produce. The
bookkeeping the field builds from a set, a callback, and a comment is the
pool drawing — merge, scan, hold — unchanged.

The retention bug rides along: uvicorn 5's hard-reference comment (asyncio
tasks GC'd mid-flight when nothing references them) marks a failure this
node excludes structurally — a started body's cell is held by the node's
walk until it settles and its completion is delivered. There is no way to
start a body that nothing observes, because starting *is* the observed walk
advancing.

## Registers: ill-formed inside, ordinary on completions

Whether to forbid registers off `serial` or define arrival-order stepping
resolves into both, in different places, with nothing subtle:

- **Inside the subject walk, downstream of the sever**: bodies have no
  order, so a register threading state *between bodies* is ill-formed,
  checked structurally (a Delay whose flow feeds a settle node's body
  operand) — the same species as every-cycle-crosses-a-register.
- **Across bodies in settlement order**: that state is a register on the
  **completions flow**, a single flow whose firings the event loop
  serialises, so the register steps in arrival order, well-defined, and
  drawn where the synchronisation actually is. The reservation that "the
  register becomes a synchronization point the diagram should show" is
  answered by putting it where the diagram already shows one. The task set,
  the failure counter, "max N failures per minute," the live-set scan: all
  folds on completions.

No register mode, no new check species. The one lock in survey 3's sample
(celery 4 — serialising a fold over racing callbacks) is exactly a
register-on-completions drawn by hand around a mutex.

## Keyed concurrency is the keyed partition, instantiated

A keyed partition on the subject flow yields lanes — data-determined cells,
one sub-diagram against a representative lane. Give the per-firing bodies to
the lanes and the concurrency story is inherited:

```
open udevAdds => dev, ~A
dev -> path => key
~A ~> partition key => ~L, k       -- keyed partition
capture(dev) in ~L…                -- nested serial within the lane
lanes' completions ~> settle => ~C, res
```

- **Within a lane**: the ordinary nested drawing — each firing's async
  opened in the lane's walk — so equal keys serialise by
  sequential-is-nesting, not by a mode. The replug race dissolves: the
  second add-event for path P sits in P's lane behind the first capture's
  settlement.
- **Across lanes**: lanes are sibling flows; sibling async walks interleave
  under joint demand (`async-flow-design.md`, threads-as-drained-streams).
  Distinct keys overlap freely by siblinghood, not by a mode.
- **The cross-lane completions**: the lanes' outputs rejoined in settlement
  order is this node applied at the lanes level — the partition's flatMap
  readout at the async grade. One construct, not a keyed variant of it.

The degenerate case closes the loop: `unbounded` — every firing its own
lane — is the bare settle node, which is why the node needed no key. The
menu's four words are now a drawing (serial), a partition plus the drawing
(keyed), a node (unbounded), and a residue (`bounded`), next. The
keyed-lane retention question (idle lanes as a leak) is unchanged by the
async instantiation and stays filed with the collect family.

## `bounded(n)` splits in two

The one entry that resisted dissolution resists because it is two things.

**The width.** mergeMap's `concurrent` parameter — "at most n bodies in
flight, admit the next on a settlement" — is a pure scheduling bound:
subject firing m+n is demanded only after completion m fires. A gate on the
walk's advancement keyed to the walk's own settlements: a sibling of paced
(which gates on an arbitrary per-firing async) with the gate pointed at the
node's own completions, n back. Expressible now, no resource, and its n is
configuration in the register-init sense — written, not drawn. The nested
serial drawing is what width 1 *means*, the bare node is width ∞, and the
width interpolates between two drawings that already exist — which is why
it belongs on this node and nowhere else.

**The permits.** undici's pool (permits, waiters, drain events), celery's
blocking acquire-bracket, uvicorn's supervised permanent worker set —
survey finding 3.5's three sightings are not walk-scheduling: the bound is
a **shared resource**, held across independent walks and collects, acquired
by a body and released at its settlement. That is bracket-shaped
(acquire/use/release, release reachable from abandonment); the permits are
permanent tokens; and Zig supplies the missing semantic
(`zig-comparison.md`, finding 8) — demanding concurrency backed by a real
resource is a **claim that can fail** (`io.concurrent` →
`error.ConcurrencyUnavailable`), so the acquisition is failable and
failability's ordinary machinery carries the refusal. All Tier-1 territory
(bracket, cancellation, resources): the permits form is *not a collect
species and not this node's parameter* — it is a resource the body
acquires, designed when bracket is.

The menu's `bounded(n)` conflated the two. The width is this design's; the
permits are bracket's; and the two should be re-examined together once
bracket exists, since a width-n node and an n-permit pool with one consumer
are observationally close (open question 4).

Zig's other half lands here too: **asynchrony as possibility.** For pure
bodies, overlap is unobservable — the node's semantic content reduces to
the settlement-order mint and the pull schedule — so a runtime is free to
run bodies serially or synchronously (`io.async` "may be called
immediately"), the DAG's permits-without-demanding stance in node form. A
program whose *correctness* needs genuine overlap (bodies that rendezvous
with each other, the pipe-deadlock shape) is making a resource claim, and
it belongs on the permits side of this split, failable and explicit, not on
the width.

## exhaustMap is a boundary policy, not a species

The reactive comparison (`reactive-comparison.md`, finding 3) handed this
round a menu member the record lacked: exhaustMap — "ignore every new
projected Observable while the previous has not yet completed," a
non-queueing serial. Worked against the dissolution, it does not land on
this node at all. Set the four flattening strategies side by side and
factor:

| RxJS | Decomposition here |
|---|---|
| concatMap | the nested serial drawing × a **buffer**-kind boundary (its documented unbounded-buffer warning is the pacing/backpressure hole, already filed) |
| mergeMap (+max) | the settle node (× the width) |
| switchMap | interrupt-race (`race-barrier-design.md`, already derived) |
| exhaustMap | the nested serial drawing × a **drop-while-busy**-kind boundary |

The variable is not the collect; it is **what happens to firings the
consumer is not ready for** — the impedance question the async round
already opened for external event sources ("buffer" vs "latest," with the
note that latest "is arguably a different source kind, not a policy flag").
exhaustMap adds the third member: keep all (buffer), keep the most recent
(latest), keep none while busy (drop). A queue policy of capacity ∞ /
1-replacing / 0, living at the source–consumer boundary, composing with
whatever drawing consumes it — exhaust is drop × serial, and drop × the
settle node is equally coherent (a load-shedding server). Filed to the
async round's source-kinds question; the species menu stays closed.

## Worked examples

**The server, redrawn.** The two edge novelties of the original assembly
are now one designed node and one owed round:

```
open requests => req, ~S               -- served open (round owed)
route(req) -> … -> respBody in ~S      -- async<Response> per firing
~S, respBody ~> settle => ~C, res
~C: res -> deliver                     -- served collect over completions
```
Sessions overlap because the settlement is off the pull path; delivery
order across sessions is settlement order, visibly.

**The pool, redrawn.**

```
open udevAdds => dev, ~A
dev -> path => key
~A ~> partition key => ~L, k           -- keyed partition (collect family)
capture(dev) in ~L…                    -- nested serial within the lane
lanes' completions ~> settle => ~C, res
~A, ~C -> merge -> scan(set ops) -> hold([]) => liveSet
changes(liveSet) -> render
```
Replug race handled in the lane; display fold on merge(subject,
completions) with the ordering guaranteed structurally; failed captures
arrive in `res` as data for the scan.

**Gather, first-of, and the drawn/dynamic boundary.** Five fetches drawn as
five siblings need no node — the concurrent join owns fixed arity, wall
time is the max, as designed. A *list* of URLs is a walk minting bodies:
settle, then collect the completions (completion order) or reassemble
(input order). First-of-a-dynamic-set is the head of the completions flow —
the race round's borrow, now backed by a designed construct.

**Bounded scrape.** Walk the URL list, settle with width 8, fold successes
and failures separately off the settled sum — two sibling consumers of one
completions flow. The +1 from the beginner's serial scraper: insert one
node; from there to bounded, one written width; to supervised, one more
fold.

## Against the philosophy

- **No bottlenecks.** The correspondence is longitudinal and never packed:
  subject-firing values cross by availability, the settled result is minted
  per firing, and no bag of anonymous events exists anywhere — each
  completion firing *is* its input firing, continued.
- **Building blocks must build.** The ladder is additive at every rung:
  nested serial → *insert settle* = overlap → *+ fold on completions* =
  supervision → *+ partition* = keyed → *+ width* = bounded → *+ interrupt
  on the subject* = stop accepting → *+ interrupt on completions* = bounded
  drain. No rung rewrites the previous drawing, and the serial beginner
  form teaches the constructs the hard forms are built from.
- **One obvious reading.** The species menu is gone; overlap,
  key-serialisation, and shutdown policy are each a visible node rather
  than a word on a collect. What the sampled code keeps in task sets,
  done-callbacks, flags, and comments is here the drawing.
- **Example first.** Every piece was forced by a sampled site or a worked
  program: the completions flow by the pool's display, the drain law by
  aiohttp 2, the register answer by uvicorn 2's task set and celery 4's
  lock, the width/permits split by mergeMap vs undici's pool, the drop
  policy by exhaustMap.
- **Abstraction is the source of truth.** Where lowerings exist they are
  derived views (the reassembly's commute family; keyed's
  partition-plus-node decomposition); where none can exist (the dynamic
  in-flight set) the node is honestly primitive rather than pseudo-derived
  — the divide flow's precedent.
- **Foundations before features.** Cancellation, permits, and the served
  flow are each named and fenced, not smuggled in: the drain law and the
  lost-cell trigger give the Tier-1 round clean attachment points and
  nothing else.

## Dead ends

Recorded in place; each with the reason it should not be re-proposed.

1. **The species menu as a mode dimension on collect nodes** (`serial |
   keyed(key) | bounded(n) | unbounded`). Four different constructs hiding
   in one word: a drawing, a partition, a node, and a resource. A mode
   would change the program without changing the drawing — the visual test
   condemns it.
2. **A "main result" value port on the settle node** (the collected
   outputs, in either order). Both orderings are complete constructs
   downstream (a collect over completions; the commute-family reassembly),
   so co-location forbids the port — and it would privilege one ordering as
   *the* result, re-opening the question the dissolution closed.
3. **Registers stepping in arrival order inside the concurrent walk.** The
   same state is an ordinary register on the completions flow, where the
   serialisation is drawn. A register mode would hide a synchronisation
   point inside a construct whose whole point is making the schedule
   visible.
4. **A starts output port.** The start observation is the subject flow's
   own firing — availability, obtainable by any sibling consumer — and the
   start-before-completion ordering the field defends with comments is
   structural (a settlement cannot precede its firing on the loop). A port
   would be a second spelling of an availability fact.
5. **Terminating the completions flow with the subject** (abandoning
   in-flight bodies by default). The absorb-collect's temporal cousin:
   settlements already owed are silently dropped, and every
   graceful-shutdown program would rebuild the drain by hand. Abandonment
   is an explicit interrupt on the completions side.
6. **exhaustMap (or drop/latest generally) as a collect species.** The
   choice is about firings the consumer is not ready for — a boundary/queue
   policy, orthogonal to what consumes it, composing with both the serial
   drawing and the settle node. On the collect it would fuse two
   independent choices and be unreachable from the source side where its
   siblings (buffer, latest) already live.

## Open questions

1. **Adoption.** Prepared for the design conversation; nothing is marked
   decided.
2. **The width's form.** Configuration (register-init precedent) vs a value
   port (pool size as runtime data). Also whether a *static* width n has a
   derived lowering (paced against a completion n back, via an n-deep
   register chain) — a curiosity that would demote the width from primitive
   parameter to recognition, worth checking when paced lands.
3. **The reassembly block.** Input-ordered consumption (pipelining) as a
   commute-family catalog entry: its buffer bound and head-of-line cost
   stated honestly; whether the incremental form and the whole-flow commute
   are one entry. Files to the commute taxonomy
   (`lazy-stream-commute-design.md`).
4. **Width × permits, once bracket exists.** A width-n settle and an
   n-permit pool with one consumer are observationally close; whether the
   width survives as the pure special case or dissolves into permits is a
   question for the bracket round, flagged so the two designs meet on
   purpose.
5. **Load-shedding compositions.** drop-kind boundaries composed with the
   settle node (shed when saturated) touch the same boundary family as
   exhaustMap; owned by the async round's source-kinds question, checked
   here only for composability.
6. **The served flow's round.** The composition drawn above (served collect
   over completions) is this design's guess at the seam; the served flow's
   own round (exchanges, failure legs, the recursive provider, the keyed
   cache) is still owed and may reshape it.
7. **Spec and text.** Spec entries for the settle node (and the partition's
   async instantiation), plus textual spellings
   (`textual-representation-design.md`), are owed on adoption.
8. **Naming.** "Settle" is a placeholder; "concurrent collect" should stop
   being the construct's name either way (it is not a collect).
   "Completions" vs "settlements"; "width" vs "window." Deferred to the
   naming sweep.

## What this doesn't address

- **Cancellation, bracket, permits, effects** — the Tier-1 gap is
  untouched; this contributes the drain law and the width/permits split as
  attachment points, nothing more.
- **The served flow and the server-program question** — still the
  concurrency row's owed rounds, with their demands (recursive provider,
  keyed cache, per-firing failure legs) unmoved.
- **The chooser family** — merge fairness and the decision-driven merge are
  untouched; the completions flow's settlement order is observation, not
  arbitration.
- **Backpressure/pacing under multi-close** — paced's
  per-consumer/per-source bit (`source-openers-design.md`) applies to the
  settle node's demand side verbatim and stays joint with end-when's
  coexistence question.
- **Visual depiction** — what a settle node, a lane, or a width looks like
  on the canvas is the layout side's question, out of scope in this repo.
- **Implementation.** The async runtime (cells, failable terminators,
  stream integration) does not exist in the compiler; nothing here changes
  the recorded dependency order (streams, then async cells, then async
  streams / race / settle).
