# Time Travel Programs

> Starting-point document (2026-07-07), in the same spirit as the
> types and bundle-provenance ones: it works out what falls cleanly
> out of the existing design, lays out options where a real choice
> exists, and records the rest as open questions. It takes up
> `visual-language-description/flow_language_design.md`'s Future
> Work #1 ("Pull-Based to Explicit Transformation") in current
> vocabulary. Nothing here is implemented.
>
> Terminology: **uncollect/collect** per the 2026-07-07 correction
> in `lazy-stream-join-design.md` (the code still says Open/Close).

## The rule as it stands

The no time travel rule is the oldest structural law in the design
record (`flow_language_design.md`, Design Principle 2):

> Flow ordering and nesting relationships must be established at
> construction time, not determined retroactively by later closing
> operations.

Its content is best seen in the program it forbids. Two lists,
opened side by side, elements added, then collected one at a time:

    listA -> $ => a, xA
    listB -> $ => b, xB
    a, b -> ADD => s
    s, xA -> @ => perB        -- collect A's flow first
    perB, xB -> @ => out

At the ADD, `xA` and `xB` have no ordering relationship: nothing
yet says whether the A iteration runs inside the B iteration or
the other way around. The placement of the ADD — which loop body
it lives in — is undefined at the point it is drawn. Only the
collects settle it: `perB` (the collect of `xA`) is itself
collected over `xB`, so `perB` must live in `xB`'s context, so
`xA` must be nested within `xB` — A is the inner loop. The meaning
of an upstream node was clarified by a downstream consumer. That
is the time travel, and the rule bans it: under the rule the
program above is ill-formed, and the sanctioned fix is to
incorporate `listA` into B's flow — capture it into `xB` and
uncollect it there (Solution 1, "explicit derivation") — so the
nesting exists at the moment the ADD is drawn.

The rule is right, and this document does not weaken what it
protects. What it protects is the *reading*: one program, one
obvious meaning, determined by structure that is on the diagram,
with every semantic fact owned by a drawable witness. The whole
downstream architecture leans on it — context paths are read off
the construction (`bundle-provenance-design.md`), the compiler
trusts nesting so completely that `deeper(a, b)` doesn't even
check it (the "honoured semantic limitations" list), and the
first check `types-design.md` schedules is exactly the one that
would make the trust explicit.

## The secret: time travel is how you want to author

Here is the observation this document exists to take seriously:
**we actually want a yes time travel rule** — at authoring time —
because it is easier to program that way.

**"The elements of A" behaves like a value.** The inside-out
principle says cases are values you flow through, not scopes you
write inside. Applied to iteration it says: the element wire of
an uncollect is a value you compute with, and computing with it
should not first require settling which loop encloses which. The
forbidden program above is the natural gesture — *here are the
elements of A, here are the elements of B, add them* — and the
rule's sanctioned form makes you decide the loop structure before
you may write the addition. That is structure declared upfront,
before the concrete computation: precisely the shape the
example-first principle rules suspect everywhere else. Time-travel
authoring is example-first applied to flow structure — write the
value computation concretely; let the nesting be identified
afterward, from what you did with the results.

**Deferred error flows.** The stronger version of the same wish:
sometimes you don't want to specify even the commutes. A pipeline
whose per-element step can fail (an option or result flow opened
inside a loop) reads best as: compute with the successful value as
if failure didn't exist, and collect all the dangling error flows
at the very end, outside everything — leaving it to be inferred
that commutes must be inserted to make the error flow outermost.
The vocabulary for the *result* of that inference already exists:
the spec's Commute node plus the "defer the error" idiom
(`visual-language-spec.md`, Commute section) is exactly "commute
the error flow out of the loop, close the loop, handle the error
flow later." The wish is to author the idiom without drawing the
commute.

**Precedents, external.** This is a known and well-liked shape in
language design. Java's unchecked exceptions: the error path is
threaded through every frame without any frame mentioning it.
Koka's effect rows: effects are commutative — every pair of
effects has a canonical commute, so the user never orders them,
and the system's ordering choices are unobservable by
construction. The common structure: an implicit mechanism is safe
when its resolution is *canonical* — fixed by rule, not searched
for — so that the user's ignorance of the details can never change
which program they get.

**Precedents, internal.** The design record has quietly been
moving this way already:

- **Capture is already implicit.** `flow_language_design.md`
  demands explicit CAPTURE to bring a constant into a flow; the
  implemented compiler never asks for one — a Lit is memoised at
  the top level and referenced from any loop body, and an App
  binding is placed at `deeper(args)` and referenced from
  deeper bodies freely. Auto-capture is a canonical elaboration
  the compile has performed silently from the start, and nobody
  has ever missed drawing a CAPTURE node. The most banal
  time-travel-adjacent inference is already in production.
- **Marker × marker commutes for free.** The commute-variant
  taxonomy (`lazy-stream-commute-design.md`) already contains the
  Koka observation natively: where neither flow has runtime
  content, commutativity is free and no node is needed.
- **The naturality quotient.** The Commute node carries no value
  ports, so map-then-commute and commute-then-map are the same
  diagram. This matters below: when a commute is *inserted*, there
  is no spurious freedom about where along the value chain it
  goes — the syntax has already quotiented that choice away.
- **`deeper` is a degenerate elaborator.** The compiler, handed a
  time-travel program today, does not reject it — it silently
  picks a nesting (whichever scope compares deeper) and emits JS
  whose meaning is an accident of the comparison. The honoured
  limitation is, read uncharitably, an unprincipled version of
  exactly the feature this document designs. The design's job is
  to make the pick principled, canonical, and visible.

## The reconciliation: the rule governs readings, not gestures

The philosophy already contains the resolution, in the
transformation-levels round: **many authoring paths, few
readings.** Discoverability (many ways to write) and readability
(one way to read) live at different layers and are not in tension.

So: a **time travel program** is an *authoring-level* artifact —
a program whose flow structure is under-committed: opens without
a drawn nesting relationship, error flows collected outside the
flows they were opened in, combining nodes whose operands' contexts
are not yet comparable. Its **meaning** is its **completion**: the
no-time-travel program obtained by inserting the missing flow
structure. The no time travel rule is not repealed; it is
relocated. It remains the unconditional law of the *reading* —
every completion satisfies it — and stops being a constraint on
the *gesture*.

Three commitments, fixed up front:

1. **Zero runtime.** Time travel programs are compiled solely and
   exclusively by translation to no-time-travel programs. There is
   no runtime representation of "unresolved nesting," no dynamic
   dispatch on flow order, nothing. The compiler consumes the
   completion, exactly as it consumes every other derived view
   ("the compiler is just another consumer of the derived view" —
   `transformation-levels-design.md`).
2. **The completion is derived, never edited.** The time travel
   program is the program of record — it is the *more abstract*
   form, in precisely the philosophy's sense: less committed,
   highest-level description that is true. The completion is a
   read-only lens on it, always available, lazily materialized.
   Note the pleasing alignment: derivation is free and downward,
   and completion *is* the downward direction here — dropping
   from "combine these elements" to "…with A's iteration inside
   B's" is derivation; recovering the uncommitted form by eliding
   canonical structure is the earned upward direction.
3. **The completion is canonical or absent — never searched.**
   Where the rules below do not determine a unique completion (up
   to canonicity), the program has no reading, and the residue is
   surfaced to the user as such. The elaborator never scores,
   backtracks, or prefers; there is no "best" completion, only
   the forced one, the canonical one, or none.

What makes the whole arrangement safe is the lens: **the editor
hints to the user where the missing parts will be inserted** to
make the program a no-time-travel program. The inserted structure
is on screen — ghost nodes at their insertion sites, as
inspectable as authored ones. If the user doesn't like them, they
add their own; explicitly drawn structure always preempts
insertion, and a program that is already complete completes to
itself.

## Completion: what is inserted, and what forces it

### The insertion inventory

The completion inserts flow bookkeeping only. Concretely, two
families:

- **Capture / derivation** — the explicit-derivation fix:
  capturing a value into a flow's context and (for a flow source)
  uncollecting it there. This is what turns "sibling opens" into
  "nested opens." Its value-level shadow is the identity: capture
  changes what context a value is available in, never the value.
- **Commute chains** — Commute nodes lifting a flow across
  enclosing flows toward its canonical position. Value-level
  shadow: none at all — the node has no value ports, and the
  naturality quotient means the insertion carries no placement
  choice along the value chain.

And, by design, two non-families:

- **Never value nodes.** Completion inserts nothing a value wire
  passes through.
- **Never joins, filters, or collects.** Those change firing
  structure — which iterations happen, what gets kept — and firing
  structure is meaning the user must draw. Every termination in
  the completion is one the user authored; completion only makes
  the authored terminations well-placed.

The principled line: **completion inserts only operations whose
value-level shadow is the identity.** (Compare the conversion
argument in `transformation-levels-design.md`: a conversion is
irreducibly level-1 *because* its value shadow is the identity.
The insertions are the same species of pure-structure content —
which is a first hint that completion belongs in the level-1
catalog; see "Where it sits" below.)

One honest wrinkle on "identity shadow": inserting a derivation
assigns a multiplicity — capturing `listA` into `xB` means A's
uncollect now fires per B-element, n×m in total. That is not the
insertion changing a defined meaning; the authored program had no
defined multiplicity, and the constraints (the terminations the
user drew) are what force this one. Completion never *overrides*
an authored meaning; it *supplies* the meaning the authored
structure left open, and only where exactly one supply is
consistent or canonical.

### The constraint model

The unknowns: the authored program's opens form contexts, but the
context *tree* is incomplete — some contexts have no drawn parent
relationship. Completion is the assignment of the missing tree
structure (each assignment realized as a derivation insertion, so
the result is drawable, not annotated), plus the commute chains
that reconcile authored terminations with the tree.

The constraints, in strength order:

1. **Explicit structure is fixed.** Drawn derivations, joins,
   commutes, and the input-derivation chain ("`inner_list` is
   produced by the outer flow") are never revisited. A complete
   program is its own completion, verbatim.
2. **Terminations direct.** A collect converts a flow's firings
   into a value at the flow's parent context; where that value is
   *consumed* therefore pins the parent. In the two-lists example:
   `perB` is collected over `xB`, so `xA`'s parent must be `xB`'s
   context — a directed edge, A inside B. This is the retroactive
   determination the rule forbade, now read deliberately, as an
   authoring signal. (It is exactly the information
   `bundle-provenance-design.md`'s collecting-node demand checks —
   "each branch's value path is a prefix of its cell's path" —
   run in reverse: instead of verifying the path, solve for it.)
3. **Combining nodes connect.** An ordinary multi-input node whose
   operands live in incomparable contexts contributes an
   *undirected* edge: these two contexts must end up on one
   root-to-leaf line, either way around. (This is the
   comparability demand from the same document, relaxed from
   "verify" to "achieve.")
4. **Canonical commutes break remaining ties.** Per flow-kind
   pair, a canonical direction, applied only where 1–3 leave the
   order free. The inaugural entry: **option/error flows commute
   outward** — a dangling failure flow, collected outside the
   flows it was opened within, lifts across each of them via
   inserted Commutes. This is the Koka move: the canonical
   direction is part of the language definition, a fixed table,
   not a per-program judgment.

Solving is partial-order extension over a finite set with no
choice points — the same complexity class as the checker's
propagation, and deliberately so (the no-search commitment of
`types-design.md` applies here with full force).

### The four dispositions

A comparability failure — the thing the checker was going to
report as a time-travel clash — now lands in one of four bins:

1. **Determined.** Constraints 1–3 force a unique tree. The
   two-lists example: the collect order directs, completion
   inserts one derivation, done. No canonicity even needed.
2. **Canonically completed.** The order is genuinely free but a
   canonical rule covers it. The deferred-option example: nothing
   in the terminations says where the error flow sits except
   "outside"; the canonical outward commute supplies the exact
   chain. A useful observation about why the canonical table's
   first entry is safe: option-against-option ordering is
   observationally symmetric — `join(option, option)` fires iff
   both fire, an AND, and a payload-free None carries no
   information about *which* absence occurred — so any consistent
   pick is sound, which is the same argument Koka makes for
   commutative effect rows. The moment payloads appear the
   symmetry breaks; see disposition 3.
3. **Ambiguous.** More than one completion survives 1–4. Canonical
   example: two *sibling* result flows with error payloads (parse
   the same element two independent ways, defer both), values
   combined. Which flow is outer decides which error is reported
   when both fail — observable, and no rule in the table covers
   result-vs-result siblings. The residue is surfaced with its
   witness (the two flows, the combining node) and the candidate
   completions; the program has no reading until the user commits
   one, by drawing structure or accepting a candidate.
4. **Contradictory.** The directed constraints cycle: one
   combining-and-collecting chain forces A inside B, another
   forces B inside A. No completion exists. This is a clash in
   the full `types-design.md` sense — *this cannot mean anything*
   — with a two-anchor witness: the two termination chains whose
   directions collide.

And one thing that is **not** a disposition of time travel at all:
**bundle mixing stays an error.** The two clash flavors that
`bundle-provenance-design.md` was careful to keep distinct now
diverge in fate, which retroactively justifies the care. Two
sibling *cells* of one case split (a Just-value and a
Nothing-value of the same dispatch) have a canonical pairing and
never coexist — no insertion of captures or commutes can create a
joint firing, so there is nothing for completion to complete.
Time travel is elaborable because the missing fact is an
*ordering*; bundle mixing is uncompletable because the missing
fact is an *execution that doesn't exist*.

## Worked examples

### 1. Sibling lists (determined)

Authored:

    listA -> $ => a, xA
    listB -> $ => b, xB
    a, b -> ADD => s
    s, xA -> @ => perB
    perB, xB -> @ => out

Constraint walk: the collect of `xA` outputs `perB` at `xA`'s
parent; `perB` is collected over `xB`, so that parent is `xB`'s
context (rule 2, directed). The ADD's comparability edge (rule 3)
is satisfied by the same assignment. Unique tree: root → `xB` →
`xA`.

Completion (ghost structure marked `+`):

    listB -> $ => b, xB
    + xB -> CAPTURE(listA) => listA_in_B
    + listA_in_B -> $ => a, xA          -- xA now created inside xB
    a, b -> ADD => s
    s, xA -> @ => perB
    perB, xB -> @ => out

Reading: for each b, the list of a+b over all of A; `out` is a
list of lists. Had the user collected in the other order, the
same machinery would have derived B-inside-A — the authored
gesture is symmetric, and the terminations are the commitment.

### 2. Deferred errors (canonically completed)

Authored — parse every element, use the parsed values as if
parsing never failed, deal with failure at the very end:

    items -> $ => item, xL
    item -> PARSE => maybeVal           -- option-typed
    maybeVal -> $ => val, xE            -- option uncollect, inside xL
    val -> PROCESS => r
    r, xL -> @ => results               -- collect the LIST flow…
    …
    results-and-friends, xE -> @ => final   -- …and xE at the end, outside

The collect over `xL` of a value that lives under `xE` — and the
collect of `xE` whose output is consumed at the root — are both
ill-placed as drawn: `xE` is nested inside `xL`, but its
termination sits outside. No termination *direction* is in
question (rule 2 pins everything); what's missing is the lift.
The canonical outward commute (rule 4) supplies it:

    + xL, xE -> COMMUTE => xE', xL'     -- error now outer, loop inner
    r, xL' -> @ => results              -- the loop collects inside xE'
    results-and-friends, xE' -> @ => final

which is letter-for-letter the spec's defer-the-error idiom — the
completion *is* the idiom; the time-travel form is the idiom with
the Commute left unsaid. Semantics: fail-fast — `final` is the
error if any element's parse failed, the processed results
otherwise, compiled by the already-designed commuted-collect
output construction with its short-circuit.

Worth pausing on how this preserves one-obvious-reading rather
than eroding it. Fallible-per-element has exactly three readings
in the vocabulary, and each keeps a distinct authored form:

- **Failure as data** — collect the option flow *in place*
  (output consumed per-element, inside `xL`): a list of options.
- **Failure as filter** — join the option flow into the list flow
  (binary join, option inner): the defined values only.
- **Failure as failure** — defer: collect the error flow outside.
  The time-travel form, canonically completed to fail-fast.

The unmarked, most natural gesture gets the fail-fast meaning;
the other two remain explicit, cheap, and visually distinct. No
reading became unreachable and none became ambiguous.

### 3. Sibling results (ambiguous)

    item -> PARSE_AS_DATE   => maybeDate    -- result, error payload
    item -> PARSE_AS_NUMBER => maybeNum     -- result, error payload
    maybeDate -> $ => d, xD
    maybeNum  -> $ => n, xN
    d, n -> COMBINE => v
    …both xD and xN deferred to the end…

`xD` and `xN` are siblings (rule 3 says they must nest, nothing
says which way), both errors deferred (rule 4's option entry does
not cover result-vs-result). If both parses fail, the outer flow's
error is the one reported — observable, uncanonical. Surfaced:
witness is the COMBINE plus the two opens; the hint shows both
candidate completions and the program has no reading until the
user draws one (or a future canonical rule — say, "first-opened
wins" — is deliberately adopted into the table; see open
questions).

Note the contrast with the same shape over payload-free options:
there disposition 2 applies, because no observation distinguishes
the two completions. The line between "canonical" and "ambiguous"
is exactly the line between unobservable and observable choice —
the commute-variant taxonomy's criterion ("runtime content to
repackage") making a second appearance.

### 4. Crossed terminations (contradictory)

    a, b -> F => s;   s, xA -> @ => sPerB;  sPerB, xB -> @ => out1
    a, b -> G => t;   t, xB -> @ => tPerA;  tPerA, xA -> @ => out2

The first chain forces A inside B; the second forces B inside A.
Cycle; no completion; clash with the two chains as witness. (A
plausible rescue — complete each consumer path independently,
duplicating the opens so `out1` gets A-in-B and `out2` gets
B-in-A — is *expressible*, since multi-collect consumers already
compile to independent thunks, but it doubles the iteration
structure behind the user's back. Whether that rescue should ever
be offered as an explicit hint rather than performed is an open
question below; performing it silently is over the line.)

## Safety: the completion is a lens

Everything the user-facing story needs already exists in the
transformation-levels machinery:

- **Always-on derived view.** The completion is a lens on the
  program of record, materialized lazily. The "editor hints" are
  nothing more than this lens rendered in place: inserted nodes
  drawn as ghosts at their insertion sites. (The graphical side
  is out of scope in this repo; here "hint" means the completion
  is a derived artifact addressed to authored node ids — a list
  of insertions each naming its anchor — which is what an editor
  would render and what a test runner can print.)
- **Accepting a hint is materialize.** A recorded construction
  step; the ghost nodes become ordinary authored structure with
  fresh minted ids; the program now completes to itself. The
  port correspondence is the identity on every authored port —
  insertions add no value ports, so nothing downstream rewires.
- **Rejecting a hint is authoring.** Draw the structure you meant;
  rule 1 (explicit structure is fixed) makes it preempt. There is
  no fight with the elaborator, because the elaborator only ever
  fills holes.

The laws that make this trustworthy, stated as obligations on any
implementation:

1. **Conservativity.** A no-time-travel program is its own
   completion, node for node.
2. **Idempotence.** Completing a completion changes nothing.
3. **Determinism.** Same program, same completion — no search, no
   scoring, no tie-breaking outside the canonical table.
4. **Materialization stability.** Materializing any subset of the
   hints yields a program whose completion is the same program it
   was before, now partly authored. (Accepting hints never
   changes the reading.)

And the one genuine cost, named honestly: **completion is a
whole-diagram inference, so a distant edit can change insertions
elsewhere.** Adding one more collect, or deferring one more error
flow, can flip an inferred nesting three constructs away — the
unchecked-exceptions cost, where a deep `throw` silently changes
every caller. The mitigations are real but partial: the reading
never changes *silently* (the lens re-renders, and hints are
visible structure, so a flipped insertion is a visible diff), and
the step-DAG's id discipline makes "diff the completion across
versions" well-defined and cheap. Whether the editor should
actively flag completion diffs on edit is recorded as an open
question; that it *can* is a direct payoff of programs being
persistent structures.

## Where it sits in the architecture

**The enforcement tiers gain a disposition.** `types-design.md`'s
three tiers — unrepresentable / checked / trusted — implicitly
assumed every detected violation is an error. Time travel was
tier-3 (trusted, awaiting a checker) and headed for tier 2 as the
"smallest first step" check. This design gives the check a third
outcome: neither trusted nor rejected but **completed**. The
inventory reads: unrepresentable things you cannot draw; clashes
that mean nothing (bundle mixing, contradictory orderings);
incompletenesses that mean exactly one thing (completed, with the
lens as receipt); trusted hazards as before.

**The checker comes first, unchanged.** The elaborator consumes
precisely the analysis the checker runs — context paths compared
at combining and collecting nodes (`bundle-provenance-design.md`)
— and adds a solver over the failures. The sequencing in
`types-design.md`'s smallest first step is therefore untouched:
implement flow-context alignment as a check; the completion pass
is that check's second consumer, turning a subset of its findings
from errors into insertions. Nothing about completion weakens the
case for building detection first — detection *is* the front half
of completion.

**Completion is a level-1 catalog entry.** It passes the admission
test verbatim: its content is a statement about level-0 programs
(this incomplete one denotes that complete one), and its value
shadow is the identity. Pattern: a time-travel program with a
defined completion. Expansion: the completion. Port
correspondence: identity on authored ports; inserted nodes are
expansion-internal, with the inserted flows' ports (a
commute-derived error flow, say) as the principal derived ports —
addressable through the lens, materialized on acceptance. Lens
and materialize modes exactly as `transformation-levels-design.md`
defines them. The upward direction exists too: eliding canonical
structure — recognizing that an authored commute chain is exactly
what the canonical table would insert, and collapsing the program
to the more abstract time-travel form — is a `recognize`-family
entry, partial as ever.

**Well-formedness restated.** A program is well-formed iff its
completion is defined (dispositions 1 and 2 everywhere; no
residue, no cycles, no bundle mixing). This is a whole-diagram
quotient check in the established family — alt matching,
no-crossing, Delay productivity — with the one novelty that
passing it produces an artifact (the completion) rather than mere
absence of error.

**Reuse.** A reusable diagram may be a time-travel program — in
fact the placeholder story of `types-design.md` (read-out 3)
predicts it: a diagram authored against schematic sources
accumulates residual *demands*; a diagram authored with
uncommitted flow structure accumulates residual *ordering
constraints*, projected onto its boundary the same way. Its
principal property signature then carries both: "a list of things
with field `price`" and "this input's flow must end up enclosing
that one." Call-site checking composes the caller's orderings
with the callee's residue, interior never re-examined. (Slots
raise the same conditional-signature question they raise for
demands; deferred with it.)

**The compiler.** Zero changes to the runtime and zero to the
emitted JS, by commitment 1. The one repo-level consequence is a
new pass — Expr-level completion — in front of the existing
compile, plus the check it depends on. The current `deeper`
behavior becomes an assertion that the input is complete, which
after the pass it always is.

## What this deliberately is not

- **Not a runtime feature.** No lazy nesting resolution, no
  reified flow order, no new emitted forms. Translation only.
- **Not inference-that-chooses.** The precise ban in the record —
  *"relying on type inference or constraint solving to determine
  behavior"* — is met at its letter's edge and amended in spirit,
  and the amendment should be owned rather than smuggled:
  completion does derive structure the user didn't draw. What
  keeps it on the right side: the derivation is forced-or-
  canonical (never searched, never scored), it is always on
  screen (the lens; nothing behaves differently than shown), and
  it is always overridable (explicit structure preempts). What is
  genuinely given up: "the authored strokes alone show the full
  flow structure." The reading now lives in authored-strokes-
  plus-lens. That trade is this document's thesis, and it is the
  same trade Koka and unchecked exceptions made — bought back, in
  our case, by the lens being *structure*, not prose.
- **Not a repeal of no time travel.** Every reading — every
  completion — satisfies the rule. There is no program whose
  *meaning* involves retroactive determination; there are only
  programs whose *notation* leaves canonical bookkeeping unsaid.
- **Not layout-driven.** flow_language_design's Future Work #6
  (vertical positioning as elaboration input) would make the
  editor's geometry a fifth constraint source. Possible, but it
  belongs to the visual side and is out of scope in this repo;
  the constraint model above neither needs nor mentions position.

## Philosophy check

- **Example first, then generalise.** The whole feature is this
  principle applied to flow structure: the concrete value
  computation is written first; the nesting is identified
  afterward from what was done with the results — read off the
  program, never declared. The completion is the identified
  generalisation, and like the link's, it is derived structure
  the user can inspect.
- **Inside-out / cases as values.** "The elements of A" is a
  value you compute with, not a scope you must first enter.
  Completion is what cashes that out without giving the interior
  of anything a different meaning from its exterior — the
  inserted structure is ordinary visible wiring, no magic names,
  no context-sensitive readings.
- **Foundations before features.** This round is on paper; the
  canonical table starts with one entry; the ambiguity policy
  ships as "refuse" until a real program demands more. Cheaper to
  reject candidate canonical rules here than to retract one the
  ecosystem has leaned on.
- **Building blocks at the programmer's abstraction level.**
  "Add the elements of these two lists," "handle all the errors
  at the end" *are* the programmer's abstractions. One reading
  per program survives because every alternative reading kept
  its own explicit spelling (the three fallible-element forms).
- **No bottlenecks.** Nothing is packed to pass a structural
  point: insertions are captures and commutes, which pass value
  wires through as themselves — commute doesn't even have value
  ports to bottleneck.
- **Abstraction is the source of truth; concreteness is a derived
  view.** The time-travel program is the record and the most
  abstract true description; the completion is a read-only lens,
  compiled from, never edited; accepting hints is materialize;
  eliding canonical structure is recognize. The feature is almost
  a corollary of this principle — which is the strongest sign it
  belongs in the language.

## Smallest first step

The repo can grow the skeleton with no UI and no streams:

1. **The check** (unchanged from `types-design.md` step 1):
   flow-context alignment with a two-anchor error, converting the
   trusted rule into a checked one. Prerequisite: `scopeRef`
   origins, per `bundle-provenance-design.md`'s sharpening.
2. **Directed completion for sibling list opens.** An Expr→Expr
   pass: where the check finds sibling opens, harvest the
   directed constraints from the authored collects (rule 2), and
   where they force a unique nesting, rewrite — re-rooting the
   inner open's source as a value consumed inside the outer flow
   — and report the insertion in test output (ExprPrint the
   completed program alongside the original). Where they don't:
   the check's error, now split into ambiguous vs contradictory.
3. **Canonical option-outward commute** waits for stream flows
   and the Commute implementation; its design is done here and
   in `lazy-stream-commute-design.md`, and step 2's constraint
   harvest is written to extend to it.

Each step is testable in `Main.res` style: build a time-travel
Expr, expect either a specific completion (compare compiled
output against the hand-completed program — they must be
identical, which is commitment 1 as a test) or a specific
residue.

## Open questions

1. **Ambiguity policy.** Recommended above: surface and refuse —
   no reading until the user commits. Alternatives: a
   deterministic tiebreak (first-opened wins) promoted into the
   canonical table, or per-kind defaults. The refuse policy is
   the only one that never chooses a meaning; the others buy
   convenience at the exact spot where the choice is observable.
   Revisit only with a corpus of real ambiguous programs in hand.
2. **The canonical table's contents.** Option/error outward is
   the inaugural entry. Result-out-of-sequenceable presumably
   joins it (fail-fast with payload — same direction, and
   *non-sibling* result flows are ordered by their nesting
   already). Async and incremental kinds need their own rounds;
   the commute-variant taxonomy is the map of which pairs even
   have a commute to canonicalize. The table is language
   definition, versioned with it — a program's reading must not
   change because the table grew (new entries may only give
   readings to previously-residue programs; never alter existing
   completions).
3. **Completion diffs on edit.** Should the editor actively flag
   "this edit changed the completion over there," and at what
   granularity? The id discipline makes the diff cheap; the UX is
   the question. (This is the unchecked-exceptions cost center;
   whatever the answer, it should be designed against example
   programs, not in the abstract.)
4. **Per-consumer completion.** The crossed-terminations rescue —
   duplicating opens so each consumer path gets its own
   consistent nesting, which multi-collect compilation would
   happily support — is expressible but multiplies iteration
   structure. Never silently; the open question is whether it is
   ever *offered*, as an explicit hint with the duplication drawn.
5. **Boundary residue representation.** How a reusable diagram's
   unresolved ordering constraints appear in its principal
   property signature, and how they compose at call sites —
   including whether a caller can discharge a callee's residue
   (probably yes: the caller's structure directs the callee's
   siblings) and whether that recomposes lazily.
6. **Recognize-side ergonomics.** Should the editor offer to
   collapse authored-but-canonical structure ("this commute chain
   is exactly what deferral would insert — elide it?"), and does
   that ever fight with a user who drew it deliberately for
   emphasis? Same tension as eager recognition in
   `transformation-levels-design.md`; likely the same answer.
7. **Naming.** "Time travel program" is a vivid internal name and
   an alarming user-facing one. "Deferred flow structure,"
   "schematic nesting," or simply never naming the state (the
   editor just shows hints) are candidates. Interacts with
   whether the user-facing vocabulary ever says "type"
   (`types-design.md`, open question 1) — the two vocabularies
   should be decided together.
