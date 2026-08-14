# Configuration scopes — wiring in what other languages pass as a lambda

Status: design-only exploration — this chapter teaches a worked
proposal that has not been adopted yet; none of it is implemented.
Read it as "here is the candidate and the case for it." The general
open/configure/close shape taught below survives independently; for
servers specifically it is largely superseded by the served flow of
`tough-use-cases-design.md` (see "Handling events" below). Code
samples use the textual syntax of
`textual-representation-design.md`; spellings for recursive
constructs that the language has not settled are marked *spelling
provisional*. Update (2026-08-04): the open/configure/close shape
lands — a configuration scope is a C-shaped sub-diagram used
flow-wise, and this chapter's anti-higher-order stance is
reasserted there (`with`-binding rejected); see
`late-bound-operations-design.md`, revision notes 2026-08-04.

## Sorting by a key

Suppose you have a list and want it sorted — not by the items
themselves, but by a key you compute from each item. Here is how:

```
list -> open sort => item, ~S            -- spelling provisional
item -> sortKey -~> collect => sorted
```

Read it one line at a time. Opening the sort says "I am sorting this list, but not finishing
yet." It exposes the item the sort operates on: `item` stands for
each element, and `~S` is the sort's flow. The middle of the
lifecycle is the second line — `item -> sortKey` wires in the
computation of the ordering key. The collect closes the scope and
completes the operation, yielding the sorted list.

In a conventional language, that key computation would be the
comparator: a function passed as an argument, `sort(list,
comparator)`. Here, `sortKey` is the comparator, **wired instead of
passed**. A parameterized operation becomes a scope with a
lifecycle — you *open* it, you *configure* it by wiring in the
computation that would have been the lambda body, and you *close*
it to complete the operation. Such a scope is called a
**configuration scope**.

## Filtering, and other shapes like it

Filter follows the same shape — expose the item, wire in the
predicate, close:

```
list -> open filter => item, ~F          -- spelling provisional
item -> isReady -~> collect => ready
```

The wired predicate `item -> isReady` selects which items the close
keeps. Group-by follows the same shape too: expose the item, wire
in the key computation, close. Open, configure, close — one pattern
covering everything that other languages express as an operation
taking a function argument.

## Why not just pass a function?

Now, you might wonder why the language doesn't just let you pass
the comparator or the predicate as a value — write a lambda and
hand it to `sort(list, comparator)` or `filter(list, predicate)`,
the way every language with higher-order functions does. It turns
out this would cause problems: a function waiting to be called has
no honest visual representation. There is nothing on the wire —
only a promise to run later — and it confuses exactly the users the
language is for. So passing a function as a value is rejected for
this language, and the parameter that would be a lambda has to
become something you can *wire*. The open/configure/close pattern
above is that something. (This is a settled rejection — please
don't re-propose function-valued arguments without new evidence.
`functions-design.md` states the same decision from the function
side: functions are not first-class values and not closures.)

## A scope is not a flow

You might also wonder whether a configuration scope is just another
flow kind — after all, it shares the open/close lifecycle, and the
visual vertical-segment drawing, with custom flows
(`custom-flows.md`). It is not. A configuration scope is **not an
execution context**. It cannot join with itself, cannot commute,
cannot be partitioned or spread. It exists only to configure its
operation. That restriction is exactly what distinguishes it from a
real flow that happens to use the same open/close spelling.

## Handling events

The same open/configure/close shape covers callback-based APIs —
the places a conventional language hands a callback function to a
framework. An HTTP server opens a scope that exposes the incoming
request; the wired computation is the handler; the flow threads
through once per request:

```
server -> open serve => req, ~R          -- spelling provisional
req -> handle -~> collect => responses
```

The scope exposes each `req`; the wired `handle` is the request
handler; the collect is what gets sent back.

For servers specifically, this is not the current design — it has
been carried much further, not rejected but superseded. The
**served flow** ("the collect is the response") plus concurrent
collects with lifecycle outputs was first named in
`tough-use-cases-design.md`; the current design lives in
`served-flow-design.md` (the two-ends core adopted 2026-07-23).
Read that doc as the current design for request/response. What
survives here independently is the general point:
open/configure/close is the language's alternative to higher-order
functions, for sort/filter/group-by as much as for callbacks.

## Where this pattern sits now

The general question this pattern answers — an operation whose
meaning is wired in per use — has since grown a broader framing,
now worked as its own round: **late-bound operations**
(`late-bound-operations-design.md`, exploration — a request/response
port pair on the diagram boundary, binding as wiring a provider on,
with the test double as its everyday face). Configuration scopes
are the special case where the operation is a catalog block like
sort or filter and the provider is spliced inline at the one use
site — demand and binding coinciding at one place. Read that round
before extending this pattern to new ground.

## Not decided yet: checking a scope's signature

How a configuration scope's *signature* is checked — conditional
signatures, slots — the language hasn't decided yet; it is
deliberately deferred in `types-design.md` (open question 3).
