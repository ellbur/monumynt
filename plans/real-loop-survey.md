# Real-Loop Survey: Random Loops Against the Block Inventory

This is an evidence document, not a design proposal. It classifies
seeded random samples of real code against the language's designed and
candidate constructs, and reports what the frequencies say. It decides
nothing.

The doc holds three surveys:

- **Survey 1** — thirty loops from infrastructure corpora (Python and
  Ruby standard libraries, npm's JavaScript).
- **Survey 2: the missing domains** — thirty loops from six domain
  corpora chosen to fill Survey 1's stated gap: numerics, graph
  algorithms, simulation, terminal UI, game logic, 3D graphics. Its
  headline correction: the running-sum scan, which never appeared in
  Survey 1, *does* occur — concentrated exactly where Survey 1
  predicted (numerics). So Survey 1's "scan absent" result is corpus
  skew, not a fact about real code.
- **Survey 3: concurrency orchestration** — thirty concurrency *sites*
  (a different unit than a loop) from six server/async-heavy corpora,
  giving the candidate-block inventory's items 1–3 the frequency
  treatment the loop surveys gave items 4–5. Its headline: sum-shaped
  barriers (race / timeout / interrupt / cancellation) dominate
  nine-to-one over the all-of join, and every hand-rolled race
  reconstructs "who won" from side flags rather than receiving it
  structurally.

**How to read the tallies.** Frequency is not importance. This is the
80/20 counterweight, stated in full under "Reading the frequencies"
near the end and now a standing rule of the method: high frequency
ranks what must be *effortless*; a shape drawn only once is a *breadth
obligation*, not a candidate for deprioritization. The singleton hard
draws are collected there as **the breadth set** — nine loops the
language must handle without too much pain.

## Why sample real loops

Designing iteration constructs from first principles "risks designing
to the theory's existing categories rather than to what real iterative
code actually looks like" (`iteration-rails-design-notes.md`). The
remedy is to sample whole loops at random from real code across
domains, without filtering for interesting cases, and study the shape:
what state is carried, how it updates, what is read afterward, what is
set up before.

Two questions make this load-bearing. First, the one-writeback rule of
`iteration-with-state-design.md` — "conditional carry expressed as a
conditional value wired into the single writeback" — is to be tested
against exactly this sample. Second, the rail-notes question of what
proportion of real loops the simple rail pattern actually fits bears
directly on whether a loop-carried register deserves to be the
*central* construct or a tail one.

Sampling reality this way is now a standing practice, to be used
frequently, not a one-off. Its statement and rules (seeded, unfiltered,
biases stated, evidence kept separate from decision) live in
`language-design-philosophy.md`, "A standing method: sample reality."
Findings feed three places: the iteration-state decision bar
(`iteration-with-state-design.md`), that doc's one-writeback question,
and the ranked candidate-block inventory (`tough-use-cases-design.md`).

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
whole, the fraction needing no state machinery is well above half.
*(Now quantified — see "Combinator census" below. It holds, as a clear
~60% majority in infrastructure code, but modestly: statement loops
outnumber combinators ~2:1 even in Ruby and JS, so the no-state
majority is carried mostly by stateless statement loops, not by the
excluded combinators, which add only ~7 points.)* The
foundation bet (uncollect/collect as the center) is confirmed against
random real code, for whatever this corpus family is worth.

### 2. The running-sum scan did not occur

*(Survey 2 sampled the missing domains and the scan occurred
immediately and repeatedly in the numerics corpus — see Survey 2,
finding 2.1. The caveat below was right: it was corpus skew. This
finding stands for infrastructure code specifically.)*

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
  flip. *(Done — "Survey 2" below. It flipped, exactly as anticipated:
  the scan lives in numerics.)*
- **Larger n** if any proportion needs to be load-bearing rather than
  indicative.
- **A combinator census** (comprehensions, map/filter/reduce counts per
  file) if the "well above half needs no state" claim in finding 1 is
  ever worth firming up; the current statement rests on the exclusion
  bias's direction alone, which is sound but unquantified.

---

# Survey 2: the missing domains

Thirty more loops from six domain corpora chosen to fill Survey 1's
stated gap. Same method; protocol amendments below.

## Protocol (survey 2)

Corpora were fetched from the public package registries (pip / npm)
onto the survey machine, one project per domain — plus one small
second project pooled into the simulation corpus:

| Corpus | Project(s) | Domain |
|---|---|---|
| mpmath | mpmath 1.4.1 | arbitrary-precision numerics |
| networkx | networkx 3.6.1 | graph algorithms |
| sim | mesa 3.3.1 + simpy 4.1.2 | agent-based / discrete-event simulation |
| textual | textual 8.2.8 | terminal UI, event-driven |
| chess | python-chess 1.11.2 (sdist) | game logic, engines, formats |
| three | three.js (npm, r182 era) | 3D graphics (JS) |

Selection as in survey 1: seed `20260709` retagged per corpus
(`random.Random(f"20260709:{name}")`), shuffled file list, one loop
per drawn file, five per corpus, thirty total. Excluded paths:
`*test*`, `__pycache__`, `/docs/`, `/examples/` (and for three.js,
`/build/` — the bundles duplicate `src/` — and `*.min.js`).

**Protocol amendment, made before any classification.** The first
draw produced two non-loops: a regex hit on a docstring line
("...for additional examples.") and a comprehension clause. Rather
than hand-discarding — which would breach no-filtering — loop
identification for Python was tightened to the **parser level**:
loops are `ast.For` / `ast.While` / `ast.AsyncFor` nodes, which
excludes strings, comments, and comprehensions by construction. The
draw was then re-run from the same seed. JS identification stays
regex-based (with comment-line filtering), verified by reading.
Survey 1's regex draw was inspected retroactively: all thirty of its
hits are genuine statement loops, so its results are unaffected.
Future Python surveys should use the ast rule.

Biases: one project per domain, so project style and domain are
confounded; `mpmath` is unusually loop-dense (fixed-point kernels);
three.js's idiom is index-based mutation of typed arrays, which reads
as more stateful than it is. Same n = 30 coarseness as survey 1.

## The sample (survey 2)

Grouped by classification, using survey 1's classes plus the new ones
the sample forced (marked *new*).

### Class 1 — stateless per-element work (17 of 30)

**mpmath 5** — `mpmath/calculus/differentiation.py:643`

    for j in range(M):
        for i in range(min(M, L+j+1)):
            A[j, i] = a[L+j-i]

Filling a matrix from a coefficient list: a 2D index map into a keyed
collect. The inner bound depends on `j` (ragged, so a nested
uncollect, not a rectangular Cross), but each cell is computed
independently. Stateless.

**networkx 2** — `networkx/algorithms/operators/product.py:36`

    for u, v, c in G.edges(data=True):
        for x, y, d in H.edges(data=True):
            yield (u, x), (v, y), _dict_product(c, d)

The tensor-product edge generator: all pairs of two independent edge
flows, each pair mapped and yielded. This is **the Cross node**
(`product-flows-design.md`), literally — two mutually-independent
flows combined all-pairs — with a stream output. Field sighting of
Cross in exactly the designed shape.

**networkx 3** — `networkx/generators/line.py:356`

    for e in list(combinations(T, 2)):
        if e[0] not in G[e[1]]:
            raise nx.NetworkXError(...)

Validation walk: per-element check with a failure terminator.

**networkx 4** — `networkx/algorithms/centrality/flow_matrix.py:22`

    for u, v in sorted(...):
        B = np.zeros(w, dtype=dtype)
        ...build row...
        yield row, (u, v)

Per-element map with a fresh local scratch buffer each firing,
yielded as a stream. Stateless (the scratch never crosses firings).

**networkx 5** — `networkx/generators/community.py:64`

    for start in range(0, l * k, k):
        edges = itertools.combinations(range(start, start + k), 2)
        G.add_edges_from(edges)

Per-element effect (build one clique per block).

**sim 1** — `mesa/experimental/meta_agents/meta_agent.py:194`

    for agent_class in agent_classes:
        for name in agent_class.__dict__:
            if callable(...) and not name.startswith("__"):
                meta_methods[name] = original_method

Nested walk, filter, keyed collect (last-wins).

**sim 3** — `mesa/visualization/space_drawers.py:260`

    for vertices in self.hexagons:
        for v1, v2 in pairwise([*vertices, vertices[0]]):
            edge = tuple(sorted([...round(v1)..., ...round(v2)...]))
            edges.add(edge)

Adjacent-pairs iteration — `pairwise` is **window(2)**, here with a
ring closure (the first vertex appended to close the polygon) —
normalize, collect into a set (dedup collect). Field sighting of the
window operation the rail notes mention, plus two wrinkles a window
construct would need: cyclic wraparound, and dedup-collect as the
consumer.

**sim 4** — `mesa/discrete_space/voronoi.py:261`

    for region in regions:
        polygon = [coordinates[i] for i in regions[region]]
        self._cells[region].properties["polygon"] = polygon
        ...area, capacity also written...

Per-element computation with three keyed writes — one walk, three
outputs per element, done as effects. Stateless.

**textual 2** — `textual/_spatial_map.py:98`

    for grid_coordinate in self._region_to_grid_coordinates(region):
        grid_values = get_grid_values(grid_coordinate)
        if grid_values is not None:
            add_results(grid_values)

Map through an option (`Map.get` returning None — OptionIter's exact
encoding), filter the None, flatten into a collect; dedup after.
Stateless; a small composition of designed pieces.

**textual 3** — `textual/app.py:3723`

    for stack in self._screen_stacks.values():
        for stack_screen in reversed(stack):
            if stack_screen._running:
                await self._prune(stack_screen)
        stack.clear()

Teardown: nested walk, conditional async effect per element (in
reverse order), container cleared after. Stateless; bracket/lifecycle
territory rather than iteration-state territory.

**textual 5** — `textual/document/_wrapped_document.py:256`

    for y_offset in range(top_y_offset + new_height, len(self._offset_to_line_info)):
        old_line_index, section_offset = self._offset_to_line_info[y_offset]
        self._offset_to_line_info[y_offset] = (old_line_index + line_shift, section_offset)

In-place map over a slice of a table: shifting a derived index after
an edit. Each entry independent — stateless — but note what the code
*is*: hand-rolled maintenance of a derived structure after an edit,
i.e. the incremental flow's motivating pattern
(`incremental-flow-design.md`), written manually.

**chess 1** — `chess/svg.py:359`

    for rank_index, rank_name in enumerate(chess.RANK_NAMES):
        y = ...rank_index...
        svg.append(_coord(...)); svg.append(_coord(...))

Per-element effects (two appends per element); `enumerate` supplies
element + position. Stateless.

**chess 5** — `chess/engine.py:2083`

    for option in self.engine.options.values():
        if option.default is not None:
            self.engine.config[option.name] = option.default
        if option.default is not None and not option.is_managed():
            self.engine.target_config[option.name] = option.default

Filter + two keyed collects from one walk — a multi-close, done as
two conditional writes. Stateless.

**three 1** — `three/src/extras/ShapeUtils.js:79`

    for ( let i = 0; i < triangles.length; i += 3 ) {
        faces.push( triangles.slice( i, i + 3 ) );
    }

Fixed-size chunking (stride 3): regroup a flat list into triples +
collect. The fixed-rate cousin of data-dependent take — consumption
rate ≠ 1, but constant. Stateless.

**three 2** — `three/src/animation/AnimationUtils.js:335`

    for ( let j = 0; j < numTimes; ++ j ) {
        const valueStart = j * targetValueSize + targetOffset;
        if ( quaternion ) { ...multiply in place... }
        else { for k: values[valueStart + k] -= referenceValue[k] }
    }

Strided in-place map over a flat typed array with a case split.
Stateless (each stride independent). The flat-array-with-stride idiom
is pervasive in this corpus — a layout concern, not a flow concern.

**three 3** — `three/src/helpers/CameraHelper.js:335`

    for ( let i = 0, l = points.length; i < l; i ++ ) {
        position.setXYZ( points[ i ], _vector.x, _vector.y, _vector.z );
    }

Per-element effect (write one computed value to many indices).
Stateless. (`_vector` is a module-scratch reuse idiom, not loop
state.)

**three 5** — `three/src/renderers/webgl-fallback/utils/WebGLTextureUtils.js:547`

    for ( let i = 0; i < mipmaps.length; i ++ ) {
        const mipmap = mipmaps[ i ];
        ...case splits on texture kind...
        gl.compressedTexSubImage2D( ..., i, ..., mipmap.data );
    }

Per-element effect with case splits (upload each mip level; the index
is data — the GL level argument). Stateless.

### Class 2 — search / first-match (1 of 30)

**networkx 1** — `networkx/algorithms/regular.py:161`

    for outer_n in outer:
        for neighbor, attrs in g._adj[outer_n].items():
            if neighbor not in core_set:
                g.add_edge(node, neighbor, **attrs)
                break

Per outer element, find the first acceptable neighbor, act on it,
stop. First-match with an effect at the match — end-when plus a
readout again, nested inside a plain walk.

### Class 3 — conditional carry (2 of 30)

**chess 3** — `chess/polyglot.py:468`

    chosen_entry = None
    for i, entry in enumerate(self.find_all(board, ...)):
        if chosen_entry is None or _randint(random, 0, i) == i:
            chosen_entry = entry
    if chosen_entry is None: raise IndexError()

Reservoir sampling: one carried variable, conditionally overwritten,
read after; the condition uses the position and a random draw. Second
field sighting of conditional carry, and again exactly one writeback
with a conditional value. The post-loop None check is the empty-flow
case surfacing as a failure.

**three 4** — `three/src/materials/nodes/manager/NodeMaterialObserver.js:578`

    let morphChanged = false;
    for ( let i = 0; i < ...influences.length; i ++ ) {
        if ( renderObjectData.morphTargetInfluences[i] !== object.morphTargetInfluences[i] ) {
            renderObjectData.morphTargetInfluences[i] = object.morphTargetInfluences[i];
            morphChanged = true;
        }
    }
    if ( morphChanged ) return false;

Compare-and-sync: per-element conditional effect (write back the
changed entries) **plus** a boolean any-changed flag — an OR-fold that
cannot early-exit because the sync must visit every element. One walk,
two outputs (effects + flag). Also notable as hand-rolled change
detection — cutoff, in the incremental flow's vocabulary.

### Class 4 — read-until-sentinel pump (1 of 30)

**chess 4** — `chess-sdist/fuzz/pgn.py:20`

    while True:
        game = chess.pgn.read_game(pgn)
        if game is None: break
        repr(game)
        if not game.errors: str(game)

Parse-until-EOF pump: sentinel `None`, per-element effects. Survey
1's class 4 shape exactly.

### Class 5 — condition-driven repetition / event loop (2 of 30)

**mpmath 4** — `mpmath/functions/bessel.py:953`

    n = m+1
    while 1:
        r1, err = mcmahon(ctx, kind, prime, v, n)
        if err < isoltol:
            ...compute intervals, fill cache...
            return find_in_interval(ctx, f, intervals[m-1])
        else:
            n = n*2

Retry with geometric escalation: a carried register (`n`, doubled
each round) driving repeated attempts until a data condition holds,
then exit with a computed payload (after a cache-filling side walk).
Register + data-driven exit + result payload in one loop.

**textual 1** — `textual/drivers/_input_reader_linux.py:34`

    while not exit_set():
        for _key, events in self._selector.select(self.timeout):
            if events & EVENT_READ:
                data = read(fileno, 1024)
                if not data: return
                yield data
        yield b""

A complete event loop in seven lines: an external source polled with
a timeout, an **interrupt** (the exit event ends the stream from
outside), an **EOF sentinel** (empty read ends it from the data), a
stream output, and a per-round heartbeat (`yield b""`). The async
doc's inventory — external flow, interrupt, data-driven end,
failability's cousins — all at once, in the wild. Stateless apart
from the control conditions.

### Class 6 — cursor / worklist (1 of 30)

**textual 4** — `textual/css/parse.py:388`

    while True:
        token = next(iter_tokens, None)
        if token is None: break
        if token.name == "variable_name":
            variable_tokens = variables.setdefault(variable_name, [])
            yield token
            while True: ...consume whitespace...
            while True:
                ...append definition tokens to variable_tokens...
                elif token.name == "variable_ref":
                    ref_name = token.value[1:]
                    if ref_name in variables: ...substitute stored tokens...

A tokenizer-substituter: pull-based consumption at a variable rate
(nested sub-loops consume more tokens depending on what was seen),
stream in / stream out, and a keyed accumulator (`variables`) that is
**both written and read back during the walk** — variable definitions
are collected and then substituted into later references. Survey 1's
class 7 (worklist) shape, and the second independent sighting of
*reading the collect-so-far mid-walk* (survey 1: textwrap read its
`lines`; here the parser reads its `variables`).

### Class 9 — the scan: loop-carried arithmetic recurrence (*new*, 5 of 30)

**mpmath 1** — `mpmath/calculus/extrapolation.py:865`

    b = self.ctx.one
    s = 0
    for k in range(n):
        b = 2 * (n + k) * (n - k) * b / ((2 * k + 1) * (k + self.ctx.one))
        s += b * S[k]
    value = s / d

The survey-1 no-show, immediately: **two carried variables** — a
recurrence register (`b`, self-referencing, also using the index) and
an accumulator (`s`). Note the wiring: `s`'s step reads `b`'s
*current-iteration updated value*, not `b`'s previous value. In port
vocabulary: `s.step` wires from the value node feeding `b.step` — an
ordinary value wire, no second state port needed. Real chained
recurrences do this routinely (see also mpmath 2), which confirms the
conversion analysis's load-bearing assumption in the concrete: state
ports carry no within-iteration dependency on each other; the
within-iteration chaining rides the value wires.

**mpmath 2** — `mpmath/functions/theta.py:189`

    while are**2 + aim**2 > MIN:
        bre, bim = (bre*x2re - bim*x2im) >> wp, (bre*x2im + bim*x2re) >> wp
        are, aim = (are*bre - aim*bim) >> wp, (are*bim + aim*bre) >> wp
        t1..t4 = ...cnre, cnim, snre, snim rotation...
        cnre, cnim, snre, snim = t1, t2, t3, t4
        sre += ((are*cnre - aim*cnim) >> wp)
        sim += ((aim*cnre + are*cnim) >> wp)
        n += 2

A fixed-point theta-series kernel: **eight-plus carried registers**
advancing together — a geometric pair (`b`), a term pair (`a`)
reading `b`'s new value, a rotation quadruple (`cn`,`sn`) where each
new value reads *both* old values (the cross-referencing register
pair — Fibonacci's shape — in production code), two series
accumulators, and a counter. Termination is a **take-while on the
carried state** (loop while the term is big enough): the scan and
data-driven termination (end-when) in one construct, inseparable.
This single loop exercises nearly everything the iteration-state
design must serve: many independent registers, cross-references,
within-iteration chaining, accumulators reading registers, and a
data-driven end.

**mpmath 3** — `mpmath/libmp/gammazeta.py:1434`

    for n in range(5, N+1, 4):
        U = (n-1)//4
        s = zeta_values[4*U+2]*(2*U+1)
        for k in range(1, 2*U+1):
            s += ((-1)**k * 2*k * zeta_values[2*k] * zeta_values[4*U+2-2*k]) >> wp
        zeta_values[n] += ((s*reciprocal_pi) >> wp)//(2*U)

Dynamic programming: filling a table where each entry's computation
**indexes into earlier entries of the same table** (`zeta_values[2*k]`
read while `zeta_values[n]` is being produced). The inner loop is a
plain reduce; the outer structure is a *history-indexed collect* — a
collect whose per-element body can read arbitrary already-produced
elements by position. This is stronger than the running-view question
(reading the collect-so-far as a value) and stronger than window
(bounded recent history): it is scan-with-full-history, and nothing
in the current or candidate inventory names it. Recurrence tables are
the bread of numerics, so this is unlikely to be a rare draw.

**sim 5** — `mesa/discrete_space/property_layer.py:362`

    for prop_name, condition in conditions.items():
        prop_mask = condition(self._mesa_property_layers[prop_name].data)
        combined_mask = np.logical_and(combined_mask, prop_mask)

A fold with `logical_and` — associative, with identity (all-true, and
indeed the surrounding function initialises exactly that). A
**reduce-close** in the wild, hand-rolled: the operator carries the
identity, the user never thinks "running mask".

**chess 2** — `chess/__init__.py:4135`

    def intersection_update(self, *others):
        for other in others:
            self &= other

A fold with `&` into self — again associative-with-identity, again
reduce-close-shaped, two lines long. (The surrounding class repeats
the shape for `|=` in `update`.)

### One-off — recursive gather (1 of 30)

**sim 2** — `mesa/discrete_space/cell.py:199`

    for neighbor in self.connections.values():
        neighborhood.update(
            neighbor._neighborhood(radius - 1, include_center=True)
        )

Radius-r neighborhood by recursion: per-element recursive call,
results merged into a keyed collect (the dict doubles as dedup, since
overlapping sub-neighborhoods revisit cells). The loop itself is a
stateless flatten-and-merge; the interesting structure is the
recursion it participates in — self-similar descent with a merge at
each level, which is `trees-and-recursion.md` / divide-flow
territory rather than iteration state.

## Tally (survey 2)

| Class | n | Note |
|---|---|---|
| 1. Stateless per-element work | 17 | incl. Cross (networkx 2), window(2) (sim 3), chunking (three 1), option-filter (textual 2) |
| 2. Search / first-match | 1 | networkx 1 |
| 3. Conditional carry | 2 | reservoir sampling; any-changed flag |
| 4. Read-until-sentinel pump | 1 | chess 4 |
| 5. Condition-driven repetition / event loop | 2 | retry-escalation; full event loop |
| 6. Cursor / worklist | 1 | tokenizer with mid-walk readback |
| 9. Scan / recurrence / fold (*new*) | 5 | 3 numerics, 1 simulation, 1 games |
| 7, 8 (worklist-textwrap, reset) | 0 | classes from survey 1; no new instances |
| Recursive gather (*one-off*) | 1 | sim 2: recursive neighborhood merge into a keyed dedup collect — the divide flow / trees territory |

Cross-cutting: early termination 6–7 of 30 (vs 11–12 in survey 1);
effects-as-payload ≈ 12 of 30; genuine carried state 9 of 30 (vs 5).

## Findings (survey 2)

### 2.1 The scan exists, and it lives where predicted

Five of thirty draws are scans/folds — and all three mpmath stateful
draws are dense recurrence kernels. Survey 1's zero was corpus skew,
exactly as its caveat said. The corrected statement, now with evidence
on both sides: **the scan is real and domain-concentrated.** In
numerics it is the *dominant* loop shape (4 of 5 mpmath draws carry
state); in infrastructure code it is nearly absent. The
iteration-state machinery is not niche — but its demand is
domain-shaped, which matters for the decision bar: "flexible enough
for complex code" is mostly a numerics/simulation requirement, while
the beginner-facing everyday loop is a search, a pump, or a stateless
walk.

### 2.2 Cross-referencing registers occur in production code

mpmath 2's `cn`/`sn` rotation pair — each new value computed from
both old values — is the Fibonacci shape the design record treats as
the canonical hard case, running in a production theta-function
kernel. The record's insistence that cross-references be ordinary
wires (both candidates) and that cycles be first-class (the recorded
cycles-are-inevitable position) is validated by field demand, not
just by the toy example.

Additionally, both mpmath 1 and mpmath 2 chain registers *within* an
iteration (`s` reads `b`'s new value, `a` reads `b`'s new value):
the step of one register wires from the value feeding another
register's step. This is an ordinary value wire in both candidates —
no second state port, no ordering among state ports — which concretely
confirms the conversion analysis's assumption that stack order among
augmentations carries no semantics (the within-iteration chaining
rides value wires, never state ports). Worth stating because it is
exactly the kind of assumption a survey could have broken.

### 2.3 Reduce-close and operator identities gain urgency

Three independent monoid folds (logical-and over masks, bitwise-and
over square sets, boolean-or as an any-changed flag) — all
hand-rolled, all with the operator's genuine identity as the start
value. This is reduce-close's exact boundary
(`iteration-with-state-design.md`, "Two operations for accumulation"),
now with field frequency behind it, and it presses on the open
question recorded there: **how operator identities attach** (`+`→0,
`and`→true, `&`→full-mask...). Note the third fold (three 4) cannot
early-exit despite being an `any`, because the same walk performs
per-element sync effects — one logical iteration, two consumers
(effects + fold), i.e. multi-close earning its keep.

### 2.4 One-writeback: still unbroken, now including dense numerics

Every register in every survey-2 loop updates exactly once per
firing, unconditionally (the scans) or conditionally-as-one-value
(the carries). The eight-register kernel is eight parallel
single-writeback threads, not a multi-writeback anything. Two surveys
and sixty loops in, no counterexample to the thread's rule has been
drawn.

### 2.5 The history-indexed collect is a real gap

mpmath 3 (finding stated in its entry): a collect whose per-element
body indexes into the collect's own earlier output. Combined with
survey 1's textwrap (reading the collect-so-far as a whole, and
rewriting its last element) and survey 2's textual 4 (reading back a
keyed collect mid-walk to substitute variable references), the
"running view of a collect" question from survey 1 is now **three
independent sightings in three guises** — read-whole, read-by-index,
read-by-key — and should be treated as a recurring demand, not a
curiosity. It files somewhere between multi-close (what may be
observed of an iteration while it runs) and the register designs
(what may be carried), and no current construct owns it.

### 2.6 Designed constructs sighted in the wild, in their designed shapes

Worth recording because it is confirmation the vocabulary is carving
reality at its joints: **Cross** (networkx 2 — the tensor-product
generator is two flows all-pairs, verbatim); **window(2)** (sim 3's
pairwise, with a ring-closure wrinkle a window construct should
anticipate); **OptionIter's encoding** (textual 2 — `get` returning
None, checked and skipped); **the async inventory** (textual 1's
seven-line event loop contains an external source, an interrupt, a
data-driven end, and a stream output simultaneously); **the
incremental flow's motivating pattern, hand-rolled** (textual 5's
derived-index maintenance after an edit; three 4's change detection
with cutoff); and **trees/divide territory** (sim 2's recursive
neighborhood gather). Each was designed from first principles or from
the tough use cases; each was then drawn at random within thirty
files of its home domain.

### 2.7 Early exit: lower here, still second place

6–7 of 30 (vs survey 1's 11–12): library and numerics code terminates
early less often than infrastructure glue, but data-driven
termination still appears across four corpora — and in the numerics
corpus it appears *fused to the scan* (mpmath 2's take-while on the
carried term; mpmath 4's retry-until-tolerance). Combined across
surveys: roughly 18 of 60. The survey-1 recommendation stands, with a
sharpening: end-when must compose with the register/thread designs,
because real numeric loops stop *because of* their carried state.

## The combined picture (n = 60)

| | Survey 1 (infra) | Survey 2 (domains) | Combined |
|---|---|---|---|
| Stateless per-element work | 15 | 17 | 32 (53%) |
| Genuine carried state | 5 | 9 | 14 (23%) |
| — of which scans/folds | 0 | 5 | 5 |
| Early termination | 11–12 | 6–7 | ~18 (30%) |
| Effects as the payload | ~13 | ~12 | ~25 (42%) |

The shape that emerges across sixty random loops from nine projects
in five languages:

- **The center holds.** Half of everything is uncollect/collect
  vocabulary, before counting the excluded combinators.
- **Termination is the biggest unserved everyday demand.** ~30%
  of all loops end early or on a data condition; end-when (plus its
  readout composition) is the highest-frequency gap in both corpus
  families.
- **Iteration state is real, domain-shaped, and internally simple.**
  ~23% carry state; the hard cases (many registers, cross-references,
  take-while fused to the scan) concentrate in numerics; and across
  all fourteen stateful loops, every register is one-writeback and
  every cross-reference is a plain value wire. The candidates'
  shared structural commitments survive contact.
- **Three recurring demands have no owner yet:** the running/
  history-indexed view of a collect (three sightings, three guises);
  variable-rate consumption (textwrap, the tokenizer — the
  decision-driven family's "advance how far"); and reduce-close's
  operator identities (three hand-rolled monoid folds).

## Reading the frequencies: the 80/20 counterweight

*(Now also a standing rule of the method —
`language-design-philosophy.md`, "A standing method: sample
reality".)*

The tables above must not be read as "optimize for the fat rows and
deprioritize the thin ones." A sample measures how often a shape
occurs, not how much time it costs to write. Per the 80/20 rule, most
of a programmer's time goes to the rare hard cases — so the most
annoying loop to write can break the language even when every common
case is trivial. Frequency evidence therefore cuts one way only:
high frequency ranks what must be *effortless*; a shape drawn once is
a **breadth obligation** — something the language must handle without
too much pain — never a deprioritization candidate.

Read that way, the surveys yield a second artifact alongside the
tallies: the singleton hard draws are randomly-harvested members of
the same set `tough-use-cases-design.md` constructs deliberately.
Collected as **the breadth set** — nine loops the language must be
able to express without too much pain, each drawn blind:

1. **The wrap loop** (survey 1, textwrap.py) — variable-rate
   consumption, mid-walk read *and rewrite* of the output-so-far,
   truncation break. **No owner**; the sharpest standing challenge.
2. **The tokenizer-substituter** (survey 2, textual css/parse.py) —
   variable-rate pull, nested state-dependent sub-loops, keyed
   collect read back mid-walk. **No owner**; the same challenge from
   the parsing side.
3. **The theta kernel** (survey 2, mpmath) — eight-plus registers,
   cross-references, within-iteration chaining, take-while on carried
   state. Owner: the register candidates + end-when; the test is
   whether eight threads stay *legible*, not merely expressible.
4. **The DP table fill** (survey 2, mpmath gammazeta) — a collect
   indexed into its own earlier output. **No owner** (the
   history-indexed collect, finding 2.5).
5. **The buffer with conditional flush** (survey 1, net/http) —
   multi-site append, reset entangled with effect ordering. Owner:
   registers + the custom-flows effect story, jointly; untested
   jointly. *(Now has a worked exploration round —
   `within-firing-effects-design.md`: the buffer dissolves into a
   segmentation of the op flow (split-when + the effect thread); the
   register half of the joint ownership was the imperative costume,
   and the caveat recorded under finding 3 — "what strains is effect
   ordering, which no writeback count addresses" — is discharged
   there.)*
6. **The backtracking parser** (survey 1, rdoc markdown) —
   save/restore cursor; wants the save/restore *pairing* visible.
   Owner: registers express it; nothing yet makes it legible.
7. **The event loop** (survey 2, textual input reader) — external
   source, interrupt, sentinel end, stream out, heartbeat, in seven
   lines. Owner: the async/FFI inventory — this is its acceptance
   test in miniature.
8. **The retry-with-escalation** (survey 2, mpmath bessel) — register
   + data-driven exit with payload + cache side-walk. Owner:
   register + end-when + the readout composition.
9. **The recursive gather** (survey 2, mesa cell) — self-similar
   descent with per-level merge. Owner: the divide flow /
   trees-and-recursion.

Six of nine have at least a designed owner to be tested against;
items 1, 2, and 4 — all three faces of variable-rate consumption and
the running view — have none. By the 80/20 reading, that cluster is
where the language's breadth risk currently concentrates, whatever
the frequency tables say about scans and searches. *(The cluster now
has a worked exploration round to be tested against —
`variable-rate-consumption-design.md` (split-when; the running view as
the collect's derived state port), which works items 1, 2, and 4
end-to-end, including their +1 ladders. Nothing adopted; the "no owner"
statements above describe the record as sampled.)*

*(Companion criterion, from the seventh principle — "Building blocks
must build", `language-design-philosophy.md`: each breadth-set member
is also an **expansion test**, not just an expressibility test. The question is not only "can this be written
without pain" but "is it reachable from the simple form of the same
program by +1 steps" — the theta kernel from a beginner's running
sum by adding links; the wrap loop from a plain list collect by
whatever construct eventually owns variable-rate consumption. A
breadth-set member that is expressible only by abandoning the simple
vocabulary and starting over fails the test even if the exotic
version is painless. This is the survey-evidence form of the
map/filter complaint: constructs the common case teaches must be the
same constructs the hard case is built from.)*

## Next round (updated)

- **UI/browser event-handling in JS** remains under-sampled (textual
  covered terminal UI in Python; three.js's draws landed in geometry
  and GPU plumbing, not its event/render loop).
- **A concurrency-focused sample** (server codebases, async-heavy
  projects) to give the tough-use-cases inventory items 1–3 the same
  frequency treatment items 4–5 got here. *(Done — "Survey 3" below,
  with a protocol variation: the unit sampled is the orchestration
  site, not the loop.)*
- **Larger n / combinator census**: as before.

---

# Survey 3: concurrency orchestration

Thirty concurrency orchestration sites from six server/async-heavy
corpora. Same method, different unit: Surveys 1–2 sampled loops; this
survey samples the places where code creates, coordinates, or guards
concurrency, because that is where inventory items 1–3 — the concurrent
collect, the served flow, bracket — and the async doc's barriers live.
Protocol below.

## Why a different unit

The loop surveys measured what iteration constructs must serve.
Inventory items 1–3 were promoted by the five tough use cases, not
by frequency — `open-problems.md` flags the concurrency row's
evidence as thin, and the async doc's race barrier (question 5) owes
its own round. Sampling loops again would not reach this code: the
interesting structure in concurrent programs sits at spawn points,
barriers, timeouts, locks, and queues, most of which are not loops.
So the unit here is the **orchestration site**, defined by a fixed
published vocabulary (below), drawn seeded and unfiltered exactly as
before.

## Protocol (survey 3)

Corpora fetched from the public registries (pip / npm) onto the
survey machine, one project per subdomain:

| Corpus | Project | Domain |
|---|---|---|
| aiohttp | aiohttp 3.14.1 | async HTTP server + client (Python) |
| uvicorn | uvicorn 0.51.0 | ASGI server: process supervision, protocols |
| websockets | websockets 16.0 | WebSocket protocol library (Python) |
| celery | celery 5.6.3 | distributed task queue, thread-based worker |
| fastify | fastify 5.10.0 | HTTP server framework (JS) |
| undici | undici 8.7.0 | HTTP client with connection pooling (JS) |

**What counts as a site.** Python identification is parser-level
(`ast`), per survey 2's amendment:

- an `ast.Call` whose callee name (or attribute suffix) is in a
  fixed orchestration vocabulary — spawn/structured concurrency
  (`create_task`, `ensure_future`, `gather`, `wait`, `wait_for`,
  `as_completed`, `shield`, `to_thread`, `run_in_executor`,
  `run_coroutine_threadsafe`, `TaskGroup`, `create_task_group`,
  `start_soon`, `open_nursery`), timers/scheduling (`sleep`,
  `call_soon`, `call_later`, `call_at`, `call_soon_threadsafe`,
  `timeout`), sync-primitive constructors (`Lock`, `RLock`,
  `Semaphore`, `BoundedSemaphore`, `Event`, `Condition`, `Barrier`,
  `Queue` and variants, `Future`, `create_future`),
  threads/processes/pools (`Thread`, `Timer`, `ThreadPoolExecutor`,
  `ProcessPoolExecutor`, `Pool`, `submit`), and
  `add_signal_handler`;
- an `ast.AsyncWith` or `ast.AsyncFor` statement;
- an `ast.With` whose context expression mentions an identifier
  containing lock/sem/cond/mutex (lock-usage sites).

JS identification is regex-based with comment-line filtering,
verified by reading (survey 1's precedent): Promise combinators
(`all`/`race`/`any`/`allSettled`/`withResolvers`), `new Promise`,
`AbortController`/`AbortSignal`, timers (`setTimeout`,
`setInterval`, `setImmediate`, `queueMicrotask`,
`process.nextTick`), `new Worker`, `MessageChannel`, `Atomics`,
`for await`.

**Selection.** Seed `20260710` retagged per corpus
(`random.Random(f"20260710:{name}")`), shuffled sorted file list,
walk in shuffled order, in each file containing at least one site
pick **one** site uniformly at random, five per corpus, thirty
total. Excluded paths: `*test*`, `__pycache__`, `/docs/`,
`/examples/`, `/benchmarks/`, `*.min.js`, `.dist-info`. File counts
after exclusion: aiohttp 53, uvicorn 41, websockets 48, celery 154,
fastify 39, undici 112.

**Two identification slips, kept and flagged** (don't-filter means
they stay; both turned out to be genuine concurrency sites of a
different kind than the pattern intended):

- celery 5 was drawn by the with-lock heuristic matching
  `block=True` — "block" contains "lock". The site is actually a
  *pooled-resource acquire bracket*, in scope on its own merits.
  Future runs should match on word boundaries.
- celery 3 was drawn by the `Queue` constructor rule, but the
  `Queue` is kombu's AMQP queue — a broker route declaration, not a
  threading queue. A vocabulary collision across domains; kept and
  classified at the domain level.

Stated biases, beyond the vocabulary itself:

- **These corpora implement concurrency infrastructure.** All six
  are libraries/frameworks whose job is to provide concurrency to
  applications, so the sample over-represents the *machinery* of
  primitives (timeout internals, pool guts, protocol bridges)
  relative to application-level orchestration ("fetch these five
  things in parallel"). Direction: it strengthens findings about
  what hand-rolled machinery a language would replace, and
  under-measures how often an application reaches for gather vs
  race. An application-level sample is the stated next round.
- **Plain `await` is excluded by construction.** Sequential
  composition (bind) is the dominant async operation and is already
  served structurally (nesting); counting it would only inflate the
  "already served" bucket. Same direction as survey 1's combinator
  exclusion.
- **Event-listener registration (`.on`/`.once`) is excluded** on
  the JS side, and callback-slot assignment generally — so
  event-source *wiring* is undersampled relative to its true
  frequency in Node code.
- **n = 30**, same coarseness as before; one site per file caps
  density, so loop-dense files contribute no more than sparse ones.

## The sample (survey 3)

Grouped by classification; class names defined by the entries.

### Class C1 — completion cells: deferreds, one-shot futures, memoised barriers (4 of 30)

**aiohttp 1** — `aiohttp/client_reqrep.py:400`

    @property
    def upload_complete(self):
        if self._upload_complete is None:
            self._upload_complete = self._loop.create_future()
            if self._stream_writer is None:  # upload already finished
                self._upload_complete.set_result(None)
        return self._upload_complete

A lazily-minted future marking "request body fully sent" —
already-resolved if the milestone has passed. A **lifecycle
completion output** as a first-class value, minted on demand so that
un-observed milestones cost nothing. The inventory's "lifecycle
barrier outputs (completions)" appearing as a hand-built cell.

**fastify 2** — `fastify/lib/promise.js:7`

    function withResolvers () {
      let res, rej
      const promise = new Promise((resolve, reject) => { res = resolve; rej = reject })
      return { promise, resolve: res, reject: rej }
    }

The deferred pattern as a utility (polyfill for
`Promise.withResolvers`): a promise created **empty**, with the
write half handed out separately. The eager-promise conflation
(`async-flow-design.md`) undone by hand — the executor exists only
to smuggle the resolvers out. That a server framework needs this as
a building block (and that JS eventually added it to the language)
is field evidence that the write-once cell with an external write
half, not the eager computation, is the primitive.

**fastify 5** — `fastify/fastify.js:526`

    function ready (cb) {
      if (this[kState].readyResolver !== null) { ...share existing promise... }
      process.nextTick(runHooks)
      // "It will work as a barrier for all the .ready() calls
      //  (ensuring single hook execution)"
      this[kState].readyResolver = PonyPromise.withResolvers()
      ...

The ready barrier: the first `.ready()` call mints a deferred and
schedules the boot hooks; every later call shares the same promise.
A **memoised one-shot cell** — lazily started, computed once, value
shared by all consumers — which is precisely the async doc's
`__asyncCell__` discipline, hand-enforced with a null check and a
stored resolver.

**undici 1** — `undici/lib/web/websocket/stream/websocketstream.js:116`

    this.#openedPromise = Promise.withResolvers()
    this.#closedPromise = Promise.withResolvers()
    if (options.signal != null) {
      if (signal.aborted) { ...reject both, return... }
      addAbortListener(signal, () => { ...fail connection, reject both... })
    }

A resource (WebSocketStream, per the WHATWG spec) with **two
lifecycle cells — opened and closed — plus an interrupt input**. The
abort wiring shows the standard two-step: check if the signal
already fired, then subscribe — the registration race every
event-object consumer must handle by hand. Lifecycle outputs and the
cancellation input as explicit per-resource ports, in a spec-mandated
shape.

### Class C2 — race and timeout (5 of 30)

**websockets 3** — `websockets/asyncio/server.py:136`

    await asyncio.wait(
        [self.request_rcvd, self.connection_lost_waiter],
        return_when=asyncio.FIRST_COMPLETED,
    )
    if self.request is not None:
        ...proceed with handshake...

**The race barrier, verbatim**: handshake-request arrival raced
against connection loss. And the load-bearing detail: the
discrimination — who won — is *not delivered by the race*; it is
reconstructed afterwards by inspecting a side variable
(`self.request is not None`). The correspondence between contender
and continuation survives only in the programmer's head, which is
exactly the bottleneck argument for race's per-contender output
flows (`async-flow-design.md`, "Racing is a barrier, not a value").

**websockets 5** — `websockets/cli.py:118`

    incoming = asyncio.create_task(print_incoming_messages(websocket))
    outgoing = asyncio.create_task(send_outgoing_messages(websocket, protocol.messages))
    try:
        await asyncio.wait([incoming, outgoing], return_when=asyncio.FIRST_COMPLETED)
    finally:
        incoming.cancel(); outgoing.cancel(); transport.close()

The interactive client: two stream-drains (server→screen,
stdin→server) raced; whichever ends first (server close or ^D) wins;
the loser is cancelled in `finally`. Unless-and-until over two
threads-as-drained-streams, with abandonment handled by explicit
cancellation and bracket-shaped cleanup.

**fastify 4** — `fastify/lib/route.js:530`

    const ac = new AbortController()
    request[kTimeoutTimer] = setTimeout(() => {
      if (!reply.sent) {
        const err = new FST_ERR_HANDLER_TIMEOUT(...)
        ac.abort(err); reply.send(err)
      }
    }, handlerTimeout)
    const onAbort = () => { if (!ac.signal.aborted) ac.abort(); clearTimeout(...) }
    req.on('close', onAbort)

Per-request handler timeout: a timer racing the handler, the winner
determined by **flag checks** (`reply.sent`, `signal.aborted`),
cancellation propagated by signal, and the timer/close cleanup
paired by hand. race(handler, timer) with the discrimination again
reconstructed from state.

**websockets 4** — `websockets/asyncio/async_timeout.py:254` *(vendored
copy of the async-timeout library — library-machinery code, flagged
as such)*

    self._timeout_handler = self._loop.call_at(deadline, self._on_timeout)
    ...
    def _do_exit(self, exc_type):
        if exc_type is asyncio.CancelledError and self._state == _State.TIMEOUT:
            _uncancel_task(self._task)
            raise asyncio.TimeoutError

The inside of `async with timeout(...)`: a timer that **cancels the
current task**, a four-state machine (INIT/ENTER/TIMEOUT/EXIT), and
an exit hook that converts the self-inflicted `CancelledError` into
`TimeoutError` — carefully un-counting the cancellation so an outer
*real* cancellation still propagates. This is what
interrupt-plus-terminator-discharge costs when the interrupt channel
is task cancellation: the "why did this end" discrimination is
threaded through an exception type, a state enum, and a cancel
counter.

**aiohttp 4** — `aiohttp/helpers.py:600`

    return loop.call_at(when, _weakref_handle, (weakref.ref(ob), name))

Timeout plumbing: schedule a method call at a deadline — through a
**weakref**, so the pending timer does not keep the target alive.
The retention question (`async-flow-design.md`, event sources;
`lazy-stream-placement-design.md`, `Delayed` retention) in the wild:
a scheduled future effect is a reference, and library authors must
hand-break the cycle timer→object→timer.

### Class C3 — interrupt, shutdown, and cancellation delivery (4 of 30)

**uvicorn 1** — `uvicorn/supervisors/basereload.py:35`

    self.should_exit = threading.Event()
    def signal_handler(self, sig, frame):
        self.should_exit.set()
    def pause(self):
        if self.should_exit.wait(self.config.reload_delay):
            raise StopIteration()

The interrupt shape end-to-end: OS signal → one-shot event; the
reload loop's tick is `should_exit.wait(delay)` — literally
race(timer, interrupt) once per iteration, with the interrupt
winning by raising out of the iterator. The async doc's
unless-and-until, hand-rolled on threading primitives.

**aiohttp 2** — `aiohttp/web_protocol.py:327`

    self._force_close = True
    ...
    self._handler_waiter = self._loop.create_future()
    async with ceil_timeout(timeout):
        await self._handler_waiter          # wait for graceful completion
    ...
    async with ceil_timeout(timeout):
        if self._current_request is not None:
            self._current_request._cancel(asyncio.CancelledError())
        await asyncio.shield(self._task_handler)
    ...
    self._task_handler.cancel()             # force-close non-idle handler

Graceful connection shutdown: refuse new work, wait bounded time for
the in-flight request (a completion cell created only when needed),
then cancel-and-shield-await, then force-cancel. **The
graceful-shutdown backlog program** (tough doc addenda) drawn at
random: interrupt + bounded drain + escalating cancellation, three
stages of it, each stage a timeout race. The `shield` is the honest
marker of how delicate "wait for the thing you are cancelling" is.

**celery 2** — `celery/worker/pidbox.py:107`

    shutdown = self._node_shutdown = threading.Event()
    stopped = self._node_stopped = threading.Event()
    try:
        with c.connection_for_read() as connection:
            while not shutdown.is_set() and c.connection:
                if resets[0] < self._resets: ...reset channel...
                try: connection.drain_events(timeout=1.0)
                except socket.timeout: pass
    finally:
        stopped.set()

The broadcast-command thread: a drain loop checking a shutdown event
every bounded drain, a connection bracket, a reset counter
reconciled per round — and the **two-event handshake**: `shutdown`
(interrupt in) set by the stopper, `stopped` (completion out) set in
`finally`, awaited by the stopper. The lifecycle barrier pair —
interrupt input, completion output — built from two Events and a
try/finally.

**fastify 3** — `fastify/lib/request.js:221`

    get signal() {
      let ac = this[kRequestSignal]
      if (ac) return ac.signal
      ac = new AbortController()
      this.raw.on('close', () => { if (!ac.signal.aborted) ac.abort() })
      return ac.signal
    }

The served flow's failure leg (tough doc question 3), resolved the
Node way: client disconnect becomes an abort signal lazily minted
per request and delivered *into* the handler body, which must wire
it onward by hand. Per-firing cancellation as an explicit port on
the exchange.

### Class C4 — task spawn: per-firing, companion, root (4 of 30)

**uvicorn 2** — `uvicorn/protocols/websockets/wsproto_impl.py:234`

    self.queue.put_nowait({"type": "websocket.connect"})
    task = self.loop.create_task(self.run_asgi())
    task.add_done_callback(self.on_task_complete)
    self.tasks.add(task)

Task-per-connection — the **unbounded concurrent collect's firing**
— with its lifecycle bookkeeping hand-rolled: a task set (so
shutdown can find the in-flight bodies) maintained by a
done-callback. The collect's "starts" and "completions" outputs,
built from a set and a callback.

**websockets 2** — `websockets/legacy/server.py:147`

    # Register the connection with the server before creating the handler
    # task. Registering at the beginning of the handler coroutine would
    # create a race condition between the creation of the task, which
    # schedules its execution, and the moment the handler starts running.
    self.ws_server.register(self)
    self.handler_task = self.loop.create_task(self.handler())

Task-per-connection again (second sighting), and the comment is the
finding: registration must precede spawn or the task's startup races
the bookkeeping. The **spawn-registration race** is real enough to
carry a four-line explanatory comment in a mature library — the
ordering a structural "starts" output would give by construction.

**uvicorn 5** — `uvicorn/lifespan/on.py:51`

    main_lifespan_task = loop.create_task(self.main())  # noqa: F841
    # Keep a hard reference to prevent garbage collection
    # See https://github.com/Kludex/uvicorn/pull/972
    await self.receive_queue.put(startup_event)
    await self.startup_event.wait()

Spawn a long-lived companion task, then rendezvous with it via a
queue and a one-shot event. The comment marks a real bug class:
asyncio holds tasks weakly, so a spawned task referenced by nothing
gets **garbage-collected mid-flight**. A complete program whose
parts hang off no root expression — the "program is a node set, not
a root expression" consequence (`first-class-ports-design.md`) with
a production incident number attached.

**aiohttp 3** — `aiohttp/worker.py:63`

    self._task = self.loop.create_task(self._run())
    try:
        self.loop.run_until_complete(self._task)
    except Exception: ...
    self.loop.run_until_complete(self.loop.shutdown_asyncgens())
    self.loop.close()

The gunicorn worker's root: spawn the serve task, run the loop to
its completion, then shut down async generators and close. The
sync→async **program-root bridge** — the task handle exists so
signal handlers elsewhere can cancel the whole composition. "What is
a program for a server?" (tough doc question 7) at the process
level: the program's value is its ongoing behaviour, and its exit is
an interrupt delivered to the root task.

### Class C5 — pools and permits (3 of 30)

**undici 5** — `undici/lib/dispatcher/pool-base.js:198`

    if (!dispatcher) {
      this[kNeedDrain] = true
      this[kQueue].push({ opts, handler })
    } else if (!dispatcher.dispatch(opts, handler)) { ...mark client draining... }
    ...
    [kAddClient] (client) {
      client.on('drain', ...).on('connect', ...).on('disconnect', ...)
      this[kClients].push(client)
      if (this[kNeedDrain]) {
        queueMicrotask(() => { if (this[kNeedDrain]) this[kOnDrain](...) })
      }
    }

The connection pool's guts: free client → dispatch; none → push to a
wait queue and mark `needDrain`; drain events redistribute queued
work; adding a client schedules a deferred drain check. This is
**`bounded(n)` as a resource** exactly as the inventory's addendum
reads it — permits (clients), waiters (the queue), release events
(drain) — none of it partition-shaped, all of it
permit-acquisition machinery.

**celery 5** — `celery/backends/rpc.py:331`

    with self.app.pool.acquire_channel(block=True) as (_, channel):
        binding = self._create_binding(task_id)(channel)
        binding.declare()
        for _ in range(limit):
            msg = binding.get(accept=accept, no_ack=no_ack)
            if not msg: break
            yield msg
        else:
            raise self.BacklogLimitExceeded(task_id)

A **pool-acquire bracket**: take a channel from the connection pool
(blocking on a permit), use it, release on exit. Inside: a bounded
drain (take-until-empty with a hard cap, the cap overflow a
failure), and upstream of this draw the caller deduplicates the
drained messages by task id, last-state-wins — a keyed latest-of
collect. Permits, bracket, bounded take, keyed collect, in one
function.

**uvicorn 3** — `uvicorn/supervisors/multiprocess.py:203`

    while not self.should_exit.wait(0.5):
        self.handle_signals()
        self.keep_subprocess_alive()
    self.terminate_all(); self.join_all()
    ...
    def keep_subprocess_alive(self):
        for idx, process in enumerate(self.processes):
            if process.is_alive(timeout=...): continue
            process.kill(); process.join()
            ...restart or give up...

The process supervisor: a heartbeat loop (poll the interrupt with a
timeout, again race(timer, interrupt) per tick) whose body
**reconciles a pool of permanent workers against a desired count** —
health-check each, restart the dead, distinguish
failed-at-startup (give up: the failure would repeat) from
died-while-serving (restart). Plus a rolling restart that races
`wait_until_ready` against a health timeout before swapping old for
new. The permanence theme (a real-world set kept matching a spec)
governing a worker pool.

### Class C6 — queues as callback→stream bridges (2 of 30)

**uvicorn 4** — `uvicorn/protocols/websockets/websockets_sansio_impl.py:74`

    self.queue: asyncio.Queue[ASGIReceiveEvent] = asyncio.Queue()
    ...protocol callbacks put_nowait() events...
    ...the ASGI app awaits queue.get() as its receive stream...
    self.writable = asyncio.Event()   # flow control
    ...ping/pong keepalive timers alongside...

The per-connection bridge: transport callbacks (sans-io world)
produce protocol events into a queue; the application consumes the
queue as its receive stream. **An external event source materialized
as a stream by hand** — the FFI-node stream-output shape — with
explicit flow control beside it (`pause_reading` when a message is
buffered; a writability event for the send side). The queue is the
seam between push (callbacks) and pull (the app's awaits), which is
precisely where the language's external-flow nodes sit.

**celery 3** — `celery/utils/nodenames.py:49` *(vocabulary collision,
kept and flagged — kombu's `Queue`, an AMQP entity, not a threading
queue)*

    def worker_direct(hostname):
        return Queue(
            WORKER_DIRECT_QUEUE_FORMAT.format(hostname=hostname),
            WORKER_DIRECT_EXCHANGE,
            hostname,
        )

A broker route declaration: the direct-to-one-worker queue, named by
the worker's node name. At the distributed level this is a **lane
keyed by worker identity** — the keyed-lane shape (one serial
channel per key, lanes concurrent among themselves) existing as
infrastructure between processes rather than within one. Read as
evidence that the lane abstraction is not event-loop-specific.

### Class C7 — async pumps and collects (3 of 30)

**undici 4** — `undici/lib/mock/mock-utils.js:282`

    async function getResponse (body) {
      const buffers = []
      for await (const data of body) {
        buffers.push(data)
      }
      return Buffer.concat(buffers).toString('utf8')
    }

Collect over an async stream, then fold. The async flow's collect in
exactly the designed shape — the second verbatim sighting across
surveys (survey 1's js 9 was the first).

**aiohttp 5** — `aiohttp/web_request.py:774`

    while (field := await multipart.next()) is not None:
        ...
        tmp = await self._loop.run_in_executor(None, tempfile.TemporaryFile)
        while chunk := await field.read_chunk(size=DEFAULT_CHUNK_SIZE):
            async for decoded_chunk in field.decode_iter(chunk):
                await self._loop.run_in_executor(None, tmp.write, decoded_chunk)
                size += len(decoded_chunk)
                if 0 < max_size < size:
                    await self._loop.run_in_executor(None, tmp.close)
                    raise HTTPRequestEntityTooLarge(max_size)

Multipart upload parsing: three nested pumps (fields, chunks,
decoded chunks — take-until-sentinel at each level), blocking file
effects offloaded to the executor (`to_thread`-shaped sync→async
bridging, four calls), a running size register guarding a failure
terminator that aborts the whole walk. Survey 1's class-4 pump,
composed three deep and interleaved with offloaded effects.

**celery 1** — `celery/backends/asynchronous.py:401`

    prev_on_m, self.on_message = self.on_message, on_message
    try:
        for _ in self.drain_events_until(result.on_ready, timeout=timeout, ...):
            yield
            sleep(0)
    except socket.timeout:
        raise TimeoutError(...)
    finally:
        self.on_message = prev_on_m

Wait-for-result: drain backend events **until a predicate cell
fires** (`result.on_ready` — a promise), with a timeout converted at
the boundary, a cooperative yield each round, and a save/restore
bracket on a callback slot. Drain-until is end-when's shape over an
event pump; the handler swap is a scoped-configuration bracket.

### Class C8 — retry with backoff (2 of 30)

**websockets 1** — `websockets/legacy/client.py:612`

    backoff_delay = self.BACKOFF_MIN / self.BACKOFF_FACTOR
    while True:
        try:
            async with self as protocol:
                yield protocol
        except Exception:
            if backoff_delay == self.BACKOFF_MIN:
                await asyncio.sleep(random.random() * self.BACKOFF_INITIAL)
            else:
                await asyncio.sleep(int(backoff_delay))
            backoff_delay = min(backoff_delay * self.BACKOFF_FACTOR, self.BACKOFF_MAX)
            continue
        else:
            backoff_delay = self.BACKOFF_MIN

`async for connection in connect(...)`: reconnect forever with
truncated exponential backoff, jittered first delay, reset on
success. A register (the delay) carried across firings of a
self-driven flow, stepped on the failure leg, reset on the success
leg, driving a timer. Survey 2's retry-with-escalation (mpmath 4),
now in network form.

**undici 3** — `undici/lib/handler/retry-handler.js:218`

    if (statusCode != null && ... && !statusCodes.includes(statusCode)) { cb(err); return }
    if (counter > maxRetries) { cb(err); return }
    const retryTimeout = retryAfterHeader > 0
        ? Math.min(retryAfterHeader, maxTimeout)
        : Math.min(minTimeout * timeoutFactor ** (counter - 1), maxTimeout)
    setTimeout(() => cb(null), retryTimeout)

The same construct from the client side: give-up guards (method not
idempotent, status not retryable, counter exhausted), delay from
either the server's `Retry-After` or the exponential formula, timer,
retry — plus checkpoint state for resuming a partial body. Third
sighting of retry-with-escalation across the surveys; the shape is
cross-domain.

### Class C9 — the hand-rolled all-of join (1 of 30)

**fastify 1** — `fastify/lib/reply.js:919`

    let cbAlreadyCalled = false
    function cb (err, value) {
      if (cbAlreadyCalled) return
      cbAlreadyCalled = true
      handled++
      ...
      process.nextTick(send)
    }
    const result = reply[kReplyTrailers][trailerName](reply, payload, cb)
    if (typeof result === 'object' && typeof result.then === 'function') {
      result.then((v) => cb(null, v), cb)
    }

HTTP trailer computation: scatter each trailer function (callback or
promise style, adapted by hand), join on a **completion counter**
with per-callback once-guards, and re-check readiness on the next
tick after each completion. `gather` rebuilt from a counter, a
boolean per branch, and a scheduler bounce — the one all-of join in
the sample, and it is hand-rolled because the values arrive through
callbacks rather than as awaitables.

### One-offs (2 of 30)

**undici 2** — `undici/lib/api/api-request.js:239`

    } catch (err) {
      if (typeof callback !== 'function') throw err
      queueMicrotask(() => callback(err, { opaque }))
    }

Zalgo discipline: a synchronous failure during dispatch is
**deferred to a microtask** so the callback never runs re-entrantly
inside the caller's stack. The timing half of the async value's
contract — a consumer never observes resolution synchronously —
which the event-loop-cell semantics provides by construction and
callback code must enforce by hand. (The same discipline appears as
`process.nextTick(send)` in fastify 1 and the deferred drain check
in undici 5.)

**celery 4** — `celery/worker/consumer/consumer.py:708`

    with self.qos._mutex:
        if any((not self.app.conf.worker_enable_prefetch_count_reduction,
                self._maximum_prefetch_restored)):
            return
        new_prefetch_count = min(self.max_prefetch_count, self._new_prefetch_count)
        self.qos.value = self.initial_prefetch_count = new_prefetch_count
        self.qos.set(self.qos.value)

The sample's only lock: a mutex-guarded read-modify-write of shared
QoS state, called from message-ack promise callbacks that may race,
with an idempotence guard. In flow terms: a fold over an event flow
(acks → prefetch state) that must be *serial*, with the lock
supplying the serialisation the unmarked serial collect would give
by construction.

## Tally (survey 3)

| Class | n | Inventory owner |
|---|---|---|
| C1. Completion cells / deferreds | 4 | async cell + lifecycle outputs |
| C2. Race and timeout | 5 | race barrier (round owed) |
| C3. Interrupt, shutdown, cancellation delivery | 4 | interrupt + bracket + the cancellation gap |
| C4. Task spawn (per-firing / companion / root) | 4 | concurrent collect + node-set programs |
| C5. Pools and permits | 3 | `bounded(n)` as resource; permanence |
| C6. Callback→stream bridge queues | 2 | external event sources (FFI nodes) |
| C7. Async pumps and collects | 3 | async collect, end-when, executor bridge |
| C8. Retry with backoff | 2 | register + timer + end-when composite |
| C9. Hand-rolled all-of join | 1 | concurrent join (already designed) |
| One-offs: scheduling discipline; lock-guarded fold | 2 | cell timing contract; serial collect |

Cross-cutting counts:

- **Sum-shaped coordination (first-of: race, timeout, interrupt,
  cancellation — C2 + C3): 9 of 30.** All-of coordination (the
  join): 1. The field weight is nine to one in favor of the
  construct the record has *not* yet given its own round.
- **Sites where "who won / has it fired" is reconstructed from side
  state** (flags, None checks, state enums) rather than delivered
  structurally: at least 6 (websockets 3, websockets 4, fastify 1,
  fastify 4, fastify 5, undici 1).
- **Sites touching cancellation, cleanup-on-abandonment, or
  retention across an abandonment**: roughly 8 of 30 (aiohttp 2,
  aiohttp 4, websockets 4, websockets 5, fastify 3, fastify 4,
  undici 1, celery 2).
- **Locks: 1 of 30.** The event loop serialises; where these
  corpora need mutual exclusion they mostly restructure (queues,
  single-consumer drains) rather than lock.

## Findings (survey 3)

### 3.1 Racing dwarfs gathering, and the design attention is inverted

Nine of thirty sites coordinate by *first-of* (race, timeout,
interrupt, cancellation); one coordinates by *all-of* (the trailer
join) — and that one is hand-rolled only because its inputs are
callbacks. The record has the concurrent join fully worked
(`async-flow-design.md`, sequential/parallel are structural) while
race owes its own semantics round (its question 5); the field weight
is the reverse of the design attention. On this evidence the race
barrier round — and the interrupt/timeout composites over it — is
the concurrency area's most demanded piece, not the concurrent
collect's species menu.

### 3.2 Hand-rolled races never get the discrimination structurally

In every sampled race or timeout, "which contender won" is
reconstructed after the fact from side state: `self.request is not
None` (websockets 3), `reply.sent` and `signal.aborted` flags
(fastify 4), a four-state enum plus an exception-type conversion
(websockets 4), started/ready booleans (fastify 5). The pairwise
input/output correspondence that the barrier form of race promises
is exactly what this code lacks and rebuilds by convention — the
strongest field support yet for "racing is a barrier, not a value,"
and for the no-bottlenecks principle behind it.

### 3.3 The deferred cell is the most-reached-for primitive

The most common single shape (C1, 4 of 30, plus appearances inside
C3/C4 sites): a promise/future created **empty** with its write half
separate, often memoised (mint once, share with every consumer),
often lazily (mint on first observation, already-resolved if the
milestone passed). Nobody was sampled using `new Promise` for its
designed eager purpose. This confirms the eager-promise-problem
analysis in `async-flow-design.md` — the write-once, memoised,
externally-written cell is the primitive; eager start is the
accident — and it puts everyday frequency behind the inventory's
lifecycle outputs: opened/closed/upload-complete milestones are what
the deferreds are minted *for*.

### 3.4 The concurrent collect's bookkeeping is real, and it bites

Both task-per-firing sightings hand-roll the lifecycle bookkeeping
the collect's barrier outputs would provide: a task set maintained
by done-callbacks (uvicorn 2), registration ordered before spawn to
dodge a startup race, documented in a four-line comment
(websockets 2). And uvicorn 5's hard-reference comment marks a
production bug class — asyncio's weakly-held tasks are
garbage-collected mid-flight when nothing references them —
which is the "program is a node set, not a root expression"
consequence (`first-class-ports-design.md`) observed as a real
incident: a complete program whose parts are unreachable from any
root. The spawn/registration/retention triple is where this code's
subtlety concentrates, not in the per-firing bodies.

### 3.5 `bounded(n)` is a resource — confirmed three ways

The addendum's reading (permits, not partitions) is what the field
shows: undici's pool is permits + a wait queue + release events;
celery's `acquire_channel(block=True)` is a permit acquisition
worn as a bracket; uvicorn's supervisor keeps a *permanent* worker
set reconciled against a desired count — the permanence theme
governing the pool from above. None of the three is remotely
partition-shaped. The species menu's dissolution (`keyed` →
group-by wiring, `serial` → unmarked default) plus these three
sightings leaves `bounded(n)`/permits as the one genuinely
resource-shaped member, now with field confirmation.

### 3.6 Cancellation is where the hardest sampled code lives

Roughly eight of thirty sites deal with cancellation, abandonment,
or retention-across-abandonment, and they contain the sample's most
delicate machinery: the timeout context manager's
state-machine-plus-uncancel dance (websockets 4), shield-await
inside a graceful shutdown's escalation ladder (aiohttp 2),
check-then-subscribe abort wiring (undici 1), weakref-broken timer
retention (aiohttp 4), cancel-both-in-finally (websockets 5). The
Tier-1 "IO, effects, and cancellation" row
(`open-problems.md`) now has frequency evidence to go with its six
documented arrivals: in concurrency-infrastructure code, roughly a
quarter of all orchestration sites touch the gap, and they are the
sites least expressible in the current vocabulary.

### 3.7 Locks are nearly absent; the boundary discipline is the queue

One lock in thirty draws (celery 4 — serialising a fold over racing
callbacks), against two callback→stream bridge queues and repeated
single-consumer drain loops. Where the loop surveys confirmed
uncollect/collect as the center of iteration, this survey confirms
the async doc's structural bet: event-loop code coordinates by
*flow* (queues, drains, single writers), not by shared-state
locking, so "serial is no construct at all — the default collect,
unmarked" matches practice. The lock that did occur is exactly a
serial collect hand-enforced.

### 3.8 Retry-with-backoff is a cross-domain composite worth an expansion test

Third and fourth sightings across the surveys (mpmath 4's geometric
escalation; websockets' reconnect; undici's Retry-After/exponential
handler): a register (delay/counter) stepped on the failure leg and
reset on success, a timer, give-up guards, and an exit payload. All
pieces are designed vocabulary (register, timer, end-when, failure
legs); none of the samples needed anything novel. This is a natural
+1-ladder test case — beginner's retry → add backoff → add jitter →
add Retry-After override → add give-up guards — for whichever
register/end-when combination lands.

### 3.9 The cell's timing contract is real discipline, not pedantry

Three sites (undici 2, undici 5's deferred drain check, fastify 1's
nextTick bounce) exist solely to guarantee that a continuation never
runs re-entrantly inside the frame that armed it — the "release
Zalgo" rule. The event-loop-cell semantics gives this by
construction (resolution is observed only via the loop), so it is a
cost the designed model pays nothing for; worth recording because it
is invisible in the design documents precisely where it is
ever-present in the field code.

## What this changes, and what it doesn't

For the **candidate-block inventory**
(`tough-use-cases-design.md`): the race barrier and its composites
(timeout, interrupt, cancellation delivery) gain everyday-frequency
demand that item 1's species menu does not show (findings 3.1–3.2);
`bounded(n)`-as-resource is confirmed (3.5); the lifecycle barrier
outputs gain both frequency (3.3) and a bug class they would
prevent (3.4). Item 2 (the served flow) was the ambient structure
around many draws — every handler body in three corpora — but no
draw contradicted or extended its design; its per-firing failure
leg was sighted in exactly the shape question 3 anticipates
(fastify 3).

For the **Tier-1 cancellation gap** (`open-problems.md`): frequency
evidence added; the gap's load-bearing status is now measured, not
only argued (finding 3.6).

For the **async flow's foundations**: the cell model (eager-promise
correction, memoised write-once cells, the timing contract) is
confirmed against field practice from three independent directions
(findings 3.3, 3.9); threads-as-drained-streams and
structural-parallelism appeared in their designed shapes
(websockets 5; fastify 1's counter is what their absence costs).

Not changed: no draw pressed on the iteration-state candidates, the
commute taxonomy, or the incremental flow — as expected from the
corpus family; and this survey, sampling sites rather than loops,
does not update the loop-shape proportions of surveys 1–2.

## Next round (updated)

- **Application-level concurrency** — these corpora *implement*
  concurrency infrastructure; a sample of applications that *use*
  it (bots, scrapers, data pipelines, deployment tools) would
  measure how often application code reaches for gather vs race vs
  pool, complementing this survey's machinery view.
- **UI/browser event-handling in JS** — still owed from survey 2.
- **Larger n / combinator census** — the census is now done (see
  "Combinator census" below); larger n as before.

---

# Combinator census

A whole-corpus count, not a thirty-item sample. Surveys 1–3 excluded
expression-level combinators (comprehensions, `map`/`filter`/`reduce`)
by construction, on the argument that they are collect-shaped and
would only inflate the "already served" bucket; survey 1's finding 1
then rested a claim on that exclusion — "in the corpora's code as a
whole, the fraction needing no state machinery is well above half" —
and flagged it as resting "on the exclusion bias's direction alone,
which is sound but unquantified." This census quantifies it. It counts
*every* statement loop and *every* combinator use across the three
survey-1 corpora and reports the ratio, so the exclusion's size stops
being a guess. It decides nothing.

## Why count, not sample

The loop surveys measured *which shapes* real loops take, at a sample
size (n = 30) that resolves "which patterns occur and dominate" but not
second-digit proportions. The exclusion-bias question is different: it
asks *how much* code was removed from view by excluding combinators —
a magnitude, one number per corpus, best answered by counting all of
it rather than sampling. So the unit here is the syntactic occurrence,
and the coverage is exhaustive.

## Protocol (census)

Same three corpora as survey 1, on this machine (paths and post-
exclusion file counts as measured here; the npm and Ruby trees match
survey 1's counts, the Python tree is the same 3.10 stdlib at a
slightly smaller install — 548 vs survey 1's stated 621, noted so the
per-file figures are read against the right denominator):

| Corpus | Path | Files |
|---|---|---|
| Python 3.10 stdlib | `/usr/lib/python3.10` (excl. `test`, `idlelib`, `lib2to3`, `__pycache__`) | 548 |
| Ruby 3.3 stdlib incl. bundled gems | `/opt/ruby-3.3.6/lib/ruby/3.3.0` | 996 |
| npm (own JS + vendored deps) | `/opt/node22/lib/node_modules/npm` (excl. `*.min.js`) | 1046 |

**What is counted.** Two populations, plus a three-way split of the
second:

- **Statement loops** — the survey-1 unit: `for`/`while`/`do`/
  `foreach`-style explicit iteration. This is the denominator the
  loop surveys already classified.
- **Combinators** — expression-level bulk operations the language's
  collect vocabulary already covers, split by what they produce:
  - **collect** (element-wise / keyed / reorder, no accumulator):
    comprehensions and generator expressions; `map`/`filter`/
    `flat_map`/`select`/`reject`/`grep`/`group_by`/`partition`/
    `tally`/`sort_by` and kin.
  - **fold** (true reduction to an accumulator): `reduce`/`inject`/
    `each_with_object`/`sum`/`min_by`/`max_by`; Python `sum(...)` and
    single-iterable `min`/`max` (scalar `min(a, b)` clamps excluded);
    JS `.reduce`/`.reduceRight`.
  - **search** (first-match / boolean short-circuit — early exit):
    `find`/`detect`/`any`/`all`/`none`/`some`/`every`/`findIndex`;
    Python `next(genexp, …)`. Grouped with search, not fold, because
    they terminate early — the split matters for reading these against
    finding 4 rather than 2.3.

**Identification.** Parser- or token-level wherever the language
allows, matching survey 2's amendment:

- **Python** — `ast`: loops are `For`/`AsyncFor`/`While`;
  comprehensions are the four comp nodes; builtin combinators are
  matched by callee name (over-counts under shadowing — direction
  stated below).
- **Ruby** — `Ripper.lex`: comments (`:on_comment`) and string
  contents (`:on_tstring_content`) are distinct token types, so prose
  never counts. Loop keywords are `:on_kw for`/`while`/`until`;
  method combinators are exact idents following a `.`/`&.`. *This
  correction matters:* a naive `\bfor\b` regex over the same tree
  reported 574 Ruby `for`s (English "for" in comments and strings);
  the token count is 64. The `.method` combinator counts were
  unaffected by the switch, which is why the surveys' regex sightings
  stand.
- **JS** — regex over comment-stripped source (survey 1's method),
  requiring the loop's `(`/`{` and excluding `.for(`-style method
  calls (e.g. `Symbol.for(`) via lookbehind; verified by reading.

## The counts

| Corpus | Stmt loops | collect | fold | search | Combinators | comb : loops |
|---|---|---|---|---|---|---|
| Python 3.10 | 3048 | 885 | 71 | 77 | 1033 | 0.34 |
| Ruby 3.3 | 3468 | 1365 | 93 | 509 | 1967 | 0.57 |
| npm JS | 1991 | 856 | 99 | 145 | 1100 | 0.55 |
| **Combined** | **8507** | **3106** | **263** | **731** | **4100** | **0.48** |

Derived:

- **Combinators are ~1/3 of all iteration constructs** (4100 of 12607
  = 32.5%); statement loops are ~2/3.
- **Combinator split: collect 76%, search 18%, fold 6%.**
- **No-state fraction of the whole population** (combinators +
  statement loops), using the loop surveys' stateless-statement-loop
  rate (32/60 ≈ 53%): collect combinators + ~half of statement loops
  ≈ **60%**; adding search/early-exit constructs (no accumulator) ≈
  **66%**.

Notable per-corpus detail: Python's combinator surface is
comprehensions (737 of its 885 collect); Ruby's iteration is blocks
(`.each` 1928) with a large search family (`.any?` 214, `.find` 204);
JS splits between C-style `for` (1515) and `.map`/`.filter` (856).

## Findings (census)

### C.1 The exclusion is real but modest — statement loops dominate, even in Ruby and JS

Finding 1's "well above half needs no state" survives, quantified as a
clear **~60% majority** in infrastructure code — but the census
corrects the natural misreading of *why*. It is not that most code is
comprehensions: combinators are a minority third, and the explicit
statement loop outnumbers the expression combinator about two to one
in every corpus, including block-idiomatic Ruby (0.57) and
`.map`-idiomatic JS (0.55). The no-state majority is carried
predominantly by *stateless statement loops*; excluding combinators
lifts the figure only about seven points (loop-level ~53% →
population-level ~60%). The exclusion bias's direction was right; its
magnitude is a nudge, not the main effect. "Well above half" is
honest for infrastructure code as "a ~60% majority," not as an
overwhelming supermajority.

### C.2 Collect dominates the combinators; fold is rare here

Three-quarters of all combinator uses are pure collect (map / filter /
comprehension) — the uncollect/collect center holds at the expression
level as it did at the loop level (survey 1, finding 1). True
accumulating folds are genuinely uncommon in this corpus family: 263
across 2590 files, ~2% of all iteration constructs. That is the same
result surveys 1–2 reached from the loop side — the scan is absent in
infrastructure, concentrated in numerics — now confirmed from the
combinator side. Read under the 80/20 counterweight: fold's rarity
ranks it as *not needing effortlessness in infrastructure code*, not
as unimportant. Survey 2 showed the ratio inverts in numerics, and the
reduce-close operator-identity question keeps its breadth weight
regardless of this count.

### C.3 Search/early-exit is prominent at the expression level too

Search combinators are 18% of all combinator uses (731), and the loop
surveys independently found ~30% of statement loops terminate early.
Both levels point the same way: data-driven termination and
first-match readout is the highest-frequency everyday gap — end-when
plus its readout composition (survey 1, finding 4), now sighted at a
second syntactic level. Ruby carries it hardest (509 search
combinators, where the language ships `.any?`/`.find`/`.detect`);
Python spells the same intent as explicit loops or `any(genexp)`, and
its membership tests (`x in c`, uncounted here) hide still more of it —
so the search share is if anything undercounted.

### C.4 The trichotomy is a property of the work, not the language

Ruby spells iteration as blocks, JS splits `for` against `.map`,
Python leans on explicit loops with comprehensions as its combinator
surface — yet the collect/fold/search decomposition holds in all three
despite the surface differences, and the collect≫search>fold ordering
is the same in each. That the split survives three different library
idioms is evidence it carves the work, not one ecosystem's method
menu — the same "carving reality at its joints" check survey 2 applied
to Cross and window.

## Biases (census), with direction

- **Same infrastructure corpora as survey 1** — parsing, IO, tooling;
  no numerics, simulation, or UI. This is where fold is undercounted:
  survey 2 showed folds concentrate in numerics, so a census over the
  survey-2 domains would raise the fold share and could move the
  no-state fraction. *Direction: undercounts fold; the ~60% figure is
  an infrastructure figure only.*
- **Uncounted collect/search forms.** Python `sorted()`, dict/set/list
  constructors over genexps, and membership `in`; JS `.sort()`; Ruby
  `.min`/`.max`/`.count`-with-block are not counted. *Direction:
  undercounts combinators — so "loops dominate 2:1" is conservative;
  the true combinator share is somewhat above 32.5%, not enough to
  overturn the loop majority.*
- **Name-based builtin detection (Python).** `map`/`filter`/`sum`/
  `any`/`all`/`reduce` matched by callee name; a shadowed local or a
  same-named method over-counts. *Direction: slight over-count of
  Python combinators* — partially offsetting the previous bias.
  Comprehensions (the bulk of Python collect) are `ast`-exact.
- **JS residual string contamination.** Comment-stripped and
  paren/brace-anchored, but a `for (` inside a string literal could
  still count; it affects numerator and denominator alike and is
  small.
- **Occurrence-weighted, not size- or runtime-weighted.** One
  syntactic occurrence = one count; nested comprehensions counted per
  node. A census of what is written, not of what runs.
- **Exhaustive, not sampled** — unlike surveys 1–3 the proportions are
  not n = 30 coarse, but they inherit the corpus-family skew above.
  Read them as "infrastructure code," not "all code."

## What this changes, and what it doesn't

For **survey 1's finding 1**: quantified. The claim holds as a ~60%
majority and is annotated in place; the previously-unquantified
"exclusion bias's direction alone" now has a magnitude (~7 points) and
a corrected reading (the majority is stateless statement loops, not
excluded combinators).

For the **foundations** (uncollect/collect as the center): reconfirmed
at the expression level (76% of combinators are pure collect),
independently of the loop-level confirmation.

For **end-when** (finding 4): reinforced — early-exit is prominent at
the combinator level as well as the loop level.

For **reduce-close and operator identities** (finding 2.3): fold's
infrastructure rarity is now measured (~2% of iteration constructs),
consistent with the scan's loop-level absence here and its numerics
concentration in survey 2; the identity question's urgency is
domain-shaped, and its *breadth* weight is unaffected by frequency
(the 80/20 rule).

Not changed: this census counts occurrences, so it does not classify
which statement loops carry state (that is the loop surveys' job) and
does not update their state/stateless proportions; the iteration-state
candidates, the commute taxonomy, and the incremental flow are
untouched.
