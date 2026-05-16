# Commuting Option Out of List: Design Notes

## What "commute" means here

We have a list iter with an option iter inside it — a `List<Option<X>>`.
Today, joining the inner option close to the outer list level produces a
`List<X>` of just the defined values (push when Some, skip when None).
That's a useful operation, but it's not the *commute* we're after now.

Commute swaps the nesting: `List<Option<X>>` → `Option<List<X>>`. The
outer is now an option whose Some-case carries the list of all values,
and whose None-case fires if *any* iteration's option was None. In
Haskell terms this is `sequence :: [Maybe a] -> Maybe [a]`.

The two operations are genuinely different — the output containers
differ — so commute is a new primitive, not a variant of join.

## Why this is harder than join

Join has no runtime effect of its own. It's a *layout* annotation: it
tells the compiler "put this close's output binding one scope higher."
The JS emitted is otherwise identical to a non-joined close. Whatever
the loop was doing, it still does.

Commute has runtime effect. Its meaning *is* "stop accumulating and
report None the moment you see a None." If we implement that literally,
we have to actually stop the loop early — and that "stopping" interacts
badly with everything else the loop might be doing.

## The deeper conflict

Lists, as the compiler currently models them, are *eager* and *reusable*.
An Open ListIter compiles to a `for…of` over a JS array; consumers attach
to it freely (multi-close just works); the same list expression can feed
multiple loops, each running to completion, each producing whatever
outputs it wants. That model is a good fit for "transform/filter/zip
data already in hand" — which is most of what the language does today.

Commute wants a different shape. To respect the "stop on first None"
semantics, the list-as-data-structure has to behave like a stream
consumed once-through, where the consumer can say "I'm done" and the
producer doesn't compute more elements. That's a *linear, one-shot*
data structure. Linearity is what makes "stop" meaningful: if nobody
else is reading, stopping is just stopping; if other readers are still
pulling, stopping is incoherent.

Trying to bolt commute onto today's list flow forces us to choose
between:

- Pretending the list is linear (break out of the for-of), which
  truncates *all other consumers'* output. They get fewer elements than
  the input list had, and the language never warned them this could
  happen.
- Pretending the commute consumer is allowed to peek without affecting
  others (no short-circuit), which gives correct semantics for commute
  itself but burns CPU on iterations whose results commute won't use,
  and forces us to compute intermediate values nobody on the
  short-circuit path needed.
- Forbidding multi-output once a commute is present, which is a hidden
  linearity rule the user can't see in the diagram.

None of these is great, and all three exist because we're asking one
flow type to play two roles.

## The wasted-intermediate-values question

Even with one perfectly linear consumer, commute has a second-order
problem. Suppose the loop body is

    elem -> expensive(elem) -> isValid -> Option<X>
                            \-> someStat              (only consumer is a list close)

If commute terminates at iter K, iters K+1..N should not compute
`expensive`. But `someStat`'s consumer needs them. So `expensive` has
to be either:

- Computed lazily and forced only when needed (then we need a "force"
  mechanism and a memo so the two consumers share work when both want
  the value).
- Computed eagerly always (then the iteration cost is the same whether
  we short-circuit commute or not — and short-circuiting commute saves
  almost nothing).

Lazy values inside the loop body would be a significant extension to
the language. Eager-always defeats most of the point of short-circuit.

## Options considered

### 1. Lazy streams replacing loops

Compile lists as pull-based iterators rather than for-of loops. Each
consumer holds its own cursor and pulls; if a consumer stops pulling,
no more work is done for it. Shared intermediate values get a memo so
the second consumer doesn't recompute.

Pros: single uniform model that handles commute, multi-consumer, and
wasted-intermediate all at once.
Cons: a much heavier runtime than `for…of` — generator/iterator
protocol per element, allocation per yield, plus a memo per shared
value. Loses the "compiles to a tight loop" property that makes today's
output readable JS.

### 2. Make the list flow linear

Restrict every list flow to at most one Close. Multiple outputs require
an explicit `tee` (or `dup`) operation that takes a list flow and
produces two list flows. The two branches are then independently
linear.

Pros: principled. The visual language acquires a real linearity rule,
and commute (and other one-shot operations) fit naturally.
Cons: every existing multi-close diagram breaks until rewritten with
`tee`. The compile target for `tee` is also nontrivial: either you
buffer everything (loses any short-circuit benefit) or you actually
run two independent loops (which means re-computing whatever the
shared computations were, with no memo).

### 3. Linear list flow + separate stream flow

Keep lists linear (per Option 2), but add a stream flow as a separate
primitive. Streams are lazy and pull-based; their consumers can stop
independently. Commute is a stream-level operation, never a list one.

Pros: each flow type plays one role cleanly. Lists stay tight loops.
Streams handle the cases that need linearity-with-stoppage.
Cons: still breaks existing multi-close. Two flow types to learn. The
wasted-intermediate-values problem in streams still wants lazy values,
which is a further extension.

### 4. Hybrid: loops when safe, streams when commute is in play

Same data type at the language level; the compiler picks the backend.
A list flow with no commute consumers compiles to a for-of; one with
commute compiles to a stream.

Pros: invisible to the user; no breaking change.
Cons: invisible to the user — performance characteristics depend on
nonlocal properties of the diagram. "I added a commute over here and
everything got 10× slower" is a bad failure mode. Also doesn't solve
the multi-consumer-of-a-commuted-list problem; it just relocates it
into the stream compile, where Option 3's caveats apply.

### 5. Loops that cut short in multiple alternative ways

Add a "break vote" mechanism: each commute close registers an
intent-to-stop; the loop continues until every consumer either
finishes naturally or votes to stop. In the multi-consumer case
where only one consumer wants to stop, the loop keeps going.

Pros: stays in the loop model.
Cons: in the very case that motivates the design — commute alongside
other consumers — there's still no short-circuit, so the wasted-CPU
problem isn't solved. We've just paid for the vote protocol with
nothing to show for it.

### 6. Non-short-circuiting commute (the easy half)

Implement commute *without* the cut-the-loop-short part. The loop runs
to completion. The commute close accumulates into a list and tracks
whether any iter was None; after the loop, it emits Some(list) or
None.

Pros: zero conflict with multi-consumer; zero changes to the existing
flow model. Drop-in addition. Semantically correct.
Cons: misses the "stop early" property the user named as the
interesting one. Wasted CPU after the first None — bounded but real.
For pure code, fine; for side-effecting code (which the language
doesn't yet have), wrong.

### 7. Commute as the sole consumer of its list

Allow commute only when it's the *only* close on its list. Single
consumer ⇒ no conflict; the loop can break freely. Reject the diagram
at compile time if any other close shares the underlying ListLoop.

Pros: short-circuit works; nobody else is affected because there is
nobody else.
Cons: a context-sensitive linearity rule the user has to discover by
hitting the error. Doesn't generalize. Awkward to explain.

### 8. Side-band break with truncated other consumers

Implement commute as a real `break`. Document that other consumers of
the same list also stop at that point. So a list-close sibling gets the
elements up to iter K, not all of them.

Pros: simple to implement.
Cons: a footgun. The truncation is invisible from the diagram. A
beginner adds a commute and silently changes what their other outputs
contain.

### 9. Commute as a JS-level function on lists, not a flow operation

Don't add commute to the flow language at all. Produce a `List<Option
<X>>` with the existing tools (multi-close on an outer list pushing
inner-option outputs), then App a `sequence` JS function over it.

Pros: no language changes; no semantic puzzles.
Cons: the data flow's structural commute isn't visible in the diagram
— it's hidden inside a JS function. The motivation for adding commute
as a flow op is presumably that we want it to be a first-class
diagrammatic rearrangement, not a post-hoc function call.

## Recommendation

The deeper observation behind the user's framing is that **list flow,
as currently modeled, conflates two distinct things**: a passive data
structure (an array you can iterate over multiple times) and an active
process (an iteration that's happening once). Most of what we use list
flow for is the former; commute wants the latter.

Trying to make list flow do both is what produces all the awkward
tradeoffs above. The honest split is:

- Keep the **list flow** as it is: eager, reusable, multi-consumer,
  compiles to `for…of`. Commute is *not* available on it.
- Add a **stream flow** later: lazy, single-consumer, supports
  commute and other early-termination operations. Compiles to either
  generators or hand-rolled iterators.

This is essentially Option 3, but consciously deferred: stream flow is
a real extension worth designing on its own terms (lazy intermediate
values, linearity rules, what visual cue distinguishes a stream from
a list, what the join/filter/case-split analogs look like for streams,
etc.), and the right time to take it on isn't while bolting an
ill-fitting commute onto list flow.

In the meantime, if there's a near-term need for the operation, **the
right step is Option 6 — non-short-circuiting commute on the existing
list flow.** It's the only option in the list that adds the feature
without committing to any of the design tensions that would have to be
relitigated when stream flow arrives. Specifically:

- It works with multi-consumer.
- It produces correct results.
- It does *not* claim to do early termination, so users (and the
  visual language) aren't promised something it can't honor.
- It introduces a single new flowRef constructor (something like
  `Commuted(flowRef)`) and a single new consumer path. Removing it
  later, or generalizing it for stream flow, is local work.

The wasted-CPU cost is bounded by the size of the list and is purely
a performance concern in the absence of side effects. For typical
"validate this list of inputs" or "parse this list of tokens" use
cases on lists of modest size, it's a non-issue. If the cost ever
matters, that's the signal to start the stream-flow conversation, not
the signal to retrofit linearity onto list flow.

### Concretely, what Option 6 looks like

A new flowRef constructor, parallel to `Joined` / `Filtered`:

    | Commuted(flowRef)

Valid wrap: an option iter, possibly with Joineds on top of it (for
deeper nesting). The compile target for a single commute close on
`List<Option<X>>`:

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

Output is at the list's parent. Multi-consumer works as before — a
sibling list close pushing into its own array is unaffected.

Whether the `if (elem !== undefined) … else { v_ok = false; }` form is
better than `if (elem === undefined) v_ok = false; else …` or a single
short-circuit pattern is a small choice; the structural point is that
the loop runs to completion either way.

## Open questions to settle when implementing

- **Commute over deeper nestings.** `List<List<Option<X>>>` — does
  commute lift over one level or all the way out? Likely "one level
  per Commuted wrapper," parallel to how Joined behaves.
- **Commute through joined chains.** Can `Commuted(Joined(...))`
  appear, and what does it mean? Most likely: "commute *and* lift one
  list level," giving `Option<List<X>>` at two levels up. Probably
  worth either supporting uniformly or rejecting cleanly until
  there's a concrete use case.
- **Empty list.** If the input list is empty, the result should be
  `Some([])`. The accumulator pattern above produces this correctly
  (v_ok stays true, v_acc stays empty, v_out becomes `[]`).
- **Multiple commute closes on one list.** Two commute closes on the
  same `List<Option<X>>` with different per-iter values. Each gets
  its own `v_acc` and shares the `v_ok` flag (since both fail on the
  same None). Or each gets its own v_ok — slightly more flexible
  (different commutes could be over different sub-options). Worth
  thinking through with a concrete example.

## What this leaves unsolved

The "wasted intermediate values" question never gets answered by
Option 6. Within the loop body, intermediate Apps are still computed
every iteration, even when only the commute consumer would use them
and even when the commute has effectively already failed. That's the
cost we pay for not having short-circuit; it stays on the table for
the stream-flow discussion.

The linearity question also stays open. As long as list flow is
multi-consumer, no operation that requires real linearity can be added
to it. Commute is the first such operation we've thought through;
others will appear (anything that involves stoppage, anything
side-effecting, anything that consumes a generator). Stream flow is
where those should live.
