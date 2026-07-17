// Lexer for the textual form. Line-oriented: NEWLINE is a token (statement
// boundaries are line-structured; continuation is decided by the parser
// from what a line *starts* with). Indentation is entirely ignored (P3:
// derived, never parsed). `--` comments run to end of line.

type token =
  | TokName(string)
  | TokNum(float)
  | TokStr(string)
  | TokArrowV // ->
  | TokArrowF // ~>
  | TokArrowVF // -~>
  | TokBind // =>
  | TokEq // =
  | TokComma
  | TokLParen
  | TokRParen
  | TokLBracket
  | TokRBracket
  | TokDot
  | TokColon
  | TokPipe
  | TokTilde // ~
  | TokTildeUp // ~^
  | TokPlus // + (completion-line prefix; parser skips those lines)
  | TokSemi
  | TokNewline
  | TokEof

type positioned = {tok: token, line: int}

exception LexError({message: string, line: int})

let isDigit = (ch: string): bool => ch >= "0" && ch <= "9"
let isNameStart = (ch: string): bool =>
  (ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || ch === "_"
let isNameChar = (ch: string): bool => isNameStart(ch) || isDigit(ch)

let lex = (src: string): array<positioned> => {
  let out: array<positioned> = []
  let n = String.length(src)
  let i = ref(0)
  let line = ref(1)
  let push = t => Array.push(out, {tok: t, line: line.contents})
  let peekAt = k => if i.contents + k < n {String.charAt(src, i.contents + k)} else {""}

  while i.contents < n {
    let ch = String.charAt(src, i.contents)
    if ch === "\n" {
      push(TokNewline)
      line := line.contents + 1
      i := i.contents + 1
    } else if ch === " " || ch === "\t" || ch === "\r" {
      i := i.contents + 1
    } else if ch === "-" && peekAt(1) === "-" {
      // comment to end of line
      while i.contents < n && String.charAt(src, i.contents) !== "\n" {
        i := i.contents + 1
      }
    } else if ch === "-" && peekAt(1) === ">" {
      push(TokArrowV)
      i := i.contents + 2
    } else if ch === "-" && peekAt(1) === "~" && peekAt(2) === ">" {
      push(TokArrowVF)
      i := i.contents + 3
    } else if ch === "~" && peekAt(1) === ">" {
      push(TokArrowF)
      i := i.contents + 2
    } else if ch === "~" && peekAt(1) === "^" {
      push(TokTildeUp)
      i := i.contents + 2
    } else if ch === "~" {
      push(TokTilde)
      i := i.contents + 1
    } else if ch === "=" && peekAt(1) === ">" {
      push(TokBind)
      i := i.contents + 2
    } else if ch === "=" {
      push(TokEq)
      i := i.contents + 1
    } else if ch === "," {
      push(TokComma)
      i := i.contents + 1
    } else if ch === "(" {
      push(TokLParen)
      i := i.contents + 1
    } else if ch === ")" {
      push(TokRParen)
      i := i.contents + 1
    } else if ch === "[" {
      push(TokLBracket)
      i := i.contents + 1
    } else if ch === "]" {
      push(TokRBracket)
      i := i.contents + 1
    } else if ch === "." {
      push(TokDot)
      i := i.contents + 1
    } else if ch === ":" {
      push(TokColon)
      i := i.contents + 1
    } else if ch === "|" {
      push(TokPipe)
      i := i.contents + 1
    } else if ch === "+" {
      push(TokPlus)
      i := i.contents + 1
    } else if ch === ";" {
      push(TokSemi)
      i := i.contents + 1
    } else if ch === "\"" {
      // string literal; escapes: \" \\ \n \t
      let buf: array<string> = []
      i := i.contents + 1
      let closed = ref(false)
      while !closed.contents && i.contents < n {
        let c = String.charAt(src, i.contents)
        if c === "\"" {
          closed := true
          i := i.contents + 1
        } else if c === "\\" {
          let next = peekAt(1)
          let repl = switch next {
          | "n" => "\n"
          | "t" => "\t"
          | "\\" => "\\"
          | "\"" => "\""
          | other => other
          }
          Array.push(buf, repl)
          i := i.contents + 2
        } else if c === "\n" {
          throw(LexError({message: "unterminated string", line: line.contents}))
        } else {
          Array.push(buf, c)
          i := i.contents + 1
        }
      }
      if !closed.contents {
        throw(LexError({message: "unterminated string", line: line.contents}))
      }
      push(TokStr(buf->Array.join("")))
    } else if isDigit(ch) {
      let start = i.contents
      while i.contents < n && (isDigit(String.charAt(src, i.contents)) || String.charAt(src, i.contents) === ".") {
        i := i.contents + 1
      }
      let text = String.slice(src, ~start, ~end=i.contents)
      switch Float.fromString(text) {
      | Some(f) => push(TokNum(f))
      | None => throw(LexError({message: "bad number: " ++ text, line: line.contents}))
      }
    } else if isNameStart(ch) {
      let start = i.contents
      while i.contents < n && isNameChar(String.charAt(src, i.contents)) {
        i := i.contents + 1
      }
      push(TokName(String.slice(src, ~start, ~end=i.contents)))
    } else {
      throw(LexError({message: "unexpected character: " ++ ch, line: line.contents}))
    }
  }
  push(TokEof)
  out
}

let tokenToString = (t: token): string =>
  switch t {
  | TokName(s) => "name '" ++ s ++ "'"
  | TokNum(f) => "number " ++ Float.toString(f)
  | TokStr(_) => "string"
  | TokArrowV => "'->'"
  | TokArrowF => "'~>'"
  | TokArrowVF => "'-~>'"
  | TokBind => "'=>'"
  | TokEq => "'='"
  | TokComma => "','"
  | TokLParen => "'('"
  | TokRParen => "')'"
  | TokLBracket => "'['"
  | TokRBracket => "']'"
  | TokDot => "'.'"
  | TokColon => "':'"
  | TokPipe => "'|'"
  | TokTilde => "'~'"
  | TokTildeUp => "'~^'"
  | TokPlus => "'+'"
  | TokSemi => "';'"
  | TokNewline => "newline"
  | TokEof => "end of input"
  }
