// The compile pipeline entry point (compile-strategy-design.md).
//
//   program of record (node set + outputs)
//     0. derive     — Derive.res (v0 identity; no abstract species yet)
//     1. check      — Check.res (witnesses or proceed)
//     2. complete   — Complete.res (harvest/solve/realise; v0 trivial)
//     3. annotate   — Annotate.res (write index, species)
//     4. codegen    — TWO ENGINES, see below
//     5. print      — the existing JsPrint
//
// The two engines, and the migration harness they form:
//
//   - NextCodegen (Codegen.res) — the rebuild. Emitters land one at a
//     time; an unimplemented one raises Codegen.Todo.
//   - Bridge (LegacyBridge.res -> src/Compile.res) — the disposable
//     stand-in, compiling one legacy IIFE per output.
//
//   `compile` tries NextCodegen and falls back to the Bridge on Todo, so
//   every program compiles by the best engine available today and tests
//   switch engines silently as emitters land. `codegenGap` reports which
//   missing emitter caused a fallback — the successor's to-do signal.
//   `compileVia` forces one engine; NextMain's differential check uses it
//   to prove both engines agree wherever both can compile (the legacy
//   suite is the rebuild's spec). When Codegen.Todo can no longer be
//   raised, the Bridge, the legacy modules, and this fallback all retire.
//
// The pipeline returns witnesses as data (result type), never throws for
// user-level problems. Engine gaps DO throw out of `compileVia`
// (Codegen.Todo / Failure from the bridge) — they are compiler gaps, not
// program errors, and the test runner reports them as such.

type engine = NextCodegen | Bridge

type compiledOutput = {
  outputName: string,
  iife: JsAst.expr,
  js: string,
  engine: engine,
}

type compiled = {
  outputs: array<compiledOutput>,
  insertions: array<Complete.insertion>,
  // Some(msg) when NextCodegen raised Todo and the Bridge stood in.
  codegenGap: option<string>,
}

// Passes 0-2, shared by both engines. Error = the program's own witnesses.
let frontHalf = (p: Program.program): result<Complete.completed, array<Check.witness>> => {
  let core = Derive.derive(p)
  let witnesses = Check.check(core)
  if Array.length(witnesses) > 0 {
    Error(witnesses)
  } else {
    Ok(Complete.complete(core))
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
    {outputName: name, iife, js: JsPrint.printExpr(iife), engine: NextCodegen}
  })
}

let bridgeOutputs = (committed: Program.program): array<compiledOutput> => {
  // One shared translation ctx so legacy node identity mirrors new node
  // identity; still one independent legacy compile (and IIFE) per output.
  let ctx = LegacyBridge.makeCtx()
  committed.outputs->Array.map(o => {
    let root = LegacyBridge.outputRoot(ctx, committed, o.name)
    let iife = Compile.compileToIIFE(root.node)
    {outputName: o.name, iife, js: JsPrint.printExpr(iife), engine: Bridge}
  })
}

// Force a specific engine. Raises Codegen.Todo (NextCodegen) or Failure
// (Bridge) when that engine cannot compile the program — compiler gaps,
// not program errors.
let compileVia = (eng: engine, p: Program.program): result<compiled, array<Check.witness>> =>
  switch frontHalf(p) {
  | Error(ws) => Error(ws)
  | Ok({program: committed, insertions}) => {
      let ann = Annotate.annotate(committed)
      let outputs = switch eng {
      | NextCodegen => codegenOutputs(ann, committed)
      | Bridge => bridgeOutputs(committed)
      }
      Ok({outputs, insertions, codegenGap: None})
    }
  }

// The default: the rebuild where it reaches, the bridge where it doesn't.
let compile = (p: Program.program): result<compiled, array<Check.witness>> =>
  switch frontHalf(p) {
  | Error(ws) => Error(ws)
  | Ok({program: committed, insertions}) => {
      let ann = Annotate.annotate(committed)
      switch codegenOutputs(ann, committed) {
      | outputs => Ok({outputs, insertions, codegenGap: None})
      | exception Codegen.Todo(gap) =>
        Ok({outputs: bridgeOutputs(committed), insertions, codegenGap: Some(gap)})
      }
    }
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
