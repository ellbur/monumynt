# The served flow: the two ends of an exchange

Status: mixed — the **two-ends core is adopted** (design
conversation, 2026-07-23, riding the function-boundary /
late-bound joint adoption): one construct with two ends, the
client end being late-bound operations' op pair, the server end a
provider diagram, "which one is the server" a property of a
binding. The rest of the chapter — the exchange law's fine print,
the serving blocks' catalog rows, the k-operation provider, the
recursive provider, the keyed cache, and this round's own open
questions — remains exploration with stated leanings. None of it
is implemented (it presumes the async runtime, the settle node, the
keyed partition, and registers, none of which exist in the compiler).
Read it as "here is a candidate and the case for it." Code samples
use the textual syntax of `textual-representation-design.md`; every
construct-specific spelling below (`serve`, `op`, `with … = …`, the
FFI serving blocks) is provisional and owed to the textual catch-up
round.

This is the round the concurrency row has owed since
`tough-use-cases-design.md` named the served flow (use case 1), and
it arrives with five clients already waiting: the server program
itself; the protocol replier (use case 5); the provider side of
late-bound operations (`late-bound-operations-design.md`, which
identified its client end and stopped); the Effekt build system's
recursive provider and keyed cache (`effekt-comparison.md`, finding
4); and saturation's top-down dual (`saturation-design.md`, open
question 5). The round's job is to work the construct all five are
pointing at — once, so the five stop deferring to each other.

## A value in, a value owed back

Here is the smallest program of the shape this chapter is about. It
answers every question it is asked, by shouting it back:

```
diagram shout
  serve handle => req, ~X        -- one firing per exchange; the request comes in
  req -> upcase => resp
  resp -~> collect ~X            -- the collect is the response
end
```

`serve handle` puts the program on the *answering* side of an
operation called `handle`. Each time someone asks, the serving flow
`~X` fires once: the request arrives on `req`, the body computes,
and the collect that closes `~X` supplies the answer — delivered to
whoever asked, per firing.

A firing of this shape — a value in, a value owed back, pairwise —
is an **exchange**, and a flow whose firings are exchanges is a
**served flow**. The definition is the one `tough-use-cases-design.md`
coined: a flow "where each firing is an *exchange* — a value in (the
request) and a value owed back (the response) — and the collect that
closes the handling body supplies the owed value, per firing,
delivered to the requester." The exactly-once obligation every
request/response system polices by convention is here the law of the
collect: a collect fires once per firing, and an unclosed flow is an
incomplete program. The structure is the guarantee.

What that one paragraph does not say — and what this chapter works
out — is everything around it: *who* is asking, and what the asking
side looks like; what happens when the body fails, or the asker
vanishes; how exchanges overlap; what a provider with several
operations looks like; what happens when a provider asks *itself*;
where a cache goes; and what kind of thing a program built around a
served flow even is.

## Words this chapter borrows

Used throughout, defined elsewhere:

- An **operation pair** (`op read`) is a request/response port pair
  on a diagram's boundary; **binding** wires a provider onto it, and
  a **facet** is the drawn identity that groups an algebra's pairs
  and carries their ordering commitment
  (`late-bound-operations-design.md`, `facets-design-notes.md`).
- A **handle** is an ordering commitment; within a firing, the only
  order is along a handle's segment
  (`within-firing-effects-design.md`).
- **Settle** is the node that reroutes per-firing async settlements
  off a walk's pull path, minting the **completions flow**; the
  **settled sum** (`Ok(x) | Fail(e)`) is its per-completion value
  (`concurrent-collect-design.md`).
- A **keyed partition** groups a flow's firings into lanes by a
  per-firing key, one drawn sub-diagram against a representative
  lane (`collect-family-design.md`).
- **Availability** is how a barrier's per-firing values cross when
  provenance already tracks the correspondence; **minted** ports
  create values that exist nowhere upstream; minted outputs
  co-locate only when the node's law ties them together
  (`barrier-value-crossing-design.md`).
- A **register** is loop-carried state — read half and late-wired
  write half (`iteration-with-state-design.md`).
- `Cancelled` is the terminator the runtime delivers to in-flight
  work stranded by ceased demand (`cancellation-design.md`).
- The **link** is the divide flow's gesture: draw one level
  concretely, tie sub-problem wires back to problem wires; each link
  firing mints an instance (`divide-flow-design.md`).

## What earlier rounds already fixed

This round inherits more than it invents. Seven constraints, each
with its owner:

1. **The collect is the response.** Chosen over respond-as-effect in
   the original break (`tough-use-cases-design.md`, use case 1,
   break #1); this round owns the construct now and restates that
   rejection in its dead ends.
2. **The client end is the operation pair.** "A late-bound operation
   is the client end of a served flow; a provider is its server end"
   (`late-bound-operations-design.md`) — the identification is
   already load-bearing there, and this round builds on it rather
   than re-deriving it.
3. **Provider statefulness and facet orderedness are the same bit.**
   A provider may hold cross-exchange state exactly when the facet's
   handle gives the exchanges an order to observe; unordered facets
   get exchange-stateless providers, checked structurally
   (`late-bound-operations-design.md`).
4. **Concurrency species are drawings, not modes.** Serial is the
   nested drawing; overlap is the settle node; keyed is the
   partition; the species menu is dissolved
   (`concurrent-collect-design.md`). That round's question 6 guessed
   at the served seam; this round confirms it below.
5. **The vanished requester is answered.** Transport close becomes
   `Cancelled` on that exchange's flow, delivered by the serving FFI
   node; brackets release (`cancellation-design.md`). The dual leg —
   the body fails, what does the requester receive — was explicitly
   left to this round, and is worked below.
6. **The crossing rules are decided (as leanings).** Availability
   for provenance-tracked correspondence, minted ports for values
   that exist nowhere upstream, co-location by law
   (`barrier-value-crossing-design.md`).
7. **Dynamic sets live on flow constructs.** Runtime-many
   contenders are not drawable arity (`race-barrier-design.md`, dead
   end 5) — which is why a server's dynamic session set lives on
   flows (the serving flow, its completions flow) and never on a
   drawn barrier.

## One construct, two ends

Here is the load-bearing move of this round. The record has been
holding two constructs at arm's length from each other — the
operation pair (`op read`: a stage in a consumer's diagram) and the
served flow (`serve`: a flow in a provider's diagram) — with the
identification "client end / server end" bridging them. This round
commits to the strong reading: **there is one construct, the
exchange pair, and the two spellings are its two ends.**

| | the client end (`op`) | the server end (`serve`) |
|---|---|---|
| sees | a *stage* in its own flow | a *flow* of exchanges |
| the request | a value sent out | a value in, per firing |
| the response | a value received back | a value owed, per firing |
| exchanges ride | the client's own firings | the serving flow's firings |
| exactly-once by | one wire into the pair | the collect's law |

A client using `read` inside a walk fires one exchange per firing of
*its* walk; it never sees a served flow — the exchange rides its own
context. The provider sees no client context — just the flow of
exchanges, minted by uses. One wire pair; the flow exists only at
the serving end, which is why "served flow" names a *view*, not a
free-standing thing you could hold apart from the pair.

Two consequences follow immediately, and both dissolve standing
questions.

**The server is a provider; the network is a binding.** Use case 1
sketched a system-provided source, `requests = served<Request,
Response>`, and opened it. Under the two-ends reading there is no
served *value* to open — there is a boundary. An HTTP server is a
provider diagram offering a one-operation facet (`handle: Request →
Response`); the network side is an FFI **serving block** — the
world's client end — and deploying the server is *binding* the
block's demand to the program's offer:

```
-- spelling provisional
listen http(8080) with handle = myServer
```

The same provider bound to a scripted requester is a test run (the
worked example below). "Which one is the server" is a property of a
*binding*, not of a diagram — the from-list lexer double of the
late-bound round and an HTTP server are the same species of program,
differing only in what stands at the other end of the pair.

**The kinds table is untouched.** Now, you might wonder whether
"served" is a new flow kind — a row beside list, case, stream,
async, and incremental, as the original sketch assumed ("a new flow
kind whose collect has an external meaning"). Run the kinds-table
test from `source-openers-design.md`: a kind earns its row by its
open behaviour and its collect behaviour. The serving flow's open
behaviour is the push adapter's — firings minted by external
arrivals, an async stream. And its collect novelty — the value goes
*to the requester* — turns out not to be kind content at all: it is
**pair** content. The responding collect is ordinary; what is new is
only that its value port is the response half of a boundary pair,
the same way `out` names a boundary port. So the served flow is a
boundary structure minting an (async) stream, exactly as `open self`
is a node minting a stream — a pair, not a row. (This is a recorded
dead end — dead end 2; the same knife that cut "self-driven" and
"list-with-state" as kinds.)

One sentence of ontology, per the standing lens. Use case 5 already
found it: served flows are the general form of **prompted output** —
any situation where the world speaks first and each utterance owes
an answer. An exchange is a prompted answer. And this locates the
construct in the demand structure: everywhere else in the language,
demand originates in the program's declared outputs and flows
toward sources; the served flow is the one place where **external
demand is minted per firing, at runtime** — each exchange is a
little demand edge arriving from outside. That is why cancellation's
external half (the vanished requester) lands exactly here, and why a
serving program's liveness is its requesters' business rather than
its own.

## The law of the exchange

Stated once, in port terms, so the checks are structural:

**Every exchange's response half receives exactly one value, tied to
that exchange by provenance.**

Unpacked:

- **Exactly-once.** The pair's response half is a port; a port takes
  one wire; the collect on that wire fires once per firing. No
  linearity side condition, no convention.
- **Exhaustiveness.** Routing may split the exchange flow into cases
  and handle them separately, but the branches must merge back — the
  alts partial-collected to one response flow, exactly the
  partial-collect worked example. A response flow that *drops*
  exchanges (a filter-join that discards firings) is ill-formed: an
  answer owed and never supplied. The check is the case collect's
  exhaustiveness discipline, applied over the exchange's firings.
- **The responding collect need not sit on the exchange flow
  itself.** It may close any flow whose firings correspond
  one-to-one to the exchanges — the exchange flow (serial), its
  completions flow (overlapped), a pass-through readout of a
  partition of it (keyed). Provenance carries the correspondence,
  and *order was never part of the law*: the obligation is per
  exchange, not per position. This is what makes the concurrency
  seam free, below.
- **Observers are free.** Other consumers of the exchange flow —
  a request log, a metrics fold, a live-session scan — are ordinary
  multi-close, unconstrained by the law. Only the response half is
  spoken for.

## Failure crosses the exchange as itself

The dual leg the cancellation round left here: the body fails — what
does the requester receive?

The answer splits at the boundary between the program and the edge,
the same seam as cancellation's "silence exists only at the edges":

- **Program side: the response lane is failable, like any wire.** A
  body's failure terminator, undischarged, discharges *into the
  exchange* — the response half carries the failure payload instead
  of a value. At the client end the response wire is then failable
  in the client's own context, propagate-by-default, dischargeable
  wherever the client chooses — precisely how `path -> read` failing
  behaves under failability's ordinary machinery, and what
  `late-bound-operations-design.md` already assumed when it made the
  FailingAllocator double's threshold lane a failure. Nothing new:
  the exchange is a barrier, and failure crosses it as itself,
  pairwise, never as a propagated whole-flow terminator — one
  session's error does not kill the server, because the serving
  flow's terminator was never involved. (For an overlapped server
  this is visible in the drawing: the settled sum carries `Fail(e)`
  as data per completion, and the response collect forwards it into
  the exchange.)
- **Edge side: the serving block's catalog row translates.** What a
  wire-level failure *becomes* — a 500 response, a connection reset,
  an NAK datagram — is the FFI serving block's policy, recorded on
  its catalog row, exactly as the cancel translations live on the
  FFI catalog rows in `cancellation-design.md`. A program that wants
  a *lowered* error response (a drawn 500 page) simply discharges
  the failure itself before the response collect — ordinary
  discharge, visible, upstream of the edge.

So the serving block's catalog row carries **three edge
translations**, consolidated here for the catalog schema round:
*failure-out* (what a failed exchange becomes on the wire),
*cancel-in* (what transport close becomes — `Cancelled`, per the
cancellation round), and *admission* (what happens to arrivals the
program isn't ready for — the buffer / latest / drop family the
async round owns, with drop × settle already noted as the
load-shedding server in `concurrent-collect-design.md`).

## Serial, overlapped, keyed — drawings, not modes

Nothing in this section is new; it is the confirmation
`concurrent-collect-design.md` asked for (its open question 6). The
serving flow composes with the concurrency vocabulary exactly as
that round guessed:

- **Serial** — the nested drawing: each exchange's async body opened
  in the walk, settlement on the pull path. The alternating protocol
  replier (use case 5) is exactly this, and *wants* it: replies are
  order-sensitive.
- **Overlapped** — insert settle: the body's settlement reroutes to
  the completions flow; the response collect closes completions, the
  requester riding to it by availability. "Order between sessions is
  explicitly not promised" is visible structure.
- **Keyed** — a partition on the exchange flow (by session, by user,
  by resource): within a lane serial, across lanes overlapped, the
  replug-race discipline verbatim.

The one thing this round adds is the observation that the law makes
the seam *free*: because the obligation is per-exchange and
provenance-carried, rerouting the response collect from the exchange
flow to the completions flow changes nothing about what is owed to
whom. The drain law composes too: stop accepting (end-when or
interrupt on the serving flow), and every in-flight exchange still
delivers — graceful shutdown is inherited, not redesigned.

## A provider with several operations: the bundle arrives pre-split

`late-bound-operations-design.md` left one structural question open
(its question 3): a sequenced algebra's provider receives one
segment-ordered stream of exchanges across k operation lanes — what
is the drawn form? Its leaning was "k lanes, one shared serving
context"; this round works that leaning out, and the answer is a
construct the record already has.

**The serving end of a k-operation facet is a bundle.** One serving
context — a flow `~N`, one firing per exchange, in handle order —
whose firings are partitioned into k static lanes, one per
operation. Each exchange is exactly one operation's, so exactly one
lane fires per firing of `~N`: that is the bundle law, and
everything bundles support applies. Per-lane request and response
wiring (the lanes keep the operations' identities — the
no-bottleneck rule respected on the provider's side); registers on
`~N` for cross-exchange state, their steps supplied per-lane and
merged by the exhaustive case collect (the conditional-carry shape);
each lane's response half closed by its own partial collect.

```
facet Lexer = algebra { peek, next }     -- sequenced: one handle

diagram fromList                          -- the two-op lexer double
  in tokens
  serve Lexer => ~N                       -- one serving context, two lanes
  ~N ~> delay init tokens => remaining    -- register on the exchange flow
  ~N.peek: remaining -> head -~> collect ~N.peek     -- answer; no step
  ~N.next: remaining -> head -~> collect ~N.next     -- answer…
           remaining -> rest              -- …and consume
  …merged -> step of remaining            -- per-lane steps, case-collected
end
```

The point worth pausing on: **there is no dispatch**. A mailbox
architecture receives a tagged union and switches on it; use case
1's server splits its request *data* on a route field. Here neither
happens — the alternation is minted *pre-split* at the boundary,
because no union was ever packed (that packing is the sum
bottleneck, dead end 3 of the late-bound round). A one-operation
server that routes on its request's content and a k-operation
provider are now visibly different programs: the first draws a case
split on data; the second receives a bundle whose cases are the
operations themselves.

For an **unordered** facet there is no handle, hence no
cross-exchange order, hence (by the statefulness-orderedness result)
no register on `~N` — the serving context still exists as a flow,
but it is order-free, and the exchange-stateless check applies. The
lanes remain; only the register vocabulary is barred.

## The recursive provider: the link, in exchange costume

Now the build system (`effekt-comparison.md`, finding 4): one
operation `need(key): Val`; a build rule computes a key's value *by
needing other keys*; the build system answers `need` by recursively
building. The demand the record filed: a provider defined partly in
terms of requests back to itself.

Draw what is actually there. The provider's body — one build rule —
contains a client-end use of the very facet the provider offers:

```
facet Build = algebra { need }            -- unordered: sub-builds may overlap

diagram builder
  serve need => key, ~B                   -- server end: each firing builds one key
  key -> rule => deps, recipe             -- one level, concrete
  deps -> open list => d, ~D
  d -> need => v                          -- client end: the same facet, used
  v -~> collect => inputs
  inputs -> recipe -~> collect ~B         -- this key's value; the response
end
```

The `d -> need` stage is a use site whose demand travels outward
like any unmet demand — and binding it *to this same provider* is
tying a boundary of the diagram back to itself. The record has a
name for that gesture: it is the **link** (`divide-flow-design.md`)
— write one level concretely, tie the sub-problem wires back to the
problem wires — performed on an exchange pair instead of a value
pair. Each sub-need mints a fresh instance of the serving body;
per-instance membership is derived from dataflow; sibling instances
share nothing but their answers at the parent.

The consequences transfer wholesale from the divide flow:

- **Unmemoized, the instance structure is a tree** — every `need`
  spawns a fresh build, sub-builds of a shared dependency repeat.
  That is the divide flow exactly, and the divide flow's
  **termination discipline** applies verbatim: the recursion is
  admissible when a measure decreases across the link — here, that
  the dependency relation on keys is well-founded. A build system
  without a cycle check is trusting its keys the way a recursive
  descent parser trusts its grammar.
- **Concurrent sub-builds are the collect species on the client
  side** — `Build` is an unordered facet precisely so that the
  `inputs` walk may settle its sub-needs overlapped. Scheduler
  strategies ("Build Systems à la Carte") are drawings on the two
  ends: serial vs settled sub-need walks on the client side, serial
  vs overlapped serving on the provider side — swapping schedulers
  is swapping drawn structure, not handlers.

## The keyed cache: a partition with a lane register

The second build-system demand: `memo`, the composable cache in
front of a provider. Where does it go, and what is it?

It is a **middleware** — the policy layer's shape from the
late-bound round: provider-shaped upward (offers `Build`),
consumer-shaped downward (demands `Build`), installed by splicing
into the binding. And its interior is existing vocabulary:

**The keyed cache is a keyed partition of the exchange flow by
request key, with a per-lane register holding the answer, lanes
drained serially within and freely across.** The first exchange in a
lane forwards downstream and stores the answer; every later exchange
in that lane answers from the register without forwarding.
Same-key requests serialise behind the first computation (the lane
is serial within — so a burst of requests for one key computes
once); distinct keys don't wait for each other (lanes are siblings).

Notice what this dissolves: a cache is *stateful*, and `Build` is an
*unordered* facet — by the statefulness-orderedness result, a
register on the whole exchange flow would be ill-formed. The keyed
form threads that needle exactly: the cache's state is **per-lane**,
and the only order it observes is *within* a lane — which is a
scheduling fact the lane's serial drain supplies, not an observation
of cross-exchange order the facet never promised. A cache is legal
on an unordered facet precisely because its statefulness is keyed —
and the structural check can say so (a register on an unordered
serving flow: ill-formed; a register on a keyed lane of one:
fine, the lane is serial by construction).

Two boundaries, stated so they aren't blurred:

- **This cache is the run-scoped memo.** A cache that *invalidates*
  — staleness, subscriptions, React Query — is the incremental
  collections layer's client (`incremental-flow-design.md`; keyed
  var families, per-key subscriptions), and stays filed there. The
  memo of this section never invalidates within a run.
- **Correctness leans on the downstream provider being effectively
  pure per key.** Answering from the register is unobservable
  exactly when the forwarded exchange would have returned the same
  value. For an unordered facet that is the natural reading; the
  fine print (what marks a facet's operations as cacheable — a
  catalog property with a witness?) is open question 5.

**And the cache is what turns the tree into a DAG.** Splice the memo
in front of the recursive provider and repeated sub-needs dedup
against the lanes: each key builds once, later requests join the
stored answer. The instance structure collapses from the divide
flow's tree to a DAG with merges — which is saturation's exact
distinction ("tree without dedup = divide; DAG with dedup =
saturation"), arrived at from the demand side.

The cycle question sharpens beautifully here. A lane whose first
exchange is still open — requested, not yet answered — is
**in-flight**; and a request for key K arriving *from within the
demand cone of K's own open exchange* is a dependency cycle: the
answer would have to be an ancestor of itself. The witness is
provenance: the link crossing appends a segment to the context path,
so the arriving exchange's path contains the lane's own open
exchange — a drawn, pointable witness, and the printed trace every
build tool produces ("cycle: A → B → A") *is* that context path.
This is the same species as the divide-flow round's progress-measure
violation — the parser field's left-recursion check — surfacing at
the exchange level: left recursion and cyclic dependency are one
defect in two costumes.

## The duality with saturation, first joint working

`saturation-design.md` named the hinge and asked for the joint
design once this round ran. Here is the first working.

Both constructs discover a runtime DAG the drawn program never
states. Saturation **pushes**: seeds derive consequences upward,
exhaustively; its dedup collect is what makes the loop monotone and
convergent. The cached recursive provider **pulls**: a goal demands
its needs downward; its keyed cache is what makes the recursion
shared and finite. The correspondence is now concrete on both
sides:

- **The memo table and the seen-set are the same construct** — a
  keyed collect — **written by opposite drivers**: saturation's is
  written by the feedback loop's rounds (a fact enters when derived),
  the provider's by exchange completion (a key enters when answered).
- **Termination is the same non-structural condition read in
  opposite directions**: a finite universe reached exhaustively
  (bounded fact universe, no rule minting unboundedly new values)
  versus a finite cone reached on demand (well-founded or
  cycle-checked keys). Neither is structural; both hang off the
  dedup construct.
- **Which construct a program draws is which end names the
  extent.** Want everything derivable? The extent is the closure —
  draw saturation. Want one goal's answer and only what it needs?
  The extent is the goal's cone — draw the recursive provider behind
  a cache. These are *different drawn programs with different
  meanings*, not two lowerings of one construct: the closure
  computes facts no goal asked for, and the provider leaves
  underivable-but-unneeded facts unexplored. (Datalog's magic-set
  transformation — rewriting a query so bottom-up computes only the
  goal's cone — is, in this record's terms, a *recognition* between
  the two drawings: transformation-levels territory, a derived
  equivalence to exploit in code, never a mode on either construct.)
- **Provenance transfers.** Saturation's explanation sub-DAG (why is
  F in the closure) and the provider's demand cone (why did K
  rebuild; the cycle trace) are the same derived view — the firing
  DAG read off the run — approached from opposite ends.

## What is a program, for a server?

Question 7 of the tough round: a served flow never ends; the program
of record is a standing composition, not an expression with a
result; what does `compileToBody` even mean?

The two-ends reading dissolves most of the question's mystery. **A
server program is a provider diagram** — a value-less thing only in
the sense that its meaning sits on its boundary: the facet it
offers, the demands it re-exports, the sources it consumes. That is
not a new species of program; it is the same diagram-with-ports the
functions row already has, whose *deployment* is one more binding.
The program of record is the diagram. The standing run is the
diagram bound to the world's client end.

What remains genuinely different is the compile target: a bound
serving program's "result" is its ongoing behaviour, so the compiled
form is a registration (install the exchange handler, subscribe the
sources) rather than a value computation — the first-class-ports
consequence ("the program is a node set, not a root expression")
gaining its second, larger client exactly as predicted. The
compile-strategy doc owns the mechanics; nothing here changes them.

The payoff is testing, and it comes free. Because "which one is the
server" is a property of the binding, the same provider runs under a
scripted requester as an ordinary value-producing program:

```
diagram harness
  in script                       -- a list of requests
  op handle                       -- the harness is a client
  script -> open list => req, ~T
  req -> handle => resp           -- one exchange per scripted request
  resp -~> collect => transcript
  out result = transcript
end

myScript -> harness with handle = myServer => transcript
```

The transcript is a value; the test is a pure program; and the facet
shared between the production binding (`listen http(8080) with
handle = myServer`) and the test binding is what makes the test
informative — the late-bound round's test-double story, run in the
opposite direction. Servers are testable for the same reason
consumers are: the pair has two ends, and either can be the double.

## Worked examples

**The server, assembled** — use case 1's program, with every piece
now owned:

```
diagram myServer
  serve handle => req, ~S              -- the exchange flow
  req -> split route of Status, Data
    Status: -> statusResponse
    Data:   -> … -> dbWrite … => body  -- async per-exchange work
  -~> collect => resp                  -- routing merges back: exhaustive
  ~S, resp ~> settle => ~C, res        -- sessions overlap
  res -~> collect ~S                   -- respond per completion; requester by availability
end

listen http(8080) with handle = myServer
```

Sessions overlap because settlement is off the pull path; a failed
body arrives in `res` as `Fail(e)` and crosses into that exchange —
the block's catalog row says what the socket sees; a vanished client
is `Cancelled` into that exchange's body. One drawing; every edge
case is a designed seam rather than a comment.

**The protocol replier** (use case 5's alternating regime) — the
same shape, serial: no settle node, the reply on the pull path, so
replies leave in prompt order. The difference between an HTTP server
and a lockstep protocol is one node's presence, visibly.

**The build system** — the recursive provider above, with the memo
spliced on:

```
memoBuilder = interpose memo on builder      -- memo: the keyed-cache middleware
goal -> need with need = memoBuilder => out  -- a goal-directed, shared, cycle-checked build
```

**The lexer double** — the two-operation bundle form drawn in the
multi-operation section, replacing the single-op sketch the
late-bound round could draw before the serving context was designed.

## Against the philosophy

- **Example first.** Every piece generalised from a program that
  hurt: the server (use case 1), the replier (use case 5), the build
  system (Effekt), the double (Effekt's corpus), the cache (memo),
  the cycle (every build tool's error message). The construct adds
  no structure the examples didn't demand — no session objects, no
  service registry, no dispatch.
- **Inside-out.** No scope, no magic names: the request arrives on a
  port, the provider is found at the end of a drawn binding, never
  by ambient resolution. Cases (the operation lanes) are values.
- **No bottlenecks.** The pair crosses the boundary as per-value
  lanes; the k-operation bundle arrives pre-split because no union
  was packed; failure crosses per-exchange as itself, not as a
  whole-flow terminator; correlation is provenance, never an ID
  packed into the payload.
- **Programmer's abstraction level.** "Answer each request,"
  "overlap sessions," "one at a time per user," "cache by key,"
  "build what the goal needs" — each is one node or one splice.
- **Abstraction is the source of truth.** The cache is a drawn
  middleware, never a mode; the scheduler is drawn structure; the
  magic-set equivalence is a recognition, not a switch; where a
  form is fused (`serve` minting the pre-split bundle) its
  decomposition is readable.
- **Graceful expansion.** The +1 ladder: the echo server → +routing
  (a split and a merge) → +async body (open it in the walk) →
  +overlap (insert settle) → +keying (insert a partition) →
  +supervision (a fold on completions — an observer) → +cache (a
  splice) → +recursion (a link). No rung rewrites the previous
  drawing; the shout server teaches the shape the build system is
  made of.
- **Foundations before features.** Per-exchange IO handles, permits,
  and invalidating caches are fenced to their owners (Tier-1,
  bracket, incremental collections), with the seams named.

## Dead ends

Each worked and set aside; the wondering form carries the reason.

**1. Respond-as-effect.** Now, you might wonder why the request
doesn't carry a respond capability the body calls (`res.end(…)`),
as the JS ecosystem does. It turns out this trades the collect's law
for a linearity side condition the language would have to police —
nothing structural shows a response happens, or happens once; the
capability can be dropped, doubled, or smuggled. Rejected when the
served flow was first named (`tough-use-cases-design.md`, break #1)
and owned here now: the collect *is* the response. (Settled
rejection — please don't re-propose without new evidence.)

**2. "Served" as a flow kind.** You might wonder why the kinds
table doesn't grow a served row. It turns out the serving flow's
open behaviour is the push adapter's and its collect novelty is pair
content (a boundary port), not kind content — a kind whose every
behaviour is another kind's is that kind, opened differently. The
same knife as "self-driven" and "list-with-state." (Settled
rejection.)

**3. The exchange as two one-way messages.** You might wonder why
the pair isn't just a request event plus an independently-sent
response event — the actor/mailbox architecture. It turns out
severing the pair severs the correspondence: exactly-once becomes a
convention, and the requester must be re-identified by data. The
field's own witness is the **correlation ID** — hand-rolled
provenance, packed into every payload, doing by convention what the
pair does by structure. Unprompted sends and n-replies-per-prompt
are real programs, but they are *not exchanges* — that is the
corecursive production over merged events (use case 5's
non-alternating regime), a different drawing for a different
meaning. (Settled rejection as a reading of the exchange;
the non-alternating shape stays owned elsewhere.)

**4. The memo as a mode on `serve`.** You might wonder why caching
isn't `serve memoized by key`. It turns out a mode would change the
program without changing the drawing — the visual test again — and
would fuse three decisions (key choice, lane policy, downstream
purity) into a word. The cache is a drawn middleware whose interior
is a partition and a register; splice it and you can point at it.
(Settled rejection.)

**5. Inherited rejections**, restated as owned context: the tagged
single pair (the sum bottleneck), the provider as a value on a wire,
and ambient/nearest-handler resolution are the late-bound round's
dead ends 3, 2, and 1; each applies to the serving end unchanged and
none is re-litigated here.

## Open questions

The language hasn't decided any of these yet.

1. **Adoption.** This chapter is prepared for the design
   conversation; nothing is marked decided. The conversation is
   joint with the late-bound round's — the two are one construct's
   two ends and should be adopted (or reshaped) together.
2. **Multi-client sharing and arbitration.** A serving provider
   bound at two boundaries receives the merged exchanges. Per-client
   order is each client's handle; *cross-client* order is genuinely
   undefined, and "who is answered first when two ask at once" is
   arbitration — the chooser family's territory (merge fairness),
   confirming that family as the concurrency row's remaining core.
   *The round now exists* (`chooser-family-design.md`,
   exploration): a program that wants to own cross-client order
   draws the decision-driven merge over the client exchange flows
   upstream of the provider — decision by arrival (a race of
   heads) as the neutral form, priority as a decision reading the
   request payloads, fair-share as a register on the step flow —
   and an undrawn arbitration is the serving block's ambient
   arrival order, kind content on its catalog row. Arbitration is
   drawn or ambient, never a hidden provider property.
3. **Spellings.** `serve`, the lane projections (`~N.peek`),
   `listen … with …`, `interpose … on …` — owed to the textual
   catch-up jointly with `op` and the level boundary (one decision,
   now four clients: functions, divide, late-bound, this round).
4. **The serving blocks' catalog rows.** The three edge translations
   (failure-out, cancel-in, admission) as catalog schema content —
   files to the checking row's question 4, with the admission family
   staying owned by the async round's source-kinds question.
5. **Cacheability's fine print.** What licenses the memo middleware
   on a facet — an "effectively pure per key" property on the facet
   or its operations, presumably a catalog property with a witness;
   and what the checker says when the memo is spliced onto a facet
   without it. Joint with the checking row's question 4 and the
   collect family's witness-carrying rows.
6. **When does a server end?** End-when/interrupt on the serving
   flow compose (stop accepting; drain), but the *root* question —
   what keeps a standing composition alive, and what its orderly
   exit means for still-bound facets — touches end-when's adoption,
   cancellation's root-exit edge, and question 7's compile residue
   at once. Sketched here only as far as "the drain law composes."
7. **Streaming responses.** The law says one response value; that
   value's kind is unconstrained, so a chunked response is an
   exchange whose answer is a stream. Whether the serving blocks'
   rows need a "the answer is a stream" translation (chunked
   encoding — the within-firing round's non-coalescing sink) is
   catalog content, filed with question 4.
8. **Evidence.** The application-level concurrency sample
   (`real-loop-survey.md`, "Next round") should now also carry this
   round's frequency questions: how often application code stands on
   the serving side (handlers, RPC endpoints, message repliers), and
   whether the build-system shape occurs outside build tools. Per
   the standing method, sample before the adoption conversation
   treats importance as measured.
9. **Naming.** "Served flow" vs exchange/session/dialogue; "serving
   block"; "memo" vs "cache." Deferred to the naming sweep.

## What this doesn't address

- **Per-exchange effects.** "Each session may use IO" still crosses
  the Tier-1 hole; the constraint recorded with the original use
  case — IO handles mintable per exchange, only same-handle
  operations ordered — rides to the effects round unchanged.
- **Permits and bracket.** A bounded server (n sessions' worth of
  resources) is the permits half of `bounded(n)`, fenced to the
  bracket round as before.
- **The chooser family.** Named as the owner of cross-client
  arbitration (question 2) and otherwise untouched.
- **The incremental collections layer.** The invalidating cache,
  staleness, and per-key subscriptions stay filed there; this
  round's memo is the run-scoped special case.
- **Visual depiction.** What a serve boundary, a lane bundle, or a
  spliced middleware looks like on the canvas is the layout side's
  question, out of scope in this repo.
- **Implementation.** Nothing here exists in the compiler; nothing
  here changes the recorded dependency order (streams, async cells,
  settle, then boundaries).

## Prior art

- **Effekt** (`effekt-comparison.md`): the build system — `need`,
  the recursive handler, `memo` as a composable handler — is this
  round's hardest client, reproduced as a link plus a spliced
  partition-register middleware; the from-list double is the serving
  register's first program.
- **Flix** (`flix-comparison.md`): channels-and-processes as an
  architecture is the sighting this round answers; provider stacks
  as stdlib furniture feed the middleware form.
- **The JS field** (`tough-use-cases-design.md`, surveys): `res.end`
  is the respond-as-effect negative witness; correlation IDs in
  message architectures are hand-rolled provenance; HTTP/1.1
  pipelining vs multiplexing is the serial/overlapped seam shipped
  both ways.
- **Datalog / build-systems literature**: "Build Systems à la
  Carte"'s scheduler/rebuilder decomposition maps onto drawn
  client-side and provider-side species; magic sets locate the
  top-down/bottom-up relation as a recognition between two drawn
  programs (`saturation-design.md`).
- **Zig** (`zig-comparison.md`): parameters-as-capabilities support
  binding-at-a-boundary over any ambient resolution, inherited via
  the late-bound round.
