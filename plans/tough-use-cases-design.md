# Tough Use Cases

Status: evidence / stress-test. The candidate blocks proposed here are
*candidates* — the consolidated inventory at the end ranks them by how
many use cases demand each, and nothing in this document is decided or
implemented. Its vocabulary is current with the binary-join, Cross, and
completion designs. Update (2026-08-04): read its uses of the fail
node, terminator payloads, op pairs, and `level of` against the
2026-08-04 revision notes in `failure-payloads-design.md`,
`late-bound-operations-design.md`, `divide-flow-design.md`, and
`end-when-design.md` (end-when's fusion with its collect into
collect-until) — this document is evidence and is left unrewritten.

Citations to `visual-flow-language.md` (the retired first-generation
narrative) refer to the record preserved in git history; its live content
is now in `core-model.md` and the topic docs this document lists under
"designed-ahead vocabulary."

This document has a randomly-harvested sibling. The real-loop surveys'
singleton hard draws are collected as a nine-loop **breadth set**
(`real-loop-survey.md`, "Reading the frequencies: the 80/20
counterweight") — members of the same must-express-without-pain set this
document's five programs were constructed for, but drawn blind. Three of
the nine currently have no owning construct: the wrap loop, the
tokenizer-substituter, and the history-indexed table fill — the
variable-rate-consumption / running-view cluster.

## What this is for

Every design round so far started from a construct and worked outward:
join, commute, the register, the async flow. This document inverts the
direction. It takes five programs that real systems are made of — programs
with servers, races, recursion, child processes, and wire protocols in
them — and writes each one against the building blocks the design record
currently has, honestly, until it hurts. Where it hurts is the finding:
either an existing block needs modification, or a new block is missing, or
the program exposes a gap that several use cases share.

The method leans on a standing position from
`language-design-philosophy.md`: building blocks live at the programmer's
abstraction level, not at the minimal-primitive level, and abstraction is
the source of truth — a high-level block whose lowering is a read-only
derived view is durable, not magic. So this document does not apologise
for proposing very high-level blocks. If a block solves a problem that is
genuinely hard to get right by hand — a synchronization problem, a
lifecycle problem — that is the *strongest* case for it, not a mark
against it: the one-obvious-reading criterion is worth the most exactly
where hand-rolled solutions are subtly wrong in ways reviewers miss.

Each use case section follows the same arc: what the program is, how far
the existing blocks carry it, where it breaks down, candidate blocks with
the philosophy check applied, and what the case teaches beyond itself. A
consolidated inventory at the end collects the proposals and ranks them by
how many independent use cases demanded them — convergent demand from
unrelated programs being the best evidence a block is real.

## The inventory being tested

What the design record has on paper (much of it unimplemented), one line
each, so the use cases can reference it:

- **Synchronous flows**: list iteration, option iteration, case splits;
  binary Join (`lazy-stream-join-design.md`), filter as join with an
  option operand; the partial collect (`partial-collect-design.md`);
  Cross for sibling products (`product-flows-design.md`).
- **Stream flows**: single-pass, on-demand, memoised cells
  (`lazy-stream-placement-design.md`); commute as a per-close repackaging
  (`lazy-stream-commute-design.md`).
- **Async flows** (`async-flow-design.md`): the async cell;
  sequential-is-nesting / parallel-is-concurrent-join; the race barrier;
  merge (race lifted over streams); interrupt; failable flows (terminator
  payloads); external event sources as async streams.
- **Incremental flows** (`incremental-flow-design.md`): vars, derived
  vars, switch-join, `hold` and `changes`, scan-then-hold at the mutation
  boundary.
- **The register** (`iteration-with-state-design.md`): loop-carried state
  via the link transformation; two candidate drawings (Delay-as-ports and
  the latent-flow uncollect), since proven result-level equivalent — one
  register pair; self-driven streams (a
  register with no source); the every-cycle-crosses-a-register
  productivity rule.
- **First-class ports** (the first-class-ports round, retired — see
  `core-model.md` and `src/ARCHITECTURE.md`): per-kind port
  inventories, mixed-kind ports on one node, the DelayRead/DelayWrite
  pair, the program as a node set.
- **Designed-ahead vocabulary** (now the topic docs `functions-design.md`,
  `configuration-scopes.md`, `custom-flows.md`,
  `trees-and-recursion.md`): functions as sub-diagrams with port
  interfaces; configuration scopes; custom effect-handle flows with
  lifecycle (open → operations → close); the parallel pool sketch; derived
  zipper/catamorphism/anamorphism from recursive ADTs.

And the known gaps, which several use cases will land on:

- **No IO design.** Effects are designed-ahead vocabulary only.
- **No cancellation.** Abandonment ≠ cancellation is recorded in both the
  async and incremental docs; nothing closes it.
- **No user recursion.** Deliberate ("no manual recursive step-taking");
  iteration is derived from data shapes.
- **No output side.** Everything so far consumes external streams and
  produces values; nothing writes *to* the world.

## Use case 1: an HTTP server

Listen for requests; handle each with a response; each session may do IO.
The request and IO operations are system-provided; the user supplies the
handling logic.

### What carries

The inbound side is fully designed. Incoming requests are an external
event source — an async stream, buffer-kind (every request matters; none
may be dropped), exactly the adapter the async doc's external-event-sources
section describes. Routing is a case split on the request value — cases as
values, nothing new. The retired language description already sketched a server
flow (now `configuration-scopes.md`, event-driven section) as an iteration
over "a stream of events", so the reading "a server is an open over the request stream" is
established.

### Break #1: where does the response go?

A request is not just data that arrives; it is data that arrives *owing an
answer*. In every flow so far, the collect's per-firing value builds
**our** output — a list, a var, a folded result. Here the per-firing value
must be delivered **back to the source**: the response goes to the socket
the request came in on.

Two ways to say that:

- **Respond-as-effect.** The request value carries a respond capability;
  the handler calls it. This is what the JS ecosystem does (`res.end(...)`),
  and it needs the IO design, first-class effectful operations, and a
  discipline ensuring the capability is called exactly once per request —
  a linearity obligation the language would have to police as a side
  condition. Nothing about the diagram's structure would show that a
  response happens, or happens once.

- **The collect is the response.** Keep the open/collect shape and change
  *whose* output the collect's value is. Call a flow with this property a
  **served flow**: a flow opened from an external source where each firing
  is an *exchange* — a value in (the request) and a value owed back (the
  response) — and the collect that closes the handling body supplies the
  owed value, per firing, delivered to the requester. The exactly-once
  obligation becomes the exhaustiveness discipline collects already have:
  an unclosed flow is an incomplete program; a collect fires once per
  firing by the law of the collect. The structure *is* the guarantee.

The second is clearly this language's answer. It costs no new wiring
concept — an open with value+flow out, a collect with value in — only a
new flow kind whose collect has an external meaning. And it is the missing
half of that server sketch (`configuration-scopes.md`): the sketch had the
open (requests as an ongoing flow) and stopped before saying what closing
it means. Answering the requester is what closing it means.

The philosophy check passes cleanly: no magic names (the request arrives
on a value port); cases as values (routing is an ordinary split; different
routes are partial collects over the split, merging back to one response
flow — the partial-collect worked example in `partial-collect-design.md`
is literally an HTTP response computation already); no bottleneck (request
in, response out correspond pairwise per firing — the barrier discipline,
applied longitudinally along a flow).

### Break #2: sessions must overlap

A drain, as designed, is sequential: pull cell N, run the body, pull cell
N+1. A server whose handler awaits a database call would accept no new
connections while waiting. The per-firing body here is async-valued
(`async<Response>`), and the server wants many bodies in flight at once.

The design record has *fixed-arity* concurrency (the concurrent join:
these two asyncs overlap) and *sequential* unbounded iteration (the
drain). It does not have **unbounded, dynamic concurrency**: one body in
flight per element of a stream, joined as they complete. That is the gap.

Candidate: the **concurrent collect** — a collect mode (or a distinct
collect node; see open questions) on a flow whose per-firing value is
async, with the law: *each firing's body is started when the firing
arrives, not when the previous body settles; the collect's obligations are
per firing, unordered across firings.* For a served flow, "the collect
delivers the response to firing N's requester when firing N's body
resolves" — order between sessions is explicitly not promised, and the
structure says so, because the reader can see which collect species is in
play. Sequential remains the default; concurrency is visible, not
inferred.

This is the retired language description's parallel pool ("looks sequential; the
runtime has N workers") landing in async vocabulary — with the important
correction that the concurrency is *cooperative interleaving on the event
loop*, per the async doc's honesty rule, not worker parallelism. The pool
sketch's instinct that concurrency belongs to the flow kind, leaving the
per-element diagram sequential-looking, survives intact.

A hard follow-on the moment this block exists: **what does a register mean
inside a concurrently-collected flow?** A register carries state from
firing to firing *in order*; concurrent bodies have no order. Options:

- **(a)** registers are ill-formed inside a concurrent collect (checkable
  structurally — a Delay whose flow is concurrently collected is rejected,
  the same species of check as every-cycle-crosses-a-register);
- **(b)** registers step in *arrival* order — the register's steps
  serialise even though bodies overlap — well-defined but subtle, since
  "arrival" is settlement order, and the register becomes a
  synchronization point the diagram should probably show.

Lean: (a) now, (b) only if a use case demands it — and use case 2 has a
better construct for cross-session state anyway (a var fed by events).
Either way, the check is structural, which is the point of making
concurrency a visible collect species rather than a runtime mood.

### Break #3: per-session IO

"Each session may use IO" sounds like it should wait for the IO round, and
mostly it does, but this use case leaves the IO round a constraint it must
honour: the IO story (now `custom-flows.md`) threads an `io_flow` effect
handle through operations to sequence them. Thread *one* handle through a
server and every session serialises on it — the concurrency of break #2
destroyed by the effect system. So: IO handles must be mintable per
session (per firing of the served flow), with only same-handle operations
ordered. The custom-flow machinery (effect-handle flows commute freely
with each other) already points the right way; recorded here so the IO
design inherits the requirement with a concrete program attached.

### The server, assembled

Spelling provisional — `served` and `concurrent collect` are candidates:

```
requests = served<Request, Response>       -- system-provided source

requests -> open served => req, ~session   -- exchange per firing: request in, response owed
req -> split route of Status, Data
  Status: -> statusResponse
  Data:   -> ... -> await dbWrite ...       -- async body, per-session IO
-~> collect                                 -- alts partial-collected to one response
response -~> concurrent collect ~session    -- delivered per firing; sessions overlap
```

Everything in the middle is existing vocabulary. The two new things sit at
the edges: the flow kind of the source (served) and the species of the
collect (concurrent).

## Use case 2: a worker pool over external resources

The concrete program (previously written by hand, with pain): automatic
MIDI recording with a TUI display. Watch udev for new MIDI devices; when
one appears, open it and dump its events to a file until EOF; meanwhile
display the list of currently-open captures. The known trap: a device can
be unplugged and replugged, and the udev "add" event for the reappearance
races the EOF of the previous capture.

### What carries

More than expected:

- udev events: an external event source, async stream, buffer-kind.
  Designed.
- One capture: a drain of the device's data stream into a file, ending at
  EOF. The *ending* is exactly the failable-flow design: EOF is `Nil`, a
  read error (including the yank of an unplug) is `Fail(e)`, and the
  capture's own completion is an async value — the drain's fold. Designed,
  and a pleasing confirmation that terminator payloads were the right
  shape: "unplugged" arrives as a terminator, not as an exception from
  nowhere.
- The display: a `var<list<capture>>` built by scan-then-hold over
  capture-lifecycle events, rendered by draining `changes` — the
  incremental doc's full worked loop, verbatim. Designed.
- Spawning one capture per add-event with overlap: the concurrent collect
  from use case 1, second independent demand. A capture takes minutes;
  add-events must not queue behind it.

### Break #1: lifecycle events come from inside

The display fold needs `started(capture)` and `finished(capture)` events.
`started` could be synthesised at spawn — it is visible in user-space. But
`finished` happens *inside* the spawned body (the drain hits its
terminator), and every spawned body's finish must feed **one** merged
stream that the display fold consumes. With merge as designed (binary,
race-lifted), merging an *unbounded, dynamically growing* set of
completion asyncs is not expressible: merge's operands are wired at
authoring time.

This is not a display-side problem; it is a missing *output* of the
concurrent collect. The block should be a proper barrier: per input
firing, corresponding lifecycle firings out. Concretely, the concurrent
collect grows flow/value outputs beyond its main result:

- a **completions** stream: one firing per body settlement, in settlement
  order, carrying the body's result (or its terminator payload —
  completions of failed bodies are data here, not propagated failure; a
  supervisor consumes them, it doesn't die of them);
- optionally a **starts** stream (spawn order), though this one is
  synthesisable outside.

Pairwise correspondence between input firings and completion firings is
the no-bottleneck discipline again — the completions stream is not a bag
of anonymous events; each firing corresponds to an input firing, and the
correspondence should survive into whatever identity the elements carry.

With that output, the display is: merge starts and completions, scan a
set, hold, `changes`, render. All existing vocabulary.

### Break #2: the replug race

The trap, precisely: capture for device path P is draining; device is
unplugged (capture will end with `Fail(unplugged)` or EOF, *eventually* —
the fd read has to notice); device is replugged; the add-event for P
arrives **before** the old capture's terminator. A naive program now opens
P while the old capture still holds it — open fails or, worse, two captures
fight — and when the old terminator finally lands, a path-keyed display
fold removes the *new* capture's entry.

Two remedies, at different levels, both worth having:

- **Fresh identity per capture** (data-level). Mint a token at spawn;
  lifecycle events carry the token, not the path. This fixes the
  *bookkeeping* half — the display fold keyed by token cannot confuse the
  two captures. It does nothing for the *resource* half: the new open
  still races the old close on the OS device. Worth stating as an idiom
  (it is just correct data modelling), but it is not the synchronization.

- **Keyed lanes** (synchronization-level). A construct with the law:
  *given a stream and a key computed per element, elements with equal keys
  are handled serially — element N+1's body does not start until element
  N's body has settled — while elements with distinct keys overlap
  freely.* The replug race dissolves by construction: the second add-event
  for path P waits, inside the lane, for the first capture's settlement
  (terminator seen, file closed, fd released) before its body opens the
  device. No flags, no retry loop, no sleep.

The keyed lane is precisely the kind of block this document's preamble
defends: a synchronization problem that is short to state, miserable to
hand-roll (the by-hand version of this exact program had the bug), and
whose one-obvious-reading form is a single node with a visible key. The
philosophy check: the key is computed by ordinary value nodes per element
(no magic, cases as values); per-key order is a *longitudinal* barrier —
firings correspond one-to-one through it, nothing packed; and it has an
honest derived lowering — per key, a register holding the previous body's
completion async, each new body's start joined on it — which is exactly
the subtle program nobody should write by hand but everyone should be able
to *read* when they drop to the derived view.

Relationship to the concurrent collect: a keyed lane *is* a concurrency
species — sequential collect is "one global lane", concurrent collect is
"every element its own lane", keyed lanes are the middle. That suggests
representing all three as one collect-concurrency dimension: `serial |
keyed(key) | unbounded` (plus, likely, `bounded(n)` — see open questions).
One dimension, four values, and the diagram shows which is in play at the
collect. Lean: yes, one dimension; the lane is not a separate node
species.

### The pool, assembled

Spelling provisional:

```
udevAdds = stream<Device>                   -- event source

udevAdds -> open stream => dev, ~adds
dev -> path => key                          -- ordinary value computation
capture(dev) -~> collect ~adds              -- capture body (async): open device, drain to file
    [concurrency: keyed(key)]               -- replug race handled here
  => results, ~completions                  -- lifecycle output

starts, completions -> merge -> scan(setOps) -> hold([]) => liveSet
liveSet -> changes -> render                -- TUI, incremental loop
```

What this case teaches beyond itself: supervision is a *reading of
lifecycle streams*, not a construct. Restart policies, back-off, "max N
failures per minute" — all of these are ordinary stream programs over the
completions output. The only primitives are the concurrency species and
the lifecycle barrier outputs; everything an Erlang supervisor does is
user-space above them. That is the right cut line, and it is worth
protecting: proposals to build restart policy *into* the pool should be
resisted, because the events-out form keeps the policy programmable.

## Use case 3: mergesort

You think it should be clean in a visual language. It is not, in this one,
with the current blocks — and the reasons are precise and instructive. Two
independent obstructions, one per half of the algorithm.

Framing note: the language's answer to *sorting* is a catalog `sort`
configured by a scope, and that stands. The test here is not "can users
sort" but "can the language express the algorithm's own shape" —
divide-and-conquer with a data-dependent merge. If it can't, a whole
family of programs (parsers, planners, tree algorithms, anything
recursive) is out of reach, not just a redundant sort.

### Obstruction 1: the merge step is output-driven

Merging two sorted lists looks like a job for the existing blocks and is
not. Walk both lists with a cursor each; compare heads; emit the smaller;
advance that cursor; repeat until both are exhausted. Try to place this on
the inventory:

- Not zip (lockstep — cursors advance *dependently*).
- Not join (join concatenates levels; no interleaving by data).
- Not the async merge — but *look at* the async merge: race the two heads,
  emit the winner, recurse with that side advanced. The ordered merge is
  the **same walk with the decision made by comparison instead of by
  arrival time**. The async doc derived merge from the race barrier; the
  data-ordered sibling has no corresponding derivation because there is no
  synchronous "race".
- Registers? A register carries state across the firings of *a flow* — and
  here is the real diagnosis: **no input flow drives this iteration.**
  Neither list's own iteration is the loop; the *output* is. Each output
  element is one comparison. Iteration driven by the output's demand
  rather than an input's shape is corecursion, exactly the thing the
  language deliberately declines to hand users raw.

The honest current-blocks expression exists and is grim: a self-driven
stream (a register with no source — the Fibonacci shape) whose carried
state is the pair of cursor indices, whose step compares `a[i]` vs `b[j]`,
emits one element and advances one index. Legal under the productivity
rule (the cycle crosses the register), and unreadable: manual cursor
bookkeeping is the assembly language of iteration, three constructs
coordinated to say one word. It also exposes a *second* gap en route: the
self-driven stream never ends, and the language has no **data-driven
stream termination** — filters skip elements but the walk continues;
interrupt ends a stream by an *event*; nothing ends a stream because *the
data says so* ("stop when both cursors exhausted", "take while ascending").
That gap is independent of mergesort and keeps appearing (see use case 5
and the bottom-up variant below); recorded in the inventory as
**end-when**, the data-driven sibling of interrupt, writing the terminator
from inside the walk.

Candidate block: the **ordered merge** — better, the **decision-driven
merge**, since the comparator is configuration: two flows in, per-step a
chooser (a configuration scope, like sort's comparator — exposing the two
current heads, the user wires the decision) picks which side advances;
elements pass through as themselves, no pair is packed. Kind-symmetric
with the async merge: one interleaves by time, the other by data; both are
"consume two flows, interleaved by a per-heads decision". Its derived
lowering is precisely the cursor-register program above — which is the
strongest form of the philosophy argument: the lowering exists, is
correct, and nobody should read it unless they ask to.

### Obstruction 2: the recursion has no data to hang on

The language derives iteration from data shape: lists give list iteration,
recursive ADTs give zippers and cata/anamorphisms. Mergesort's recursion
tree is not the shape of any data the program *has* — it is the shape of
the algorithm's own division. The input is a flat list; the balanced tree
of splits is virtual, existing only as the trace of "split until
singleton". The derived-from-ADT machinery almost applies (mergesort is a
hylomorphism: anamorphism by splitting, catamorphism by merging) but the
intermediate tree would have to be materialised as data purely to give the
derivation something to chew on — declaring structure upfront, exactly what
example-first forbids.

The bottom-up variant dodges recursion and lands in the other gap: runs =
list of singletons; repeatedly "merge adjacent pairs" until one run
remains. "Repeat a whole-collection transformation until a predicate" is a
self-driven stream of lists plus end-when plus a final readout —
expressible the day end-when exists, and still reading as three constructs
coordinated to say "until".

Candidate block: the **divide flow** — and there is a principled way in,
because the design record already contains its linear ancestor. The
register was earned by the *link transformation*: write one step
concretely, then link the output back to the input — "this output and this
input are the same thing across iterations." The divide flow is **the
link, tree-shaped**: write one level of the division concretely — a case
split on the problem:

```
problem -> split divisible? of Base, Divide
  Base:   problem                    -- the problem itself is the answer's seed (singleton)
  Divide: -> splitInHalf => subA, subB   -- two smaller problems
```

— and then link `subA` and `subB` back to `problem`: "these outputs and
that input are the same thing across *levels*." The linear link produced
iteration; the tree link produces divide-and-conquer. The collect side is
dual: per base firing, a leaf answer; per divide firing, a combine of the
two child *results*, which arrive on visible ports — the tree analog of
the rail's recursive tap-outs (previous-iteration values drawn as ports),
so there is even visual-vocabulary precedent for "a value from another
instance of this same region, on a wire."

Mergesort then reads at its own abstraction level, two nodes (spelling
provisional):

```
[3,1,4,1,5] -> divide flow
  base (singleton):  the one-element run
  divide:            splitInHalf => subA, subB      -- linked back
collect:
  base:    singleton run
  divide:  childResultA, childResultB -> decision-driven merge
```

"Split until singletons, merge upward" — the diagram says the sentence.

The costs, honestly:

- **Termination.** The linear link's productivity check was crisp: every
  cycle crosses a register; the tick is real time (an iteration, a turn).
  The tree link needs sub-problems to be *smaller*, which is undecidable
  in general. Options: **(a)** trust, with runtime divergence as the
  failure mode — precedented, this is exactly the derived-iteration
  soundness check's documented lazy fallback ("cannot verify
  termination"); **(b)** demand a measure (size decreases) — checkable for
  catalog divisions; **(c)** restrict divisions to a catalog (halve a
  list, split a tree, partition by pivot) with user divisions admitted
  under (a)'s warning. Lean: (c) with (a) as the escape hatch, matching
  the derived-iteration precedent exactly.
- **Representation.** The back-link is a cycle, and the record already
  owns the answer: the DelayRead/DelayWrite move — the later wiring act
  mints its own node, the object graph stays a DAG, the cycle is recovered
  from identity. The divide link is the same pattern with two write-halves
  (or one, two-ported).
- **Non-lowering.** The divide flow does not lower to existing vocabulary
  — nothing does general recursion below it. That is acceptable: list
  iteration doesn't lower either. The criterion is one obvious reading, not
  reducibility; the divide flow is a *primitive* flow kind (problems as
  firings, self-similar), not a macro.

What this case teaches beyond itself: the missing dimension is
**algorithm-shaped iteration** as opposed to data-shaped. The language's
stance — recursion implicit in primitives — survives; the divide flow *is*
that stance applied to divide-and-conquer, the way list-iteration was that
stance applied to lists. And the merge obstruction generalises past
sorting: "consume input(s) at a data-dependent rate" is parsing,
run-length encoding, two-pointer algorithms, stream alignment. Use case 5
hits it again from the protocol side.

## Use case 4: a child process with pipes

Run an external program; feed its stdin; consume its stdout and stderr;
observe its exit.

### The shape falls out of first-class ports

This use case is the payoff of the port-inventory design. A child process
is one node with a mixed-kind inventory:

```
Process
  value inputs:   command, args, env
  stream input:   stdin
  stream outputs: stdout, stderr        -- failable: Fail on stream error
  async output:   exit                  -- failable: Fail on spawn failure / signal;
                                         -- exit *code* is the value (nonzero is data, not failure)
```

No new flow kinds; the node is FFI surface. The exit-code decision is
worth pinning: a process that runs and returns 1 has *succeeded at being a
process* — code-as-data lets the program case-split on it; `Fail` is
reserved for "there is no exit code" (couldn't spawn, killed by signal).
This is the recover-vs-end boundary from the failability design, applied.

### Break #1: a node that consumes a stream

`stdin` is the first port anywhere in the design that *consumes a stream as
an operand*. Everything so far consumes flows by opening them or collecting
them, and consumes values whole. Two readings were on the table and one
wins cleanly:

- A "sink" concept — a new dual construct, push-shaped, that our program
  writes into. Rejected below (use case 5 finishes the argument).
- **Streams are already values** (`stream<X>` is a type; stream heads are
  passed around today), so a stream-typed input port is not new machinery
  — what is new is the *runtime contract*: the node pulls the stream at
  its own pace. For a process, that pace is the pipe's: the OS pipe drains
  as the child reads; each drained chunk is demand; demand pulls our
  stream; our stream's thunks run. **Backpressure is not a feature to
  design — it is the pull model meeting a consumer that happens to live
  outside the program.** A child that stops reading stops our production
  automatically, unbounded buffering is impossible by construction, and
  nothing had to be invented.

This resolution — *the world consumes our streams by pulling them through
external nodes' stream-input ports* — is proposed here as the general
answer to the output side of IO. It gets its second confirmation in use
case 5.

### Break #2: the classic pipe deadlock, made visible

The famous bug: parent writes stdin while the child blocks writing its full
stdout pipe; nobody reads stdout; deadlock. In this model the bug *can* be
written — by making the stdin production and the stdout drain sequential
when they should be concurrent — but the mistake is **structural and
visible**: sequential is nesting (drain stdout *after* stdin's stream
ends), concurrent is siblings plus concurrent join (both in flight,
interleaving on the event loop). The async doc's "to know whether two
computations overlap, look at whether one hangs off the other's value
port" applies verbatim, and the reviewer can see the deadlock as a
wrongly-nested drain. Structure-as-semantics paying rent on a bug class
that costs real debugging time in every language that hides the
concurrency.

Interleaving stdout and stderr into one log: the async merge, as designed.
Distinguishing "streams ended" from "process exited": concurrent join of
the drains' folds with `exit` — both are ordinary compositions.

### Break #3: the process must die with the program

Abandon the composition — a race overtakes it, the consumer stops pulling,
the program shuts down — and the child is still running. For pure
computation the async doc could shrug ("abandonment wastes CPU"); a child
process is not wasted CPU, it is a zombie holding fds. External resources
convert the **cancellation gap from a performance wart into a correctness
hole**, and this is its third arrival in the design record (async doc:
lost racers; incremental doc: pending-pull registrations; now: leaked
processes — plus use case 2's fds and use case 5's sockets and the served
flow's vanished clients, so really its third-through-sixth).

Candidate block: **bracket** — acquire/use/release, with the law: *the
release runs on whichever way the use ends — normal terminator, failure
terminator, or abandonment.* The first two legs are expressible today
(terminator handling); the third leg **is** the cancellation capability,
and bracket is the construct that converts "we should design cancellation
someday" into a requirement with programs attached: abandonment must
become a deliverable event at resource nodes. The async doc's constraint
("the async cell should be able to carry a cancellation capability later")
is exactly the hook; bracket is its consumer. Every resource in this
document — device fds, child processes, sockets, listen ports, tempfiles —
sits inside one.

What this case adds to the IO round's requirements: kill is not optional;
release must be reachable from abandonment, not just from terminators; and
release itself is effectful and async (waitpid), so bracket's release leg
is an async body with a completion the supervisor may need to observe (a
lane keyed on the resource serialises replacement — note how use case 2's
construct reappears).

## Use case 5: a local websocket serving a child process

Open a local websocket server; spawn a child that connects to it; exchange
datagrams over the connection.

### The choreography is free

The setup sequencing that imperative code gets wrong (spawn before
listening; connect before accepting) is *structurally unwritable* here:
the child needs the port as an argument, the port is the listen node's
async value output, so spawn hangs off listen's value port and cannot
start earlier — sequencing by data dependency, the async doc's rule doing
real work. Accept is an async of the connection; the connection is a node
with a stream output (incoming datagrams) and a stream input (outgoing
datagrams). The stream-input reading from use case 4 lands its second
confirmation: **no sink construct exists anywhere in these five
programs.** Every write-to-the-world is an external node pulling a stream
we composed. The concept can be struck from the missing-blocks list, which
is this document's one subtraction.

### Break: the conversation

Datagram protocols are conversations: what we send next depends on what
they said last. Two protocol regimes, sharply different in what they
demand:

- **Alternating (request/reply).** The child sends a request; we respond;
  repeat. This is *exactly the served flow* from use case 1, in miniature
  — each incoming datagram opens an exchange; the collect's value is the
  reply. Second independent demand for the served flow, and a scope
  expansion worth recording: served flows are not a server-shaped special
  case; they are the general form of **prompted output** — any situation
  where the world speaks first and each utterance owes an answer. (With
  one difference from HTTP: protocol replies are usually order-sensitive,
  so this served flow wants the *serial* collect, not the concurrent one —
  and the concurrency-species dimension from use case 2 expresses exactly
  that distinction, at the collect, visibly.)

- **Non-alternating (n replies per prompt, unprompted sends, both sides
  initiating).** Now the outgoing stream is not per-incoming-firing; it is
  a genuine corecursive production driven by *merged* events (incoming
  datagrams, timers, our own state changes) with protocol state carried
  across them. The vocabulary exists — merge, registers (scan over the
  merged stream), end-when for session termination, `hold` if the protocol
  state should be readable elsewhere — but the honest assessment is that
  this is the *hardest* composition in this document: a state machine
  hand-built from a register whose carried value is a protocol-state ADT,
  with a case split per step. The custom-flow doc
  (`custom-flows.md`, "state-machine protocols": file
  open→read/write→close) is the
  designed-ahead hook: a custom flow kind whose lifecycle *is* the
  protocol, giving the state machine one reading instead of a
  register-and-split assembly. Whether custom protocol flows are
  user-defined flow kinds (heavy) or a catalog block over (merge +
  register + split) with a derived lowering (lighter) is left open — but
  the use case says the need is real: hand-rolled protocol state machines
  are where the bugs live in every datagram program ever written.

The mergesort connection, closing the loop: a datagram parser that needs
"read exactly N more bytes, where N came from the header" is
decision-driven consumption again — the input is consumed at a
data-dependent rate. The decision-driven merge's single-input degenerate
form (a chooser deciding *advance or stop*, i.e. end-when; or *advance how
far*) is the same primitive family. Three arrivals (merge step,
until-loops, framing) make the family load-bearing.

## Consolidated inventory

Ranked by independent demand across the five use cases.

### 1. Concurrent collect

A concurrency-species dimension on collects — `serial | keyed(key) |
bounded(n) | unbounded` — with lifecycle barrier outputs (completions;
starts). Demanded by: server (sessions overlap), pool (spawn per device,
replug race via `keyed`), protocol replies (serial, stated visibly).
Interacts with registers (likely: forbidden off `serial`; structural
check).

**Field evidence** (concurrency survey, `real-loop-survey.md`, survey 3).
Task-per-firing was drawn twice, both times hand-rolling the lifecycle
bookkeeping the barrier outputs would provide: a task set maintained by
done-callbacks, and registration ordered before spawn to dodge a startup
race documented in a four-line comment. `bounded(n)`-as-resource is
confirmed three ways (a pool with permits/waiters/drain events, a blocking
acquire-bracket, a supervised permanent worker set) — none
partition-shaped, supporting the permits reading. `serial`-as-unmarked-default
matches practice: one lock in thirty orchestration draws, and it was
serialising a fold. But the survey's headline cuts the other way: the
race/timeout/interrupt cluster outweighed collect-species demand
nine-to-one (see finding 3.1 there).

**Round findings** (`concurrent-collect-design.md`, an exploration round
with leanings). The species dimension dissolves: `serial` is the nested
drawing, `keyed` is the keyed partition (`collect-family-design.md`)
instantiated, and what remains is one primitive binary flow operation
("settle") minting the completions flow in settlement order, with the
body's settled result as a per-firing discharged sum. Lifecycle outputs:
completions is the node's one flow output; starts is availability, not a
port. `bounded(n)` splits into a width (this node's configuration) and
shared permits (bracket-shaped, failable, fenced to the Tier-1 round).
Registers: ill-formed across bodies, ordinary on the completions flow.
Leanings, nothing adopted.

### 2. The served flow

An external flow kind whose firings are exchanges; the collect's per-firing
value is delivered back to the source. Demanded by: server (responses),
websocket (alternating protocols). Generalises to all prompted output.

**Field evidence** (concurrency survey). The served flow was the ambient
structure around many draws — every handler body in three corpora — with
no draw contradicting the design. Its per-firing failure leg (open
question 3) was sighted in exactly the anticipated shape: client
disconnect delivered into the handler body as a lazily-minted per-request
abort signal.

### 3. Bracket (release-on-any-end)

Acquire/use/release with release reachable from abandonment. Demanded by:
process (kill), pool (fd release feeding the keyed lane), sockets, listen
ports, served-flow clients that vanish mid-exchange. Forces the
cancellation capability; consumes the async cell hook already recorded.

**Field evidence** (concurrency survey, finding 3.6). Roughly eight of
thirty sites touch cancellation, abandonment, or retention-across-abandonment,
and they are the sample's most delicate code: a timeout's
state-machine-plus-uncancel dance, shield-await inside a graceful
shutdown's escalation ladder, check-then-subscribe abort wiring, weakref-broken
timer retention. The graceful-shutdown backlog program (in the use-case
backlog below) was itself drawn at random, three escalation stages of it.

**Round findings** (`cancellation-design.md`, an exploration round with
leanings). Bracket is not a region: the lifecycle segment's acquire
vertex mints the handle (failable), and the release is a late-wired
body on the acquiring node consuming (handle-at-cut, terminator) — one
body ignoring the tag is `defer`, a split on it is `errdefer`;
granularity (per-firing vs per-walk) is vertex placement. The third leg
is supplied by the round's central move: abandonment is delivered as a
`Cancelled` terminator over the demand frontier, so release-on-any-end
is ordinary discharge. Kill is release's effect on the handle; release
is infallible and uncancellable, its completion a cell the supervisor
observes (the keyed-lane replacement consumes it). Leanings, nothing
adopted.

### 4. The decision-driven family

Ordered/decision-driven merge (two flows, per-heads chooser as a
configuration scope); **end-when** (data-driven terminator writing, the
synchronous sibling of interrupt); data-dependent take. Demanded by:
mergesort's merge, until-loops, protocol framing.

**Field evidence** (the real-loop surveys). Across sixty randomly sampled
loops in two corpus families, roughly eighteen terminate early or on a
data condition, in four guises: first-match, take-until-sentinel,
poll-until-result, predicate cursor. Data-dependent take also occurred
naturally: line filling, skip-while, a variable-rate tokenizer. The domain
sample adds a sharpening: in numerics, data-driven termination arrives
*fused to the scan* — loops stop because of their carried state (take-while
on the term size, retry-until-tolerance) — so end-when must compose with
the register designs. On that evidence end-when outranks this slot (see
`real-loop-survey.md`, findings 4–5 and 2.7).

**Round findings.** end-when has a worked exploration round
(`end-when-design.md`) proposing the binary flow-operation shape (subject,
stop), bounding it against the rest of this family, and taking up open
question 5's degenerate-case question with a leaning toward separate
constructs sharing verdict vocabulary. Data-dependent take has its round
too (`variable-rate-consumption-design.md`), reframing "advance how far"
as boundary placement: split-when, a segmenting (subject, boundary) flow
operation yielding a nested flow, with the count entering as data (a
register the boundary reads) rather than as a verdict. The family's
remaining unworked member — the two-flow decision-driven merge — now
has its round too (`chooser-family-design.md`): the walk over k
cursors, per-step heads, a late-wired advance operand, the chooser
dissolved into ordinary drawn wiring; this use case's mergesort merge
is its opening example. Nothing adopted.

### 5. The divide flow

The link transformation, tree-shaped: a self-similar flow with base/divide
alts, child-result ports at the collect, catalog divisions plus a warned
escape hatch. Demanded by: mergesort, and behind it the recursive-algorithm
family. Genuinely primitive (no lowering), like list iteration.

### 6. External nodes with mixed-kind port inventories

The whole FFI story — processes, sockets, listeners, device sources;
stream-*input* ports as the universal output-to-the-world (no sink
construct — struck from the list). Demanded by: every use case; enabled by
the ports representation (`core-model.md`; migration landed) as-is.

### 7. Custom protocol flows

State machines with one reading. Demanded once (non-alternating
protocols); the designed-ahead custom-flow lifecycle section is the hook;
lightest-viable form unclear. Weakest claim; watch for a second demand.

### Cross-cutting findings, for the rounds they belong to

- **The IO round inherits**: per-session mintable handles (one global io
  thread would serialise servers); kill/release as effects; abandonment as
  a deliverable event at resource nodes; the exit-code-is-data /
  no-exit-is-Fail boundary as the worked example of recover-vs-end.
- **The cancellation gap is now load-bearing** — six arrivals across three
  documents; bracket gives it a construct-shaped consumer; it should not
  wait past the IO round.
- **Validated by contact, no changes needed**: pull-model backpressure
  (pipes made it free); failable terminators (EOF / unplug / spawn-failure
  mapped on without residue); the incremental loop (the TUI fell out
  verbatim); structural concurrency-visibility (the pipe deadlock became a
  visible nesting mistake); Cross/partial-collect (routing merged
  responses).

The philosophy check, in aggregate: every proposed block is either a flow
kind (served, divide), a barrier with pairwise correspondence (lifecycle
outputs, decision-driven merge, lanes read longitudinally), or a lifecycle
pairing (bracket). None packs a tuple or a tag to pass a structural point.
All but the divide flow (and the FFI nodes themselves) have derived
lowerings into existing vocabulary — lanes to completion-registers,
ordered merge to cursor registers, pools to merge+scan — keeping them
durable abstractions over readable expansions, per the source-of-truth
principle. And each earns its keep on the stated criterion: the
hand-rolled version of the lane, the bracket, and the protocol machine is
where this document's motivating programs actually had their bugs.

## Open questions

1. **Concurrency-species representation.** One dimension on the collect
   node vs distinct collect kinds; where `bounded(n)` gets its n (a value
   port — making pool size runtime data — or configuration); whether
   `keyed`'s key is a port or a configured scope. Also the register
   interaction: forbid off `serial`, or define arrival-order stepping?
   *Worked in `concurrent-collect-design.md`:* the dimension dissolves
   entirely — no mode survives; the key is the keyed partition's ordinary
   key wire; `bounded(n)`'s n splits (width as configuration now, permits
   as a Tier-1 resource later); and the register question resolves into
   both halves — ill-formed across concurrent bodies (structural check)
   and arrival-order stepping delivered as an ordinary register on the
   completions flow, where the serialisation is drawn. Leanings, not
   adopted.
2. **Concurrent collect output ordering.** The main output: is it
   completion-ordered (a merge) or input-ordered (a commute-like
   reassembly, buffering completions)? Both are real programs (log lines
   vs HTTP/1.1 pipelining). Two collect readings or an annotation?
   Interacts with the served flow, where the "output" is per-firing
   delivery and ordering is moot. *Dissolved in
   `concurrent-collect-design.md`:* the node has no main result port at
   all (the co-location criterion); completion-ordered results are an
   ordinary collect over the completions flow, input-ordered results are a
   commute-family reassembly block (filed to the commute taxonomy with its
   head-of-line cost stated). Neither is a mode. A leaning, not adopted.
3. **Served-flow failure legs.** The requester vanishes mid-exchange
   (client disconnect): the firing's flow is already open, the collect's
   delivery has nowhere to go. Is this a per-firing cancellation delivered
   *into* the body (the bracket/cancellation machinery at element
   granularity), a terminator on the exchange, or silently absorbed? Also
   the dual: the body fails — what does the requester receive (connection
   reset vs a lowered error response) and is that the FFI node's policy or
   the program's?
   *Both legs now worked:* the vanished requester in
   `cancellation-design.md` (transport close becomes `Cancelled` on that
   exchange's flow, delivered by the serving FFI node), and the dual leg
   in `served-flow-design.md` (the response lane is failable like any
   wire — the body's terminator discharges *into the exchange*,
   per-exchange, never as a whole-flow terminator; what the wire sees is
   the serving block's catalog-row policy, dischargeable upstream by the
   program). Leanings, not adopted.
4. **Divide-flow termination.** Catalog divisions with a size-measure
   check, plus warned trust for user divisions — confirm against the
   derived-iteration soundness precedent; work a non-list example (tree
   from use, not from data — e.g. quadtree build) to make sure the catalog
   isn't list-shaped. *Worked in `divide-flow-design.md`:* the ladder is
   confirmed (catalog division → drawn measure → warned trust, the last
   matching the derived-iteration precedent), and the quadtree did its
   job — point count is *not* a valid measure (coincident points), so the
   example forces the drawn-fuel species, and the catalog comes out
   three-specied (structural shrink, cursor progress, fuel), not
   list-shaped. The progress species' violation witness is the parser
   field's left-recursion check. Leanings, not adopted.
5. **Decision-driven merge arity and generality.** Two flows with a binary
   chooser covers merge; framing wants single-input with advance-counts;
   is there one primitive (chooser over N heads returning which-advances)
   or a small family? And is end-when its degenerate case or separate?
   *Both halves now have worked leanings:* end-when stands alone
   (`end-when-design.md`); advance-counts dissolves into boundary
   placement (`variable-rate-consumption-design.md` — split-when owns the
   single-input case, and the leaning is no N-head chooser at the surface:
   the chooser is the family's shared lowering shape, the members share
   verdict/operand vocabulary). *The two-flow merge's round now exists*
   (`chooser-family-design.md`, exploration): one primitive after all,
   but not a chooser — a walk minting per-step heads over k ≥ 2
   cursors, with the decision as ordinary drawn vocabulary and the
   sketch's configuration-scope instinct kept (wired, never passed);
   end-when confirmed separate (the k = 1 shapes stay with end-when,
   split-when, and the cut). Nothing adopted.
6. **Keyed-lane key semantics.** Equality of keys (structural? user
   equivalence, like cutoff?); unbounded key spaces (a lane per key ever
   seen is a leak — lanes must be collectable when idle, which is a
   retention question shaped like the event-source one).
7. **What is a "program" for a server?** A served flow never ends; the
   program of record is a standing composition, not an expression with a
   result. The node-set consequence — "the program is a node set, not a
   root expression" (`core-model.md`; `src/ARCHITECTURE.md`, "Node set
   from day one") — was derived from Delay write-halves; long-running
   compositions are its second, larger client.
   What does `compileToBody` mean for a program whose value is its ongoing
   behaviour?
   *Largely dissolved in `served-flow-design.md`:* a server program is a
   provider diagram — its meaning sits on its boundary (the facet it
   offers) — and the standing run is that offer *bound* to the world's
   client end (the network FFI block); the same provider bound to a
   scripted requester is an ordinary value-producing test program. What
   remains is the compile residue (a bound serving program compiles to a
   registration, not a value computation — the node-set consequence's
   second client, as predicted). A leaning, not adopted.
8. **Naming.** "Served flow" vs exchange/dialogue/session; "lane" vs
   key-serial; "bracket" vs with/scope; "end-when" vs take-while/until;
   "divide flow" vs recurse/split. Deferred, per tradition.

## Addenda: four notes from review

Four points raised in review of the first draft. None fully explored here
— each is recorded with enough working-out to show where it leads, and
left for its own round.

### The visual test, and the species menu revisited

This is a visual language, and a building block's role should, where
possible, be legible from the drawing — "semantics structural, not
nominal" applied to the *block inventory*, not just to programs. Measured
against that, the consolidated inventory's item 1 fails as stated: `serial
| keyed(key) | bounded(n) | unbounded` is a menu of words, and a reader who
hasn't looked them up learns nothing from seeing one on a collect.

Working the menu against the test, most of it dissolves into structure:

- **`keyed` decomposes.** Keyed lanes are a **group-by open** — a dynamic
  partition: one flow in, one sub-flow per runtime key value — whose
  per-group body is an ordinary serial drain, with groups concurrent among
  themselves (siblinghood across groups). The correspondence that the word
  `keyed` named is then *drawn*: the key wire visibly feeds the
  partition's discriminator, exactly as a case split's discriminator wire
  is drawn today. The apparent obstacle — the keys aren't known until
  runtime, so the correspondence is abstract — is handled by a convention
  the language already relies on everywhere: the **representative
  instance**. One element wire stands for every element of a list; one alt
  body stands for every firing of an alt; one lane body stands for every
  key's lane. A group-by open is drawn like a case split with one
  representative alt, and the reader's existing training reads it
  correctly. (Group-by is also independently useful — histograms, word
  counts, any partition-by-computed-key — so it earns its place as a block
  in its own right, with keyed concurrency as one reading of it.)
- **`unbounded` is the degenerate group-by** — group by firing identity;
  every firing its own lane.
- **`serial` is no construct at all** — the default collect, unmarked.
- **`bounded(n)` resists the decomposition**, and the resistance is
  informative: it is not a partition but a *resource* — n permits, a body
  runs while holding one. That is the permanence theme's first client
  (below): permits as permanent objects moving pool → body → pool on
  wires, the count visible as n token sources rather than as a numeral
  annotation.

So the "dimension on the collect node" framing in the inventory should be
read as superseded in spirit: the species are mostly *wiring*, not modes,
and open question 1 is partially answered. Honest residue: some things stay
written rather than drawn — the key function is authored, an n is a numeral
— but written-configuration has precedent (register init values), and the
test is "expressed visually *where possible*", a preference, not an
absolute.

The test should be applied retroactively to the rest of the inventory as
each block gets its round: what does a served open *look like* such that
"the collect answers the requester" is visible? What does a bracket region
look like such that the release's reachability-from-abandonment is
apparent? Recorded as a standing gate, not answered here.

### A use-case backlog

The five programs here were chosen for maximum stress, but five is not
enough to firm up a language; convergent demand across many unrelated
programs is the only reliable signal a block is real (it is what promoted
the concurrent collect and the served flow above the others). Candidates
for future rounds, one line each, with the blocks they would stress:

- **tail -f with log rotation** — event sources, failable terminators
  (rotation as a terminator vs a new stream?), bracket.
- **debounced autosave** — timers, interrupt/switch-join interplay,
  incremental boundary.
- **rate limiter / token bucket** — permanence (tokens), timer refill, the
  bounded-pool permit machinery from the other side.
- **graceful shutdown** — interrupt + concurrent collect together: refuse
  new firings, drain in-flight bodies, then release; stresses the
  lifecycle outputs and bracket ordering.
- **binary protocol parser** — decision-driven consumption, end-when,
  data-dependent take; the framing pressure from use case 5 worked to
  completion.
- **directory synchronisation / reconciliation** — permanence's headline
  case: match a real-world set, no duplicates, nothing missing.
- **a spreadsheet** — incremental flows at scale, switch-join, the
  deferred incremental-collections question.
- **a text editor with undo** — transformation-levels (program and history
  as one structure) meeting a runtime document.
- **a game loop** — fixed-timestep timer stream, registers, incremental
  render; fairness and priority pressure.
- **a build system** — divide flow (dependency recursion), pool,
  incremental recomputation, and bracket, all at once.

Method note for future rounds: pick one and work it to the same depth as
this document's five — writing it against the blocks until it breaks —
rather than surveying many shallowly. The backlog is a queue, not a
checklist.

### Object permanence as a theme

A concept, not a building block: **swap the copy default.** Ordinarily
values copy freely — writing an object into one slot doesn't remove it from
another. Permanence inverts that for a designated object: putting it in a
result *takes it from* the source; there is exactly one of it, and it is
wherever it last moved. Prior art in text languages is linear/uniqueness
typing and ownership systems — but the visual reading is native here in a
way those systems had to encode in types: **the wire is the object.** A
permanent value's wire is identified with the unique object, not with a
description of it, and the object goes where the wire goes.

That reading makes the discipline *structurally checkable* with machinery
the language already has. Sharing in this language is visible: bind once,
reference twice, fan out at a junction. So permanence of a wire is simply
the demand that it **not fan out** — exactly one consumer — a graph check
of the same species as no-time-travel and provenance. And the design
record already contains one instance of it: the one-write-per-DelayRead
rule from the (retired) first-class-ports round (see `src/Program.res`
and `src/ARCHITECTURE.md`) is a linearity check on the register's
back-edge, arrived at independently.

Three worked glimpses of what the theme does to blocks:

- **Comparison returns the values, not a Boolean.** Under permanence,
  comparing two objects can't yield `true` and quietly keep the objects
  available for re-reading — it yields *the two objects, in order*: a
  two-in-two-out barrier (smaller out, larger out), the no-bottleneck
  principle applied to ordering. Sorting networks are the existence proof
  that this scales visually — compare-exchange nodes and wires carrying the
  objects are literally what a sorting-network diagram is. The
  decision-driven merge under permanence carries *the* elements of both
  inputs through to the output, and "no element duplicated or dropped"
  stops being a property to test and becomes a property of the wiring.
- **The pool matches the world.** Use case 2's live-set var, read through
  permanence, doesn't hold bookkeeping *about* devices — it holds *the*
  devices. There is a real set of MIDI devices out there; udev add-events
  grant possession of one; terminators return it; the display renders what
  the program holds. No-duplicates-and-nothing-missing is then not an
  invariant maintained by careful fold logic (the place the hand-written
  version had its bug) but a conservation law the wiring can't violate.
- **Existing obligations are permanence claims.** The served flow's
  respond-exactly-once obligation is linearity of the exchange; bracket's
  use-exactly-once release is linearity of the resource; `bounded(n)`'s
  permits are permanent tokens. Three blocks in this document independently
  reinvented fragments of the theme, which is the usual sign a theme is
  real.

Status: a lens to hold candidate blocks against — "would this be simpler,
or its guarantee stronger, if the value were permanent?" — and a candidate
for eventual promotion alongside the six principles if it keeps earning;
not promoted here. Open threads if it gets a round: how a permanent wire
crosses a flow boundary (does an open borrow or take?); permanence vs the
memo (sharing machinery is precisely what it forbids per-object); whether
fan-in (merging possession) is dual to the forbidden fan-out; and escape
hatches (an explicit copy node — visible, so the discipline stays
structural).

### Facets: partial views against crowding

Visual languages have a deserved reputation for becoming *literal*
spaghetti at even moderate complexity — every wire drawn is every wire
seen. One answer to record: **facets** — ways of viewing a chunk of a
program that deliberately don't show all of it. The motivating example:
code organized around a state machine could be viewed *as a state diagram*
— states and transitions visible, the per-transition computation hidden.

The concept is not foreign to the record. The design already contains one
facet, hardcoded: the function interface is the "flow skeleton with data
holes" — flow structure shown, data operations hidden, produced by
proven-sound rewrites so that no-time-travel and soundness remain
checkable across the boundary. The facets idea is that projection
generalized from one built-in view to a family: flow-skeleton,
state-diagram, the value-dataflow-only view, the concurrency/timing view,
a possession view (which wires are permanent objects and where they
currently are). Each hides dimensions; none is the program.

The tricky part, named honestly: facets are very hard to make flexible,
because **code is rarely a perfect instance of the facet's vocabulary** —
it is a state machine that sometimes branches parallel execution paths, or
backtracks, or escapes into ad-hoc handling. Two routes to a facet, with
different exposure to that problem:

- **Recognition**: find the state machine hiding in general wiring and
  render it. Flexible in principle, partial and fragile in practice — and
  the philosophy already says so: "abstraction is earned and upward";
  recovering a high-level form from a concrete one is partial recognition.
- **Projection of authored structure**: if the state machine is an
  *authored* high-level construct (the custom protocol flow of use case 5
  is exactly this), then its state diagram is a derived view — free,
  downward, total by construction, per "abstraction is the source of
  truth". Imperfection then stops being a rendering failure and becomes
  *marked structure*: the parallel branch is a visible composite region,
  the escape into detail is a marked exit, because the user authored a
  state machine *with escapes* and the facet projects what was authored.

The philosophy clearly leans to the second route as primary (with
recognition as the earned, partial path for hand-rolled shapes) — which
quietly strengthens the case for authored high-level blocks generally:
every block whose round this document proposes is also a facet
opportunity, since an authored construct can always project a summary view
of itself, while wiring that merely *implements* the pattern cannot.

One more mitigation worth naming: part of the flexibility problem
dissolves if the facet's own vocabulary is chosen richly enough. The
imperfections listed above — parallel paths, returning to where you were —
are precisely what Harel statecharts added to flat state machines
(orthogonal regions, hierarchy, history states). A facet family should
steal from notations that already survived contact with real systems
rather than inventing minimal diagrams and drowning in their residue.

Open threads if facets get a round: the facet inventory (which views, per
construct); residue marking (how a facet shows "there is more here"
without showing it — the data-hole convention is the precedent); whether
authoring *through* a facet (add a state on the state diagram) is
admissible as a construction step on the underlying program, which is
transformation-levels territory; and the boundary with the visual/layout
side — facets are about *what structure is shown*, not how it is laid out,
but the two meet at the canvas and the split should be kept clean.

Too big a topic to explore now; recorded so the crowding problem has a
named answer and the protocol-flow round knows a facet is among its
deliverables.

## What this doesn't address

- **Visual depiction.** What a served open, a concurrency species marking,
  a lane key, a bracket region, or a divide link look like on the canvas —
  out of scope in this repo. One note to pass across: the concurrency
  species and the bracket are *region* properties, and the incremental doc
  already flagged that standing regions may want visual distinction from
  per-element ones; these are more clients of that.
- **True parallelism.** Everything here is event-loop concurrency; the
  pool is interleaving, not workers. Worker parallelism would revisit use
  case 2 with shared-nothing constraints.
- **The IO design itself.** This document generates requirements for it
  (collected above) and deliberately stops there.
- **Priorities and fairness.** A pool draining a hot device can starve a
  cold one between pulls; inherited from the async doc's open question 7,
  sharpened by the pool but not advanced.
- **Implementation.** All of this sits on the unimplemented
  stream/async/incremental runtimes; nothing here changes their dependency
  order, though the concurrent collect slots in immediately after async
  streams, and bracket waits on cancellation, which waits on IO.
