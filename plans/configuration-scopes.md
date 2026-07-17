# Configuration scopes

Status: design-only exploration. The general open/configure/close shape
below survives independently; for servers specifically it is largely
superseded by the served flow of `tough-use-cases-design.md` (see
"Event-driven extension"). Code samples use the textual syntax of
`textual-representation-design.md`; recursive-construct spellings that
the language has not settled are marked *spelling provisional*.

## The higher-order function problem

Operations like `sort(list, comparator)` and `filter(list, predicate)`
take a function as one of their arguments. Passing a function as a value
is rejected for this language: a function waiting to be called has no
honest visual representation — there is nothing on the wire, only a
promise to run later — and it confuses exactly the users the language is
for. So the parameter that would be a lambda has to become something the
user can *wire*.

## The pattern: open, configure, close

A parameterized operation becomes a scope with a lifecycle. Opening the
scope says "I am doing this operation, but not finishing yet" and
exposes the item it operates on; the middle wires in the configuration —
the computation that would have been the lambda body; closing the scope
completes the operation.

```
list -> open sort => item, ~S            -- spelling provisional
item -> sortKey -~> collect => sorted
```

*Opens a sort over `list`, exposing each `item`; the wired
`item -> sortKey` computes the ordering key; the collect closes the
scope and yields the sorted list. `sortKey` is the comparator, wired
instead of passed.*

Filter and group-by follow the same shape — expose the item, wire the
predicate or the key computation, close:

```
list -> open filter => item, ~F          -- spelling provisional
item -> isReady -~> collect => ready
```

*The wired predicate `item -> isReady` selects which items the close
keeps.*

A configuration scope shares the open/close lifecycle — and the visual
vertical-segment drawing — with custom flows (`custom-flows.md`), but it
is **not an execution context**. It cannot join with itself, cannot
commute, cannot be partitioned or spread. It exists only to configure
its operation. That restriction is what distinguishes it from a real
flow that happens to use the same open/close spelling.

## Event-driven extension

The same open/configure/close shape covers callback-based APIs. An HTTP
server opens a scope that exposes the incoming request; the wired
computation is the handler; the flow threads through once per request.

```
server -> open serve => req, ~R          -- spelling provisional
req -> handle -~> collect => responses
```

*The scope exposes each `req`; the wired `handle` is the request
handler; the collect is what gets sent back.*

For servers specifically, `tough-use-cases-design.md` carries this much
further — the **served flow** ("the collect is the response") plus
concurrent collects with lifecycle outputs. Read that doc as the current
design for request/response. What survives here independently is the
general point: open/configure/close is the language's alternative to
higher-order functions, for sort/filter/group-by as much as for
callbacks.

The general question this pattern answers — an operation whose meaning
is wired in per use — has since grown a broader framing: **late-bound
operations** (a request/response port pair on the diagram boundary,
with the test double as its everyday face; the functions/reuse/facets
row of `open-problems.md`). Configuration scopes are the special case
where the operation is a catalog block like sort or filter; read that
row for the provider-on-a-port direction before extending this pattern
to new ground.

## Deferred: checking a scope's signature

How a configuration scope's *signature* is checked — conditional
signatures, slots — is deliberately deferred in `types-design.md` (open
question 3).
