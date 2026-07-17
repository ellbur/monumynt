// The compile pipeline entry point (compile-strategy-design.md).
//
//   program of record (node set + outputs)
//     0. derive     — NOT PRESENT YET: no abstract node species exist. The
//                     slot is reserved; reduce-close is the planned first
//                     catalog entry (transformation-levels-design.md).
//     1. check      — Check.res (witnesses or proceed)
//     2. complete   — Complete.res (stub identity; insertions surface)
//     3. annotate   — Annotate.res (write index, species)
//     4. codegen    — Codegen.res is the target; TODAY the LegacyBridge +
//                     src/Compile.res stand in for it
//     5. print      — the existing JsPrint
//
// The pipeline returns witnesses as data (result type), never throws for
// user-level problems. Bridge-unsupported constructs DO throw (Failure) —
// they are compiler gaps, not program errors, and the test runner reports
// them as such.

type compiledOutput = {
  outputName: string,
  iife: JsAst.expr,
  js: string,
}

type compiled = {
  outputs: array<compiledOutput>,
  insertions: array<Complete.insertion>,
}

let compile = (p: Program.program): result<compiled, array<Check.witness>> => {
  let witnesses = Check.check(p)
  if Array.length(witnesses) > 0 {
    Error(witnesses)
  } else {
    let {program: committed, insertions} = Complete.complete(p)
    let _ann = Annotate.annotate(committed) // consumed by Codegen when it lands
    // --- codegen stand-in: bridge to the legacy compiler ---
    let ctx = LegacyBridge.makeCtx()
    let outputs = committed.outputs->Array.map(o => {
      let root = LegacyBridge.outputRoot(ctx, committed, o.name)
      let iife = Compile.compileToIIFE(root.node)
      {outputName: o.name, iife, js: JsPrint.printExpr(iife)}
    })
    Ok({outputs, insertions})
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
