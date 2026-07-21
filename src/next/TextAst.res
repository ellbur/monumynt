// Surface AST for the textual representation
// (plans/textual-representation-design.md).
//
// Architecture of the text pipeline — TextAst is the meeting point:
//
//   text --TextLex--> tokens --TextParse--> TextAst statements
//        --TextResolve--> Program.program        (parse direction)
//
//   Program.program --TextPrint--> text          (print direction; TextPrint
//                                                 currently renders directly,
//                                                 growing a layout stage
//                                                 through TextAst later)
//
// The split matters: TextParse owns only what is lexically decidable
// (statement shape, sort discipline via sigils/arrows). TextResolve owns
// reference resolution — names, taps, the implicit flow stack — and mints
// nodes through Build. Pronouns desugar in resolve (P8): the representation
// never contains a tap or an anaphor. All checks beyond that stay in
// Check.res, shared with every authoring path: a file can parse and still
// be ill-formed, necessarily, since printing ill-formed programs is a
// requirement.
//
// v0 grammar (the subset TextParse currently accepts — see
// ARCHITECTURE.md for the growth path; the full notation is in the design
// doc):
//
//   file        := line*                          -- '--' comments to EOL
//   statement   := leafDef | outDecl | chain | laneCollect
//   leafDef     := NAME '=' leafTerm
//   leafTerm    := NUMBER | STRING | 'js' STRING | '[' leafTerm,* ']'
//   outDecl     := 'out' NAME ('=' NAME)?
//   chain       := sources? (arrow tap* stage)* naming?
//   sources     := source (',' source)* | tap+    -- leading '|'s resume taps
//   source      := term | '~' flowName
//   term        := primary | term OP term          -- infix; OP in * / % + -
//   primary     := applied | leafTerm | '-' NUMBER
//   applied     := (NAME | NAME '.' NAME) ('(' term,* ')')*  -- prefix application
//   flowName    := NAME ('.' NAME)?
//   arrow       := '->' | '~>' | '-~>'
//   tap         := '|'
//   laneCollect := lane+ '-~>' 'collect' '=>' binder (',' binder)*
//   lane        := '~' flowName ':' term            -- one per covered alt
//   stage       := 'open' ('list'|'option') ('in' '~' flowName)?
//               | 'split' term 'of' NAME (',' NAME)*
//               | 'collect' ('~' flowName)?
//               | 'join' ('into' '~' flowName)?
//               | 'commute'
//               | 'delay' 'init' term
//               | 'step' 'of' NAME
//               | OP primary                      -- operator section (`-> * 2`)
//               | NAME ('(' term,* ')')?          -- application
//   naming      := '=>' binder (',' binder)*
//   binder      := NAME | '~' NAME
//
// Infix operators (OP: * / % + -, standard precedence, left-associative) are
// accepted input per the design doc's permissive grammar; they desugar to App
// of the operator's JS extern (a + b => App((a,b)=>a+b, [a, b])). In chain
// position an operator is a section on the running topic (-> * 2 is topic*2).
// The canonical printer does not yet re-emit infix (design open question 5),
// so a round-trip prints the desugared App form.
//
// A physical line starting with an arrow or '=>' continues the previous
// statement; a line starting with '|' begins a new chain sourced from the
// antecedent line's taps (ordinal binding). A line starting with '~flow:'
// begins a lane group (the flow-ref-labeled form). Not yet parsed (printer
// may still emit them): fused lane groups, 'commute out of' / 'cross with'
// standalone forms, '+' completion lines (recognised and skipped — they are
// derived, never stored), '~'/'~^' anaphora, ';' multi-resume, 'diagram
// ... end' wrappers, '@id' suffixes.

type rec term =
  | TNum(float)
  | TStr(string)
  | TArr(array<term>) // literal array of leaf terms
  | TJs(string) // js "..." extern
  | TName(string)
  | TProj(string, string) // cs.Just — value port projection
  // Infix binary operator (a + b, x * 2): sugar for an App of the operator's
  // JS function to the two operands (textual-representation-design.md, "the
  // grammar is permissive"). The middle field is the operator symbol; the
  // resolver maps it to the extern. Not a literal — leafToJs rejects it.
  | TBinop(term, string, term)
  // Prefix application `f(x, y)`: the fn term applied to the arg terms. Sugar
  // for an App node, exactly as the postfix stage `x, y -> f` builds — the
  // design's permissive grammar accepts both, one reading
  // (textual-representation-design.md, "parse accepts prefix (`f(x, y)`)").
  // Not a literal — leafToJs rejects it. The canonical printer emits the
  // postfix form, so a round-trip prints `x, y -> f` (App-node wiring is
  // identical either way).
  | TApp(term, array<term>)

// A flow reference after its '~' sigil: ~L or ~cs.Just.
type flowTerm =
  | FName(string)
  | FProj(string, string)

type source =
  | SrcTerm(term)
  | SrcFlow(flowTerm)
  | SrcTap // one leading '|'; ordinal position = index among the line's taps

type arrow =
  | AValue // ->
  | AFlow // ~>
  | AValueFlow // -~>

type stage =
  | StApp({fn: term, extraArgs: array<term>})
  | StUncollect({kindWord: string, nesting: option<flowTerm>}) // "list" | "option"
  | StSplit({disc: term, alts: array<string>})
  | StCollect({flowArg: option<flowTerm>})
  | StJoin({into: option<flowTerm>})
  | StCross({with_: flowTerm}) // ~left ~> cross with ~right => ~flow
  | StCommute
  | StDelay({init: term})
  | StStepOf(string) // step of <register binder>
  | StTap // '|' mid-chain: mint a junction here
  // Chain-position infix operator (`-> * 2`): the running topic is the left
  // operand, `rhs` the right — an operator section applied to the chain value
  // (like `(* 2)`). Resolves to App(opFn, [topic, rhs]).
  | StBinop({op: string, rhs: term})

type binder =
  | BValue(string)
  | BFlow(string)

type statement =
  | LeafDef({name: string, term: term})
  | OutDecl({name: string, from: option<string>})
  | Chain({
      sources: array<source>,
      stages: array<(arrow, stage)>,
      binders: array<binder>,
    })
  // A lane group gathered by a postfix collect (a case collect, full or
  // partial): one `~flow: value` line per covered alt, then a `-~> collect =>
  // binder` terminator. The binders are a value binder for the result plus,
  // for a partial collect, a `~flow` binder for the merged remainder.
  | LaneCollect({
      lanes: array<(flowTerm, term)>,
      binders: array<binder>,
    })
