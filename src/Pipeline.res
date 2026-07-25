// The compile pipeline entry point (compile-strategy-design.md).
//
//   program of record (node set + outputs)
//     0. derive     — Derive.res (v0 identity; no abstract species yet)
//     1. check      — Check.res (witnesses or proceed)
//     2. complete   — Complete.res (harvest/solve/realise; v0 trivial)
//     3. annotate   — Annotate.res (write index, species)
//     4. codegen    — Codegen.res
//     5. print      — the existing JsPrint
//
// The pipeline returns witnesses as data (result type), never throws for
// user-level problems. A missing emitter DOES throw (Codegen.Todo) — that is a
// compiler gap, not a program error, and the test runner reports it as such.

type compiledOutput = {
  outputName: string,
  iife: JsAst.expr,
  js: string,
}

type compiled = {
  outputs: array<compiledOutput>,
  insertions: array<Complete.insertion>,
}

// Passes 0-2. Error = the program's own witnesses.
//
// Complete runs BEFORE Check, and Check validates the COMPLETED program.
// Completion commits an under-determined program (inserting a Cross for a
// sibling-opens combine, product-flows-design.md's "smallest first step" 3);
// checking the committed form is what lets that combine pass — the inserted
// Cross gives it a product home. Completion is identity for already-committed
// programs, so every other witness (bundle mixing, dependent nesting,
// coverage, flow-borne, invariance) is reported exactly as before; only the
// genuinely completable time-travel gap now compiles instead of witnessing.
// (Completion harvests its own demands rather than reading Check's — the two
// keep distinct outputs, compile-strategy-design.md open question 6.)
let frontHalf = (p: Program.program): result<Complete.completed, array<Check.witness>> => {
  let core = Derive.derive(p)
  let completed = Complete.complete(core)
  let witnesses = Check.check(completed.program)
  if Array.length(witnesses) > 0 {
    Error(witnesses)
  } else {
    Ok(completed)
  }
}

let codegenOutputs = (ann: Annotate.annotations, committed: Program.program): array<
  compiledOutput,
> => {
  let g = Codegen.codegen(ann, committed)
  // One module's statements, wrapped per output for the eval harness: each
  // IIFE carries all statements (unused lazies never run) and returns its
  // own forced output. Real packaging — one module scope, several exports —
  // is compile-strategy-design.md open question 3.
  g.outputs->Array.map(((name, valueExpr)) => {
    let body = Array.concat(g.stmts, [JsBuild.ret(valueExpr)])
    let iife = JsBuild.call(JsBuild.arrow([], body), [])
    {outputName: name, iife, js: JsPrint.printExpr(iife)}
  })
}

// Compile a program. Returns witnesses as data; raises Codegen.Todo when an
// emitter is not yet written (a compiler gap, not a program error).
let compile = (p: Program.program): result<compiled, array<Check.witness>> =>
  switch frontHalf(p) {
  | Error(ws) => Error(ws)
  | Ok({program: committed, insertions}) => {
      let ann = Annotate.annotate(committed)
      Ok({outputs: codegenOutputs(ann, committed), insertions})
    }
  }

// The COMPLETION LENS: the program as text with everything completion inserted
// rendered faint — a leading `+` (time-travel-programs-design.md, "Safety: the
// completion is a lens"; textual-representation-design.md, "the printer renders
// the derived insertions as `+` lines"). Derive + complete only; no checking, so
// a program that will not compile can still be *seen* with its inferred
// structure. The lens is re-derived, never stored: parse discards `+` lines, so
// reparsing this text gives back the authored program.
let completionText = (p: Program.program): string => {
  let completed = Complete.complete(Derive.derive(p))
  TextPrint.print(
    ~inserted=completed.insertions->Array.flatMap(i => i.insertedNodeIds),
    completed.program,
  )
}

// Convenience for the single-output case.
let compileOne = (p: Program.program): result<compiledOutput, array<Check.witness>> =>
  switch compile(p) {
  | Error(w) => Error(w)
  | Ok({outputs}) =>
    switch outputs[0] {
    | Some(o) if Array.length(outputs) === 1 => Ok(o)
    | _ =>
      failwith(
        "Pipeline.compileOne: program has " ++
        Int.toString(Array.length(outputs)) ++ " outputs; use compile",
      )
    }
  }
