# Configuration scopes

*Distilled 2026-07-09 from the retired design narrative
(`visual-flow-language.md`, git history). Design-only.*

## The higher-order function problem

`sort(list, comparator)`, `filter(list, predicate)` — passing
functions as values is rejected for this language
(`rejected-ideas.md` entry 82): a function waiting to be called has
no honest visual representation, and the pattern confuses exactly the
users the language is for.

## The pattern: open, configure, close

A parameterized operation becomes a scope with a lifecycle:

```
list → [open_sort] ──┬──
                     │
                     ╎ sort_context   (item available here)
                     │
[extract sort key] ──┤
                     │
          [close_sort] ──→ sorted_list
```

Opening says "I'm doing this operation, but not finishing yet"; the
middle wires in the configuration (compute the key from the exposed
item); closing completes the operation. Filter and group-by follow
the same shape: expose the item, wire the predicate/key computation,
close.

Configuration scopes share the open/close lifecycle and the vertical
segment drawing with custom flows (`custom-flows.md`), but they are
*not* execution contexts: they cannot join with themselves, cannot
commute, cannot be partitioned or spread. They exist only to
configure the operation.

## Event-driven extension

The same shape covers callback-based APIs: an HTTP server opens a
scope exposing the request; the wired computation is the handler; the
flow threads through per request.

> **Status.** `tough-use-cases-design.md` takes this much further for
> servers specifically: the **served flow** ("the collect is the
> response") plus concurrent collects with lifecycle outputs. Read
> that as the current design for request/response; this doc's
> contribution that survives independently is the general
> open/configure/close alternative to higher-order functions.

> **Status.** How a configuration scope's *signature* is checked
> (conditional signatures, slots) is deliberately deferred in
> `types-design.md` (open question 3).
