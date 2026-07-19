# The core model

This is the place to start learning the language. It walks through the
core ideas with small programs, simplest first; everything else in the
design record builds on what's here. The seven principles behind the
design are in `language-design-philosophy.md`, and the notation the
code samples use is defined in `textual-representation-design.md` —
but you don't need either to read this page. Each piece of notation is
explained the first time it appears.

## Your first program

Here is a complete program. It doubles every number in a list:

```
double = js "x => x * 2"
[1, 2, 3] -> open list -> double -~> collect => out    -- out = [2, 4, 6]
```

Read it left to right. The first line defines `double` by borrowing a
JavaScript function (`js "…"` is the escape hatch for that). The
second line is the interesting one:

- `[1, 2, 3]` is a list.
- `-> open list` opens the list up, so that what flows onward is
  *each element in turn* rather than the list as a whole.
- `-> double` applies to each element as it comes through.
- `-~> collect` closes the iteration back up, gathering the doubled
  elements into a list again.
- `=> out` names the result.

So a "loop" in this language is a stretch of wire between an **open**
and a **collect**. Between those two points, the wire carries one
element at a time; before and after, it carries an ordinary value.
Opening is also called **uncollect** — it is collect's inverse, and
the pair uncollect/collect are the two fundamental operations.
Everything iterative in the language is built from them. (In the
implementation they are the `Open` and `Close` node kinds, and some
older notes use the informal glyphs `$` for uncollect and `@` for
collect.)

## Blocks turned inside out

If you're used to conventional languages, notice what the program
above *doesn't* have: a loop body. There is no block, no `{ ... }`,
no region of code that is "inside the loop" while the rest is
outside.

Traditional languages contain control flow in scoped blocks. The body
of a loop or an `if` lives *inside* a construct, and what is visible
inside differs from what is visible outside. This language inverts
that. The interior of what would be a block becomes explicit values
and flows, wired through the diagram. Control flow is not implicit
containment; it is explicit wiring. No construct makes an
expression's interior scope differ from its exterior.

The whole static graph is the program. Wires are structural, not
runtime data flowing through boxes: the graph has meaning when
complete, and the intermediate wires are symbolic — a wire stands for
"the element here," not a particular value at a particular moment.

## Two sorts of wire

Look again at the arrows in the first program: most are `->`, but the
one into `collect` is `-~>`. That squiggle marks the language's most
load-bearing distinction. Every place iteration happens produces two
distinct sorts of wire:

- A **value wire** (`->`) carries data — an element, a branch's
  payload, a result. Values are computed on, transformed, wired
  onward.
- A **flow wire** (`~>`) carries the execution context itself —
  *when, and how often, does this happen*. It is used only by flow
  operations (collect, join, commute — you'll meet the last two
  below) and cannot be read as a value.

The `-~>` arrow means a value crossing *together with its flow* —
that's what collect consumes: it needs both the per-element values
and the "once per element" context that tells it when they happen.

Why keep the two sorts separate? Two reasons. It is what lets
combining constructs pass values through as themselves (see
"Barriers, not bottlenecks" below), and it makes misuse impossible to
write down: you cannot apply a function to a flow wire, because a
flow wire is not a value.

## One loop, several results

Now, a first extension of the doubling program. Suppose you want the
doubled *and* the tripled elements. You might expect to need two
loops — but the language lets one open feed any number of collects.
The `|` symbol is a **tap**: a junction on a wire, so the same value
can continue down more than one chain:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Both collects close the same list flow; each element reaches both
chains through the tap. This is called **multi-close**: each collect
is an independent consumer of the same one logical iteration — one
loop with multiple outputs, not multiple loops. (The current compiler
realises each collect as its own self-contained thunk; see
`lazy-compile-design.md`.)

## Using values from outside the loop

A value from outside a flow — a constant, or a value from an
enclosing context — does not need any transport machinery. You just
use it:

```
ten = 10
[[1, 2], [3]] -> open list -> open list -> add(ten) -~> join -~> collect
=> out                                                 -- [11, 12, 13]
```

`add(ten)` sits inside two nested opens, and `ten` comes from
entirely outside them — and it just works. (The rule that makes this
sound is the "prefix rule" of provenance tracking,
`bundle-provenance-design.md`: a value from an enclosing context is
always admissible in a nested one.)

Where you want to name the bringing-in step explicitly, there is a
construct for it: **Incorporate** brings a value into a flow context,
and is a primitive in its own right. One caution: Incorporate must
*not* be used to nest two *sibling* opens (two independently opened
lists) inside one another — that would erase their mutual
independence. When two sibling iterations need combining, the right
node is **Cross** (`product-flows-design.md`), and that is what the
editor's completion inserts.

## Nested lists, and join

The example above also sneaked in something new: two `open list`
stages in a row, and a `-~> join` before the collect. Opening a list
of lists twice gives you a flow *within* a flow — the inner list's
elements, once per outer element. If you want one flat result list,
you have two nested iterations but want to collect only once.

**Join** is the operation for that. It is a binary flow operation
with asymmetric operands, an outer and an inner: it absorbs the inner
flow's firings into the outer flow. Flattening a nested list is
`join(list, list)` — in the example, the two levels of list collapse
to one, so the single collect gathers `[11, 12, 13]`.

### Filtering is a join too

You might expect the language to have a built-in `filter`. It
doesn't — and the reason is that filtering turns out to *be* a join,
once you have case splits. Keeping only the even elements looks like
this:

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens        -- the even elements, as a list
  Odd:  -~> join -~> collect => odds
```

`split parity` sends each element down its case — `Even` or `Odd` —
and each case is itself a flow, one that fires only when its case
happens. Joining the list flow with the `Even` flow keeps exactly the
elements for which `Even` fired, dropping the rest. Filtering is
`join(list, case flow)`; there is no separate filter primitive.

(The implemented code still spells join as a per-collect annotation,
`Joined(flowRef)`, which lost the second operand; that spelling is
superseded at the design level by `lazy-stream-join-design.md`.)

## Case splits and bundles

The `split` in the filtering example deserves its own introduction.
Opening a case-typed value produces a **bundle**: the parent flow's
firings are partitioned into sibling case flows, exactly one of which
fires per firing of the parent. The siblings are mutually exclusive —
a given firing is `Even` or `Odd`, never both.

Here is a split used for computation rather than filtering — replace
the missing values in a list of options:

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                    -- the case close: one value per alt, exhaustive
-~> collect                    -- closes the list flow
=> out                         -- e.g. [2, 0, 10]
```

The first collect is a *case* collect: it supplies one value per case
(doubled payload, or the constant `0`) and produces a single value
whichever case fired. The second closes the surrounding list flow as
usual.

Because sibling case flows are mutually exclusive, they may meet
again only at collecting nodes, never at ordinary combining nodes.
Trying to add `Even`'s value to `Odd`'s value is meaningless (they
never coexist), and the check that catches it is bundle provenance
(`bundle-provenance-design.md`).

You do not need a special construct to use only *some* branches of a
bundle — terminations of a partially-used bundle are handled by the
**partial collect** (`partial-collect-design.md`), of which the
exhaustive case collect above is the fully-covering instance.

Positional filtering falls out of this. Collecting only some
positions of a partitioned list flow yields a shorter list —
differentiation, for instance, computes `current − previous` and
collects only the positions that *have* a previous.

Now, you might wonder whether that first-position case could double
as the seed of a running accumulator — "on the first element, start
from zero; afterwards, add to the previous total." It turns out this
is not part of the model: the initial value of a loop-carried
accumulator belongs outside the flow, not in a first-position branch.
Loop-carried state is its own design — the register
(`iteration-with-state-design.md`, which also records the rejected
`stateful(...)` / `prev(x)` shapes and why they must not return).

## No time travel

Flow ordering and nesting are fixed at construction time. They are
never determined retroactively by an operation added later. This is
the rule that makes the drawn structure trustworthy: what you see
nested *is* nested.

The refined form of the rule governs **readings, not gestures**
(`time-travel-programs-design.md`). You may draw an under-committed
program — sibling opens with no stated order, a termination left
deferred — and the editor completes it by published rules, shown
faint. But every *reading* of a program satisfies no-time-travel
unconditionally.

## Barriers, not bottlenecks

You might wonder: when several wires pass through a combining
construct together — a join of two concurrent flows, say — why
doesn't the language just pack them into a tuple on the way in and
unpack on the way out, the way a fold in a functional language packs
its accumulators? It turns out this packing is exactly what the
design forbids, because it severs the visual thread between each wire
and what it carries — you can no longer follow a value through the
construct, only a bundle-of-everything.

Instead, combining constructs are **barriers with corresponding
inputs and outputs**. Wires pass through as themselves — nothing is
packed into an intermediate structure just to get across.

- **Product side.** Joining two concurrent flows merges the *flow*
  wires; the value wires pass through separately. No tuple is packed
  to cross the join.
- **Sum side.** Racing two async flows keeps a separate output per
  contender; no tagged union is packed to cross the race
  (`async-flow-design.md`, "Racing is a barrier, not a value").

Tuples and tagged unions remain perfectly good as genuine data. The
anti-pattern is constructing one *merely* to pass a structural point
and tearing it apart immediately after.

## Commute: reordering nested flows

With nested flows in the picture, one more operation completes the
core set. Sometimes two layers of nesting are in the wrong order for
what you want to do next — you want to close the inner loop but keep
the outer layer open. **Commute** swaps the two innermost layers:

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option (error) layer still open
perElem -> summarize -~> collect => report
```

Here each element's `mayFail` result opens into an option layer
*inside* the list layer. Commuting swaps them, so the first collect
closes the list while the option (error) layer stays open for a later
collect.

Reordering nested flows is always this explicit operation — flows
never cross implicitly. Commute is defined per flow-kind pair
(`lazy-stream-commute-design.md` maps the taxonomy); effect-handle
flows commute freely by nature (`custom-flows.md`), and over a Cross
product, commute is transpose and is always defined
(`product-flows-design.md`).

## Flow kinds

Everything above used lists and cases, but the open/collect shape is
one shape instantiated by *kind* — the same drawing works for values
that arrive on demand, later in time, or repeatedly over time. Lists
and case/option are implemented; the rest are designed:

| Kind | Opens into | Collect yields | Where |
|---|---|---|---|
| list | each element, in order | a list | implemented; `lazy-compile-design.md` |
| case / option | the matching alt / fires iff Some | exhaustive value / option | implemented |
| stream | each element, on demand (pull) | a stream | `lazy-stream-*.md` |
| async | the value, later | an async value | `async-flow-design.md` |
| incremental (var) | the current value, over time | a var | `incremental-flow-design.md` |

Failability is a uniform dimension across all kinds — a terminator
that can carry a payload — not a per-kind bolt-on
(`async-flow-design.md`).

## Where to go next

- How the notation works in full — taps, marks, lanes, ports:
  `textual-representation-design.md`.
- Validity without types: `types-design.md`,
  `bundle-provenance-design.md`.
- Loop-carried state (running sums, accumulators): 
  `iteration-with-state-design.md` — the biggest open area.
- Ports as first-class, and the program as a node set:
  `first-class-ports-design.md`.
- Editing and history as computation:
  `transformation-levels-design.md`.
- Real-system pressure testing: `tough-use-cases-design.md`.

Rejected and dissolved ideas are recorded in place, in the doc that
owns the topic, each with the reason it must not be pursued again —
in these docs they usually appear in the form "now, you might
wonder why the language doesn't…"
