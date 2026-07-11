# Learning from other languages: Raku grammars

This is a "learning from other languages" comparison, the second in the
genre begun with `effekt-comparison.md`: read another language's approach
to a problem against how the record approaches the same problem, extract
problems — never mechanisms — and reweight `open-problems.md`. It decides
nothing on its own; demands are handed to the owning docs, and design
stays in the design conversations.

Corpus: the Raku documentation's parsing material, read in full — the
Grammars page (docs.raku.org/language/grammars), the Regexes page, and
the Grammar type page. Deliberately narrower than the Effekt comparison:
Raku is a lot, and the whole language would be too much; this reads one
subsystem — the one whose lesson looked sharpest for us.

## Reading rules for this genre

The three standing cautions, with their directions, plus one specific to
this corpus.

1. **What's out there is already out there.** The output is problems —
   programs that must be writable, demands with evidence — never
   mechanisms. Duplicating Raku grammars would produce Raku grammars,
   which exist.
2. **Different core; bolting on clashes.** Raku's parsing story is
   *textual and trial-driven*: a compact write-only algebra (rescued at
   scale by naming), running on a backtracking engine whose most delicate
   property — what gets re-tried — is controlled by declarator choice and
   code position. Our core is drawn and data-driven: boundaries are
   decided by visible case splits on firing data, and control is
   structure. Where their approach is stronger, the question is what the
   drawn, inside-out form of the same capability is, not how to graft
   theirs.
3. **Maturity polish.** Grammars are Raku's crown jewel — the language
   parses itself with one, and the construct has had twenty years of
   refinement. The docs are its showcase.
4. **This corpus is documentation, not programs** — one step more curated
   than even Effekt's example suite. Nothing here counts as a field
   sighting, and frequencies mean nothing. Mitigation: most demands
   extracted below attach to shapes the random surveys already drew blind
   (breadth items 2 and 6, the protocol framing of use case 5), so the
   field evidence mostly *predates* this comparison; the reading
   contributes structure, not sightings.

## The observation that prompted the reading

Stated up front because it organizes everything and it survived the
reading. **Raku grammars look like a special case of a concept with more
general application: inhomogeneous iteration.** The pattern is everywhere:
loop until you see a start token; then loop accumulating body tokens
until an end token; then loop for the next start token; and so on — one
walk over one input, made of phases with different vocabularies.

The regex notation itself is an inside-out exemplar. `/a/` describes a
loop: scan until you see an `a`. `/ab/` modifies that loop by adding to
it. `/(ab)+/` modifies it again — now it accumulates. Complex
inhomogeneous loops are *bought by adding atoms* to a declarative
specification, never by restructuring. That is a pattern language for
buying complex inhomogeneous loops, and a mainstream demonstration that a
"+1 steps" algebra over loops can work (principle 7 — with a caveat
recorded in §4: at scale the algebra needed names to stay legible).

Nothing about the algebra is text-specific. That is the reading's
question: what does the record need so that this family of programs —
over token flows, byte flows, event flows — is drawable?

## Raku's move

A regex is a declarative specification of a consumption loop over a
string. The algebra:

- *Concatenation* — match this, then that: a phase sequence over one
  cursor.
- *Alternation* — `||` tries branches in written order with backtracking;
  `|` runs all branches and takes the longest match, order-independent,
  ties broken by a published law.
- *Quantification* — `+`, `*`, `** n..m`, and the separator-modified
  `a+ % ','`.
- *Recursion* — rules invoke rules; `<~~>` invokes the whole regex from
  inside itself.

A **grammar** is a class whose methods are named regexes — "grammars
allow you to group regexes, just as classes allow you to group methods" —
with three declarators setting backtracking policy (`token` and `rule`
ratchet: no back-up once matched; `regex` backtracks). Matching builds a
**Match tree** — one node per named rule that matched, i.e. the parse's
segment structure as a value. Meaning is a separate, optional layer: an
**actions class** whose methods share names with the grammar's rules;
after each rule matches, the same-named action runs (children before
parents — post-order) and can attach a semantic value (`make`) that the
parent reads off its sub-matches (`.made`). One grammar can run under
different action classes, or none.

## The material, against the record

### 1. Repetition and separators — split-when confirmed from a fourth direction

**Their approach.** `a+ % ','` — any quantifier takes a separator
modifier; `%%` additionally allows a trailing separator. General counts:
`\w ** 4`, `\w ** 2..5`, and computed counts `\w ** {$start .. $start+2}`.

**Our approach.** This is split-when's ground
(`variable-rate-consumption-design.md`), and the mapping is exact enough
to be a confirmation sweep. `%` is the delimiter reading of the
boundary-destination setting (the separator is neither segment's). `%%` —
trailing delimiter tolerated — is a *fourth* sighting of the destination
choice surfacing as API in the wild, after Ruby's
`slice_when` / `chunk_while` pair and end-when's inclusive / exclusive bit;
more support for that round's open question 1 (one shared enumeration).
The general quantifier is prior art for split-when's open question 4 (the
fixed-length-segment catalog block): Raku found even *computed* counts
everyday enough to admit expressions into the quantifier. Note the count
lives in the recognition spec, not in a verdict — consistent with the
dead-end record's rejection of `advance(k)` verdicts while keeping counts
as data.

One real difference, load-bearing for finding 1: **how the end of a run
is decided.** Split-when's boundary is a drawn condition on per-firing
data. Raku's `\w+` ends where the *next thing* matches — the boundary is
defined by what the following phase accepts, with trial and (in `regex`
declarators) backtracking to negotiate it. The deterministic special case
— boundary decidable at the firing from data and carried state — is what
split-when owns, and Raku's own defaults are evidence it covers most of
practice: `token` and `rule` ratchet, and the docs say plainly "this will
usually do what you want." The trial-negotiated general case is the
speculation row's territory (§3).

### 2. Concatenation — the rung the record is missing

**Their approach.** `/ \w+ '=' \w+ /` — three consumers in sequence over
one cursor, each phase's extent decided by its own vocabulary.
Concatenation is so basic to regexes it isn't even named as a feature.
The bracket case gets its own helper: the tilde in
`'(' ~ ')' <expression>` matches open delimiter, body, close delimiter —
and *commits* to the close: if the body succeeds but the terminator is
missing, a user-definable `FAILGOAL` method fires ("Cannot find ')' near
position 4"). And `.parse` vs `.subparse` is the whole-vs-prefix
distinction as API: `.subparse` consumes a prefix and the rest of the
input is unconsumed, reportable — the *rest* is a first-class output.

**Our approach.** Nothing owns this. The record has *one cut* — end-when's
prefix, skip-while as the kept second segment, take-while / span / break as
"projections of one cut" (`variable-rate-consumption-design.md`,
"Skip-while, and the relationship to end-when") — and *homogeneous
repeated cuts* (split-when). It does not have "eat a prefix shaped like A,
then one shaped like B, then one shaped like C," where each phase has its
own boundary logic, its own per-phase state, its own collect.

The tokenizer worked program got close, with two *nested* split-whens
whose inner boundaries are adjacency conditions ("phase sub-segments
(name, whitespace run, definition run) — split-when again... on
token-kind changes") — evidence that phased walks are expressible when
phases are distinguishable per-firing. But the honest note there was that
past two levels this wants different vocabulary, and open question 3 asked
where that boundary is. This is the start-token / body / end-token pattern
of the prompting observation, and it is the first missing rung of the
grammar ladder. Finding 1 states it as a demand.

Two smaller notes. The tilde construct is the (open, body, close) pattern
promoted to a single gesture *with its failure expectation attached* —
evidence that once you commit past the open delimiter, a missing close is
a diagnosable error, not a non-match; that error / expectation half feeds
§3. And the Digifier example (`[ <.succ> <digit>+ ]+`, where `succ` is an
always-succeed token existing only to trigger a per-group setup action)
shows the recognition algebra lacking a drawn segment-start: they
simulate "a new group began" with a marker token. Our segment starts are
structural — the outer flow's firing — and per-segment state
reinitialises by nesting. Where the phases *are* drawable, we read
better.

### 3. Two alternations and the ratchet — data for the speculation row

**Their approach.** Two distinct choice constructs. `||` tries branches in
written order; first match wins; the engine restores position between
attempts. `|` is longest-token matching: all branches are notionally
raced, the longest *declarative prefix* wins, ties broken by specificity,
then by textual order — a published tie law. Backtracking policy is set by
declarator (`token` / `rule` ratchet, `regex` backtracks) and
per-quantifier (`+:` disables; `:!` re-enables). The docs' own example:
identical pattern text `.+ q` succeeds as `regex` and fails as `token` —
same program, opposite result, chosen by one keyword away from the site.

**Our approach.** The speculation row — ordered alternatives with rollback
— was opened by the Effekt comparison (finding 3 there; breadth item 6,
the backtracking parser, is the field sighting: rdoc's generated PEG
parser saving and conditionally restoring `self.pos`). Raku is the third
independent arrival at the shape, and it contributes structure the row
didn't have:

- **Ordered choice and best-match choice are different constructs in the
  wild.** `||` is the speculation shape (drawn order, try / fail / restore);
  `|` is a *law-with-ties over simultaneous contenders* — structurally the
  race barrier's shape (`race-barrier-design.md`: the barrier's law with
  drawn-order ties), with "longest / most specific" where race has "first
  settled." A future speculation round should not conflate them; Raku
  needing both is evidence the distinction is real.
- **Commitment is the everyday mode.** Ratchet-by-default in the
  declarators users are steered toward means most grammar code never
  backtracks; the speculative engine is the exception, opted into
  locally. Supports the row's recorded leaning that consumed input
  threaded as values (nothing to roll back) can be the substrate, with
  speculation a bounded construct on top — rather than a backtracking
  substrate everywhere.
- **Commitment is where errors come from.** FAILGOAL converts can't-match
  into a *diagnosis* — expected what, where — precisely because the tilde
  committed after the open delimiter. A failed ordered-alternatives
  construct that has committed past a point can say what it expected next;
  one that hasn't can only say "no alternative matched." This adds a
  demand to the speculation round's scope that neither the Effekt
  comparison nor breadth item 6 named: **what does a failed parse say?**
  Error reporting is part of the construct's territory, not a layer on
  top.

The clash side: the `regex`-vs-`token` example is the same genre of
implicitness the Effekt comparison recorded for
rollback-by-allocation-position — the program's most delicate property
readable only in a declarator far from the consequence — though milder
(the declarator is at least written). And LTM's tie law depends on where
the "declarative prefix" ends — embedded closures terminate it, and the
docs warn that an implicit `<.ws>` does too, silently changing which
branch wins. A law whose inputs shift when a spec stops being
"declarative" is a fragility to avoid: our laws should range over drawn
structure only.

### 4. Rules calling rules — recursion, and naming at scale

**Their approach.** Rules invoke rules by name; `<~~>` invokes the
enclosing regex recursively (the balanced-parentheses example: match
nested parens to the *matching* close, "very difficult to duplicate
without recursive regexes"); the result of a parse is the Match tree, one
node per named rule — the recursive segment structure as a value. And the
framing sentence of the whole page: grammars group regexes as classes
group methods — i.e. the flat regex algebra does not survive at scale; it
needed naming, reuse, and (their choice) inheritance.

**Our approach.** Recursive descent over input is recursion over *virtual*
structure — the tree exists only as the walk's call structure until the
parse materialises it. That is the divide flow's territory
(`trees-and-recursion.md`, status note; `tough-use-cases-design.md`, the
mergesort limit), and this is worth recording because the divide flow's
worked examples so far are constructed (mergesort, quadtree owed):
**parsing is the everyday client of recursion-over-virtual-structure.**
The row's eventual round has, in "parse nested delimiters," a candidate
first program with field precedent (breadth item 9 is the data-side
cousin). The naming-at-scale observation lands on the functions row:
whatever drawn form the grammar ladder takes, its units will need to be
nameable and reusable sub-diagrams — the same pressure
`functions-design.md` already carries, arriving from a new direction.

### 5. Actions — meaning arrives later, again

**Their approach.** Recognition and meaning are separate layers: the
grammar parses; an actions class, passed per `.parse` call, attaches
values. The Calculator example runs one grammar under `Calculations`
(compute the arithmetic) — and the docs' own progression subclasses both
grammar and actions independently. Actions are optional: recognition
alone is useful. Values propagate by `make` / `.made` — each match node
carries a semantic value built in post-order, parents reading children's
`.made`.

**Our approach.** Two findings from the Effekt comparison get their second
independent witness, from a differently-shaped language. One grammar
under interchangeable action classes is **late-bound meaning** (Effekt
finding 1: one program, many meanings) — arrived at here not via handlers
but via a parallel class matched by *method-name reflection*. Capability
confirmed; mechanism (magic name matching, meaning attached by
coincidence of spelling) is exactly what the inside-out principle rejects
— the drawn form remains wiring consumers onto ports. And the
`make` / `made` discipline is our segment shape: a value riding each
segment, built when the segment closes, inner segments before outer —
post-order action order is the discharge-at-terminator shape split-when
already draws ("per-segment readout is discharge"; the boundary payload
riding the segment terminator, generalized to a per-segment collected
value). Confirmation that the segment-with-readout vocabulary is the right
skeleton for parse results.

### 6. Proto regexes — the +1 ladder in the wild

**Their approach.** A `proto token calc-op {*}` declares an open
alternation; members are added as `rule calc-op:sym<add> {...}`, each with
a matching action method. The motivating complaint is verbatim our
unbuildable-upon complaint: with a hand-written alternation and a ternary
in the actions, "it becomes even worse the more operations we add." With
protos, `BetterCalculator is Calculator` adds multiplication as one rule
plus one action — nothing edited, everything else inherited.

**Our approach.** This is principle 7 (building blocks must build)
demonstrated by a mainstream construct, and it names a demand the record
holds only implicitly: **extending a case vocabulary without editing the
defining site** — add an alternative to a split, and the consumers that
dispatch on it, from outside. For us the question lands on the
functions / reuse / facets row (it is a reuse mechanism; their
implementation is inheritance, which we would not import) with a tension
to flag for that row's round: an open alternation means no single place
*shows* the complete alternative set, which presses against the
drawn-structure-is-trustworthy bar. Raku accepts the trade for
extensibility; our form would need the completed set to be viewable
somewhere (a facets-flavored question — the derived complete view of an
openly-extended split).

### 7. Sigspace, dynamic variables, error-tolerant recognition — the cross-cutting mechanisms

Three smaller mechanisms, each an answer to a real problem, each with a
drawn form we already have or explicitly reject.

- **Sigspace.** `rule` silently rewrites whitespace in the pattern to
  non-capturing `<.ws>` calls — separator noise handled by invisible
  insertion, with a redefinable magic-named `ws` token. The problem
  (cross-cutting separator noise between every phase) is real; our form is
  the Effekt comparison's finding 6c verbatim — a filter on the token
  flow, upstream, drawn once. The honest caveat: sigspace works *below*
  tokenization (scannerless); our answer presumes a lex-then-parse
  pipeline where the filter has a token flow to act on. That pipeline
  split is itself a stance — probably the right one for drawability, but
  noting it.
- **Dynamic variables in tokens.** `$*USE-WS` set in one token and read as
  a guard in a later token, cascading invisibly "down through all tokens
  defined thereafter" — parse state steering later parse decisions. The
  capability is the running-view / register territory
  (`variable-rate-consumption-design.md`, Part II — the tokenizer's
  `variables` map read back by key mid-walk is exactly this, drawn); the
  mechanism is dynamic scope, already in the clash record via Effekt
  (finding 7a: an invisible wire).
- **Error-tolerant recognition.** The HTTPRequest example threads
  per-component `accept` / `error` method calls so invalid pieces are
  *classified and kept* rather than failing the parse. In our vocabulary
  this needs no mechanism at all: a per-piece case split (valid / invalid
  alts) whose alts flow to independent consumers. We read better; their
  version routes validity through grammar attributes with documented sharp
  edges ("tokens are methods of Match, not of the grammar").

### 8. Not just text — where the generalization points

The prompting observation's payoff. Nothing in the algebra — phases,
alternation, repetition-with-separators, recursion, per-segment values —
mentions characters. The same shapes over other flows:

- **Event grammars.** A drag gesture *is* `down move* up` over a
  pointer-event flow; double-tap, long-press, swipe are all
  phase-sequenced recognitions with data conditions (time windows,
  distance thresholds) at the boundaries. Today's imperative form is the
  hand-built state machine — the same "assembly language of iteration"
  diagnosis the record already applies to cursor bookkeeping.
- **Protocol framing.** Use case 5's read-N-more and the framing worked
  program are the byte-flow instance; the two-phase (header, body)
  register there is a two-phase *grammar* written as a hand-built state
  machine — the variable-rate round itself flagged the granularity worry
  and asked the catalog question.
- **Log / stream sessionisation.** Multiline log grouping (stack traces
  under a header line), gaps-and-islands sessionisation — already cited as
  split-when prior art; the grammar reading adds the *typed* segments
  (header segment, body segment) the flat reading lacks.

Custom flows are adjacent here (`custom-flows.md`): the vertical-segment
lifecycle "generalizes to state machines — each segment a state with its
valid operations," and a grammar over an event flow is a state machine
whose states are phases. The custom-protocol-flows candidate sits on
probation with "one demand; watch for a second" — a recognized-gesture
flow derived from raw events is a *candidate* second demand, but per
reading rule 4 a documentation reading cannot supply the sighting. The
owed UI / browser sample (`open-problems.md`, "Evidence owed") is the
instrument that can: it should carry the question **how much real
event-handling code is grammar-shaped** (phase-sequenced recognition with
state) **versus independent-handler-shaped** (stateless reactions). That
sample was already owed; this reading gives it a second question to
answer.

## Findings

**Finding 1 — inhomogeneous iteration: the phase-sequence rung is
missing.** The grammar algebra has four combinators over segments:
*repeat* (owned: split-when), *sequence* (unowned — eat a prefix shaped
like A, then B, then C, each phase with its own boundary logic, state,
and collect), *alternate* (segments classified into kinds — partially
reachable as case splits on segment content; unexamined as a segmentation
mode), *recurse* (the divide flow's territory, §4). The sequence rung is
the start-token / body / end-token pattern and the `.subparse` shape: a
consumer that takes a prefix and yields the rest. With it comes a fork
that gives split-when's open question 3 its shape: phases whose boundaries
are decidable per-firing from data and carried state are segmentation
vocabulary (the tokenizer program shows two levels already compose);
phases whose boundaries are negotiated by trial — what the next phase
accepts, backtracking on failure — are the speculation row's territory,
not segmentation's. Raku's ratchet-by-default is the outside witness that
the deterministic side covers most practice. Owner: the variable-rate row
(`variable-rate-consumption-design.md` question 3 sharpened, plus the §1
confirmations); the recursion end of the ladder files to the
trees / divide row.

**Finding 2 — recognition vocabulary generalizes beyond text, and the UI
sample can measure it.** Event grammars (gestures), protocol framing, and
sessionisation are the same algebra over event, byte, and record flows
(§8). The hand-built state machine is the imperative encoding of a phase
structure the same way the flag was end-when's terminator and the count
was a boundary. No new row: the demand lands with finding 1's owner, plus
a question handed to the owed UI / browser sample (grammar-shaped vs
handler-shaped event-handling) and a candidate second demand for the
custom-protocol-flows probation — pending a real sighting, which
documentation cannot supply.

**Finding 3 — the speculation row gains structure: two choice constructs,
commitment, and diagnosis.** Raku is the third independent arrival at
ordered-alternatives-with-rollback, and it splits the territory (§3):
ordered try-in-order choice (`||`) is distinct from best-match choice
under a tie law (`|`, LTM — race's structural sibling with "longest" for
"first"); commitment (ratcheting) is the everyday mode, supporting the
row's threaded-values leaning; and commitment is where diagnosis comes
from — FAILGOAL turns can't-match into "expected X near Y." New scope for
that row's round: **a failed parse must say what it expected** — error
reporting belongs to the construct. Clash notes recorded: rollback
semantics chosen by a distant declarator; a tie law whose inputs depend
on where a spec stops being declarative.

**Finding 4 — confirmation sweep for split-when.** The separator
quantifiers `%` / `%%` are the delimiter reading and a fourth wild sighting
of the boundary-destination enumeration; the tilde construct confirms the
bracket pattern as one gesture with its failure expectation attached;
general and computed counts (`** n..m`, `** {...}`) are prior art for the
fixed-length-segment catalog question; `make` / `made` in post-order
confirms the per-segment-value-at-discharge skeleton (§5). No score
movement — the reading strengthens the existing proposal's evidence base.

**Finding 5 — late-bound meaning, second witness; extensible alternation,
new demand.** One grammar under interchangeable (and optional) action
classes independently re-derives the Effekt comparison's central
capability — one program, many meanings — via a different mechanism,
confirming the functions / reuse / facets row's late-bound-operations
demand without moving its score. Proto regexes add a demand that row
didn't have: extend a case vocabulary (an alternation and its dispatching
consumers) without editing the defining site — with the drawn-form tension
flagged: the complete alternative set must remain viewable somewhere (a
facets-flavored derived view).

**Finding 6 — what not to import (the clash record).** (a) *Sigspace* —
meaning inserted invisibly at whitespace, under a magic-named redefinable
token: the drawn form is an upstream filter on a token flow. (b) *Dynamic
variables cascading through rules* — dynamic scope again; an invisible
wire (Effekt 7a); the drawn form is registers and the running view.
(c) *Actions bound by method-name reflection* — meaning attached by
coincidence of spelling; the drawn form is wires onto ports.
(d) *Backtracking policy by declarator* (`regex` vs `token` flipping a
match result at a distance) — the program's most delicate property must be
readable at the site; milder than Effekt's allocation-position rollback
but the same genre. (e) *`$/` and positional / named capture magic* —
implicit result destinations; ours arrive on drawn ports. As with Effekt:
not criticisms of Raku — reasons graft fails, and each capability needs
its own inside-out form.

## What this reading changes in `open-problems.md`

- **Variable-rate consumption row**: remaining list gains the grammar
  ladder — the phase-sequence rung (finding 1) and the segment-kind
  question, with question 3's deterministic / trial fork stated; §1 / §5
  confirmations noted. Scores unchanged (I 3, W 4): the worked round's
  center is unchanged; the remaining list is sharper and longer.
- **Speculation row**: note (finding 3) — two-construct split,
  commitment-as-default supporting the threaded-values leaning, and error
  diagnosis added to the round's scope. Scores unchanged (I 4, W 3); this
  is prior-art structure, not worked design.
- **Recursion / divide flow row**: note (finding 1, §4) — parsing named as
  the everyday client of recursion-over-virtual-structure; nested-delimiter
  parsing as a candidate first program for the divide flow's round. Scores
  unchanged.
- **Functions, reuse, and facets row**: remaining list gains extensible
  alternation with its viewability tension (finding 5); late-bound
  operations note gains its second witness. Scores unchanged.
- **Evidence owed**: the UI / browser sample gains the grammar-shaped vs
  handler-shaped question (finding 2).

## Next rounds of this genre

The Effekt comparison's candidate list stands (a dataflow / reactive
language; an APL-family language; a beginner-first language). This reading
adds a variant worth considering when the grammar ladder is worked:
reading *uses* rather than documentation — real Raku grammars in the
ecosystem, or real parser-combinator code — would supply the field
sightings that reading rule 4 correctly denied this reading, and would
show which rungs of the algebra working programmers actually climb.
