# Late-bound operations: one program, many meanings

Status: **adopted** (design conversation, 2026-07-23), **revised
(design conversation, 2026-08-04): the op construct is dissolved
into an ordinary port pair** — a caller-supplied operation is an
out port and an in port on the sub-diagram, `with`-binding is
rejected, and the exchange correspondence is derived under
copy-paste rather than stated; the one place pairness is stated is
the flow-use marking. See "Revision notes (2026-08-04)" below,
which governs where the body differs. From the 2026-07-23
adoption (the joint
adoption with the function-boundary round): the op pair as the
client end of a served flow, binding as wiring a provider on at a
boundary, orderedness-equals-provider-state, the test double as an
ordinary program, and the policy layer as middleware-as-splice.
The op pair's identification with the spec's slot machinery
carries the function-boundary round's provisional-confidence
marker (adopted as the working position, not yet fully engaged by
the adopting conversation). Spellings and the other open questions
stay open where marked; none of it is implemented. (One more
spelling note: the register samples below use the pre-thread
`~N ~> delay` / `step of` form — the thread ergonomics round,
`iteration-with-state-design.md` 2026-08-04, has since retired the
register's flow operand; read it as the thread's derived frame.) It is the round the functions/reuse/facets row
of `open-problems.md` has owed since the Effekt comparison: the
capability four independent languages put at their center of mass —
write a program against named operations whose meaning is supplied
per use — worked inside-out, with the **test double** as its everyday
face and the **policy layer** as its stacked form. Per the facets
notes' own advice (`facets-design-notes.md`, open edge 2), this round
works *one* manifestation — the algebra facet with the test double —
and does not attempt a general theory of facets.

The round's central move is a unification, not an invention. The
record already owns all three pieces:

- the **exchange shape** — a value in, a value owed back, per firing —
  is the served flow (`tough-use-cases-design.md`, item 2);
- the **propagation shape** — an unmet need travelling outward to a
  boundary — is the placeholder story's residual demand
  (`types-design.md`; `time-travel-programs-design.md`, "Reuse");
- the **grouping identity** — several operations that belong together,
  matched by a drawn reference rather than structural search — is the
  facet (`facets-design-notes.md`).

A late-bound operation is what you get when the three are snapped
together. Code samples use the textual syntax of
`textual-representation-design.md`; every construct-specific spelling
below is provisional and is owed to the textual catch-up round.

## Running a program against pretend files

Suppose you have a diagram that counts the words in a file:

```
readFile   = js "p => require('fs').readFileSync(p, 'utf8')"
splitWords = js "s => s.split(/\\s+/).filter(w => w.length > 0)"

path -> readFile -> splitWords -> length => n
```

It works. Now you want to *test* it — run it against a pretend file
so the test doesn't depend on the disk, the working directory, or a
fixture file that someone will eventually delete. Every language
that takes testing seriously has an answer to this; ours, until this
round, had none (`effekt-comparison.md`, finding 2: "the word 'test'
barely appears outside compile notes"). The diagram names `readFile`
concretely — an `App` names its JS function — so its meaning is
fixed at authoring time, and there is nothing to swap.

What the program wants to say is: *I use an operation called `read`;
I am not the one who says what reading is.*

## The first example: leave the operation open

Here is the same diagram with the operation left open:

```
diagram wordCount                  -- diagram wrapper as in functions-design
  in path
  op read                          -- an operation used here, defined elsewhere
  path -> read => text
  text -> splitWords -> length => n
  out result = n
end
```

The new line is `op read`. It puts an **operation pair** on the
diagram's boundary: a *request* port going out and a *response* port
coming back. The pair is a boundary port like any other — `in` marks
where a caller's value comes in, `out` where one goes back, and `op`
marks where a *question* goes out and its *answer* comes back. One
use, one exchange: the request carries `path`, the response is what
comes back as `text`.

The use site `path -> read` is an ordinary chain stage. `read` is
not a magic name reaching into an invisible environment; it is a
reference to the boundary pair declared two lines up, the same way
`cs.Just` references a port of a split. Everything readable at the
use site arrived by a visible wire — the wire runs from the use site
to the boundary, and stops there. What is on the *other* side of the
boundary is, deliberately, not this diagram's business.

## Where does the meaning come from?

Now, you might wonder why the language doesn't resolve `read` the
way effect handlers do — walk outward at run time through enclosing
scopes until some enclosing context is found that handles `read`,
the way Effekt's `do next()` reaches its nearest enclosing handler.
It turns out this is exactly the shape the inside-out principle
exists to reject: the meaning would arrive by *position*, not by a
drawn connection — an invisible wire, and one whose other end moves
when the program is rearranged. The Effekt comparison recorded this
as the first entry of its clash record (finding 7a), and this round
keeps it rejected. The capability survives; the mechanism does not.

And you might wonder why the caller doesn't simply pass the reading
function as an argument — `wordCount(path, readFn)`, the way Zig
passes an `Allocator`. Passing a *value* that is a function is the
settled rejection of `configuration-scopes.md` (a function waiting
to be called has no honest visual form; there is nothing on the
wire). But notice what Zig's mechanism actually is, stripped of the
word "function": the capability arrives at the boundary, explicitly,
per call — no dynamic scope, no registry. That part is right, and it
is the flattest of the four field mechanisms the record has studied
(`zig-comparison.md`, §8). The correction is only in *what* arrives:
not a value carrying latent code, but a **wiring** — the caller
connects the pair to something.

## Binding is wiring a provider

A **provider** is anything with the answering side of the shape: a
place a request can go and an answer come back. Binding an operation
is wiring the diagram's pair to a provider at the call boundary:

```
-- spelling provisional throughout
"notes.txt" -> wordCount with read = readFile  => n     -- production
"notes.txt" -> wordCount with read = fakeRead  => n2    -- test
```

For a simple pure operation, a provider is just an ordinary diagram
or extern of the right shape — `readFile` is the extern we started
with, and the test double is one line:

```
fakeRead = js "p => 'five little words right here'"
```

That is the whole answer to the motivating question. Running a
diagram against fake IO is *rewiring one connection at one visible
place*, which is the answer the Effekt round predicted a visual
language should be able to give more naturally than a textual one:
you can point at the difference between the production run and the
test run.

Two readings of the same structure, to fix the ontology:

- From the diagram's side, `op read` is a **demand**: the diagram is
  honest that it is incomplete without a meaning for `read`. This is
  not a new species — it is the placeholder story's residual demand
  (`types-design.md`), carried on the boundary like any other.
- From the provider's side, answering is an **offer**. A provider is
  a diagram whose boundary offers the operation; binding matches an
  offer to a demand — by drawn reference, never by structural search
  (more below, when operations come in groups).

## From concrete to open: extraction, and defaults

You do not have to plan for openness. The example-first path is the
one the round above actually walked: write the concrete program with
`readFile` named directly, and when the need to swap appears,
**extract** — replace the concrete stage with an operation pair and
push `readFile` out through the boundary, where it becomes the
pair's **default binding**. The program computes exactly what it
did; the only change is that one connection now crosses a boundary
where it can be seen and re-wired. Declaring `op read` up front
remains available as planning (the principle constrains obligation,
not option), but nothing forces the general form first.

Defaults matter because the everyday case must stay effortless.
Flix's providers ship as effects *with default handlers*; Zig's
cost — every intermediate function threads the parameter by hand —
is the noise this language does not need to pay (the next-but-one
section says why). A pair with a default binding behaves exactly
like the concrete program until someone overrides it; the test
double is an override at one call site.

## A use inside a loop: the pair carries exchanges

So far `read` fired once. Put the use under a walk:

```
diagram wordCountAll
  in paths
  op read
  paths -> open list => p, ~L
  p -> read -> splitWords -> length
  -~> collect => counts
  out result = counts
end
```

Now `read` is asked once per element. The operation pair does not
carry one value; it carries **one exchange per dynamic use** — a
request fires out, an answer is owed back, pairwise. This is a shape
the record already has a name for. The served flow
(`tough-use-cases-design.md`, item 2) is "a flow opened from an
external source where each firing is an *exchange* — a value in
(the request) and a value owed back (the response) — and the collect
that closes the handling body supplies the owed value, per firing,
delivered to the requester."

That is this, seen from the other side of the wire. **A late-bound
operation is the client end of a served flow; a provider is its
server end.** The identification is the round's load-bearing result:

- The consumer's exactly-once expectation (every request gets one
  answer) is the served flow's existing law — the collect fires once
  per firing; an unclosed flow is an incomplete program. The
  structure is the guarantee; no linearity side condition appears.
- The concurrency row's worked machinery transfers instead of being
  re-invented: whether a provider handles exchanges serially or
  overlapped is the *collect species on the provider's side*
  (`concurrent-collect-design.md`), invisible to and undemandable by
  the consumer — exactly as a server's internal concurrency is not
  the client's business.
- The Effekt comparison's build-system demands (finding 4: the
  recursive provider, the keyed cache in front of a provider) land
  where they were already filed — on the served flow's own round —
  and this round inherits their answers when that round runs.

## Two ways to be a provider

A pure extern like `readFile` can be bound directly, and the natural
reading is **splicing**: each use behaves as if the provider's
little diagram were instantiated at the use site, once per exchange.
Nothing observable distinguishes one shared `readFile` from a fresh
one per call, because there is no state to share.

The interesting providers are the ones where that *would* be
observable — the provider holds something across exchanges. The
from-list lexer double, the reason Effekt's corpus built a test
double at all, is exactly this: it feeds scripted tokens one at a
time, so it must remember how far through the script it is. Such a
provider is **serving**: one instance, opened over the flow of
exchanges, its state a register on that flow. And with the
identification above, it is drawable today, with existing
vocabulary — a served flow plus a register:

```
facet Lexer = algebra { next }          -- spelling as in facets-design-notes

diagram fromList                        -- a serving provider for Lexer
  in tokens                             -- the scripted token list
  serve next => (), ~N                  -- exchange per call; request is unit
  ~N ~> delay init tokens => remaining  -- register: script not yet emitted
  remaining -> headOrEof => tok         -- this exchange's answer
  remaining -> rest -> step of remaining
  tok -~> collect ~N                    -- the collect *is* the response
end
```

`serve` mirrors `open served`; the register's read/write halves are
the standard two-phase spelling. The double is six lines here too —
but every line is ordinary: a flow, a register, a collect. The test
double is not a feature; it is a small program in the language.

Which form a provider takes is not a free choice, and the thing that
decides it is the next section's subject.

## More than one operation: the algebra and its facet

A real capability is rarely one operation. Files come as
open/read/close; a lexer as peek/next. The group is an **algebra**
(`facets-design-notes.md`), and the group's members travel together:
a provider answers all of them or it isn't a provider of the
capability.

How does a group of operations cross the boundary? One pair per
operation:

```
facet FileOps = algebra { open, read, close }

diagram backup
  in dir
  op FileOps                    -- three pairs arrive together, named by the facet
  ... open ... read ... close ...
end
```

Now, you might wonder why the group isn't *one* pair whose request
is a tagged value — `Read(path) | Write(path, text)` — dispatched by
the provider, the way an actor's mailbox or a message protocol would
do it. It turns out this is precisely the **sum bottleneck** the
fifth principle forbids: a tagged union packed on one side of a
structural point and unpacked on the other, severing the visible
thread between each operation's use sites and its handling. The
operations pass through the boundary *as themselves* — the boundary
is a barrier with per-operation lanes, not a funnel. The reward is
concrete: demanding less is *dropping pairs*. A consumer that only
ever reads demands only the `read` pair — the narrowest-capability
discipline Flix builds an effect hierarchy for (`FileExists` running
into `FileTest`) falls out of the lanes with no new construct.

What holds the lanes together is the **facet**. `FileOps` is
authored once; the consumer's demand references it, and every
provider's offer references it. Binding matches offer to demand *by
that drawn identity* — the checker verifies that both ends point at
the same facet, which is checkable by looking. It never matches by
structural coincidence ("this thing happens to have a `read` and a
`close`"): that would be search, and `types-design.md` forbids
search. This is the facets note's ladder cashed out: the facet is
not a pair of function slots (an interface); it is the named,
referenceable concept of *having these operations*, attachable to
the production provider and the test double alike. And that shared
attachment is the round's answer to why a double is *informative*:
exercising `fromList` tells you about the consumer's behaviour
against the real lexer because both bindings are the same facet —
a fact you can point at, not a convention you hope holds.

## Ordering: which exchanges have an order?

Two operations expose the question the single-operation examples
hid. A consumer calls `peek`, then `next`, then `peek` again — and
the from-list provider's register steps on *both* kinds of exchange,
so the provider's behaviour depends on the interleaving. Who says
what the interleaving is?

The record has already legislated the only honest answer. Within a
firing there is no time; the one intra-firing order is order along a
handle's segment, and **a handle is an ordering commitment**
(`within-firing-effects-design.md`). So:

- An algebra whose exchanges are mutually ordered is a **sequenced
  algebra**: its facet carries a handle, the consumer threads that
  handle through its uses (`peek` then `next` are strung on the
  segment, exactly like any two effect ops), and the provider
  receives exchanges in segment order — across all the algebra's
  lanes, because the handle is one commitment spanning the group.
  The lexer is sequenced; so are FileOps.
- An algebra with no handle is an **unordered algebra**: exchanges
  across uses have no defined order, and consequently a provider of
  it must be **exchange-stateless** — a register on a serving flow
  of an unordered algebra is ill-formed, the same species of
  structural check as a register under a concurrent collect
  (`tough-use-cases-design.md`, break #2, option (a)). Arithmetic
  for automatic differentiation is unordered; `readFile` alone can
  be either, and the choice is the facet author's commitment.

This is the round's second load-bearing result: **statefulness of
the provider and orderedness of the facet are the same bit.** A
provider may hold cross-exchange state exactly when the facet's
handle gives those exchanges an order to observe; a pure algebra's
providers can always be spliced, and the serving/spliced distinction
of the previous section is derived from the facet, not chosen per
binding. Note what the handle does *not* say: it is an ordering
commitment, not an IO commitment. The from-list double threads the
Lexer handle and does no IO at all — its register is ordinary
diagram state. Whether a provider touches the world is the
provider's business; the facet only fixes what consumers may rely
on.

## Calls within calls: the demand travels

`wordCount` uses `read`. Now some larger diagram uses `wordCount`.
Where does the larger diagram stand?

If it binds `read` — perhaps to the disk, perhaps to a cache — the
matter ends there. If it does not, the demand does what unmet
demands already do in this record: it travels outward.
`time-travel-programs-design.md` ("Reuse") states it exactly: "a
diagram authored against schematic sources accumulates residual
*demands* … projected onto its boundary the same way." The caller's
own boundary grows the pair; *its* caller binds or re-exports in
turn; the program is complete when no operation pair reaches the
root unbound (or every pair that does carries a default).

This is where the language earns something Zig cannot have. Zig's
mechanism is flat and honest, but every intermediate function pays
for it in text — the `Allocator` parameter threaded by hand through
ten layers that never allocate. Here the threading is *real* — a
drawn wire from the inner boundary to the outer one, no dynamic
scope anywhere — but it is **canonical bookkeeping**, and the
completion machinery already built for flow structure applies
verbatim: the re-export of an unbound pair through an intermediate
boundary is derived by published rule, shown faint, excludable by
ordinary authoring (bind it, and the faint wire is gone). The
authored program says `wordCount` with nothing about files; the
completed program shows, faintly, the file demand riding up to
whoever settles it. Every reading rule of
`time-travel-programs-design.md` — published, never searched, on
screen, excludable — carries over unchanged.

## The policy layer: middleware is a splice

Because binding is wiring, *interposition* is splicing. A
**middleware** is a diagram that is provider-shaped on one side and
consumer-shaped on the other — it offers the facet upward and
demands the same facet downward — and it is installed by splicing it
into the binding wire:

```
-- spelling provisional
logged = interpose logging on readFile        -- logging: a FileOps middleware
"notes.txt" -> wordCount with read = logged => n
```

Requests flow through the middleware on the way to the provider,
responses on the way back; the middleware sees both and may count,
log, transform, retry, or refuse. Flix's stdlib list — retry,
circuit breaker, rate limiting, dry-run, read-only, chroot, atomic
write, audit logging — is this shape eleven times over
(`flix-comparison.md`, §2), and its known hazard dissolves on
arrival: in handler-land, *stack order* is semantically loaded and
textually invisible (`withCircuitBreaker` outside `withBaseUrl`
differs from inside). Here the stack is drawn nesting — which policy
wraps which is where the splice sits, and there is nothing else it
could be. Interposition by drawing is the one place this round can
claim the language is structurally *better* than the field, not just
even with it.

Two notes with owners:

- **Fault injection is a configured double.** Zig's
  `FailingAllocator` — "fails after N allocations, useful for making
  sure out-of-memory is handled" — is a serving provider with a
  value port (`n`) and a register counting exchanges; at the
  threshold its response lane carries the failure. Failure travels
  as failability's terminator payloads, which means the *response
  lane of an operation pair is failable* like any other wire — the
  payload-type composition residue on failability's row applies here
  and is not re-answered. (*Now worked* —
  `failure-payloads-design.md`: the response lane is a failable
  catalog row, its lanes entering the client's inventory like any
  source's.)
- **Retry is blocked on pacing.** The one middleware everyone wants
  first sleeps between attempts; sleeping is pacing, the concurrency
  row's named hole, and this round inherits the block rather than
  designing around it (`flix-comparison.md` recorded the same
  dependency).

## Choosing a provider at runtime

Binding is drawn structure — so what about "pick the storage backend
from the config file"? That is not a new capability: wire *both*
providers, and route. A case split on the configuration value sends
each request down the lane of the chosen provider and merges the
answers back — cases as values, selection as ordinary data flow. The
thing that does not exist is a provider *arriving on a wire at run
time*, and that absence is the first-class-function rejection
holding, not a gap: every provider that can be chosen is on the
drawing, and the choosing is visible routing among them.

## What this round does not claim

- **Reverse-mode AD.** Effekt's corpus runs one arithmetic program
  under forwards, symbolic, *and backwards* interpretation; the
  backwards handler is the continuation used as a tape. The
  forwards and symbolic bindings are ordinary providers here — one
  unordered algebra, three offers. The backwards one is not: it
  needs the rest of the computation as a value, which is exactly the
  continuation-as-user-value mechanism the clash record excludes.
  If this language ever wants reverse AD, it is a *program
  transformation* — transformation-levels territory, a derived view
  of the diagram — not a provider. Stated as honesty, not designed.
- **The served flow's own round.** This round leans on the served
  flow's law and species; it does not work the served flow's open
  list (the recursive provider, the keyed cache, question 7's
  what-is-a-program-for-a-server). Those stay on the concurrency
  row, now with a second client waiting on them. *That round now
  exists* (`served-flow-design.md`): it commits to the two-ends
  reading this round opened (one construct, the exchange pair;
  "which one is the server" is a property of a binding), works the
  recursive provider (the link in exchange costume), the keyed
  cache (a partition-plus-lane-register middleware), and the
  program-for-a-server question, and its adoption conversation is
  declared joint with this round's.
- **The rest of the functions row.** Extensible alternation, the
  decorated tree, and the `across`-style authoring gesture are
  untouched; the function boundary's spelling (the level boundary,
  jointly demanded by the divide flow) is used informally here and
  still owed its joint decision.
- **A general theory of facets.** One manifestation, per the facets
  notes' own methodology. What this round *does* pin: a facet can
  group operation pairs, carries the sequenced/unordered commitment,
  and is the identity that binding matches on. Attachment's
  representation (facets open edge 3) is still unworked.

## Against the philosophy

- **Example first, then generalise.** The concrete program with the
  extern comes first; extraction pulls the pair out afterward and
  the extern becomes the default binding. `op`-first authoring
  remains an option (planning), never an obligation.
- **Inside-out — no magic names.** The use site references a drawn
  boundary pair; the meaning arrives at that boundary by a visible
  wire from the binding site. Dynamic scope — the field's dominant
  mechanism — is rejected in the dead ends, again.
- **Foundations before features.** The round adds almost nothing:
  one boundary port species (`op`), one stage form (`serve`), one
  edit gesture (bind/splice). Exchanges, ordering, state,
  concurrency, failure, and propagation are all inherited from
  worked rounds, which is the point of the unification.
- **Programmer's abstraction level.** "Run it against fake files,"
  "log every read," "swap the backend" are the user's own sentences,
  and each is one gesture on the drawing.
- **No bottlenecks.** The tagged-request encoding is rejected as the
  sum bottleneck; an algebra crosses the boundary as per-operation
  lanes under one facet identity.
- **Abstraction is the source of truth.** The authored program keeps
  the open pair; a binding is structure added beside it, and the
  completed threading is a derived, faint, excludable view. No
  lowering replaces the abstraction.
- **Building blocks must build — the +1 ladder.** Concrete extern →
  extract to one open operation (the program is unchanged plus one
  boundary pair) → second operation (one more pair under the same
  facet) → provider grows state (the facet takes the handle; the
  provider takes a register) → add a middleware (a splice on an
  existing wire) → a stack of them (more splices, order = nesting) →
  provider chosen by data (a case split among wired providers).
  Every rung is an addition to the drawing; no rung rewrites the
  consumer.

## Dead ends

Recorded so they are not re-proposed:

1. **Dynamic scope / nearest-enclosing-handler resolution.** Meaning
   by position is an invisible wire whose far end moves under
   rearrangement; rejected on arrival by the inside-out principle
   and the Effekt clash record (finding 7a). The capability is kept;
   the mechanism is not.
2. **The provider as a value on a wire.** A function in costume:
   nothing honest is on the wire, only a promise to answer later.
   The settled first-class-function rejection
   (`configuration-scopes.md`) covers it; runtime choice among
   providers is routing, not transport.
3. **One pair with tagged requests.** The mailbox/protocol encoding
   of an algebra is the sum bottleneck: operations lose their lanes,
   narrow demands become subset constraints on a union instead of
   dropped pairs, and the provider grows an obligatory dispatch that
   the drawing already did.
4. **Binding by structural match.** "Anything with a `read` of the
   right shape will do" is search, and it manufactures coincidental
   compatibility the way duck typing does; binding matches on facet
   identity, which is checkable by looking at two references.
5. **The operation as a bare value hole.** A hole that receives "the
   function's result" once cannot say what happens under a walk
   (many firings), under ordering (which exchange first), or under
   failure (whose terminator). The pair-carrying-exchanges form is
   not a generalization of the value hole; it is the honest form of
   which the value hole was the once-fired special case.

## Revision notes (2026-08-04): ops dissolve into port pairs; the C-shape

A design conversation following the boundary round's node-set and
copy-paste revision (`function-boundary-design.md`, revision notes
2026-08-04) re-examined the op pair and dissolved it.

**Ops are not a species.** `op` is not visual; in ports and out
ports are. A caller-supplied operation is **an out port and an in
port** on the sub-diagram, nothing more. The `with read = readFile`
binding spelling is **rejected**: it corresponds to no obvious
visual representation, and it is a higher-order form — passing an
operation as if it were a value — which the language avoids as
confusing (the configuration-scopes rejection reasserted, not
weakened). Binding is the caller wiring code between the two
ports. This also resolves the boundary round's
provisional-confidence marker on the slot/op-pair identification:
the anticipated later look has happened, and the chain ends at
bare ports — slots → op pairs → port pairs.

**The exchange correspondence is derived, not stated.** Under
copy-paste semantics the caller's code is literally pasted between
the request port and the response port; the answer corresponds to
the question because the caller's wires connect them, inside
whatever frame the ports sit in — per firing when the hole sits in
a walk. Nothing declares the pairing; the wiring is the pairing.
**One exception — the only place pairness is a stated thing: using
a sub-diagram flow-wise requires recognizing the port pair as
special.** The flow-use marking says "these two ports form an
openable hole," distinguishing them from arbitrary ports; without
it there is nothing to open.

**Constraints on use are derivable; the abstract wire states the
expectation.** The example that shows a black box imposing real
constraints, not just documentation:

```
diagram readAll
  in paths -> list uncollect => path
  out path ... in content        -- the abstract wire; spelling provisional
  content -~> list collect => contentList
  out contentList
end
```

`path` lives in an internal flow the caller never receives, so the
caller can only route `path` (through any nodes) into `content`,
or feed `content` a constant (the prefix rule admits it) — and
nothing else; anything context-incompatible is witnessed. That
hard constraint is **derivable** by the boundary round's contract
projection (the internal collect's demand lands on the `content`
port). The authored `...` states the *expectation* — content
derives from path — strictly stronger than the constraint,
checkable against the derivation, and it earns its ink twice over:
layout (the hole's ports ordered vertically) and the `-~>`
shorthand across the hole (the flow context is known). This is the
first concrete instance of types-as-summaries: statable, verified,
never load-bearing for meaning. (Ports-as-documentation — what a
port *means*, labels vs shapes — is deliberately pinned as a
separate, unexplored question.)

**The C-shape.** A sub-diagram's black box need not be a box: an
out port upstream of an in port draws as a **cutout** — the
interior-out port above, the interior-in port below, the caller's
code wired into the hole. And a flow is a long, thin C: the code
between an uncollect and its collect is the code in a cutout, the
back of the C the flow wire. Run the identification forward and
**a custom flow is a C-shaped sub-diagram used flow-wise** —
`custom-flows.md` gains its missing definition form;
configuration scopes and cancellation's bracket are C-shapes
(open the operand, wire the computation, close); retry with an
internal attempt register is a nontrivial instance whose hole runs
per attempt. The call-site spelling problem the `with` rejection
created dissolves with it: *using* a C-diagram is consuming a
flow — open, wire the hole, close — vocabulary that already
exists. The back-of-C wire is the **stow**
(`barrier-value-crossing-design.md`, revision notes): the
diagram's carried wires tunneled together — which is also what a
commute or join of a custom flow would have to act on, well-defined
exactly when the stow is.

**Filed, not chased.** Shapes beyond the C: multiple cutouts, and
nested cutouts (cutting back in and then out again) — the latter
the shape of two-phase lifecycles, so
`within-firing-effects-design.md` is where a forcing example
should eventually come from. Pointing the same way from the other
side: inhomogeneous iteration already recognizes flow shapes more
complicated than one start-to-finish wire (segments, the
continuation), so richer flow routing has precedent in the record
rather than being exotic.

**What survives unchanged:** the rejection of effect-handler
position-resolution (meaning arrives by drawn connection, never by
enclosing scope); the demand/offer ontology (an unbound operation
is the placeholder story's residual demand, now carried by a bare
port pair); middleware-as-splice (a splice is exactly an insertion
into the hole); the facet as grouping identity. The served-flow
identification re-reads with the pair dissolved: the client end is
a port pair too — the two-ends core untouched, its client-end
vocabulary simplified.

## Open questions

1. **Spellings.** `op`, `serve`, `with … = …`, `interpose … on …`,
   and the facet reference in a demand are all provisional; owed to
   the textual catch-up jointly with the function boundary (the
   level boundary the divide flow also demands — one decision, three
   clients). *The boundary round now exists*
   (`function-boundary-design.md`, exploration): an `op` pair is a
   port of a cut like any other — a crossing — and "the demand
   projects onto the caller's boundary" is literal (the pair's wires
   keep crossing outward until bound); the spec's slot machinery is
   proposed dissolved into the pair. The spellings themselves stay
   owed to the joint catch-up.
2. **Where may a binding sit?** This round binds at call boundaries.
   Whether a *region* of one diagram can be rebound (run this
   sub-graph against the double, the rest against the disk) — and
   what that does to the facet's one-handle ordering commitment — is
   unworked.
3. **The serving provider's multi-lane form.** A sequenced algebra's
   provider receives one segment-ordered stream across k lanes. Is
   the drawn form k `serve` stages sharing one register scope, or
   one `serve` over the merged exchange flow with per-lane
   projections? The answer must respect the no-bottleneck rule from
   the *provider's* side too, and probably co-locates with the
   barrier-value-crossing co-location criterion. Leaning: k lanes,
   one shared serving context, register scope = the serving context;
   not worked. *Now worked in `served-flow-design.md`:* the serving
   end of a k-operation facet is a **pre-split bundle** — one
   serving context (a flow, one firing per exchange, in handle
   order) with k static lanes, exactly one firing per lane per
   exchange, registers on the parent flow with per-lane steps merged
   by the exhaustive case collect. No dispatch is drawn because no
   union was packed. A leaning, not adopted.
4. **Defaults and override scope.** A default binding rides the
   demand outward; can an outer caller override an inner default
   (the test overrides the production default two levels down)?
   Leaning yes — override is rebinding at any boundary the faint
   thread crosses — but the interaction with "picking early turns a
   caller's direction into a contradiction"
   (`time-travel-programs-design.md`, Reuse) needs the checking
   round.
5. **Checking.** The facet's signature — what each pair's request
   and response demand and offer, the sequenced bit, slots — is
   `types-design.md` open question 3, unchanged; the algebra facet
   as an authoring surface with value witnesses is the collect
   family's demand on question 4. This round adds one item: the
   exchange-stateless check for unordered facets (the register-free
   serving flow), which should be the same species as
   every-cycle-crosses-a-register.
6. **Cancellation mid-exchange.** A consumer stops demanding while
   an exchange is in flight (the race settled; the client vanished).
   The cancellation round's `Cancelled` terminator over the demand
   frontier should reach the provider's serving flow like any other
   stranded work; confirming the exchange's owed-answer obligation
   discharges correctly under it is Tier-1 work, inherited not
   answered.
7. **The evidence condition.** The row's W move (4 → 5, argued by
   three corpora) is still conditioned on the owed application-level
   sample: does real application code swap providers, and how often
   are middleware stacks assembled outside infrastructure code? Per
   the standing method, sample before the adoption conversation
   treats importance as measured.

## Prior art

Four independent witnesses, one per mechanism family, all read and
clash-recorded in their comparison docs:

- **Effekt** (`effekt-comparison.md`): handlers; four of nine case
  studies are this capability; contributed the from-list double, the
  build system's recursive-provider and keyed-cache demands, and the
  clash record (dynamic scope, continuation-as-value).
- **Flix** (`flix-comparison.md`): provider stacks and stdlib
  doubles — the strongest witness that the test double is furniture,
  not technique; contributed the policy layer and the
  narrowest-capability hierarchy that per-operation lanes absorb.
- **Zig** (`zig-comparison.md`): ordinary parameters — the flattest
  mechanism, supporting boundary wiring over any dynamic scope;
  contributed `FailingAllocator` (fault injection as configuration)
  and the threading noise that motivates completion-derived
  re-export.
- **Raku** (`raku-grammars-comparison.md`): action classes — the
  grammar parses, the actions supply meaning per run; the earliest
  sighting of one-program-many-meanings in the record.

What must not be imported is recorded above as dead ends 1–3; each
witness's capability survives in the drawn form.
