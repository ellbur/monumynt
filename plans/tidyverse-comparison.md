# Learning from other languages: the tidyverse (dplyr, tidyr, purrr)

This is one of the "learning from other languages" comparison studies: read
another language's real programs against how this design (referred to below as
*the record* — the accumulated design docs and their tracked agenda in
`open-problems.md`) approaches the same problems, extract *problems* — programs
that must be writable, demands with evidence — never mechanisms to copy, and
reweight the agenda. A study **decides nothing on its own**; demands are handed
to the docs that own each topic, and design happens in the design
conversations.

**The question this study answers.** The record has given tabular data no
thought at all. The cheap answer is that a table is a list of structs. But a
table has two axes that are not fully independent — it has columns, and each
row has all the columns, and each column has all the rows — and that coupling
may produce iteration patterns a (possibly ragged) list of lists never
exhibits. So: is a table more than a list of structs? The tidyverse is the
corpus because it is the most deliberately designed table vocabulary in wide
use — three packages, one data model, a decade of revisions.

**Corpus.** dplyr: the package vignettes read in full from source — `dplyr.Rmd`
(the verb taxonomy), `grouping.Rmd`, `rowwise.Rmd`, `colwise.Rmd` (across),
`window-functions.Rmd` (on the Lahman batting data), `two-table.Rmd` (joins),
`programming.Rmd`, plus `base.Rmd` for base-R translations. tidyr:
`tidy-data.Rmd` (the theory paper as vignette), `pivot.Rmd` (including the
pivot-spec section), `rectangle.Rmd`, `nest.Rmd`, plus the roxygen examples
for `complete`/`expand`/`fill`/`unite`/`separate`. purrr: all three vignettes
(`base.Rmd`, `purrr.Rmd`, `other-langs.Rmd`) plus the roxygen reference
examples from `R/*.R` (`map2`, `pmap`, `imap`, `reduce`, `accumulate`,
`safely`, `detect`, `keep`, `modify`, `list_transpose`, `list_flatten`,
`map_depth`) — purrr's vignettes are thin and its example corpus lives in the
reference docs.

## Reading rules for this study

The three standing cautions, plus three for this corpus:

1. **What's out there is already out there.** The output is problems —
   programs that must be writable, demands with evidence — never mechanisms.
   Duplicating dplyr would produce dplyr.
2. **Maturity polish.** Vignettes are the authors' showcase, maximally
   curated; frequencies mean nothing. What partly compensates: the tidyverse
   is unusually candid in its own docs (a design called "possibly a mistake,
   but we're stuck with it"; whole sections on why a prior approach failed),
   and constructs *added late* — `rowwise` re-added after deprecation,
   `across` arriving years into the package — are field reports that the
   original vocabulary hit a wall. Read those hardest.
3. **The ergonomics are inverted, so difficulty does not transfer.** R is
   column-major: "dplyr, and R in general, are particularly well suited to
   performing operations over columns, and performing operations over rows is
   much harder" (`rowwise.Rmd`). The record's ground floor is the opposite —
   per-firing computation is the default, whole-column operations are
   collects. So what is hard there may be free here and vice versa; each of
   their bolted-on modes marks where *their* default axis failed, not where
   ours would.
4. **Weak-typing compensation is not design evidence.** A visible fraction of
   purrr exists to patch R: the typed output suffixes (`map_int`, `map_chr`)
   exist because `sapply` auto-simplifies unpredictably; `safely`'s
   `{result, error}` product-with-invariant exists because R has no sum types.
   Machinery whose job is to restore guarantees the record's wire sorts
   already give is read as confirmation, not as a construct to import.
5. **Domain-bound corpus.** Interactive data analysis overweights reshaping,
   aggregation, and modelling loops; long-running state, concurrency, effects,
   and protocol code are nearly absent. Their absence is domain fact, not
   evidence of unimportance.

## The three packages, in a paragraph each

**dplyr.** A verb algebra over one value, the data frame, organized around the
table's axes: verbs over **rows** (`filter`, `slice`, `arrange`), over
**columns** (`select`, `mutate`, `rename`, `relocate`), over **groups of rows**
(`summarise`). "At the most basic level, you can only alter a tidy data frame
in five useful ways: reorder the rows (`arrange`), pick observations and
variables of interest (`filter` and `select`), add new variables that are
functions of existing variables (`mutate`), or collapse many values to a
summary (`summarise`)" (`dplyr.Rmd`). `group_by` is inert metadata — "it just
changes how the other verbs work" — and under it every verb becomes per-group.
Expressions inside verbs mix altitudes freely: `mutate(standard_mass = mass -
mean(mass))` combines a per-row value with a whole-group fold in one formula.
Two-table verbs (joins) and window functions (`lag`, `min_rank`, `cumsum`)
complete the algebra.

**tidyr.** The data-shape half. Its theory: "A dataset is a collection of
values. Every value belongs to a variable and an observation"; tidy means each
variable is a column, each observation a row, each value a cell — "this is
Codd's 3rd normal form, but with the constraints framed in statistical
language" (`tidy-data.Rmd`). Everything else is conversion machinery between
that form and five named messy patterns: `pivot_longer`/`pivot_wider` move
data between column names and cell values; `separate`/`unite` split and glue
within cells; `nest`/`unnest` move whole sub-tables in and out of single
cells; `complete`/`expand` manufacture rows from cross products of column
value-sets; `fill` carries values along row order. The pivot machinery is
self-describing: a reshape is specified by a **spec that is itself a table**,
and the same spec drives both directions.

**purrr.** The list half: a combinator matrix of **input arity** (`map` /
`map2` / `pmap` / `imap`) × **output type** (list, `_int`, `_dbl`, `_chr`,
`walk` for effects), plus folds (`reduce`, `accumulate`, with `done()` for
early exit), search (`detect`, `every`, `head_while`), filtering
(`keep`/`discard`), layout conversion (`list_transpose`, `list_flatten`),
error capture (`safely`, `possibly`), and shape-preserving update
(`modify_if`, `modify_at`, `modify_in`). The bridge to tables is documented at
the exact point of interest here: "A data frame is an important special case
of `.l`. It will cause `.f` to be called once for each row" (`pmap`) — a data
frame *is* a named list of equal-length columns, and `pmap` is its row-wise
reading.

## The material, against the record

### 1. The data frame is the multi-wire flow at rest

**Their approach.** The tidyverse's central value is k named, typed,
equal-length columns with scalar broadcast — and the docs treat the row view
and the column view as two readings of the same thing. `pmap.R` shows one
computation three ways: `pmin(df$x, df$y)` (columns as separate vectors) ≡
`map2_dbl(df$x, df$y, min)` (an explicit zip) ≡ `pmap_dbl(df, min)` (the table
read row-wise). `map` over a data frame iterates *columns* (`mtcars |>
map_dbl(sum)` sums each column); `pmap` and `rowwise()` iterate rows;
`list_transpose` converts a list of structs to a struct of lists and back
(turning a list-of-lists "inside-out"). The alignment law is stated as
recycling discipline: "Vectors of length 1 will be recycled to any length;
**all other elements must have the same length**" (`pmap`) — purrr
deliberately *tightened* R's general recycling to scalar-or-error. And
rectangling's step 0 wraps even a bare list into a one-column table before
doing anything else, "so that everything is tracked together" (`rectangle.Rmd`)
— the table is the *alignment device* that keeps derived columns index-locked
to their source.

**Our approach.** This is the tuple-stream finding one step further. Earlier in
the genre, XQuery's FLWOR tuple stream — named multi-wire bindings flowing
through clause barriers — was found to be the closest textual analog of the
drawn model; dplyr is a third shipped member of that family (`mutate` widens
the tuple like `let`, `filter` is `where`, `arrange` is `order by`,
`group_by`+`summarise` is `group by`). What dplyr adds that XQuery never had:
**the tuple stream reified as a value.** A data frame is what you get when a
multi-wire flow comes to rest — k value wires become k columns, n firings
become n rows, and the alignment that was structural in the flow (all wires
fire together) is retained in the value (all columns have the same extent,
cell i of each column belonging to the same firing).

In the record's vocabulary: **a table is k lists that remember they were
collected from the same walk.** That directly answers the study's motivating
question. A table *is* more than a list of structs, and the "more" is exactly
the two-axis coupling the design conversation intuited — but the two axes are
not symmetric mysteries. The column axis is the *wire* axis (drawn structure —
names, types, one per conceptual variable) and the row axis is the *firing*
axis (runtime extent). Their non-independence is rectangularity: every firing
carries every wire. A ragged list of lists has no such coupling, which is why
it exhibits none of the patterns below.

The record's current state, honestly: the *flow* side of this is the aligned
product (zip — pairing flows of the same extent by position), already a demand
on the products row after the APL study, and given a second shipped witness by
Zig's multi-object `for`. But at *rest* the record has nothing. k sibling
collects of one walk produce k lists whose alignment is real — same extent by
construction — and remembered nowhere. Any later consumer that wants to walk
them in step is back to zip plus a discipline-maintained invariant, exactly the
mask/data-alignment-by-discipline clash recorded against APL. The tidyverse's
entire ecosystem is evidence for the missing half: the aligned product's
**value form** — the collect that takes several wires of one flow at one
barrier and produces a value that keeps their correspondence, whose uncollect
gives the wires back. The multi-wire collect and the table are one construct
seen from both sides.

Three warts in the corpus argue the wire form specifically — that the table
should open into *wires*, not into row-structs:

- **The row-splat wart.** `pmap(df, f)` splats every column into `f`'s
  arguments, so a consumer of two columns from a three-column table errors
  with "unused argument" until the author writes `function(x, y, ...)` to
  absorb the unused columns. On wires, an unused column is an unconnected port.
- **The arity matrix.** map/map2/pmap × typed suffixes is a combinatorial
  family whose reason for existence is that aligned inputs arrive as separate
  loose values. dplyr's own history documents the cost: they tried teaching
  row-wise work via purrr and retreated — "this was challenging because you
  needed to pick a map function based on the number of arguments that were
  varying and the type of result" (`rowwise.Rmd`) — re-adding `rowwise()` so
  the table itself carries the alignment. The whole matrix collapses to one
  uncollect when the aligned wires are a drawn fact.
- **Suffix disambiguation.** Joins auto-rename colliding columns `.x`/`.y` —
  the one-namespace cost of packing all wires into a single value's field set.
  Wires don't collide; names are labels on wires, not lookup keys.

One more datum for the same row: `reduce2`'s second input is deliberately **one
element shorter** than its first — values aligned with the *gaps between*
firings ("per-edge"), used for separators
(`reduce2(letters[1:4], c("-", ".", "-"), ...)`). Alignment targets are not
only firing-to-firing; the edge between consecutive firings is a distinct,
shippable alignment target — adjacent to the register/previous-firing
vocabulary and the window family.

### 2. The broadcast-back — a collect consumed by a re-walk of its own source

**Their approach.** dplyr's single most distinctive expression shape mixes
altitudes: a per-row value combined elementwise with a fold of the whole
column.

```r
starwars |> mutate(standard_mass = mass - mean(mass, na.rm = TRUE))
players |> mutate(G_z = (G - mean(G)) / sd(G))       # grouped: per player
players |> filter(G > mean(G))                        # keep above-average years
by_species |> filter(height == max(height))           # tallest per species
```

The window-functions vignette names the family "recycled aggregates" and
defines the genus: an aggregation function takes n inputs and returns one
value, but "a window function returns n values. The output of a window
function depends on all its input values." Under `group_by` every instance
becomes per-group: fold the group, broadcast the result back to the group's
own rows, combine elementwise. The base-R rendering makes the machinery
visible: `ave(x, g, FUN = mean)` — apply f per group, stretch the result back
to row shape.

**Our approach.** Read as a flow, the shape looks alarming — a collect's output
consumed *per-firing of the flow it collected*, which inside one walk is time
travel (the collect completes only when the walk ends). But the alarm
dissolves on the value side: lists are values, walks are cheap, and the drawn
form is **two walks of the same list** — uncollect once, collect the mean;
uncollect again, the mean now available per-firing as an ordinary ancestor
value (provenance's prefix rule; no transport needed); combine and collect.
dplyr's one-formula rendering is a fusion of that two-walk program, and its own
implementation (a whole-column vectorized pass for the fold, another for the
combination) *is* the two walks.

What the shape genuinely demands, and where it lands:

- **Re-walkability as the everyday case.** z-scores, proportions of group
  totals, `x == max(x)`, above-average filters — this is the corpus's most
  common composite. The record's cost for it is one extra uncollect of an
  existing value; acceptable, but the pattern deserves a place in the collect
  family's worked examples so the drawn form is established, and so nobody
  re-invents a within-walk broadcast that would violate no-time-travel.
- **Under grouping, the group must be a value.** The per-group version needs
  each group re-walked, which means each lane of a keyed partition must be
  collectable to a sub-list and re-opened. The group-as-flows form (from the
  XQuery study) already says non-grouping wires become per-group flows; this
  study adds that the per-group *value* (the collected sub-list) is
  load-bearing, not a convenience — the broadcast-back is only drawable through
  it. dplyr agrees from the other side: `nest_by()` reifies each group as a
  table-valued cell, and the vignettes treat grouped-verbs and nest-then-map as
  interchangeable strategies for the same problems.

### 3. The keyed partition has two readouts — collapse and pass-through

**Their approach.** Under one `group_by`, dplyr's verbs split into two families
by output cardinality. `summarise` **collapses**: one row per group, output
schema literally the keys plus the aggregates ("it starts from
`group_keys()`, adding summary variables to the right hand side",
`grouping.Rmd`). `mutate` and `filter` **pass through**: same rows in, same
rows out, in the original order — the per-group computation's results flow back
to the rows that produced them ("A grouped `filter()` effectively does a
`mutate()` to generate a logical variable, and then only keeps the rows where
the variable is TRUE"). A third, group-level readout drops whole partitions
(`filter_out(n() == 1)` — fold each group to a bool, keep or drop the entire
group).

And grouping is a **stack**: `group_by(sex, gender) |> summarise(n = n())`
leaves the result still grouped by `sex` — summarise pops exactly one level by
default (`.groups = "drop_last"`, configurable) so a second summarise folds the
next level out.

**Our approach.** The keyed-collect agenda (three prior studies of evidence —
Flix's operator-merge, XQuery/jq's group-as-flows, BQN's classify-then-place)
has so far accumulated *collapse* readouts only — one output per group, however
formed. This corpus ships the readout the row is missing: **pass-through**. The
structural analogy is exact and already in the record's vocabulary. A keyed
partition is a bundle with data-determined cells, and a bundle's exhaustive
collect produces one value per *parent firing* — the case collect. dplyr's
grouped `mutate` is that collect on the keyed bundle: every parent firing
landed in exactly one lane; a per-firing value computed in the lane rides back
to the parent walk, in original order by provenance. Grouped `filter` is the
same readout feeding a keep/drop. So the keyed partition arrives with the same
two collects the case bundle already has — the per-group collapse (summarise;
the keyed collect proper) and the per-firing exhaustive collect (mutate; the
case collect generalized to data-determined cells) — plus the group-level
engagement (drop whole lanes) that partial-collect vocabulary already frames.
Handed to the collect family's round as structure: the two readouts are one
partition barrier consumed two ways, not two constructs.

The group stack is a confirmation with a shipped detail: nested uncollects
popped one collect at a time is exactly drawn nesting (an uncollect inside an
uncollect, collects peeling inner levels first), and `.groups =
"keep"/"drop"/"drop_last"` is the "how many levels does this collect close"
choice as API. The grouped-`arrange` asymmetry (ignores groups unless
`.by_group = TRUE`) and `select` silently retaining key columns ("This design
is possibly a mistake, but we're stuck with it for now") go to the clash record
(§10): they are the costs of grouping as an ambient mode rather than drawn
structure.

### 4. The pivots — data crossing between the schema axis and the value axis

**Their approach.** tidyr's theory names five messy patterns, and the first is
the archetype: **column headers are values, not variable names**.
`pivot_longer` repairs it:

```r
relig_income |>
  pivot_longer(cols = !religion, names_to = "income", values_to = "count")
```

k selected column *names* become k *values* of one new column; n rows × k
columns become (n·k) rows × 2 columns; untouched id columns replicate per
firing. The names carry typed payloads (`names_transform = as.integer` parses
`"wk3"` into `3`; `names_pattern = "new_?(.*)_(.)(.*)"` factors one name into
three data columns — the column axis was a flattened three-dimensional index).
The `.value` sentinel factors a single name into a part that *stays schema* and
a part that *becomes data* (`dob_child1` → column `dob`, row-value
`child = 1`). `pivot_wider` is the exact inverse — the distinct values of a
column become column names, so **the output schema is data-dependent**: you
cannot know the result's columns without reading the data. When keys don't
uniquely identify cells it quietly becomes aggregation (`values_fn = mean`).
And the whole machine is self-describing: "a data frame that specifies
precisely how metadata stored in column names becomes data variables (and vice
versa)" — one spec table drives both directions, with an exact size law
(`nrow(out) = nrow(df) * nrow(spec)`).

Riding along is the missingness complex: `values_drop_na`, `values_fill`,
`complete`, and the implicit-vs-explicit missing distinction — a rectangle
*forces* cells to exist for observations that never happened (the song's rank
in week 60, the third child of a two-child family), and both pivots must decide
at the boundary whether to synthesize or delete such cells.

**Our approach.** This is where distinguishing the two species of "column"
pays off. In the drawn language the column axis is not one thing:

- A **static-schema** table — columns fixed when the program is drawn — is k
  wires. Its column names are labels on drawn structure, not data anywhere at
  runtime.
- A **data-keyed** table — `pivot_wider`'s output, where the column set comes
  from the data — is not a struct at all in the record's terms. It is **keyed
  lanes at rest**: a keyed partition's collected value, cells determined at
  runtime — exactly the data-determined bundle the XQuery study flagged as "a
  different animal" from the static case bundle.

R conflates the two because its column names are strings either way, and the
pivot machinery is the price: an entire reshaping sub-language for moving data
across a boundary the representation refuses to draw. Once the species are
distinguished, the pivots mostly dissolve. `pivot_wider` **is the keyed
collect** (partition rows by the `names_from` value; the collision case
`values_fn` is precisely the operator-merge variant the collect family already
carries; `unused_fn` is the non-grouping wires becoming per-group flows).
`pivot_longer` applied to a data-keyed table **is the keyed uncollect** — lanes
back to firings, the key back on a value wire. Neither is a new construct; both
are the keyed partition consumed from its two ends.

The honest residue is in two pieces. First, the **boundary**: data arrives from
outside in wide files with value-bearing headers, and parsing schema into data
(`names_pattern`, `names_transform`, `.value`) is real work — but it is
edge/ingestion vocabulary (sibling of the FFI source openers), not core
iteration vocabulary. Second, the **static case**: `pivot_longer` over k
statically-known columns ("melt these five wires into (name, value) firings")
is drawable today — k explicit (name-literal, wire) contributions interleaved
into one collect — and k-fold repetition of near-identical structure is the
same authoring pressure `across` raises, filed in §8.

The missingness complex reads as a clash-flavored confirmation: the
forced-cells problem is *created by* rectangularity. A fires-or-not option wire
carries absence structurally — the record's row for "song not on chart in week
60" simply doesn't fire, and no NA cell exists to be dropped
(`values_drop_na`) or synthesized (`values_fill`, `complete`). The record keeps
rectangularity as a property of particular tables (all wires total), not a
type-level constraint — which is also tidyr's own direction of repair
(`values_drop_na = TRUE` converts explicit back to implicit missing).
`complete`/`expand` then locate themselves: manufacturing the full key product
and completing absent firings is Cross plus the outer-join completion
(`allowing empty`'s costume, sighted again), with `nesting()` — restricting a
factor of the product to *observed* combinations — a small new datum for the
products row: the observed product and the full product are distinct
constructions over the same wires.

### 5. Rectangling — the two unnests name the two axes

**Their approach.** tidyr's rectangling vignette turns nested JSON-ish blobs
into tables with a pair of duals: "`unnest_longer()` takes each element of a
list-column and makes a new row"; "`unnest_wider()` takes each element of a
list-column and makes a new column." The canonical staircase alternates them by
inspecting each nesting level's meaning:

```r
gmaps_cities |>
  unnest_wider(json) |>        # struct fields -> columns
  unnest_longer(results) |>    # each match -> its own row
  unnest_wider(results) |>
  unnest_wider(geometry) |>
  unnest_wider(location)       # -> lat, lng
```

`hoist()` bypasses the ladder with a path (`hoist(json, lat = list("results",
1, "geometry", "location", "lat"))`), plucking selected components from depth
and removing them from the blob. And the discography example concedes the
limit: deeply nested data is often *properly several tables* — rectangling into
one is lossy or duplicative; normalize into disc/artist/format tables and join
back as needed.

**Our approach.** The duality is the study's two axes stated as a pair of
verbs: a nesting level is either positional (elements are observations — expand
onto the firing axis) or named (fields are variables — expand onto the wire
axis). `unnest_longer` is the list uncollect with sibling wires riding along as
per-firing context, joined into the outer walk — owned. `unnest_wider` is the
more instructive one: **in the drawn language it is a no-op.** A struct-valued
wire already *is* its fields — one App per field projection — and "making
columns" is only an operation when columns are table machinery to be
maintained. The entire staircase, drawn: uncollect at each list level, field
projections at each struct level, one nested-flow program; the intermediate
tables the pipeline materializes at every step are rest-forms the flow never
needs. `hoist`'s path selection is the read half of paths-as-values (the
focused-update row's selection vocabulary, here selecting *out* rather than
writing back). The normalization concession is the record's nesting stance from
the other direction: tables at different granularities are flows at different
nesting depths, and flattening them into one rectangle duplicates ancestor
values per inner firing — which is exactly what `unnest` does ("repeating the
outer columns the right number of times") and exactly what drawn nesting avoids
until a collect asks for it.

### 6. Joins — keyed lookup between two flows, with the outer case as a completion

**Their approach.** Three families (`two-table.Rmd`). Mutating joins: for each
row of x, find key-matching rows of y and emit the combined row — with the
essential fine print that non-unique matches produce the Cartesian product of
matches (a join can *grow* rows: 3 joined to 3 yielding 5), and outer joins
fill unmatched rows' y-columns with NA. Filtering joins never duplicate:
`semi_join` keeps x-rows with a match, `anti_join` those without — membership
tests against the other table's key set. Set operations treat whole rows as
elements. Multi-table is deliberately out of scope: "use `purrr::reduce()`...
to iteratively combine the two-table verbs."

**Our approach.** Per firing of x, a keyed lookup into y: the match set is a
flow (zero, one, or many firings), joined into the outer walk — join(list,
list) with the inner flow produced by the lookup, which is why row growth is
automatic rather than surprising. The left join is the fired-empty completion
of a fires-or-not match — XQuery's `allowing empty` outer-join completion,
sighted again. Semi/anti joins are the membership predicate: a per-firing case
split against a set value built from the whole other table. The construct doing
quiet work in all of them is **the keyed index as a value** — y reorganized by
key so the per-firing lookup is a read, the keyed collect's product consumed as
an index (jq's `INDEX` was the same sighting; this corpus makes it everyday).
Handed to the collect family's round as a consumption pattern rather than a new
construct: build keyed lanes once, read them per-firing of another flow.

One clash rides along: the default join key is *whatever column names coincide*
(`flights2 |> left_join(airlines)` joins "by" the shared names) — unification
by name coincidence, the same clash recorded against Flix, here as the default
of the ecosystem's most used two-table operation. The vignette itself nudges
toward explicit keys.

### 7. Window functions — the register, the scan, and rank's third derivation

**Their approach.** Five named families on grouped data
(`window-functions.Rmd`): ranking (`min_rank`, `ntile`, `cume_dist`), offsets
(`lag`, `lead`), cumulative aggregates (`cumsum`, `cumany`, `cummean`), rolling
aggregates (named as a family; not shipped in dplyr), recycled aggregates (§2).

```r
filter(players, G > lag(G))                 # better than previous year
mutate(players, G_change = (G - lag(G)) / (yearID - lag(yearID)))
mutate(scrambled, prev = lag(value, order_by = year))   # order is a parameter
filter(players, cumany(G > 150))            # all years after the first 150-game year
by_team_quartile <- group_by(by_team, quartile = ntile(G, 4))
```

**Our approach.** A confirmation sweep, each family landing on an owned row.
Offsets are the register's previous-firing read — and dplyr's `order_by =`
parameter, plus the vignette treating "lag on scrambled rows" as the family's
footgun, is field support for the record's stance that ordering attaches to the
operation's walk, not to ambient table state. Cumulative aggregates are the
scan/running view (shipped yet again; `cumany` used as a *filter predicate* — a
scan feeding a case split — is a nice composite for the worked-examples file).
Ranking is sort-as-data's derived output: rank-after-reorder now has a **third**
independent derivation (APL's `⍋⍋`, XQuery's `count $rank`, dplyr's `min_rank`)
— the candidate derived port on the sort block hardens. The rolling family
being named-but-absent in dplyr (delegated to other packages) is a small
negative witness on window(k)'s demand side. And `ntile`-then-`group_by`-the-
result — a whole-column rank becoming the *next partition key* — is the keyed
partition composing with ordering vocabulary, the same composition demand the
XQuery study logged from the working-time query.

### 8. across and rowwise — schema iteration dissolves into authoring; the inverted mirror

**Their approach.** `across()` applies one operation to many columns, selected
by name pattern, position range, or runtime type predicate, with computed
output names:

```r
df |> group_by(g1, g2) |> summarise(across(a:d, mean))
starwars |> summarise(across(where(is.numeric), min_max, .names = "{.fn}.{.col}"))
df |> mutate(across(all_of(names(mult)), ~ .x * mult[[cur_column()]]))
starwars |> filter_out(if_any(everything(), is.na))
```

`cur_column()` exposes the current column's *name* inside the mapped function;
`.names` is string-template metaprogramming on the schema; `if_any`/`if_all`
fold a predicate across a schema-selected field set per row. `colwise.Rmd`
explains why `across` took years to become possible: a column of a data frame
can itself be a data frame — the table had to become a legal cell value first.
`rowwise()` is the mirror: R's per-row mode, bolted on (deprecated, then
re-added) because the ambient axis is columns; implemented as "a special type
of grouping where each group consists of a single row," with `c_across()` as
the per-row fold over a schema-selected field set.

**Our approach.** Split the demand by the §4 species and it files cleanly,
mostly *not* as runtime iteration:

- Over a **static schema**, "apply `mean` to columns a through d" is not
  iteration at all — it is k-fold repetition of drawn structure, and the honest
  drawn form is k collects. What `across` supplies is the *authoring gesture*:
  one gesture that produces the k nodes, with the k-fold structure still
  readable. That is the record's many-authoring-paths / one-reading stance
  (level-1 operations producing ordinary drawn structure), plus the functions
  row's schematic-diagram territory (a sub-diagram instantiated per wire). The
  demand is real — the corpus is full of it — but it is a demand on authoring
  and reuse vocabulary, not on the flow model. `if_any(everything(), is.na)`
  over static wires is a drawn OR-tree, same story.
- Over a **data-keyed** table, `across(where(is.numeric), ...)` really is
  runtime iteration — over the lanes of a keyed value — and is owned by the
  keyed partition's ordinary uncollect. The type-predicate selection is a lane
  filter.
- `cur_column()` — the mapped operation's meaning depending on the column's
  *name*, with the name arriving ambiently — goes to the clash record: it is a
  magic name (the inside-out principle: anything readable in a position must
  arrive by a visible wire), and its legitimate content (per-lane key available
  as a value) is what the keyed uncollect's key wire already provides.

`rowwise` earns a finding of its own not for its mechanism but for its history:
the tidyverse's most instructive field report is that **each package bolted on
the axis it lacked** — R, column-major, re-added a row-wise mode after trying
and failing to serve row-wise work with purrr's arity matrix; and `across`
arrived years in because column iteration needed tables-as-cells. The record's
ground floor (per-firing walks, wires per variable, collects for whole-column
results) starts with both readings drawn: the multi-wire uncollect *is*
`rowwise`, the k collects *are* the column pass. The inversion also cuts the
other way as a caution: R's whole-column primitives are fast because they are
fused vector operations, and dplyr's docs recommend `rowSums(pick(...))` over
honest row-wise folds for speed. The record's per-firing surface with
whole-column *compilation* (the deferred placement/fusion passes) is positioned
to have both, but the fusion is load-bearing for the domain — worth a line in
the compile ledger.

### 9. The purrr audit — the combinator inventory against the drawn constructs

purrr's combinators, item for item:

| purrr | What it computes | Drawn form in the record |
|---|---|---|
| `map` (+ typed suffixes) | independent per-element map | uncollect/collect (suffixes: the collect's kind, statically evident) |
| `map2` / `pmap` | map over aligned lists; "a data frame... `.f` called once for each row" | the aligned product (zip) — §1; over a table, the multi-wire uncollect |
| `imap` | map with index/name (`map2(x, names(x) or seq_along(x))`) | index as a derivable aligned lane (Zig's `0..` again) |
| `walk` / `iwalk` | per-element effects, input passed through | the Tier-1 effects row (per-firing effects; the pass-through output is a barrier detail) |
| `keep` / `discard` / `compact` | predicate filter | join(list, case flow) |
| `detect` / `head_while` / `every` / `some` | search with genuine short-circuit; miss → `NULL`/default | end-when + the option-shaped discharge |
| `reduce` (+ `.init`, `.dir`) | fold; seed handles empty input | the fold collect; the initial-value port (empty-collect framing confirmed again) |
| `accumulate` | "applies a 2-argument function in the same way [as reduce], but" keeps every intermediate | the running view / augment form (shipped, third corpus running) |
| `done(value)` inside reduce/accumulate | early exit from a fold, as a returned value | **end-when composed with the register — as a value, not a control statement** |
| `reduce2` / `accumulate2` | fold with an aligned second input, length n−1 | register + zip; the per-edge alignment datum (§1) |
| `list_transpose` | list-of-structs ↔ struct-of-lists | commute-as-transpose at the value level (rest form of §1's duality) |
| `list_flatten` / `list_c` / `list_rbind` | remove one nesting level / concat | join(list, list), one level at a time |
| `safely` / `possibly` | exception → `{result, error}` value / default | failability's terminator payload as data; `map(safely(f))` + transpose = per-firing failability re-columnized into a result lane and an error lane |
| `modify` / `modify_if` / `modify_at` / `modify_in` | shape-preserving update of selected elements, rest untouched | **focused update** — with the functor laws stated in the docs (`modify(x, identity) === x`; composition) |
| `map_depth` / `modify_depth` | map at nesting level k; `.ragged` policy | uncollect nesting; the level drawn, not annotated |

Three entries deserve a sentence beyond the table. **`done()`** is the study's
best small find: purrr's fold takes early termination as a *value-level wrapper
returned by the step* — `done(out)` means "stop, this is the answer," bare
`done()` means "the previous accumulator was the answer," and in `accumulate`
it truncates the emitted trajectory. That is end-when composed with
loop-carried state, shipped in a resolutely functional interface, with the
inclusive/exclusive readout (this value vs previous value) appearing as the
wrapper's arity — a datum for end-when's bit and for the register's
final-readout anchor at once. **`safely` + `map` + `list_transpose`** is the
corpus's canonical error idiom, and its shape is the discharge's two-lane form:
a walk whose firings each carry result-or-error, re-columnized into a result
lane and an error lane — the partial collect / terminator vocabulary arriving
at the same drawing from the error side. **The `modify` family** is the
focused-update row's sixth witness and its most law-abiding: selected elements
rewritten, "the same type as the input object" preserved, identity and
composition laws stated outright, `modify_in` writing at a pluck path — jq's
paths, BQN's Under, and purrr's modify now agree across three ecosystems on the
same construct the record holds open.

Like the APL audit, the striking thing is coverage in both directions: nothing
in purrr's inventory names a construct the record lacks entirely — and
everything the record holds *open* that purrr ships (zip, the running view,
end-when's readout, focused update, the keyed forms via dplyr) ranks the debts
again, in the same order.

### 10. Smaller sightings, and the clash record

**Sightings.**

- **`expand.grid` / `crossing`** — the Cross node as everyday table furniture
  (parameter sweeps: "Cartesian product of params" feeding a rowwise
  simulation); with `nesting()`'s observed-product restriction as the
  products-row datum (§4).
- **The contact-list key synthesis** — rows with no grouping id; the id is
  manufactured from row order: `mutate(person_id = cumsum(field == "name"))`
  then widened. That is split-when in a scan costume — segmentation of a walk
  by boundary firings (`field == "name"` starts a segment), encoded as a
  running count because the vocabulary lacks the construct. Another
  assembly-language sighting for the variable-rate row, from a fourth
  ecosystem.
- **`fill(.direction = "down"/"downup", .by = group)`** — the carry-forward
  register (last non-absent value), direction explicit, composed per-group:
  register + keyed partition, an everyday composite for the worked-examples
  file.
- **`slice_max(height, n = 3)` / top-N** — rank + take, the no-end-when top-N
  contrast from the XQuery study not applicable here (lists are finite values);
  noted only as vocabulary overlap.
- **`separate` / `unite`** — pure per-firing Apps; listed to be explicit that
  most of tidyr's cell-level verbs are ordinary value code and need nothing.
- **`reframe()`** — summarise minus one-row-per-group: per group, emit any
  number of rows — the per-lane collect whose output is itself a flow joined
  upward; the keyed partition's flatMap readout, completing §3's readout
  family.
- **Grouping metadata queryable both directions** (`group_indices` row→group,
  `group_rows` group→rows) — the partition as a first-class value with two dual
  views; provenance made data, adjacent to the grade/permutation-as-value
  finding.

**What not to import (the clash record).** As always: the reasons a graft
fails, not criticisms of the source.

- *Ambient magic names.* `n()`, `cur_column()`, `pick()`, `c_across()`, and the
  whole "current group" context are meaning by position — the inside-out
  principle's named counterexample. Their legitimate content (extent of the
  current lane, the lane's key) is what drawn wires from the enclosing
  uncollect provide.
- *Grouping as a mode bit on the value.* `grouped_df` changes the meaning of
  every subsequent verb at a distance; the receipts are dplyr's own: `arrange`
  ignoring groups by default while everything else honors them, `select`
  silently retaining key columns ("possibly a mistake"), `summarise`'s
  pop-one-level default surprising enough to grow a `.groups` argument and a
  message. Drawn nesting *is* the grouping; there is no mode.
- *Schema as strings.* Columns selected by name pattern (`ends_with("color")`),
  output names via glue templates, join keys defaulting to name coincidence,
  `.x`/`.y` collision suffixes — the one-namespace, stringly-typed column axis
  is what §4's conflation costs. Wires carry identity structurally.
- *Recycling and auto-simplification.* Length-1 broadcast is Incorporate's
  implicit costume (same clash as APL's scalar extension); base R's general
  recycling and `sapply`'s type-unstable simplification are the ancestral
  versions purrr itself walked back (scalar-or-error; typed suffixes) — a
  shipped correction *toward* the record's barrier law and wire sorts, recorded
  as such.
- *The rectangle as a type.* Forced cells and the NA-complex (§4) follow from
  making rectangularity structural; the record keeps it a property.
- *`rowwise`'s `[` vs `[[`.* The grouped-vs-rowwise distinction hinging on
  auto-unwrap of a one-element cell — semantics by subscript flavor — is the
  mode-bit clash in miniature.

## Findings

**The headline.** The tidyverse is the third shipped member of the
tuple-stream family the XQuery study identified — and its distinctive move,
reifying the multi-wire stream as a *value*, answers this study's motivating
question: a table is more than a list of structs, and the "more" is exactly the
record's aligned product, at rest. The two axes are wires (drawn, schema) and
firings (runtime, extent); their coupling is rectangularity. Nothing in three
packages demands a new iteration construct: the interesting operations
decompose into the keyed partition consumed from both ends (pivots, group-by,
joins), the fold-then-re-walk composite (recycled aggregates), the register and
scan (window functions, fill), Cross (expand), and focused update (modify) —
every one an existing row, most receiving their third-or-later consecutive
study of evidence. The two genuinely new pieces of structure both land on
existing rows: the **table as the aligned product's value form** (products row)
and the **pass-through readout of the keyed partition** (collect family).
Deliberately *no new row*: tabular data dissolves into the record's existing
agenda, which is itself the study's strongest result.

**Finding 1 — the data frame is the multi-wire flow at rest; the aligned
product needs a value form.** k columns = k wires, n rows = n firings,
alignment retained from common provenance. The record has the flow half (zip, a
demand since the APL study) but nothing at rest: k sibling collects forget they
shared a walk. Demand handed to the products row: the multi-wire collect whose
product is a table — k lists that remember they were collected from the same
walk — and whose uncollect returns the wires. The row-splat wart, the map-arity
matrix (with dplyr's own documented retreat from it), and join suffix
collisions are the evidence that the open form should be wires, not row-structs.
Small new datum: `reduce2`'s length-(n−1) second input — per-edge alignment as
a distinct alignment target.

**Finding 2 — the broadcast-back is a fold consumed by a re-walk, and it is
everyday.** `x - mean(x)`, grouped z-scores, `filter(height == max(height))`: a
collect's result combined per-firing with its own source. Not time travel — the
drawn form is two walks of the same value, the fold's result entering the
second walk by ancestor availability. Demands recorded: the two-walk composite
belongs in the collect family's worked examples, and under grouping it requires
the per-group value (the lane collected to a sub-list, re-openable) —
group-as-flows' group-as-*value* corollary, which dplyr independently ships as
`nest_by`.

**Finding 3 — the keyed partition has two readouts: collapse and
pass-through.** `summarise` = one output per group (keys ⊕ aggregates — the
keyed collect as already recorded); `mutate` / `filter` under grouping =
per-firing outputs riding back to the parent walk in original order — the case
bundle's exhaustive collect generalized to data-determined cells; `reframe` =
the flatMap readout; `filter_out(n() == 1)` = whole-lane engagement. One
partition barrier, several collects — handed to the collect family's round as
the readout family, alongside the group *stack* confirmation (summarise pops
one drawn nesting level; `.groups` is the how-many-levels choice as API).

**Finding 4 — the pivots dissolve once the two species of column are
distinguished.** Static-schema columns are wires; data-keyed columns are keyed
lanes at rest. `pivot_wider` is the keyed collect (its `values_fn` collision
case is the operator-merge variant); `pivot_longer` on keyed data is the keyed
uncollect; the five messy patterns are data sitting on the wrong side of the
static/dynamic divide; R needs a reshaping sub-language because its string-named
column axis refuses to draw that divide. Residue: schema-parsing at the
ingestion boundary (`names_pattern`, `.value`) — edge vocabulary, sibling of
the source openers; and the k-fold static melt, which is §8's authoring
pressure. The missingness complex (forced cells, `values_fill`/`values_drop_na`,
`complete`) is created by rectangularity-as-type; option wires carry absence
structurally, and rectangularity stays a property. `complete`/`expand` = Cross +
the outer completion (`allowing empty` sighted again), with `nesting()`'s
observed-product restriction as a new small products-row datum.

**Finding 5 — the two unnests name the two axes; `unnest_wider` is a no-op on
wires.** "Each element... makes a new row" vs "each element... makes a new
column" is the firing-axis/wire-axis duality as a verb pair. Rectangling's
staircase is uncollects at list levels and field projections at struct levels;
the intermediate tables are rest-forms the flow never materializes. `hoist`'s
pluck paths are the read half of paths-as-loci (focused-update adjacency). The
normalization concession (nested data is properly several tables joined by
keys) is drawn nesting's stance arrived at from the flat side: `unnest`
"repeating the outer columns" is the duplication nesting avoids until a collect
asks.

**Finding 6 — joins are keyed lookup; the keyed index is the keyed collect's
product consumed per-firing.** Mutating join = per-firing-of-x lookup into
keyed y, match flow joined upward (row growth on duplicate keys is automatic);
left join = the fired-empty completion; semi/anti = membership case split
against a set value. Handed to the collect family as a consumption pattern:
build lanes once, read per-firing of another flow (jq's `INDEX` made everyday).
Clash: join-by-name-coincidence as the default.

**Finding 7 — the window sweep.** Offsets = the register's previous-firing
read, with `order_by =` as field support for ordering attached to the walk (the
`scrambled` footgun as the negative witness); cumulative = the running view
(third corpus running); `cumany`-as-filter-predicate a good worked composite;
rank-after-reorder gains its third independent derivation (`min_rank` after
`⍋⍋` and `count $rank`) — the sort block's derived rank port hardens;
`ntile`-then-regroup = ordering vocabulary composing with keyed partition (same
composition demand XQuery logged); rolling aggregates named-but-delegated is a
small window(k) demand datum.

**Finding 8 — schema iteration dissolves into authoring; the bolted-on axes are
the field report.** Over static schema, `across`/`if_any`/`c_across` are k-fold
repetition of drawn structure — an authoring-gesture demand (one gesture, k
readable nodes; the many-paths/one-reading stance and the functions row's
schematic territory), not runtime iteration. Over data-keyed tables they are
the keyed uncollect. `cur_column()` is a magic name whose legitimate content is
the lane-key wire. The history — column-major R re-adding `rowwise` after
purrr's arity matrix failed row-wise work; `across` waiting on tables-as-cells
— is the study's cleanest evidence that the multi-wire flow surface, where both
axes are drawn from the start, is the right ground floor. Caution recorded for
the compile ledger: R's column axis is fast because fused; the domain needs the
deferred fusion passes to deliver whole-column performance under the per-firing
surface.

**Finding 9 — the purrr audit maps item for item; `done()` is end-when as a
value.** The combinator inventory names nothing the record lacks entirely (§9's
table); the open debts it ships — zip, running view, end-when readout, focused
update, keyed forms — rank in the same order as the APL audit left them. Best
small find: `done(out)` / bare `done()` — early exit from a fold as a returned
value, with the this-value/previous-value readout as wrapper arity — a datum
for end-when's inclusive bit and the register's final readout at once.
`safely`+`map`+`transpose` is the discharge's two-lane drawing arrived at from
the error side. The `modify` family (identity and composition laws stated;
`modify_in` at pluck paths) is the focused-update row's sixth witness, third
ecosystem.

**Finding 10 — what not to import.** Ambient magic names (`n()`,
`cur_column()`); grouping as a mode bit with dplyr's own documented
inconsistencies as receipts; the stringly-typed schema (name-pattern selection,
glue-template output names, join-by-coincidence, suffix collisions); recycling
and auto-simplification as implicit-Incorporate and type instability — with
purrr's own tightenings (scalar-or-error, typed suffixes) recorded as a shipped
correction toward the record's barrier law and wire sorts;
rectangularity-as-type and its forced-cells bill; semantics by subscript flavor
(`[` vs `[[`).

## What this study changes in `open-problems.md`

- **Products row**: the aligned product gains its **value form** as a named
  demand — the table as k lists retaining common provenance, the multi-wire
  collect/uncollect pair (finding 1) — plus the per-edge alignment datum and
  the observed-product (`nesting()`) note. W 3 → 4: the row now owns tabular
  data as a domain, not just lockstep pairing as an operation — three
  consecutive studies (APL, Zig, this) landing their central evidence here, and
  an entire mainstream ecosystem organized around the row's missing value form.
  (Honesty: this corpus is curated and frequencies transfer nothing; the move
  is about the row's *scope*, not measured frequency.)
- **Loop-carried state row (keyed collect / collect family items)**: the
  readout family (collapse / pass-through / flatMap / whole-lane engagement —
  finding 3), the group-as-value corollary and the broadcast-back composite
  (finding 2), the keyed index as consumption pattern (finding 6), pivots as
  the keyed pair (finding 4). Scores unchanged.
- **End-when row**: `done()` as the value-form witness, with the
  inclusive/exclusive readout as wrapper arity; `detect`'s option-shaped miss.
  Scores unchanged.
- **Focused update row**: sixth witness (`modify` family, functor laws, pluck
  paths; `hoist` as the read half). Scores unchanged; the frequency sample
  still decides W.
- **Variable-rate row**: the contact-list `cumsum(field == "name")` key
  synthesis as a fourth-ecosystem split-when assembly-language sighting;
  rolling-named-but-delegated as a window(k) demand datum. Scores unchanged.
- **Functions/reuse row**: the authoring-gesture demand from `across`/static
  melt (one gesture, k readable nodes — schematic sub-diagram instantiated per
  wire), filed beside late-bound operations. Scores unchanged.
- **Concurrency row**: nothing — the domain's silence is corpus fact (reading
  rule 5).
- **Evidence owed**: no new entries; the focused-update frequency sample can
  add `modify_at`/`modify_in` to its idiom list.

## Next in this genre

The standing list still carries the **beginner-first study** (Scratch/HyperCard
lineage) and the **reactive-library application-code variant**. This study
suggests its own successor in the APL study's spirit: the tidyverse vignettes
are the showcase; real analysis scripts (a seeded sample of Kaggle notebooks or
rOpenSci package internals) would supply the field frequencies this corpus
cannot — in particular how often the broadcast-back, the pivot pair, and
`across` occur in code nobody curated, which is what the products row's W move
should eventually rest on.
</content>
</invoke>
