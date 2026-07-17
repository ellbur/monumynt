# Commuting Option Out of List: Design Notes

> **Status: superseded stopgap — kept for its options analysis.** This
> document worked out what `commute` should mean and where it could live.
> Its recommendation was Option 3 (defer commute to the stream-flow
> conversation), with Option 6 — a non-short-circuiting commute bolted
> onto the existing eager list flow — held as the near-term stopgap *if*
> one proved necessary. The stopgap was never needed or built. The stream-flow conversation it deferred to happened
> instead, and commute landed there as a per-close output annotation on
> *stream* flows — the "honest split" this document recommends as the real
> answer (the deferred half of Option 3). See `lazy-stream-placement-design.md`,
> `lazy-stream-join-design.md`, and `lazy-stream-commute-design.md`.
>
> What survives, and why this file is kept: the nine-option survey (below)
> and the list-flow linearity critique are the reasoning that led to
> streams, and the stream docs build on them directly. The `Commuted(flowRef)`
> constructor proposed here survived too — only its host flow moved from
> list to stream. What is specifically discarded is Option 6 as a stopgap:
> once streams are designed, there is no reason to add a commute that
> cannot short-circuit.
>
> One reconciliation carries forward. The spec's `Commute` *node* (flow
> wires only, no value ports) is the representation; the per-close
> construction here is the compilation. "Swap-and-continue" turned out not
> to be expressible at all. See `visual-language-spec.md` under "Commute".
>
> Terminology: this document says open/close (the older names for
> uncollect/collect); the code still says `Open`/`Close`.

## What "commute" means here

Start with a list iteration that has an option iteration nested inside it
— a `List<Option<X>>`. There are two distinct things you might want.

*Join* (already available): merge the inner option level into the outer
list. Push a value when the option is Some, skip when None. The result is
a `List<X>` of just the defined values — the filter reading.

*Commute* (what this document is about): swap the nesting.
`List<Option<X>>` becomes `Option<List<X>>`. The outer container is now an
option: Some carries the list of all values, and None fires if *any*
iteration's option was None. In Haskell terms this is
`sequence :: [Maybe a] -> Maybe [a]`.

The two operations produce different output containers, so commute is a
new primitive, not a variant of join.

## Why this is harder than join

Join has no runtime effect of its own. It is a *layout* annotation: it
tells the compiler "put this close's output binding one scope higher." The
emitted JS is otherwise identical to a non-joined close — whatever the
loop was doing, it still does.

Commute has runtime effect. Its meaning *is* "stop accumulating and report
None the moment you see a None." Implemented literally, that requires
actually stopping the loop early — and that stopping interacts badly with
everything else the loop might be doing.

## The deeper conflict: two roles for one flow type

Lists, as the compiler models them, are *eager* and *reusable*. An `Open
ListIter` compiles to a `for…of` over a JS array. Consumers attach freely
(multi-close just works); the same list expression can feed several loops,
each running to completion, each producing its own outputs. This is a good
fit for "transform / filter / zip data already in hand," which is most of
what the language does today.

Commute wants a different shape. To respect "stop on first None," the list
has to behave like a stream consumed once through, where the consumer can
say "I'm done" and the producer stops computing. That is a *linear,
one-shot* structure. Linearity is what makes "stop" meaningful: if nobody
else is reading, stopping is just stopping; if other readers are still
pulling, stopping is incoherent.

Bolting commute onto today's list flow forces a choice among three bad
options:

- **Pretend the list is linear** (break out of the `for…of`). This
  truncates *every other consumer's* output — they get fewer elements than
  the input had, unwarned.
- **Pretend commute can peek without affecting others** (no short-circuit).
  This is correct for commute but burns CPU on iterations commute won't
  use, and computes intermediate values nobody on the short-circuit path
  needed.
- **Forbid multi-output once a commute is present.** That is a hidden
  linearity rule the user cannot see in the diagram.

All three exist because one flow type is being asked to play two roles.

## The wasted-intermediate-values question

Even with a single perfectly linear consumer, commute has a second-order
problem. Suppose the loop body is:

```
elem -> expensive(elem) -> isValid -> Option<X>
                        \-> someStat              (only consumer is a list close)
```

If commute terminates at iteration K, iterations K+1..N should not compute
`expensive`. But `someStat`'s consumer needs them. So `expensive` must be
either:

- **Computed lazily** and forced only when needed — which requires a force
  mechanism and a memo so the two consumers share work when both want the
  value.
- **Computed eagerly always** — in which case the iteration cost is the
  same whether commute short-circuits or not, so short-circuiting saves
  almost nothing.

Lazy values inside the loop body would be a significant extension.
Eager-always defeats most of the point of short-circuit.

## Options considered

Nine ways to reconcile commute with the flow model, each with its cost.

### 1. Lazy streams replacing loops

Compile lists as pull-based iterators rather than `for…of`. Each consumer
holds its own cursor and pulls; a consumer that stops pulling causes no
more work for itself. Shared intermediate values get a memo so a second
consumer doesn't recompute.

- **Pros:** one uniform model handles commute, multi-consumer, and
  wasted-intermediate at once.
- **Cons:** a much heavier runtime than `for…of` — generator/iterator
  protocol per element, allocation per yield, a memo per shared value.
  Loses the "compiles to a tight loop" property that makes today's output
  readable.

### 2. Make the list flow linear

Restrict every list flow to at most one close. Multiple outputs require an
explicit `tee` (or `dup`) that takes a list flow and produces two,
independently linear.

- **Pros:** principled — the language acquires a real linearity rule, and
  commute (and other one-shot operations) fit naturally.
- **Cons:** every existing multi-close diagram breaks until rewritten with
  `tee`. The compile target for `tee` is nontrivial: either buffer
  everything (loses short-circuit) or run two independent loops
  (recomputing the shared work, with no memo).

### 3. Linear list flow + separate stream flow

Keep lists linear (per Option 2) but add a stream flow as a separate
primitive. Streams are lazy and pull-based; their consumers stop
independently. Commute is a stream operation, never a list one.

- **Pros:** each flow type plays one role cleanly. Lists stay tight loops;
  streams handle linearity-with-stoppage.
- **Cons:** still breaks existing multi-close. Two flow types to learn. The
  wasted-intermediate problem in streams still wants lazy values, a further
  extension.

### 4. Hybrid: loops when safe, streams when commute is in play

One data type at the language level; the compiler picks the backend. A
list flow with no commute consumers compiles to `for…of`; one with commute
compiles to a stream.

- **Pros:** invisible to the user; no breaking change.
- **Cons:** invisible to the user — performance depends on nonlocal
  properties of the diagram. "I added a commute over here and everything
  got 10× slower" is a bad failure mode. Also doesn't solve
  multi-consumer-of-a-commuted-list; it just relocates the problem into the
  stream compile, where Option 3's caveats apply.

### 5. Loops that cut short in multiple alternative ways

A "break vote" mechanism: each commute close registers intent-to-stop; the
loop continues until every consumer either finishes naturally or votes to
stop. When only one consumer wants to stop, the loop keeps going.

- **Pros:** stays in the loop model.
- **Cons:** in the very case that motivates the design — commute alongside
  other consumers — there is still no short-circuit, so the wasted-CPU
  problem is unsolved. The vote protocol is paid for with nothing to show.

### 6. Non-short-circuiting commute (the easy half)

Implement commute *without* cutting the loop short. The loop runs to
completion; the commute close accumulates into a list and tracks whether
any iteration was None; afterward it emits `Some(list)` or `None`.

- **Pros:** zero conflict with multi-consumer; zero changes to the flow
  model; a drop-in, semantically correct addition.
- **Cons:** misses the "stop early" property the user named as the
  interesting one. Wastes CPU after the first None — bounded but real. Fine
  for pure code; wrong for side-effecting code (which the language doesn't
  yet have).

### 7. Commute as the sole consumer of its list

Allow commute only when it is the *only* close on its list. Single consumer
means no conflict, so the loop can break freely. Reject the diagram at
compile time if any other close shares the underlying list loop.

- **Pros:** short-circuit works; nobody else is affected because there is
  nobody else.
- **Cons:** a context-sensitive linearity rule the user discovers only by
  hitting the error. Doesn't generalize. Awkward to explain.

### 8. Side-band break with truncated other consumers

Implement commute as a real `break`, and document that other consumers of
the same list also stop at that point — a sibling list-close gets the
elements up to iteration K, not all of them.

- **Pros:** simple to implement.
- **Cons:** a footgun. The truncation is invisible from the diagram; a
  beginner adds a commute and silently changes what their other outputs
  contain.

### 9. Commute as a JS-level function on lists, not a flow operation

Don't add commute to the flow language at all. Produce a `List<Option<X>>`
with existing tools (multi-close on an outer list pushing inner-option
outputs), then App a `sequence` JS function over it.

- **Pros:** no language changes, no semantic puzzles.
- **Cons:** the structural commute is invisible in the diagram — hidden
  inside a JS function. The whole point of adding commute as a flow op is
  to make it a first-class diagrammatic rearrangement, not a post-hoc
  function call.

## Recommendation

The observation behind all of the above: **list flow, as currently
modeled, conflates two distinct things** — a passive data structure (an
array you can iterate many times) and an active process (an iteration
happening once). Most uses of list flow want the former; commute wants the
latter. Making one flow type do both is what produces every awkward
tradeoff.

The honest split:

- Keep the **list flow** as it is — eager, reusable, multi-consumer,
  compiles to `for…of`. Commute is *not* available on it.
- Add a **stream flow** later — lazy, single-consumer, supporting commute
  and other early-termination operations. Compiles to generators or
  hand-rolled iterators.

This is Option 3, consciously deferred. Stream flow is a real extension
worth designing on its own terms (lazy intermediate values, linearity
rules, the visual cue distinguishing a stream from a list, the
join/filter/case-split analogs for streams), and the time to take it on is
not while bolting an ill-fitting commute onto list flow.

### The stopgap that was on the table (superseded)

If a near-term need for the operation had arisen before stream flow, the
right step would have been **Option 6 — non-short-circuiting commute on the
existing list flow.** It is the only option that adds the feature without
committing to any of the design tensions that stream flow would have to
relitigate:

- It works with multi-consumer.
- It produces correct results.
- It does *not* claim early termination, so neither users nor the language
  are promised something it can't honor.
- It introduces one new flowRef constructor (`Commuted(flowRef)`) and one
  new consumer path. Removing it later, or generalizing it for stream flow,
  is local work.

The wasted-CPU cost is bounded by the list size and is purely a
performance concern absent side effects. For "validate this list of inputs"
or "parse this list of tokens" over modest lists, it's a non-issue. If the
cost ever mattered, that was the signal to start the stream-flow
conversation — not to retrofit linearity onto list flow. In the event,
stream flow was taken up directly and the stopgap was never needed.

### Concretely, what Option 6 would have looked like

A new flowRef constructor, parallel to `Joined` / `Filtered`:

```
| Commuted(flowRef)
```

Valid wrap: an option iter, possibly with `Joined`s on top of it (for
deeper nesting). The compile target for a single commute close on
`List<Option<X>>`:

```js
const v_acc = [];
let v_ok = true;
for (const elem of input) {
  if (elem !== undefined) {
    v_acc.push(value);
  } else {
    v_ok = false;
  }
}
const v_out = v_ok ? v_acc : undefined;
```

The output binding lands at the list's parent. Multi-consumer works as
before — a sibling list close pushing into its own array is unaffected. The
loop runs to completion either way; whether the test is written
`if (elem !== undefined) … else …` or its inverse is a cosmetic choice.

## Open questions (their stream analogs are live)

These were posed for the Option-6 list-flow implementation that isn't
happening. Their stream counterparts — layering with `Joined`, deeper
commutes, generalising past option — are the open questions of
`lazy-stream-commute-design.md`. The empty-input answer carries over
unchanged: `Some([])` (or `Some` of the empty stream).

- **Commute over deeper nestings.** For `List<List<Option<X>>>`, does
  commute lift over one level or all the way out? Likely "one level per
  `Commuted` wrapper," parallel to `Joined`.
- **Commute through joined chains.** Can `Commuted(Joined(...))` appear,
  and what does it mean? Most likely "commute *and* lift one list level,"
  giving `Option<List<X>>` two levels up. Worth either supporting uniformly
  or rejecting cleanly until there is a concrete use case.
- **Empty list.** An empty input should give `Some([])`. The accumulator
  pattern produces this correctly: `v_ok` stays true, `v_acc` stays empty,
  `v_out` becomes `[]`.
- **Multiple commute closes on one list.** Two commute closes with
  different per-iter values: each gets its own `v_acc`. Do they share the
  `v_ok` flag (both fail on the same None) or get their own (different
  commutes over different sub-options)? Worth working through on a concrete
  example.

## What this leaves unsolved (answered by stream flow, not list flow)

Both threads below were resolved by the stream-flow design rather than
within list flow:

- **Wasted intermediates.** `Delayed`-cell memoisation makes per-element
  work lazy and shared across consumers, so a short-circuiting consumer
  forces only what it needs (`lazy-stream-placement-design.md`). Option 6
  never answered this — its loop body still computes every intermediate App
  each iteration, even when only the commute consumer would use it and even
  after the commute has effectively failed.
- **Linearity.** Streams are multi-consumer via per-consumer cursors over
  memoised cells, so stoppage never truncates siblings — the linearity
  restriction turned out unnecessary in the lazy model
  (`lazy-stream-commute-design.md`, "Multi-output independence"). As long
  as list flow stays multi-consumer, no operation requiring real linearity
  can be added to it; commute was the first such operation thought through,
  and stream flow is where those belong.
