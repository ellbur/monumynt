# Learning from other languages: the APL family

*Comparison round, 2026-07-10. Fifth execution of the genre begun
with `effekt-comparison.md`: read another language's programs
against how the record approaches the same problems, extract
problems — never mechanisms — and reweight `open-problems.md`.
**This round decides nothing**; demands are handed to owning docs,
design stays in the design conversations.*

*This round has a stated brief from the design conversation, set
before the corpus was read. APL-family concision comes from
higher-order functions — the operator layer — and **that approach
is not wanted**: higher-order functions are too hard to reason
about, and the record already has the inside-out answer to the
problem they solve. A flow resembles a higher-order function in
that arbitrary code consumes the value output before it is
collected — but by the inside-out principle nothing is ever passed
as a function: the uncollect exposes the mapped value as a
*virtual value* the program simply computes with. So this round
does not shop for mechanisms even by its usual standard; it reads
the family for **example programs** — hunting for ones the drawn
vocabulary would struggle to represent naturally — and for what
the operator inventory says about the completeness of ours.*

*Corpus. The FinnAPL idiom library, complete (707 idioms — task
statement plus expression — read via the public-domain conversion
of the APL Wiki page; the wiki itself is proxy-blocked in this
environment, as is the J wiki). Dyalog's open documentation:
reference pages for Key `⌸`, Stencil `⌺`, Rank `⍤`, At `@`,
Reduce (with the identity-element table), N-wise Reduce, Scan,
Inner/Outer Product, Grade, Where, Partition `⊆`, Partitioned
Enclose, Replicate, indexed/scatter assignment, and the scalar
conformability rules; plus three Dyalog notebooks (John Scholes's
Game of Life walkthrough; Boolean scans and reductions; grading).
BQN's documentation from source: Under `⌾` (the most important
page), Group `⊔`, Windows `↕`, Scan, Fold, Replicate, Order,
Depth, Rank, the leading-axis convention, and the
functional-programming rationale; plus the BQNcrate idiom table.
J: fragments only (the Josephus one-liner; the `parts.ijs`
run-length addon) — the J wiki was unreachable.*

## Reading rules for this genre

The three standing cautions, plus two specific to this corpus:

1. **What's out there is already out there.** The output is
   problems, never mechanisms. Doubly so this round: the brief
   rules the operator mechanism out in advance.
2. **Different core; bolting on clashes.** The family's core —
   whole arrays as the unit of computation, iteration implicit in
   pervasion and operators — is textual concision machinery. Where
   an idiom is admirable, the question is what program it computes
   and whether we can draw that program, not how to spell it.
3. **Maturity polish.** Dyalog's docs and BQN's docs are showcases;
   BQN's are also *argued* design documents by a single designer,
   which cuts both ways — reasoning is visible, and it defends its
   own choices.
4. **An idiom library is a special kind of corpus.** FinnAPL is
   accumulated working vocabulary — closer to field evidence than
   any documentation read so far (these are the phrases users kept
   needing), but with a structural bias: a *library* of 707
   memorized phrases exists precisely because the encodings do not
   reconstruct themselves from first principles. Density of a
   theme in the library measures what practitioners reach for
   *and* what the notation makes hard enough to need looking up —
   read both ways below. Frequencies still transfer to nothing
   outside the family.
5. **The brief.** Findings about the operator layer are read
   against the standing position: no higher-order surface. Where
   the family is right about a *capability*, its drawn form must
   expose values and flows, not take functions.

## The family's move, in a paragraph

Arrays are the only aggregate, and iteration is never written. Two
layers deliver that. **Pervasion**: scalar functions apply
"independently to corresponding pairs of simple scalars in their
arguments" (Dyalog), with scalar and singleton extension lifting
mismatched ranks — `1 2 + 3 4` is elementwise addition, no map
anywhere. **Operators**: second-order forms that turn functions
into iteration schemes — each/rank (`¨`, `⍤`, `˘`) apply at a
chosen depth or cell rank; reduce and scan (`/`, `\`) fold along
an axis; outer and inner product (`∘.f`, `f.g`) pair all or
corresponding combinations; Key (`⌸`) groups by key; Stencil
(`⌺`) and Windows (`↕`) run neighborhoods; At (`@`) and Under
(`⌾`) write results back into selected parts; Power (`⍣`)
iterates. Around the primitives sits an idiom culture: recognized
phrases (`X[⍋X]` sort, `⍋⍋X` rank, `+\` running total) function
as the language's real vocabulary. BQN, the family's most recent
member, revises the tradition self-consciously: everything is
first class, several APL operators are demoted to ordinary
functions ("it's strongly preferred to use functions, and not
modifiers, for array manipulation" — the Windows doc), and custom
orderings are deliberately *data*, not comparator functions.

## The material, against the record

### 1. The operator catalog, read as a coverage audit

The brief says the operator layer is not a mechanism to import.
Read instead as an *inventory* — what iteration vocabulary did
fifty years of array programming find necessary? — it becomes a
coverage audit of the record, and the audit is striking: **almost
every operator in the family names something the record has as a
drawn, first-order construct.**

| Family form | What it computes | Drawn form in the record |
|---|---|---|
| `¨`, `⍤`, `˘` (each, rank, cells) | apply at a depth/level | uncollect nesting (the level is drawn, not annotated) |
| pervasion, `1 2 + 3 4` | lockstep pairing | **gap — see §2** |
| `/` reduce (+ identity table) | fold an axis | collect (+ the operator-identity open) |
| `\` scan | running results | the register's running view / augment form |
| `∘.f` outer product | all pairs | Cross (`product-flows-design.md`) |
| `f.g` inner product | pair-then-fold | zip + collect composed (§2 again) |
| `⌸` Key, `⊔` Group | group by key | the keyed collect (collect-family round) |
| `⌺` Stencil, `↕` Windows, N-wise `/` | neighborhoods | window(k) / sliding split-when |
| `⊆` Partition, `⊂` Partitioned Enclose | mask-driven segments | split-when (boundary as data — §3) |
| `⍋` Grade | order as a permutation value | sort as configured block; order-by barrier |
| `@` At, indexed assignment, `⌾` Under | write back into a part | **focused update** (the row opened last round — §7) |
| `⍣` Power | iterate n times / to fixpoint | self-driven source + end-when |
| `◶` Choose (BQN) | dispatch on a computed index | the case split |

Two readings of this table, one in each direction. Toward
validation: the family's second-order layer is, item for item, the
record's first-order drawn structure — which is the brief's claim
made concrete. Their operators are how a *textual* language
encodes iteration vocabulary once it refuses loops; a drawn
language encodes the same vocabulary as visible structure, and the
uncollect's virtual value does the work of every `𝔽` operand slot
without a function ever being passed. Toward humility: everything
on that table that the record holds as *open* (keyed collect,
window, focused update, operator identities, zip) is something
this family shipped decades ago — the audit ranks our debts.

The genuinely higher-order residue is small and identifiable. BQN's
functional-programming doc argues for first-class functions
("the three-tier system has some obvious limitations… BQN removes
these by making every type first class") and its honest examples
are: folding over an *array of functions* (`{𝕎∘𝕏}´ ⋆‿-‿(×˜)`),
applying a list of functions to one argument, and dispatch tables
(`(2⊸|)◶⟨÷⟜2,1+3×⊢⟩` — a Collatz step choosing between two
computations by a computed index). The dispatch table is our case
split, drawn. The arrays-of-functions cases are real higher-order
programming — data-driven choice of *computation*, not value — and
they file where the record already keeps that question: the
functions/reuse row (late-bound operations; a wired provider *is*
the drawn form of "which computation applies here is data"). Note
also BQN's diagnosis of why APL never had first-class functions —
"probably syntax: there's no way to say that a function should be
used as the left argument to another function." Our reason is
different in kind — discoverability and reasoning, per the brief —
worth stating so the two positions aren't conflated: BQN removed a
syntactic obstacle; we are declining the semantics.

### 2. Pervasion — lockstep pairing is the family's ground floor, and our named gap

**Their approach.** The single most-used operation in the family is
not an operator at all: `1 2 + 3 4` pairs corresponding elements
of two arrays, by conformability rules stated once and used
everywhere ("dyadic scalar functions apply independently to
corresponding pairs of simple scalars in their arguments… if a
simple scalar corresponds to a non-scalar, the simple scalar is
replicated"). Everything leans on it: the blend idiom
`c+b×d-c` (choose per position by a mask — three aligned vectors
combined pointwise); inner product's very definition ("each item
is `f/x g¨y`" — pair, then fold); the mesh idioms
(`(X,Y)[⍋⍋G]` — merge two lists under a boolean control); BQNcrate
has a whole zip section (`x∾¨y` "join corresponding elements",
`⥊x1≍˘y1` interleave); Life's kernel (§9) sums nine same-shape
grids pointwise. Scalar extension is the same rule's degenerate
case: a lone value silently lifted into the pairing.

**Our approach.** The record's honest state: zip is "a note, not a
demand" (`translation-exercise.md` finding 10 — indices were
honest for the one sampled case), and the only zip in the record
is a *compile-level* stream primitive (the multi-parent zip of
`lazy-stream-placement-design.md`), not authoring vocabulary. Two
uncollects over two lists are *independent* — their product is
Cross — and nothing drawn says "these two walks are the same walk,
paired by position." This round upgrades the note to a demand: an
entire language family's ground floor is aligned pairing, and
programs as ordinary as blend, interleave, weighted average
(`Y+.×X`), and sort-one-by-another (§6) are all instances. The
natural home is the products row: **the aligned product is Cross's
sibling** — Cross pairs every firing with every firing (mutual
independence), zip pairs firing *i* with firing *i* (mutual
identity of extent), and the two Life readings below show one
program needing both. Scalar extension, read in our vocabulary, is
Incorporate's implicit costume — a value lifted into a flow
context by shape coincidence rather than by a drawn node; the
capability is confirmed, the implicitness is for the clash record
(a rank mismatch that happens to conform silently computes the
wrong program).

### 3. Masks — the case flow reified as data, and the flat encodings our constructs dissolve

**Their approach.** Boolean vectors are the family's control plane.
A condition produces a mask; the mask then drives everything:
filtering (`Y/X` compress, `⍸` where), counting (`+/X`),
zeroing-instead-of-removing (`Y×X`), leading-ones (`∧\`),
on-from-first-one (`∨\`), parity (`≠\` — the quoted-text idiom:
`≠\T∊'()'` turns delimiter positions into inside/outside regions),
first-of-group (`1,(1↓X)≠¯1↓X` — compare with shifted self),
group-ends, expand (`\`), mesh. Segmentation is a mask handed to
Partition (`(' '≠TEXT)⊆TEXT` splits on blanks) or Partitioned
Enclose (`0 0 1 0 0 1 0⊂'abcdefg'` cuts before each 1). And the
deepest cut: **segmented operations** — scan or fold *within*
mask-delimited segments — are a named genre in FinnAPL, and their
flat encodings are virtuoso index algebra: cumulative sums over
subvectors is
`+\Y-X\A-¯1↓0,A←X/+\¯1↓0,Y`; *cumulative maxima* over subvectors
is `Y[A⍳⌈\A←⍋A[⍋(+\X)[A←⍋Y]]]` — a grade of a grade of a
plus-scan, indexed back into itself. The Dyalog notebook teaches
partitioned-reverse the same way (`a[⌽⍒+\p]` — "if we downgrade
the plus-scan, the relative positions… are reversed, but the
positions within each partition stay in ascending order"), then
*benchmarks* the flat forms at 75–87% faster than the nested
(`¨`-over-partition) forms — the community maintains both a
readable encoding and a fast one, and they are different code.

**Our approach.** A mask is a *value-level photograph of a case
flow*: which firings of some walk satisfy P. The record's form
keeps that information *as* the flow — the case split's bundle,
attached to its walk by provenance, no same-length invariant to
maintain by discipline (nothing in APL checks that a mask belongs
to the vector it filters; length agreement is the programmer's
problem). The segmented-scan genre is precisely split-when + a
register on the inner flow — the composition
`variable-rate-consumption-design.md` already draws — and the
FinnAPL encodings are the strongest exhibit yet for the standing
assembly-language diagnosis: the drawn form *states* "running
maximum per segment"; the flat form is three grades and a scan
that must be looked up in a library of 707 phrases. That the
notebook's own material introduces a helper operator for the
pattern (`_P ← {∊⍺⍺¨⍺⊂⍵}` — "a partitioned-function-application
operator") is the family half-inventing split-when. Reading rule 4
cuts both ways here and should be said plainly: the idioms prove
the *demands* are real and everyday (running state per segment,
group boundaries by adjacency, parity regions), and the library's
existence prices the encoding. The mask algebra itself — combining
boundary conditions by shifting and comparing (`1»≠⟜«`,
`»⊸<`) — is adjacency vocabulary the drawn form gets from the
register/previous-firing read, one condition at a time, with the
shift direction visible as structure instead of a `»` vs `«`
convention.

### 4. Windows, Stencil, N-wise — window(k)'s design space, shipped three ways

**Their approach.** The family ships *three* surface forms of the
windowed computation. **N-wise reduce** (`3+/⍳4` → "(1+2+3)
(2+3+4)") fuses window and fold; a *negative* width reverses each
window before reducing; width 0 returns identity elements.
**Windows as value** (BQN `↕`): all slices as cells of a flat
array ("it doesn't add a layer of nesting… the slices have a
fixed size, so they fit together as cells"), including
2-dimensional windows (`2‿2↕` over a table); windowed reduction is
then ordinary code (`+˝˘3↕x`), and BQNcrate carries the fast
rewrites (rolling sum as difference-of-prefix-sums:
`i0(↓--⊸↓)0∾+`n`). **Stencil** (`⌺`): neighborhoods *centered* on
every element, padded at the edges, with the operand told, per
invocation, how much padding it received and on which side ("`f`
is invoked dyadically with a vector left argument indicating for
each axis the number of fill elements and on what side"); a
movement parameter gives size-and-step windows
(`{⊂⍵}⌺(⍪3 2)` → slices of size 3 stepping by 2).

**Our approach.** window(k) is a named candidate with its strongest
textual evidence already recorded; last round located it as the
fixed-size point of a (tumbling/sliding × condition/count) family.
This corpus fills in the design space with shipped parameters:
**step/movement** (Stencil's second row — window(k, step), whose
step=k point is fixed-length split-when, unifying the two);
**edge handling** as a first-class dimension — Stencil pads and
*tells the consumer about the padding*, N-wise truncates
(`(≠x)-k+1` windows), and the two are exactly the
unterminated-segment bit from the XQuery round appearing at both
edges of a symmetric construct (emit-partial-with-fill vs drop);
**2D windows** (both `⌺3 3` and `2‿2↕`) — the neighborhood over a
rank-2 structure, which lands on the products row (§9). The
fast-rewrite idioms (rolling sum via prefix sums, rolling min via
the doubling trick) are compile-level equivalences between
window-collects and scans — noted for whatever pass eventually
optimizes window(k), not for the surface.

### 5. Key and Group — the keyed collect's third consecutive round

**Their approach.** Dyalog `⌸`: "applies the function `f` to each
unique key in `X` and the major cells of `Y` having that key…
Key is similar to the GROUP BY clause in SQL" — and, notably,
"the elements of `R` appear in the order in which they first
appear" (first-appearance order). BQN `⊔` decomposes grouping into
two pieces: a *classification* step producing target indices
(group-by-key is `co⊐⊸⊔ln` — Classify/Index-of computes each
cell's bucket number), and a *placement* step scattering cells
into buckets — with index `¯1` meaning "drop this cell" (partial
grouping) and an optional extra element forcing a minimum result
length (empty trailing groups). "If every element of `𝕨` is a
list in ascending order with no ¯1s, we have `𝕩≡∾𝕨⊔𝕩`, that is,
Join is the inverse of partitioning."

**Our approach.** Three consecutive rounds have now handed the
collect family's round the same construct with different details,
and the details have started to disagree in instructive ways.
**Group output order**: Dyalog says first-appearance, jq says
sorted-by-key, XQuery says implementation-dependent — three
shipped answers to a question the keyed collect will have to
decide (and provenance gives us a natural fourth candidate:
first-appearance is the only one of the three that *is* the
subject flow's own order). **The decomposition**: BQN's
classify-then-place splits the keyed collect into a per-firing key
computation (ordinary value code) and a placement primitive —
evidence that the collect's key extraction wants to be ordinary
drawn computation on the element, not node configuration, which
is also what the sort material says (§6). **Partiality**: the
`¯1`-drop is partial engagement arriving in the keyed world
(matching the partial collect's stance), and the minimum-length
extension is the empty-groups question (split-when open question
2's cousin) surfacing as API. All to the collect-family round;
the group-as-flows vs operator-merge fork from the XQuery/jq
round stands unchanged (Key's `f` per group is the fused form;
`{⊂⍵}⌸` — enclose per group — is group-as-values).

### 6. Grade — ordering decomposed into data, and the comparator dissolved

**Their approach.** "There is no sort primitive in APL." `⍋Y`
returns the *permutation that would sort* — a value — and the
idiom culture composes it: sort is `X[⍋X]`; **sort-one-by-another
is `Y[⍋X]`**; rank is `⍋⍋X` ("the positions each element would
occupy after sorting"); inverting a permutation is grading it
(`⍋X`); merging two lists under a boolean control is
`(X,Y)[⍋⍋G]`; collation is data too (dyadic grade:
`X⍋Y ←→ ⍋X⍳Y` — order defined by position in a collation array,
the vowels-first example). BQN states the stance outright: "You
can't provide a custom ordering function to Sort… Instead, build
another array that will sort in the order you want… Then Grade
it, and use the result to select from the original array."

**Our approach.** This is the brief's position, discovered
independently inside the family itself: where other languages
configure sorting with a comparator *function*, the array
tradition configures it with *data* — a key array, a collation
array — and gets composition for free (rank, mesh, inversion are
index arithmetic on the permutation value). That is exactly
`configuration-scopes.md`'s sort example (the key extracted per
element by ordinary drawn code inside the sort's context, no
function passed), now with fifty years of field practice behind
it. Two further notes for the record. The permutation-as-value is
a *provenance artifact made data* — "where each firing lands in
the reordered flow" — and applying it to a second array is, once
again, aligned pairing (§2): `Y[⍋X]` zips Y with the graded
positions of X. And `⍋⍋` (rank) is a derived output of sorting
that XQuery spelled `count $rank` after `order by` — two
traditions independently deriving "position after reorder" as
vocabulary; noted for whatever round owns the sort block's ports.

### 7. At, scatter, Under — the focused-update row's decisive round

The row opened one round ago with jq's paths and XQuery's Update
Facility as its two witnesses. This family supplies the third,
fourth, and fifth — and more than witnesses, structure.

**Indexed and scatter assignment.** `A[2 3]←10 ⋄ A` — and the
Dyalog reference states a *conflict rule*: "The last-most element
of `Y` is assigned when an index is repeated in `I`" — multi-locus
updates with colliding loci get a declared resolution, the same
question the pending update list answers with compatibility rules.
FinnAPL's scatter idioms (build a lookup table by
`A←9999⍴0 ⋄ A[X]←1`; mesh by `A[⍋G]←A←Y,X`) show scatter as
everyday construction vocabulary, not just mutation.

**At (`@`).** `(10 20@2 4)⍳5`, `÷@2 4 ⍳5`, `0@(2∘|)⍳5` — replace
or transform *at* an index array or *at* a mask-producing
function; the functional (non-mutating) form of the same shape.

**Structural Under (`⌾`) — the row's semantic law, found shipped.**
BQN's Under doc is the most complete design statement any language
in this genre has made about focused update:

- **The law.** `(𝔾 𝕨𝔽⌾𝔾 𝕩) ≡ 𝕨𝔽○𝔾 𝕩` — reading the selected part
  *after* the update equals computing on the part read *before*
  it; "other parts are defined to be the same as it was in `𝕩`."
  That pair of sentences is the specification the focused-update
  row was going to have to invent: the update commutes with the
  selection, and the frame is untouched.
- **The well-formedness condition.** The selection `𝔾` must be a
  *structural function* — "it has to be based on the structure of
  its argument… and not on the values of atoms in it." Selecting
  by value (`10⊸+⌾((<⟜5)⊸/)`) is rejected; the sanctioned form
  computes the mask from a copy *first* and then uses it
  structurally (`{10⊸+⌾((𝕩<5)⊸/)𝕩}`). This is jq's paths-as-data
  independently rediscovered as a *lawfulness requirement*: the
  loci must be fixed as data before the write-back, or the
  round-trip law fails. The drawn form inherits the condition
  directly — a locus is a provenance witness computed before the
  update, never a live value-dependent probe.
- **The lens identification, made by the doc itself.** "Structural
  Under is the same concept as a (lawful) lens in functional
  programming… BQN's restriction to structural functions makes an
  implicit setter work" — selection and update share one
  vocabulary (jq's deepest win, now stated as a theorem-shaped
  claim: the getter *determines* the setter when it is
  structural).
- **Update under a derived view.** `F⌾⥊` ("handle array `y`
  temporarily as a list"), `F⌾⍉` (act on columns by working on
  rows), `∧`⌾⌽` (scan from the end by reversing, scanning,
  un-reversing) — the "part" generalizes from a sub-locus to a
  *reversible re-presentation*, compute in the view, write back
  through it. That is this record's derived-views instinct
  (principle 6) surfacing at the value level, and it subsumes the
  computational Under (`𝔾⁼∘𝔽○𝔾` — J's `1&|.&.#:` Josephus
  one-liner: rotate under binary encoding) whose inverse-inference
  half stays in the clash record.
- **A dissolution.** BQN *removed* APL's Expand primitive: "An
  alternative to Expand is to use Replicate with structural Under
  to insert values into an array of fills" (`x⊣⌾(b1⊸/)y` — blend
  by mask). A shipped language reducing its primitive count by
  recognizing focused update as the more general construct is the
  strongest possible evidence that the construct is load-bearing.

BQNcrate's Under section confirms the everyday-ness: replace first
cell, apply to last cell, replace by mask, set a matrix diagonal,
swap first and last, sort each column via `⌾⍉` — small, constant
uses, not exotica. The row keeps I 5 (nothing worked *in our
vocabulary* yet) but its remaining list now has the law, the
structural-selection condition, the derived-view generalization,
and the conflict-rule question, each with a shipped citation.

### 8. The identity table — the operator-identity question, answered by a catalog

**Their approach.** Dyalog's Reduce page carries a 23-row identity
table (`+`→0, `×`→1, `⌊`→M, `∧`→1, `∪`→⍬, …): reducing an empty
axis returns the identity, or DOMAIN ERROR for functions that
lack one; N-wise reduce with width 0 returns identities too. BQN
sharpens the semantics: Fold "tries to derive an 'identity
value'… if the argument array is empty," *or* the programmer
supplies an initial value as `𝕨`; and **Scan never needs one** —
"it never depends on `𝔽`'s identity value, because scanning over
an empty array simply returns that array."

**Our approach.** The operator-identities item (loop-carried state
row, joint with the collect family's spelling round) has been
accumulating hand-rolled-monoid sightings since the surveys; this
is the first *catalog* — a shipped enumeration of which operators
carry identities and what they are. And BQN's split hands the item
its sharpest framing yet: the identity question is exactly and
only the **empty-collect question** (what does a fold-collect of
zero firings yield?); an initial-value port dissolves it, and the
running view (scan) never asks it. Which collects demand an
identity, which take a seed, and which inherit emptiness is now a
three-way structure with shipped exemplars of each.

### 9. The showpieces — where the drawn vocabulary struggles, honestly

The brief's direct question. Worked against the corpus's
best-known programs:

**Life (the Scholes construction).** `1 0 ¯1 ∘.⊖ 1 0 ¯1 ⌽¨ ⊂R`
builds nine shifted copies of the board (outer product of row- and
column-rotations), `+/ +/` sums them pointwise, then the rule is
pervasive arithmetic (`3 4 = …`, `∧`, `∨.∧`). In drawn
vocabulary: the nine offsets are Cross (two three-element opens —
comfortable); each rotation is a whole-value App (comfortable);
but the *pointwise sum of nine same-shape grids* is aligned
pairing again — a zip across the collected offset flow, at rank 2.
Life needs both products at once: Cross to enumerate the
neighborhood, zip to overlay it. The honest verdict: drawable
only after the aligned product exists, and clumsy at rank 2 until
the products row's open questions (n-ary, axis handling) are
worked. This is the round's sharpest "struggles to represent
naturally" exhibit, and it localizes the struggle precisely: not
iteration, not grouping, not state — *alignment and rank-2
structure*.

**Quoted-text extraction.** `≠\T∊'()'` — parity scan turning
delimiter positions into in/out regions, then compress. Drawn:
a register toggling on delimiter firings, its state joined as a
case flow to filter the walk — natural, arguably clearer (the
inclusive/exclusive variants that cost the notebook two distinct
compositions, `(~∧≠\)` vs `(⊢∨≠\)`, are our boundary-destination
bit as configuration). No struggle.

**Progressive index-of** (match without replacement, FinnAPL 1:
`((⍴X)⍴⍋⍋X⍳X,Y)⍳(⍴Y)⍴⍋⍋X⍳Y,X`, BQN's `⊒`). Stateful matching
where each key consumes its match: in drawn vocabulary a keyed
partition with a per-lane register (consume the next unclaimed
occurrence). The flat form is famous precisely for being
unreadable; ours states the program. No struggle — the contrast
favors the drawn form.

**Run-length encoding.** Starts by shifted-compare
(`1,(1↓X)≠¯1↓X`), lengths by indexing the starts, decode by `X/Y`
(replicate *is* RLE-decode, per the BQN doc's own reading).
Drawn: adjacency split-when (boundary = "differs from previous"),
per-segment count collect; decode is an uncollect of counts with
an inner repeat — all owned. No struggle.

**The residue that does strain**, gathered: (a) **aligned
pairing** — pervasive there, a note here; upgraded by this round
(§2). (b) **Rank-2 structure** — 2D windows, transposes, diagonal
group-keys (`(+⌜´·↕¨∘≢)⊸⊔` anti-diagonals — drawable as Cross +
keyed collect on i+j, but nested-list rank-2 is heavy); files as
evidence on the products row's existing questions 3–5, not a new
row. (c) **Permutation application** (`Y[⍋X]`) — drawable via an
index walk, but it is index-flavored in our vocabulary too; the
family's form is honest about that rather than better. Everything
else read this round maps.

## Findings

**The headline, for direction.** The operator catalog audit
(finding 1) is the round's answer to its brief: the family's
second-order layer names, item for item, the record's first-order
drawn constructs — validation that flows-exposing-virtual-values
covers what higher-order functions are *for* here, with a small
genuinely-higher-order residue already filed on the functions
row. The audit also ranks debts: everything the family shipped
that we hold open (keyed collect, window, focused update,
identities, zip) got new structure this round, and the one place
the showpieces genuinely strain the drawn vocabulary — aligned
pairing, especially at rank 2 — is promoted from a note to a
demand.

**Finding 1 — the operator inventory maps onto the drawn-construct
inventory.** Each/rank → uncollect nesting; reduce/scan →
collect/register; outer product → Cross; Key/Group → keyed
collect; Stencil/Windows → window(k); Partition → split-when;
Grade → sort-as-data; At/Under → focused update; Power → iterate;
Choose → case split (§1's table). The brief validated
structurally, with the residue named: arrays-of-functions and
computed dispatch over *computations* file to the functions row's
late-bound-operations demand; BQN's pro-first-class rationale is
recorded so the positions aren't conflated (they fixed syntax; we
decline the semantics).

**Finding 2 — aligned pairing (zip) is promoted from note to
demand.** The family's ground floor is lockstep combination
(pervasion, blend, mesh, inner product, interleave), and the
showpiece audit localizes our only real representation struggle
there (Life needs Cross *and* zip at once). The aligned product is
Cross's sibling — same walk paired by position rather than
independent walks paired exhaustively — and the compile already
owns a zip primitive at the stream level, so the gap is authoring
vocabulary, not runtime. Owner: the products row
(`product-flows-design.md`), beside its n-ary and axis questions,
which the rank-2 evidence (2D windows, transposes, Life) also
feeds. Scalar extension is Incorporate's implicit costume —
capability confirmed, implicitness clashed.

**Finding 3 — masks are case flows reified as data; the segmented
idioms are the assembly-language exhibit of the record's life.**
The FinnAPL segmented-scan genre (three grades and a scan for
"running maximum per segment") and the notebook's flat-vs-nested
benchmark culture are what split-when + register dissolve; the
notebook's own `_P` helper operator is the family half-inventing
split-when. The mask's same-length-by-discipline invariant is
carried structurally by provenance in the drawn form. Idiom-library
epistemology recorded (reading rule 4): the 707 phrases prove the
demands are everyday *and* price the encoding.

**Finding 4 — window(k)'s design space arrives shipped.** Three
surfaces (N-wise reduce, windows-as-value, centered Stencil);
parameters sighted: step/movement (step=k unifies with
fixed-length split-when), **edge handling as a real dimension**
(Stencil pads and reports the padding per-invocation; N-wise
truncates — the XQuery round's unterminated-segment bit at both
edges), per-window reversal as configuration (negative width), 2D
windows. The prefix-sum rewrites are compile equivalences, not
surface. Owner: the variable-rate row's window(k) mapping.

**Finding 5 — the keyed collect, third consecutive round: order,
decomposition, partiality.** Group output order now has three
shipped answers (first-appearance / sorted / unspecified) —
a decision the collect-family round must make, with provenance
favoring first-appearance. BQN's classify-then-place decomposition
argues the key extraction is ordinary drawn computation, not node
configuration; `¯1`-drop is keyed partial engagement; minimum
length is the empty-groups question as API.

**Finding 6 — ordering is data, not a comparator: the family
agrees with the brief.** No sort primitive; the permutation is a
value; sort-by, rank (`⍋⍋`), inversion, mesh, and collation are
index arithmetic on it; BQN explicitly refuses comparator
functions. Confirms `configuration-scopes.md`'s drawn key
extraction, with two notes onward: the permutation value is a
provenance artifact made data, and applying it to a second array
is aligned pairing (finding 2 again). Rank-after-reorder now has
two independent derivations (⍋⍋; XQuery's `count`) — a candidate
derived port on the sort block.

**Finding 7 — focused update: the row's structure round.** From
one round old to fully furnished: the commuting law
(`(𝔾 update) ≡ compute∘𝔾`, frame untouched), the well-formedness
condition (selection must be structural — loci fixed as data
before write-back; value-dependent selection sanctioned only by
first materializing the mask), the lens identification made by
the shipped doc itself (the structural getter determines the
setter), the derived-view generalization (`⌾⥊`, `⌾⍉`, `⌾⌽` —
compute in a reversible re-presentation and write back), the
multi-locus conflict rule (Dyalog's "last-most is assigned"), and
a primitive-count dissolution (BQN removing Expand in favor of
Under). I stays 5 — nothing worked in our vocabulary — but the
row's remaining list is now a worked-round agenda rather than a
blank page.

**Finding 8 — the identity question is the empty-collect
question.** A shipped 23-operator identity catalog (Dyalog);
BQN's three-way split — derive the identity (empty fold), take a
seed (initial-value port), or never need one (scan; empty in,
empty out). Hands the operator-identities item its framing and
its catalog. Owner: loop-carried state row, joint with the
collect family.

**Finding 9 — confirmations, briefly.** (a) The Scholes Life
walkthrough is Cross + whole-value ops + pervasive arithmetic —
the record's reading of it needs no new iteration constructs,
only findings 2's products. (b) Power (`⍣`) is the bounded/
to-fixpoint iterate — another sighting for the self-driven source
(and its fixpoint form nods at the saturation row). (c) Nub
idioms (`(X⍳X)=⍳⍴X` and friends) are set-collect sightings, again.
(d) Partitioned Enclose's drop-before-first-divider and
Partition's drop-zeros are gap-tolerant segmentation, matching
the XQuery round's variant. (e) The quoted-text and RLE programs
map cleanly (register toggle; adjacency split-when) — the drawn
forms state what the idioms encode.

**Finding 10 — what not to import (the clash record).** (a) *The
operator/tacit layer itself* — per the brief; even BQN's docs
steer array manipulation toward functions-not-modifiers, and the
idiom library is the encoding cost made institutional. (b)
*Computational Under's inverse inference* — `𝔾⁼` conjured by the
implementation (Josephus's `&.#:` is delightful and unreadable);
the structural half survives as focused update, the magic-inverse
half does not. (c) *Meaning by shape coincidence* — scalar and
singleton extension silently lifting mismatched operands; a
conforming-by-accident pair computes the wrong program with no
drawn trace. (d) *The ambient index origin* (`⎕IO`) — a global
setting changing every index's meaning: the invisible-wire genre.
(e) *Mask/data alignment by discipline* — the same-length
invariant nothing checks. (f) *Idiom-recognition compilation* —
performance by phrase-matching (the flat-vs-nested benchmark gap)
rewards exactly the encodings the drawn form exists to dissolve;
our equivalences (window-as-scan-difference) belong in compile
passes, not the surface.

## What this round changes in `open-problems.md`

- **Products row**: gains the **aligned product (zip)** as a named
  demand — Cross's positional sibling, upgraded from the
  translation exercise's note by the family's ground-floor
  evidence and the Life localization; the rank-2 evidence (2D
  windows, transpose-heavy idioms) attaches to existing questions
  3–5. Scores unchanged (I 3, W 3) — the row grew a demand, not a
  worked answer.
- **Focused update row**: the structure note (finding 7) — law,
  structural-selection condition, derived-view generalization,
  conflict rule, the Expand dissolution. I 5 / W 3 held; the
  frequency sample still decides W.
- **Variable-rate row**: window(k) design-space note (finding 4);
  gap-tolerant confirmation (finding 9d). Scores unchanged.
- **Loop-carried state row**: the identity catalog and the
  empty-collect framing (finding 8); segmented-scan sightings
  (finding 3). Scores unchanged.
- **Functions/reuse row**: the genuinely-higher-order residue
  (arrays of functions, dispatch-over-computations) filed on the
  late-bound-operations demand; BQN's first-class rationale
  recorded as the position we decline. Scores unchanged.
- **Collect family (joint items)**: group order's three shipped
  answers; classify-then-place; keyed partiality (finding 5).
  Tracked on the loop-carried-state and Tier-4 rows as before.

## Next rounds of this genre

Remaining from the standing list: the **beginner-first round**
(Scratch/HyperCard lineage — the discoverability bar as the whole
language) and the **reactive-library round** (Rx/signals read
from application code, method closer to the surveys). This round
suggests a variant worth holding: the FinnAPL library was the
genre's first *idiom-library* corpus and its double reading
(demands proven, encoding priced) worked well — the same reading
applied to a jq-oneliner collection or a pandas-recipes corpus
would triangulate the everyday-transformation vocabulary from a
third direction.
