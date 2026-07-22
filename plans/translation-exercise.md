# Translation Exercise: Sampled Loops in the Textual Form

This document takes concrete programs from the real-loop surveys
(`real-loop-survey.md`) and writes them out in the textual form
(`textual-representation-design.md`), using the designed and candidate
constructs as they stand. **Nothing here is adopted, and nothing here
executes.** The point is contact: to see where the vocabulary and its
notation carry a real program cleanly, where they strain, and where
they have no spelling at all. Where the notation lacked a form, one was
invented on the spot; every invention is marked `(provisional)` and
gathered in one table so it cannot be mistaken for designed syntax. The
findings feed the ranked improvement list at the end, which feeds
`open-problems.md`.

The sources are drawn from the surveys' already-sampled loops, so they
inherit the surveys' no-filtering credibility, but the **selection among
them is deliberate** — chosen to span the survey classes and the breadth
set from trivial to hardest. No frequency claims are made here;
frequency lives in the survey document.

## Why transcription, not classification

The surveys sampled sixty loops and thirty orchestration sites and
classified each against the vocabulary. Classification ("this is
end-when plus a readout") is cheaper than transcription ("here is the
program, written out"). A construct can classify well and still be
unwritable, because classification never has to spell the wiring, order
the statements, or discover that two constructs both want the same seam.
Transcription does. The rules of the exercise:

- **Translate honestly.** Every statement of the source program must
  land somewhere in the translation — or its omission must be called
  out. No smoothing a sample into the shape the vocabulary prefers.
- **When stuck, invent — and mark it.** If the language is too awkward
  to carry a sample, mint a provisional spelling or construct, flag it,
  and record what the awkwardness was. Inventions here are strawmen for
  the design conversations, not proposals with standing.
- **Count the strain.** For each translation: what was smooth, what was
  verbose, what needed invention, what was impossible.

## Provisional spellings introduced

Everything below marked `(provisional)` was invented during this
exercise. Gathered here first so the translations read without surprise.
Each is discussed where it first appears and again in the findings.

| spelling | meaning | why it was needed |
|---|---|---|
| `~F, ~stop ~> end-when => ~W` | end-when standalone form (subject, stop), per `end-when-design.md` | end-when has no textual spelling (owed per `open-problems.md` Tier 3) |
| `end-when … inclusive` | the inclusive/exclusive bit (keep or drop the stopping firing) | the bit exists in the design, has no spelling |
| `~W ~> discharge => term` | terminator-only readout of a flow (a collect that keeps no prefix) | first-match wants the terminator and nothing else; collecting a dummy constant is the only designed spelling |
| `-~> collect last`, `collect any`, `collect set` | reduce-closes by named operator (last-of, or, dedup-set) | reduce-close exists; per-operator spellings and identities are the open identity question |
| `k, v -~> collect keyed` | keyed collect (last-wins map) | keyed collect is used throughout the record, never spelled |
| `open entries => k, v, ~E` | opening a map/assoc yields two value ports | pair-typed elements otherwise cost `fst`/`snd` externs at every use |
| `source js "…"` | an external pull source as a flow (FFI stream node) | pumps (survey class 4) cannot start on the page at all |
| `repeat -> open self => ~R` | the self-driven flow (repetition without a source) | polls/retries (survey class 5) cannot start on the page at all |
| `~io ~> op(args…) => ~io'` | an effect operation as a stage on an effect-handle chain | per-firing effects — the most common loop payload — have no spelling (textual open question 10) |
| `-> fail` | a value-position stage minting a failure terminator that propagates | "do bodies raise?" is open; validation walks need *something* |
| `~C ~> split-when => ~seg, ~elem` | split-when minted with its boundary unwired | see next row |
| `~alt ~> boundary of ~seg start-next` | late-wiring split-when's boundary operand, with the destination bit | the boundary reads per-segment state, i.e. state defined on split-when's own output — the operand is a back-edge |
| `~seg ~> collect list => lines` … `x -> value of lines` | a collect minted early, its value input late-wired | the running view is read *before* the collect statement can appear; the value input is a back-edge |
| `lines!sofar` | the running view of a collect (state port of the derived augment form) | designed in `variable-rate-consumption-design.md` Part II; lens `!` was the natural fit |
| `Plain:` (bare lane) | an identity lane — the alt's payload passes through unchanged | "else leave it alone" is constant in real code; the notation has no blessed identity lane |

One pattern above deserves a name, because three rows share it: `step
of`, `boundary of`, and `value of` are all **late-wired operands** — a
node minted in one statement, one input wired by a later statement that
refers back to it. The register design already has exactly this (mint
the read half, wire the step later — `iteration-with-state-design.md`,
"The Delay back-edge: the write half is a node"). The
exercise found that the same two-phase spelling is demanded by every
construct that sits on a cycle, not just Delay. Taken up in the findings.

---

# The translations

Grouped by how they went: the core (smooth), the everyday gaps (writable
with inventions), the breadth set (the hard ones), and concurrency
(partly out of designed territory).

## Group A — the core holds

### A1. Map + collect (survey 1, python 8)

Source:

    for file in build_files:
        outputs.append(os.path.join(output_dir, file[prefix_len:]))

Textual form:

```
stripJoin = js "(f, dir, n) => path.join(dir, f.slice(n))"
buildFiles -> open list -> stripJoin(outputDir, prefixLen)
-~> collect => outputs
```

One chain, no names inside it. The imperative append-to-an-outer-list
reads as what it is — a collect. Nothing to report, which is the point
of including it: the center of the language costs one line where Python
costs two.

### A2. One walk, three outputs (survey 1, ruby 6)

Source (the surrounding function repeats this walk three times, for three
different outputs, because each block can only build one thing):

    ucm.each { |cm| methods.concat cm.method_list }

Multi-close via taps does all three in one walk:

```
ucm -> open list -> | methodList -~> join -~> collect => methods
| -> attrList  -~> join -~> collect => attributes
| -> constList -~> join -~> collect => constants
```

The tap carries the element to three chains; one logical iteration,
three collects. Here the translation is *better* than the source — the
language's multi-close shape is what the Ruby author would have written
if the host language allowed it. Smooth; the tap rule worked exactly as
specified.

### A3. Chained registers — the numeric scan (survey 2, mpmath 1)

Source:

    b = one; s = 0
    for k in range(n):
        b = 2*(n+k)*(n-k)*b / ((2*k+1)*(k+one))
        s += b * S[k]
    value = s / d

The wiring subtlety the survey flagged: `s`'s step reads `b`'s *updated*
value. In the textual form:

```
range(n) -> open list => k, ~L
~L ~> delay init one => b
~L ~> delay init 0   => s
b, k -> stepB(n) => bNew          -- the recurrence, one App
bNew -> step of b                 -- final b unused; binder omitted
S, k -> index -> mul(bNew) -> add(s) -> step of s => total
total -> div(d) => value
```

Genuinely smooth — arguably the cleanest translation in the set. The
within-iteration chaining (`s` reading `bNew`) is exactly what the
survey's finding 2.2 predicted: an ordinary value wire, no second state
port. In text it is simply *naming the shared value* (`bNew`), which
sharing-is-naming renders load-bearing rather than incidental. The write
half's binder giving the final value (`=> total`) made the post-loop
readout free. `range(n)` was accepted as a value-level list builder
without comment; whether iteration-by-index deserves better than
materializing a range is a small open note (see B5, where indices are
load-bearing).

### A4. Conditional carry, both readings (survey 1, js 1)

Source:

    let command
    for (const [k, v] of Object.entries(commands)) {
      if (d.includes(k)) { command = v }
    }

This reads two ways — filter+last (collect vocabulary) or a register —
and neither is forced. Both translate.

Filter + last-of:

```
commands -> open entries => k, v, ~E        -- (provisional binder)
k -> split includedIn(d) of Hit, Miss => m
~m.Hit: v~
-~> collect last => command                 -- (provisional operator)
```

Register:

```
commands -> open entries => k, v, ~E
~E ~> delay init none => cmd
k -> split includedIn(d) of Hit, Miss
  Hit:  v -> some
  Miss: cmd
-~> collect -> step of cmd => command
```

Both are short and both are readable; the two-readings freedom survives
into text. Two strains, both small but both recurring for the rest of
the exercise:

- **Pair-shaped elements.** `Object.entries` yields pairs; without the
  provisional two-value binder, every use of `k` and `v` costs a
  `fst`/`snd` extern. Real code iterates maps *constantly* (six-plus
  samples across the surveys). The representation question — does an
  open over an assoc have two value ports? — is small and worth
  settling; the textual answer (multi-binders already exist: `=> a,
  ~L`) is ready as soon as the ports exist.
- **`collect last` names a reduce-close by its operator**, and
  last-of's identity is "no value," so its result is option-shaped —
  the operator-identity open question (`iteration-with-state-design.md`)
  surfacing at the syntax level. The register form dodges it by making
  `init none` explicit.

## Group B — the everyday gaps

### B1. First-match with computed result and a default (survey 1, js 3)

Source:

    for (const saveType of saveTypeMap.keys()) {
      if (hasSubKey(pkg, saveTypeMap.get(saveType), name)) {
        if (saveType === 'peerOptional' && ...) { return 'peer' }
        return saveType
      }
    }
    return 'prod'

End-when's flagship composition — stop, discharge, readout split:

```
saveTypes -> open list => ty, ~L
ty -> split hasSubKey(pkg, name) of Hit, Miss => m
~L, ~m.Hit ~> end-when => ~W               -- (provisional spelling)
~W ~> discharge => term                     -- (provisional)
term -> split tag of Stopped, RanOut
  Stopped: -> adjustPeerOptional(pkg, name) -- the inner if
  RanOut:  "prod"
-~> collect => saveType
```

The composition works and reads well: the walk, the cut, the readout —
three statements plus a case collect, against the source's three exit
paths hidden in control flow. The strains:

- **End-when has no spelling.** The standalone flow-op form (`~L, ~stop
  ~> end-when => ~W`) follows the concurrent-join precedent (`~A, ~B ~>
  join all => ~ab`) and reads naturally. A chain form (`-~> end-when
  ~m.Hit`, value riding) will also be wanted — B3 uses it.
- **The terminator-only readout has no honest form.** Nothing here
  collects a prefix; the only designed way to reach the terminator is a
  whole-flow collect, and the only way to collect with no per-firing
  value is the collect-a-constant idiom (`5 -~> collect ~W => walked,
  term` — then discard `walked`). That spelling is *technically*
  available and reads as a joke. `discharge` (a collect that keeps no
  prefix) is the strawman; alternatively a discard binder (`=> _, term`)
  would make the designed form tolerable. Either way the (prefix,
  terminator) two-output collect needs its binder-arity convention
  written down — this exercise assumed `=> prefix, term` by analogy with
  the partial collect's `=> errCode, ~err`.
- **`split tag of …`** — case-splitting an already-tagged value (the
  discharged terminator) makes the discriminator an identity. Reads
  fine; discharge + split-on-tag is going to be the single most common
  readout idiom and may eventually deserve fusion sugar (lanes directly
  on `discharge`).

### B2. Validation walk with a raise (survey 1, python 10)

Source:

    for (lib_name, build_info) in self.libraries:
        sources = build_info.get('sources')
        if sources is None or not isinstance(sources, (list, tuple)):
            raise DistutilsSetupError(...)
        filenames.extend(sources)

The abort-the-whole-walk raise. With designed vocabulary only, this is
end-when again — stop on the bad element, discharge, re-raise at the
readout:

```
libraries -> open entries => name, info, ~L
info -> get("sources") => srcs
srcs -> split isSourceList of Ok, Bad => v
~L, ~v.Bad ~> end-when => ~W
v.Ok -> open list in ~W -~> join -~> collect => filenames, term
term -> split tag of Stopped, RanOut
  Stopped: name -> setupError -> fail       -- (provisional)
  RanOut:  filenames
-~> collect => result
```

It expresses the semantics exactly (including that elements after the
bad one are never demanded), but count the cost: **seven statements for
what Python says in four lines**, and the reader must decode "stop early
and report" from an end-when + discharge + re-raise pattern. The design
record already points the right way — failability's propagate-by-default
means a failure terminator minted in the body should just flow to the
collect's discharge — but "do bodies raise?" is flagged open in the
failability residue, and this is the everyday case that question gates.
The provisional `-> fail` (a value-position stage that mints a failure
terminator, propagating outward) collapses the translation to:

```
libraries -> open entries => name, info, ~L
info -> get("sources") => srcs
srcs -> split isSourceList of Ok, Bad
  Ok:  -> open list -~> join
  Bad: name -> setupError -> fail
-~> collect => filenames
```

which is the right size. The gap is not notation — it is the undesigned
failability residue, and this translation is a concrete demand to put in
that row's file.

### B3. Filter + per-element effect (survey 1, js 8)

Source:

    for (const key of keys) {
      if (key.match(new RegExp(section + ':'))) {
        this.finishTracker(section, key)
      }
    }

The most common loop shape in both surveys (stateless per-element work,
often effectful) — and the first translation that **cannot be written at
all** with designed vocabulary, because per-firing effects have no
construct and no spelling. The filter half is fine:

```
keys -> open list => key, ~K
key -> split matchesSection(section) of Hit, Miss => m
~m.Hit ~> join into ~K => ~hits
```

Then, per firing of `~hits`, call `finishTracker`. The record's effect
story (`custom-flows.md`) threads a handle flow through operations;
textual open question 10 defers the threading spelling. Inventing the
minimum — an effect op as a stage on the handle's chain:

```
in ~io
~io ~> finishTracker(section, key) in ~hits => ~io'   -- (provisional)
```

Even granting the spelling, questions the record hasn't answered fall
out immediately: the op fires per firing of `~hits`, so the handle is
*inside* the iteration — what is `~io'` outside the loop (the handle
after all firings)? That is a collect of an effect flow, which nothing
defines. The lifecycle pattern's `(db', io', result)` tuples are drawn
for straight-line code, not for ops under a flow.

The honest finding: **the single most common thing sampled loops do —
cause an effect per element — is currently unwritable.** Roughly 42% of
sampled loops exist for their effects (`real-loop-survey.md`, combined
picture). Every translation below that touches IO (B4, B5, C-group) hits
this same wall and marks it `-- effect gap`. This is not primarily a
notation gap; the notation exposed that effect-under-a-flow has no worked
design (the Tier-1 IO/effects row), and it is the largest single obstacle
this exercise found to writing ordinary programs.

### B4. Read-until-sentinel pump (survey 1, python 4)

Source:

    while 1:
        line = self._getline(False)
        if line in terminators: break
        if line.startswith(b'..'): line = line[1:]
        file.write(line)

Two gaps before the loop even starts: the source is an effectful function
called repeatedly (no designed opener — the FFI stream node is named in
the async round but has no form), and the payload is a write (the effect
gap). With provisional spellings for both:

```
lines = source js "() => getline(false)"    -- (provisional FFI source)
lines -> open stream => line, ~P
line -> split isTerminator of End, Data => c
~P, ~c.End ~> end-when => ~W                -- exclusive: sentinel dropped
line -> split startsDotDot of Esc, Plain
  Esc:   -> dropFirst
  Plain:                                    -- (provisional identity lane)
-~> collect => outLine
~io ~> writeLine(outLine) in ~W => ~io'     -- effect gap
```

Notes:

- The sibling branch in the wild code (append to `lines` instead of
  writing) is the same drawing with the last statement replaced by
  `outLine -~> collect ~W` — the effect/collect swap is one statement,
  which is a genuinely good property.
- python 5's variant keeps the sentinel element (inclusive take-until).
  The design has the inclusive/exclusive bit; the text needs a word for
  it (`end-when ~c.End inclusive` is the strawman). The bit's final form
  is already open in the end-when round; the spelling should land with
  it.
- The identity lane (`Plain:` with no chain) had no blessed form. "Else
  leave it unchanged" appears in a large fraction of case splits in the
  samples; writing the payload explicitly was ambiguous enough that a
  bare label reading "the alt's payload passes through" seems worth
  blessing.

### B5. Compare-and-sync with an any-changed flag (survey 2, three 4)

Source:

    let morphChanged = false;
    for (let i = 0; i < influences.length; i++) {
      if (a[i] !== b[i]) { b[i] = a[i]; morphChanged = true }
    }

Lockstep iteration over two arrays. There is no zip; via an index range
the arrays are honest data:

```
range(len(a)) -> open list => i, ~L
a, i -> index => x
b, i -> index => y
x, y -> split equal of Same, Diff => c
~c.Diff ~> join into ~L => ~changes
~io ~> writeAt(b, i, x) in ~changes => ~io'   -- effect gap
x -~> collect ~changes => changedList
changedList -> nonEmpty => morphChanged
```

- Multi-close earns its keep exactly as the survey noted: the `~changes`
  flow has two consumers (the write-back effect and the flag), and the
  OR-fold *cannot* early-exit because the sync must visit every element
  — which the two-independent-collects reading gives by construction.
- The flag as `collect` + `nonEmpty` sidesteps `collect any` (reduce-
  close by operator) but materializes a list to test emptiness. Fine on
  paper; the reduce-close operator/identity question again.
- **Zip's absence** was felt but not fatal here (typed arrays are
  index-shaped anyway). For list-land lockstep iteration — iterating two
  same-length lists together — the record has nothing: Cross is
  all-pairs, join is nesting, the concurrent join is for concurrent
  flows. Filed as a small improvement item; possibly it is a
  flow-kind-pair operation like commute (zip(list, list) with a length
  side condition), possibly indices are simply the honest answer.

### B6. Window(2) with a ring closure (survey 2, sim 3)

Source:

    for v1, v2 in pairwise([*vertices, vertices[0]]):
        edge = tuple(sorted([round(v1), round(v2)]))
        edges.add(edge)

No window construct exists (it is a named candidate). The register
lowering, hand-rolled:

```
vertices -> append(first(vertices)) => ring   -- the ring closure, value land
ring -> open list => v, ~R
~R ~> delay init unit => prev
v -> step of prev
~R ~> delay init true => isFirst
false -> step of isFirst
isFirst -> split id of First, Rest => p
~p.Rest ~> join into ~R => ~pairs
prev, v -> normEdge => edge
edge -~> collect set ~pairs => edges          -- (provisional dedup collect)
```

Ten statements for three lines of Python, and the middle six are pure
bookkeeping: a delay whose first firing is garbage, plus a second delay
whose only job is to detect and drop that first firing. This is the
strongest textual pressure yet recorded for a **window(k)** block: the
lowering is exactly what the record says it is (delay + positional
filter), and writing it out shows why it must not be the surface. Two
associated notes:

- The design for window should anticipate the **ring/wraparound
  wrinkle** (the survey flagged it; here it cost one clean value-land
  statement, which is acceptable — wraparound-as-input-preprocessing may
  simply be the answer).
- `collect set` (dedup collect) joins `collect keyed` in the list of
  used-everywhere, spelled-nowhere collects. The keyed-collect family
  wants one round that fixes the spelling and the operator identity
  story together.

## Group C — the breadth set

### C1. The wrap loop (breadth item 1; survey 1, textwrap)

The sharpest standing challenge. The construct-level drawing exists
(`variable-rate-consumption-design.md`, worked programs); this is its
first transcription into the textual form. Core first (segmentation +
per-line length + indent), then truncation.

```
chunks -> open list => chunk, ~C
~C ~> split-when => ~line, ~w            -- (provisional two-phase mint)
     -- ~line: one firing per output line; ~w: this line's chunks

-- per-segment length register, on split-when's own inner flow:
~w ~> delay init 0 => lineLen
chunk -> len => cl
lineLen, cl -> add => tot
tot -> step of lineLen

-- the lines collect, minted early so its running view is readable:
~line ~> collect list => lines           -- (provisional two-phase mint)
lines!sofar -> isEmpty -> split id of First, Later
  First: initialIndent
  Later: subsequentIndent
-~> collect => indent
fullWidth, indent -> sub(len(indent)) => width

-- the boundary decision reads the register and the width:
tot -> gt(width) -> split id of Over, Fits => f
~f.Over ~> boundary of ~line start-next  -- (provisional late wire + bit)

-- build each line; late-wire it into the early-minted collect:
chunk -~> collect ~w => lineChunks
lineChunks -> joinWith(" ") -> prepend(indent) => lineText
lineText -> value of lines               -- (provisional late wire)
```

Truncation (`max_lines`), compactly: a count register on `~line`,
end-when on its overflow alt, the lines collect moved to the shortened
flow, and the last-line amendment downstream on the collected prefix —
per Part II's "the rewrite guise dissolves." Elided here:
`drop_whitespace`, `break_long_words` (the latter is out of split-when's
scope by that round's own analysis, correctly).

What the transcription taught, beyond what the construct-level drawing
already said:

- **It fits.** Eighteen-odd statements for a loop whose Python is about
  twenty lines, and — as the construct round claimed — each statement is
  a clause of the program's sentence, not bookkeeping. The pieces
  compose in text, not just in prose.
- **But it is held together by back-edges the notation doesn't own.**
  The wrap loop's interlock (boundary → width → indent → running view →
  lines → segments → boundary) is one big cycle threaded through
  registers, and transcribing it forced the two-phase mint-then-wire
  spelling **three times**: the register's `step of` (designed),
  split-when's `boundary of` (invented — the boundary operand reads
  per-segment state, i.e. state on the node's own output), and the
  collect's `value of` (invented — the running view is read four
  statements before the line value exists). "Token order is time"
  (textual P4) survives *only* because every cycle crosses a register
  and the write half is a later statement. The conclusion: **the
  write-half two-phase form is not a register quirk — it is the textual
  shape of every on-cycle operand**, and the notation should adopt
  `<port> of <name>` as the general late-wiring form. This is the single
  most useful thing the exercise found about the notation itself.
- A near-miss worth recording: the first attempt wired the boundary as
  an ordinary operand (`~C, ~f.Over ~> split-when => …`), which is
  unwritable — `~f.Over` doesn't exist until the register on `~w`
  exists, which doesn't exist until split-when does. The
  define-before-use discipline caught a genuine cycle, exactly as P4
  intends; the fix (late-wire the boundary) is the same fix the
  representation already chose for Delay's step. The notation and the
  representation agree about where the seam is, which is encouraging.

### C2. Retry with escalation / poll-until (survey 1 rb 9 + survey 3 websockets 1, jointly)

The poll loop:

    loop do
      response = poll(...)
      raise ... unless response.is_a?(HTTPSuccess)
      case parsed["status"]
      when "pending" then sleep 5
      when "success" then return parsed["code"]
      else raise ...
      end
    end

```
repeat -> open self => ~R                   -- (provisional self-driven flow)
~io ~> poll(url) in ~R => resp, ~io'        -- effect gap (an effectful read)
resp -> split httpOk of Ok, HttpErr => h
~h.HttpErr: h.HttpErr -> fail               -- (provisional)
h.Ok -> parse -> get("status")
     -> split statusTag of Pending, Success, Other => st
~st.Other: -> fail
~R, ~st.Success ~> end-when => ~W
~W ~> discharge => term
-- term: Stopped(code) is the return value; Fail(e) the raises
~io' ~> sleep(5) in ??? => ~io''            -- see below
```

Three findings, one of them new:

- **Repetition without a source has no opener.** Survey class 5 (three
  of thirty in survey 1) cannot be started on the page. `repeat -> open
  self` is the strawman; the real design question (what is the flow kind
  of bare repetition — a self-driven stream?) belongs to the
  async/stream rounds.
- **Pacing is a genuine semantic hole, not a spelling hole.** The `sleep
  5` must complete *between* firing n and firing n+1 of the self-driven
  flow. Nothing in the record says what gates the next firing of a
  self-driven flow — the sleep is just an effect op, and no wire
  connects it to the flow's advancement. The same hole reappears
  verbatim in the backoff reconnect loop (survey 3, websockets 1: sleep
  the current backoff before retrying, step the backoff register on the
  failure leg, reset it on success) and in undici 3. Three field
  sightings, one shape: **a self-driven flow whose next firing waits on
  a per-firing async value.** The retry composite the surveys flagged as
  an expansion test needs exactly this as its floor. Filed as an
  improvement item under the async/concurrency area.
- The failure legs (`raise unless…`, `else raise`) hit the same
  bodies-raise gap as B2, and the provisional `fail` carried them at the
  right size — more weight behind resolving that residue.

For the backoff half (websockets 1), the register ladder itself
translates cleanly — `~R ~> delay init BACKOFF_MIN/F => bd` with a step
chosen by a case split on the attempt's outcome (escalate on failure,
reset on success) is A4's conditional-carry shape — and the survey's
+1-ladder claim held on paper *except* for pacing and jitter (jitter
needs randomness, which is an effect, which is the effect gap again).

### C3. The DP table fill (breadth item 4; survey 2, mpmath 3)

Source:

    for n in range(5, N+1, 4):
        s = zeta_values[4*U+2]*(2*U+1)
        for k in range(1, 2*U+1):
            s += ...zeta_values[2*k]... * ...zeta_values[4*U+2-2*k]...
        zeta_values[n] += (s*rp) >> ...

The running view by index. With the two-phase collect from C1 this is
direct — mint the keyed collect early, read its running view in the
body, late-wire the contribution:

```
range5N4 -> open list => n, ~L
~L ~> collect keyed => zv                    -- (provisional mint)
n -> uOf => u
range(1, 2*u+1) -> open list in ~L => k, ~K
zv!sofar, k -> getAt2k... => zk              -- running view, by index
...term arithmetic... -~> collect ~K => s    -- the inner reduce
n, s -> ...final arithmetic... => entry
n, entry -> value of zv                      -- (provisional late wire)
```

(Arithmetic condensed; it is Apps.) The construct-level claim — read-by-
index is a value operation on the running view's port — transcribes
without new inventions beyond C1's pair. The wrinkle the transcription
surfaced: the wild code *seeds* the table (`zeta_values` is
pre-populated for small indices before the loop) and the loop *amends*
entries (`+=` onto an existing entry, not insert). A keyed collect with
an initial map and combine-on-collision is the general form — which is
the keyed collect meeting the reduce-close operator question (combine =
`+` needs its identity story). The keyed-collect round keeps
accumulating obligations: spelling, dedup variant, initial contents,
collision operator. It should happen as one round.

## Group D — concurrency sites

### D1. Race of two drains, cancel the loser, close in finally (survey 3, websockets 5)

Source:

    incoming = create_task(print_incoming(ws))
    outgoing = create_task(send_outgoing(ws, msgs))
    try:
        await asyncio.wait([incoming, outgoing], FIRST_COMPLETED)
    finally:
        incoming.cancel(); outgoing.cancel(); transport.close()

```
incoming: ws -> drainIncoming
outgoing: ws, msgs -> drainOutgoing
-> race => r
~r.incoming: unit
~r.outgoing: unit
-~> collect => done
-- loser cancellation: the race round's lost-cell hook — no spelling
-- transport.close() in finally: bracket — undesigned (Tier 1)
```

The race lanes themselves (the designed part) translate exactly as
`textual-representation-design.md` drew them, and the discrimination the
wild code never gets structurally is right there in the lane labels —
finding 3.2's point, visible on the page. But the translation is
honestly **half a program**: the `finally` block is the entire safety
story of the source, and it lands in two undesigned areas (the lost-cell
cancellation hook, opt-in per the race round but shapeless; bracket/
cleanup, Tier 1). No new finding — a transcription confirms what
`open-problems.md` already ranks first.

### D2. Not attempted, deliberately

The graceful-shutdown ladder (aiohttp 2), the timeout context manager's
uncancel dance (websockets 4), and the deferred-cell lifecycle sites (C1
class) were read and set aside: each sits mostly inside the undesigned
cancellation/effects area, and a transcription would be an inventory of
`-- effect gap` and `-- bracket gap` comments. The marginal information
from them is zero beyond D1's. Recorded so the selection is honest about
where translation is not yet possible at all.

---

# Findings

## What worked — worth trusting more

1. **The core is real.** Chains, taps, opens, splits, joins, collects,
   and the register two-phase form carried every stateless and every
   scan-shaped sample at or below the source's size, with no inventions
   (A1–A4). The mpmath scan (A3) — the iteration-state design's home
   case — was the smoothest translation, including the within-iteration
   chaining subtlety.
2. **Multi-close is a genuine improvement over the sources.** Ruby
   walked three times where one open + three taps says it once (A2); the
   sync-plus-flag loop (B5) got its cannot-early-exit property by
   construction.
3. **End-when's composition reads well** (B1): stop, discharge,
   split-on-tag is legible and mechanical, and the readout split puts
   the three exit paths of the wild code side by side on the page. The
   construct earns its Tier-3 "close soon" position.
4. **The define-before-use discipline caught a real cycle** (C1's
   near-miss): an operand that would have to be written before it could
   exist. The notation's P4 and the representation's two-phase register
   construction located the same seam independently. Good sign for the
   whole no-scope bet.
5. **Lane labels carry the race discrimination** (D1) exactly as finding
   3.2 wanted.

## Where it strained — the improvement list

Ranked by how hard the exercise hit each, with owners. Items 1–3 are
design gaps the notation exposed; 4–8 are notation/spelling debts; 9–10
are small construct candidates with new pressure.

1. **Per-firing effects are unwritable** (B3, and every IO-touching
   sample). The most common payload of real loops has no construct and
   no spelling; effect-handle threading under a flow (what is the handle
   after the iteration?) is undesigned. This is the Tier-1 IO/effects
   row, now with the concrete everyday failure mode: *you cannot
   transcribe `task.cancel()` in a loop.* The design needs both the real
   model (handle threading + effect collect) and a lightweight surface,
   because the shape occurs in nearly half of everything.
2. **Bodies-raise / lightweight failure** (B2, C2). The validate-or-
   abort walk costs seven statements via pure end-when; failability's
   propagate-by-default plus a one-word `fail` stage brings it to par
   with the source. Concrete demand for the failability-residue row's
   open question. *That row's round now exists*
   (`failure-payloads-design.md`, exploration): `fail` is worked as
   end-when's failure-tagged sibling, and B2/C2 are its opening
   evidence.
3. **Sources: external pulls and bare repetition have no opener** (B4,
   C2). Survey classes 4 and 5 — six of sixty loops — cannot start on
   the page. The FFI stream source and the self-driven flow need at
   least placeholder forms; and **pacing** (the next firing of a
   self-driven flow gated on a per-firing async value — sleep-between-
   retries) is a semantic hole with three field sightings, which the
   retry composite cannot be assembled without. Owner: async/concurrency
   area.
4. **Generalize the write-half: late-wired operands** (C1, C3). `step
   of` is designed; the exercise needed the same two-phase form for
   split-when's boundary (`boundary of`) and a collect's value input
   (`value of`) — every on-cycle operand wants it. One rule ("a node may
   be minted with an on-cycle operand unwired; a later statement wires
   it as `<port> of <name>`") covers all three and keeps P4 intact.
   Owner: the textual round, jointly with `first-class-ports-design.md`
   (which already owns the write-half-is-a-node idea).
5. **The discharge readout spelling** (B1, B2, C2). The (prefix,
   terminator) collect's binder convention, a terminator-only form (or a
   discard binder), the inclusive/exclusive bit's word, and possibly
   lanes-on-discharge sugar. Owner: textual round, blocked jointly on
   end-when adoption (which `open-problems.md` already lists as owing
   "the textual spelling").
6. **The collect family needs one spelling-and-identity round** (A4, B5,
   B6, C3): keyed, dedup-set, last, any/or — all used throughout the
   record and the samples, none spelled; the operator-identity question
   underneath them; plus C3's additions (initial contents, collision
   combine). Owner: iteration-with-state (reduce-close) + textual.
7. **Pair-shaped elements / entry opens** (A4 and five other samples):
   opening a map should yield two value ports, or `fst`/`snd` noise
   taxes every dict walk. Small representation question, textual binder
   already ready.
8. **Identity lanes** (B4): bless a spelling for "this alt passes
   through unchanged."
9. **window(k) gains its strongest evidence yet** (B6): the hand-rolled
   lowering is ten statements of which six are bookkeeping — exactly the
   "lowering must not be the surface" situation. Ring-closure input
   preprocessing looked acceptable.
10. **Zip / lockstep pairs of lists** (B5): absent; indices were honest
    for arrays; whether list-land needs a real zip is an open note, not
    a demand.

## What this changes

- `open-problems.md`: item 1 adds everyday-writability pressure to the
  Tier-1 IO/effects row (no score change — the row is already maximal);
  items 4–8 sharpen the Tier-4 textual-catch-up row's contents from
  "spellings owed" to this concrete list; item 3 adds the pacing hole to
  the concurrency row's remaining list.
- The end-when and variable-rate rounds get their first transcription
  evidence: both compositions survive contact with text (B1, C1, C3),
  which the adoption conversations can cite.
- The provisional spellings table above is raw material for the textual
  round's next revision — strawmen, not commitments.

## Next round

- Re-run the exercise after the effect story and the failability residue
  get designs — B3 and B2 are the acceptance tests, and they should
  shrink to source size.
- Transcribe the remaining breadth-set members that were skipped (the
  tokenizer-substituter end-to-end; the theta kernel — A3 suggests it
  will go well and its real test is legibility at eight registers).
- When the textual form's parser exists, these translations are the
  first golden files: they were written by hand against the spec, so
  `parse(print(parse(t)))` disagreements will locate spec ambiguities
  (the gather rule and lane forms especially — this exercise leaned on
  fused lanes eleven times).
