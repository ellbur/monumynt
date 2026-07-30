# Failure payloads: lightweight failure and the terminator inventory

Status: **adopted** (design conversation, 2026-07-23, in three
steps of one rolling conversation): the **fail node** (see "What
fail is — the ontology note" for the adoption's stated basis and
the commute-completion ruling that came with it), the **edge
stance with a structural amendment** (bodies total, declared
throws as catalog-row lanes, undeclared throws landing on the
**background super flow** — see that section for the adopted
account and its filed edges), and the **terminator inventory
account** with the clients' cashings (lanes as derived sets of
minting sites, union by propagation, discharge exhaustiveness as
alt matching, re-tagging drawn only where meaning changes, and
the `Cancelled` / subset-merge / divide-link riders as cashed).
None of it is implemented. The open questions below remain open
where marked — tag identity across reuse boundaries now carries
its worked round (the last section below), unadopted. Its scope is the two
flagged residues of the failability design (`async-flow-design.md`,
"Failure as terminator payload"): **"do bodies raise?"** and
**payload-type composition** — plus the payload questions other
rounds filed to be decided jointly with them: the `Cancelled` payload
(`cancellation-design.md`, open question 2), the subset-merge payload
(`race-barrier-design.md`, open question 3), speculation's diagnosis
payload (`speculation-design.md`, open question 4), and the divide
flow's link-crossing payload sets (`divide-flow-design.md`,
"Failability composes with one constraint"). Read the unadopted parts
as "here is a candidate and the case for it." The failable flow kind itself is
settled design this chapter builds on, not reopens: a flow kind's
termination event can carry a payload; consumers propagate it by
default and discharge it at a whole-flow collect, where it becomes
ordinary data.

## A walk that must abort

Here is a sampled loop (`real-loop-survey.md` survey 1, python 10;
transcription B2 of `translation-exercise.md`) — validate every
entry, and abort the whole walk on the first bad one:

    for (lib_name, build_info) in self.libraries:
        sources = build_info.get('sources')
        if sources is None or not isinstance(sources, (list, tuple)):
            raise DistutilsSetupError(...)
        filenames.extend(sources)

With only the designed vocabulary, this transcribes as end-when plus
a discharge plus a re-raise at the readout — seven statements for
Python's four lines, with "stop early and report" spread across
three constructs. The translation exercise flagged that cost as a
concrete demand on the failability residue, and invented a
provisional one-word stage, `-> fail`, that collapses it to:

```
-- spelling provisional (open question 5)
libraries -> open entries => name, info, ~L
info -> get("sources") => srcs
srcs -> split isSourceList of Ok, Bad
  Ok:  -> open list -~> join
  Bad: name -> setupError -> fail
-~> collect => filenames
```

which is the right size. Read it top to bottom: open the entries;
split each on validity; good entries' sources join into the walk and
collect into `filenames`; the first bad entry ends the walk with a
failure terminator carrying `setupError`'s value. `filenames` is a
**failable value** — its consumer receives either the list or the
failure, and a consumer that says nothing about the failure passes
it along, exactly as a promise chain would.

This chapter is the design behind that one word: what `fail` *is*,
why bodies never raise without it, and how the payloads it and its
siblings mint compose across a program — the two questions the
failability round left open, answered together because they turn out
to be one subject.

Two sentences carry the whole chapter; everything after them is
consequences.

> **Failure is drawn, not thrown.** Nothing fails ambiently: a flow
> can end exceptionally only where a drawn construct (or a declared
> edge) says it can. The everyday raise is one node — `fail` — and
> it is the terminator-writing family's third member, consuming the
> same wiring a filter or an end-when consumes.

> **A flow's possible endings are its minting sites, read off the
> wiring.** A terminator lane is not a type and not an exception
> class; it is a *set of places in the program* — the drawn sites
> that can end this flow, grouped by tag. The set derivable at any
> consumer is called the flow's **terminator inventory**, and it is
> computed by the same monotone propagation as every other property
> (`types-design.md`) — so payload composition is propagation, not
> conversion, and every lane at every discharge carries a walkable
> witness back to the sites that mint it.

## The construct: fail, precisely

**Fail is a binary flow operation with asymmetric operands
(subject, stop), the same operand pattern as join and end-when.**
Both operands are flows; `stop` must be option-kind relative to the
subject, in the sense `partial-collect-design.md` defines — it fires
in the subject's own context, at most once per subject firing.
Typically `stop` is one alt of a case split on per-firing data:
exactly the wiring a filter consumes, consumed by a different node.
The three everyday consumers of an alt line up:

| operation | operands | output |
|---|---|---|
| join (filter) | (subject, alt flow) | the firings where the alt fires |
| end-when | (subject, alt flow) | the firings before the alt first fires; ends `Stopped(v)` |
| fail | (subject, alt flow) | the firings before the alt first fires; ends `Fail(e)` |

One wiring, three verbs: *keep those*, *stop there*, *abort there*.

The law is end-when's law with a different tag:

> **The law of the failed flow.** The derived flow fires with each
> firing of the subject, in step with it, up to but not including
> the first subject firing at which `stop` fires; at that firing it
> terminates with a failure terminator whose payload is `stop`'s
> value. If `stop` never fires, the derived flow ends the way the
> subject ends, terminator passed through.

Everything end-when established about this shape transfers verbatim,
because it is the same shape:

- **The walk itself is untouched.** Fail derives a shorter flow
  beside the subject; it never reaches into an existing flow and
  ends it. Consumers wired to the subject see the full walk;
  no-time-travel's no-retroactivity argument is inherited whole
  (`end-when-design.md`, "The walk itself is untouched").
  Operationally nothing runs past the cut anyway, if every collect
  hangs off the derived flow — laziness, as ever.
- **The lane spelling is the derived-flow form with the subject
  implicit.** `Bad: name -> setupError -> fail` names no subject;
  the implicit subject is the flow the stop alt is option-kind
  relative to — well-defined by provenance, and the same
  lane-position/explicit-binary divergence end-when's open
  question 6 already records for the textual round. The explicit
  form is `~L, ~v.Bad ~> fail => ~W`.
- **Stacking composes by end-when's worked rules.** Several
  terminator writers on one subject — two fails and an end-when,
  say — stack, and the stacked results of that round (the
  restriction rule, the regime split, the tie-break theorem) apply
  unchanged, since they were theorems of the law, not of the tag.

Two deliberate asymmetries with end-when, and both are why fail is a
sibling node rather than a tag parameter on end-when:

- **Fail has no inclusive/exclusive bit.** The cut is exclusive,
  always. End-when's bit exists because take-until-sentinel
  sometimes keeps the sentinel in the prefix; a failing firing has
  no value to keep — the Bad alt fired *instead of* the value lane.
  A knob that is meaningful on one node and meaningless on the
  other is two nodes.
- **The everyday readings differ.** An end-when's collect usually
  binds the discharged terminator right there — the stop *is* the
  loop's designed ending, and its payload is often the loop's
  result. A fail's collect usually binds nothing — the failure
  propagates silently outward until some consumer chooses to
  discharge it. The machinery underneath is uniform (next section);
  the *reading* is not, and a construct's reading is what it is
  (`language-design-philosophy.md`, principle 4). A reader who sees
  `fail` knows at a glance: this walk can abort.

One degenerate case rounds out the table from
`async-flow-design.md`. A fail whose context is a once-firing
context — the root, or any per-firing body — derives the **now
column's failable value**: the "result-as-flow" row (zero-or-one,
end+e). `x -> validate -> fail` at the top of a program makes the
program's output failable, with no walk in sight. The table's now
column fills in from the same construct as its later column, which
is what "failability is a uniform dimension" predicted.

## What fail is — the ontology note (2026-07-23)

The design conversation that adopted the node asked what it *is*,
and the answer is one sentence: **fail is the minting half of the
applicative sequence, whose commute half is the propagating
whole-flow close.** Unpacked:

- The record already contains sequence twice without naming it.
  The option commute's runtime move — abandon the rest at the
  first `None`, resolve to `None` — is `[Maybe a] → Maybe [a]`,
  and end-when's cut compiles to that same move aimed at a
  terminator. And the propagating close's all-or-nothing reading
  ("the output is a failable value that fails if the walk
  failed") is `[Either e a] → Either e [a]`, verbatim. So the
  construct decomposes sequence: the close is the commute
  (list∘failable → failable∘list); `fail` is only the minting
  site — the half that gives the walk a failure dimension to
  commute at all, invisible in the applicative form because there
  every body already returns `Either`.
- The packed alternative — building a flow of `Ok(x) | Bad(e)`
  values and feeding it to a drawn commute — is the sum bottleneck
  in sequence's clothes: the per-firing sum exists only to pass
  the construct, when the split had already delivered the alts
  unpacked. The philosophy's sentence extends verbatim: no tuple
  packed just to pass a join, no union packed just to pass a race,
  no Either packed just to pass a sequence.
- **The adoption's stated basis is the drawn distinction between
  short-circuit and accumulate.** In the applicative form,
  abort-at-first vs collect-all-failures is the invisible choice
  between the `Either` and `Validation` instances — one `sequence`
  call, meaning selected off the page. Here they are two visibly
  different drawings: `fail` on the Bad alt (this chapter), vs
  collecting the Bad alt beside the walk (the recover side —
  ordinary multi-close, already free). The conversation was
  honest that beyond this clarity the construct's difference from
  an uncollected error flow remained partly intuitive; the further
  payoffs (stacked-lane union, the discharge's prefix, witnesses)
  ride along rather than carrying the decision.

**The commute-completion ruling** (same conversation, a general
ruling, not specific to failure): *implicitly inferring a commute
is time travel* — it retrospectively determines whether the loop
terminates early — *and the language allows time travel only under
the completion discipline*: the implied commute must be inferred
by published rule **and available for the author to see**, faint,
never merely absent
(`time-travel-programs-design.md`). "Never drawn" everywhere in
the record is to be read as "never authored" — the completed form
exists and is viewable on request. This answers the half of
`effects-design.md`'s open question 1 that asked whether the faint
completed commute is "worth showing at all": showing it is
required — it is what makes the inference legitimate. And the
error commute has a sharper edge than the IO commute: the IO
commute went unauthored because it is mandatory and unique (no
lawful alternative), but the error commute is a genuine *choice* —
short-circuit (commuted) and accumulate (uncommuted) are both
lawful — which by the effects round's own criterion is exactly why
the choice must be visible. `fail` vs the collected Bad alt is
that visibility.

## Do bodies raise? — No. The raise is a node

The failability round posed the question honestly: a JS `async`
function converts thrown exceptions into rejections automatically,
so if compiled bodies inherit that, *every* async close is failable
whether declared or not — JS-honest, but it erases the
infallible/failable distinction the flow-kind table draws. The
alternative — bodies are total, failure enters only at declared
sources — was called "cleaner and less honest." This section takes
the cleaner side and pays the honesty bill at the edge, where the
record already pays every other JS bill.

Now, you might wonder why the language doesn't just take the
JS-honest side — let any body throw, auto-convert throws into
failure terminators, and be done, the way `async` functions are.
It turns out this would cause problems worth naming precisely:

- **The inventory dies.** If anything can throw, every flow's
  possible endings are "anything," so discharge exhaustiveness
  (below) is meaningless, and the reader's question — *can this
  walk abort, and with what?* — has no drawn answer. That is
  exception systems' known illegibility, imported wholesale: the
  surveys' costume for this design is the invisible `raise` that
  every `except:` downstream must defensively over-catch.
- **The infallible/failable distinction is real and load-bearing.**
  The flow-kind table's bare-end rows (list, stream, async) are
  distinct kinds from their failable siblings, and other rounds
  lean on the distinction — speculation's contenders are failable
  *by construction*, the exchange law's response lane is failable
  *per-exchange*. A dimension that is secretly always-on is not a
  dimension.
- **It violates the record's oldest visibility stance.** Everything
  that happens must arrive by a visible wire; an ambient raise is
  control flow with no drawn source — the same objection that
  rejected magic names and dynamic scope.

(This is a settled rejection within this proposal — dead end 1 —
please don't re-propose ambient bodies-raise without new evidence.)

The constructive answer has three parts:

**The program's own raises are drawn.** `fail` is the raise, at one
node's cost per raise *site* — and zero cost per propagation step,
because propagate-by-default means the terminator flows silently
through every consumer that says nothing. Compare Zig, the strongest
field witness (`zig-comparison.md`, finding 7): `try` is
propagate-by-default at one keyword per failable *call*. Our
propagation is cheaper than the field's best (no per-step mark); our
minting is one word, the same price as theirs. The translation
exercise's B2 and C2 both land at source size under exactly this
accounting.

**The JS edge converts by declaration.** A registered function, an
external source, a foreign operation — each enters through a catalog
row, and throwability is part of what the row asserts, exactly as
shape offers are (`types-design.md`, "The JS boundary"): a fetch
block's row declares the failure lanes its rejections map onto; a
parsing source's row declares `Fail(e)` with its payload shape.
Promise rejection at the FFI boundary was already recorded as
mapping into the terminator ("a cell whose promise rejects is a flow
that terminated with payload"); this generalizes that sentence to
the whole edge: **declared throws are lanes; the row is their
minting site.**

**An undeclared throw is an edge breach — and it lands on the
background super flow.** This part was **amended at adoption**
(2026-07-23; the section below is the adopted account). As
proposed, an undeclared throw was a runtime fault outside the
vocabulary entirely. The adopted form keeps the *attribution* —
a JS payload registered as total that throws anyway is still the
catalog's claim being false, the same species of violation as a
discriminator returning an unregistered alt, and the firing
carries which row lied so tooling can say so — but the throw
itself lands on the background super flow rather than outside the
language. What keeps the derived inventory honest is *quarantine*,
not exclusion: the super flow is absent from ordinary flows'
inventories, so exhaustiveness and the infallible/failable
distinction are untouched.

## The background super flow (adopted, 2026-07-23)

The edge stance above was adopted with one structural amendment,
stated by the design conversation as follows. However accurate the
catalog, there is always a background risk of a throw that wasn't
accounted for — the language compiles to a runtime that can fail
in unpredictable ways, and that cannot be eliminated. The best
account of that fact is a distinguished, runtime-owned
**super flow**:

- It **silently commutes out of everything and joins with
  itself** — all background failures, from any depth, are one
  flow, not a per-flow dimension. Ordinary inventories never
  contain it; the reader's question "can this walk abort, and
  with what?" is still answered by the drawn inventory, plus one
  standing background caveat that is the same everywhere and so
  carries no per-program information.
- Its silent commutes are **not rendered, and this is the
  recognized boundary of the commute-completion ruling**, not an
  exception carved by fiat: that ruling governs commutes that are
  *choices* (a lawful alternative existed, so the completion must
  be shown to make the inference legitimate). The super flow's
  commutes have no lawful alternative — a program cannot opt out
  of the runtime's ability to fail — and they are identical
  everywhere, so rendering them would add zero information. The
  ruling's content survives in operative form:
  **availability-as-addressability** — the flow is always nameable
  and collectable, it just isn't drawn for you.
- **It is not handled in generated code by default** — no ambient
  try/catch anywhere, zero compilation cost. **Collecting it is
  drawn, and compiles to a try/catch** around the collected
  region's generated code. This is the escape hatch made
  expressible: the supervisor boundary ("this handler may blow up
  unpredictably; log, serve the error, keep going") becomes a
  drawable program instead of a fault the vocabulary disowns.
  Erlang/OTP supervision is the shipped witness —
  crash-as-data at a drawn boundary — and JS's own
  `uncaughtException`/`unhandledrejection` hooks are the
  runtime-floor costume.
- Its payload is the caught JS value: **one lane, no shape** — the
  dynamic catch-all of dead end 4, which that dead end already
  said "survives as a choice," here given its principled home at
  the language's floor rather than in its substrate.

Note carefully what this does *not* re-open: dead end 1 (ambient
bodies-raise) rejected making *every flow's own inventory*
unbounded. The super flow is the opposite move — one quarantined
lane outside the per-flow accounting, leaving every drawn
inventory finite and every discharge exhaustiveness check intact.

## The discharge barrier (noted 2026-07-23 — a direction, details owed)

A further direction from the adopting conversation, recorded as
direction rather than worked design. It starts from the ontology
note read one step further: if failure is an uncollect of an
**error flow**, then each fail site mints a flow wire — and those
wires are *arrows pointing at the failure points*, case-split-like
wires identifying the ways this program can fail. That cashes the
site-as-label direction (open question 2) with ordinary
constructs — no facets needed.

The observation that makes it a construct: the adopted idiom
`~> discharge => term` followed by `term -> split tag of …` is
**merge-then-split** — lanes packed into one tagged value at a
structural point, torn apart immediately after. Fail-fast makes
the packing look inevitable (only one error can come out), but by
the no-bottlenecks principle the honest form is a **barrier**:
feed the error flow wires in, corresponding case flow wires come
out, plus a completed/success case. Wires pass through as
themselves; no union is packed.

What the conversation worked out on the spot:

- **The bundle is legal by construction.** One walk's error flows
  are mutually exclusive (the walk ends at the first), and each
  lives at the *outer* context already — a walk's ending is one
  event at the level above — so the inputs are outer-context
  at-most-once flows and the output is an honest bundle. The case
  vocabulary applies verbatim: *"handle this point and that point
  together" is a partial collect over cells*, and a **tag
  reconstructs as a drawn identification** (same-meaning cells
  merged) rather than a substrate primitive.
- **The success case needs no value port** — the availability law
  answers it by kind. On many-kinds (list/stream) the prefix is
  total, a value at the outer context, readable inside every cell
  by the prefix rule; the completed cell fires bare with the
  result in reach. On exactly-one kinds the resolved value is born
  at settlement, so the success cell *mints* its payload — exactly
  race's winner cell. (The conversation's first intuition — a
  value wire feeding the barrier as success payload — was the
  packed reading; availability dissolves it.)
- **Propagation is untouched.** Between minting and the barrier
  the terminator still propagates silently through consumers that
  say nothing; the barrier is where handling is *chosen*.

**Interaction flagged:** this contests
`barrier-value-crossing-design.md`'s corner 4. The settled-sum
output there was justified by the value and failure payload having
"no independent upstream wires" — fail-as-uncollect gives every
failure an upstream wire, so the barrier form is a live
alternative, possibly the primary drawing with term-then-split as
its packed lowering (a level-1 recognition candidate). Corner 4
should not be ratified as written without this in the room.

**Refined the same day (the one-closer resolution).** The
crossing round's corner 4 was decided in this direction with a
synthesis governed by a stated principle: *when a loop's result
has one consumer, one construct closes the loop flow.* The
barrier does not stand beside the closing collect — it **is** the
closing collect's discharge half, minting the outcome cells
directly on the closer (no `term` value; the fold an optional
sibling output readable in the cells; exhaustiveness = the cell
set matches the derived inventory). The standalone-barrier
drawing survives via multi-close for genuinely-multiple
consumers, but the everyday gesture is the one closer. See
`barrier-value-crossing-design.md`, corner 4, for the full
resolution.

Open edges owed by the round that works this out: whether the
ending sites' wires feed the closer as authored inputs (the
visible-control-flow lean) or the cells derive from the inventory
with site→cell arrows as viewable derived witnesses (the
commute-completion ruling's pattern); per-site or per-tag cells;
the bare-end cell's exact form; whether the super flow and
`Cancelled` can feed it as inputs where collected; spelling.

Open edges filed at adoption (this round still owes them):

1. **The collect's anchor.** The super flow "commutes out of
   everything," so a collect of it must name a *region* — which
   boundary's background failures are meant. The likely vocabulary
   is the demand/necessity frontier the cancellation round already
   ordered; needs working.
2. **The async face.** A rejection whose payload doesn't match its
   row's declared lanes, and a synchronous throw inside a
   registered body, should presumably both land on the super flow;
   the mapping through the FFI catalog blocks needs stating.
3. **Two runtime-minted lanes.** `Cancelled` (strand delivery) and
   the super flow are now siblings — the runtime's two non-drawn
   minting sites. Whether they share machinery (both deliver over
   frontier structure) is worth one look.
4. **Naming.** "Super flow" is the conversation's placeholder.

The payoff of drawing every entry point is that **failability
becomes readable instead of declared.** A flow is failable iff its
derived inventory is nonempty — a property computed from the drawn
program, displayable faint the way completions are, never annotated.
Zig's function signatures carry `!T` because text needs the
declaration; here the wiring *is* the declaration, and the summary
level that shows it is chosen at display time (`types-design.md`,
read-out 2).

## The terminator inventory

Now the composition question. The failability round's residue asked:
chaining closes over flows with different payload types `E1`, `E2`
"needs either payload unification at joins of failability or an
error-mapping operation on the terminator." Worked through the
demands/offers substrate, the answer is **neither — both horns
presuppose that payload types are artifacts that must be made equal.
They are not artifacts at all; they are derived.**

**Minting sites.** Every way a flow can end exceptionally is a drawn
or declared place:

- a `fail` node (this chapter),
- an end-when (`Stopped`, with its payload),
- an interrupt (`Interrupted(e)`),
- a failable catalog row — an external source, a foreign operation,
  a serving block's response lane,
- the runtime's strand delivery (`Cancelled` — the one non-drawn
  site, minted at the demand frontier; `cancellation-design.md`),
- and the subject's own bare end (`Nil`/`RanOut`), the payload-less
  lane every flow has.

**The inventory is an offer, propagated.** Each minting site offers
its lane — tag plus payload shape — into the derived flow's
terminator. From there the lanes travel exactly as value properties
travel (`types-design.md`): forward along wires, transported through
structural nodes, accumulated by union wherever flows of failability
meet. The three composition sites, each already recorded somewhere
in the record, are:

- **Stacking** — several terminator writers on one subject. The
  derived flow's inventory is the union along the stack: C2's poll
  loop (redrawn below) stacks two fails and an end-when on one
  self-driven flow, and the flow that reaches the discharge carries
  all three lanes.
- **Nesting** — an inner flow's failure joins the outer terminator.
  This is the async round's own observation ("a stream cell that
  rejects is a stream whose termination arrived early — the
  rejection *joins into* the stream's terminator") read as
  transport: the inner walk's lanes flow into the outer flow's
  inventory where the levels meet.
- **Chained closes** — propagation through a consumer that says
  nothing. The output kind keeps the terminator, payload intact, so
  the inventory passes through collects unchanged; at a whole-flow
  close, propagating (rather than discharging) is the all-or-nothing
  reading — the output is a failable value that fails if the walk
  failed. Keeping the prefix is what discharge is for.

Union needs no coercion and no subset-to-superset conversion,
because there is nothing nominal to convert: Zig's error-set algebra
(union at merge points, subset coercion along propagation, inference
by default) is what this substrate *computes* rather than what the
user manipulates. The subset relation is containment of derived
sets; "coercion along propagation" is just a smaller inventory
flowing into a larger context; and "inference by default" is the
only mode there is, with declared sets surviving in exactly one
role — boundary summaries (below).

**Discharge exhaustiveness is alt matching.** At a discharge the
terminator is in hand as a settled tagged value, and the split over
it is an ordinary case split whose required alts are the derived
inventory. The language's oldest check — a case collect covers its
uncollect's alts — applies with no new machinery; Zig's exhaustive
`catch |e| switch` is this check shipped. Selective handling is
drawn, not defaulted: discharge, split, handle the lanes you mean,
and `-> fail` the rest onward (Zig's `else => return err`, as
wiring). A discharge over lanes the inventory cannot produce is
dead-lane noise the checker can flag advisorily; a missing lane is a
clash.

**Every lane carries its witness.** Because the inventory arrives by
propagation, each lane at each discharge knows the path back to its
minting sites — the fail node, the catalog row, the interrupt. "What
can end this walk, and from where?" is a walkable derived view, the
same witness discipline as every other check (`types-design.md`,
"no error without a witness drawable on the diagram"). This is the
piece the field's exception systems structurally lack — a `catch`
site names classes, never places — and it falls out of using
propagation as the substrate instead of declaration.

**The fixpoint is finite, including over recursion.** Propagation
over cycles (a Delay's back-edge, the divide flow's link) is a
monotone fixpoint, and here the domain is the powerset of the
program's minting sites — finitely many, because sites are drawn.
So the inventory converges over any cycle, with no well-foundedness
worry. This matters for the divide flow, and is taken up with the
other clients below: Zig's warning that inferred error sets break on
recursion is a fact about *type-level self-reference* (an
inferred-set function becomes generic, and generic-in-itself has no
fixed point), not about the underlying set equation, which is tame.

**Payload shapes ride the lanes.** Each lane's payload shape is a
property like any other, derived at the minting site from the wire
the payload came in on. Where one tag has several minting sites
whose payload shapes disagree, the lane's shape property is simply
absent (properties are absent-able by design), and downstream
demands on the payload go unmet until the program either narrows
the tag (two tags for two shapes) or handles the payload
shape-agnostically. That gentle pressure toward distinct tags is
the system working, not a failure mode.

## Payload mapping is drawn where meaning changes

What survives of the "error-mapping operation" horn? Exactly the
cases where a program genuinely means to translate a failure — wrap
a low-level lane in a domain-level one, attach which file was being
processed, collapse five lanes to one at an API boundary. That is
not plumbing, it is computation, and it is spelled with pieces this
chapter already has: **discharge, transform, re-fail.**

```
-- spelling provisional
rows -> parse -~> collect => parsed, term      -- inner lanes: BadRow(e), Truncated
term -> split tag of Ok, BadRow, Truncated
  Ok:        parsed
  BadRow:    -> describeRow -> configError -> fail ConfigBad
  Truncated: -> configError -> fail ConfigBad
-~> collect => config                          -- outer lane: ConfigBad
```

The mapping site is a drawn place with the old lanes discharged and
the new lane minted; the outer inventory contains `ConfigBad` and
not `BadRow`, because inventories are derived from what actually
propagates. Nothing else in the program pays anything: where no
mapping is drawn, lanes flow through under union, however many
levels they cross.

Two field idioms locate themselves against this:

- **Cause chains** (wrapping each error in the one below it) are
  hand-built provenance. The *where-from* half is free here — the
  witness is derived, every lane knows its minting path — so
  wrapping-for-traceability is not vocabulary. The *what-data* half
  is real: "which file failed" is a datum, and it is the re-fail
  payload's job, drawn as above. Splitting those two halves is the
  dissolution; the field packs them because it has no derived
  provenance to lean on.
- **The dynamic catch-all** (`catch (e)` over an any-typed error) is
  the degenerate one-lane inventory with no payload shape. It
  remains *expressible* — nothing forbids a program from mapping
  everything onto one tag — but it is a choice made at a drawn
  mapping site, not the substrate.

## The poll loop, redrawn with its lanes

C2 of the translation exercise (retry-until-result with two failure
legs), carried by this chapter's vocabulary end to end:

```
-- spelling provisional throughout
repeat -> open self => ~R                 -- (self-driven opener, its own round)
~io ~> poll(url) in ~R => resp, ~io'      -- effectful read (effects round)
resp -> split httpOk of Ok, HttpErr => h
  HttpErr: -> httpError -> fail HttpFailed
h.Ok -> parse -> get("status")
     -> split statusTag of Pending, Success, Other => st
  Other: -> badStatus -> fail BadStatus
~R, ~st.Success ~> end-when => ~W
~W ~> discharge => term
term -> split tag of Stopped, HttpFailed, BadStatus
  Stopped:    ...                         -- the code; the loop's value
  HttpFailed: ...
  BadStatus:  ...
-~> collect => outcome
```

Three terminator writers stack on one subject; the derived flow's
inventory is the union `{Stopped, HttpFailed, BadStatus}` (no
`RanOut` — a self-driven flow has no bare end, and the checker knows
it); the discharge's split is checked exhaustive against exactly
that set, with each lane's witness pointing at its minting site. The
two fail sites needed distinct tags because the program routes them
differently — the naming pressure doing its job. Note also what the
stacking rules give for free: `HttpErr` and `Other` can never tie
(`Other` is downstream of `Ok`, so the two alts are mutually
exclusive by provenance), so this stack sits in the regime where
order is immaterial.

## The clients, cashed

Five rounds wrote checks on this residue. Each is answered by the
minting-site account, and none needed machinery of its own.

**The `Cancelled` payload — no payload, by construction.** A lane's
payload is data the minting site had in hand on the wire feeding it.
`Cancelled`'s minting site is the runtime's strand delivery — not a
drawn site, and it has no input wire: delivery is the *absence* of a
consumer, and the abandoning party engaged nothing through which a
value could arrive. So the bare-fact lean of the cancellation round
is confirmed with a structural reason rather than a taste judgment:
there is no wire whose value a `Cancelled` payload could carry, and
inventing a side channel to smuggle the abandoner's identity in
would be the one thing the lane discipline exists to prevent.

**The subset-merge payload — the bare fact, confirmed.** A subset
partial collect over a race bundle terminates when settlement went
elsewhere. In hand at that mint: which cell settled — and, at the
same event, the winner's value. The criterion that decides between
them is lane integrity, not availability: each contender's value
belongs to its own lane's thread, and routing the winner's value out
through a losing subset's terminator severs the per-contender
correspondence the barrier form exists to preserve (the sum
bottleneck, in terminator clothes). A consumer that wants to know
which contender won should consume the bundle's cells — that is
what they are. The race round's lean (bare settled-elsewhere fact)
stands, now aligned with `Cancelled` for the same reason.

**Speculation's aggregate diagnosis — ordinary data construction.**
The all-soft-failed aggregate looked like a new composition mode:
payloads combining by *and* (every contender declined) where merges
combine by *or*. Worked through, there is no new mode, because of
where the aggregate is built: the speculation barrier *discharges*
each contender's soft-fail in order to advance to the next, so by
the time all have declined, every payload is already ordinary data
in the barrier's hand. The aggregate is a value the barrier
constructs from data — a list of declined expectations, a merged
set, furthest-position-wins — and *which* aggregate is a
value-level design choice for the parsing domain's catalog, not
payload algebra. The union rule governs what it should: the
barrier's propagated inventory is `{Fail(aggregate)} ∪` the
contenders' hard-fail lanes, which pass through undischarged
(commit upgraded them past the barrier), exactly the
soft-goes-around / hard-goes-through routing the speculation round
drew.

**The divide flow's link — the reason relocates, the leaning
survives.** That round leaned on declared payload sets at the link
crossing "the way Zig's recursive functions demand explicit error
sets," citing Zig's warning that inference is not well-founded over
recursion. The fixpoint result above dissolves the well-foundedness
half: the inventory equation over a link cycle is a monotone
fixpoint on a finite domain and converges like any other cyclic
propagation — Zig's breakage is a fact about its type system's
genericity, and does not transfer. What survives, and is real, is
the *summary* half: a link is a reuse boundary, and a reuse
boundary's inventory belongs in its principal property signature
(`types-design.md`, boundary projection) — computed once, checked
against, optionally *pinned* by declaration when the author wants
the boundary's failure surface stated rather than inherited. Pinned
is checked, both directions: a declared set smaller than the derived
one is a clash with the extra site as witness; larger, an advisory
dead lane. That is Zig's inference-by-default-with-named-escape,
with the escape relocated from a necessity to a documentation
choice.

**The served flow's response lane, and the fault-injecting double —
nothing new.** The exchange pair's response lane is failable
per-exchange, with edge policy on the serving block's catalog row —
which is precisely a failable catalog row in the sense above, its
lanes entering the client's inventory like any source's. The
late-bound round's fault-injecting double (`FailingAllocator`
configured to refuse after N exchanges) mints its failure on the
response lane of an ordinary provider — a drawn site in a test
harness, same machinery. Both rounds deferred here; both are
consumed by the general account with no residue.

**End-when's merged stops, refined.** When several stop conditions
merge into one stop operand, the payload is the firing branch's
value — so the `Stopped` lane's payload shape is derived per the
shape-agreement rule above, and a program whose stop reasons carry
different payloads gets the same gentle pressure toward per-reason
tags. Nothing in end-when's worked rounds moves; the inventory
account just says precisely when its discharge split may be drawn
finer than `Stopped | RanOut`.

## Where this shows up in real code

The demand side is already measured. The bodies-raise gap was the
translation exercise's finding 2: the validate-or-abort walk (B2)
costs seven statements without `fail` and lands at source size with
it, and the poll loop's failure legs (C2) hit the same wall — "more
weight behind resolving that residue," filed twice from one
exercise. Zig is the shipped mirror for both halves of this chapter
(`zig-comparison.md`, finding 7): `try` is
propagate-by-default-at-a-keyword (the witness that the lightweight
form is the right size, and that seven-statement raises are not
viable), and error-set algebra is payload composition shipped —
union at merges, subset coercion, inference by default, explicit
sets as the named escape — here re-derived as property propagation
rather than type algebra. The negative witnesses bracket the design
from both sides: Java's checked exceptions are the declared-set
posture made mandatory at every boundary (the ceremony this
chapter's derived-by-default avoids, and the reason the field
abandoned the idea), while the dynamic `catch (e)` world is the
no-inventory posture (the illegibility dead end 1 names). The
middle the field actually converged on — Rust's `Result` with
per-boundary error enums and a derived catch-all escape, promise
chains' silent propagation with `.catch` at chosen points — is
recognizably the shape drawn here: propagation silent by default,
lanes enumerable where someone chooses to look, translation drawn
at meaning boundaries.

## Against the philosophy

- **Example first, then generalise.** No failure surface is
  declared before the concrete program exists; the inventory is
  read off the drawn walk after the fact, and pinning a boundary's
  set is optional documentation, never an obligation. Checked
  exceptions are the counterexample this ordering avoids.
- **Inside-out — cases are values.** A raise is a node consuming an
  alt, not a control transfer out of a scope; the discharged
  terminator is a value you case-split; there is no `try`-block
  whose interior means differently.
- **Foundations before features.** The chapter adds one node and
  one derived property; everything else — the law, stacking,
  discharge, witnesses, exhaustiveness — is inherited from rounds
  already worked. Five dead ends died on paper below.
- **Building blocks at the programmer's level.** "This walk can
  abort with these failures" is a sentence in the programmer's
  vocabulary; the inventory is that sentence, derived. First-match
  reads as end-when; validation-abort reads as fail; the reader
  never decodes one from the other's machinery.
- **No bottlenecks.** Lanes cross every barrier as themselves:
  no packed error union (the subset-merge and aggregate answers
  are both this principle applied to the terminator channel), no
  cause-chain product hand-packed for traceability the witness
  already provides.
- **Abstraction is the source of truth.** The inventory, the faint
  failability marking, and the witness paths are derived views —
  nothing annotated, nothing stored, nothing to drift.
- **Building blocks must build.** The +1 ladder: an infallible walk
  → *+ abort* (one fail on an existing alt) → *+ a second reason*
  (second fail, distinct tag — union handles the rest) → *+ handle
  one reason here* (discharge + split + re-fail the others) →
  *+ translate at a boundary* (discharge, transform, re-fail) →
  *+ pin a reuse boundary's surface* (declare the set on the
  signature). Every rung is an addition; no rung rewrites the walk
  into a different species. The cliff this removes is the field's:
  code that outgrows silent propagation must today migrate between
  vocabularies (exceptions → result types, or vice versa), and
  both directions are wholesale rewrites.

## Dead ends

Recorded here with the reasons they should not be re-proposed.

1. **Ambient bodies-raise (JS-honest auto-conversion).** You might
   wonder why compiled bodies don't simply inherit JS's
   throw-to-rejection conversion, making every close failable. It
   turns out this kills the inventory (every flow's endings become
   "anything"), erases the infallible/failable kind distinction
   other rounds lean on, and re-imports the invisible control flow
   the record's visibility stance exists to exclude. The edge
   converts *declared* throws; undeclared throws are catalog
   breaches. (Settled within this proposal — please don't
   re-propose without new evidence. The adopted **background super
   flow** is not this dead end: it quarantines the
   unaccounted-throw risk into one runtime-owned lane outside
   every flow's inventory, where this dead end is about making
   every flow's own inventory unbounded.)

2. **Nominal payload types with coercion.** You might wonder
   whether payload sets should be named artifacts that convert
   into one another — Zig's error-set types, imported. It turns
   out the artifacts are unnecessary once the substrate is
   propagation: union is the offer algebra, containment is the
   subset relation, and a conversion node in the vocabulary would
   be plumbing drawn to satisfy bookkeeping — the bottleneck
   pattern on the terminator channel. Translation is drawn only
   where meaning changes. (Settled — don't re-propose without new
   evidence.)

3. **Mandatory declared sets at boundaries (checked exceptions).**
   You might wonder whether every reuse boundary should be made to
   state its failure surface, so callers can rely on it. It turns
   out mandatory declaration is upfront structure of exactly the
   kind principle 1 rules out, and its field history (Java) shows
   the ceremony corrodes into `throws Exception` — the declaration
   goes vacuous precisely because it is demanded everywhere rather
   than chosen where wanted. Derived by default; pinned by choice;
   checked both ways when pinned. (Settled — don't re-propose
   without new evidence.)

4. **One dynamic catch-all payload as the model.** You might wonder
   why payloads aren't just one any-typed error value everywhere —
   it is, after all, what JS itself does. It turns out a
   no-inventory model has no exhaustiveness, no witnesses, and no
   readable failure surface — the `catch (e)` blindness the field
   itself keeps rebuilding enums to escape. It survives as a
   *choice* (map everything to one tag at a drawn site), never the
   substrate. (Settled — don't re-propose without new evidence.)

5. **Cause-chain wrapping as vocabulary.** You might wonder whether
   failures should wrap their causes as they propagate, Go/Rust
   style, so the trail is reconstructible. It turns out the trail
   is *derived* here — every lane carries its minting-site witness
   through propagation — so wrapping-for-provenance hand-packs
   what the checker already knows (a product bottleneck on the
   terminator channel), while genuinely contextual data ("which
   file") is ordinary payload at a drawn re-fail. Split the two
   halves; keep only the second. (Settled — don't re-propose
   without new evidence.)

## Open questions

The language hasn't decided any of these yet; leanings are stated
as leanings.

1. **Adoption.** Done (2026-07-23, the rolling conversation): the
   fail node, the edge stance (amended — the background super
   flow), and the inventory account, beside end-when's adoption
   the same day — the family constraint honored in substance. One
   member's paperwork remains: interrupt is designed in
   `async-flow-design.md` (its verdict vocabulary now fixed by two
   adopted siblings) but rides that round's own adoption, with its
   mechanical content owned by the race round.
2. **Tag identity across reuse boundaries.** Within one diagram,
   tags are names and same-tag sites union into one lane. Two
   independently-authored diagrams both minting `NotFound` — one
   lane or two at a caller that composes them? The leaning is that
   a tag is scoped to its minting diagram unless deliberately
   shared through a signature (the summary artifact is the natural
   place to state identity), but this needs a worked round with
   real composed programs, and it touches the catalog schema
   (`types-design.md`, question 4). Now worked below ("Tag
   identity across reuse boundaries" — the referent rule: a lane's
   identity is a drawn identification, never a string, with three
   homes for deliberate sharing; not adopted).

   **The site-as-label direction (noted 2026-07-23, deliberately
   unworked).** The adopting conversation added a reordering of
   this question's layers worth keeping in view: the minting
   *site* is itself a label — a visual program's shape already
   distinguishes every failure point — so the user need not name
   lanes just to handle them later. Imagine a **failure facet** of
   a subprogram (`facets-design-notes.md`): the view showing just
   its minting points, and a discharge authored by *picking sites
   from that view* — "handle the failure from this point and that
   point," identified by location, no tag authored. Under this
   reading site identity is the primitive the inventory already
   uses (every lane carries a site witness), and a **tag is a
   drawn act of identifying several sites as one meaning** —
   needed exactly for sameness across sites or across a reuse
   boundary, and not before; this question's scoped-by-default
   leaning gets sharper, not weaker. Cautions filed with it: site
   identity is edit-fragile where a tag is not (leans on
   boundary-identity-across-versions,
   `transformation-levels-design.md`); one site in a reused
   subdiagram is many instances, and site-addressed handling must
   say which are meant — exactly where tags-through-signatures
   earn their keep; and the textual form still needs a spelling
   for site references, a problem the visual form doesn't have.
   (The discharge-barrier direction, above, cashes this with
   ordinary constructs — the error flow wires are the site
   references, and no facets are needed.)
3. **The aggregate payload's value design.** Speculation's
   all-declined aggregate is ordinary data construction (above),
   but *which* construction serves parsing well — expectation
   lists, merged expected-sets, furthest-position — is a catalog
   design with domain evidence owed
   (`speculation-design.md`, open question 8's sample).
4. **The advisory tier's exact contents.** Dead-lane splits
   (handling a lane the inventory cannot produce) lean advisory;
   whether a *root-propagated* nonempty inventory (a program whose
   output can fail with lanes nobody discharged) deserves a
   warning or is simply an honest failable output is a taste
   question for the checking round.
5. **Spellings.** `fail`, tag naming (`fail HttpFailed`), the
   discharge binder convention (`=> prefix, term` vs the
   standalone `~> discharge`), and the lane-position vs
   explicit-binary divergence are all owed to the textual round,
   jointly with end-when's open question 6 — one spelling family,
   decided once.
6. **Option convergence, sharpened again.** Under the inventory
   account, an option is the flow whose inventory is exactly
   `{Nil}` and a result-as-flow is `{Nil, Fail(e)}` — the
   convergence the async round's question 6 tracks, now one step
   sharper. Still not merged, for that question's standing reason
   (now/later is a difference in meaning); noted so the next
   round there starts from this formulation.

   **Direction noted (2026-07-23): option-as-flow is the default
   surface for failable operations.** The adopting conversation's
   aside, recorded: the language may not like option *values*
   generally — a failable operation (a lookup, a parse) should
   mint the unpacked reading by default, an **open option flow**
   (fires iff there is a value, `Nil` in its inventory), rather
   than a packed option value that downstream immediately splits
   (packing-to-pass, in miniature). The packed value survives as
   data-on-purpose only, via a drawn collect (options stored in a
   list, an optional field). What this buys: chaining without
   ceremony (each op in the previous hit's context, the miss
   propagating by default — Maybe-monad behavior from the adopted
   machinery, no operator), and Rust's warn-on-discarded-Option
   falls out structurally — a discarded option is a nonempty
   `{Nil}` inventory reaching the root undischarged, which files
   as a datum for question 4's advisory side (`#[must_use]` is
   the field shipping that advisory). The now/later distinction
   is untouched; this is a ruling about the now column's default
   surface only.
7. **Naming.** "Inventory," "lane," "minting site," "tag" are this
   chapter's placeholders; "fail" vs "raise" vs "abort"; deferred
   to the naming sweep (`implementation-strategy.md`).

## What this doesn't address

- **The recover-vs-end boundary** — settled, untouched: errors you
  recover from per element are data (a flow of results); errors
  that end the flow live in the terminator. This chapter designs
  the second side only.
- **Bracket, release, and delivery** — `cancellation-design.md`'s;
  this chapter only confirms its payload lean.
- **Within-firing effect ordering and the segment terminator** —
  `within-firing-effects-design.md`'s; the op-flow segmentation's
  terminators are that round's subject.
- **The batched-effect construct** — its own round, unchanged.
- **Visual depiction** — how faint failability marking, lanes at a
  discharge, and witness walks render is the layout side's, out of
  scope in this repo.
- **Implementation.** Nothing here exists in the compiler; the
  dependency order is unchanged (streams, then async cells /
  failability's runtime, then the terminator-writing family). The
  checker-side inventory is a natural early citizen of workstream
  D once shape propagation exists — it is one more property, and
  its exhaustiveness check is the alt-matching check re-aimed.

## Tag identity across reuse boundaries (open question 2, worked)

Status: worked with leanings, **not adopted** — prepared for its
design conversation. It takes the site-as-label direction recorded
in open question 2 at its word, works the composed programs that
question demanded, and lands its residue on the catalog schema
where the question predicted it would (`types-design.md`,
question 4).

### The composed program that forces the question

Two subprograms, authored independently, each behind a remembered
cut (`function-boundary-design.md`): `fetchUser` looks up a user
record, minting `NotFound` when the id is absent; `fetchOrder`
looks up an order, also minting `NotFound`. A caller composes
them — fetch the user, then the user's latest order. The caller's
derived inventory: one `NotFound` lane, or two?

If tags are global names, one lane — and the caller is broken two
ways. It cannot route the failures apart: "user missing → offer
signup; order missing → show an empty history" is unwritable
without discharging, inspecting the payload for which callee it
was, and re-failing — the payload doing the tag's job, a
bottleneck in terminator clothes. And the union is an accident:
the two authors never agreed that their `NotFound`s mean one
thing; the sameness is a pun on a string, and the day either
author renames for clarity (`UserNotFound`), the caller's program
changes meaning silently. This is variable capture, in failure
clothes.

If tags are scoped, two lanes, and the program above reads right
by default. That is the leaning the question recorded; what this
round adds is the account of *why*, and of what deliberate
sharing is.

### A tag is an identification, and identifications have reach

The site-as-label direction already reordered the layers: site
identity is the primitive (every lane carries its site witness),
and a tag is *a drawn act of identifying several sites as one
meaning*. This round asks what that act's **reach** is. An
identification is drawn by an author, in a drawing; it reaches
exactly as far as the drawing does. Two diagrams' tags are two
acts by two authors, and textual coincidence between their
display names is not an act at all. So:

> **The referent rule (candidate).** A lane's identity is a
> referent — a drawn identification of minting sites — never a
> string. Two sites mint one lane iff they reference one
> identification. A tag's name is presentation; sameness of name
> across independently-authored boundaries identifies nothing.

Within one diagram this changes no behaviour: the adopted
account's "same-tag sites union into one lane" re-reads as "sites
referencing one identification union," which is what an author
means by reusing a tag — one act, several sites. Across a reuse
boundary, the composing caller sees each callee's lanes
*qualified by the boundary they surface from* — fetchUser's
`NotFound`, fetchOrder's `NotFound` — exactly the way it sees
their ports: read off the cut, provenance-carried, not up for
collision. The union rule, the witnesses, exhaustiveness, and the
shape-agreement pressure all operate unchanged; only the notion
of lane *sameness* gained a referent. (This is the codebase's own
port convention one level up: strings below, identities above.)

### When sameness is meant, it is drawn — in one of three homes

**At the caller.** The caller identifies two surfaced lanes as
one meaning ("both `NotFound`s are nothing-to-show"). Local, no
coordination with the callees, and already provided for: the
discharge-barrier direction's "handle this point and that point
together is a partial collect over cells" is this identification,
drawn at the handling site. The cheapest home, right for
caller-private sameness.

**In a shared referent both sides already reference — the
facet.** The late-bound round says the facet supplies the
grouping identity for op pairs; one step further, a facet's ops
declare their failure lanes, and every provider bound to the
facet mints *the facet's* lane, not its own. Two storage
providers' `Timeout`s are one lane by construction, because the
lane belongs to the facet both implement. This is what makes the
policy layer writable at all: retry middleware must discharge
`Timeout` across providers it has never seen, and the facet is
the referent that gives that discharge a target. The test double
inherits the same identity for free — the double's injected
failure (`FailingAllocator` refusing after N exchanges) mints the
facet's lane, so the test exercises the very discharge the
production binding runs.

**In the catalog.** The JS edge's declared throws are catalog-row
lanes. Two blocks wrapping the same library — or two rows both
converting a JS `TimeoutError` — mint one lane only if the schema
has a place for a shared lane referent that rows reference rather
than each minting a private one. This files a concrete content
demand on the catalog schema (`types-design.md`, question 4), the
second after the collect family's identity-witness rows: **rows
carry lane references, not lane strings.**

And the degenerate home nobody had to ask about: the language's
own lanes — `Stopped`, `RanOut`, `Nil`, `Cancelled`, the super
flow's one lane — are shared referents supplied by the constructs
themselves, one per construct, everywhere. That is why it never
occurred to anyone to wonder whether two end-whens' `Stopped`s
are "the same tag": they reference one identification (the
construct's), and where their payloads diverge the ordinary
shape-agreement pressure applies, exactly as within a diagram.

### Instances: the boundary quotient

The direction's second caution: one site in a reused subdiagram
is many instances, and site-addressed handling must say which are
meant. The boundary round answers with machinery it already has —
membership is derived per call, so a lane surfacing at a call's
cut is that call's lane. A caller composing `fetchUser` twice
(against two replicas, say) holds two per-call inventories, and
its discharge of call A's `NotFound` says nothing about call B's.
The quotient is the call, from the same derivation as everything
else about the boundary. Sub-call granularity — this site only
when reached along that deeper path — is expressible in principle
(witnesses are paths), but no program has asked; not proposed.

The link is the unbounded case: one site, one lane, an instance
per level of recursion, unioned by the finite fixpoint. Per-depth
routing does not exist and should not: depth is the measure
discipline's business, and a program that means "first level's
failures are different" says so with a drawn re-tag inside the
level — discharge, transform, re-fail — a change of meaning drawn
where meaning changes, per the adopted account.

### The fragility asymmetry, restated honestly

The direction's first caution was that site identity is
edit-fragile where a tag is not. Under the referent rule the
asymmetry narrows but does not vanish. Both a site and a tag are
identities under the step-DAG's discipline
(`editor-state-management-design.md`): renaming a display name
touches nothing, and moving a node preserves it. What stays
fragile is replacement: deleting a site and drawing a successor
severs the site's identity — a new node — while a tag referenced
by both old and new sites persists across the edit. **A tag is an
identity that outlives any one site, because many sites hold it;
a site is its own only referent.** That is the honest content of
"tags earn their keep": a tag is the author's claim that a
meaning is stable under edits to its minting sites — precisely
the claim a reuse boundary's consumers need, and exactly what the
signature's pinned set states. The leaning's two halves fuse:
scoped by default (an identification reaches as far as its
drawing), shared through signatures (the pinned set is where a
boundary's lane referents join its published surface, checked
both ways as adopted).

### The textual seam

The visual form points; text must spell. The referent rule makes
the spelling problem ordinary rather than novel: text names lanes
the way it names ports — a qualified form at the caller
(`fetchUser.NotFound`, provisional) resolved against the boundary
in scope, an unqualified tag resolving to the innermost drawing
that identifies it — the same strings-below/identities-above
resolution the textual surface already performs for ports and
taps. Owed to the textual round with the rest of open question 5's
family; nothing here decides syntax.

### Dead ends

1. **The global tag namespace.** You might wonder whether tags
   should simply be one namespace, so `NotFound` is `NotFound`
   everywhere and composition is frictionless. It turns out this
   makes renames change composed programs' meaning silently, lets
   unrelated authors capture each other's discharges, and forces
   payload inspection wherever two captured lanes must be routed
   apart. The field's shipped mirror is `errno`: every library's
   `ENOENT` is one lane, and callers famously cannot tell whose it
   was. Note the exception world is *not* the counterexample it
   seems — `catch` clauses match on class identity (a referent,
   scoped by its defining module), not on class *name*; even the
   field's dynamic vocabulary quietly uses referents. (Settled
   within this proposal — don't re-propose without new evidence.)

2. **Structural payload-shape identity.** You might wonder whether
   two lanes whose payload shapes match should be one lane —
   identity by structure, no referent needed. It turns out this is
   binding by structural match, the search the late-bound round
   already rejected, transferred to the terminator channel: shapes
   coincide by accident constantly (`{message: string}`), and a
   coincidence is precisely not an identification. (Settled —
   don't re-propose without new evidence.)

3. **Mandatory re-tagging at every boundary.** You might wonder
   whether each boundary crossing should force a drawn
   translation, so lane identity is always diagram-local and the
   question never arises. It turns out this is dead end 2's
   conversion plumbing resurrected: qualification is derived and
   free, boundary-crossing is not a change of meaning, and forcing
   a re-fail per level is ceremony that corrodes exactly as
   mandatory declarations did. Translation stays drawn where
   meaning changes, and only there. (Settled — don't re-propose
   without new evidence.)

### What this leaves

The adoption conversation; the facet-lane declaration's exact
shape (rides facets' attachment representation,
`facets-design-notes.md` open edge 3, jointly with the catalog
schema demand above); the qualified spelling (textual round);
and whether the discharge-barrier's pick-sites-from-the-view
gesture and the tag act share one edit gesture (editing round).
The instances answer above assumes the boundary round's per-call
membership derivation and adds nothing to it; if the adoption
conversation confirms the referent rule, the summary-artifact
leaning in open question 2 is subsumed rather than contradicted —
the pinned set was always the visible face of lane referents on a
signature.
