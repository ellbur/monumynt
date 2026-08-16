# Language cheat sheet

*Or: every part of the language on one page, each with the smallest
example that shows it.*

Status: derived quick-reference, written 2026-08-16. This page is a
**view of the record, not part of it** — it decides nothing, and when
it disagrees with a construct's own doc, the doc wins. It lists the
**most up-to-date desired design**: where a newer round revised a
construct (the thread over the old delay operand, collect-until over
standalone end-when), the newer surface is what appears here. Much of
what follows is design, not code — the status tag on each entry says
which. Tags:

- *(implemented)* — true of `src/` today.
- *(adopted)* — settled design, not necessarily built.
- *(exploration)* — a worked proposal with leanings, not adopted.
- *(spelling provisional)* — the construct stands but its textual
  spelling is a strawman owed to the textual round; read the example
  as a sketch of the drawn structure.

The notation itself is `textual-representation-design.md`; the model
is `core-model.md`. Comments run from `--` to end of line. One glyph
caveat: `@` currently serves three different rounds (the thread's
sigil, the site's thread anchors, the id suffix `sum@n42`) — all
provisional; the naming sweep owns the collision.

---

## Values and application

**Extern — borrow a JavaScript function.** `js "…"` is the escape
hatch to JS; `name = …` (left assignment) is the short form for leaf
definitions. *(implemented)*

```
double = js "x => x * 2"
ten = 10
```

**Chain — forward application.** Write the value first, then what
happens to it. `a -> double` means `double(a)`. *(implemented)*

```
3 -> double => six
```

**Naming a result.** `=> name` is the last stage of a chain, not a
statement wrapped around it. A binder can name several output ports
at once (`=> a, ~L`). *(implemented)*

**Chains across lines.** Any stage may start a new line; a leading
arrow continues the previous chain. *(implemented)*

```
xs -> open list
   -> double
  -~> collect
=> doubled
```

**Extra inputs.** In chain position the chain's value is the first
argument; extra inputs go in parentheses. When the topic is not the
first argument, use the full comma list. *(implemented)*

```
xs -> open list -> add(ten) -~> collect => bumped
ten, x -> sub                    -- sub(ten, x)
```

**Grouping.** A source-list item may be a short parenthesized chain.
Parentheses are grouping, not scope — they bind nothing.
*(implemented)*

```
(a -> sq), (b -> sq) -> add -> sqrt => c
```

**Infix operators and sections.** `+ - * / %` are accepted infix —
sugar for an App of the operator's extern, no new node kind. In chain
position an operator is a section on the running topic.
*(implemented — parsing; infix printing is an open printer question)*

```
a2 + b2 -> sqrt => c
[1, 2, 3] -> open list -> * 2 -~> collect => out
```

**Accepted input vs canonical print.** The grammar is permissive —
prefix `f(x, y)`, name-first `b = double(a)`, infix — but the printer
is canonical and forward: chains, right-hand naming, producers before
consumers, token order is time. *(implemented)*

## Names, sharing, and pronouns

**Naming is sharing.** Writing `double(a)` twice mints two nodes. To
share a computation, name it and reference the name — a name used
twice is fan-out from one port. Names are single-assignment and
global to the diagram: anonymous is linear, named is shared.
*(implemented)*

```
a -> double => d
d, d -> add => quadrupled        -- one double node, referenced twice
```

**Junction tap `|` — fan-out without a name.** A `|` mid-chain mints
a tap; a line beginning with `|` resumes from it. Binding is ordinal
(k-th leading `|` ↔ k-th tap of the nearest tap-minting line), never
by column. *(implemented)*

```
req -> parse -> | route => target
| -> logLine -> emit => logged
| -> checksum => sum
```

**Value mark `^` — fan-in without a name.** A terminal `^` marks a
chain's value as pending; a `^` in source position uses the front of
the queue (FIFO: k-th use ↔ k-th mark). Marks are linear and
terminal-only. *(implemented)*

```
a, a -> mul ^
b, b -> mul ^
^, ^ -> add -> sqrt => c
```

**The diamond — tap plus marks, zero names.** *(implemented)*

```
data -> parse -> | max ^
| -> min ^
^, ^ -> sub => range
```

**Flow shorthand `~` and `~^`.** In a statement with a flow operand
and no value to derive it from, bare `~` is the innermost live flow,
`~^` the one outside it. Desugars at parse, like every pronoun.
*(implemented)*

**Ports and projections.** A binder names the node; the bare name is
its principal value port, `~name` its principal flow port. Projection
reaches named ports: `cs.Just` is a value port, `~cs.Just` the flow
port of the same name. There is no Branch construct — a branch *is* a
reference to one output port of the split. *(implemented)*

```
xs -> open list => a, ~L
m -> split isJust of Just, Nothing => cs
cs.Just -> double => x
```

## The loop: open and collect

**Open / collect — the fundamental pair.** A "loop" is a stretch of
wire between an open (uncollect) and a collect. Between them the wire
carries one element at a time. There is no loop body and no block —
the interior is explicit values and flows. *(implemented)*

```
[1, 2, 3] -> open list -> double -~> collect => out    -- [2, 4, 6]
```

**Three arrows, two wire sorts.** `->` carries a value; `~>` a flow
(the execution context — when, and how often); `-~>` a value together
with its flow, which is what collect consumes. Flow references carry
the `~` sigil. Mixing sorts is a parse error. *(implemented)*

**Multi-close — one loop, several results.** One open can feed any
number of collects; each is an independent consumer of the same
logical iteration. *(implemented)*

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

**Values from outside — just use them.** A value from an enclosing
context needs no transport; the prefix rule admits it anywhere
deeper. The explicit bringing-in step is **incorporate**, spelled
`in` where it needs saying at all. *(implemented; `in` clause
implemented for opens)*

```
ten = 10
[[1, 2], [3]] -> open list -> open list -> add(ten) -~> join -~> collect
=> out                                                 -- [11, 12, 13]
```

**Nesting and join — flatten.** Opening twice gives a flow within a
flow; **join** is the binary flow operation (outer, inner) that
absorbs the inner flow's firings into the outer. In a chain, bare
`-~> join` merges the two innermost layers of the value's context —
no operand needed. *(implemented)*

**Filter is a join.** There is no filter primitive: joining a flow
with one of its case-alt flows keeps exactly the firings where that
alt fired. *(implemented)*

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens
  Odd:  -~> join -~> collect => odds
```

**Explicit flow operands.** When the chain value is context-free
(e.g. a constant), the collect names its flow: `5 -~> collect ~L`
builds a list of fives. Standalone flow statements exist too:
`~c.Even ~> join into ~L => ~keep`. *(implemented)*

**Commute — reorder nested layers.** Swaps the two innermost layers
so you can close the inner loop while the outer stays open. Bare in a
chain; standalone it names its operands, inner first. Defined per
flow-kind pair; over a Cross product it is transpose and always
defined. *(implemented for the core cases)*

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option layer still open
perElem -> summarize -~> collect => report
```

**Open option.** The one-or-zero flow: fires iff the value is Some.
*(implemented)*

```
m -> open option => v, ~O
```

## Case splits

**Split with fused lanes.** `split <discriminator> of <alts>` opens a
case-typed value into a bundle of mutually exclusive sibling flows,
one lane per line. An exhaustive case collect gathers the lanes back
into a single value. *(implemented)*

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                    -- case close: one value per alt
-~> collect                    -- closes the list flow
=> out                         -- [2, 0, 10]
```

**Lanes spread across the program.** Lanes are sugar for the named
form; nothing requires a split's branches to sit together —
membership is dataflow, not adjacency. *(implemented)*

```
m -> split isJust of Just, Nothing => cs
cs.Just -> double => x
-- … unrelated statements …
~cs.Just:    x
~cs.Nothing: 0
-~> collect => out
```

**Implicit branch `value~`.** A branch value that carries context
supplies its flow implicitly; the suffix `~` is the noun form of
`-~>` — the value together with the flow it lives in. *(implemented)*

```
m -> split isJust of Just, Nothing => cs
  Just: -> double => y
y~
~cs.Nothing: 0
-~> collect => out
```

**Partial collect — close only some branches.** One k-ary node:
branches are (value, flow) pairs over pairwise-disjoint cells of one
bundle; one value output, one merged-flow output. Coverage is read
off the cells — a covering collect has no flow output (it *is* the
case collect); a partial one fires zero-or-one per parent firing.
*(implemented; the surfaced name is open — it should not contain
"collect")*

```
resp -> split status of Ok, Redirect, ClientError, ServerError => h
~h.ClientError: h.ClientError
~h.ServerError: h.ServerError
-~> collect => errCode, ~err   -- partial: value + merged flow
~h.Ok:       "ok"
~h.Redirect: "moved"
~err:        errCode -> describe
-~> collect => report          -- exhaustive: cells cover the bundle
```

**Default value — engage the empty branch.** Not a partial collect:
the None branch supplies a constant in an exhaustive collect.
*(implemented)*

```
maybeN -> split isJust of Some, None
  Some: -> f
  None: 5
-~> collect => out
```

## Flow kinds

One open/collect shape, instantiated per kind. *(list and
case/option implemented; stream implemented in its first round; the
rest designed)*

| kind | opens into | collect yields |
|---|---|---|
| list | each element, in order | a list |
| case / option | the matching alt / fires iff Some | exhaustive value / option |
| stream | each element, on demand (pull) | a stream |
| async | the value, later | an async value |
| incremental (var) | the current value, over time | a var |

```
chars -> open stream => c, ~S      -- pull-based, on demand
```

## Loop-carried state: the register

**The thread — current surface.** Loop-carried state (a running sum:
"prior + element → next, repeated") is a **thread**: a third
connector species (`@`, provisional sigil) saying *this point
corresponds to that point across iterations*. The read anchor's law:
its value at iteration n is the write anchor's value at n−1, or the
init when no prior iteration exists. The frame is **derived from the
anchors' contexts** — no flow operand on the register.
*(adopted 2026-08-04 as the working surface; spelling provisional)*

```
xs -> open list => a, ~L
0 @s, a -> add => nextSum @s       -- read anchor (init 0), write anchor
```

**The register pair — the stored form.** The thread stores as a
read-half/write-half pair, and the record's worked examples are
written in that two-statement spelling: mint the read, wire the step
later. (The `~L ~>` flow operand in this spelling is retired by the
thread revision — read it as the thread's frame, now derived.)
*(adopted 2026-07-23; examples verbatim from the record)*

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum               -- read half; bare `sum` = prev
sum, a -> add -> step of sum => total   -- write half; binder = final
```

**Cross-referencing registers — Fibonacci.** Registers are ordinary
wires to each other; every cycle passes through a register (the
productivity rule), so text never references forward.
*(adopted)*

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA
fa, fb -> add -> step of fb => lastB
```

**The exit is a scoop of the read port.** The final value is read at
whichever closer the author wires, under the same
write-at-n−1-else-init law — so the empty walk yields the init for
free, and a walk cut early scoops state-at-the-cut.
*(adopted 2026-08-04; spelling owed)*

**Explicit frames — `in ~flow`.** Where the derived frame is
ambiguous (nested loops: carry across the outer?) or absent (pure
state loops on self-driven flows), the thread says its frame with the
existing `in` clause: `@s in ~L`. Mandatory only where nothing can be
derived. *(adopted 2026-08-04)*

**Which flows allow a register — the owned-order criterion.** A flow
supplies a "next iteration" exactly when its firings carry a total
order the flow's *meaning* owns (list walk, stream, self-driven flow,
event stream — yes; concurrent bodies, sibling instances, the
incremental var flow — no; a product is the surplus-order residue).
*(adopted 2026-07-23)*

**Hold — sample a register onto a wider flow.** A register whose
update flow is nested strictly inside its read flow is total (last
write, else seed), so it can be read on the outer frame: forward-fill,
sample-at, "value as of the last event" are one construct.
*(adopted identification; spelling provisional)*

```
readings -> open list => r, ~L
r -> open option => v, ~O
~O ~> delay init 0 => nSeen
nSeen, 1 -> add -> step of nSeen => count
count -> hold init 0 over ~L => held
held -~> collect => progress       -- progress[i] = #valids at or before row i
```

## Ending and segmenting walks

**Collect-until — stop early and fold what came before.** End-when
fused with its collect: the node consumes (flow, value) input pairs —
a stop pair and an optional prefix pair — folds the firings before
the stop's alt first fires, and emits the terminal reason as a tagged
value (`Stopped` / `RanOut`). Payloads travel value wires;
terminators carry only the reason a flow ended.
*(construct adopted 2026-07-23, fusion revised 2026-08-04; spelling
provisional)*

```
xs -> open list => a, ~L
a -> split find => s                    -- alts Match, Other
~L, ~s.Match ~> collect-until of (a => prefix), (s.Match => term)
term -> split ended of Stopped, RanOut
```

**The cut — the root of the family.** A binary flow operation
(subject, boundary) with two flow outputs: the prefix up to the first
boundary firing, and the continuation after it (empty, not absent, if
the boundary never fires). End-when is the cut with the continuation
unconsumed; a single cut fuses into its collect (collect-until);
the iterated cut does not. *(root adopted 2026-07-23; the cut round
itself exploration; spelling owed)*

**Split-when — the iterated cut.** Cuts one walk into consecutive
segments at every boundary firing, minting an outer flow of segments
(the home of once-per-segment values — why it stays a flow
operation). Per-segment state is a register on the inner flow; the
nesting is the reset. *(re-founded 2026-07-23, revised 2026-08-04;
spelling provisional)*

```
chars -> open list -> split kind of Space, Letter
  Space: -~> split-when         -- outer flow: segments; inner: one word's chars
-~> collect => words            -- one result per word
```

**Late-wired operands — `<port> of <name>`.** Every construct that
sits on a cycle takes one operand in a second statement referring
back to the minted node: the register's `step of`, split-when's
boundary, a collect's running view. Token order stays time because
the back half is always a later statement. *(the register's form
adopted; the general family is the textual round's finding)*

## Sources: flows with no input list

**Open self — the self-driven flow.** Asserts repetition with
nothing to open: no value ports, no operand; extent unbounded, all
shortening consumer-side. This is where a thread's `in ~R` frame
annotation is mandatory. *(exploration; spelling provisional)*

```
open self => ~R          -- mints a self-driven flow; nothing feeds it
```

**External pull source.** An outside iterator consumed until *it*
says stop — value → firing, exhaustion → RanOut, raise → Fail, as a
catalog block. *(exploration; spelling provisional)*

```
lines = source js "() => getline(false)"
lines -> open stream => line, ~P
```

**Paced — gate the next firing.** A binary flow operation: firing
n+1 of the subject is demanded only after a per-firing async gate
settles. The gate must be minted per firing (`in ~R`); its value is
discarded — only settlement matters. *(exploration; spelling
provisional)*

```
open self => ~R
sleep(5) in ~R => d              -- per-firing timer
~R, d ~> paced => ~R'            -- next firing waits for d
```

**The merge — a walk over k cursors.** When no input flow drives the
iteration (mergesort's merge, fair arbitration): one node exposes
per-step heads and a minted step flow, and takes a late-wired advance
operand. The decision is ordinary drawn vocabulary — a case split, a
race, a register read — never a comparator argument; stopping is
collect-until on the step flow. *(exploration; spelling provisional)*

```
a, b -> merge => ha, hb, ~M          -- heads + the step flow
split present ha, hb of Both, OnlyA, OnlyB
  Both:  ha, hb -> le -> split of TakeA, TakeB
           TakeA: -~> advance of ha
           TakeB: -~> advance of hb
  OnlyA: -~> advance of ha
  OnlyB: -~> advance of hb
~M -~> collect => merged
  TakeA | OnlyA: ha
  TakeB | OnlyB: hb
```

## Products of flows

**Cross — combine two independent iterations.** Two sibling flows in,
the same two flows out, now nested (all pairs) — nothing packed; each
axis's element rides unchanged. Cross is what completion inserts for
sibling opens (never incorporate, which would erase their
independence). The stored node carries an orientation; consumers may
read either. *(exploration with a recorded lean; spelling
provisional)*

```
listX -> open list => x, ~x
listY -> open list => y, ~y
~x, ~y ~> cross => ~xy           -- provisional spelling
x, y -> add => s
s -~> collect -~> collect => table
```

**Commute over a product is transpose.** Always defined (crossed
pairs are never ragged); derived where the consumer's order doesn't
matter, authored where it does. *(exploration)*

```
~yx ~> commute => ~xy
```

**Join on a product — orientation as drawn data.** A join chain
consumes a product axis-by-axis; the operand order *is* the read
orientation (row-major vs column-major), drawn on the page.
*(exploration)*

```
~d, ~q  -> join => ~dq                 -- commits dept-major
~co, ~dq -> join => ~line              -- absorbs the pair into the company walk
r -> format => txt
txt -~> collect => report              -- flat, in the committed order
```

**Zip — the aligned product.** Same-extent pairing by position: one
flow out, widened by the second lane's value wire, no new firings.
Same-provenance zip is free and drawn as nothing (two opens of one
walk are already aligned); distinct-provenance zip asserts co-extent
once at the start. An index is an aligned lane, not a loop mode.
*(exploration; no spelling yet)*

**The multi-wire collect — the table.** k value wires of one flow
collected at one barrier: k columns, one row per firing; its
uncollect gives the wires back already aligned. "A table is k lists
that remember they were collected from the same walk." *(exploration;
no spelling yet)*

**Orientation pinning.** On any path from a Cross to an
order-observing consumer (a non-commutative register, a spanning
effect), the orientation is semantics and must be authored — or the
completion's pick surfaced loud. Discharged by commutativity: `sum`
over a table pays nothing. *(exploration)*

## The collect family

**Reducing collects.** A collect that collapses a flow with an
associative operator — no seed, no accumulator variable. Named forms
are catalog rows, not node species. *(availability ladder adopted
2026-07-23; spellings provisional)*

```
xs    -~> collect sum => total
flags -~> collect any => anyChanged
xs    -~> collect set => distinct          -- dedup, first-appearance order
xs    -~> collect last => finalX           -- option-shaped output
masks -~> collect by and => combined       -- any catalog/facet operator
```

**The availability ladder — what an empty flow yields.** Monoid
(identity exists) → total, empty yields the identity. Semigroup
(associative, no identity) → option-shaped: the output fires iff the
flow fired (`first`, `last`, `min`, `max` live here — no fake ±∞
identities). Non-associative → no reduce-close at all; write the
augment (explicit seed, explicit step) — supplying a seed is a change
of construct, not a parameter. *(adopted 2026-07-23)*

**Keyed collect — group-by as flows.** A barrier grouping a flow's
firings into lanes by a per-firing key. The fused form is the
everyday spelling; the partition (lanes flow + within-lane flow) is
what it lowers to. Collisions dissolve — a collision is a lane with
several firings, and the per-lane operator answers it. Keys are
ordinary drawn computation, never extractor functions.
*(exploration; spelling provisional)*

```
k, v -~> collect keyed by add => totals    -- fused: per-key running sum
k, v -~> collect keyed => groups           -- bare: map of lane-lists
k, v -~> collect keyed from seedMap by add => table
```

## Async and reactive

**Open async — the value that arrives later.** Opens into the
resolved value and the async context; everything consuming the value
happens after arrival. Sequencing is nesting — B can't start before A
because B's input doesn't exist earlier. No `await` keyword.
*(exploration)*

```
url -> open async => resp, ~A
resp -> next -> open async => body, ~B   -- ~B nested in ~A: strictly after
```

**Parallel is the concurrent join.** Sibling opens merge their
contexts at a product barrier; wall time is the max. `Promise.all`
derived from structure, not named. *(exploration)*

```
urlA -> open async => a, ~A
urlB -> open async => b, ~B
~A, ~B ~> join all => ~ab
a, b -> combine -~> collect => out
```

**Race — first to settle wins.** N contenders in, a bundle of N cells
out: cell i fires iff contender i won, carrying its value — no tagged
union crosses the barrier. Losers are abandoned, not cancelled; ties
among already-settled contenders go to drawn order. *(exploration;
lane spelling as below)*

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

**Timeout is not a construct.** It is where the timer cell is minted:
`race(subject, timer(d))` one-shot; interrupt with the timer outside
the walk = whole-walk deadline; the timer minted inside the per-pull
body = per-step. *(exploration)*

**Settle — take async results as they finish.** A binary flow
operation (subject, per-firing async body) minting a **completions
flow**: one firing per body that settles, in settlement order, with
the settled sum (`Ok(x) | Fail(e)`) as data — the supervisor consumes
failures, it doesn't die of them. Bodies overlap; the completions
flow drains every started body before terminating. *(exploration;
"settle" is a placeholder name)*

```
open requests => req, ~S
handle(req) in ~S => body          -- async, per firing
~S, body ~> settle => ~C, res      -- completions flow + settled result
~C: res -> deliver
```

**Open var — the incremental (reactive) flow.** Opens a var into its
current value and a tracking context; the collect is a derived var
kept consistent as inputs change — at most one recomputation per
affected node per mutation. Combining vars is the concurrent join
again. *(exploration; spellings provisional)*

```
price -> open var => p, ~P
qty   -> open var => q, ~Q
~P, ~Q ~> join all => ~PQ
p, q -> mul -~> collect => total   -- recomputes when price OR qty changes
```

**Hold and changes — the mutation and observation boundaries.**
`hold init` turns an event stream into a var (a register over the
event stream whose step ignores prev); `changes` turns a var back
into a stream of its new values. Accumulation is scan-then-hold.
*(exploration; spellings provisional)*

```
clicks -> open stream => _, ~C
~C ~> delay init 0 => n
n, 1 -> add -> step of n => running
running -> hold init 0 => count        -- the var: current click count
count -> open var => c, ~V
c, 2 -> mul -~> collect => label       -- derived var
label -> changes -> drain => log       -- observe
```

## Effects and IO

**Per-firing effect — do something once per element.** An effect op
is a stage on a handle's chain, with `in ~flow` naming the flow it
fires per firing of. Spanning handle (top vertex outside the loop) =
ordered by the loop; handle minted inside the firing = independent,
unordered — told apart by the drawing, never by a mode.
*(exploration; spelling provisional)*

```
lines -> open list => line, ~L
in ~io                              -- the console handle, from outside
~io ~> print(line) in ~L => ~io'    -- one print per line, in order
```

**IO is a flow, not a handle.** The core reading: an op *uncollects*,
minting a baby IO flow that must join into one global IO flow;
`join(outer, inner)` means outer's operations happen before inner's —
sequencing is join's existing asymmetry, and the handle wire is the
derived spelling of the join order. Handle chains and baby-flow joins
are one program, two spellings. *(recorded direction 2026-07-23;
exploration)*

**The sequencing commute — never drawn.** Commuting an IO flow out
of a list flow concatenates the per-firing segments in firing order
into one segment — one handle out, never a list. It is mandatory and
unique, so it is never authored and never absent: inferred by
published rule, shown faint. Consuming the handle after the loop does
the job. *(exploration)*

**Conditional effect — the case collect selects flow wires.** "If
the line is abc print yes, otherwise nothing": the collect's flow is
the firing cell's continuation, the same verbatim law as the value
case collect, extended to flow wires. In the core reading the Other
branch contributes the empty IO flow — absence of effects needs no
identity lane. *(exploration 2026-08-16; spelling provisional)*

```
readLine => line, ~r                 -- op mints its baby io flow
line -> split check of Abc, Other => cs
print("yes") => ~p                   -- born in the Abc cell
~cs.Abc: ~p
-~> collect => ~c                    -- partial: Other contributes nothing
~r, ~c ~> join => ~io                -- join order is the sequence
out ~io
```

**`in` is the incorporate.** The `in ~flow` clause on an op is the
incorporate operation — subordinating a wire to a deeper flow
context. Like the sequencing commute, it is inferable when
unambiguous (shown faint), authored only on genuine ambiguity.
*(ruled 2026-08-16; exploration)*

**Within a firing there is no time.** The only order inside a firing
is order along a handle's segment; everything else is data
dependence. Cross-handle order does not exist — a handle *is* an
ordering commitment, and minting granularity follows observability.
*(exploration)*

```
req -> connect => ~s              -- fresh handle inside the firing
~s ~> sendHeader(req) => ~s'
~s' ~> sendBody(req) => ~s''      -- ordered by the chain
~s'' ~> closeConn
```

**The conditional-flush buffer is segmentation.** A buffer appended
per firing and flushed at boundaries is no register at all: the
buffer is a per-segment collect, the reset is the boundary (a nested
collect starts empty), the flush is one write op per segment on the
handle threaded through the segment flow. The forgotten-final-flush
bug is unwritable. Whether a boundary is meaning or optimisation is a
catalog row ("this sink's write coalesces"). *(exploration)*

**Cancellation — nothing to author.** A program never cancels
anything; it stops demanding (a race settles, an interrupt cuts, an
end-when ends), and the runtime delivers the ceased demand as a
`Cancelled` terminator to the stranded work, at yield points, over
the necessity frontier. There is no cancel token in the vocabulary.
*(exploration)*

**Bracket — the release half on the acquire.** Acquire, use, release,
with the release late-wired at the acquire and guaranteed to run on
whichever way the segment ends (done, failed, cancelled). Granularity
is vertex placement: acquire under a firing = per-firing bracket;
outside the loop = per-walk. Release cannot fail, structurally.
*(exploration; spelling provisional)*

```
path -> openFile => ~f                 -- acquire: top vertex, failable
~f ~> write(line) in ~W => ~f'         -- use: ops along the thread
release of ~f: close                   -- release half, late-wired
```

**Custom flow kinds — the lifecycle segment.** A flow wire can carry
the open lifetime of a resource: creation at the top vertex,
operations strung along, destruction at the bottom. "You cannot query
a closed database" is an unwireable program, not a runtime check. A
custom flow is a C-shaped sub-diagram used flow-wise (see the reuse
section). Effect-handle flows commute freely; structural flows never
cross implicitly — inferred from the definition, never annotated.
*(exploration; spelling provisional)*

```
conn -> open db => ~D
sql, ~D ~> query => rows, ~D2
~D2 ~> close
```

## Failure

**A may-fail step is a case split.** There is no failure construct
and no `fail` node (dissolved 2026-08-04): a step that can fail is an
ordinary split whose alts are Error and Success, and the split is the
minting site. Failure data travels a drawn flow wire to wherever it
is handled — never silent propagation, never an ambient failable
type. *(the dissolution adopted)*

```
srcs -> split isSourceList of Ok, Bad
  Ok:  -> open list -~> join
  Bad: name -> setupError          -- the error, on its own drawn wires
```

**Short-circuit vs accumulate — where the alt's collect sits.**
Collect the Bad alt *beside the walk* (nesting intact) and you
accumulate every error; collect it *alone, outside the walk* and the
case dimension must commute out first — the inferred short-circuit
commute, drawn faint, selecting the first error. The faint commute is
the at-a-glance abort marker. Schematically:
`List (Error e + Success s) -> Error firstError + Success (List s)`.
*(adopted 2026-08-04)*

**A close's result is a case bundle iff some alt commutes out at
it.** That derived fact replaces "this flow is failable" — no
annotation anywhere. What failure data can arrive at a wire is
**alt-reach**: the set of minting splits whose error alts reach it,
propagated by existing case-alt rules. *(worked, not adopted)*

**The JS edge.** A declared throw or rejection enters by catalog row
as an Ok/Err case bundle — the row is the minting split. Undeclared
throws are quarantined on the **background super flow**: one
runtime-owned lane that silently commutes out of everything, costs
nothing when unhandled, and compiles to a try/catch only where
collecting it is drawn. Bodies do not raise — settled. *(super flow
adopted 2026-07-23; bundle rows a worked direction)*

**The scoop.** How a value gets out of a flow at a barrier: a
selecting node takes a (flow, value) pair and mints the selected
value at its output context — race's winner payload, collect-until's
terminal, the short-circuit commute's first error. Inference may
route a drawn wire through a scoop, never invent a selection.
*(adopted 2026-08-04)*

**The tunnel — stow / unstow.** The sanctioned packed transport:
deliberately pack a (case flow, value) pair into one wire, ship it
through any number of nesting levels, unstow at the distant handler.
For payloads the author deliberately does not want to look at — never
the default the language teaches. *(exploration)*

**Speculation — try in order, first success wins.** Ordered
alternatives, each failable, all reading the same input wire — which
is why rollback is structure, not a save/restore operation. Cell i
fires iff contenders 1..i−1 declined and i succeeded; a `commit`
marker upgrades later fails from soft (try next) to hard (stop).
*(exploration; spelling provisional)*

```
p -> | parseLet     -- the shared input, fanned to each contender
     | parseApp
-> speculate => r
~r.parseLet:  r.parseLet -> LetNode
~r.parseApp:  r.parseApp -> AppNode
-~> collect => expr          -- one AST; whichever alternative won
```

**The election rule.** A flow shortened by a commute cannot be
shortened again by a commute without an explicit election — the
series-priority trap ("first A, else first B" silently reversing
time) is impossible to draw by accident. The safe program is the
barrier: **join, then commute, then split** — merge your channels,
then shorten once, time-ordered, unmarked. *(adopted 2026-08-16)*

## Reuse and abstraction

**A function is a remembered cut.** Write the concrete program
first, then select nodes and cut: each severed wire becomes a port
(ports come from the cut, never the cut from the ports); each wire
left intact stays environment, shared by every call. Calls keep the
chain-stage spelling. Using a diagram has exactly the behavior of
pasting its node set — no interface memory, contexts re-derived per
instance. *(adopted 2026-07-23, geometry revised 2026-08-04)*

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

**Membership is derived — the prefix rule.** A node is per-call iff
it is downstream of an in-port; everything else the cone reads is one
shared value every call reads. Closure capture dissolves — there is
no scope to capture into. *(adopted)*

```
diagram circumference
  in r
  tau = 3.14159 -> mul(2)        -- reads no in-port: shared, once
  r -> mul(tau) => c
  out result = c
end
```

**Partial cuts are local functions.** An uncut wire is a free wire;
the call site is legal anywhere the uncut wires' contexts are a
prefix. Widening is cutting one more wire — a +1 gesture, never a
rewrite. Linear values force port-ification (an uncut handle read
from two call sites is forbidden fan-out). *(adopted)*

**Flow ports are the drawn call-by-name.** Values through ports are
pure — call-by-value; wanting the diagram to manage whether and when
something runs is a flow port. The language never picks a default —
the distinction is wiring. *(adopted)*

```
diagram print_string
  in s
  in ~io
  s, ~io ~> put => ~io2
  out ~io2 = ~io2
end
```

**A late-bound operation is a port pair.** An operation whose
meaning is supplied per use — the test double, the policy layer — is
an out-port and an in-port on the boundary, nothing more (`op` is not
a species; `with … = …` binding is rejected). Binding is wiring code
between the two ports; the exchange correspondence is the wiring
itself, one exchange per dynamic use. Unmet demands keep crossing
outward, cut after cut, until some binding wires a provider on.
*(adopted 2026-07-23, revised 2026-08-04; spellings owed)*

```
diagram wordCount
  in path
  op read                          -- read: an out-port/in-port pair
  path -> read => text
  text -> splitWords -> length => n
  out result = n
end
```

**The abstract wire and the C-shape.** `out p ... in q` states the
expectation that the answer derives from the question; an out-port
upstream of an in-port draws as a cutout — the caller's code wired
into the hole. A custom flow is a C-shaped sub-diagram used
flow-wise; a middleware (logging, retry, cache) is provider-shaped on
one side, consumer-shaped on the other, spliced into the hole — which
policy wraps which is where the splice sits. *(adopted revision;
spellings provisional)*

**Facets group operations that travel together.** One port pair per
operation, never one pair with tagged requests; binding matches by
drawn facet identity. A sequenced algebra carries a handle (provider
may be stateful); an unordered one forbids provider state — the same
bit. *(exploration; spelling provisional)*

```
facet FileOps = algebra { open, read, close }
```

**Configuration scopes — wire the lambda body in.** The comparator,
predicate, or key another language passes as a function: open the
operation as a scope, wire what would have been the body, close. A
scope is not a flow (it cannot join, commute, or partition); it is
the C-shape where demand and binding coincide at one use site.
*(exploration; spelling provisional)*

```
list -> open sort => item, ~S
item -> sortKey -~> collect => sorted
```

**Served flows — flows whose firings are exchanges.** A request in,
a response owed back; the collect *is* the response (exactly-once is
the collect's law). One construct, two ends: the client end is the
port pair, the server end a provider diagram — and which one is "the
server" is a property of a binding, so the same provider bound to a
scripted requester is a test. Serial, overlapped (insert settle), and
keyed (partition the exchange flow) are drawings, not modes.
*(two-ends core adopted 2026-07-23; the rest exploration; spellings
provisional)*

```
diagram shout
  serve handle => req, ~X        -- one firing per exchange
  req -> upcase => resp
  resp -~> collect ~X            -- the collect is the response
end

listen http(8080) with handle = myServer   -- deploying is binding;
                                           -- the `with` spelling is rejected
                                           -- (2026-08-04), replacement owed
```

**Recursion — the site.** Recursion whose tree exists only as call
structure (mergesort, a parser's descent) is drawn as a **site**: an
out-port (the problem leaves the page) and an in-port (the answer
arrives) joined by the abstract wire, with threads anchored at the
page's own wires — *feed the child where you are fed; read it where
you are read*. A frame is a hypothetical ("what would sorted be if
xs were subA?"), indexed by the tree of askings; a leaf is an alt
with no sites; no termination checking. Mutual recursion is inlining
— only a group's back edges are sites. *(adopted 2026-07-23, revised
2026-08-12; glyphs provisional)*

```
in xs @xs                       -- @xs starts at the page's question wire
xs -> split singleton? of Base, Divide => s
s.Divide -> splitInHalf => subA, subB

subA => qA @xs                  -- child A's question (the out-port)
qA ... aA @sorted               -- child A's answer (the in-port)
subB => qB @xs
qB ... aB @sorted

aA, aB -> mergeSorted => merged
~s.Base:   s.Base
~s.Divide: merged
-~> collect => sorted @sorted   -- @sorted starts at the answer wire
out sorted
```

## Trees, focused update, saturation

**Open tree — iterate a recursive structure.** The zipper-based
uncollect walks the structure and exposes each node with its full
context (value, parent, path, children) as innocent data reads; the
collect gathers results back into a tree. Hand-written recursive
walks are a settled rejection. *(exploration; spelling provisional)*

```
tree -> open tree => node, ~T
node.value -> render -~> collect => rendered
```

**Shallow focused update — a split with an identity branch.**
Change selected elements, keep the rest in place: never a filter
(filter forgets the unselected positions; the exhaustive close
remembers them). *(the rule settled within the round)*

```
xs -> open list -> split parity of Even, Odd
  Even: -> double        -- selected loci: transform
  Odd:                   -- the rest: identity, rides through
-~> collect
-~> collect => out       -- [1, 4, 3, 8] from [1, 2, 3, 4]
```

**Deep focused update — the path and its mirror.** Name a path once
and a transform once; every intervening rebuild is the derived mirror
of the path (open list ↔ exhaustive collect, `.field` ↔ spread,
split ↔ exhaustive case collect). A separate setter language is a
settled dead end. *(exploration; spelling provisional — `|=`, `->*`,
and `collect back` are all owed to the textual round)*

```
doc | .users[] .posts[] .likes  |=  add(1)   => doc'
```

**Saturation — a back-edge on a flow wire.** Closure under rules
(reachability, dataflow analysis): a set collect re-opened, the
flow-level counterpart of the register's delay, in the same
two-statement read/write discipline. Every cycle crosses a dedup
collect; the walk halts when a round adds nothing new. Naive vs
semi-naive are lowerings of one drawing, never a knob. *(exploration;
spelling provisional)*

```
edges -> open list -~> collect set => reach0    -- seed: Reach = Edge
saturate init reach0 => reach                   -- read half
reach -> open set => x, y
edges -> open list => y2, z
x, y2 -> eq => hit
(x, y), (y2, z) ~> cross -> keep(hit) -> pair(x, z)
-~> collect set -> feed of reach                -- write half: union back
```

**Lattice saturation — keyed collect under feedback.** Swap the set
collect for a keyed collect by a lawful operator and the same
back-edge computes shortest distances (per-key min), dataflow facts,
any bounded-height lattice fixpoint. *(exploration; spelling
provisional)*

```
src -> pair(0) -~> collect keyed by min => d0
saturate init d0 => dist
dist -> open keyed => n, dn
edges -> open list => a, b, w
n, a -> eq => hit
(n, dn), (a, b, w) ~> cross -> keep(hit)
-> pair(b, dn + w)
-~> collect keyed by min -> feed of dist
```

## Under-commitment, completion, and the page

**Under-committed programs are writable.** Sibling opens with no
declared order parse fine; the closes name their flows explicitly.
The program's meaning is its completion. *(implemented in part)*

```
listA -> open list => a, ~A
listB -> open list => b, ~B      -- sibling opens; no order authored
a, b -> add => s
s -~> collect ~A => inner
inner -~> collect ~B => out
```

**`+` lines — inferred structure, visibly derived.** The printer
renders completion's insertions (a Cross for sibling opens, an
incorporate for a value into a flow) prefixed `+`, the textual faint
rendering. `+` lines are derived and not stored; to override an
inference, author the line solid. *(adopted convention)*

```
+ ~A, ~B -> cross => ~A2, ~B2    -- inserted; orientation from collect order
```

**Indentation and spans are views, not syntax.** The parser reads no
indentation and no columns; the printer indents by derived flow
depth, and the span lint flags un-nested overlap of structural flows.
One source of truth — the wiring. *(adopted)*

**Diagram boundary.** A file holds one or more diagrams; boundary
ports are declared, outputs are explicit statements (no implicit
return — a program is a node set with distinguished outputs, not a
root expression). *(draft)*

```
diagram sumOf
  in xs
  xs -> open list => a, ~L
  ~L ~> delay init 0 => sum
  sum, a -> add -> step of sum => t
  out total = t
end
```

**Level-1 statements — operations on programs.** Distinguished by
their operand sort (names of nodes/steps, not wires), no level
marker: `expand` materializes a node's expansion; `!` is the lens
mode, referencing a principal port of the derived view. Ids print as
suffixes on request (`=> sum@n42`) for diff and patch. *(draft)*

```
sum -> expand => sumX      -- materialize sum's expansion, named
sum!acc -> double => w     -- lens reference into the derived view
```
