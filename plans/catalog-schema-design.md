# The catalog schema: one registry, graded trust

Status: exploration (worked 2026-08-02) — this chapter is a worked
proposal prepared for a design conversation; **nothing in it is
adopted** and none of it is implemented. Update (2026-08-04): the
failure revision (`failure-payloads-design.md`, revision notes)
re-directs the throw rows — the recorded direction is declared
throws as **case bundles** on the row's output rather than
terminator lanes (terminators carry reason only); the super-flow
attribution for undeclared throws survives unchanged. The lane /
minting-site vocabulary below needs re-founding on alt-reach when
this round runs — the alt-reach account is now worked
(`failure-payloads-design.md`, "The inventory re-founded as
alt-reach", 2026-08-14, unadopted), supplying the form this
round will consume: bundle rows carry alt referents, not
strings. It is the round checking's
question 4 (`types-design.md`, "The catalog schema") has owed since
other rounds began filing schema demands on it: the collect family's
identity rows (adopted content — `collect-family-design.md`), the
failure round's lane-reference demand
(`failure-payloads-design.md`, "Tag identity across reuse
boundaries", unadopted), the Life residue's shape-preservation row
(`product-flows-design.md`, "The Life residue, worked"), the divide
flow's measure catalog (`divide-flow-design.md`, adopted discipline,
schema owed), the cancellation round's cancel translations
(`cancellation-design.md`, question 4), the served flow's three edge
translations (`served-flow-design.md`, "consolidated here for the
catalog schema round"), and the within-firing round's coalescing law
(`within-firing-effects-design.md`). Where a demand comes from
adopted design, this round owes it a schema, not a re-decision;
where it comes from an unadopted round, the dependency is noted in
place.

The one-line result: **the catalog is one registry of
referent-identified entries, not several tables.** An entry carries
facts in open-ended families — ports, laws, lanes, translations,
measures, expansions — each family earned by a construct that
demands it. Every fact is graded by its truth-maker: *definitional*
(its content is a drawing or the language's own construct, checkable
by inspection) or *asserted* (a claim about the foreign side,
trusted, carrying a stated direction of doubt and a displayable
witness). And the asserted facts a given program's validity rests on
are a **derived view — the trust manifest** — so "soundness relative
to the catalog" (`types-design.md`, "The JS boundary") is legible
per program, not just true in general.

(You'll want `types-design.md` first: demands, offers, properties on
wires, witnesses, the no-search rule. This chapter also leans on the
referent rule (`failure-payloads-design.md`, unadopted — the
dependency is called out where it binds), the level-1 catalog
entry's anatomy (`transformation-levels-design.md`), and the
step-DAG identity discipline
(`editor-state-management-design.md`); each is recalled where it is
used. Code samples use the textual syntax of
`textual-representation-design.md`; every spelling is provisional.)

## A program that keeps consulting something off the page

Start with the smallest program whose checking cannot finish by
reading the drawing:

```
xs -> open list => x, ~x
x -~> collect by add => total
```

The checker's job here is settled design: `collect by <op>` demands
`associative` of its operator, and demands `has-identity` too if
`total` is consumed as total rather than option-shaped — the
availability ladder (`collect-family-design.md`, adopted). But
nothing *in the drawing* says `add` is associative with identity 0.
The drawing names an operator; the facts live somewhere else. That
somewhere is the catalog: `add`'s entry carries the row
`associative, has-identity(0)`, and the `0` is not a flag but the
identity **value**, the witness the empty collect will yield,
displayable at the collect node.

Now swap the operator for one the user drew:

```
x -~> collect by mergeCounts => totals
```

`mergeCounts` is a diagram — two ins, one out — and its
associativity is a theorem the checker is forbidden to attempt (no
search). The adopted answer: the user attaches an **algebra facet**
declaring "associative, identity `emptyCounts`," and the facet mints
the row. Same row shape, different author, and the claim's truth is
trusted with its direction of doubt stated — a false associativity
claim makes reassociation wrong; a false identity makes empty
collects wrong (`collect-family-design.md`, "How identities
attach").

Now add a line whose *whole meaning* is off the page:

```
path -> readLines => line, ~line
```

`readLines` is foreign — a JS block. What does it offer
(string-shaped elements)? What can go wrong (`NotFound` when the
path is absent)? What does a delivered `Cancelled` do to it mid-read
(close the fd)? Is the order of `~line`'s firings owned (yes — file
order) so a register may bind to it? None of these facts is drawn,
and none is *drawable*: they are facts about the far side of the JS
edge. Every one of them, some round of the record has already said,
"lives on the block's catalog row."

Three lines, and the checker consulted the catalog three ways: a
built-in operator's law, a user operator's asserted algebra, a
foreign block's entire account of itself. The record has been
filling this registry for a dozen rounds while deferring, each time,
what an entry *is*. This round works that question.

## The demands on file

What the schema must hold is not designed here from theory; it is
sampled from the record — every family below is a demand some round
already filed, with the filing cited. (That is the standing method
applied to ourselves: the record is the corpus.)

- **Identity rows with value witnesses.** `associative`,
  `has-identity(v)` carrying the identity value; minted for user
  operators by the algebra facet; consumed by the availability
  ladder. Adopted. (`collect-family-design.md`.)
- **The commutativity flag.** A commutative-monoid row discharges
  the orientation-pinning demand and the whole-cube order demand;
  survey 4 found the discharge has field instances, and that one
  operator swap moves a program between regimes — evidence the flag
  belongs on the *operator's* row, not the construct
  (`product-linearization-design.md`; `product-flows-design.md`,
  "Registers over products"; `real-loop-survey.md`, finding 4.3.)
- **Shape/extent preservation.** The proved regime of co-extent
  walks through whole-value ops (`rotate`, `reverse`, permutations)
  only if their rows say shape is preserved; without the row the
  license falls back to the asserted regime.
  (`product-flows-design.md`, "The Life residue, worked" — filed as
  question 4's third client.)
- **Lane rows, by reference.** Declared throws convert to
  terminator lanes by catalog row (adopted —
  `failure-payloads-design.md`); and the tag-identity round demands
  that rows carry lane *references*, not lane strings, so two
  blocks converting the same underlying failure can mint one lane
  by shared referent (unadopted, consumed consistently below).
- **Edge translations.** The cancel translation (what a delivered
  `Cancelled` becomes at a foreign yield point — fetch →
  AbortSignal, timer → clearTimeout; `cancellation-design.md`,
  question 4 owns the fine print) and the serving block's three:
  failure-out, cancel-in, admission (`served-flow-design.md`).
- **Measure rows.** Structural-shrink and progress species carried
  as properties with witnesses on catalog divisions; the
  `minus1`-style decrement rows the drawn-fuel rung leans on;
  "the measure catalog's schema" filed jointly with question 4
  (`divide-flow-design.md`; `function-boundary-design.md`).
- **Ordering and effect laws.** The coalescing-write law (write as
  a monoid homomorphism — where present, segment placement is free;
  where absent, the boundary is meaning —
  `within-firing-effects-design.md`); the owned-order class of a
  block-minted flow, including the honest "Ambient" row
  (`delay-ontology-design.md`, adopted criterion;
  `chooser-family-design.md`, cross-client arbitration).
- **Level-1 entries.** Pattern, expansion, port correspondence —
  the anatomy `transformation-levels-design.md` already specifies
  for conversions, recognitions, and derived constructs; catalog
  *blocks* (merge by op, the external pull source, the fixed-length
  segmenter, pacing) are these.
- **Candidates explicitly not assumed.** Cacheability
  ("effectively pure per key" — `served-flow-design.md`, question
  5) and the settled-at stamp (`chooser-family-design.md`, question
  5) are filed as *possible* rows by their owners; this round gives
  them a family to land in and decides neither.

One registry keeps being named by three words — the level-1
**entry**, the derived **block**, the operator/edge **row** — and
the first thing to settle is that these are one thing at three
grains, not three mechanisms.

## One catalog, three grains: entry, block, row

**The catalog is the registry of vocabulary** — everything a
program invokes by name rather than draws in place: node kinds,
operators, named collects, derived blocks, level-1 operations, and
foreign (FFI) blocks. One entry per vocabulary item. The three
words the record already uses name grains of that one registry:

- An **entry** is the unit: one vocabulary item's whole account.
- A **block** is an entry whose definitional content is an
  *expansion* — a drawing it lowers to, with the anatomy
  transformation-levels specifies (pattern, expansion, port
  correspondence). `merge by <op>` is a block; so is the external
  pull source; so is completion itself
  (`time-travel-programs-design.md`, "Completion is a level-1
  catalog entry").
- A **row** is one *fact* on an entry: `add`'s `has-identity(0)` is
  a row; `readLines`'s `NotFound` lane is a row; a serving block's
  cancel-in translation is a row.

Nothing in the record's existing usage has to change; the three
words were always this. What the unification buys is that one
referent carries its whole account in one place. The serving block
is the proof case: its entry holds ports (the exchange pair), lanes
(the response lane's failability), three edge translations, an
ambient-order note, and — if it is a derived block over drawn
vocabulary — an expansion. Scatter those across an operator table,
a lane table, and a block table and the "one auditable place" goal
(`types-design.md`, "The JS boundary") is lost before the schema
exists: auditing one block would mean joining four tables by name.

## The entry is a referent, not a name

The tag-identity round's central move — a lane's identity is a
drawn identification, never a string — is adopted here for the
catalog wholesale, one level down (its adoption status rides that
round's; if the referent rule falls, everything below degrades to
qualified names, and the degradation is noted honestly at the end).

**An entry is an identity under the step-DAG discipline; its name
is presentation.** Renaming `readLines` to `readTextLines` touches
nothing: every program that used it referenced the entry, not the
spelling. Two entries with the same display name in different
scopes collide nowhere, because nothing was ever keyed by the name.
This is the codebase's own convention — strings below, typed
identities above — applied to the registry itself.

Two consequences do immediate work:

- **Lane fields hold lane referents.** The filed demand lands
  structurally: a row's `NotFound` is a reference to a lane
  identification, and two blocks wrapping the same library mint
  *one* lane by referencing one identification — deliberate,
  drawn-at-registration sharing, never a spelling coincidence. The
  catalog is exactly the third home the tag-identity round named
  ("In the catalog"), now with the schema slot it asked for.
- **Facet-minted rows anchor to the facet's identity.** A user
  operator's algebra row is minted by the facet attached to the
  operator's boundary, and the boundary is an identity
  (anchor-is-identity — the joint adoption's constraint). Edit the
  operator's interior and the row survives; *replace* the operator
  and the row's referent is gone with it, which is the right
  fragility: the claim was about that operator.

## The fact families

An entry carries facts in **families**. The families are open-ended
the way the property inventory is open-ended
(`types-design.md`, "A starter property inventory"): each is earned
by a construct that demands it, and the six below are the ones with
filed clients. A family defines three things: what a fact of the
family *claims*, what its **witness** is (the displayable evidence a
drawing can show at the consuming node), and what its **direction
of doubt** is when asserted (what breaks if the claim is false).

**Ports** — demands and offers per port, the `types-design.md`
substrate itself. For a node kind, this is its port discipline; for
a registered function or block, what it demands of inputs and
offers on outputs (`readLines` offers string-shaped elements). The
witness is the property itself, shown where it is used. This is the
family `implementation-strategy.md` names as the missing concrete
record ("the concrete record by which a node kind declares demands
and offers").

**Laws** — unary and algebraic facts about the operation:
`associative`, `has-identity(v)`, `commutative`,
`shape-preserving`, `coalescing`, the owned-order class of a minted
flow. Witnesses are family-defined: `has-identity` carries the
identity value (the strongest witness in the schema — a value the
program will actually yield); `coalescing` displays its law as the
two-sided equation (`write(a); write(b) ≡ write(a ++ b)`);
`shape-preserving` displays the extent equation across the op;
bare `associative` has no value witness, and its evidence *is* its
stated direction of doubt. Directions of doubt, per the collect
family's discipline: false associativity → reassociation and
parallel lowering wrong; false identity → empty collects wrong;
false commutativity → an order demand silently discharged that the
program observes; false shape preservation → a transpose licensed
by the proved regime misaligns — precisely the runtime conformance
error the asserted regime would have caught; false coalescing → a
boundary treated as free efficiency when the far side could see it.

**Lanes** — the failure account: each declared throw or failure
mode as a lane referent plus its payload shape and minting
condition. Adopted content gives this family its semantics
(declared throws convert by row; undeclared throws land on the
background super flow). Note the family's unusually *soft* doubt,
worth recording because it is the exception: a throw the row failed
to declare is not silent corruption — it lands on the super flow,
quarantined and collectable — and a lane declared but never minted
is dead vocabulary, harmless. The lane family fails soft in both
directions, which is the background super flow doing exactly the
job it was adopted for.

**Translations** — edge policy on foreign blocks: *cancel-in* (what
a delivered `Cancelled` becomes at the foreign API), *failure-out*
(what a failed exchange becomes on the wire), *admission* (what
happens to arrivals the program isn't ready for). These are the
irreducibly trusted family: they do not describe drawn meaning at
all, they describe what the runtime will *do* at the boundary, and
no drawing can witness them. Their doubt is the sharpest in the
schema — a false or missing cancel translation strands in-flight
foreign work beyond cancellation's reach (the leak the uncancel
pathology names), which is why a missing cancel translation on a
block that mints async work should be *advisory-tier visible*
(`types-design.md`, severity tiers), not silently fine. The
translations' fine print stays with its owners: the cancel word's
idempotence/promptness/post-cancel state is `cancellation-design.md`
question 4; the admission family belongs to the async round. This
round supplies the slot, not the content.

**Measures** — the divide flow's termination vocabulary: a division
op's row states its species (structural shrink or progress), the
decrease claim, and the precondition under which it holds
(`splitInHalf` yields strictly shorter lists *given length ≥ 2* —
the precondition discharged by the drawing, where the split's
discriminator establishes it). The `minus1`-style decrement rows
the drawn-fuel rung consumes are the degenerate members. The
witness is the decrease statement itself, displayable at the link
where the measure discipline checks it.

**Expansions** — the definitional content of blocks and level-1
operations: pattern, expansion, port correspondence, principal
derived ports, exactly as `transformation-levels-design.md`
specifies ("Anatomy of a catalog entry"). Nothing about that
anatomy is re-owned here; the schema point is only that an
expansion is *one family of facts on the same entry* that may also
carry rows — `merge by <op>` has an expansion (the walk with a race
in the decision position) *and* port facts *and*, per its operator
parameter, demands against another entry's rows (next section).

## Rows are demanded, not looked up

The question "how does the checker consume the catalog" has a
one-word answer: propagation. **A node demands facts of an entry
exactly as it demands properties of a wire.** Reduce-close demands
`associative` *of its operator's entry*; the divide link demands a
measure of its division op; a transpose in the proved regime
demands `shape-preserving` of each op the provenance walk crosses;
the memo middleware — if its owner adopts the row — would demand
effectively-pure-per-key of its facet. Operator and block positions
are ports at the meta level, and the demand/offer machinery already
runs over them: `types-design.md`'s starter inventory listed
"associative, has-identity — demanded by reduce-close (of its
operator), offered by operator catalog entries" from the start.

So there is **no second checker**. A missing row is an unmet
demand, with the standard witness — the demanding node, plus the
entry the demand reached — and the standard severity grading:
reduce-close over an operator with no associativity row is the
ladder's "no monoid, no node" (an error, the collect isn't
available); a missing cancel translation is advisory; a missing
shape-preservation row is not even a warning, because the program
falls back to the asserted regime and still draws (the Life
filing's own account). Which family lands in which tier is decided
per family by its owner, using the tiers checking already has.

## Trust is graded per fact, not per entry

The classic framing — "the catalog is the trusted edge" — is too
coarse, and getting it right is most of this round's content. One
entry mixes truth-makers:

- **Definitional facts** are checkable by inspection. A block's
  expansion *is a drawing*: its truth is not asserted, it is
  readable — the block means its lowering, and the lowering is
  ordinary drawn vocabulary the checker checks like anything else.
  A node kind's port discipline is the language's own construct.
  Wrong definitional content is a bug, not a betrayal of trust.
- **Asserted facts** are claims about what cannot be drawn: JS
  behavior (shape offers of a foreign function, lanes,
  translations) and unprovable laws (a user operator's
  associativity, an op's shape preservation). Every asserted fact
  carries its stated direction of doubt, and is shown with the
  "asserted, not verified" grading the collect family already
  prescribes for facet claims.

The same *family* can appear on both sides of the grading: a
built-in `add`'s identity row is the language's own word
(definitional — the language ships and vouches for its starter
table), while `mergeCounts`'s identity row is the user's word
(asserted via the facet). The schema records the grade per fact,
so the display and the manifest (below) never have to guess.

This is also where the record's degenerate case slots in without
ceremony, exactly as the tag-identity round found for construct
lanes: the language's own constructs are entries whose facts are
all definitional — `Stopped` and `RanOut` are lane referents
supplied by the constructs themselves; a collect's port discipline
is its entry's port family. Nobody registers these; the language
is their author. The catalog does not begin at the JS edge — it
begins at the vocabulary, and the JS edge is where its facts stop
being checkable.

## The admission rule: use-independent facts only

What keeps the catalog from becoming a second program: **an entry
holds only facts that are true of the operation everywhere, never
facts about a particular use.** If two uses could honestly
disagree, it is not catalog content — it is drawn at the use.

The record has already sorted several borderline cases onto the
right side of this line, and the rule is read off them rather than
invented:

- The **asserted co-extent precondition** lives at the barrier that
  needs it, per use, with a runtime failure witness — because two
  zips of the same op's outputs can differ in whether their extents
  match. Not a row.
- The **drawn fuel measure** lives on the page — the decrement and
  the zero-covering alt — because the budget is the program's,
  not the operation's. Only the decrement op's own decrease fact is
  a row.
- **Caller-local lane identifications** ("both `NotFound`s are
  nothing-to-show") are drawn at the handling site. The catalog
  holds shared lane referents; *which* lanes a caller chooses to
  identify is that caller's meaning.
- The **orientation-pinning demand** is authored at the
  order-observing consumer; only the commutativity flag that
  *discharges* it is a row. Survey 4's sharpest finding is field
  confirmation that the split is real: one operator swap (additive
  compositing → over-painting) moves a program between regimes
  while the drawing stays fixed — so the flag tracks the operator,
  and the demand tracks the use (`real-loop-survey.md`, 4.3).

The litmus is worth stating because future rounds will keep filing
candidate rows: *would the fact survive the operation being used in
a program its author never saw?* Identity of `+`: yes. "This zip's
lanes are co-extent": no.

## The empty entry

What of the JS that registers nothing? The textual form's
`js "…"` escape hatch and any unregistered App function are
**entries with no facts** — and that is a lawful, load-bearing
state, not a hole in the story:

- No port facts: the value offers nothing, demands nothing.
  Downstream checking is *silent*, not failing — absence of a
  property is absence, not falsity, the same reading placeholders
  rely on (`types-design.md`, read-out 3).
- No lanes: its throws are undeclared by construction, and land on
  the background super flow — the adopted quarantine, doing for
  unregistered code exactly what it does for a registered block's
  undeclared residue.
- No translations: a delivered `Cancelled` has no foreign word, so
  in-flight foreign work it started is beyond delivery — the honest
  gap, surfaced by the same advisory that flags a registered block
  missing its cancel translation.
- No laws: no reduce-close over it, no proved-regime transpose
  through it, no register on a flow it mints (no owned-order row —
  the order-demand check simply finds no discharge).

Registration is therefore **opt-in refinement, monotone in what the
program may do**: add a shape offer and downstream demands start
being met; add lanes and discharges become drawable and
exhaustiveness checkable; add laws and the collect ladder, the
proved regime, and registers unlock. Each addition is one more
fact, never a rewrite of the program — graceful expansion, applied
to the edge. Mandatory registration is rejected below as a dead
end; this default is what makes the rejection affordable.

## The trust manifest

`types-design.md` states the honest soundness claim: relative to
the catalog. This round makes the claim *legible per program*. The
propagation that checks a program knows, at every discharged
demand, whether the discharging fact was definitional or asserted.
Record it, and project:

> **The trust manifest (derived view).** For a chosen output or
> boundary: the set of asserted facts its checked validity rests
> on — each with its entry, its direction of doubt, and the demand
> it discharged, every element walkable to a place on the diagram.

"This output is well-checked, *given*: `mergeCounts` is associative
with identity `emptyCounts` (else empty totals are wrong);
`readLines` mints only `NotFound` (else the residue lands on the
super flow); its cancel translation closes the fd (else a stranded
read leaks)." That is the audit surface the JS-boundary note asked
for ("assertions in one auditable place") — sharpened from *one
place to read* into *one question to ask*: not "what does the
catalog assert?" but "what does **this program** trust?"

The manifest is a read-only derived view in the standard
discipline — computed from the same propagation, never stored,
never edited — and it composes with the machinery around it:

- **Boundary projection carries it.** A reused diagram's principal
  property signature can carry its interior's manifest as a
  summary, so a caller's manifest includes the callee's without
  re-propagating the interior — the same once-per-version
  memoisation as the signature itself.
- **The test double is its discharge surface.** A facet's asserted
  laws and lanes are exactly what a double exercises: the
  FailingAllocator double mints the facet's lane, so the test runs
  the very discharge the production binding will run. The manifest
  names which assertions a test suite has contact with — the
  legibility-over-enforcement stance
  (`effects-design.md`) applied to trust: the language does not
  verify the claims; it makes visible *which* claims are load-
  bearing, per program, so a human can aim tests and review at
  them.

## Honest registrations

The remaining half of the question as originally posed: "whether
discriminators and primitives should register through a schema that
keeps the assertions in one auditable place — e.g. generated
together with the JS they describe."

The leaning: **the JS is a field of the entry, not the entry a
label on free-floating JS.** A foreign block is authored as one
act — its JS source (or import reference) and its facts in one
record — so there is no drift channel between a function and a
registration living apart. The repo's own test registry is the
first client: the handful of App functions `Main.res` uses would
register ports and laws in one ReScript value beside their JS
string (the `Property.res` stub already sketches the flat version
of exactly this).

On generation: where the foreign side carries its own typed
description (a `.d.ts`, an OpenAPI schema), a derivation can
**draft** port facts — but drafting changes authorship, not trust
class. The author adopts the draft into the entry and the entry
says so; trust always terminates at an author's assertion, never
at an artifact nobody in the record vouched for. (The silently
imported interface is a dead end below.) Discriminators get the
sharpest version of honesty available: a discriminator's
registration declares its alt set, and its entry can carry the
discriminating JS *generated from* the alt set (tag string
comparisons, in the degenerate case) rather than hand-written
beside it — the one case where the assertion can literally
manufacture the code it describes, closing the gap from the other
side.

## Against the philosophy

- **Example first, then generalise.** The families are sampled
  from filed demands, cited row by row — no metadata theory
  declared upfront, and the schema admits new families only the
  way the property inventory admits new rows: earned by a
  construct that demands them.
- **Foundations before features.** This round is paper-first
  consolidation of six rounds' filings before `Property.res` grows
  past a stub; the flat strawman record is named as the thing this
  schema replaces *before* it calcifies.
- **Building blocks at the programmer's abstraction level.** One
  obvious reading: a row is shown at the node that consumes it —
  the identity value at the reduce-close, the alt coverage at the
  split, the cancel word at the block. The catalog is where facts
  live, never where they are read.
- **No bottlenecks.** An entry is not a packed type: each fact is
  demanded, discharged, and displayed individually, and the
  boundary projection stays a *set* of facts. The expansion
  family inherits transformation-levels' port correspondence —
  the no-bottleneck principle one level up, unchanged.
- **Abstraction is the source of truth; concreteness derived.**
  The admission rule keeps the catalog from ever duplicating a
  drawn fact (no second source of truth); the manifest and every
  row display are read-only derived views.
- **Building blocks must build.** The empty entry → shape offer →
  lanes → laws → translations ladder is additive refinement; no
  rung rewrites a program or an entry. The +1 step never changes
  vocabulary.

## Dead ends

1. **The name-keyed catalog.** You might wonder whether the
   registry should simply be a global table keyed by name —
   `"add"`, `"NotFound"`, `"readLines"` — so registration is a
   string and lookup is trivial. It turns out this imports every
   failure the tag-identity round catalogued for lanes, now for
   the whole vocabulary: renames silently rebind programs, two
   authors' coincident spellings capture each other's entries, and
   sameness becomes a pun (`errno`'s one `ENOENT` for every
   library is the shipped mirror). Strings stay below; the
   serialization layer resolves them against scope exactly as the
   textual surface resolves port names. (Settled within this
   proposal — don't re-propose without new evidence.)

2. **Per-family separate catalogs.** You might wonder whether the
   operator registry, the lane registry, and the block registry
   should each be their own mechanism, designed by their owning
   rounds. It turns out one referent's account then scatters: the
   serving block carries ports, lanes, three translations, an
   order note, and possibly an expansion — five tables joined by
   name to audit one block, and the name join reintroduces dead
   end 1 through the back door. The families are the schema's
   modularity; the entry is its unit. (Settled — don't re-propose
   without new evidence.)

3. **Mandatory registration.** You might wonder whether every App
   function should be *required* to register before use, so the
   checker never runs blind. It turns out this is the obligatory
   declared signature in edge clothes — the ceremony-before-
   concreteness shape the boundary round rejected for functions
   and the failure round rejected for throw sets. The empty entry
   keeps unregistered JS lawful and silently unchecked, the super
   flow keeps it *safe*, and refinement stays opt-in and monotone.
   (Settled — don't re-propose without new evidence.)

4. **Facts on instances.** You might wonder whether the row could
   live on the node that uses the operation — annotate *this*
   reduce-close as associative — avoiding the registry entirely.
   It turns out this is two sources of truth the moment an
   operation is used twice, and the field evidence cuts against
   it: survey 4.3's operator swap shows the law tracking the
   operator while the drawing stands still, so a per-instance
   annotation would have to be edited in lockstep across every
   use — the drift channel the catalog exists to close. Per-use
   truth exists, but it is *drawn* (the admission rule), never
   annotated. (Settled — don't re-propose without new evidence.)

5. **The proving checker.** You might wonder whether asserted laws
   could graduate to verified — prove associativity from the
   operator's diagram, prove shape preservation from `rotate`'s
   definition. It turns out this is the collect family's settled
   dead end, and it generalises: theorems about operations are not
   propagatable properties, and a checker that attempts them
   acquires search, the one thing the solver is forbidden. The
   catalog *consumes* claims; it never establishes them. Doubt is
   handled by stating its direction and surfacing it in the
   manifest, not by proof. (Settled in
   `collect-family-design.md`; recorded here at schema scope —
   don't re-propose without new evidence.)

6. **The silently imported interface.** You might wonder whether
   foreign type descriptions (`.d.ts`, API schemas) should flow
   into the catalog automatically, so the edge is "already
   typed." It turns out this floods wires with facts nobody
   demanded and — worse — installs trust roots no author in the
   record vouched for: the manifest would name assertions whose
   author is a build artifact. Derivation may draft; an author
   adopts; the entry records the adoption. (Settled — don't
   re-propose without new evidence.)

## Open questions

1. **The adoption conversation.** The schema as a whole is
   unadopted. Its dependency structure for that conversation: the
   entry-as-referent piece rides the tag-identity round's referent
   rule (if that falls, entries and lanes degrade to
   scope-qualified names — the registry survives, the sharing
   story weakens); the lane family's semantics are already adopted
   content; the manifest and the admission rule stand on their
   own.
2. **Per-family content owed to owners.** The cancel translation's
   fine print (idempotence, promptness, post-cancel state —
   `cancellation-design.md` question 4); the admission family's
   members (async round); cacheability's witness
   (`served-flow-design.md` question 5); the settled-at stamp
   (`chooser-family-design.md` question 5); equality's fine print
   (`types-design.md` question 8). This round supplies slots, not
   their contents.
3. **The facet-lane declaration's exact shape.** How a facet
   declares the lanes its ops mint — rides facets' attachment
   representation (`facets-design-notes.md`, open edge 3), jointly
   with the tag-identity round's residue.
4. **The concrete record.** The ReScript shape of an entry — how
   `Property.res`'s flat `catalogRow` strawman (string-keyed,
   fixed fields) evolves into referent-identified entries with
   per-family fact lists — is a decide-in-code question for
   workstream D (`implementation-strategy.md`), constrained but
   not dictated by this round.
5. **Is the manifest level-1?** Whether the trust manifest is a
   first-class derived view with port correspondences (like
   expansions and summaries — `types-design.md` question 6's
   tower question) or editor ephemera. The lens discipline
   suggests the former; nothing here forces it.
6. **Naming.** "Catalog", "entry", "block", "row", "manifest",
   "translation" are all placeholders, owed to the naming sweep
   with checking's other words.

## What this doesn't address

The checker's own machinery (owned by `types-design.md` and
implemented in workstream D); recursive shapes (question 2) and
slot/conditional signatures (question 3), which will add demands
*through* the schema but are not schema questions; the graphical
presentation of rows and the manifest (layout side, out of scope
in this repo); and any spelling (textual round).
