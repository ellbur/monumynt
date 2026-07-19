# Focused update: transform selected loci of a nested value

Status: exploration — this chapter teaches a worked proposal that has
not been adopted yet; everything below is a leaning, not a decision.
Nothing here is implemented. Code samples use the textual syntax of
`textual-representation-design.md`; the compact path spelling (`|=`)
and the write-back collect (`collect back`) are *spelling
provisional* and owed to the textual round — as are two glyphs the
compact form borrows that collide with reserved meanings: the
leading `doc | …` path marker (that document reserves `|`
exclusively for junction taps) and the `->*` map-into-open arrow
(not in the arrow family). Read every compact-form sample as a
sketch of the drawn structure, not as parseable text.

## Changing a little, keeping the rest

You will often want to change a small part of a large nested value
while preserving everything else: add one to every post's
like-count, redact one field of every record, apply a function at a
fixed depth of a tree. Each spot being changed we'll call a
**locus** (plural *loci*) — the rest of the value, the part that
must come through untouched, is the frame around them. The clients
of this shape are document transformation, immutable state updates
(reducers, config edits), and tree rewriting.

This chapter works out the construct for the shape, called **focused
update** — what it *is* (a selection read as a round trip), the
structural condition that makes the write-back well-defined, why the
value-selected case is a case split and never a filter, why
many-loci-at-once is the primary case, and the conflict rule — and
records where its pieces already live. The evidence from shipped
languages, which here is unusually rich, is gathered in "Where this
shows up in real code" below.

## The shallow case: the language already does this

Start with the smallest version, because it needs no new construct
at all. A **one-level** focused update over a list — no nesting
between the root and the loci — is a case split with an identity
branch and an exhaustive collect, which `core-model.md` already
draws:

```
xs -> open list -> split parity of Even, Odd
  Even: -> double        -- the selected loci: transform
  Odd:                   -- the rest: identity, the element rides through
-~> collect              -- case close: one value per position, exhaustive
-~> collect => out       -- list close: [1,4,3,8] from [1,2,3,4]
```

Read it as: open the list, split each element by parity, double the
even ones, leave the odd ones exactly as they are, and close
everything back up. Nothing is missing here. The untouched elements
pass through because the close is **exhaustive** — every position
yields exactly one value, the identity branch yielding the
original — so the list rebuilds with only the `Even` positions
changed, order and length preserved. Record fields are the same
story shallowly: `rec -> {title, likes: .likes -> add(1)}` changes
one field by spreading the rest.

## When the change is deep

Now the case that hurts. A document of users, each with posts, each
post with a like-count:

```
{ users: [ { name, posts: [ { title, likes }, … ] }, … ] }
```

The task: **add one to every post's like-count**, leaving names,
titles, post order, and user order exactly as they were. In jq this
is one line — `.users[].posts[].likes |= (.+1)`. The loci are
`.users[].posts[].likes`: many of them, deep in the structure.

The hand-written form — the "assembly language" the record uses to
recognize a missing construct — is an identity rebuild at *every*
level between the root and the locus:

```
doc -> .users -> open list
  -> {name, posts:  .posts -> open list
                      -> {title, likes:  .likes -> add(1)} }   -- rebuild each post
     -~> collect                                               -- rebuild the posts list
  ... rebuild each user {...name, posts: •} ...
  -~> collect                                                  -- rebuild the users list
  ... rebuild {...doc, users: •} ...
=> doc'
```

Every untouched sibling — `name`, `title`, and the two list orders —
is named and copied forward by hand, at each of the three levels, to
change the one field at the bottom. This is XQuery's `swizzle`
typeswitch recursion (rebuild every node by cases to change the few
that match) and Redux's spread-pyramid, in our notation.

Compare the two examples: the shallow one was fine, and the deep one
is the shallow one repeated at every level. What compounds into
boilerplate is **depth**. Each level adds one more exhaustive
collect and one more spread to write by hand, and the path to the
loci threads through all of them. Focused update is the construct
that lets you name the path once and the transform once, and derives
every intervening rebuild. The identity rebuild is to focused update
what the side-flag was to end-when and the worklist to saturation:
the boilerplate whose removal names the construct.

## One drawing, read both ways

Here is the key move. The path `.users[].posts[].likes` is an
ordinary **selection chain** — the very chain you would draw to
*read* every post's like-count:

```
doc -> .users ->* open list -> .posts ->* open list -> .likes
     -~> join -~> collect => allLikes      -- reads the loci: a flat list of counts
```

Focused update takes *this same chain*, transforms at its tail, and
instead of gathering into a fresh value, **collects back through the
chain into the original structure**:

```
doc | .users[] .posts[] .likes  |=  add(1)   => doc'   -- spelling provisional
```

The compact `|=` form is the surface; underneath it is the selection
chain plus a write-back collect (`collect back`) that **mirrors the
chain**. Every stage of a structural selection has a known inverse —
its lens setter — and the mirror is nothing but those inverses run
in reverse order:

| forward stage (getter) | inverse stage (setter) | what it preserves |
|---|---|---|
| `open list` | exhaustive list collect | order and length — one value per position |
| `.field` (record projection) | `{…rec, field: •}` (spread) | every sibling field |
| `split P of A, B, …` (case open) | exhaustive case collect | the untouched alts (identity branches) |

So the write-back is **fully determined by the path**. This is the
idea functional programmers call a *lens*, made concrete: *the
structural getter determines the setter.* You draw the selection and
the transform; the mirror is a **derived view** — derivation is
downward and free, abstraction upward and earned (principle 6,
"abstraction is the source of truth," applied at the value level).
Selection and update are one drawing read in two directions, which
is jq's deepest design win (the filter that reads a locus is the
filter that writes it) preserved rather than re-invented as a
separate update-side language.

The one genuinely new capability is **running a selection backward
as a reconstruction.** Uncollect/collect over lists already
round-trips (open a list, do nothing, collect and you have the list
back). Focused update generalizes that round trip to projections and
case splits, and makes the backward direction automatic.

## Selecting by value: a split, never a filter

The write-back is well-defined only when the selection is
**structural** — fixed by the shape of the value, not by the values
of the atoms in it (BQN's well-formedness condition).
`.users[].posts[].likes` is structural: the loci are determined by
walking the structure, before any atom is read. The commuting law
that makes the round trip sound — *reading a locus after the update
equals transforming the value read before it, with the frame
untouched* (BQN's `𝔾 𝕨𝔽⌾𝔾 𝕩 ≡ 𝕨𝔽○𝔾 𝕩`) — holds exactly because
the loci do not move when their contents change.

Value-dependent selection is the trap. "Add one to the like-counts
**over 100**" selects loci by reading them — the mask depends on the
data. BQN rejects `10⊸+⌾((<⟜5)⊸/)` outright and requires the mask
be computed from a copy *first*, then used structurally. In our
vocabulary this condition is not an extra rule — it is the
**value/flow discipline already in force**. A value-dependent
selection is a **case split**, and its bundle provenance is the
materialized mask:

```
doc | .users[] .posts[]  |=  ( split (likes > 100) of Hot, Cold
                                 Hot:  -> .likes -> add(1) ...
                                 Cold:                        )   -- identity
```

The selected posts and the rest are **two alts of one exhaustive
split**, both collected — the `Cold` alt is an identity branch, the
untouched rows retained by ordinary bundle provenance
(`bundle-provenance-design.md`). This is the load-bearing
distinction of the whole design:

> **Focused update by predicate is a case split with an identity
> branch, never a filter.** Filtering (`join(list, case-alt flow)`)
> *forgets* the unselected elements; focused update must *remember*
> them in place.

Filter drops the `Cold` rows; the exhaustive collect keeps them.
This is `modify_if` versus `keep` in purrr, and it is *why* BQN
forbids value-selection-Under unless the mask is materialized: the
materialized mask is exactly the retained case bundle. The
value/flow sort makes the error unwritable in the drawn form — you
cannot re-collect a filtered flow back into the original positions,
because filter discharged the provenance that named them.

The **reflective tier** (jq's `paths` — compute *which* loci from
the data itself, then update them) fits without exception: the
computed paths are materialized as data before the write, so the
selection they drive is structural even though it was derived from
values. Same condition, one level up.

## Many loci is the normal case

`.users[].posts[].likes` selects *many* loci — the `[]` steps are
`open list`, and every list-open turns the selection into a **flow**
of loci (a nested list flow here). The transform fires once per
firing of that flow, and the mirror collects each level back. The
single-locus case (`.config.timeout |= …`) is the degenerate path
with no list-opens — an all-projection chain, one firing, the mirror
a stack of spreads. So multi-locus is not an extension of a
single-locus core; it is the core, and single-locus is the flow that
fires once.

This is why the construct is built from uncollect/collect rather
than from a scalar `setIn(path, value)`: the path naturally crosses
opens, and crossing an open is exactly where "many loci" is born.
`(.a, .b) |= g` (several *different* paths to one root) is the
multi-path case — a fan of selection chains sharing the input wire,
each with its own mirror, composed left-to-right (see the conflict
rule).

## When two writes collide: the conflict rule and the scatter costume

Could two write-backs ever fight over the same spot? For the
ordinary structural path, no: distinct list positions and distinct
record fields never collide — the mirror writes each to its own
slot. Collisions arise only in the **scatter costume**: writing by a
*computed index* (`A[X] |= …` where the index vector `X` has
repeats), which is the value-write dual of structural selection.
When two write-backs reach the same slot, a resolution must be
declared; the record adopts Dyalog's shipped rule — **last-most
wins** — for the multi-path fan and for scatter. For the common
structural path (list positions, record fields, case alts) the
question does not arise, so it is filed as a **named sub-case (the
index-as-value write), not part of the base construct** — the base
is disjoint by construction. Scatter-as-construction (build a lookup
table by writing at computed indices) is the same node used forward
from an empty seed; whether that is one construct with focused
update or a sibling is an open question.

## Views you can write back through

BQN's Under generalizes the "part" from a sub-locus to a *reversible
re-presentation*: `F⌾⥊` acts on an array reshaped to a list, `F⌾⍉`
acts on columns by working on rows, `` ∧`⌾⌽ `` scans from the end by
reversing, scanning, un-reversing — compute in the view, write back
through it. This is the record's derived-views instinct (principle
6) surfacing at the value level, and it subsumes the whole family:
reshape, transpose, and reverse are structural one-to-one
correspondences, each with a known inverse, so each is a legal
*stage* in a selection chain exactly like `open list` and `.field`.
The mirror composes their inverses with the rest. This round names
the generalization and defers the per-view catalog (transpose is the
product round's commute; reverse and reshape want the zip/table
forms) — the point secured here is that a reversible view is
admissible in the path because its inverse is the setter.

## Rewriting every node of a tree: the recursive lift

Everything above is focused update at **fixed, drawn depth** — the
path names a specific number of `open list` / `.field` steps. jq's
`walk` and `recurse(.children[]) |= g` rewrite at *every* node of a
recursively nested structure, depth unknown until runtime — "change
every node matching P, however deep." That is recursion over
structure, which is `trees-and-recursion.md`'s territory (the
zipper, the divide flow), still narrative-stage. The relationship is
clean and worth stating now:

- **Fixed-depth focused update is the non-recursive base** — worked
  here.
- **Deep rewrite is that base lifted over tree iteration** — the
  mirror becomes the *unfold* half of the tree's fold/unfold pair,
  rebuilding each node with its rewritten children and untouched
  other fields, exactly the exhaustive-collect-preserves-siblings
  rule applied at every node of the walk. XQuery's `swizzle`
  recursion is what writing that unfold by hand costs.

So focused update and the trees row meet: the trees row owns
*iterating* a recursive structure; focused update owns *writing back
through* a selection, and the deep-rewrite case is their product.
Neither is worked enough yet to nail the seam; the divide flow's
round should take `walk`-style rewrite as a first client, because it
forces the unfold side that the constructed divide-flow examples so
far have not. *The round has now done so*
(`divide-flow-design.md`, "Deep rewrite: the unfold client"): each
level is this round's fixed-depth mirror with a link at every child
locus, and — because the division there is over data (strict
components) — its termination measure holds by construction.

## What an update gives back: the delta

Immer records the coupling this round should not lose: the natural
*output* of a focused update is not only the new value but a
**stream of patches** (the loci that changed, and to what) — a
delta, as data. Two consequences the record already leans toward:

- **Patches-as-data.** The set of loci the update touched is
  drawable — it is the selection chain's flow, the same witness that
  drove the write. An update can emit its delta beside its result,
  no extra machinery: the loci flow is already in hand.
- **Update loci are invalidation keys.** A change at a locus is
  exactly the invalidation event the incremental-collections layer
  keys on (`incremental-flow-design.md`; provenance's prefix rule in
  runtime clothes). This row and the incremental collections layer
  are two ends of one pipe — the focused update *produces* the
  deltas that layer *consumes* — and hierarchical keys with prefix
  invalidation are the path made into a subscription. Named, not
  designed here.

## Relationship to the neighbours

- **Partial collect** (`partial-collect-design.md`) edits *flows* —
  which branches of a split reconverge. Focused update edits
  *resting structure* — which loci of a value change. They share the
  exhaustive case-collect (the identity-branch retention), but the
  partial collect drops branches while focused update never drops a
  sibling; the base focused update is the *fully-covering* collect
  used as a setter.
- **`transformation-levels-design.md`** edits *programs and edit
  history*, not values; a focused update is a value-level operation
  that could itself be an edit at that level, but the two are
  different structures (one rewrites a program, the other a datum).
- **The register / loop-carried state**
  (`iteration-with-state-design.md`) is independent of this: focused
  update carries no state across firings; each locus is transformed
  independently. A stateful focused update (a running fold *while*
  rewriting) is the register composed with the mirror, not a new
  construct.

## Where this shows up in real code

The gap is well-witnessed and, unusually, its *structure* was worked
before any round in our vocabulary ran. Two shipped relatives each
built major machinery for exactly this shape: half of jq is paths as
first-class values (every filter in path context names the loci it
selects; every assignment is defined by those paths; `walk`-family
deep rewrites), and XQuery grew an entire separate W3C facility
(Update; `copy … modify … return`) to say "a changed copy of this
tree" at all (`xquery-jq-comparison.md`, §7). APL/BQN supplied the
semantic law: BQN's structural Under `⌾` is the round-trip
specification, the structural-selection well-formedness condition,
the lens identification, the derived-view generalization, and the
multi-locus conflict rule — and BQN *removed* its Expand primitive
in favour of Under, a shipped language cutting its primitive count
by recognizing focused update as the more general construct
(`apl-family-comparison.md`, §7). purrr's `modify` family is the
sixth witness, stating the functor laws outright — the sanity checks
that changing nothing changes nothing (`modify(x, identity) === x`)
and that updates compose — with `modify_in` writing at a pluck path
(`tidyverse-comparison.md`). Three ecosystems agree on the shape;
none of it has been drawn here.

## Against the philosophy

- **No bottlenecks.** The untouched siblings pass through as
  themselves — the exhaustive collect and the spread are barriers
  with corresponding inputs and outputs, nothing packed into an
  intermediate structure to cross a level. The spread-pyramid and
  the `swizzle` typeswitch are what the severed thread looks like
  when the passthrough is written by hand.
- **Inside-out — cases as values.** The selected and unselected loci
  are drawn cells of a split, not a scoped `if` that mutates in
  place; the path is a value wire read forward and back, not ambient
  cursor position.
- **Building blocks must build.** The +1 ladder is additive: shallow
  (already the case split) → deep (the path's mirror) →
  value-selected (the split with an identity branch) → reflective
  (computed paths) → recursive (the divide-flow lift). Each rung
  adds structure to the drawing; none rewrites into a different
  construct — the counterexample the record fears (`.map()`
  unbuildable-upon) is avoided precisely because selection and
  update are one vocabulary.
- **Abstraction is the source of truth.** The setter is a *derived
  view* of the getter, never separately authored — you cannot edit
  the write-back to disagree with the path, which is what keeps a
  lens lawful.
- **Example first.** Every piece was forced by a concrete witness —
  the nested `likes` increment, the over-100 predicate, jq's
  `paths`, BQN's reshape-Under — not invented for generality.
- **Foundations before features.** The recursive deep-rewrite is
  named and deferred to the divide flow rather than bolted on; only
  the seam is stated.

## Dead ends

Recorded in place, each with the reason it should not be
re-proposed.

1. **A separate update-side language.** Now, you might wonder why
   the language doesn't just add a `setIn`/setter DSL distinct from
   the selection vocabulary — the way XQuery's Update Facility is a
   second facility beside the query language. It turns out this
   doubles the vocabulary and breaks the lens identity (selection
   and update must be *one* drawing read two ways). jq's
   paths-as-one-vocabulary is the positive witness; XQuery's needing
   a whole second W3C facility is the negative one. (This is a
   settled dead end — please don't re-propose it without new
   evidence.)

2. **Value-dependent selection written as a filter.** You might
   wonder why you can't select loci by `keep`/`join`-with-a-case-alt
   and then write them back. It turns out filter discharges the
   provenance that names the unselected positions, so there is
   nothing to write *around*. Value-selected focused update is an
   exhaustive split with an identity branch, which retains every row
   (the materialized mask BQN's condition demands). (This is a
   settled dead end — please don't re-propose it without new
   evidence.)

3. **A scalar `setIn(path, value)` core with multi-locus as an
   extension.** You might wonder why the single-locus write isn't
   the base case, with many-loci layered on top. It turns out this
   inverts the primacy. The path crosses opens, and crossing an open
   is where "many loci" is born, so multi-locus is the base and
   single-locus the once-firing flow — not the other way round.
   (This is a settled dead end — please don't re-propose it without
   new evidence.)

4. **A live value-dependent probe as the selection.** You might
   wonder why the loci can't be chosen by a predicate evaluated
   *during* the write-back (so the mask can shift as contents
   change). It turns out this is rejected by the commuting law: the
   loci must be fixed as data before any write, or the round trip is
   ill-defined (read-your-writes inside one update). This is BQN's
   structural condition; reflective paths (computed *then*
   materialized) are the sanctioned way to be data-driven. (This is
   a settled dead end — please don't re-propose it without new
   evidence.)

5. **Materializing the virtual recursion tree to reuse ADT
   derivation for deep rewrite.** You might wonder why deep rewrite
   doesn't just build the recursion tree as a data structure and
   fold over it. It turns out this is rejected for the same reason
   `trees-and-recursion.md` rejects it for mergesort: declaring the
   structure upfront violates example-first. Deep rewrite is the
   divide flow's lift, not a data-tree fold. (This is a settled dead
   end — please don't re-propose it without new evidence.)

## Open questions

The language hasn't decided any of these yet.

1. **Adoption.** Prepared for the design conversation; nothing
   marked decided. The shallow case is already in the language; what
   adoption buys is the derived mirror over a drawn path.
2. **The path's exact drawn form.** Whether the path is a
   first-class value (a drawn witness you can name, fan, and
   compute — jq's `path(f)`/`paths`) or only a chain shape read in
   two directions. The reflective tier wants the former; the
   co-location and provenance rules want to know which node the
   mirror hangs on.
3. **The write-back collect's spelling.** `collect back`, a `|=`
   marker on the tail, or a block form (`focus <path> in
   <transform>`); and how it interacts with the implicit flow stack
   when the path mixes list opens (flow layers) with record
   projections (not layers). Owed to the textual round.
4. **Scatter and the conflict rule.** Whether the index-as-value
   write (`A[X] |= g`, collisions resolved last-most) is the same
   construct as structural focused update or a sibling, and whether
   scatter-from-empty (construction) unifies with update. Dyalog's
   last-most is adopted for the multi-path fan; scatter's membership
   is open.
5. **Derived-view catalog.** Which reversible re-presentations are
   admissible path stages (transpose = the product round's commute;
   reverse, reshape, the zip/table forms) and how each view's
   inverse is named. The generalization is secured; the catalog is
   deferred.
6. **The seam with the trees row.** How the fixed-depth mirror lifts
   to the divide flow's unfold for deep (`walk`-style) rewrite. Both
   rows are under-worked; take `walk` as a first client of the
   divide flow's round. *Worked in `divide-flow-design.md`* ("Deep
   rewrite: the unfold client") — the seam held as predicted; what
   remains here is only the delta output's behaviour through the
   lift (question 7's territory).
7. **Delta output and incremental coupling.** Whether the
   touched-loci flow is emitted beside the result by default
   (Immer's patches) and how it feeds the incremental-collections
   layer's keyed invalidation. Named; the layer is
   `incremental-flow-design.md`'s.
8. **Evidence.** The shape is invisible to loop sampling by
   construction, and this round's comparison corpora are
   document-domain-biased toward it. A sample of application code's
   nested-immutable-update idioms (spread pyramids, builder copies,
   `setIn`/lens libraries, reducer bodies) would measure how often
   the shape occurs outside document processing and re-weight this
   row's W — a breadth obligation, never a demotion on rarity
   (`open-problems.md`, Evidence owed; the focused-update frequency
   question).

## What this doesn't address

- **Recursive deep rewrite** — `walk`-style
  change-every-matching-node is the divide flow's lift
  (`trees-and-recursion.md`), deferred; this round supplies the
  fixed-depth base and the seam.
- **The path as a first-class computed value** — jq's
  `paths`/`getpath`/`setpath` reflective tier is named (open
  question 2), not designed.
- **Derived-view stages beyond naming them** — the
  transpose/reverse/reshape catalog is open question 5.
- **The delta/patch output and incremental collections** — named as
  one pipe (open question 7); the collections layer is separately
  designed (`incremental-flow-design.md`).
- **Visual depiction** — how a path-as-selection reads, and how the
  mirror write-back is drawn, are the layout side's, out of scope in
  this repo.
- **Implementation.** Nothing here is in the compiler; record
  projection as a lens setter, and the mirror collect, are new
  pieces the drawn vocabulary does not yet emit.
