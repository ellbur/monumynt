# Learning from other languages: Zig

*Comparison round, 2026-07-10 — seventh execution of the
learning-from-other-languages genre (Effekt, Raku, Flix, XQuery/jq,
the APL family, the reactive ecosystem precede it). **This round
decides nothing** — like the surveys, it reweights
`open-problems.md` and hands demands and structure to owning docs;
design stays in the design conversations.*

*Corpus: the Zig language reference read at source
(`ziglang/zig`, `doc/langref.html.in` and the `doc/langref/*.zig`
example programs, master as of this round — ziglang.org itself was
unreachable from this environment, so the reference was read from
the repository), the standard library as field code
(`lib/std/zig/tokenizer.zig`, `lib/std/mem.zig` iterators and
`window`, `lib/std/Io.zig`, `lib/std/testing/FailingAllocator.zig`),
the Zen list, and the 0.14.0 release-notes material on labeled
switch via secondary reports (the notes themselves are behind the
unreachable site; the 13% tokenizer figure below is theirs).*

*The round was run under a stated brief: Zig is the survey corpora's
own territory — an imperative, C-lineage language whose designers
**deliberately redesigned C's control flow**. Every modification
they made is a field-tested claim about where raw imperative control
flow fails (a bug class, a legibility failure, a codegen failure).
So the round reads Zig as a designer's changelog against C, and for
each entry asks: does the record's construct already contain that
fix structurally, or is there a gap? Where prior rounds compared
against foreign cores (handlers, grammars, Datalog, arrays,
signals), this one stress-tests the record against the *home turf*
of the loops the surveys sampled.*

## Reading rules for this round

The genre's standing cautions (problems, never mechanisms; different
core; curated-corpus bias) apply as always. Three round-specific
ones:

1. **The corpus is documentation plus stdlib, not a random sample.**
   The langref examples are chosen to flatter each feature. But the
   stdlib reads differently from every prior round's corpus: it is
   *production code* (the tokenizer that compiles Zig itself), the
   closest thing to a field sighting this genre has produced.
   Frequencies still mean nothing; existence-in-shipping-code means
   more than usual.
2. **Familiarity cuts the other way here.** The XQuery/jq round's
   close-relative rule flipped for dataflow relatives; Zig is the
   *imperative* relative of the sampled loops. The risk is reading a
   Zig construct as "just a loop, already classified" and missing
   that Zig's designers found it worth *changing* — the change is
   the evidence. Read hardest where Zig differs from C, not where
   it differs from us.
3. **Some of Zig's pressures are machine-level.** Branch prediction,
   jump tables, unrolling. The record deliberately assigns that
   layer to the compile (the deferred placement pass; "an
   optimisation/runtime concern, not vocabulary"). Where a Zig
   feature exists partly for codegen, split the reading: the
   legibility half is vocabulary evidence, the codegen half files to
   the compile docs' stance and must not smuggle a construct in.

## Zig's core move, in one paragraph

Zig's control-flow design is one conviction applied repeatedly:
**everything that happens must be visible at the place it happens.**
No exceptions, no operator overloading, no hidden allocations — an
error path, a heap allocation, an async suspension are all readable
at the call site, because the mechanism arrives as a visible value
(`try`, an `Allocator` parameter, an `Io` parameter) rather than an
ambient facility. The Zen list opens "Communicate intent precisely"
and includes "Favor reading code over writing code" and "Only one
obvious way to do things" — the record's discoverability bar and
one-obvious-reading principle, arrived at from the systems side.
Under that conviction they rebuilt C's loops: `for` iterates only
concrete finite sequences (and got multi-sequence lockstep syntax);
`while` pulled the step out of the body into a header clause; loops
became expressions with an on-normal-exit `else` arm and
break-with-value; `switch` gained `continue`-to-a-prong for state
machines; `defer`/`errdefer` moved cleanup next to acquisition. Each
of these is examined below.

## The constructs, against the record

### 1. `while` with a continue expression — the step rejoined to the loop

**Their approach.** C's `for (init; cond; step)` is gone. Zig's
`while` takes an optional *continue expression*: "While loops
support a continue expression which is executed when the loop is
continued. The `continue` keyword respects this expression."

```zig
var i: usize = 1;
var j: usize = 1;
while (i * j < 2000) : ({
    i *= 2;
    j *= 3;
}) {
    const my_ij = i * j;
    try expect(my_ij < 2000);
}
```

The design isolates C's bug class: with the step as an ordinary
statement at the bottom of the body, `continue` skips it — the
classic accidental infinite loop. Zig makes the step un-skippable by
*attaching it to the loop* rather than placing it in the body.

**Our approach — and the correspondence.** This is the record's own
decomposition, shipped in header syntax. A Zig `while` header is
exactly (end-when, register write half) pulled out of the body:

- the condition is **end-when** (stop when the predicate on carried
  state fails);
- the continue expression is **the register's step** — one write
  half per carried variable, fired per advancement, structurally
  impossible to skip, which is precisely what the write-half design
  gives by construction (`iteration-with-state-design.md`;
  the step is a port on the flow, not a statement in the body).

Transcribed (provisional spellings from `translation-exercise.md`):

```
repeat -> open self => ~R                  -- (provisional self-driven flow)
~R ~> delay init 1 => i
~R ~> delay init 1 => j
i -> mul(2) -> step of i
j -> mul(3) -> step of j
i, j -> mul => ij
ij -> lt(2000) -> split id of Go, Done => c
~R, ~c.Done ~> end-when => ~W
```

The registers and end-when carry it at the source's size — but note
what the transcription had to reach for first: `repeat -> open self`.
See finding 2.

### 2. The counter `while` bottoms out at the missing source opener

Zig's plainest loop — a `while` driven only by carried state, no
data walked — is the record's **self-driven flow**, which has no
designed opener (survey class 5; `translation-exercise.md` finding
3; already on the concurrency row with six witnesses). The prior
witnesses were generators, pumps, retries — shapes that read as
somewhat specialized. Zig's testimony is blunter: **the imperative
world's ground-floor loop is the record's least-designed opener.**
Every C-lineage `while (cond)` without an iterated collection lands
there. This does not change what the item is, but it corrects a
possible misreading of its priority: the source opener is not
exotic-flow furniture, it is the other half of ordinary iteration.

The same section of the langref supplies the *pull-source* witness
too — Zig's only iterator protocol is a function returning an
optional, consumed by payload-capture:

```zig
while (it.next()) |value| {
    sum += value;
}
```

There is no iterator interface in the language; `std.mem`'s split,
tokenize, and window iterators are all just structs with a
`next() ?T`. The FFI pull source (`source js "…"`, provisional) is
the record's spelling-in-waiting for exactly this shape — seventh
witness, and the most institutional one: a whole stdlib's iteration
built on pull-until-null.

### 3. Multi-object `for` — the aligned product as the loop syntax

**Their approach.** `for` iterates only concrete, finite,
known-length sequences — slices, arrays, bounded ranges ("Unbounded
range is always a compile error"). And it zips natively:

```zig
for (items, items2) |i, j| {
    count += i + j;
}
// All lengths must be equal at the start of the loop, otherwise
// detectable illegal behavior occurs.   (langref example, verbatim comment)
```

Index access is the same mechanism — `for (items, 0..) |item, i|` —
an unbounded range is *allowed there* because the other operands fix
its length. The index is not a loop mode; it is one more aligned
lane.

**Our approach.** This is the **aligned product (zip)** the APL
round promoted to a demand on the products row
(`apl-family-comparison.md`, finding 2; `open-problems.md`, products
row): Cross's positional sibling — same extent paired by position.
Zig is the second shipped witness and the more pointed one, because
it arrives from the imperative side *as the primary loop construct*:
where B5 in the translation exercise fell back to `range(len(a))`
plus two `index` Apps, Zig's designers decided lockstep pairing was
what `for` fundamentally is. Two pieces of structure travel with the
witness: the **length-equality side condition surfaced as an
asserted precondition** (checked at the barrier, "at the start of
the loop" — not per element), and **indices-as-an-aligned-lane**
(`0..` deriving its extent from its siblings), which answers the
translation exercise's small open note ("whether iteration-by-index
deserves better than materializing a range") in the affirmative and
gives it a shape.

### 4. Loops as expressions: `else`, break-with-value — the readout shipped

**Their approach.** Every loop is an expression. `break` takes a
value; the `else` arm supplies the value when the loop exhausts
("when you break from a while loop, the `else` branch is not
evaluated"):

```zig
fn rangeHasNumber(begin: usize, end: usize, number: usize) bool {
    var i = begin;
    return while (i < end) : (i += 1) {
        if (i == number) {
            break true;
        }
    } else false;
}
```

Labeled `break :outer` / `continue :outer` target enclosing loops.
On optional-iteration the `else` runs "on the first null value
encountered"; and a `while` over an *error union* gives the `else`
arm the error payload (`else |err|`) — the source's exhaustion
arrives discriminated, with data.

**Our approach.** This is the strongest syntax-level confirmation
yet of end-when's readout composition: Zig's (`break v` / `else d`)
pair is the discharge's terminator split with its two lanes —
`Stopped(v)` and `RanOut` — shipped as expression syntax. B1's
transcription shape maps lane-for-lane:

```
range(begin, end) -> open list => i, ~L
i -> equal(number) -> split id of Hit, Miss => m
~L, ~m.Hit ~> end-when => ~W
~W ~> discharge => term
term -> split tag of Stopped, RanOut
  Stopped: true                    -- Zig: break true
  RanOut:  false                   -- Zig: else false
-~> collect => found
```

Three further confirmations ride along: the error-union `while`'s
`else |err|` is the **failable source's terminator payload**
(`async-flow-design.md`'s uniform failability dimension) in the
wild; labeled break across nesting is the readout targeting an
outer flow (drawn, in the record, as end-when on the outer flow
with an inner-derived stop — no new construct); and Effekt's
`while ... else` (finding 6b there) now has a second, more
mainstream sibling. Where Zig is *ahead* of its own lineage —
C has nothing here; Python's `for/else` is famously misread —
the record's version makes the two exit reasons a first-class sum
rather than two syntactic slots, which is what lets the same
readout carry three-plus reasons (the XQuery windowing witness) and
payloads on every lane.

### 5. Labeled `switch` — the state graph demands to be drawn

**Their approach.** New in 0.14: label a `switch`, and `continue
:label operand` jumps "to the matching prong, as if the switch were
executed again with the continue's operand replacing the initial
switch value." The langref is explicit about both motivations:

> "This can improve clarity of (for example) state machines, where
> the syntax `continue :sw .next_state` is unambiguous, explicit,
> and immediately understandable."

> "A loop-based lowering would force every branch through the same
> dispatch point, hindering branch prediction."

The canonical example is a direct-threaded VM:

```zig
return vm: switch (code[ip]) {
    .add => {
        try stack.appendBounded(stack.pop().? + stack.pop().?);
        ip += 1;
        continue :vm code[ip];
    },
    .mul => { ... continue :vm code[ip]; },
    .end => stack.pop().?,
};
```

The langref shows the exact `while (true) { switch (state) { ... } }`
loop it replaces and calls them semantically equivalent. Zig's own
tokenizer was rewritten onto it (`lib/std/zig/tokenizer.zig`,
`state: switch (State.start)` with dozens of `continue :state
.next`), and the 0.14 release notes report a 13% speedup there.

**Our approach.** Split the reading per rule 3. The codegen half —
per-prong dispatch, jump-table placement — is the compile's
business, and Zig's own "semantically equivalent" note confirms no
new semantics live here. The record can already write the VM: two
registers (instruction pointer, stack-as-value) on a self-driven
flow, a case split on the fetched instruction, end-when on the
`.end` alt with the popped value as the `Stopped` payload — every
piece designed except (again) the opener.

The legibility half is the real finding. Zig had a working encoding
(loop + switch + state variable) and judged it bad enough to add
surface syntax whose stated virtue is that **the state graph
becomes readable** — each prong names its successors. In the
record's transcription the successor state is a *value* flowing
into a register step; the graph exists but as data, not as drawn
transitions. That is exactly the question the
**custom-protocol-flows probation** has been carrying
(`tough-use-cases-design.md` item 7: "state machines with one
reading"; second demand at category strength from the reactive
round's statecharts). Zig is the third arrival, and it upgrades the
evidence class: not a library category compensating for a reactive
core, but a *systems language adding syntax*, with the shape
shipped in production compiler code. Where the statechart witness
was documentation-strength, `std.zig.tokenizer` is field code. The
probation's standing rule wanted a field sighting from the owed UI
sample; that sample is still owed (event-handling is a different
population), but the probation should be re-read knowing the shape
now has a field sighting *somewhere* — recorded here, decision left
to the owning doc's conversation. The tokenizer connection also
ties it to breadth item 2 (the tokenizer-substituter): Zig's
tokenizer is that item's shape, and Zig's answer to it is
state-transitions-as-syntax over a mutable cursor — the
deterministic rung of the grammar ladder
(`raku-grammars-comparison.md` finding 1), not the trial rung.

### 6. `defer` / `errdefer` — cleanup adjacency, keyed by exit reason

**Their approach.** `defer` "executes an expression unconditionally
at scope exit," LIFO; `errdefer` runs "if and only if the function
returned with an error from the block"; `errdefer |err|` can read
the error. The langref's stated payoff:

> "you get robust error handling without the verbosity and
> cognitive overhead of trying to make sure every exit path is
> covered. The deallocation code is always directly following the
> allocation code."

```zig
fn createFoo(param: i32) !Foo {
    const foo = try tryToAllocateFoo();
    errdefer deallocateFoo(foo);       // free only if we fail below

    const tmp_buf = allocateTmpBuffer() orelse return error.OutOfMemory;
    defer deallocateTmpBuffer(tmp_buf); // free on every path

    if (param > 1337) return error.InvalidParam;
    return foo;
}
```

And the Zen list carries the constraint the whole design obeys:
**"Resource allocation may fail; resource deallocation must
succeed."**

**Our approach.** Unwritable, and known to be: this is the Tier-1
IO/effects/cancellation row's bracket half (release-on-abandonment,
six arrivals across three documents). What Zig hands that row is
its most concrete structural prior art yet — four load-bearing
properties any bracket design should reproduce:

1. **Adjacency.** The release is written *next to the acquisition*,
   not at the exit sites — their stated core virtue. In a language
   with no scopes, the natural reading is the two-phase form the
   record already owns: acquisition mints a node whose **release
   half is a late-wired operand** (`<port> of <name>`, the
   register-write-half shape the translation exercise generalized),
   fired by the owning flow's discharge rather than by a lexical
   boundary. Recorded as a leaning, not a design.
2. **Exit-reason discrimination.** `defer` vs `errdefer` (with the
   error capturable) is cleanup keyed by *how the scope ended* —
   the terminator, again: release wired per-lane on the discharge's
   split. The createFoo pattern (free-on-failure, transfer-on-
   success) is ownership transfer decided by terminator tag.
3. **The infallibility asymmetry.** Acquisition is failable;
   release must not be. A drawn bracket whose release leg can
   itself raise has no story; Zig's Zen line names the constraint
   the design must state.
4. **Per-firing cleanup.** `defer` in a loop body releases at each
   iteration's end — cleanup scoped to a *firing*, not only to a
   whole walk. The bracket design must attach at both granularities
   (the firing and the flow), which in the record's terms falls out
   if release fires on the discharge of whichever flow owns the
   acquisition.

### 7. Errors as values — failability's shipped mirror

**Their approach.** Error sets are enum-like value sets; `E!T` is an
error union; "`try` evaluates an error union expression. If it is an
error, it returns from the current function with the same error" —
propagate-by-default in one keyword. Handling is `catch default`,
`catch |err| switch (err) { ... }` with **exhaustive** error
switches, `if (f()) |v| ... else |err| switch (err)`. Composition is
worked out: sets merge with `||` ("the Zig standard library uses
`LinuxFileOpenError || WindowsFileOpenError` for the error set of
opening files"), subset coerces to superset (never the reverse
without an asserted cast), and return-type `!T` *infers* the set —
with the costs stated plainly: an inferred-set function "becomes
generic," is awkward to take pointers to, and is "incompatible with
recursion"; their recommended escape is an explicit set, letting
"compile errors guide you toward completing the set."

**Our approach.** The failability design
(`async-flow-design.md`: terminator payloads, propagate-by-default,
discharge at a collect) is this, drawn — the correspondence is
essentially total: `try` is default propagation, `catch |e| switch`
is discharge plus split-on-tag (B1's idiom), exhaustive error
switches are the case collect's exhaustiveness on the failure lane.
Which makes Zig the field answer to the row's two flagged residues
(`open-problems.md`, failability's residue):

- **"Do bodies raise?" — answered yes at one keyword's cost.** The
  everyday validation walk (B2) costs Zig a `try` per failable
  step. Strongest witness yet that the provisional `-> fail` /
  propagate-by-default direction is the right size, and that
  seven-statement end-when encodings of a raise are not viable as
  the everyday form.
- **Payload-type composition — the unexamined question has shipped
  prior art.** Terminator payload types composing across
  subtrees is exactly error-set algebra: union at merge points,
  subset-to-superset coercion along propagation, inference as the
  default with a named escape to explicit sets when inference's
  genericity bites. Their recursion incompatibility is a warning
  worth keeping: inference over a cyclic structure (the record's
  divide flow, feedback forms) is where inferred payload sets stop
  being well-founded.

### 8. Capabilities as parameters — Allocator, `Io`, and the test double

**Their approach.** Zig has no effect system and no dynamic scope;
anything that allocates takes an `Allocator` parameter, and (new,
landing over 0.15/0.16) anything that does IO takes an `Io`
parameter. Swapping the value swaps the meaning: an arena, a
leak-checking debug allocator, a logging wrapper — or, in tests,
`std.testing.FailingAllocator`: "Allocator that fails after N
allocations, useful for making sure out of memory conditions are
handled correctly" — the test double *with fault injection as
configuration*, in the standard library. The `Io` interface
generalizes this to concurrency: `io.async` "may be called
immediately, before `async` returns" — asynchrony is a
*possibility* the caller's chosen implementation may or may not
exploit ("By calling `async` instead, one allows, for example,
stackful single-threaded blocking I/O"); `io.concurrent` is the
stronger, *failable* request (`error.ConcurrencyUnavailable` — "may
occur due to a temporary condition such as resource exhaustion, or
to the Io implementation not supporting concurrency").
Cancellation is built in at the same layer: `Future.cancel` is
"equivalent to `await` but places a cancellation request" — cancel
*returns the result*; `Group.wait` propagates cancellation to all
members, `Group.cancel` is wait-plus-cancel-all; `io.select` races
a set of futures.

**Our approach.** Three existing rows collect this:

- **Late-bound operations and the test double** (functions row):
  fourth independent witness, and the flattest mechanism yet — no
  handlers, no proto regexes, no provider stacks; *ordinary
  parameters* suffice, which supports the row's inside-out leaning
  (a provider wired onto a boundary port) over any dynamic-scope
  reading. FailingAllocator adds a piece the prior witnesses
  lacked: the double as a **fault injector** — the test double
  question includes "make the fake fail on demand."
  Allocator wrappers (arena, leak-checking, logging) are the
  **policy layer**'s third witness-as-furniture.
- **The concurrency row**: Zig lands on the record's side of a line
  the survey corpora blur — *the drawing permits concurrency
  without demanding it*. `async`-as-possibility is the DAG's
  stance in API form; `concurrent`-as-failable-request is new
  structure for the concurrent collect's round: demanding
  parallelism is a **resource claim that can fail**, which slots
  beside `bounded(n)`-as-resource. And their cancellation cluster
  confirms the record's leanings from the field: cancel-returns-
  the-result is cancellation-as-discharge (the cancelled
  computation still terminates, with a readable terminator);
  group-wait-propagates-cancel is scope-bound task lifetime
  (`spawn @ region`'s second witness); `cancelRequested` polling is
  the cooperative floor the IO round will need to name.
- **One clash-flavored note**: `io.select` returns a *tagged union
  built from the contenders* (`SelectUnion`) — the sum bottleneck
  the race barrier's per-contender lanes exist to avoid. The
  mitigating half: the union is discriminated by contender name,
  so the winner arrives *discriminated* — the side-flags
  reconstruction survey 3 diagnosed does not occur. Confirmation
  that discrimination must be structural; the packing itself is
  what the record's barrier form dissolves.

### 9. `comptime`, `inline for`/`while`, `unreachable` — brief

`comptime` is Zig's whole generics-and-metaprogramming story
(run the language at compile time over types). Mechanism, out of
scope; the record's counterpart commitments (derivation downward,
level-1 computations) are differently shaped and nothing here
demands importing theirs. Two small notes survive: the **inline
guidance is the record's placement stance verbatim** — "use inline
loops only [when] you need the loop to execute at comptime for the
semantics to work [or] you have a benchmark" — unrolling is not
semantics; and `unreachable` (an *optimizer assumption* in release
modes, a checked crash in safe modes) is the imperative costume of
a declared-then-trusted property, supporting the checking row's
demands/offers framing with its mode split (witnessed in debug,
assumed in release) as prior art for check-now vs trust-later.

## What transcription showed, in sum

Attempted against the langref's own programs: the doubling scan
(§1), the search-with-default (§4), the VM (§5). The register +
end-when + discharge core carried each at roughly source size —
Zig's redesigned loop headers decompose into exactly the record's
constructs, which is the round's central confirmation. The two
walls were the standing ones: **no self-driven source opener**
(every counter `while`, the VM, every iterator pump starts off the
page) and **per-firing effects** (`createFoo`, and any loop whose
body writes — untranscribed, per the Tier-1 row). Multi-object
`for` needs the aligned product to transcribe as itself rather than
via indices. No *new* wall was found: Zig's home turf is territory
the record has already either designed or ranked.

## Findings

**Finding 1 — Zig's `while` header is the record's decomposition,
shipped.** Condition = end-when; continue expression = the
register's write half, attached to the loop precisely so `continue`
cannot skip it — C's skip-the-increment bug class is the negative
witness for making the step structural rather than positional.
Confirmation for the iteration-state round's write-half design and
for end-when; no score movement.

**Finding 2 — the missing source opener is the imperative ground
floor.** The plainest `while` in the language transcribes onto
`repeat -> open self`, which has no designed form; the stdlib's
entire iteration story is pull-until-null, the FFI pull source's
seventh and most institutional witness. Priority correction, not a
new item: the opener gates ordinary loops, not just pumps and
generators. Concurrency row's remaining list, already there —
weight added.

**Finding 3 — the aligned product's second shipped witness, from
the imperative side.** Zig made zip the primary `for` syntax, with
the length-equality side condition as an asserted-at-the-barrier
precondition and indices as one more aligned lane (`0..`). Products
row's zip demand strengthened; the index-lane reading answers the
translation exercise's range-materializing note.

**Finding 4 — the discriminated readout shipped as expression
syntax.** `break v` / `else d` (and `else |err|` on failable
sources) is the discharge's Stopped/RanOut split lane-for-lane;
end-when confirmation from the systems mainstream, plus the
failable-source terminator payload in the wild.

**Finding 5 — the state graph demands to be drawn.** Labeled
switch is the custom-protocol-flows probation's third arrival and
its first *field* sighting (`std.zig.tokenizer`, production code, a
measured 13% besides): a systems language added syntax whose stated
virtue is that state transitions become "unambiguous, explicit, and
immediately understandable." The record can transcribe the shape
(registers + case split + end-when) but the graph lives in values,
not drawn transitions — exactly the probation's question. The
codegen half of Zig's motivation files to the compile stance, not
to vocabulary. Probation decision stays with its owning doc; the
owed UI sample keeps its question.

**Finding 6 — the bracket's structure round.** `defer`/`errdefer`
hand the Tier-1 row four properties: release adjacent to
acquisition (in the record's terms, a late-wired release half on
the acquiring node — the `<port> of <name>` two-phase form again,
fired at the owning flow's discharge); cleanup keyed by exit reason
(errdefer = per-terminator-lane release, with payload); the
infallibility asymmetry ("Resource allocation may fail; resource
deallocation must succeed"); and per-firing as well as per-flow
attachment. Structural prior art for the cancellation/bracket half,
complementing the XQuery pending-update-list prior art on the
effects half.

**Finding 7 — failability's two flagged residues get field
answers.** Bodies-raise: yes, at one keyword's cost (`try`), the
strongest witness for propagate-by-default plus a lightweight
`fail`. Payload-type composition: error-set algebra shipped — union
at merges, subset-to-superset coercion along propagation, inference
by default with a named escape to explicit sets, and a warning that
inference breaks on recursion. Handed to the failability-residue
row.

**Finding 8 — capabilities as ordinary parameters.** Late-bound
operations' fourth witness and the flattest: no machinery at all,
just values passed in — supporting the inside-out
provider-on-a-port leaning; FailingAllocator adds fault injection
to the test-double question; allocator wrappers are the policy
layer's third furniture witness. The `Io` layer contributes to the
concurrency row: asynchrony-as-possibility (the DAG's stance in API
form), concurrency-as-failable-resource-claim (beside
`bounded(n)`), cancel-as-await (cancellation discharges a readable
terminator), group-scoped cancel propagation, and the select-union
packing as the sum bottleneck's clash note with its discrimination
half confirmed.

**Finding 9 — what not to import, and why (the clash record).**
(a) *Visibility by prohibition.* Zig keeps call sites honest by
forbidding abstraction (no overloading, no exceptions, no hidden
calls); the record aims at the same Zen — intent precise, reading
over writing, one obvious way — by *drawing* the flow instead, so
the capability (abstraction) survives while the visibility is
structural. Same bar, opposite mechanism; the bar is the shared
part. (b) *The mutable substrate.* Every Zig loop is registers all
the way down (cursor, accumulator, state variable, `self.index`);
transcription confirms the record's registers cover it, but the
substrate itself — one mutable cell, many writers across arms — is
what the one-writeback rule exists to exclude, and no sample here
broke that rule either (the survey's finding stands at seventy-plus
sites). (c) *`comptime` as the abstraction story* — running the
language over types at compile time; the record's derivation
commitments point the other way (downward, read-only views).
(d) *Machine-level motivation is not vocabulary* — branch
prediction justified labeled switch's codegen, not its legibility;
only the latter is evidence here.

## What this round changes in `open-problems.md`

No new row; no score movement. Dated notes:

- **IO, effects, and cancellation (Tier 1)**: finding 6 — the
  bracket half's structural prior art (adjacency via a late-wired
  release half; exit-reason-keyed cleanup; the infallibility
  asymmetry; per-firing attachment), plus finding 8's cancellation
  cluster (cancel-as-await, group propagation, cooperative floor).
- **Concurrency constructs (Tier 2)**: findings 2 and 8 — source
  opener weight correction (imperative ground floor; seventh
  witness), asynchrony-as-possibility vs
  concurrency-as-failable-claim to the concurrent collect's round,
  select-union note to the race round.
- **Failability's residue (Tier 2)**: finding 7 — bodies-raise and
  payload composition both gain shipped answers.
- **Functions, reuse, and facets (Tier 2)**: finding 8 — fourth
  late-bound-operations witness (parameters suffice), fault
  injection added to the test-double question, policy layer's third
  witness.
- **Loop-carried state (Tier 2)** and **end-when (Tier 3)**:
  findings 1 and 4, confirmation notes.
- **Products (Tier 3)**: finding 3 — zip's second shipped witness,
  the side condition's placement, indices as a lane.
- **Variable-rate consumption (Tier 2)**: small note —
  `std.mem.window(T, buf, size, advance)` ships window(k) with an
  independent step parameter and emits the partial final window
  (the unterminated-final-segment bit set to "emit"), one more
  point in the window family's design space.
- **Evidence owed**: the UI sample's statechart question gains the
  cross-reference that the protocol shape now has a field sighting
  in a systems language (finding 5).

## Next rounds of this genre

The genre has now covered handlers, grammars, Datalog, document
dataflow, arrays, reactive cores, and the imperative mainstream.
Still unvisited from the original list: a beginner-first language
(Scratch/HyperCard lineage — where the discoverability bar is the
whole language and the record's beginner claims would face their
real jury); and from this round's vantage, a hardware-description
or synchronous language (Verilog/VHDL, Lustre/Esterel) would
stress-read the register/clock story from the side that never had
mutable loops at all.
