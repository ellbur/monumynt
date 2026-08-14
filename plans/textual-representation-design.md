# Textual representation

*Or: how to read and write programs as text.*

Status: draft — this chapter teaches a proposed textual form for
programs: something that can be parsed and generated, sitting beside
the visual form. It is a worked proposal, not a settled feature.
Nothing here changes the representation (`visual-language-spec.md`,
`core-model.md`): the text is a serialization of the
same nodes, ports, and wires, not a new layer of meaning.

The rest of the design record writes its examples in this notation,
so this chapter doubles as the syntax tutorial for the whole record.
It comes in two halves. The first half teaches you to read and write
programs, starting from a one-line chain and adding one construct at
a time. The second half explains why the notation is the way it is —
what a textual form is for, what makes one hard for this language,
the principles that shaped it, and the alternatives that were
considered and turned down.

One orientation fact before the first example. The canonical form is
**forward**: you write a value first, then what happens to it, so
`double(a)` is written `a -> double`, and results are named on the
right (`… => out`). Conventional name-first, head-first spellings
(`b = double(a)`) are accepted when you type them, but they are not
what the printer emits. The reasons are in "Reading forward," in the
second half — along with the record of a brace-delimited fan-out
syntax that was considered and rejected, and of the name-first form's
demotion to input-only.

## Your first line

Comments run from `--` to the end of the line, as everywhere in the
design docs. Here is a complete program:

```
double = js "x => x * 2"          -- extern: the JsAst escape hatch
3 -> double => six
```

The first line defines `double` by borrowing a JavaScript function —
`js "…"` is the escape hatch for that, and `name = …` (left
assignment) is the short form used for leaf definitions like externs
and constants. The second line reads left to right: take `3`, apply
`double` to it, and name the result `six`.

That left-to-right shape is called a **chain**: stages joined by
arrows, each stage receiving the value the previous stage produced.
A stage is either a value operation (like `double`) or a construct
keyword (`open list`, `split`, `collect`, `join`, `commute`, … —
you'll meet each below). `=> six` is the **naming stage**; naming is
just the last thing that happens to the value, not a separate
statement wrapped around it.

Now the doubling loop, the same first program `core-model.md` opens
with:

```
double = js "x => x * 2"          -- extern: the JsAst escape hatch
[1, 2, 3] -> open list -> double -~> collect => out
```

`open list` opens the list so that what flows onward is each element
in turn; `collect` gathers the doubled elements back into a list.
(If those words are new, read `core-model.md` first — this chapter
teaches the *notation*; that one teaches the model.)

## Chains across lines

Any stage may start a new line; a leading arrow continues the
previous line's chain. So the doubling program can equally be
written:

```
xs -> open list
   -> double
  -~> collect
=> doubled
```

`=>` is just the last stage, so right-hand naming never needs column
alignment — the name simply starts its own line when the chain is
long. The naming stage may also bind several outputs at once
(`=> a, ~L` — more on the `~` in a moment) and may stand on its own
line.

## Three arrows

Look at the arrows above: most are `->`, but the one into `collect`
is `-~>`. There are exactly three arrows, one per combination of the
language's two wire sorts:

- `->` — a **value wire**. Ordinary application, open inputs.
- `~>` — a **flow wire**. Wiring a flow into a stage with no value
  involved: `~L ~> delay init 0`, `~c.Even ~> join into ~L`.
- `-~>` — a value **with its flow**. Into `collect` (which consumes
  both). Also used in chain position for `join` and `commute`, which
  are flow-only operations — join takes two flows in and emits one
  flow; commute takes two flows in and emits two flows; neither has
  any value port. There the arrow marks that the stage acts on the
  chain value's flow context; the value itself never enters the node
  (a soundness note below explains why nothing is lost).

Flow references are lexically marked too: `~L` is a flow reference,
`L` would be a value reference. The sorts are distinguishable at a
glance, before any name is looked up — mixing them up is a parse
error, not a puzzle for the checker.

Now, you might wonder why the language doesn't just let a plain `->`
into a `collect` quietly reach for the flow — after all, a value in
a chain has a *context path* (the stack of flows it lives under,
derivable from the dataflow), so the information is there. It turns
out this would cause a problem of level-mixing: the wire would be
being used to mean not the value it carries but *the wire itself*,
as a key for a different associated wire — do you mean the variable
or its value? `-~>` is the honest spelling: it acknowledges, in the
syntax, that a flow is entering the stage. The stage still needs no
*operand* (see "The implicit flow stack" — the adjacency rules
determine which flow), but the arrow says a flow is entering at all.
(This is a settled design point — the third arrow earns its keep.)

The soundness of letting a value "ride through" a `-~> join` or
`-~> commute`: join and commute are pure flow operations — a join is
two flows in, one flow out; a commute is two flows in, two flows
out — with no value ports at all, so no value ever passes through
either. The chain spelling is sugar: when the parser desugars it,
the value wire bypasses the node entirely (value references keep
pointing at their producer) and only the flows are rewired. Nothing
is lost by drawing the value as riding through, because "before vs
after the commute" is not a distinction the representation can even
express — the two are identified (the *naturality quotient*, in the
spec's terms).

## Naming is sharing

Names in this notation carry more weight than in most languages, so
it's worth pausing on them early.

Writing `double(a)` twice mints two separate nodes — two
applications, not one. To share a computation, name it (or tap it —
taps come below):

```
a -> double => d
d, d -> add => quadrupled       -- one double node, referenced twice
```

A statement binds names to output ports of the one node it
constructs. Names are single-assignment, never shadowed, and global
to the diagram. Referencing a name twice is fan-out from one port —
the same node, not a copy. Conversely, writing the same expression
twice makes two nodes: sharing is opt-in via naming, exactly as it
is opt-in via ReScript binding in today's code. So in this text, **a
name is the mark of sharing**: anonymous is linear, named is shared.

There is a deeper reason the discipline is this strict, carried over
from `types-design.md`: "wires are the type variables." The diagram
never has an identity problem — a wire simply *is* one connection.
Text reintroduces the burden the diagram avoided (a name must
faithfully stand for exactly one wire), and single-assignment global
names are the discipline that pays that debt.

## More than one input

Value operations in chain position take the chain's value as their
first input; extra inputs go in parentheses: `-> add(ten)` means
`add(topic, ten)`, where "topic" is the value riding the chain. When
the topic is not the first argument, use the full comma-list form:

```
ten, x -> sub                    -- sub(ten, x)
```

A source-list item may itself be a short chain, parenthesized:

```
(a -> sq), (b -> sq) -> add -> sqrt => c
```

The parentheses are **grouping, not scope** — they bind nothing and
have no interior; they only delimit where the item's chain ends,
which without them would be ambiguous against the consuming chain.
Inside a stage's argument list the delimiters already exist, so
items there may be bare chains: `-> add(b -> sq)` (accepted input;
canonical output prefers the forward comma-list spelling, since a
computed chain inside stage arguments reads against token order the
way prefix application does). Reading direction survives grouping
intact: within each group and across the list, producers still come
before consumers — a group is the one tree-shaped nesting the
forward form admits, because a group reads forward too. Provisional
restriction: no taps, marks, or lanes minted inside a group; a
sub-chain that complex should be its own line (a mark) or named.

## Infix operators

The operators conventionally written between their operands — `+`,
`-`, `*`, `/`, `%` — are accepted infix (`a * a`, `x + 1`), the
permissive-grammar clause of "many authoring paths, few readings."
An infix expression is **sugar for an App of the operator's function**
to its two operands: `a + b` is `a, b -> add` with `add` the extern
`(a, b) => a + b`. So infix earns no new node kind and no new
semantics — squaring is `a * a` (a name used twice is fan-out from one
port, so the two operands are the same wire), and the fan-in noise
that a comma-source list forces (`a2, b2 -> add` demanding a name per
operand) dissolves into `a2 + b2`. Standard precedence, left-
associative; there is no `**`, and unary minus is only a negative
number literal (`-5`), not general negation (write `0 - x`).

In **chain position** an operator is a *section* on the running topic,
mirroring the topic-first rule for every value operation: `-> * 2`
takes the chain's value as the left operand and `2` as the right —
`(* 2)` in the Haskell-section sense, "multiply the thing flowing by
two." So the doubling loop needs no bespoke `double` extern:

```
[1, 2, 3] -> open list -> * 2 -~> collect => out
```

The section's right operand is a single primary, so precedence never
crosses a stage boundary; sequence more operations by chaining more
sections (`-> * 2 -> + 1` is `(topic * 2) + 1`).

The printer's side of this — emitting a small pure-value leaf back as
infix rather than as the desugared App — is open question 5 (the
implicitness thresholds); until it lands, a round-trip prints the
App form (`n1 = js "(a, b) => a * b"` / `-> n1(2)`), which reparses to
identical wiring. Parsing infix is implemented (`TextParse`'s `opInfo`
precedence climb + the operator-section stage; `TextResolve.opToJs`
maps each symbol to its extern).

## Ports and projections

A binder names the *node*. The bare name stands for the node's
principal value port (its `value`/`result`/`element`/`prev`); the
`~`-prefixed name (`~L`) stands for the principal flow port. So

```
xs -> open list => a, ~L
```

names the open's element `a` and its flow `~L` in one stage.

Projection reaches named ports: `cs.Just` is the value port named
`Just` on node `cs`, and `~cs.Just` the flow port of the same name —
the sigil states the sort of the reference; the checker verifies
that the node's kind actually has that port. This is
`ValuePort(node, name)` / `FlowPort(node, name)` from
`src/Program.res` (`core-model.md`), spelled out. Notice there is no
Branch construct anywhere in the text: a branch *is* a reference to
one output port of the split, so projection replaces the satellite
node.

Port inventories are per-kind and irregular (Commute has no value
ports; a register's read half has no flow outputs) — the syntax
never assumes a fixed shape.

## Opens and nesting

```
xs -> open list => a, ~L
m -> open option => v, ~O
ys -> open list in ~L => y, ~Y     -- explicit outer-nesting
```

`open <kind> <input>` — the flow kind is part of the node (explicit
over implicit; no inference discovers it). Future kinds slot in
without new shapes: `open async`, `open stream`, `open var`,
`open pool(3)`, `open config sort`. The `in` clause is the spec's
`outerFlows`: it says which flow this open nests inside. When the
nesting is already implied by the value input (opening a value that
is itself per-iteration), `in` is omitted; when it is neither
implied nor stated, the program is under-committed — legal to write,
and covered in "Under-commitment and completion" below.

## The implicit flow stack

Because a chain's value carries its context path, flow stages in
chain position need no operands:

- `-~> collect` closes the **innermost** layer of the incoming
  value's path.
- `-~> join` merges the **two innermost** layers — the binary flow
  operation: two flows in (inner into outer), one combined flow out.
- `-~> commute` swaps the **two innermost** layers — two flows in,
  two flows out, reordered.

Flatten-map, with no names at all:

```
rows -> open list -> open list -> double -~> join -~> collect => flat
```

The bare `join` stage is the binary flow node: the two innermost
layers of the value's path are its two flow inputs, the combined
flow its one output. `double`'s value rides the chain past it
untouched — the node has no value ports.

This is well-defined, not merely convenient, because of the
adjacency requirement: binary join's operands must be
nesting-adjacent, and in a chain the inner operand can only be the
value's innermost unconsumed layer — the value couldn't cross it
otherwise. There is nothing to disambiguate. Reaching a *deeper*
layer is not done by naming it; it is done by more commutes, which
is honest about the meaning: commute variants exist per flow-kind
pair, and where no variant exists, reordering is rightly
inexpressible. The flow stack is a stack whose only rotation
operator has real meaning.

(A historical note: the old flowRef wrapper stack was this all
along. `Commuted(Joined(NodeFlow(…)))` read inside-out is postfix
stage order, and `ExprPrint` already renders joins as postfix
`-> join`.)

Flow stages accept an explicit operand when the implicit one is
unavailable or under-committed: `-~> collect ~O`. The explicit form
is *required* when the value is context-free — e.g. collecting a
constant: `5 -~> collect ~L` builds a list of fives; the constant
has no path to read the flow off. Standalone, fully explicit forms
also exist: `~c.Even ~> join into ~L => ~keep`.

## Commute in text

Commute in chain position is bare (`-~> commute`, swapping the two
innermost layers). Standalone, it names both operands, inner first —
join and commute operand order carries meaning and must never look
symmetric:

```
~err ~> commute out of ~loop => c
-- ~c.outer : the flow that was inner (now outermost)
-- ~c.inner : the flow that was outer (now inside)
```

The defer-the-error idiom in chain form: `-~> commute -~> collect`
closes the loop first, leaving the option layer open for a later
collect. (The full example is in "Worked examples" below.)

## Junction taps: fan-out without names

Suppose one value feeds two chains. You could name it — but for a
value used twice on adjacent lines, a name like `tmp1` is pure
noise. A `|` mid-chain mints a **tap** — a junction on the wire at
that point. A line whose chain begins with `|` resumes from a tap:

```
a -> | b -> c -> d
| -> e                      -- a also goes to e
```

Generalized, multiple taps per line, `;` separating resumed chains:

```
a -> | b -> c -> | d
| -> e; | -> f              -- a goes to e, c's result goes to f
```

Mechanics:

- Binding is **ordinal** — by counting, never by column: the k-th
  leading `|` on a line binds to the k-th tap of the antecedent
  line. Alignment on the page is printer cosmetics, nothing more.
- **Antecedent range**: leading `|`s refer to the taps of the
  nearest preceding line that minted any. Several consecutive
  continuation lines may reuse the same taps — pronouns bear
  repetition, so fan-out to three consumers is three `|` lines. A
  line that mints new taps replaces the antecedents. Anything that
  must reach further wants a name: pronouns for adjacency, names
  for distance.
- On the page, the leading `|` *draws the wire*: a junction dot on
  one line, the wire dropping a row to the next. The notation
  recovers a strip of the diagram's second dimension — vertical
  wire segments — in a form that is still counted, not spatial.

("Pronoun" is the record's word for these shorthand references —
like the word "it" in English, a tap refers back to something nearby
without naming it. Taps, marks, lanes, and the flow shorthand below
are all pronouns, and all of them dissolve at parse time into plain
explicit wiring.)

Multi-close on one opener, zero names:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Both bare `collect`s close the list flow; the tap carries the
element to both chains; the opener is shared through the tap.

Fan-out to three consumers is three `|` lines — consecutive
continuation lines reuse the same antecedent taps:

```
req -> parse -> | route => target
| -> logLine -> emit => logged
| -> checksum => sum
```

All three chains read `parse`'s result, and no name is minted for
it.

More taps, same rules, inside a loop — the element and an
intermediate result each fan out, and the k-th leading `|` on a
resuming line binds the k-th tap:

```
xs -> open list -> | double -> | add(ten) -~> collect => bumped
| -> triple -~> collect => tripled ; | -> negate -~> collect => negated
```

`triple` consumes the element (first tap); `negate` consumes
`double`'s result (second tap); all three collects close the same
list flow.

## Value marks: fan-in without names

Taps are the fan-out pronoun; marks are the fan-in one — the shape
the notation was quietly worst at before they arrived. The tell is
in this record's own examples: they lean on unary stages (`double`,
`sq`) because chains embed those perfectly, and the moment a
multi-input node's operands are themselves computed, the comma
source list demands a name per operand:

```
a, a -> mul => a2
b, b -> mul => b2
a2, b2 -> add -> sqrt => c
```

(Squaring is spelled as plain multiplication — `a` is a name, so
using it twice is ordinary fan-out from one port; `a * a` is
accepted infix input for the same node.)

`a2` and `b2` are pure noise — single-use, adjacent, unmeaning. This
is the over-naming failure ("if every seam forces a name, the code
goes flat" — see "What makes this hard" in the second half)
surfacing on the many-to-one side, which taps never touched.

A terminal `^` **marks** a chain's final value: the chain ends there
and its value is *pending*. Pending marks queue in text order. A `^`
in any source position — a comma-list item, a stage argument —
**uses** the front of the queue: the k-th use in reading order binds
the k-th pending mark.

```
a, a -> mul ^
b, b -> mul ^
^, ^ -> add -> sqrt => c
```

Mid-chain, in a stage argument — a value computed once, then used
inside a loop (capture stays implicit, as ever):

```
ys -> mean ^
xs -> open list -> sub(^) -~> collect => centered
```

More than two marks queue the same way — production order and
consumption order agree, so the queue never needs tracking:

```
xs -> min ^
xs -> max ^
xs -> mean ^
^, ^, ^ -> describe => stats
```

The first `^` in the source list takes `min`'s value, the second
`max`'s, the third `mean`'s.

Mechanics:

- **Binding is FIFO and ordinal**: k-th use ↔ k-th pending mark, so
  values are consumed in the order they were produced — token order
  is time on the use side too. Now, you might wonder why marks
  don't bind nearest-first, the way the flow shorthand `~` / `~^`
  reaches for the nearest flow. That alternative was considered,
  and it turns out to read wrong: with two operands, `^, ^` would
  bind *reversed* against reading order, and the flow shorthand's
  depth logic has no analogue here (marks have no nesting to index
  into). (This is a settled rejection — please don't re-propose it
  without new evidence.)
- **Marks are linear.** One use consumes one mark; a stage cannot be
  marked twice. A value needed twice is *shared*, and the naming
  principle stands: a name is the mark of sharing, so the anonymous
  mark is single-use by definition. (Near fan-out already has taps,
  which bear repetition.)
- **Terminal only.** No stage or binder follows a mark, and a
  mark-terminated line cannot be continued by a leading arrow
  (pointed error — its value is spoken for). Mark-and-continue is
  spelled with the existing pronoun: tap the chain and mark the
  resumed line.
- **Naming and marking are exclusive.** `=> name ^` is rejected; a
  named value is shared and referenced by its name.
- **Marks desugar at parse**: a use resolves to a direct wire to the
  marked port; the representation never contains one. Marks are
  value-sort only — the flow side has its own pronouns (`~`, `~^`,
  lane labels).
- **Unconsumed marks are legal input** — an unconsumed mark is just
  a dangling output, which the node set permits — but the span lint
  flags them, and flags any mark whose use is more than a statement
  or two away: pronouns for adjacency, names for distance, enforced
  as a warning, never a rule. Because the pendingness desugars to
  nothing, an unconsumed mark does not survive a round-trip; the
  canonical printer never emits one. (The editor's pending mark —
  `program-editing-design.md` — is this same remember-then-use
  gesture at the session level, and it serializes with its own
  statement for exactly this reason.)
- The printer emits marks under the same implicitness thresholds as
  taps (open question 5): single-use, with the use landing within
  the next statement or two. Anything else prints named.

Now, you might wonder why marks and taps are two symbols rather than
one pronoun doing both jobs. It turns out the two need *opposite
lifetimes*. Tap antecedents **replace** — leading `|`s bind to the
nearest tap-minting line, and a new minting line supersedes it —
which is what keeps taps trackable under repetition. Marks must
**accumulate** — several contributor lines pend their values before
one consumer takes them all — and be consumed linearly. One symbol
carrying both rules would read worse than two symbols carrying one
rule each; the glyphs are cheap (open question 3), the separation is
the commitment.

One more variant is recorded as rejected. You might wonder why the
consuming line can't just gather *unmarked* dangling lines
implicitly — the race-lane shape without labels, several bare chains
consumed by the next arrow-led line. It turns out this collides with
"a leading arrow continues the previous line's chain," and worse, it
would silently convert today's legal build-and-ignore statement into
a pending operand. Contribution must be opt-in per line, which is
exactly what the terminal mark is. (This is a settled rejection —
please don't re-propose it without new evidence.)

## Lanes: labeled lines

Branch-shaped constructs — case splits, races, multi-branch
collects — are written one lane per line, `label:` first, no
separator. (No separator is deliberate: it frees `|` to mean exactly
one thing, the wire junction.) A lane line's chain starts from that
lane's value port.

A case split used linearly, with reconverging lanes gathered by an
exhaustive collect:

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect                  -- gathers the lanes: the case close
-~> collect                  -- closes the list flow
=> out
```

Lanes that terminate independently (each ends in its own `=>`) —
the partition idiom, where each lane's bare `join` is the filter
(alt flow into list flow, both implicit):

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens
  Odd:  -~> join -~> collect => odds
```

### The gather rule

How does the parser know where a group of lanes ends and what
consumes them? The rule is stated without any reference to
indentation — the parser never reads indentation, only line
structure:

A *lane line* is `label: chain` — the label either a bare alt name
or an explicit flow reference — or `value~` (an implicit branch; see
below). A *lane group* is a maximal run of lane lines. Bare-alt
labels resolve against an antecedent multi-port stage (the statement
the group follows); flow-reference labels and implicit branches are
self-identifying, so groups made of them need no antecedent. The
first arrow-led line after the group consumes the group's branches
(subsequent arrow-led lines continue the chain normally) — except
that a lane ending in a naming stage (`=> name`) is *deferred*: it
contributes no branch to the gather, and its flow must be terminated
elsewhere, by name. A lane may also terminate its flow within its
own chain (the partition idiom above); if every lane is deferred or
self-terminating, no gather follows and the next line is a fresh
statement. Provisional restriction: a lane's chain is one logical
line — a lane complex enough to span lines should name the split and
use projections. This rule is the one place the notation leans on
line structure rather than pure wiring; it is flagged under "Open
questions."

### Standalone branch collects

When a split is named because its ports are consumed non-linearly,
the collect labels its lanes by flow reference instead of bare alt
name. Flow-reference lanes are self-identifying, so the group needs
no antecedent and the collect is written postfix, as the gather:

```
resp -> split status of Ok, Redirect, ClientError, ServerError => h
~h.ClientError: h.ClientError
~h.ServerError: h.ServerError
-~> collect => errCode, ~err   -- partial collect: value + merged flow
~h.Ok:       "ok"
~h.Redirect: "moved"
~err:        errCode -> describe
-~> collect => report
```

(A keyword-first spelling — `collect` above its lanes — is accepted
input, like prefix application; the postfix gather is canonical.)

Coverage is read off the cells, and the binder arity shows it — a
partial collect has the merged-flow output, a covering one does not
(`partial-collect-design.md`: one node, port inventory read off
coverage).

### Implicit branches

A branch value that carries context can supply its flow implicitly —
read off its path, like every other implicit flow. Inline, no new
mark is needed: the `-~>` arrow sorts the whole comma list, so
`y, (~cs.Nothing: 0) -~> collect` says each unlabeled item crosses
with its flow. On a lane line there is no arrow to do the sorting,
so the mark is a suffix sigil, `value~`. The suffix is the noun form
of the arrow: prefix `~y` is *the flow port of node y*; suffix `y~`
is *the value y together with the flow it lives in* — different
things, mirror-image marks. A context-free branch value (a constant)
has no path to read, so it must stay labeled; the checker demands of
read-off flows exactly what it demands of labeled ones (cells of one
bundle, pairwise disjoint, coverage read off the cells). Large
collects probably shouldn't be written this way — labels document
the branch-to-cell correspondence — but the form is consistent with
the other implicit areas, and consistency is what makes them
learnable as one rule.

### Lanes spread across the program

The fused lane form is sugar for the named form — lanes mint the
split's reference internally and each label is the projection. The
named form is the general one, and it fully honors the no-scope
principle: nothing requires a split's branches to be described
together. One alt's work can be built, unrelated statements can
intervene, and the other alts and the collect can come later —
membership is dataflow, not adjacency:

```
m -> split isJust of Just, Nothing => cs
cs.Just -> double => x
-- … unrelated statements …
~cs.Just:    x
~cs.Nothing: 0
-~> collect => out
```

Mixing is fine too: an alt handled as a fused lane deferred by
naming, the rest supplied at the eventual collect — the deferred
lane contributes no branch to a gather (the gather rule), so this
parses correctly even with the lanes adjacent:

```
m -> split isJust of Just, Nothing => cs
  Just: -> double => y
y~
~cs.Nothing: 0
-~> collect => out
```

Spread-out authoring is a path, not a reading — the representation
keeps only the wiring, so the canonical reprint regroups statements
into its own order ("many authoring paths, few readings" applied to
statement order itself). And an unrelated flow opened and closed
between the split and its collect raises no false crossing signal:
its span is contained, and the derived indentation follows semantic
depth, so it prints at its own depth, visibly not nested in the
alts.

### Races and the concurrent join

Races are lanes too — the lane label carries the pairwise
input-to-output correspondence across the barrier (no tagged union
exists between the race and its collect; that is the no-bottlenecks
principle in text). A race's lane labels *declare* lane names
(interpreted by the gather line's keyword) rather than referencing
an existing split, and its gather arrow is plain `->` — contenders
are values with no flow riding:

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

The concurrent join (product barrier) merges sibling flows —
genuinely not on one path, so its operands are named; in the
current lean it is flow-only and values combine in the merged
context:

```
~A, ~B ~> join all => ~ab
x, y -> add -~> collect => sums
```

If barrier value rows land (the open question shared by spec-Join,
race, and partial collect — "k branches × m value rows"), lanes
extend the same way, each row binding its crossing by label. Noted,
not committed — this is deferred on the representation question, not
rejected.

### Candidate: the inline barrier spelling (2026-08-04, needs work)

Status: **a possible candidate**, recorded from a design
conversation; not adopted, and possibly needing more work.

The lane form above severs, in text, exactly the thread the
bundle exists to preserve: the contender sits in an input lane,
its continuation in an output lane, and the reader links them by
channel name. (The input lanes also read right to left —
`fetch: fetchD` puts the sink before the source — an inconsistency
noted in the same conversation.) The candidate keeps each
contender and its continuation on one line by spelling the barrier
*inside* the chain:

```
fetchD -~[race=>|]> process -> some
timeout -~[|]> none
-~> collect => out
```

The bracket is the barrier crossed mid-chain; `|` inside it joins
by adjacency — the junction-tap convention ("connect to the
adjacent `|` without a name") extended from wire identity to node
identity, in kind rather than in meaning. A named form
(`-~[race => r1]>` … `-~[r1]>`) serves when adjacency degrades
(interleaved races), exactly as named values serve beside taps.

You always track a name along *some* axis; the candidate only
transposes which one. The principle the conversation drew from
that: **fuse the axis that carries the correspondence the
construct exists to protect.** Race's protected correspondence is
contender→continuation (the no-bottlenecks argument names it), so
race fuses the contender's line; a case split's protected
correspondence is the case *set* (coverage, one partition), so
splits keep lanes. Different constructs fusing different axes is
each construct showing its load-bearing correspondence, not
inconsistency.

Known costs, unresolved: `-~[…]>` is a new syntax species (a node
spelled inside an arrow) and if taken should be taken once, as the
general mid-chain barrier spelling (join, collect-until pairs
could harmonize) per the one-spelling-family rule; the covering
collect's scope becomes derived from bracket identity rather than
a named bundle; and cells referenced elsewhere (multi-close, a
partial collect on one cell) still need the named-projection form
— the candidate is an *addition* for linear stories, not a
replacement.

## Flow shorthand: `~` and `~^`

For statements that are not in a chain and take a flow operand with
no value input to derive it from (`delay on`, `open … in`), bare `~`
stands for the innermost live flow at this point in the text and
`~^` the one outside it — counted by depth from the innermost out,
over the textual open stack (de Bruijn indices, if you know the
term; the record calls these *flow anaphora*, i.e. flow pronouns).
The span property (see "The crossing signal") makes them
trustworthy: in a well-formed program the textual open stack agrees
with the semantic context path, so the shorthand cannot lie except
in programs that are already ill-formed. Like every pronoun, they
desugar at parse. The printer emits them sparingly (short range
only).

## Registers: delay and write-back

Loop-carried state (`iteration-with-state-design.md`) appears in
text as two statements — the read half and the write half — matching
the register's two-phase construction (mint the read; wire the step
later). The write-back reads forward — compute, then deposit into
the register's step; the write node's output is the final value:

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum          -- read half; bare `sum` = prev
sum, a -> add -> step of sum => total   -- write half; binder = final
```

`init` is the outside-the-flow initial value, kept syntactically
apart from per-iteration inputs — this is exactly the misplacement
that got `stateful(initial, update)` rejected in
`iteration-with-state-design.md`, and the syntax keeps the two
visibly separate. Cross-referencing registers are ordinary wires —
Fibonacci:

```
steps -> open list => n, ~L
~L ~> delay init 1 => fa
~L ~> delay init 1 => fb
fb -> step of fa => lastA
fa, fb -> add -> step of fb => lastB
```

A write statement's binder may be omitted when the final value is
unused (`sum, a -> add -> step of sum`). This is legal and
important: a write half can be root-unreachable in a complete
program, which is exactly why **a program is a node set with
distinguished outputs, not a root expression** — and why the textual
form is a statement list with declared outputs rather than "the last
expression is the result."

Even here, text never references forward: the write statement refers
*back* to `sum`. That is no accident — every cycle in the language
passes through a register, and a register's write half is its own
node (`iteration-with-state-design.md`, "The Delay back-edge: the
write half is a node") wired in a later act, so a define-before-use
ordering always exists; the productivity check (every cycle crosses
a register) is what guarantees it. The same spelling extends to the
incremental kind's `hold` if its cyclic uses (a var updated by
events computed from its own previous value) get the same read/write
split.

## Diagram boundary

A file holds one or more diagrams. A diagram declares its boundary
ports; outputs are explicit statements (no implicit return — see the
node-set point just above):

```
diagram sumOf
  in xs
  xs -> open list => a, ~L
  ~L ~> delay init 0 => sum
  sum, a -> add -> step of sum => t
  out total = t
end
```

Flow parameters use the sigil: `in ~io`, `out ~io2 = ~c.outer`.
Slots and calls of other diagrams follow the spec's FunctionCall
shape (named args); this section stays deliberately thin until
diagrams are the top-level structure in the code. For the sandbox, a
bare statement list with one `out` is a one-diagram file.

## Under-commitment and completion

A program whose flow structure is under-committed is *writable* —
sibling opens with no declared order, a combining node over
incomparable contexts. The closes name their flows explicitly
(nothing else could say which close is which):

```
listA -> open list => a, ~A
listB -> open list => b, ~B      -- sibling opens; no order authored
a, b -> add => s
s -~> collect ~A => inner
inner -~> collect ~B => out
```

Its meaning is its completion. The authored close order pins the
nesting — `inner` (the close of `~A`) is consumed by the close of
`~B`, so `~A`'s parent is inside `~B` — and the printer renders the
derived insertions as `+` lines (the convention
`time-travel-programs-design.md` already uses), reordering
statements as needed to restore token-order-is-time:

```
listB -> open list => b, ~B
+ listA -> incorporate in ~B
+   -> open list => a, ~A
a, b -> add => s
s -~> collect ~A => inner
inner -~> collect ~B => out
```

> *Note.* The inserted `incorporate` shown above is the pre-Cross
> completion. Sibling opens actually complete with a single inserted
> **Cross** (orientation from the authored close order), not an
> incorporate — an incorporate would erase their mutual independence
> (`product-flows-design.md`). Incorporate remains the completion for
> bringing a *value* into a flow context. A textual spelling for Cross
> is owed when that design lands.

`+` lines are derived, deterministic, and not stored: parse discards
them and re-derivation reproduces them (conservativity, idempotence,
determinism). To override an inference, author the line solid. A
contradictory program (directed constraints cycle) has no
completion; it still parses and prints, and the *error* carries the
witness.

## Worked examples

A recap gallery. First, the core fragment (everything the code
implements today).

Flatten with a shared constant:

```
ten = 10
[[1, 2], [3]] -> open list -> open list -> add(ten) -~> join -~> collect
=> out                                            -- [11, 12, 13]
```

Maybe-double (case split inside a list iteration, fused lanes):

```
maybes -> open list -> split isJust of Just, Nothing
  Just:    -> double
  Nothing: 0
-~> collect
-~> collect
=> out                                            -- [2, 0, 10]
```

Multi-close via a tap:

```
xs -> open list -> | double -~> collect => doubled
| -> triple -~> collect => tripled
```

Partition by filter joins (independent lane terminations):

```
xs -> open list -> split parity of Even, Odd
  Even: -~> join -~> collect => evens
  Odd:  -~> join -~> collect => odds
```

The same meeting point three ways (named, grouped, marked) — the
canonical printer emits the grouped form while the operands stay
short, the marked form as they grow, the named form once anything is
shared or distant:

```
a, a -> mul => a2
b, b -> mul => b2
a2, b2 -> add -> sqrt => c
```

```
(a, a -> mul), (b, b -> mul) -> add -> sqrt => c
```

```
a, a -> mul ^
b, b -> mul ^
^, ^ -> add -> sqrt => c
```

Design-only constructs:

Running sum (register):

```
xs -> open list => a, ~L
~L ~> delay init 0 => sum
sum, a -> add -> step of sum => total
```

Timeout race:

```
fetch:   fetchD
timeout: after(30)
-> race => r
~r.fetch:   r.fetch -> process -> some
~r.timeout: none
-~> collect => out
```

HTTP status partial collect: see "Standalone branch collects" above.

Defer-the-error (commute):

```
xs -> open list -> mayFail -> open option -~> commute -~> collect
=> perElem                    -- loop closed; option layer still open
perElem -> summarize -~> collect => report
```

---

That is the whole notation. The rest of this chapter is the design
behind it: what the textual form is for, what makes it hard, the
principles it obeys, and the roads not taken.

## Why a textual form at all

Two reasons.

**Rapid development.** We need to write and read concrete programs
faster than we can perfect a visual editor. Today the only authoring
path is ReScript smart constructors in `Main.res`; the only reading
path is `ExprPrint`, which is a log renderer, not a language (it is
lossy — `#N` labels are renumbered per render, literals are inlined
heuristically, and there is no parser).

**Automated generation.** Tools — Claude Code among them — work in
text. Even once the visual editor exists, a parse/print pair is the
door through which external tools read, generate, and diff programs.

Requirements that fall out:

- **Parseable**: text → representation, total on well-formed text.
- **Printable**: representation → text, total on every program the
  representation can hold — including under-committed and even
  ill-formed programs, because you must be able to print a program
  in order to talk about what is wrong with it.
- **Round-trip**: `parse(print(p))` is the same program as `p` (same
  nodes, same ports, same wiring — same ids, when ids are printed).
  And `print(parse(t)) = t` on canonical text, so diffs are
  meaningful.
- **Readable**: a human reads a program top to bottom in execution
  order, without reconstructing a graph in their head.
- **Not a second source of truth.** The program of record is the
  representation (eventually the step-DAG of
  `transformation-levels-design.md`). The text is a faithful
  projection that can also author. Per "abstraction is the source of
  truth," anything the text renders that the user did not author
  (completions, derived views) must be visibly derived.

## What makes this hard

The challenges this design has to answer:

1. **The program is a graph, not a tree.** Many nodes have multiple
   output ports — an open has a value port *and* a flow port; a case
   split has a pair per alt; a race has a pair per contender. Trees,
   the shape parsers love, have one route to each subterm. And with
   registers (Delay), the graph is not even acyclic.
2. **Edge lists are complete but unreadable.** Any graph flattens to
   `edge(n1.p1, n2.p2)` triples; nobody can read that. The related
   failure is over-naming: if every seam forces a name, the code
   goes flat — a list of bindings instead of structure. We want
   structure like Lisp's, but for a graph rather than a tree.
3. **No visual crossing signal.** In the diagram, using a flow out of
   order *looks* wrong — wires cross. Text has no 2D plane; some
   analogue of that immediate signal is worth capturing.
4. **No bottlenecks.** Joins and races are barriers with
   pairwise-corresponding inputs and outputs. The text must show
   which input lane an output belongs to without packing values into
   a tuple or tagged union — the exact thing the principle forbids.
5. **Levels.** Level-1 operations (expand, recognize, completion,
   history operations) are statements *about* programs, and derived
   views expose ports you can reference. How does text indicate what
   level a construct lives at, and how does it reference into a
   derived view?

## The central observation: the graph is a tree with seams

The ASG is tree-shaped exactly where nodes have one output port and
one consumer — which is most of value land (literals, applications,
aggregates). It stops being a tree at exactly three kinds of seam:

- **Multi-output nodes**: opens, splits, barriers, registers. One
  node, several ports, several downstream consumers.
- **Fan-out**: one port consumed by several nodes (sharing — which
  is opt-in and load-bearing for meaning).
- **Back-edges**: a register's `step → prev` crossing, the one edge
  species that crosses an iteration boundary.

So the syntax should be **nested/chained exactly where the graph is
a tree, with heavier machinery reserved for the seams** — and the
machinery is graded. Three reference tiers, cheapest first:

- **Chains** — the linear backbone. A value flows stage to stage;
  its flow context rides along (marked by the arrow family); no
  names at all.
- **Pronouns** — short-range shorthand for local seams: junction
  taps (`|`) for nearby fan-out, value marks (`^`) for nearby
  fan-in, lane labels for a split's branches, `~` / `~^` for the
  innermost flows. All of these desugar at parse; the representation
  never contains one.
- **Names** — for anything shared or distant. A name is the mark of
  sharing: anonymous is linear, named is shared, which restates the
  language's own "sharing is opt-in via binding" as a fact the text
  displays.

There is a crisp way to say what the tiers achieve. Call a point of
the graph *dominant* over everything reachable only through it (the
compiler-theory name for this structure is the dominator tree). A
graph's text can nest along that structure — everything reachable
only through one point can be written inside that point's chain,
including local fan-out (taps and lanes). Names are needed exactly
for edges that escape dominance.

## Reading forward

Why is the canonical form forward — `a -> double` rather than
`double(a)`?

A conventional syntax is inconsistent about whether moving forward
through the text moves forward or backward in dependency order:
naming moves backward (`a = …`), application moves backward
(`f(arg)` — the consumer before its inputs), yet statement order
moves forward. This form resolves it: **the canonical text is
consistently forward** — postfix application, chains, right-hand
naming. Forward notation writes producers before consumers at every
scale (a tree-traversal person would say it is a post-order
rendering), so "token order is time," not just "statement order is
time."

This is not a novelty for this repo. The design docs' informal
notation is already forward (`list -> $ => a, xL`, with `->` for
wiring and `=>` for naming), and `ExprPrint` is already a
producers-first renderer — sources first, then the op, chains for
single-consumer runs. The first draft's `name = f(x)` was the
deviation.

(Prefix notation's claim to naturalness is an artifact of which
natural languages designed the existing programming languages;
head-final order — arguments before the operation — is the most
common clause order across human languages.)

**The grammar is permissive; the printer is canonical.** By "many
authoring paths, few readings," parse accepts prefix (`f(x, y)`),
postfix (`x, y -> f`), infix for the operators conventionally
written that way (`a + b`), and both assignment directions
(`name = …` and `… => name`), as in R. The canonical printer emits:
chains and all flow structure forward; small pure-value leaves in
conventional infix/prefix; left assignment for short leaf
definitions (externs, constants), right assignment for chain
results. Printer rules are deterministic, so there is still one
reading.

Right assignment never needs column alignment, because any chain
stage may start a new line — `=>` is just the last stage (the
multi-line doubling example in "Chains across lines" shows it).

## The principles

Eight principles run through the notation. Most of them you have
already seen in action; here they are stated in full, with the
arguments behind them.

**P1. A name is a wire.** A statement binds names to output ports of
the one node it constructs. Names are single-assignment, never
shadowed, global to the diagram. Referencing a name twice is fan-out
from one port — the same node, not a copy. Conversely, writing the
same expression twice makes two nodes: sharing is opt-in via naming,
exactly as it is opt-in via ReScript binding today. This carries the
types-design insight into text: "wires are the type variables" —
text reintroduces the burden the diagram avoided (a name must
faithfully stand for one wire), and single-assignment global names
are the discipline that pays it.

**P2. Two lexical sorts.** Value references and flow references are
lexically distinct: flow references carry a `~` sigil (`~L`,
`~cs.Just`), and the arrows are sorted too (the arrow family).
Confusing the sorts is a parse error, mirroring how `expr` vs
`flowRef` catches misuse syntactically in `Expr.res`. The sigil is
provisional and cheap to change; what is not negotiable is that the
sorts are distinguishable without name resolution. (A third species
may arrive if the visible state thread of
`iteration-with-state-design.md` becomes a wire of its own kind;
reserve room, don't design it now.)

**P3. No lexical scope.** There are no blocks and no delimited
regions: "inside the loop" is a *derived* fact — a statement is
per-iteration because its inputs are — never a syntactic region.
This is the inside-out principle applied to text: a block syntax
would make an expression's interior differ from its exterior,
reintroduce magic names, and be unable to express what the language
allows (multi-close on one opener, a close on a joined flow two
levels up, a race's contenders continuing as themselves).
Indentation exists only as printer output, never as parser input.

**P4. Token order is time.** The canonical text is a producers-first
rendering: every producer appears before its consumers, within a
line and across lines. No forward references exist — even for cyclic
programs, because of how cycles enter the language: every cycle
passes through a register, and a register's write half is its own
node (`iteration-with-state-design.md`, "The Delay back-edge: the
write half is a node") wired in a later act. The one back-edge is
always spelled as a later statement referring back to an earlier
name.

**P5. Barriers are labeled lanes.** A multi-in multi-out barrier is
written one lane per line; the lane label carries the pairwise
input-to-output correspondence. No tuple, no tagged union.

**P6. Authored and inferred structure are distinguished.** Structure
the user did not write — a completion's inserted incorporates and
commutes, a lens's derived view — prints prefixed with `+`, the
textual analogue of the editor's faint rendering
(`time-travel-programs-design.md`). A complete program prints with
no `+` lines; parse ignores `+` lines (they are re-derived, not
stored).

**P7. A statement is a step.** Most statements construct one node —
these are the 1:1 steps of the step-DAG, where "the node *is* the
step seen at level 0." Native level-1 operations (expand, undo,
cherry-pick) are statements too, distinguished not by an annotation
but by what their operands are: names of nodes and steps rather than
wires. Level is read off the operand sort, matching the admission
test ("an operation belongs at level 1 iff its content is a
statement about level-0 programs rather than about values").

**P8. Pronouns desugar at parse.** Taps, value marks, lane labels,
and the flow shorthand are resolved to explicit wiring by the
parser; the representation is always fully explicit. This is what
keeps `$_`-style convenience from becoming `$_`-style fragility: the
pronoun is never runtime or representation state, only reference
resolution. Correspondingly, all pronoun binding is **ordinal, never
spatial** — nothing in the grammar depends on columns or alignment.

## Non-tree shapes: the survey

The pronoun tier grew a piece at a time (taps, then lanes, then the
flow shorthand, now marks); this section checks it against the
catalog of ways a diagram departs from a tree, so coverage is a
verified fact rather than an accumulation. Value shapes first:

| shape | anonymous spelling | falls back to names when |
|---|---|---|
| spine — single-output, single-consumer runs | chains | never |
| one-to-many, near | taps (`\|`), repeated per consumer line | consumers are distant, or many |
| many-to-one, near | marks (`^`) across lines; parenthesized groups inline | operands are distant, or shared |
| diamond — fan-out that meets again | tap + marks | either half outgrows its pronoun |
| distance / heavy reuse | — | always (deliberately: both are facts worth a name) |
| multi-output nodes | projections (`cs.Just`), fused lanes | ports consumed non-linearly |
| back-edge | — | always — the register write half refers back by name (P4 forbids the forward reference) |

The diamond, zero names — `parse`'s anonymous result feeds `max` and
`min` through the tap; their results meet in `sub` through the
queue:

```
data -> parse -> | max ^
| -> min ^
^, ^ -> sub => range
```

This earns a sharper form of the dominance claim made in "the graph
is a tree with seams." Chains nest along dominance; taps extended
anonymous reference to fan-out *within* a dominance region
(everything reachable only through the tapped point); marks are the
missing mirror — a consumer that all its contributors feed into can
now gather them anonymously, the mirror-image direction the tier
lacked (post-dominance, in the compiler-theory vocabulary). What
still requires a name is exactly what should: sharing beyond a tap's
short reach, and distance beyond the lint's tolerance.

Flow shapes were already covered and are listed for completeness:
nesting by chaining or `in`, reconvergence by lane gathers, layer
reordering by commute chains, merging by join, sibling products by
Cross — none of them changed by the additions above, since marks are
value-sort only.

## The crossing signal: spans, verticals, indentation

The diagram shows an out-of-order flow use as a wire crossing. The
text has analogues in one dimension:

- **Spans.** A flow's *span* runs from the statement that opens it
  to its last termination. Because token order is time (P4), nesting
  shows as span containment and crossing shows as overlap: two
  *structural* flows whose statements interleave without containment
  is exactly the interleaving that needs an explicit relation (a
  join, a commute, a declared `in`). Effect flows are exempt — they
  commute freely and may interleave without remark ("most
  restrictive wins"). The **span lint** flags un-nested overlap of
  structural flows: a presentation-level early warning of the facts
  the provenance check establishes properly.
- **Verticals.** Junction taps and lane labels already draw the
  short vertical wire segments — local fan-out is *visible* as the
  `|` margin.
- **Indentation.** The canonical printer indents each statement by
  the depth of its flow context. Indentation is derived — the parser
  ignores it entirely (P3) — but on a well-formed program it
  reproduces the shape a scoped language would have had, without
  being scope. On a time-travel program, no consistent indentation
  exists; the printer falls back to flat and the completion's `+`
  lines say why. That failure-to-indent is the textual cousin of the
  visible crossing.

Now, you might wonder why the language doesn't make whitespace
significant — let indentation *state* the nesting, the way Python
does. It turns out this would create a second, authoritative
statement of nesting that can disagree with the wiring. One source
of truth; indentation is a view. (This is a settled rejection —
please don't re-propose it without new evidence.)

## Levels

Two senses of "level" need textual answers; they are different
things and get different answers.

**Flow nesting depth** gets no numerals and no annotation. Depth is
structural: an open `in ~L`, chained joins, chained commutes.
"Level-2 join" is two join stages. This follows the binary-join
correction — the old `Joined(Joined(…))` wrapper counting is
superseded by explicit staging.

**Transformation levels** are the real question. The stored program
is one step-DAG whose 1:1 steps read as node declarations — which is
exactly what a statement is (P7). So:

- A **snapshot file** (the common interchange case — "the program at
  this head") is a statement list containing only level-0
  statements. Every statement mints nodes; the file is the node set.
- **Level-1 statements** are the built-in catalog entries, written
  as statements whose operands are *names of nodes/steps*, not
  wires:

  ```
  sum -> expand => sumX      -- materialize sum's expansion, named
  sum!acc -> double => w     -- lens reference: DerivedPort(sum, acc)
  ```

  `expand` is a recorded step (its parts become addressable — the
  materialize mode); `!` is the lens mode — referencing a principal
  port of the *derived view* without materializing anything.
  `sum!acc` is the textual `DerivedPort(nodeId, portName)`, and only
  principal ports are addressable through it, so ill-formed
  references stay unrepresentable. No level marker is written or
  needed: `expand` is level-1 because its operand is a node, by the
  admission test.
- **History files** — serializing the full step-DAG including undo
  and cherry-pick — are deferred (set aside for later, not
  rejected). Only the constraint is pinned: the snapshot grammar
  must remain a strict subset of the history grammar (a snapshot is
  a history with only 1:1 steps).

**Stable identity.** Node ids are load-bearing across versions
(diff, blame, completion hints anchored to ids). Names carry
identity *within* a file; across versions, the printer can be asked
to emit ids as suffixes (`=> sum@n42`). Default output omits them;
tools that diff or patch request them. Parse of an id-less file
mints fresh ids — correct for generated-from-scratch programs, and
the reason round-tripping *with* ids matters for edits.

## Well-formedness: parser vs checker

The parser owns only what is lexically decidable:

- sort discipline (the right sigil and the right arrow where each
  sort is required);
- single assignment, definition before use;
- statement/stage shape per keyword;
- pronoun resolution (taps, value marks, lanes, `~`/`~^`) — all
  desugared to explicit wiring per P8, with their ordinal binding
  rules.

Everything else stays where it belongs — checks on the
representation, shared with every other authoring path: port
existence, flow-borne locality, join operand adjacency, collect
coverage and partial-collect cell disjointness, productivity and
one-write-per-register, provenance comparability with its two clash
flavors (time travel — completable; bundle mixing — not). The text
adds *no* checks of its own; the span lint and the indentation
signal are presentation-level renderings of checker facts. A file
can parse and still be ill-formed — necessarily so, since printing
ill-formed programs (to show the witness) is a requirement.

## Correspondence to the representation

For the fragment the code implements, the mapping to `Expr.res` is
direct:

| text | representation |
|---|---|
| `5`, `js "…"` | `Lit(JsAst.expr)` |
| `x, y -> f` (or `f(x, y)`) | `App({fn, args})` |
| `xs -> open list => a, ~L` | `Open({flow: ListIter, input})`; `a` = the node in value position, `~L` = `NodeFlow(node)` |
| `m -> open option => v, ~O` | `Open({flow: OptionIter, input})` |
| `-> split d of A, B => cs` | `Open({flow: CaseSplit({alts, discriminator}), input})` |
| `cs.A` / `~cs.A` | `branch_(NodeFlow(cs), "A")` in value / flow position (before the ports migration — both are now port refs, `src/Program.res`) |
| `-~> join` (then `-~> collect`) | `close_(join_(NodeFlow(inner)), value)` — the chain determines the opener chain the compiler walks |
| lane `Even: -~> join -~> collect` | `close_(filter_(NodeFlow(branch)), value)` |
| lane group gathered by `-~> collect` | `caseClose([{altName, flow, value}, …])` |
| tap `\|` / mark `^` / flow shorthand `~` | nothing — desugared to explicit wiring |

Under the ports migration (landed) the right column simplifies
(projections become `ValuePort`/`FlowPort` refs; Join becomes the
binary node and the chain's adjacency bookkeeping moves to the
checker), and the text does not change — the point of writing the
text against ports, chains, and names rather than against the
current wrapper encoding.

## Roads not taken

Each of these was considered on the way to the design above. The
reasons are part of the record — please don't re-propose any of the
settled ones without new evidence.

**Conventional name-first, head-first syntax.** Now, you might
wonder why the language doesn't just write `b = double(a)`, like
every mainstream language — and indeed the first draft of this
design did. It is familiar, to people and to the LLMs that are half
the audience. It turns out the familiarity hides an inconsistency
about reading direction: naming and application move backward
through dependencies while statement order moves forward. Rejected
as the *canonical* form; retained in full as accepted input, which
recovers most of the familiarity benefit at zero cost to the
one-reading property. (Be precise about what is rejected here: the
spelling survives as an authoring path; only its candidacy as the
printed form is settled and closed.)

**Brace-delimited fan-out** (`-> { -> f => a | -> g => b }`; also
first draft). You might wonder why fan-out isn't a braced group of
sub-chains. It turns out this fails twice over. First, braces read
as scope in a language whose defining move is that there is no
interior scope (P3). Second, the closing brace asserts a non-fact:
it says "this wire is not used again," but the language expresses
the end of interest in a value by silence — termination of a *flow*
is meaningful and explicit (a collect, a join); termination of
interest costs nothing and should say nothing. Junction taps and
lanes replace it. (Settled rejection.)

**Significant alignment.** You might wonder why taps couldn't bind
by column — the `|` on line two directly below the `|` on line one.
Horizontal alignment as syntax (matching taps by column, lanes by
position on the page) is attractive and a known disaster; all
pronoun binding is ordinal (P8). (Settled rejection, and the sibling
of the significant-whitespace rejection under "The crossing
signal.")

**Scoped implicit parameters** (`_`, Scala/Kotlin's `it`, Raku's
alphabetically-ordered block parameters). You might wonder why the
pronoun tier isn't one of these well-known devices. It turns out all
of them bind the pronoun to a *scope* — the nearest enclosing block
or lambda decides what `_` means — and this language has no blocks
to bind to (P3); adding delimiters just to host a pronoun would
reintroduce the interior/exterior distinction the whole design
refuses. The mark queue is the non-scoped replacement: its "binder"
is text order itself — ordinal adjacency, the same mechanism taps
and lanes already use — so no region of the program reads
differently from any other. (Settled rejection.)

**Stack combinators** (the concatenative languages' dup/swap/rot).
The mark queue is recognizably a stack-family discipline — values
pend, then are consumed — so you might wonder why not go all the way
to Forth-style combinators. It turns out concatenative languages
spend their readability budget on *rearranging* the pending values,
which is where those programs die. Here rearrangement is
deliberately impossible: FIFO order, linear consumption, and
anything shared or reordered takes a tap or a name. The queue is
stack passing with the juggling removed. (Settled rejection of the
combinator vocabulary; the queue itself is the design.)

**Raw edge list / JSON dump.** Complete, trivially parseable,
unreadable — rejected as the primary form. (A mechanical JSON
projection of the node set may still exist for tooling; it needs no
design.) Note the statement form *is* an edge list, factored: one
line per node, inputs referenced inline — with the tree-shaped
majority collapsed into chains.

**S-expressions.** You might wonder why not Lisp syntax, since we
asked for "structure like Lisp's." It turns out s-expressions are
tree-biased: sharing and cycles need labels anyway, at which point
the notation has all of this design's machinery with less
readability, and the tree bias invites writing programs as
expression trees, which the language specifically is not. (Settled
rejection.)

**Keep authoring in ReScript (status quo).** Fine for the test
suite, useless for external tools: not parseable without a ReScript
toolchain, not printable back, and the smart-constructor layer is an
authoring convenience, not a stable interchange surface.

(Two more rejections live with their constructs, where a reader of
that section needs them: the nearest-first binding rule for marks,
and the implicit gathering of unmarked dangling lines — both in
"Value marks.")

## Open questions

The language hasn't decided these yet.

1. **The gather rule.** The rule as stated (lane lines — labeled,
   flow-ref, or `value~`; self-identifying groups need no
   antecedent; deferred lanes contribute no branch; race-style
   gathers interpret declaring labels) is ordinal throughout, but it
   is the one place the notation leans on line structure rather than
   pure wiring — the place a critic could say the syntax grew a
   scope after all. Needs the most careful specification; the
   provisional one-logical-line restriction on lanes (name the split
   for anything bigger) keeps it small until then.
2. **Tap antecedent range.** Proposed: nearest preceding tap-minting
   line; consecutive continuation lines may reuse; a new tap-minting
   line replaces. Alternatives (per-paragraph scope, explicit tap
   counts) exist if the proposed rule proves too subtle in practice.
3. **Glyph budget.** `->`/`~>`/`-~>`, `=>`/`=`, `|`, `^`, `~`/`~^`,
   the branch suffix `value~`, `!`, `@`, `+`, grouping `( )`. Each is
   cheap to respell; the family structure (sorted arrows, one meaning
   per glyph — `|` is only ever a junction) is the commitment. One
   reuse to record: `@` here is the id suffix (`sum@n42`), while the
   retired informal glyphs used `@` for collect (`core-model.md`) —
   harmless since those are retired, but the naming sweep should
   notice. Watch `-~>` vs `~>` legibility, and whether the
   prefix/suffix `~` mirror (`~y` the flow port, `y~` the value with
   its flow) is mnemonic or too subtle in practice — alternatives:
   `y&`, a headless `y -~`. New watch item: the value mark `^` shares
   a character with the flow shorthand `~^` — both "reach back,"
   which may be mnemonic or may be confusing; alternatives if it
   proves the latter: `` ` ``, `'`, `&`.
4. **Stage extra-argument convention.** `-> f(e)` = topic-first.
   Fine for the current catalog; revisit if operations with
   non-leading principal inputs appear.
5. **Printer implicitness thresholds.** When to chain vs tap vs
   name; when to emit `~` shorthand (rarely or never); when a value
   leaf prints infix. ExprPrint's inlining heuristics are the seed.
   Canonical-form stability matters more than the particular
   choices.
6. **Alt-port naming scheme.** Bare alt name on both value and flow
   side (disambiguated by sigil) vs `(alt, Value)`/`(alt, Flow)`
   pairs — should match the spec's `outputName` so text and spec
   never need a translation table.
7. **Barrier value rows.** If Join/race/partial-collect grow the
   "k lanes × m value rows" shape, lanes extend by labeled rows;
   blocked on the representation question, correctly.
8. **Ids in interchange.** Is `@id` on every binder acceptable for
   tool round-trips, or does edit-patching want a sidecar (name ↔
   id map)?
9. **History serialization.** Undo/cherry-pick/materialize as
   statements are sketched, not designed; snapshot-⊂-history is the
   only commitment.
10. **Effect-flow threading.** Effect operations rebind their flow;
    the docs' prime convention suggests wanting light threading for
    long effect chains. Deferred until effect flows are closer to
    implementation.
11. **Mark discipline details.** Whether a consuming line taking
    fewer than all pending marks should warn (partial consumption is
    the one place the reader must track the queue across statements);
    the span lint's exact tolerance for mark-to-use distance; whether
    a lane's chain may end in a mark (presumably yes, as a deferred
    lane — it would contribute no branch to the gather, mirroring
    `=> name` deferral — but the gather rule should say so
    explicitly); and whether stage-argument chains (`-> add(b ->
    sq)`) ever print canonically or stay input-only.

## Implementation path

Baby steps, each independently useful:

1. **Core-fragment printer.** `TextPrint.res`: render any current
   `Expr.expr` in this notation. This grows directly out of
   `ExprPrint` — the topological sort, greedy chain detection, and
   name-at-fan-in machinery transfer; what changes is names instead
   of `#N`, taps for local fan-out, lane groups for case closes, and
   totality. One notation instead of two, eventually.
2. **Core-fragment parser.** `TextParse.res`: the grammar covering
   exactly today's `Expr.res` (lit/app/extern in all three fixities,
   list/option opens, splits with projections and fused lanes, bare
   and explicit join/filter/collect, taps). Output: `Expr.expr`.
3. **Round-trip tests.** For each of the 80 suite programs:
   `print → parse → compile → run` agrees with building the Expr
   directly; and `print(parse(t)) = t` on the printed text. Pin a
   few golden files.
4. **Span lint + derived indentation.** The presentation-level
   crossing signal, once the printer exists to host it.
5. Then track the representation: first-class ports (projections
   become port refs), partial collect, `+`-completion printing —
   each lands in the text the day it lands in the representation.
