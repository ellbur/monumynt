# Learning from other languages: Effekt

*Comparison round, 2026-07-10. First execution of a new evidence
genre: read real programs written in another language, compare how
that language approaches each problem with how we approach the same
problem (where we have an approach at all), and turn the gaps into
open problems. **This round decides nothing** — like the surveys, it
reweights `open-problems.md` and hands demands to owning docs; design
stays in the design conversations.*

*Corpus: the Effekt language's own example suite
(github.com/effekt-lang/effekt, `examples/`) — all nine literate case
studies (lexer, parser, pretty printer, build system, automatic
differentiation, ANF transformation, naturalistic DSLs, scheduler;
the frontend doc combines four of them) plus the tour chapters on
effect handlers, computations, captures, regions, loops, and IO.*

## Reading rules for this genre

Three cautions govern how findings here may be used, stated up front
because each is a bias with a direction:

1. **What's out there is already out there.** The output of this
   round is *problems* — programs that must be writable, demands with
   field evidence — never mechanisms. Importing Effekt's mechanism
   would duplicate an existing language; the value is in noticing
   what their examples can do that our record cannot yet say how to
   draw.
2. **Different core; bolting on clashes.** Effekt's core move
   (below) contradicts two of our principles head-on, worked in
   finding 7. Where their approach is better, the question is what
   the *drawn, inside-out* form of the same capability is — not how
   to graft theirs.
3. **Maturity polish.** These examples are the language authors' own
   showcase: curated, literate, chosen to flatter the mechanism.
   Direction of the bias: overcounts Effekt's ease and overcounts
   the themes handlers are good at (parsing, search, DSLs) relative
   to random code. So "their version reads better" is actionable
   only when the advantage is structural; and unlike the loop
   surveys this corpus is *not* a random sample — it is closer in
   kind to `tough-use-cases-design.md`'s deliberately constructed
   programs, and its frequencies mean nothing.

## Effekt's core move, in one paragraph

Everything in the case studies is one move applied repeatedly: *name
an operation without giving it meaning, write direct-style code
against it, and supply the meaning later from the enclosing context.*
An `interface Lexer { def next(): Token }` declares operations; a
consumer says `do next()` with no idea who answers; a handler
enclosing the consumer intercepts the operation — and because the
handler receives the *continuation* (`resume`) as a value, it can
answer (resume once), abort (never resume), or fork the world (resume
twice). The one move therefore covers what for us are several
distinct territories: late binding of meaning (resume once),
failure (resume never), and search/scheduling/nondeterminism (resume
many). The type system tracks unhandled operations
(`Double / { Exception }`), and a second mechanism — capture sets,
second-class blocks, regions — polices what may escape where.

## The examples, against our record

### 1. The lexer — and the test double

**Their approach.** `Lexer` is an interface (`peek`/`next`);
consumers are written against it. Two handlers: one *actually lexes*
a string (regexes, mutable position); one feeds tokens **from a
given list** — a test double, used to run the consumer before the
real lexer exists. A third handler, `skipWhitespace`, is a
transformer: it intercepts `peek`/`next`, skips space tokens, and
re-raises — the pipeline is assembled by nesting handlers.

**Our approach.** The token stream itself is comfortable: a stream
flow; `skipWhitespace` is a filter on it (join with a case flow on
the token kind) — for the transformer we are, if anything, cleaner,
since their version needs a recursive helper and a re-raising
handler where ours is the one filter drawing the language already
has. The gap is elsewhere: **nothing in our record says how a
diagram is run against a substitute environment.** The from-list
lexer exists so that `example1` — a consumer that does IO-shaped
requests — can be *tested*. Our diagrams name concrete operations
(an `App` names its JS function); there is no worked story for
swapping providers per run. This is the everyday face of finding 1.

### 2. The parser — ordered choice, failure, and rollback

**Their approach.** Combinators over `Lexer` plus a `Nondet` effect
(`alt(): Bool`, `fail(msg): Nothing`). Grammar code is direct style —
`or { parseLet() } { parseApp() }` — and the *meaning of `alt` is
deliberately left open*: depth-first backtracking, breadth-first,
first-result or all-results are all choices of handler, made once at
the edge. The depth-first handler resumes with `true`, and if that
world returns a failure, resumes *again* with `false`. Rollback of
the lexer position is not written anywhere: it falls out of handler
*ordering* — the lexer's mutable state lives under the parser's
handler, so capturing the continuation captures the state. The doc
itself has to warn: "it is important that the lexer is executed
_under_ the parser handler and not the other way around."

**Our approach.** We have pieces but no construct: the race barrier
(`race-barrier-design.md`) is *concurrent* alternatives with
drawn-order ties; failability gives us `fail`; the decision-driven
family (`tough-use-cases-design.md` item 4) has only a chooser
sketch; and the survey record already sighted the shape in the wild
— breadth item 6, the backtracking parser: "save/restore cursor;
wants the save/restore *pairing* visible. Owner: registers express
it; nothing yet makes it legible." Nothing owns **ordered
alternatives over the same consumed input, where the world is
restored between attempts.**

**The comparison's sharpest observation.** Effekt's rollback
semantics are decided by where a `var` sits relative to a handler —
the regions tour shows two programs differing *only* in the
allocation position of `x`, printing different results. That is
maximal implicitness: the most delicate property of a backtracking
program is readable nowhere in the program text. It fails our
discoverability bar and it fails "the drawn structure is
trustworthy." But the *capability* is real and the demand is field-
confirmed (breadth 6). Our angle, recorded here as a leaning for the
future round: in a dataflow formulation the consumed input is a
value — a stream position threaded explicitly — so *there is nothing
to roll back*; an abandoned alternative simply never contributed its
position downstream. Speculation may be a place where our core is
structurally better suited than theirs, **if** a round works out the
choice construct (plausibly the chooser family: race's sequential
sibling, ordered instead of temporal, failure-driven instead of
completion-driven). Until that round exists this is a gap, not an
advantage.

### 3. The pretty printer — search with constraint failure

**Their approach.** Same `Nondet` shape one level up: `group` marks a
choice point (horizontal vs vertical), the emit handler *fails* when
the line overflows the width, and the search handler retries the
enclosing choices vertically. A constraint solver in four small
handlers.

**Our approach.** Same verdict as the parser: this is the second
independent appearance of *ordered choice + failure + rollback*, and
it shows the construct is not parser-specific — it is search. (The
mutable output buffer being reset between attempts is, again,
handler-order magic; in our formulation the emitted document would
be a value per attempt and the reset is free.) Feeds the same open
problem.

### 4. The build system — demand-driven, keyed, memoized

**Their approach.** One effect `need(key): Val`; build rules are a
function from key to value that itself `need`s other keys; a build
*system* is a handler that answers `need` by recursively building;
`memo` is a second, composable handler that caches by key. Swapping
schedulers/strategies = swapping handlers ("Build Systems à la
Carte" reproduced in ~40 lines).

**Our approach.** Two rows own pieces of this. The request/response
shape is exactly the **served flow** (`tough-use-cases-design.md`
item 2): `need` is a request wire out, a response wire back. The
memoization is what `incremental-flow-design.md` does per-generation
— but over a *static* node graph; a build system's dependency graph
is **discovered at runtime and keyed by runtime values** (which key
needs which is data-dependent), and its cache is keyed state, not
per-node memo. Neither the served flow's own round nor the
incremental-collections layer has been worked; this example hands
them two concrete demands when they run: a *recursive provider* (a
server defined partly in terms of requests back to itself) and a
*keyed cache in front of a served flow*. Not a new row — sharpens
two existing ones.

### 5. Automatic differentiation — one program, three meanings

**Their approach.** Arithmetic itself is an interface
(`AD[Num]`: num/add/mul/exp); the differentiable program is written
once against it. Then: a *forwards* handler interprets `Num` as
(value, derivative) pairs; a *backwards* handler uses the
continuation — run the rest of the program first, then push
derivatives backward through the record (reverse-mode AD with no
tape, the continuation is the tape); a *symbolic* handler interprets
`Num` as strings and prints the expression. Handlers self-compose
into towers (`forwardsHigher` over `forwardsHigher` for higher
derivatives).

**Our approach.** Nothing. And this is the theme the whole corpus
keeps repeating: the lexer ran against a dummy or a real input
(example 1); the parser's `alt` had its meaning chosen at the edge
(example 2); the build rules ran naive or memoized (example 4); here
one arithmetic program runs numeric-forward, numeric-backward, or
symbolic. Four of the nine case studies *are* this capability. In
our record the nearest ground is `functions-design.md` (a function
is a sub-diagram with ports — but the operations *inside* it are
concrete), configuration scopes (the dual: the operation is fixed
and the configuration is wired in), and facets (explicitly deferred
in `tough-use-cases-design.md`). No doc says how a diagram is
written against operations whose meaning arrives later. Finding 1
states the problem in our vocabulary.

### 6. ANF and the naturalistic DSLs — non-local insertion

**Their approach.** A `Bind` effect turns a statement into an
expression by *inserting a let-binding at a marked outer position*
(`bindHere` = the insertion point); the quantification example moves
a `ForAll` binder from deep inside a sentence up to its `scoped`
handler. Continuations used for non-local rewriting of a tree under
construction.

**Our approach.** This is program-transformation territory —
level-1 operations in `transformation-levels-design.md`, and
rule-based insertion is how completion already works
(`time-travel-programs-design.md`). The demand ("build a tree while
non-locally accumulating context") did not survey as an application-
code shape and both Effekt examples are compiler/linguistics
internals. **No finding** — recorded so the theme isn't re-derived
later. If it ever presses, it arrives as a level-1 catalog question,
not a language construct.

### 7. The scheduler — continuations as data

**Their approach.** `Proc` (yield/fork/exit); the handler pushes
`box { resume(()) }` thunks onto a dequeue and drains it — a
cooperative scheduler in twenty lines, with the capture system
(regions, second-class queue) doing the safety proof that no
continuation outlives the scheduler.

**Our approach.** The concurrency row owns this ground (concurrent
collect, race, the event-loop breadth item); we don't aspire to
user-written schedulers — in a language where concurrency is wiring,
the scheduler is the runtime's job, not a program (same reasoning as
the deferred compile-time placement pass: an optimisation/runtime
concern, not vocabulary). The twenty-line scheduler is the *most*
mechanism-flattering example in the corpus (caution 3 applies with
full force). **No finding**, beyond noting their safety machinery
maps to our checking row (finding 6d).

### 8. The tour — generators, IO, loops

- **Generators.** `fib()` yields forever;
  `with collect(limit); with filter {...}; fib()` assembles a
  pipeline. For us: the pipeline is a stream flow with a filter and
  a take — comfortable — but the *producer* is a self-driven source
  with loop-carried state, which is precisely the missing source
  opener (`translation-exercise.md` finding 3, already on the
  concurrency row). The canonical beginner generator is blocked on
  exactly that item — confirmation with an outside witness.
- **Direct-style IO, promises.** Effekt is sequential by default:
  effects run in program order, and *concurrency* is the explicit
  construct (`promise(box {...})`, four cells for the concurrent
  swap). We are the mirror image: the DAG gives concurrency for
  free, and *sequencing* is the explicit thing (the IO thread). Their
  `swap` is two reads then two writes with zero annotations; ours
  today is unwritable (per-firing effects, Tier-1 row). Their
  `concurrentSwap` is four promise/box cells; ours is just the
  natural drawing. Neither default dominates — but every one of
  their nine case studies freely `println`s mid-computation, which
  is an outside witness to what the Tier-1 row already knows: the
  effects half is the record's most load-bearing hole.
- **`while ... else`, `loop { {l} => ... l.break() }`.** A loop with
  an on-normal-exit branch, and break/continue as operations on a
  drawn label. Both confirm designs we already have: the else-branch
  is terminator discharge distinguishing end reasons
  (`end-when-design.md`, the (prefix, terminator) readout), and the
  label is a drawn wire to the loop — closer to our "arrive by a
  visible wire" than to their own `do`-reaches-invisible-handler
  default. Confirmation, no finding.

## Findings

**Finding 1 — late-bound operations (one program, many meanings).
The corpus's center of mass, and a real gap.** Four of nine case
studies are the same capability: write a diagram against named
operations whose meaning is supplied per use — real lexer vs test
list, forwards vs backwards vs symbolic arithmetic, naive vs
memoized build. Our record has the function boundary (ports, flow
skeleton) but its interior operations are concrete; configuration
scopes wire a computation *into* a fixed operation, not a meaning
*onto* an open one. Stated inside-out, the capability needs no
dynamic scope: **an unbound operation is a request/response port
pair on the diagram's boundary, and binding a meaning is wiring a
provider onto it** — which is the served flow's shape, connecting
this to `tough-use-cases-design.md` item 2 and to
`functions-design.md`'s interface story. What handlers get from the
continuation (abort/multi-resume) is *not* part of this finding —
that's findings 2–3's territory and failability's. Owner: the
functions/reuse/facets row, which this round argues is
under-weighted (W 3 → 4): testing alone (finding 2) makes it
everyday, not exotic.

**Finding 2 — the test double is the everyday face of finding 1.**
"How do you run a diagram that does IO against fake IO?" has no
answer anywhere in our record — the word "test" barely appears
outside compile notes. Effekt's answer (the from-list lexer) took
six lines. A language for beginners cannot lack this; it should be
*more* natural for us (rewire the provider) than for text languages,
which is exactly why its absence from the record is a gap and not a
deferral.

**Finding 3 — speculation: ordered alternatives with rollback. New
open problem.** Two independent case studies (parser, pretty
printer) are built on try-in-order / fail / restore-the-world /
try-next. Field demand already recorded (breadth item 6). Our
pieces: race with drawn-order ties (temporal, not ordered-choice),
failability (gives fail), the chooser family (owns
ordered/decision-driven selection), registers (express save/restore
but illegibly). Nothing owns the construct. The leaning to test in
its round: alternatives as failable contenders of a *sequential,
ordered* race-sibling, with consumed input threaded as positional
values so restoration is structural rather than semantic — contrast
Effekt, where rollback correctness hinges on invisible allocation
position (their weakest discoverability moment; see example 2).
Also arrives with a +1 ladder to check: first-success → all-results
→ bounded search → heuristic order.

**Finding 4 — demand-driven keyed computation.** The build system =
served flow + recursive provider + keyed cache. Two demands handed
to existing rows (served flow's round, on the concurrency row;
incremental collections layer): the provider that requests from
itself, and the keyed cache as a first-class block in front of a
served flow. No new row.

**Finding 5 — sequential-by-default vs concurrent-by-default.**
Effekt makes effect sequencing free and concurrency explicit; we
make concurrency free and sequencing explicit. Their examples
casually interleave effects everywhere — an outside witness that
the Tier-1 IO/effects row gates *ordinary* programs, not just
effect-heavy ones. No score change (the row is already I 4 / W 5);
recorded as external confirmation. Where we are structurally
stronger: their concurrent version of `swap` needs four
promise/box cells for what is, for us, just the drawing.

**Finding 6 — confirmations, briefly.** (a) Generator pipelines
confirm the source-opener item as the blocker for the canonical
beginner producer. (b) `while/else` and labeled break confirm the
terminator-discharge readout and end-when. (c) Their effect
*transformers* (skipWhitespace) are our plain stream filters — we
read better there. (d) Their capture/region machinery (second-class
blocks, `at {exc}` types, allocation regions) is the type-system
analog of our provenance paths and closed-scope guard; their tour
itself calls the two-system split "very confusing," supporting the
checking row's drawable-witnesses stance over imported capture
types.

**Finding 7 — what not to import, and why (the clash record).**
(a) *Dynamic scope is an invisible wire.* `do next()` reaching an
unseen enclosing handler is the magic-name shape the inside-out
principle exists to reject — meaning arrives by position, not by a
drawn connection. The drawn form (finding 1) keeps the capability
and discards the mechanism. (b) *Rollback by allocation position*
makes the program's most delicate property (what state backtracks)
unreadable in the text — the exact opposite of "the drawn structure
is trustworthy." (c) *The continuation as a user value* is the
mechanism behind their entire catalog; for us control is structure,
not a value — race, failability, end-when, and (if worked)
speculation each carry the specific capability with the control
kept drawn. These aren't criticisms of Effekt — they're the reasons
graft fails and each capability needs its own inside-out form.

## What this round changes in `open-problems.md`

- **New Tier-2 row**: speculation — ordered alternatives with
  rollback (finding 3). I 4 (a demand, pieces named, leaning
  sketched, nothing worked), W 3 (breadth obligation: parsing and
  search are rare-but-breaking; two corpus sightings + breadth
  item 6).
- **Functions, reuse, and facets**: W 3 → 4 (findings 1–2: the
  test double makes the row everyday; four of nine case studies
  rest on the capability). The row's remaining list gains
  late-bound operations and the test-double question.
- **Concurrency row**: served flow's round gains the recursive
  provider and keyed-cache demands (finding 4).
- **IO/effects (Tier 1)** and **end-when (Tier 3)**: dated
  confirmation notes only, no score movement (findings 5, 6b).

## Next rounds of this genre

Worth repeating with languages whose *core* differs from ours along
other axes: a dataflow/reactive language (closest relatives —
where differentiation matters most, per caution 1), an
array/APL-family language (where our uncollect/collect story would
be stress-read from the other side), and a beginner-first language
(Scratch/HyperCard lineage — where the discoverability bar is the
whole language). Same reading rules; curated-corpus bias stated
each time.
