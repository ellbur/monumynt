# Real-Loop Survey: Random Loops Against the Block Inventory

> **Status update (2026-07-09, later the same day).** This document
> now holds **two** surveys. Survey 1 (below, unchanged): thirty loops
> from infrastructure corpora (Python/Ruby stdlib, npm's JS). Survey 2
> ("Survey 2: the missing domains", appended): thirty loops from six
> domain corpora targeting survey 1's stated gap — numerics,
> algorithms, simulation, UI/event handling, games, graphics. The
> single most consequential correction: **the scan occurred in survey
> 2, concentrated exactly where survey 1 predicted** (numerics), so
> survey 1's "scan absent" finding is now confirmed as corpus skew,
> not a fact about real code. The combined picture is at the end.
>
> **How to read the tallies.** Frequency is not importance (the 80/20
> counterweight — "Reading the frequencies", near the end, now also a
> standing rule of the method): high frequency ranks what must be
> effortless; a shape drawn once is a breadth obligation, not a
> deprioritization candidate. The singleton hard draws are collected
> there as **the breadth set** — nine loops the language must handle
> without too much pain.

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
>
> **Adopted as a standing method (2026-07-09).** On review of this
> first run, sampling reality this way was adopted as a recurring
> practice, to be used frequently — not a one-off. The method's
> statement, its rules (seeded, unfiltered, biases stated, evidence
> separated from decision), and when to reach for it live in
> `language-design-philosophy.md`, "A standing method: sample
> reality." Future surveys should reuse the protocol shape below,
> varying the corpus or the unit sampled, and extend this record
> rather than replace it.

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

*(2026-07-09, later: survey 2 sampled the missing domains and the
scan occurred immediately and repeatedly in the numerics corpus —
see survey 2, finding 2.1. This finding's caveat paragraph was right:
it was corpus skew. The finding stands for infrastructure code
specifically.)*

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
  flip. *(Done, same day — "Survey 2" below. It flipped, exactly as
  anticipated: the scan lives in numerics.)*
- **Larger n** if any proportion needs to be load-bearing rather than
  indicative.
- **A combinator census** (comprehensions, map/filter/reduce counts per
  file) if the "well above half needs no state" claim in finding 1 is
  ever worth firming up; the current statement rests on the exclusion
  bias's direction alone, which is sound but unquantified.

---

# Survey 2: the missing domains

*(2026-07-09, later the same day. Thirty more loops, six domain
corpora chosen to fill survey 1's stated gap. Same method; protocol
amendments below.)*

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

*(Recorded position, 2026-07-09, on review of both surveys. Now also
a standing rule of the method — `language-design-philosophy.md`, "A
standing method: sample reality".)*

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
   jointly.
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
the frequency tables say about scans and searches.

*(Companion criterion, adopted the same day as the seventh principle —
"Building blocks must build", `language-design-philosophy.md`: each
breadth-set member is also an **expansion test**, not just an
expressibility test. The question is not only "can this be written
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
  frequency treatment items 4–5 got here.
- **Larger n / combinator census**: as before.
