// The async flow, the race barrier, and the settle node — ARCHITECTURE
// STUB. Nothing here runs; this plans the shapes so they can be filled in
// later. Runtime dependency order (recorded identically in four docs):
// streams (Stream.res) -> async cells -> async streams / race / settle.
//
// Design: plans/async-flow-design.md, plans/race-barrier-design.md,
// plans/concurrent-collect-design.md, plans/cancellation-design.md — all
// EXPLORATION (not adopted), except where barrier-value-crossing-design.md
// adopted a corner (2026-07-23): race's pairs-in shape is ADOPTED, and with
// it "await = open async" (the async uncollect is the opener; the N=1 race
// is the degenerate transport, NOT the way to spell await).
//
// Integration points:
//   - Program.res: `flowKind` gains `| Async` ("exactly one, but later" —
//     opens like an option except the guard is time: NO discriminator
//     field, NO zero-iterations case). An async STREAM is not a new kind —
//     it is the stream kind with the async cell in the Delayed position;
//     placement/chain analysis unchanged.
//   - Program.res kinds: Race and Settle nodes (below).
//   - Annotate.res: async-cell species.
//   - Runtime.res: the async cell (below), then the frontier's strand event
//     (the ONE genuinely new runtime piece cancellation needs).
//   - Main.res: the eval/JSON.stringify harness is synchronous; async tests
//     need an awaited runner variant (implementation-strategy.md,
//     "Test-runner asynchrony").

// --- The terminator vocabulary --------------------------------------------
//
// A failable flow kind is a flow kind whose TERMINATOR CARRIES A PAYLOAD —
// one dimension, not per-kind features (async-flow-design.md, "Failure as
// terminator payload"). Tags in circulation across the rounds; payload
// shapes ride the lanes (Fail.res owns the derived inventory).
type terminatorTag =
  | TermNil // the bare end
  | TermRanOut // a pull source exhausted (source-openers-design.md)
  | TermFail // a fail node / failable catalog row; payload = the error
  | TermStopped // an end-when's cut; payload = the stop firing's value
  | TermInterrupted // an interrupt; payload = the event
  | TermCancelled // strand delivery — the one non-drawn minting site; NO
  // payload by construction (its mint has no input wire)

// --- Runtime: the async cell ----------------------------------------------
//
// Two states suffice where the synchronous Delayed needed three — the
// promise itself supplies the third (in-flight vs resolved):
//
//   const __asyncCell__ = (t) => ({p: null, t});
//   const __startAsync__ = (z) => {
//     if (z.p === null) { z.p = z.t(); z.t = null; } return z.p;
//   };
//
// START IS SYNCHRONOUS: forcing an async cell creates the promise and
// returns immediately; only awaiting yields to the event loop. This is what
// makes concurrent-join compile to start-all-then-await-all, and what the
// settle node's law leans on. Corollary: abandonment is not cancellation —
// a started promise cannot be unstarted. Concurrent forcers share the one
// stored promise, so per-cell work runs at most once regardless of fan-out.

let asyncPreludeStmts: unit => array<JsAst.stmt> = () =>
  failwith("stub: __asyncCell__/__startAsync__ prelude — async-flow-design.md, 'the cell that fixes it'")

// --- The async uncollect/collect ------------------------------------------
//
// Uncollect ports mirror the option opener's: value "element" (the resolved
// value), flow "flow" (the async context). A collect over an async flow
// packages the body's result back up as an async — one async cell whose
// thunk is an `async` arrow containing the body, awaits where async opens'
// value ports are read. The eager-semantics discipline is entirely about
// CREATION points, not about avoiding async/await syntax.

type plannedFlowKind = AsyncKind

let emitAsyncCollect: Program.node => array<JsAst.stmt> = _collect =>
  failwith("stub: async collect emitter — async-flow-design.md, 'Compile'")

// --- The race barrier (pairs-in ADOPTED, 2026-07-23) ----------------------
//
// N-ary sum barrier, N >= 1, arity is STRUCTURE (race(a, race(b,c)) and
// race(a,b,c) are different programs; flattening is a candidate level-1
// recognition, never silent). One node, no Branch-style satellites:
//
//   inputs:  per contender, a (flow, payload) PAIR — "a barrier is a
//            control-flow operation and must consume something that stands
//            for the control flow." A bare async value is admissible as the
//            completed-open aggregate.
//   outputs: per contender CELL, a (value, flow) pair — cell i fires iff
//            contender i won, carrying i's resolved value as its mint.
//            (Race is the partial collect's async sibling: cells partition
//            the parent by first settlement.)
//
// The law: forcing any collect over the bundle starts all N contenders
// synchronously, IN DRAWN ORDER, before the first await; first settlement
// wins (including a rejection — no extra ports for failure); among
// contenders already settled when the race starts, the LOWEST-NUMBERED wins
// (drawn order is the tie-break — free at compile: Promise.race resolves
// with the first already-settled promise in argument order). Exactly one
// cell fires; losers are NOT cancelled — they run to completion into their
// memoised cells (the lost cell is the cancellation TRIGGER; race needs no
// new ports for cancellation).
//
// Collects over the bundle: covering -> async<Y>; subset partial collect ->
// failable by construction, payload the BARE settled-elsewhere fact (lane
// integrity), not the winning value.
//
// Merge / interrupt / timeout are DERIVED vocabulary: merge and interrupt
// are catalog blocks with derived corecursive lowerings (not primitives,
// not idioms — nobody authors the recursion, everybody can read it on
// drop-down); timeout is not a construct at all (race/interrupt against a
// timer, deadline scope expressed by where the timer node is minted).
//
// Provenance: race is one uncollect step in the context path — async kind,
// bundle of N cells, the same step shape a case split writes, with time as
// the discriminator. So the representation belongs NEXT TO Uncollect(Case),
// not as a foreign construct.

// Inline records keep the field names scoped (house Warning-30 discipline).
type plannedRace =
  | Race({contenders: array<(Program.flowRef, Program.valueRef)>})

// The one new check the pair form brings: the payload must descend from the
// flow wire's context (`-~>` guarantees it; the explicit form gets a
// provenance check).
let checkRacePairCoherence: Program.program => array<Check.witness> = _p =>
  failwith("stub: race pair coherence — barrier-value-crossing-design.md, corner 2")

// --- The settle node (concurrent collect) ---------------------------------
//
// plans/concurrent-collect-design.md — EXPLORATION; "settle" is a
// placeholder name (its own open q.8). NOT a collect: a binary flow
// operation in the family of end-when / interrupt / paced — the walk's own
// data reshaping the walk:
//
//   inputs:  subject flow ~S + a per-firing ASYNC VALUE (the body) computed
//            in the walk.
//   outputs: the COMPLETIONS FLOW ~C — one firing per subject firing whose
//            body settles, AT its settlement, IN settlement order — plus
//            one settled-sum value per completion firing
//            (Ok(x) | Fail(e) | Cancelled: a body that fails is a
//            completion CARRYING the failure — the supervisor consumes
//            failures, it doesn't die of them). The two outputs co-locate
//            by the criterion: the value is the firing's content.
//
// The completions flow IS an async stream — no new flow-kind row. Firing N
// of the subject demands the body's construction and START, not its
// settlement (start is synchronous), so bodies overlap as far as demand and
// source allow. Drain law: completions terminates when the subject has
// terminated AND every started body has settled; the subject's failure
// terminator propagates after the drain.
//
// A PRIMITIVE, not a catalog block: its lowering would have to carry the
// in-flight set (runtime-many cells — not a drawable partition). Compiled
// form is the callback->stream bridge: settlements enqueue, the stream is
// the queue's pull side. First-of-a-dynamic-set is the HEAD of the
// completions flow, not a race.
type plannedSettle =
  | Settle({subject: Program.flowRef, body: Program.valueRef})

// Structural check: a Delay whose flow feeds a settle node's body operand is
// ill-formed (registers across bodies belong on the completions flow — see
// also OrderDemand.res: the sever->settle interior owns no order).
let checkSettleRegisters: Program.program => array<Check.witness> = _p =>
  failwith("stub: no register inside the sever->settle interior — concurrent-collect-design.md")

// --- Pacing (source-openers rider) ----------------------------------------
//
// paced(F, g): flow in + a per-firing async value g computed in the walk;
// delayed flow out. Firing n of the output is firing n of F; firing n+1 of
// F is demanded only after g at firing n settles; the FIRST firing is
// ungated; g's value is DISCARDED — only settlement is observed. Strictly
// more expressive than a fused pace port (applies to sourced flows too);
// the gate must be minted per firing (ordinary provenance, not a new rule).
// Open: the operand sort (async value vs once-per-firing flow); per-consumer
// vs per-source pacing under multi-close.
type plannedPaced =
  | Paced({subject: Program.flowRef, gate: Program.valueRef})

// --- Cancellation (exploration; the type-shaped part only) ----------------
//
// plans/cancellation-design.md. No cancel token in the vocabulary — settled
// rejections: a user-facing cancel capability wire; task.cancel(); delivery
// on the Fail lane; bracket as a drawn region; preemptive delivery.
// Cancelling is DELIVERED: the runtime writes TermCancelled to in-flight
// work stranded by ceased demand, at yield points (pull and await
// boundaries; handle ops are atomic), over the same necessity frontier the
// incremental flow uses. Liveness, memory, and cancellation are ONE
// frontier; the only new runtime piece is the frontier's strand event.
//
// Bracket = the lifecycle segment plus a LATE-WIRED release half on the
// acquiring node — the same two-phase shape as the register's write half
// (DelayWrite is the representational precedent):
//
//   Acquire — the segment's top vertex, minting the handle, failable; where
//     the vertex sits is the granularity (under a firing = per-firing;
//     outside the loop = per-walk).
//   Release — a late-wired body on the acquire ("release of", spelling
//     provisional). The law: every acquired handle reaches exactly one
//     release, which runs on WHICHEVER way the segment ends (normal /
//     failure / Cancelled). The body consumes the handle as of the last
//     completed op, and the terminator (ignore it = defer; split on it =
//     errdefer). Release CANNOT FAIL — structurally, no lane left to fail
//     into; anything to report is data on its completion cell. Release is
//     not cancellable — the one place execution is not consumer-demanded.
type plannedRelease =
  | ReleaseHalf({acquire: Program.node, body: Program.valueRef})
