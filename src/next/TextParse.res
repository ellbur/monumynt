// Parser: tokens -> TextAst statements. Recursive descent over the token
// array. Owns only what is lexically decidable (sort discipline, statement
// shape); resolution happens in TextResolve.
//
// Grammar coverage and continuation rules: see the header of TextAst.res.
// Deliberate v0 rejections carry pointed messages so playing with the
// notation tells you which construct is missing, not just "syntax error".
//
// Note: token comparisons use `==` (structural) — `===` on payload-carrying
// variants compares allocations.

open TextAst
open TextLex

exception ParseError({message: string, line: int})

type p = {toks: array<positioned>, mutable pos: int}

let peek = (st: p): token =>
  switch st.toks[st.pos] {
  | Some({tok}) => tok
  | None => TokEof
  }

let peek2 = (st: p): token =>
  switch st.toks[st.pos + 1] {
  | Some({tok}) => tok
  | None => TokEof
  }

let lineAt = (st: p): int =>
  switch st.toks[st.pos] {
  | Some({line}) => line
  | None => 0
  }

let advance = (st: p): unit => st.pos = st.pos + 1

let fail = (st: p, msg: string) => throw(ParseError({message: msg, line: lineAt(st)}))

let expect = (st: p, t: token, what: string): unit =>
  if peek(st) == t {
    advance(st)
  } else {
    fail(st, "expected " ++ what ++ ", found " ++ tokenToString(peek(st)))
  }

let expectName = (st: p, what: string): string =>
  switch peek(st) {
  | TokName(s) => {
      advance(st)
      s
    }
  | other => fail(st, "expected " ++ what ++ ", found " ++ tokenToString(other))
  }

let peekIsKeyword = (st: p, kw: string): bool =>
  switch peek(st) {
  | TokName(s) => s === kw
  | _ => false
  }

let skipNewlines = (st: p): unit =>
  while peek(st) == TokNewline {
    advance(st)
  }

// --- terms ------------------------------------------------------------------

// Infix operators, as (symbol, precedence). Higher precedence binds tighter;
// all left-associative. `+` doubles as the completion-line prefix, but only at
// statement start (parseStatement), never mid-term, so it is unambiguous here.
let opInfo = (t: token): option<(string, int)> =>
  switch t {
  | TokStar => Some(("*", 2))
  | TokSlash => Some(("/", 2))
  | TokPercent => Some(("%", 2))
  | TokPlus => Some(("+", 1))
  | TokMinus => Some(("-", 1))
  | _ => None
  }

let rec parsePrimary = (st: p): term =>
  switch peek(st) {
  | TokNum(f) => {
      advance(st)
      TNum(f)
    }
  | TokMinus =>
    // A leading '-' folds into a negative number literal. Unary negation of a
    // non-literal is not supported yet (write `0 - x`); the design's infix is
    // about value leaves, and no current program needs general unary minus.
    switch peek2(st) {
    | TokNum(f) => {
        advance(st)
        advance(st)
        TNum(-.f)
      }
    | other =>
      fail(st, "unary '-' is only supported on number literals, found " ++ tokenToString(other))
    }
  | TokStr(s) => {
      advance(st)
      TStr(s)
    }
  | TokLBracket => {
      advance(st)
      let elems: array<term> = []
      if peek(st) != TokRBracket {
        Array.push(elems, parsePrimary(st))
        while peek(st) == TokComma {
          advance(st)
          Array.push(elems, parsePrimary(st))
        }
      }
      expect(st, TokRBracket, "']'")
      TArr(elems)
    }
  | TokName("js") =>
    switch peek2(st) {
    | TokStr(code) => {
        advance(st)
        advance(st)
        TJs(code)
      }
    | _ => parseNameTerm(st)
    }
  | TokName(_) => parseNameTerm(st)
  | other => fail(st, "expected a term, found " ++ tokenToString(other))
  }

and parseNameTerm = (st: p): term => {
  let name = expectName(st, "a name")
  if peek(st) == TokDot {
    advance(st)
    let port = expectName(st, "a port name after '.'")
    TProj(name, port)
  } else {
    TName(name)
  }
}

// A full value term: primaries joined by infix operators, precedence-climbed.
// Operators never span an arrow (arrows are separate tokens), so a term parse
// stops cleanly at the chain's next stage.
let rec parseBinop = (st: p, minPrec: int): term => {
  let left = ref(parsePrimary(st))
  let continue = ref(true)
  while continue.contents {
    switch opInfo(peek(st)) {
    | Some((sym, prec)) if prec >= minPrec => {
        advance(st)
        let right = parseBinop(st, prec + 1)
        left := TBinop(left.contents, sym, right)
      }
    | _ => continue := false
    }
  }
  left.contents
}

let parseTerm = (st: p): term => parseBinop(st, 1)

let parseFlowTerm = (st: p): flowTerm => {
  // caller has consumed the '~'
  let name = expectName(st, "a flow name after '~'")
  if peek(st) == TokDot {
    advance(st)
    let port = expectName(st, "a port name after '.'")
    FProj(name, port)
  } else {
    FName(name)
  }
}

let expectTildeFlowTerm = (st: p, what: string): flowTerm => {
  expect(st, TokTilde, "'~' introducing " ++ what)
  parseFlowTerm(st)
}

// --- stages -----------------------------------------------------------------

let parseStage = (st: p): stage =>
  switch peek(st) {
  | TokName("open") => {
      advance(st)
      let kindWord = expectName(st, "a flow kind after 'open'")
      switch kindWord {
      | "list" | "option" => ()
      | other =>
        fail(
          st,
          "unknown flow kind '" ++
          other ++ "' (v0 knows list and option; stream/async/var arrive with their runtime layers)",
        )
      }
      let nesting = if peekIsKeyword(st, "in") {
        advance(st)
        Some(expectTildeFlowTerm(st, "the outer flow of 'in'"))
      } else {
        None
      }
      StUncollect({kindWord, nesting})
    }
  | TokName("split") => {
      advance(st)
      let disc = parseTerm(st)
      expect(st, TokName("of"), "'of' after the split discriminator")
      let alts: array<string> = [expectName(st, "an alt name")]
      while peek(st) == TokComma {
        advance(st)
        Array.push(alts, expectName(st, "an alt name"))
      }
      StSplit({disc, alts})
    }
  | TokName("collect") => {
      advance(st)
      let flowArg = if peek(st) == TokTilde {
        advance(st)
        Some(parseFlowTerm(st))
      } else {
        None
      }
      StCollect({flowArg: flowArg})
    }
  | TokName("join") => {
      advance(st)
      let into = if peekIsKeyword(st, "into") {
        advance(st)
        Some(expectTildeFlowTerm(st, "the outer flow of 'into'"))
      } else {
        None
      }
      StJoin({into: into})
    }
  | TokName("cross") => {
      advance(st)
      // Standalone product form: ~left ~> cross with ~right => ~flow. The
      // chain's flow source is the left axis; `with ~right` is the other.
      expect(st, TokName("with"), "'with' after 'cross'")
      let right = expectTildeFlowTerm(st, "the other flow of 'cross with'")
      StCross({with_: right})
    }
  | TokName("commute") => {
      advance(st)
      StCommute
    }
  | TokName("delay") => {
      advance(st)
      expect(st, TokName("init"), "'init' after 'delay'")
      StDelay({init: parseTerm(st)})
    }
  | TokName("step") => {
      advance(st)
      expect(st, TokName("of"), "'of' after 'step'")
      StStepOf(expectName(st, "a register name"))
    }
  | tok if opInfo(tok) != None => {
      // operator section: `-> * 2` applies the operator to the running topic
      // (left) and this single operand (right). Chain more stages for more
      // operations (`-> * 2 -> + 1`); the right operand is a primary, so
      // precedence never crosses a stage boundary.
      let op = switch opInfo(tok) {
      | Some((sym, _)) => sym
      | None => fail(st, "not an operator")
      }
      advance(st)
      StBinop({op, rhs: parsePrimary(st)})
    }
  | TokName(_) => {
      // application stage: NAME or NAME(extraArgs)
      let fn = parseNameTerm(st)
      let extraArgs: array<term> = []
      if peek(st) == TokLParen {
        advance(st)
        if peek(st) != TokRParen {
          Array.push(extraArgs, parseTerm(st))
          while peek(st) == TokComma {
            advance(st)
            Array.push(extraArgs, parseTerm(st))
          }
        }
        expect(st, TokRParen, "')'")
      }
      StApp({fn, extraArgs})
    }
  | other => fail(st, "expected a stage, found " ++ tokenToString(other))
  }

// --- statements ---------------------------------------------------------------

let parseBinders = (st: p): array<binder> => {
  // caller consumed '=>'
  let one = (): binder =>
    if peek(st) == TokTilde {
      advance(st)
      BFlow(expectName(st, "a flow binder name"))
    } else {
      BValue(expectName(st, "a binder name"))
    }
  let binders = [one()]
  while peek(st) == TokComma {
    advance(st)
    Array.push(binders, one())
  }
  binders
}

// Parse the tail of a chain (stages and naming), given sources. A physical
// line starting with an arrow or '=>' continues the chain.
let parseChainTail = (st: p, sources: array<source>): statement => {
  let stages: array<(arrow, stage)> = []
  let binders: array<binder> = []
  let continue = ref(true)
  while continue.contents {
    switch peek(st) {
    | TokArrowV | TokArrowF | TokArrowVF => {
        let arrow = switch peek(st) {
        | TokArrowV => AValue
        | TokArrowF => AFlow
        | _ => AValueFlow
        }
        advance(st)
        // taps sit between the arrow and its stage: `-> | double`
        while peek(st) == TokPipe {
          Array.push(stages, (arrow, StTap))
          advance(st)
        }
        Array.push(stages, (arrow, parseStage(st)))
      }
    | TokBind => {
        advance(st)
        let bs = parseBinders(st)
        bs->Array.forEach(b => Array.push(binders, b))
      }
    | TokNewline => {
        let save = st.pos
        skipNewlines(st)
        switch peek(st) {
        | TokArrowV | TokArrowF | TokArrowVF | TokBind => ()
        | _ => {
            st.pos = save
            continue := false
          }
        }
      }
    | TokEof => continue := false
    | TokColon =>
      fail(
        st,
        "lane lines (label: chain) are not parsed yet — name the split and use projections (see ARCHITECTURE.md)",
      )
    | other => fail(st, "unexpected " ++ tokenToString(other) ++ " in chain")
    }
  }
  Chain({sources, stages, binders})
}

// A lane group: the first `~flow` is already consumed by the caller. Read its
// `: value`, then any further `~flow: value` lanes (newline-separated), then
// the `-~> collect => binders` terminator.
let parseLaneCollect = (st: p, firstFlow: flowTerm): statement => {
  let lanes: array<(flowTerm, term)> = []
  let readLane = (ft: flowTerm) => {
    expect(st, TokColon, "':' in a lane line (~flow: value)")
    Array.push(lanes, (ft, parseTerm(st)))
  }
  readLane(firstFlow)
  let continue = ref(true)
  while continue.contents {
    skipNewlines(st)
    switch peek(st) {
    | TokTilde => {
        advance(st)
        readLane(parseFlowTerm(st))
      }
    | _ => continue := false
    }
  }
  expect(st, TokArrowVF, "'-~>' terminating the lane group")
  expect(st, TokName("collect"), "'collect' after '-~>' in a lane group")
  expect(st, TokBind, "'=>' before the lane group's binder")
  LaneCollect({lanes, binders: parseBinders(st)})
}

let rec parseStatement = (st: p): statement =>
  switch peek(st) {
  | TokPlus => {
      // A '+' completion line: derived, never stored — skip the line.
      while peek(st) != TokNewline && peek(st) != TokEof {
        advance(st)
      }
      skipNewlines(st)
      parseStatement(st)
    }
  | TokName("out") => {
      advance(st)
      let name = expectName(st, "an output name")
      let from = if peek(st) == TokEq {
        advance(st)
        Some(expectName(st, "a source name"))
      } else {
        None
      }
      OutDecl({name, from})
    }
  | TokPipe => {
      // tap resumption: leading '|'s are ordinal tap sources
      let sources: array<source> = []
      while peek(st) == TokPipe {
        advance(st)
        Array.push(sources, SrcTap)
      }
      parseChainTail(st, sources)
    }
  | TokTilde => {
      advance(st)
      let f = parseFlowTerm(st)
      if peek(st) == TokColon {
        // lane group: ~flow: value (\n ~flow: value)* -~> collect => binders
        parseLaneCollect(st, f)
      } else {
        // flow-sourced chain: ~L ~> delay init 0 => sum
        parseChainTail(st, [SrcFlow(f)])
      }
    }
  | TokName(_) if peek2(st) == TokEq => {
      let name = expectName(st, "a name")
      advance(st) // '='
      let t = parseTerm(st)
      LeafDef({name, term: t})
    }
  | _ => {
      // value-sourced chain
      let sources: array<source> = [SrcTerm(parseTerm(st))]
      while peek(st) == TokComma {
        advance(st)
        if peek(st) == TokTilde {
          advance(st)
          Array.push(sources, SrcFlow(parseFlowTerm(st)))
        } else {
          Array.push(sources, SrcTerm(parseTerm(st)))
        }
      }
      parseChainTail(st, sources)
    }
  }

let parse = (src: string): array<statement> => {
  let st = {toks: lex(src), pos: 0}
  let out: array<statement> = []
  skipNewlines(st)
  while peek(st) != TokEof {
    Array.push(out, parseStatement(st))
    skipNewlines(st)
  }
  out
}
