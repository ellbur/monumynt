# Real-Loop Survey: Thirty Random Loops Against the Block Inventory

> **Status (2026-07-09).** First execution of the sampling plan that
> `iteration-rails-design-notes.md` set out ("sample real loops
> randomly from real code... don't filter for interesting cases") and
> that `iteration-with-state-design.md` names as the test for the
> state thread's one-writeback rule. This is an evidence document,
> not a design round: it classifies a seeded random sample of thirty
> loops from three real codebases against the language's designed and
> candidate constructs, and reports what the frequencies say. It
> decides nothing. Its known biases are stated in "Protocol" and its
> corpus gap (no numerics, simulation, or UI code) is the stated next
> round. Findings feed three places: the iteration-state decision bar
> (`iteration-with-state-design.md`), the thread's one-writeback
> question (same doc, "Open questions for the thread"), and the
> ranked candidate-block inventory (`tough-use-cases-design.md`).

## Why this document exists

The rail notes ended with a warning and a plan. The warning: designing
iteration-state constructs from first principles "risks designing to
the theory's existing categories rather than to what real iterative
code actually looks like." The plan: sample whole loops randomly from
real code across domains, don't filter for interesting cases, and
study the shape — what state is carried, how it updates, what's read
after, what's set up before. The iteration-state document then made
the plan load-bearing twice over: the fourth option's one-writeback
rule ("conditional carry expressed as a conditional value wired into
the single writeback") is explicitly to be tested against that sample,
and the rail-notes question — what proportion of real loops the simple
rail pattern actually fits — bears directly on whether a loop-carried
register deserves to be the *central* construct or a tail construct.

Nobody had run the sample. This document runs it.

## Protocol

Reproducibility first: every selection below is deterministic given
the corpora and the seed. No loop was hand-picked, added, or dropped.

- **Corpora** (real code installed on the machine the survey ran on):
  - Python 3.10 standard library (`/usr/lib/python3.10`), excluding
    `test`, `idlelib`, `lib2to3`, and `__pycache__` paths — 621 files.
  - Ruby 3.3 standard library incl. bundled/vendored gems
    (`/opt/ruby-3.3.6/lib/ruby/3.3.0`) — 476+ files.
  - npm's own JS plus its vendored dependencies
    (`/opt/node22/lib/node_modules/npm`), excluding `*.min.js` — 1049
    files.
- **What counts as a loop**: explicit iteration constructs (`for`,
  `while`, `until`, `do`, `loop`) plus each-style effectful block
  iterators (Ruby `.each*`/`.times`, JS `.forEach`). Pure
  expression-level combinators — comprehensions, `map`, `filter`,
  `reduce` — are excluded: they correspond to the language's
  already-designed collect forms, so counting them would only inflate
  the "already served" bucket. Note the direction of this bias: it
  removes code that is trivially collect-shaped, so the "no carried
  state" proportion reported below is an **undercount**.
- **Selection**: seed `20260709`, RNG `random.Random(f"20260709:{lang}")`
  per corpus. Shuffle the corpus's sorted file list; walk it in
  shuffled order; in each file containing at least one loop header,
  pick **one** loop uniformly at random; stop at ten loops per corpus.
  Thirty loops total.
- **Classification**: each loop was read with its surrounding function
  (and callees where the loop's meaning depended on them, e.g. a
  helper that clears a buffer), then classified by what state it
  carries and how it terminates.

Stated biases, beyond the combinator exclusion:

- **Domain skew.** All three corpora are language/tooling
  infrastructure: parsing, IO, package management, build tools. The
  rail plan's list included simulation, UI handling, and numerical
  routines; none of those are represented. Numerics in particular is
  where classic scans (running sums, maxima) should be commonest, so
  the scan-frequency finding below must not be read past this corpus
  family until a second sample checks it.
- **Generated code included.** One sampled loop (ruby 7) is
  machine-generated parser code. Don't-filter means it stays; it is
  flagged in place.
- **n = 30.** Proportions are coarse — at this size a reported 50% has
  a 95% interval of roughly ±18 points. The value of the sample is in
  which patterns *occur at all* and which dominate, not in
  second-digit precision.

## The sample

Each entry: source, the loop (condensed), the shape reading, and the
classification. Groups are by classification; within groups, corpus
order. The class names are defined by the entries themselves; the
tally and findings follow.

### Class 1 — stateless per-element work (15 of 30)

Map, filter, flatten, keyed collect, or per-element effect. No value
carried between iterations beyond an output builder that is only ever
appended to (which is a collect, not loop state).

**python 2** — `unittest/async_case.py:133`

    for task in to_cancel:
        task.cancel()

Per-element effect. Plain uncollect + effect per firing.

**python 6** — `filecmp.py:233`

    for sd in self.subdirs.values():
        print()
        sd.report()

Per-element effect (two ordered effects per firing).

**python 7** — `multiprocessing/managers.py:960`

    for meth in exposed:
        exec('''def %s(self, ...): ...''' % (meth, meth), dic)

Builds one dict entry per element; each iteration writes a distinct
key, nothing reads previous state. A keyed collect.

**python 8** — `distutils/command/install_lib.py:157`

    for file in build_files:
        outputs.append(os.path.join(output_dir, file[prefix_len:]))

Map + list collect, exactly.

**python 10** — `distutils/command/build_clib.py:169`

    for (lib_name, build_info) in self.libraries:
        sources = build_info.get('sources')
        if sources is None or not isinstance(sources, (list, tuple)):
            raise DistutilsSetupError(...)
        filenames.extend(sources)

Flatten (join list-of-lists) + collect, with a failure terminator
(raise aborts the whole walk). Maps to join(list, list) + collect +
fail.

**ruby 1** — `bundler/cli/binstubs.rb:34`

    gems.each do |gem_name|
      spec = ...find...
      raise GemNotFound, ... unless spec
      if options[:standalone]
        next if gem_name == "bundler"   # (condensed)
        ...effect...
      else
        ...effect...
      end
    end

Per-element case split + effect, with `next` (a filter) and a failure
terminator. No carried state.

**ruby 3** — `rdoc/markup/list_item.rb:52`

    @parts.each do |part|
      part.accept visitor
    end

Per-element effect.

**ruby 4** — `rubygems/resolver/git_set.rb:94`

    @repositories.each do |name, (repository, reference)|
      source = ...build...
      source.specs.each do |spec|
        @specs[spec.name] = ...
      end
    end

Nested iteration (join) with a keyed collect into a map at the inner
level. No carried state.

**ruby 5** — `csv/table.rb:671`

    @table.each do |row|
      if row.header_row?
        row[index_or_header] = index_or_header
      else
        row[index_or_header] = value
      end
    end

Per-element case split + effect (mutating each row).

**ruby 6** — `rdoc/stats.rb:121`

    ucm.each { |cm| methods.concat cm.method_list }

Flatten + collect (and the surrounding function repeats the same
shape three times for three outputs — a multi-close on one logical
iteration, done as three separate walks in Ruby).

**ruby 10** — `irb/inspector.rb:67`

    for k in key
      def_inspector(k, inspector)
    end

Per-element effect.

**js 6** — `promise-all-reject-late/index.js:5`

    for (let i = 0; i < promises.length; i++) {
      reflections[i] = Promise.resolve(promises[i]).then(...)
    }

Indexed map into a fresh array. A map + collect; the index is
iteration bookkeeping, not carried state.

**js 8** — `@npmcli/arborist/lib/tracker.js:63`

    for (const key of keys) {
      if (key.match(new RegExp(section + ':'))) {
        this.finishTracker(section, key)
      }
    }

Filter + per-element effect.

**js 9** — `tuf-js/dist/fetcher.js:48`

    for await (const chunk of stream) {
      chunks.push(chunk)
    }

Collect over an async stream — notable only in that it is precisely
the async flow kind's collect, occurring in the wild in exactly the
designed shape.

**js 10** — `@npmcli/arborist/lib/case-insensitive-map.js:10`

    for (const [key, val] of items) {
      this.set(key, val)
    }

Keyed collect (last-wins via the map's set semantics).

### Class 2 — search: first-match / any, with early exit (4 of 30)

A terminating walk whose entire point is to stop early. No mutable
carried state; the "result" is where (or whether) the walk stopped.

**python 9** — `pkgutil.py:256`

    for fn in dircontents:
        subname = inspect.getmodulename(fn)
        if subname == '__init__':
            ispkg = True
            break
    else:
        continue    # (of the enclosing loop) — not a package

Any/exists with early exit, using Python's for-else to route the
not-found case. The found/not-found outcome is a case split *produced
by the loop's termination*.

**js 2** — `isexe/windows.js:18`

    for (var i = 0; i < pathext.length; i++) {
      var p = pathext[i].toLowerCase()
      if (p && path.substr(-p.length).toLowerCase() === p) {
        return true
      }
    }
    return false

Any/exists; early exit via return of the enclosing function.

**js 3** — `@npmcli/arborist/lib/add-rm-pkg-deps.js:86`

    for (const saveType of saveTypeMap.keys()) {
      if (hasSubKey(pkg, saveTypeMap.get(saveType), name)) {
        if (saveType === 'peerOptional' && ...) { return 'peer' }
        return saveType
      }
    }
    return 'prod'

First-match with a computed result per match and a default after the
walk. The three exits (two returns, one fallthrough) are a case
split.

**js 5** — `pacote/lib/util/is-package-bin.js:16`

    for (const kv of Object.entries(bin)) {
      if (kv[1] === p) { return true }
    }
    return false

Any/exists, early return.

### Class 3 — conditional carry (1 of 30)

**js 1** — `init-package-json/lib/default-input.js:183`

    let command
    for (const [k, v] of Object.entries(commands)) {
      if (d.includes(k)) {
        command = v
      }
    }
    // command read afterwards

One carried variable, written only on matching iterations, passed
through unchanged otherwise, read after the loop. Last-match-wins.
This is the conditional-carry pattern named in the rail notes'
uncovered list, occurring in the wild.

Tested against the thread's one-writeback rule: the epoch's value is
`command' = d.includes(k) ? v : command` — a conditional *value* into
the single writeback, exactly as the rule prescribes. No strain.
Worth noting it also reads naturally without any register at all:
filter (`d.includes(k)`) then last-of, which is collect vocabulary.
Even the one sampled conditional carry is not *forced* onto the rail.

### Class 4 — read-until-sentinel pump over an external source (3 of 30)

An unbounded external source (socket, SSL object, file descriptor)
read repeatedly until the data itself says stop; each element is
transformed and appended or written out. No carried state; the loop
is source + data-driven termination + per-element work.

**python 4** — `nntplib.py:513`

    while 1:
        line = self._getline(False)
        if line in terminators: break
        if line.startswith(b'..'): line = line[1:]
        file.write(line)

(The sibling branch appends to `lines` instead of writing to a file —
same walk, collect instead of effect.) Unescape is a per-element map;
the terminator test is data-driven termination — `end-when` in the
tough-use-cases inventory's vocabulary.

**python 5** — `asyncio/sslproto.py:198`

    while True:
        chunk = self._sslobj.read(self.max_size)
        appdata.append(chunk)
        if not chunk: break   # close_notify

Same shape; one wrinkle: the sentinel chunk is appended *before* the
test, so the collect includes the terminator element (inclusive
take-until).

**js 4** — `fs-minipass/lib/index.js:196`

    do {
      const buf = this[_makeBuf]()
      const br = fs.readSync(this[_fd], buf, 0, buf.length, null)
      if (!this[_handleChunk](br, buf)) { break }
    } while (true)

Same shape again; the stop decision is delegated to a handler (data-
driven, from the loop's point of view).

### Class 5 — condition-driven repetition: poll / retry / produce (3 of 30)

No data source at all in the list sense. The loop *is* the source: it
repeats an exchange with the outside world until a condition holds
(or forever).

**python 1** — `subprocess.py:1955`

    while self.returncode is None:
        with self._waitpid_lock:
            if self.returncode is not None: break  # another thread waited
            (pid, sts) = self._try_wait(0)
            if pid == self.pid: self._handle_exitstatus(sts)

Poll an external process until an externally-visible condition is
set (by this loop's own effect, or by another thread — note the
recheck-under-lock). Repetition driven by a condition over effectful
state; concurrency in the room.

**ruby 2** — `irb/ws-for-case-2.rb:7`

    while true
      IRB::BINDING_QUEUE.push _ = binding
    end

An infinite producer feeding a queue. A self-driven flow with a
per-firing effect and no termination at all.

**ruby 9** — `rubygems/gemcutter_utilities/webauthn_poller.rb:47`

    loop do
      response = poll(...)
      raise ... unless response.is_a?(HTTPSuccess)
      case parsed_response["status"]
      when "pending" then sleep 5
      when "success" then return parsed_response["code"]
      else raise ...
      end
    end

Poll a server until success: each firing is an exchange whose parsed
result is a three-way case split — continue (with a delay), exit with
a value, or fail. The loop's value *is* the early exit's payload.
(An enclosing timeout — `Gem::Timeout.timeout(...)` — bounds the
whole thing: an interrupt in the async doc's vocabulary.)

### Class 6 — cursor: a position advanced through data (2 of 30)

**js 7** — `normalize-package-data/lib/extract_description.js:15`

    let s = 0
    while (d[s] && d[s].trim().match(/^(#|$)/)) { s++ }
    const l = d.length
    let e = s + 1
    while (e < l && d[e].trim()) { e++ }
    return d.slice(s, e).join(' ').trim()

Two cursor advances: skip-while (find the first non-heading,
non-blank line), then extend-while (find the end of that block), then
a slice between the cursors. Each while is a single carried variable
updated unconditionally each firing — register-shaped — but the
natural *reading* is positional: find-first-index and take-while,
i.e. searches over positions, not accumulation. The termination
condition is the loop condition itself (data-driven).

**ruby 7** — `rdoc/markdown.rb:5971` *(machine-generated PEG parser)*

    while true # choice
      _tmp = apply(:_HtmlBlockOl)
      break if _tmp
      self.pos = _save2
      ...try next alternative...
      break
    end # end choice

Two things at once, both instructive. First: `self.pos` is a cursor
into the input that is *saved and conditionally restored* —
backtracking; state with multi-site update where one of the writes is
a reset to an earlier snapshot. Second: this `while true` never
iterates — it is a one-pass block used for structured goto (`break`
out of the middle of a "choice"), a loop as control-flow scaffolding
rather than iteration. Generated code, flagged as such; but the
save/restore cursor is what any hand-written backtracking parser does
too.

### Class 7 — worklist: variable-rate consumption (1 of 30)

**python 3** — `textwrap.py:269`

    chunks.reverse()
    while chunks:                      # outer: one line per firing
        cur_line = []; cur_len = 0
        indent = self.subsequent_indent if lines else self.initial_indent
        width = self.width - len(indent)
        if drop_whitespace and chunks[-1].strip() == '' and lines:
            del chunks[-1]
        while chunks:                  # inner: fill the line
            l = len(chunks[-1])
            if cur_len + l <= width:
                cur_line.append(chunks.pop()); cur_len += l
            else:
                break
        ...long-word handling, whitespace drop...
        if cur_line:
            lines.append(indent + ''.join(cur_line))
        # (max_lines truncation path may edit lines[-1] and break)

The richest loop in the sample. The iteration source (`chunks`, a
stack) is consumed at a *variable rate* — each outer firing pops as
many elements as fit a line ("consume while it fits": a data-
dependent take). The output-so-far is *read back mid-loop* twice:
`if lines:` selects the indent (a first/subsequent-output split —
the first-iteration distinction from the iteration-state doc,
appearing in the wild as a read of the accumulated output rather
than an iteration counter), and the truncation path *rewrites*
`lines[-1]` and breaks out of the whole walk. Nothing in the current
or candidate inventory covers this loop as one reading; its pieces
are the decision-driven family's "advance how far" plus end-when plus
a running view of the collect.

### Class 8 — accumulator with multi-site append and conditional reset (1 of 30)

**ruby 8** — `net/http/generic_request.rb:320`

    buf = +''
    params.each do |key, value, h={}|
      buf << "--#{boundary}\r\n"
      if filename
        buf << "Content-Disposition: ..."
        if ...direct write case...
          flush_buffer(out, buf, chunked_p)   # writes buf to out, buf.clear
          IO.copy_stream(value, out)
        ...
      else
        buf << ...
      end
    end

A string builder appended at several sites per firing and
*conditionally flushed* — written to the output channel and cleared —
partway through some firings, so that a raw file copy can be
interleaved at the right position in the output. State with reset,
where the reset is entangled with effect ordering (the flush must
happen before the copy). Against the one-writeback rule: each
firing's final `buf` value *is* expressible as one value (the
branches each determine it — cleared-then-appended or appended), so
the rule survives structurally; what the single-writeback reading
does not capture is the mid-firing effect ordering, which lands on
the effect story (`custom-flows.md`), not on the state construct.

## Tally

| Class | n | Served today by | Gap it points at |
|---|---|---|---|
| 1. Stateless per-element work | 15 | uncollect/collect, join, keyed collect, filters, effects | — |
| 2. Search / first-match (early exit) | 4 | nothing at the everyday level | end-when + final readout |
| 3. Conditional carry | 1 | register candidates (or filter+last) | one-writeback rule: confirmed |
| 4. Read-until-sentinel pump | 3 | external stream sources (FFI nodes) | end-when |
| 5. Condition-driven repetition | 3 | self-driven stream + async | end-when, interrupt, retry-with-delay |
| 6. Cursor | 2 | registers (as lowering) | data-driven termination; decision-driven family |
| 7. Worklist / variable-rate consumption | 1 | nothing as one reading | data-dependent take + running view of collect |
| 8. Accumulator with reset | 1 | registers, strained | effect ordering within a firing |

Cross-cutting counts:

- **Early termination** (break / early return / sentinel): 11 of 30 —
  12 counting js 7, whose "loop condition" is a data predicate.
- **Loops whose primary output is a side effect** on something outside
  the loop (writes, IO, registrations), rather than a built value:
  roughly 13 of 30.
- **Loop-carried state beyond an append-only builder**: 5 of 30
  (classes 3 and 6–8). Of these, **zero** are the simple scan — an
  arithmetic accumulator updated unconditionally each firing and read
  once after the loop.

## Findings

### 1. Half of real loops need no iteration state at all — and that's an undercount

Fifteen of thirty are per-element work the existing vocabulary already
covers: collects (list, keyed, flattened), filters, per-element
effects, one async collect in exactly the designed shape (js 9). The
protocol *excluded* comprehensions and map/filter/reduce combinators,
which are this class by construction — so in the corpora's code as a
whole, the fraction needing no state machinery is well above half. The
foundation bet (uncollect/collect as the center) is confirmed against
random real code, for whatever this corpus family is worth.

### 2. The running-sum scan did not occur

The case that anchors the entire iteration-state design conversation —
`sum = sum + element`, the concrete example behind the link, Delay,
the augmented uncollect, and the thread — appeared **zero times in
thirty draws**. The accumulators that did occur are collection
builders (append-only: collect, not state), cursors (positions, not
sums), a last-match-wins variable, and a resettable buffer.

This must be read carefully, in both directions. It does *not* say
the register construct is unnecessary: the corpus has no numerics,
simulation, or signal-processing code, which is where scans live; and
the record's own analysis already routes *other* things through
registers as lowerings (the ordered merge's cursor pair, protocol
state). It *does* say that in infrastructure code — parsing, IO,
tooling, the code these corpora are made of — the scan is rare enough
that a design whose primary worked example is the running sum is
optimising its surface for a case programmers in these domains hit
occasionally, while the cases they hit constantly (searches, pumps,
worklists) go through other doors. The rail-notes question "if most
short loops are one-rail patterns, the rail is the right central
construct; if even most short loops break the pattern, the rail is in
trouble" gets neither answer: most loops are *zero*-rail patterns, and
the loops that do carry state are mostly not one-rail-shaped. The rail
is tail vocabulary, and the tail's actual shapes are listed below.

### 3. The one-writeback rule survived everything sampled

The state thread's open question — does one-writeback-per-crossing
survive real loops? — gets a yes on this sample:

- **Conditional carry** (js 1, the pattern the rule was stated for):
  expresses exactly as prescribed, a conditional value into the single
  writeback. First real-code confirmation.
- **Multi-site update with reset** (rb 8): each firing's final value is
  still one expression (the sites are sequenced within one firing, so
  they compose into a single per-firing value); the rule survives
  structurally. The honest caveat: what strains is not the writeback
  count but the *effects interleaved between the appends* — the flush
  must be ordered against the raw copy. That pressure lands on effect
  ordering within a firing (the custom-flows effect story), and no
  count of writebacks fixes or worsens it.
- **Backtracking save/restore** (rb 7): the cursor's two writes (advance
  and restore-to-snapshot) are again one conditional value per firing
  (`pos' = matched ? new_pos : saved`). Survives — though a parser
  would want the save/restore *pairing* visible, which is a reading
  concern the rule doesn't speak to either way.

No sampled loop required two independent writebacks to the same
carried variable within one firing. The rule stands, now with contact
evidence rather than only cleanliness arguments.

### 4. Early exit is the dominant non-trivial pattern, and it is the inventory's item, not a new one

Eleven or twelve of thirty loops terminate early — search hits,
sentinel lines, close_notify, success responses, full lines. That is
more than every stateful class combined. The construct this demands
already exists in the record as **end-when** (data-driven terminator
writing, `tough-use-cases-design.md`), ranked 4th in the inventory
with demand cited from mergesort's walk, until-loops, and protocol
framing. The survey's contribution is frequency: end-when is not a
corner of recursive algorithms — it is *the* most common thing
everyday loops do beyond plain iteration, appearing in four distinct
guises in one random sample:

- **first-match / any** (class 2) — end-when plus a final readout,
  a composition the tough-use-cases doc already sketched ("expressible
  the day end-when exists"). The found/not-found outcome is a case
  split produced by termination (py 9's for-else routes it; js 3
  returns per-branch), which suggests the readout is naturally
  option-shaped or alt-shaped, not just a value.
- **take-until a sentinel** (class 4) — with an inclusive/exclusive
  wrinkle (py 5 keeps the terminator element, py 4 drops it) that any
  end-when surface will need to speak to.
- **poll-until with result payload** (rb 9) — the exit carries the
  loop's value.
- **predicate cursors** (js 7) — where termination *is* the loop.

If the inventory's ranking is revisited, this sample argues end-when
outranks its current position: items 1–3 were each demanded by the
tough use cases' concurrent systems, but end-when is demanded by
ordinary sequential code at a rate no other candidate approaches.

### 5. The stateful tail is cursors, worklists, and resets — the decision-driven family's territory

The five stateful loops (classes 3, 6, 7, 8) contain: two cursors,
one worklist with data-dependent consumption rate, one resettable
buffer, one conditional carry. Set beside the record's existing
analysis, this is striking: the tough-use-cases round *derived* the
cursor-register from the ordered merge's lowering, and named the
decision-driven family ("per-heads chooser: which side advances /
*advance how far*") plus data-dependent take as candidates. The
survey finds exactly those shapes occurring naturally — textwrap's
line-filling is literally "advance how far" (consume chunks while
they fit), and js 7's skip-while is a degenerate one-flow instance of
the same decision. The theory's categories and the field's shapes
agree here, which is the agreement the sampling plan was designed to
check.

One shape in the tail is not yet anywhere in the record: **reading
the output-so-far from inside the walk** (py 3 reads `lines` twice —
once to pick the indent by first/subsequent output, once to rewrite
the last emitted line under truncation). The augmented-uncollect
candidate exposes a *running value of a register* in-loop; what py 3
reads is the running value of a *collect*. Whether that is a register
whose value happens to be the built list (making the collect a
reduce-close over append — but then the mid-walk *rewrite* of
`lines[-1]` is out of reach), or a genuine "running view" port on a
collect, is a question this survey can only raise. It files under
the same heading as multi-close: what may be observed of an
iteration while it runs.

### 6. Repetition without a source is ordinary, not exotic

Three loops (class 5) iterate nothing: they poll, retry, or produce.
The record reaches self-driven flows through Fibonacci — a recurrence
with no inlet — which makes them feel like a theoretical edge case.
In the sample they are how code talks to the world: wait for a
process, poll a server (with delay, timeout, and failure legs — rb 9
uses all three), feed a queue forever. These are the async doc's and
FFI direction's territory (external sources, interrupt, retry), and
the survey confirms that door gets everyday traffic. A design
conversation about "loops" that only pictures list iteration would
miss a tenth of this sample outright.

### 7. Effects are the payload, not the exception

Roughly thirteen of thirty loops exist to cause effects — write
lines, cancel tasks, mutate rows, register inspectors — not to build
a value. The language's effect story (effect-handle flows,
`custom-flows.md`; effect ordering within a firing, per rb 8) carries
more of the everyday load than the value-building examples in the
design record suggest. No new gap, but weight: the effect docs are
load-bearing for ordinary code, not just for the IO round.

## What this changes, and what it doesn't

For the **iteration-state decision** (`iteration-with-state-design.md`,
"The bar: easy for beginners *and* flexible enough for complex
code"): the sample reweights what "complex code" mostly is. The
candidates are evaluated throughout that document against scans and
recurrences; real loops' complexity sits mostly in *termination*
(end-when), *consumption rate* (decision-driven), and *interleaved
effects* — with the register itself usually either absent or the easy
part. Concretely: whichever candidate is chosen should be evaluated
with early exit in the room — e.g. what a Delay/thread's final-value
readout means when end-when terminates the flow mid-walk (the write
half's final-value output and a search's readout look like the same
port, which is either a pleasing unification or a coincidence to
check). The choice among the candidates is not made or moved by this
survey; the environment they'll live in is clarified.

For the **thread's one-writeback rule**: survived its stated test on
this sample (finding 3). The rule's record can cite contact evidence
now; the conditional-carry case behaves exactly as prescribed.

For the **candidate-block inventory** (`tough-use-cases-design.md`):
end-when gains everyday demand far beyond its cited use cases
(finding 4) and arguably outranks its position 4; the decision-driven
family and data-dependent take gain a field sighting each (finding
5); one new question is filed (running view of a collect, finding 5).

For the **foundations**: uncollect/collect as the center is
confirmed against random real code (finding 1) — the single clearest
result in the sample.

## Next round

- **A second sample from the missing domains** — numerics, simulation,
  UI/event handling (e.g. a scientific-computing library, a game or
  physics engine, a GUI toolkit) — to test whether the scan's absence
  is real or corpus skew. This is the one finding above that could
  flip.
- **Larger n** if any proportion needs to be load-bearing rather than
  indicative.
- **A combinator census** (comprehensions, map/filter/reduce counts per
  file) if the "well above half needs no state" claim in finding 1 is
  ever worth firming up; the current statement rests on the exclusion
  bias's direction alone, which is sound but unquantified.
