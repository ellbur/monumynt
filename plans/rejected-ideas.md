# Rejected ideas

*Compiled 2026-07-09 from the design record, vetted in design review.*

This document is the graveyard. Every entry is an idea the design record
has rejected, together with the reason it must not be pursued again. The
full arguments live in the docs cited; where the original record has been
condensed or deleted, the entry here is the record.

Two kinds of death are marked:

- **Rejected** — argued against on the merits and turned down.
- **Dissolved** — the idea (or the question it answered) turned out to be
  malformed: a later construct made it unrepresentable, or the choice it
  posed evaporated once the program was stated completely. Dissolutions
  are the record's signature move; re-proposing a dissolved idea usually
  means the underlying confusion has crept back.

The final section lists ideas that *look* rejected but are not — read it
before filing anything else here.

## Iteration state

1. **`stateful(initial, update)` primitive.** Rejected: looks like a
   function call but isn't (the two arguments live at different times);
   `prev` is a scope-contaminating magic name; it is secretly a case
   split smuggled under a call surface; the initial value is positioned
   as if it were inside the flow. Record: `iteration-with-state-design.md`;
   cited in `language-design-philosophy.md` as the canonical inside-out
   violation.

2. **`prev(x)` as a value primitive.** Rejected: its argument is a label
   (node identity), not a value — no other operator works that way; it is
   a flow-level feature written as a value expression; multiple uses are
   one case split written as many. Corollary: option-typed
   access-previous dissolved — under the link design the initial value
   *is* the first previous value, so the "no previous yet" case never
   arises. Record: `iteration-with-state-design.md`.

3. **Delay lambda form `Delay(init, prev => step)`.** Superseded twice,
   independently: the lambda introduces an interior scope (inside-out
   violation) and its parameter goes unused for cross-references. The
   port form and the latent-flow form each resolve it. Corollary:
   `let rec` / construction-time-cycle wiring falls with it — two-phase
   wiring needs no value-level recursion, and the write-half refinement
   keeps the object graph a DAG unconditionally. Record:
   `iteration-with-state-design.md`, `first-class-ports-design.md`.

4. **The stateful-collect as a terminal, output-less node.** Rejected: a
   node that "produces nothing, hangs in the air" has no place in a
   language otherwise modelled on functional behaviour. Recorded
   position (design review, 2026-07-09): this rejection stands, full
   stop — a feedback node must have an output. Passages elsewhere in the
   record that appear to soften it are mistaken readings; what the
   write-half design recovers is a distinct writing *node*, and that node
   is not terminal precisely because it outputs the final value. Record:
   `iteration-with-state-design.md`, `first-class-ports-design.md`
   ("Facing the terminal-node critique").

5. **A generic register with read/write ports.** Rejected: two registers
   look identical regardless of what they hold; meaning lives entirely in
   what's wired to them — "the imperative paradigm wearing visual
   clothing." Record: `iteration-rails-design-notes.md`.

6. **The diagonal-wire iteration rail as drawn, and the
   IterationRail/TapIn/TapOut/`ById` machinery.** Rejected as mechanisms:
   the diagonal introduced a third semantic axis and only trivial `prev`
   rendered cleanly; per-case TapIns encoded a first/subsequent split
   carried state doesn't need; `ById` symbolic references are replaced by
   an honest back-edge plus the productivity check. **Not a full
   burial** (design review, 2026-07-09): the rail *ideas* — the
   one-visible-column constraint, the state-thread depiction, the
   question of how a previous value is named vs how it is carried — may
   need resurrecting to harmonize Delay and state flows, and are kept in
   `iteration-rails-design-notes.md`.

7. **The rail as a general cross-iteration reference mechanism.**
   Rejected: `prev(prev(…))`, `next`, arbitrary peeking, and the
   dependency-analysis / soundness-check / lazy-fallback machinery that
   supported them — "trying to generalize is what made it tangle."
   Deeper lookback is chained Delays; forward reference is not a loop
   variable. Record: `iteration-rails-design-notes.md`.

8. **Elaborating reduce-close into the augment loop at construction.**
   Rejected: collapses the total-vs-running distinction and makes a plain
   `sum` read as a running-sum machine. Intent stays in the Expr;
   lowering happens in compile. Record: `iteration-with-state-design.md`.

9. **The three Delay back-edge escapes** — mutation in the node,
   tie-the-knot host-language laziness, symbolic indirection. Each
   rejected for cause: mutation makes Delay the one node whose meaning
   changes after construction; tie-the-knot re-imports the lambda form's
   machinery with less visibility; symbolic indirection undoes the
   supersession that discarded `ById`. Replaced by the write half as its
   own node. Record: `first-class-ports-design.md`.

10. **Reading a fold's total by collecting and taking the last element.**
    Rejected: materialises the whole history and gets the empty case
    wrong (zero iterations should yield `init`; the collected list is
    empty). The write half's `final` port is the answer. Record:
    `first-class-ports-design.md`.

## Commute, join, and streams

11. **Commute option: linear list flows with explicit `tee`.** Rejected:
    breaks every multi-close diagram until rewritten, and `tee`'s compile
    target is buffer-or-recompute. Retroactively unnecessary — streams
    are multi-consumer via per-consumer cursors, so stoppage never
    truncates siblings. Record: `commute-design-notes.md`.

12. **Commute option: hybrid loop/stream backend chosen invisibly.**
    Rejected: performance depends on nonlocal diagram properties — "I
    added a commute over here and everything got 10× slower" is a bad
    failure mode. Record: `commute-design-notes.md`.

13. **Commute option: break-vote protocol.** Rejected: in the very case
    that motivates it there is still no short-circuit; the vote protocol
    is paid for with nothing to show. Record: `commute-design-notes.md`.

14. **Commute option: commute legal only as sole consumer.** Rejected: a
    context-sensitive linearity rule discovered by hitting the error;
    doesn't generalize; awkward to explain. Cited in `types-design.md` as
    the canonical violation of "no error without a witness drawable on
    the diagram." Record: `commute-design-notes.md`.

15. **Commute option: side-band break truncating sibling consumers.**
    Rejected: invisible truncation — a beginner adds a commute and
    silently changes what their other outputs contain. Record:
    `commute-design-notes.md`.

16. **Commute option: commute as a JS-level `sequence` function.**
    Rejected: hides a first-class structural rearrangement inside a
    black-box App node. Record: `commute-design-notes.md`.

17. **The non-short-circuiting commute stopgap on eager lists
    (Option 6).** Superseded, never implemented: once streams were
    designed there was no reason to add a commute that cannot
    short-circuit. The `Commuted` constructor shape survived; the host
    flow moved from list to stream. Record: `commute-design-notes.md`.

18. **"Swap-and-continue" commute.** Dissolved: the reconciled Commute
    node carries flow wires only — no value ports — so computation under
    the swapped nesting is unrepresentable, not forbidden. The syntax
    quotients by naturality. Corollary: the spec's pre-reconciliation
    Commute signature with per-element value pass-through ports.
    Record: `lazy-stream-commute-design.md`, `visual-language-spec.md`.

19. **The `SFail` tagged-end trick to keep a commuted output lazy.**
    Rejected as a mechanism: it solved a problem the user didn't pose —
    commute is exactly where laziness has to give, because the answer is
    one option about the whole stream. (Failable streams as a flow
    *kind* are a different, live proposal — see `async-flow-design.md`.)
    Record: `lazy-stream-commute-design.md`.

20. **Same-kind commute (list-out-of-list / stream-out-of-stream outer
    product).** Rejected on usefulness: almost nobody who draws nested
    streams wants the outer product, and offering it as "commute" would
    invite accidents. Note the lawful exception: over a **Cross**
    product, commute-as-transpose is defined and is something like a
    same-kind commute — the rejection applies exactly where the nesting
    is not a product. Record: `lazy-stream-commute-design.md`,
    `product-flows-design.md`.

21. **The `Joined(Commuted(…))` wrapper stack.** Rejected: ill-typed —
    after the commute only one layer remains and its per-element value is
    an option, not a stream. (The original redirect — "what you wanted is
    the filter-style sibling" — was itself corrected: flattening the Some
    payloads of a per-group commute keeps only wholly successful groups;
    the filter keeps every firing element.) Record:
    `lazy-stream-commute-design.md`, `lazy-stream-join-design.md`.

22. **The J/F fork (join-crosses-levels vs filter-as-separate-stage).**
    Dissolved: the contested program was *incomplete*, not ambiguous; J
    and F were rival conventions for silently completing it. Two coherent
    algebras with no semantic way to choose was the tell. Only a naming
    residue remains (does `filter_` survive as sugar). Record:
    `lazy-stream-join-design.md` ("Join is a binary flow operation").

23. **Join as a per-close annotation — the `Joined`/`Filtered` wrapper
    stack.** Superseded by binary Join nodes: the wrapper names one flow
    where join takes two operands; losing the arity is what produced the
    J/F fork. The code still implements the wrappers; they now read as
    the compile-level view of an adjacent-pair join with the outer
    operand implied. Record: `lazy-stream-join-design.md`,
    `first-class-ports-design.md`.

24. **Option-as-zero-or-one-cell-stream coercion.** Rejected: reproduces
    the join column but gets the base case wrong (the unjoined close
    would yield a stream of 0/1-streams where the precedents yield option
    data). Partiality-as-firing is the honest formalisation. Record:
    `lazy-stream-join-design.md`.

25. **The Branch node.** Dissolved by first-class ports: a node whose
    entire content is a port name becomes a port reference
    (`cs.alt("Just").value`). Machinery below the programmer's
    vocabulary — plumbing showing through. Record:
    `first-class-ports-design.md`.

26. **The node = single-value-port conflation.** Superseded: the right
    call at Lit/App scale, but it cost three artifacts — Branch, the
    scattered `failwith`s, the wrapper stack — "the same missing concept
    surfacing three ways." Record: `first-class-ports-design.md`.

## Compile strategy

27. **Placeholder-move-on-first-consume.** Rejected: accreted as fixes to
    specific test failures rather than falling out of the design; the
    mutation order became load-bearing and every fix made it more so. The
    cautionary tale motivating the pipeline rebuild. Record:
    `placement-algorithm-notes.md`, `compile-strategy-design.md`.

28. **Stream sharing shapes A and B.** Rejected as answers: A (one fold
    returning an N-record) is max dedup with no GC; B (independent fold
    per output) is max GC with no dedup. Record:
    `lazy-stream-placement-design.md`.

29. **The original dismissal of Shape C** ("map-per-intermediate is a
    real explosion"). Reversed: Shape C is the stream transposition of
    the strategy the eager compile already runs on purpose, and is the
    committed stream baseline. The rejected idea here is the *dismissal*.
    Record: `lazy-stream-placement-design.md` ("The baseline,
    revisited").

30. **The outermost-only consumer-set rule for nested streams.**
    Rejected with a worked counterexample: outermost consumer-sets can
    only collapse inner-flow partitions, never refine them, losing pull
    granularity. Per-level lattices instead. Record:
    `lazy-stream-placement-design.md`.

31. **The benchmarks-only gate for reviving placement.** Rejected as a
    framing: profiles may never demand it, but naive output has a cost
    benchmarks don't measure — generated JS is read, not just run, and
    output that looks pathological is evidence against the language at
    exactly the moment trust is being decided. Revival is gated on
    sequencing (semantics settling), not profiles. Record:
    `lazy-stream-placement-design.md`, `placement-algorithm-notes.md`.

32. **Memo policy 1 (conjoin all reaching contexts; incomparable =
    error).** Rejected as stated: refuses the two-lists program, which
    has a perfectly clear meaning. Its conjunction survives inside the
    completion solver within a chain. Record:
    `compile-strategy-design.md`.

33. **Memo policy 2 as the answer to shared values (compile once per
    context; per-chain completion with duplicated opens).** Superseded by
    the product/Cross resolution on every axis it paid on: no duplicated
    opens, no duplicated work, one faint node. Per-context entries
    survive for placement of genuinely unrelated bindings. Record:
    `compile-strategy-design.md`, `product-flows-design.md`.

34. **A single joint iteration for the two-lists program** (Cartesian
    product in a canonical order via the list monad). Rejected outright:
    the user drew two readings; a canonical joint order is a third
    program nobody drew. The monadic outer product also *linearises*,
    which Cross deliberately does not. Record:
    `compile-strategy-design.md`, `product-flows-design.md`.

35. **One more mutating compiler walk.** Rejected architecturally: the
    shape "analysis interleaved with emission in one depth-first walk
    over mutable context" has failed once already, instructively; the
    coming load is dominated by downstream-dependent facts, exactly what
    broke it. Semantics preserved; the rebuild is a pipeline of pure
    passes. Record: `compile-strategy-design.md`.

36. **Recursive `force` through flatMap chains in the stream runtime.**
    Rejected: a run of K skipped elements costs O(K) stack; a sparse
    filter over a long source overflows. Iterative force plus path
    compression are hard requirements. Record:
    `lazy-stream-placement-design.md`.

37. **Recompute-per-consumer as the default cost policy for products.**
    Demoted: available as a possible future *opt-in* cost policy, never
    the default — once-per-point sharing honours what the sharing
    convention always intended. Record: `product-flows-design.md`,
    `compile-strategy-design.md`.

38. **A root expression as the top-level program structure.** Superseded:
    a Delay write half can be root-unreachable in a complete program, so
    the program of record is a node set with distinguished outputs.
    `compileToBody(root, ~writes)` is tolerated scaffolding only.
    Record: `first-class-ports-design.md`, `compile-strategy-design.md`.

39. **Incorporate as the completion inserted for sibling opens.**
    Rejected *for that case*: incorporating an uncollect source erases
    the mutual-constant fact the author drew — the result reads as
    dependent nesting. Completion inserts a Cross there instead.
    **Incorporate itself is not retired** (design review, 2026-07-09):
    it is a meaningful primitive — bringing a value into a flow context —
    and remains in use; it is only wrong where it loses the siblinghood
    information. Record: `product-flows-design.md`,
    `time-travel-programs-design.md`.

## Types and checking

40. **A conventional type system.** Rejected: secret extra information
    not visible in the program structure; surprises the user with errors
    whose rules were never on screen. Replaced by property propagation
    with drawable witnesses. Record: `types-design.md`.

41. **One complete type per value as the substrate.** Rejected: neither
    standard motivation survives (users only ever see partial summaries;
    modular checking needs only what propagates), and a complete type is
    a product bottleneck at the meta level. Properties are the substrate;
    generalized programs are the *display format*. Record:
    `types-design.md`.

42. **Overloading / multi-instance nodes.** Rejected: propagation would
    need search, "and search is where surprise lives" — errors reported
    far from their cause under rules the user never saw. The solver is
    monotone propagation to a fixpoint, no choice points. (Unification
    was the foil: its blame is an accident of traversal order.) Record:
    `types-design.md`.

43. **The deliberate exclusion list:** type annotations, coercions,
    defaulting, stored type artifacts, nominal typing, entailment
    lattices / user implications / subtyping, checked numeric ranges.
    Most are rejected-until-earned ("each addition to the algebra should
    be earned by a construct that demands it"); ranges are demoted to
    unchecked documentation. Record: `types-design.md`.

44. **"Two case flows never meet" / "siblings never interact" as the
    bundle-mixing rule.** Rejected: both would ban working programs. The
    rule is: siblings interact only at collecting nodes, never at
    ordinary combining nodes. Record: `bundle-provenance-design.md`.

45. **Checker narrowing on partial cell-set overlap.** Rejected: silently
    narrowing `{A,B}` meets `{B,C}` to `{B}` is inference choosing a
    meaning; coarsening and narrowing happen only at explicit nodes.
    (Strengthened later: overlap is ill-formed already at the node.)
    Record: `bundle-provenance-design.md`, `partial-collect-design.md`.

46. **One blurred diagnostic for bundle-mixing and time-travel clashes.**
    Rejected: the two are wrong for different reasons; two flavors keep
    each explanation honest. Record: `bundle-provenance-design.md`.

47. **The "relational" characterization of bundle provenance.**
    Dissolved: the stored property is unary — each wire carries its own
    context path — and the same-bundle relation is computed at
    demand-check time. Relations appear in comparisons and witnesses,
    never in the store. Record: `bundle-provenance-design.md`.

## Partial conditionals and bundles

48. **`PARTIAL_BRANCH` as a construct.** Dissolved: opening only some
    branches is referencing only some of an ordinary open's ports.
    "Partial" is always a fact about terminations (use), never about
    dispatch. Record: `partial-collect-design.md`.

49. **The "multiple possible semantics" menu for closing a partial
    branch.** Dissolved: a program whose flow termination is unstated is
    not a program with several meanings — it is not yet a program. Each
    menu item is a distinct, unambiguous program over the *same* collect
    construct; the differences live in the wiring. Record:
    `partial-collect-design.md`.

50. **The `CAPTURE` transport step for defaults, and a
    capture-from-merged-branch construct.** Dissolved: a `Lit` lives at
    the root context and the prefix rule admits it directly into any
    cell; and "merged branch as parent scope" is the containment theorem
    (`{A} ⊆ {A,B}`) — subset order doing what it always did, no
    construct needed. Record: `partial-collect-design.md`.

51. **The feared-complex partial-merge algebra.** Dissolved: three short
    theorems once the partial collect is stated as a node — the lattice
    of disjoint unions; associativity (bracketing is presentation); the
    exhaustive collect as the covering instance. Record:
    `partial-collect-design.md`.

52. **Binary partial collect as the primitive.** Rejected: join went
    binary because its operands are asymmetric (outer, inner); the
    partial collect has no such asymmetry. The node is k-ary; binary is
    the theorem-backed decomposition. Record: `partial-collect-design.md`.

53. **"Merge" as the partial collect's name.** Rejected: the word is
    spent on stream interleave (`async-flow-design.md`); one word must
    not mean two things. Record: `partial-collect-design.md`.

## Async and incremental

54. **Compiling Exprs straight to eager JS promises.** Rejected: promises
    start running the moment they are constructed, so building the graph
    would *be* running the program. The two-state thunked cell keeps
    JS's memoised resolution and fixes creation. Record:
    `async-flow-design.md`.

55. **Race as an alt-value node** (`race : (async<A>, async<B>) →
    async<alt{First(A)|Second(B)}>`). Rejected: the sum-shaped
    bottleneck — the wire-level identity between the `a` input and the
    `a` case is severed; the correspondence survives only in the tag's
    name and the reader's head. Race is a barrier with per-contender
    outputs. **This is the canonical illustration of a bottleneck** and
    is preserved as such wherever the no-bottlenecks principle is
    taught; the tagged form survives only as internal compilation.
    Corollary dissolved: the `race(a, race(b, c))` composition question —
    the barrier is N-ary from the start. Record: `async-flow-design.md`,
    `language-design-philosophy.md`.

56. **`async<result<X,E>>` as *the* failure story, and failable-async as
    a one-off.** Both horns rejected as posed: the first treats a
    termination as data prematurely and does nothing for streams; the
    second re-derives the same design three times (async rejection,
    interrupted streams, failable parsing are one design). Failability is
    a uniform dimension — terminator payloads on any flow kind.
    (`result`-as-data remains correct for element-level, recoverable
    errors.) Record: `async-flow-design.md`.

57. **A bare "zero-or-one, later" flow kind.** Dissolved: an async that
    "just doesn't fire" is indistinguishable from one that hasn't fired
    *yet*, forever. The zero case is only meaningful if the termination
    is itself an event — the slot is filled by failable async. Record:
    `async-flow-design.md`.

58. **Pure pull-with-versions as the long-term incremental model.**
    Rejected long-term (design review, 2026-07-09): the fan-out pathology
    makes pull's price genuinely wrong — verification cost is paid even
    when nothing changed — and pull additionally makes partial updates
    to lists and similar structures harder to track. It may still serve
    as the convenient first implementation and remains the semantic
    baseline the hybrid must agree with, but the destination is
    push-with-values inside a necessity frontier. Corollary rejected:
    the dirty-bit/Adapton refinement — dirt is value-free, so the whole
    fan-out gets flagged; only push-with-values can evaluate the cutoff
    during propagation. Record: `incremental-flow-design.md`.

59. **An imperative observer register/deregister API.** Rejected: there
    is no call site to put one at. Observation is structural — there is
    no bare read of a var; consumption is boundary constructs whose
    lifecycles the compiler sees. Corollary rejected:
    deregister-at-delivery (necessity would flip once per delivery);
    registrations linger to turn-end. Record:
    `incremental-flow-design.md`.

60. **A "zero-or-one, always" flow kind.** Dissolved: that is
    `var<option<X>>` — the absence is data that varies, not a property of
    the flow; a var must always be readable. Corollary: a filtered close
    over a var is ill-formed. Likewise **a "many, always" kind**
    dissolved: a var deliberately has no history; the history of a var is
    an async stream, and a time-varying collection is `var<list<X>>`.
    Record: `incremental-flow-design.md`.

61. **Commuting `var<option<X>>` → `option<var<X>>`.** Rejected: whether
    the option is Some varies over time, and a var must always be
    readable — the output kind can't hold the answer. A swap with no
    coherent repackaging; not in the commute table. Record:
    `incremental-flow-design.md`.

62. **Instantaneous self-dependence on a var.** Rejected: every cycle
    must cross a register — the same rule as iteration state, applied to
    the event-turn clock. A var updated by events computed from its own
    *previous* value is fine. Record: `incremental-flow-design.md`.

## Real-system use cases

63. **Respond-as-effect** (a callable response capability carried on the
    request). Rejected: needs a linearity obligation the language would
    have to police as a side condition, and nothing in the diagram shows
    that a response happens, or happens once. The served flow — the
    collect *is* the response — makes exactly-once the collect's existing
    exhaustiveness discipline. Record: `tough-use-cases-design.md`.

64. **The sink construct** (a push-shaped dual for writing to the world).
    Struck entirely — the record's one clean subtraction: streams are
    values, so a stream-typed *input port* on an external node suffices;
    the node pulls at its own pace; backpressure is not a feature to
    design. No sink appears in any of the five worked programs. Record:
    `tough-use-cases-design.md`.

65. **Restart/supervision policy built into the pool.** Rejected, as a
    standing veto: supervision is a *reading of lifecycle streams*;
    everything an Erlang supervisor does is user-space above them.
    Building policy in would make it unprogrammable. Record:
    `tough-use-cases-design.md`.

66. **Materialising the virtual split tree** to feed the ADT-derived
    iteration machinery. Rejected: constructing the intermediate tree as
    data purely to give the derivation something to chew on is declaring
    structure upfront — exactly what example-first forbids. Record:
    `tough-use-cases-design.md`.

67. **The cursor-register self-driven stream as the user-level ordered
    merge.** Rejected as the user-facing answer: legal under the
    productivity rule and unreadable — "manual cursor bookkeeping is the
    assembly language of iteration." Retained as the derived *lowering*
    of the decision-driven merge; nobody should read it unless they ask
    to. Record: `tough-use-cases-design.md`.

68. **The concurrency-species *menu*** (`serial | keyed(key) |
    bounded(n) | unbounded` as modes on the collect). Superseded in
    spirit by its own addenda: a menu of words fails the visual test.
    The species are mostly wiring — `keyed` is a group-by open,
    `unbounded` its degenerate case, `serial` no construct at all; only
    `bounded(n)` resists (it is a resource). The *demand* — concurrency
    species must exist and be visible — stands. Record:
    `tough-use-cases-design.md` (addenda).

## Time travel, transformations, editing

69. **Refusing to complete, and accept/reject gestures for inferred
    structure.** Rejected: a program in the heuristic bin has readings;
    declining to pick would make the most natural authoring gestures dead
    ends. Satisfaction is the default state; a user who wants a different
    completion authors the operator they meant. Record:
    `time-travel-programs-design.md`.

70. **Any runtime representation of unresolved nesting, and any
    search/scoring/backtracking elaboration.** Rejected by commitment:
    time-travel programs compile solely by translation to no-time-travel
    programs; solving is partial-order extension with published
    tie-breaks. Record: `time-travel-programs-design.md`.

71. **The per-consumer duplicating rescue for crossed terminations.**
    Resolved by dissolution: the motivating case completes with a single
    inserted Cross. Constraint recorded if ever revived: drawn, never
    silent. Record: `time-travel-programs-design.md`,
    `product-flows-design.md`.

72. **Sibling deferred flows as "the paradigm ambiguity."** Dissolved:
    any actual bringing-together the user draws carries an operand order,
    and the order is the answer — join's operands are (outer, inner).
    Record: `time-travel-programs-design.md`.

73. **The transformation-levels exclusion set:** the fully-materialized
    infinite tower (unacceptable as a representation); a user-facing
    macro surface (operating on programs is intrinsically hard; not
    foreclosed, not waited on); editable derived views (nothing mutates —
    every change builds, so there is no edit to translate back);
    "sum, plus a patch" version descriptions; stored level-1 results
    with staleness; wires into derivation internals (couples the program
    to a lowering strategy); history as a second structure beside the
    program. Record: `transformation-levels-design.md`.

## The textual form

74. **Name-first, head-first syntax as the canonical text**
    (`b = double(a)`). Rejected as canonical — inconsistent reading
    direction (naming and application move backward while statement order
    moves forward) — and **retained in full as accepted input**. Record:
    `textual-representation-design.md`.

75. **Brace-delimited fan-out.** Rejected twice over: braces read as
    scope in a language whose defining move is no interior scope, and the
    closing brace asserts a non-fact (the language expresses end of
    interest by silence). Junction taps and lanes instead. Record:
    `textual-representation-design.md`.

76. **Significant alignment** ("attractive and a known disaster" —
    pronoun binding is ordinal) **and significant indentation**
    (indentation must not become a second authoritative statement of
    nesting; it is a derived view the parser ignores). Record:
    `textual-representation-design.md`.

77. **Raw edge lists, S-expressions, and smart-constructors-as-
    interchange.** Rejected as primary forms: unreadable; tree-biased
    (sharing and cycles need labels anyway, and the tree bias invites
    writing expression trees, which the language specifically is not);
    toolchain-bound. Record: `textual-representation-design.md`.

78. **Assorted textual rejections:** block syntax / lexical scope
    anywhere in the text; implicit return ("last expression is the
    result" — a write half can be root-unreachable); plain `->` silently
    consuming a flow (hence `-~>`); naming a deeper flow layer instead of
    commuting to it (where no commute variant exists, reordering is
    rightly inexpressible); numeric depth annotations (depth is
    structural — "level-2 join" is two join stages); pronouns as stored
    state (reference resolution only). Record:
    `textual-representation-design.md`.

## The early visual-language design (first generation)

These come from the oldest docs, written before the current design
conversations; most are superseded in place.

79. **The basic uncollect/recollect-only list flow as sufficient.**
    Rejected: "a useful dead end" — simple and common, not
    compositionally flexible enough.

80. **Optional-returning `prev()` at the first position.** Rejected:
    puts the condition in the wrong place; first-ness is a property of
    position, not of a value.

81. **The 2D-spread accumulation story and its diagonal-wire pictures.**
    Superseded by the rail redesign and the iteration-state doc (see
    entries 1–7).

82. **Higher-order functions as the parameterization mechanism.**
    Rejected: a function waiting to be called has no visual
    representation and confuses non-experts. Configuration scopes
    instead.

83. **Tuple pack/unpack fork-join.** Rejected: an artificial data
    structure for syntactic reasons — the original product bottleneck.
    The 2D join (flow wires merge, value wires pass through) instead.

84. **Manual recursive step-taking and user structural decomposition.**
    Rejected: primitives with built-in recursion and zippers instead.

85. **User-annotated commutativity.** Rejected: commutativity is inferred
    from definition method; explicit commutes between independent effect
    handles would be no-op clutter.

86. **Auto-lifting every operation onto bundled flows.** Rejected: too
    complex, too ambiguous — only atomic ops (commute, join) auto-lift;
    everything else goes through unbundle/rebundle.

87. **Ghost columns / visible multi-iteration neighborhoods.** Rejected:
    the user only sees one iteration; there is no row of real columns at
    design time.

88. **Vertical positioning as flow-ordering semantics.** Rejected — the
    nesting wouldn't be determined until flows close (a time-travel
    problem) — and now **subsumed**: `time-travel-programs-design.md`
    sanctions under-committed authoring generally, with completion by
    published rules rather than by geometry.

## Layout (out of scope in this repo, recorded for completeness)

89. **Force-directed / L2-norm layout** (local edits must produce local
    layout changes; L1 linear programming when optimization is needed);
    **arbitrary splines** (layout instability); **Graphviz-style semantic
    styling in the layout graph** (the layout layer deliberately carries
    no semantic abstractions); **quadratic spacing programs**. Record:
    `visual-layout-guidelines.md`, `rendering-algorithm.md`,
    `graph-representation.md`.

## Not rejected — do not file these here

Ideas that look rejected but are alive, or retired-but-committed. Listed
so cleanup and future rounds don't over-minimize them.

- **The eager compile-time placement pass and the consumer-set
  lattice.** Retired from the compile path, *deferred, not
  conditional* — committed future optimisation passes ("one conceptual
  loop should compile to one loop"). Record:
  `placement-algorithm-notes.md`, `lazy-stream-placement-design.md`.
- **Delay (port form) vs the latent-flow form.** Both deliberately live,
  side by side. This is the biggest area still to get right (design
  review, 2026-07-09): designs that technically work are easy; the bar
  is a design both easy for beginners to understand and flexible enough
  for complex code. The recorded critiques ("the RTL shadow," "the
  imperative shadow") are pressures on the choice, not rejections.
- **Incorporate.** A meaningful primitive (value into flow context);
  only its use for sibling opens is rejected (entry 39).
- **Failable streams / terminator payloads.** Live design direction
  (only the `SFail`-as-laziness-trick died, entry 19).
- **Shape C.** The committed stream compile baseline (entry 29 records
  the reversal of its dismissal).
- **Pure pull.** Acceptable first implementation and semantic baseline;
  rejected only as the long-term model (entry 58).
- **`filter_` as authoring sugar.** Open ergonomics question — the J/F
  naming residue.
- **Option B (symmetric) product storage.** Live; the lean is "represent
  oriented, read symmetric," with a recorded exit.
- **`loopify`/generalize leaving the level-1 catalog.** A recorded
  *bet* on latent flows, with the tower retained as fallback.
- **Custom protocol flows.** On probation — "watch for a second demand" —
  not rejected.
- **The iteration-rail ideas** kept per entry 6: the one-column
  constraint, the state-thread depiction, carried-vs-named distinction.
