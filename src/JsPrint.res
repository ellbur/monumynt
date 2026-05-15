// Pretty-printer for JsAst. Produces a string of JavaScript source.
//
// The printer is precedence-aware: it inserts parentheses only when needed.
// Statement-level expressions that would otherwise start with `function` or
// `{` are wrapped, so output is safe to drop into any context. Indentation
// uses two spaces per level. No effort is made to break long lines.

open JsAst

// Precedence levels. Higher numbers bind tighter. `printExpr` takes a
// `minPrec`; if the expression's own precedence is lower, the printer wraps
// it in parentheses.
let pComma = 0
let pAssign = 1
let pCond = 2
let pNullish = 3
let pOr = 4
let pAnd = 5
let pBitOr = 6
let pBitXor = 7
let pBitAnd = 8
let pEquality = 9
let pRelational = 10
let pShift = 11
let pAdditive = 12
let pMultiplicative = 13
let pExp = 14
let pUnary = 15
let pUpdate = 16
let pCall = 17
let pPrimary = 18

@val external jsonStringify: string => string = "JSON.stringify"

// --- Numbers ---

let formatNumber = (n: float): string => {
  if Float.isNaN(n) {
    "NaN"
  } else if !Float.isFinite(n) {
    if n > 0.0 {
      "Infinity"
    } else {
      "-Infinity"
    }
  } else {
    Float.toString(n)
  }
}

// --- Identifier check (ASCII; conservative) ---

let isIdentStart = (c: string): bool =>
  (c >= "A" && c <= "Z") || (c >= "a" && c <= "z") || c == "_" || c == "$"

let isIdentCont = (c: string): bool =>
  isIdentStart(c) || (c >= "0" && c <= "9")

let isValidIdent = (s: string): bool => {
  let len = String.length(s)
  if len == 0 {
    false
  } else {
    let ok = ref(isIdentStart(String.charAt(s, 0)))
    let i = ref(1)
    while ok.contents && i.contents < len {
      if !isIdentCont(String.charAt(s, i.contents)) {
        ok := false
      }
      i := i.contents + 1
    }
    ok.contents
  }
}

// --- Operator metadata ---

let binOpToken = (op: binOp): string =>
  switch op {
  | Add => "+"
  | Sub => "-"
  | Mul => "*"
  | Div => "/"
  | Mod => "%"
  | Exp => "**"
  | Eq => "=="
  | NotEq => "!="
  | StrictEq => "==="
  | StrictNotEq => "!=="
  | Lt => "<"
  | LtEq => "<="
  | Gt => ">"
  | GtEq => ">="
  | And => "&&"
  | Or => "||"
  | Nullish => "??"
  | BitAnd => "&"
  | BitOr => "|"
  | BitXor => "^"
  | Shl => "<<"
  | Shr => ">>"
  | UShr => ">>>"
  | In => "in"
  | InstanceOf => "instanceof"
  }

let binOpPrec = (op: binOp): int =>
  switch op {
  | Exp => pExp
  | Mul | Div | Mod => pMultiplicative
  | Add | Sub => pAdditive
  | Shl | Shr | UShr => pShift
  | Lt | LtEq | Gt | GtEq | In | InstanceOf => pRelational
  | Eq | NotEq | StrictEq | StrictNotEq => pEquality
  | BitAnd => pBitAnd
  | BitXor => pBitXor
  | BitOr => pBitOr
  | And => pAnd
  | Or => pOr
  | Nullish => pNullish
  }

let binOpRightAssoc = (op: binOp): bool =>
  switch op {
  | Exp => true
  | _ => false
  }

let unOpToken = (op: unOp): string =>
  switch op {
  | Neg => "-"
  | Pos => "+"
  | Not => "!"
  | BitNot => "~"
  | Typeof => "typeof"
  | Void => "void"
  | Delete => "delete"
  }

let unOpNeedsSpace = (op: unOp): bool =>
  switch op {
  | Typeof | Void | Delete => true
  | _ => false
  }

let updateOpToken = (op: updateOp): string =>
  switch op {
  | PreInc | PostInc => "++"
  | PreDec | PostDec => "--"
  }

let updateIsPrefix = (op: updateOp): bool =>
  switch op {
  | PreInc | PreDec => true
  | PostInc | PostDec => false
  }

let assignOpToken = (op: assignOp): string =>
  switch op {
  | Assign => "="
  | AddAssign => "+="
  | SubAssign => "-="
  | MulAssign => "*="
  | DivAssign => "/="
  | ModAssign => "%="
  | ExpAssign => "**="
  | BitAndAssign => "&="
  | BitOrAssign => "|="
  | BitXorAssign => "^="
  | ShlAssign => "<<="
  | ShrAssign => ">>="
  | UShrAssign => ">>>="
  | AndAssign => "&&="
  | OrAssign => "||="
  | NullishAssign => "??="
  }

let varKindToken = (k: varKind): string =>
  switch k {
  | Var => "var"
  | Let => "let"
  | Const => "const"
  }

// --- "Starts with" checks for stmt-start and arrow-body disambiguation ---

// Does the printed form of `e` begin with a `{` token? Used to know when an
// arrow function expression-body needs to be wrapped in parens.
let rec startsWithBrace = (e: expr): bool =>
  switch e {
  | EObject(_) => true
  | EMember({obj}) | EIndex({obj}) => startsWithBrace(obj)
  | ECall({callee}) => startsWithBrace(callee)
  | EBin({left}) => startsWithBrace(left)
  | EAssign({target}) => startsWithBrace(target)
  | ECond({test}) => startsWithBrace(test)
  | EUpdate({op: PostInc | PostDec, operand}) => startsWithBrace(operand)
  | ESeq(es) =>
    switch es->Array.get(0) {
    | Some(first) => startsWithBrace(first)
    | None => false
    }
  | _ => false
  }

// Does the printed form of `e`, as the first thing on an expression
// statement, start with a token that would be reinterpreted (`function`,
// `class`, `{`, `async function`, ...)?
let rec needsParensAtStmtStart = (e: expr): bool =>
  switch e {
  | EObject(_) => true
  | EFunction(_) => true
  | EMember({obj}) | EIndex({obj}) => needsParensAtStmtStart(obj)
  | ECall({callee}) => needsParensAtStmtStart(callee)
  | EBin({left}) => needsParensAtStmtStart(left)
  | EAssign({target}) => needsParensAtStmtStart(target)
  | ECond({test}) => needsParensAtStmtStart(test)
  | EUpdate({op: PostInc | PostDec, operand}) => needsParensAtStmtStart(operand)
  | ESeq(es) =>
    switch es->Array.get(0) {
    | Some(first) => needsParensAtStmtStart(first)
    | None => false
    }
  | _ => false
  }

// JS forbids mixing `??` with `||` / `&&` without parentheses, even though
// the precedence table would otherwise resolve it.
let mixedNullishConflict = (outerOp: binOp, inner: expr): bool =>
  switch (outerOp, inner) {
  | (Nullish, EBin({op: And})) | (Nullish, EBin({op: Or})) => true
  | (And, EBin({op: Nullish})) | (Or, EBin({op: Nullish})) => true
  | _ => false
  }

// JS forbids unary on the left of `**`. Force parens in that case.
let unaryLeftOfExp = (left: expr): bool =>
  switch left {
  | EUn(_) => true
  | EUpdate({op: PreInc | PreDec}) => true
  | EAwait(_) => true
  | _ => false
  }

// --- Printer ---

let indentStr = (n: int): string => String.repeat("  ", n)

let rec printExpr = (~minPrec=0, e: expr): string => {
  let (myPrec, body) = printExprInner(e)
  if myPrec < minPrec {
    "(" ++ body ++ ")"
  } else {
    body
  }
}

and printExprInner = (e: expr): (int, string) =>
  switch e {
  | ENum(n) =>
    let s = formatNumber(n)
    // Negative numeric literals print with a leading `-`, which is really a
    // unary minus expression from the parser's perspective. Treat it as such
    // so that e.g. `-5 ** 2` correctly gets parenthesized.
    let prec =
      if String.length(s) > 0 && String.charAt(s, 0) == "-" {
        pUnary
      } else {
        pPrimary
      }
    (prec, s)
  | EStr(s) => (pPrimary, jsonStringify(s))
  | EBool(true) => (pPrimary, "true")
  | EBool(false) => (pPrimary, "false")
  | ENull => (pPrimary, "null")
  | EUndefined => (pPrimary, "undefined")
  | EId(s) => (pPrimary, s)
  | EArray(elems) => (pPrimary, printArrayLit(elems))
  | EObject(props) => (pPrimary, printObjectLit(props))
  | EMember({obj, prop}) =>
    let lhs = printExpr(~minPrec=pCall, obj)
    let suffix =
      if isValidIdent(prop) {
        "." ++ prop
      } else {
        "[" ++ jsonStringify(prop) ++ "]"
      }
    (pCall, lhs ++ suffix)
  | EIndex({obj, index}) =>
    let lhs = printExpr(~minPrec=pCall, obj)
    let idx = printExpr(~minPrec=pAssign, index)
    (pCall, lhs ++ "[" ++ idx ++ "]")
  | ECall({callee, args}) =>
    let f = printExpr(~minPrec=pCall, callee)
    (pCall, f ++ "(" ++ printArgs(args) ++ ")")
  | ENew({callee, args}) =>
    let f = printExpr(~minPrec=pCall, callee)
    (pCall, "new " ++ f ++ "(" ++ printArgs(args) ++ ")")
  | EArrow({params, body, isAsync}) =>
    (pAssign, printArrow(params, body, isAsync))
  | EFunction({name, params, body, isAsync}) =>
    (pPrimary, printFunctionExpr(name, params, body, isAsync))
  | EBin({op, left, right}) => printBin(op, left, right)
  | EUn({op, operand}) =>
    let sep = if unOpNeedsSpace(op) { " " } else { "" }
    let inner = printExpr(~minPrec=pUnary, operand)
    (pUnary, unOpToken(op) ++ sep ++ inner)
  | EUpdate({op, operand}) =>
    if updateIsPrefix(op) {
      (pUnary, updateOpToken(op) ++ printExpr(~minPrec=pUnary, operand))
    } else {
      (pUpdate, printExpr(~minPrec=pUpdate, operand) ++ updateOpToken(op))
    }
  | EAssign({op, target, value}) =>
    // Assignment is right-associative.
    let lhs = printExpr(~minPrec=pAssign + 1, target)
    let rhs = printExpr(~minPrec=pAssign, value)
    (pAssign, lhs ++ " " ++ assignOpToken(op) ++ " " ++ rhs)
  | ECond({test, cons, alt}) =>
    let t = printExpr(~minPrec=pCond + 1, test)
    let c = printExpr(~minPrec=pAssign, cons)
    let a = printExpr(~minPrec=pAssign, alt)
    (pCond, t ++ " ? " ++ c ++ " : " ++ a)
  | ESeq(es) =>
    let parts = es->Array.map(e => printExpr(~minPrec=pAssign, e))
    (pComma, parts->Array.join(", "))
  | ESpread(e) =>
    (pAssign, "..." ++ printExpr(~minPrec=pAssign, e))
  | EAwait(e) =>
    (pUnary, "await " ++ printExpr(~minPrec=pUnary, e))
  }

and printBin = (op: binOp, left: expr, right: expr): (int, string) => {
  let p = binOpPrec(op)
  let (lMin, rMin) =
    if binOpRightAssoc(op) {
      (p + 1, p)
    } else {
      (p, p + 1)
    }
  let forceParenLeft = mixedNullishConflict(op, left) || (op == Exp && unaryLeftOfExp(left))
  let forceParenRight = mixedNullishConflict(op, right)
  let lStr =
    if forceParenLeft {
      "(" ++ printExpr(~minPrec=0, left) ++ ")"
    } else {
      printExpr(~minPrec=lMin, left)
    }
  let rStr =
    if forceParenRight {
      "(" ++ printExpr(~minPrec=0, right) ++ ")"
    } else {
      printExpr(~minPrec=rMin, right)
    }
  (p, lStr ++ " " ++ binOpToken(op) ++ " " ++ rStr)
}

and printArgs = (args: array<callArg>): string => {
  let parts = args->Array.map(a =>
    switch a {
    | CArg(e) => printExpr(~minPrec=pAssign, e)
    | CSpread(e) => "..." ++ printExpr(~minPrec=pAssign, e)
    }
  )
  parts->Array.join(", ")
}

and printArrayLit = (elems: array<arrayElement>): string => {
  let parts = elems->Array.map(a =>
    switch a {
    | AElem(e) => printExpr(~minPrec=pAssign, e)
    | AHole => ""
    | ASpread(e) => "..." ++ printExpr(~minPrec=pAssign, e)
    }
  )
  "[" ++ parts->Array.join(", ") ++ "]"
}

and printObjectLit = (props: array<objectProp>): string => {
  if Array.length(props) == 0 {
    "{}"
  } else {
    let parts = props->Array.map(p =>
      switch p {
      | OKV({key, value}) => printPropKey(key) ++ ": " ++ printExpr(~minPrec=pAssign, value)
      | OShorthand(name) => name
      | OSpread(e) => "..." ++ printExpr(~minPrec=pAssign, e)
      | OMethod({key, params, body, isAsync}) =>
        let async = if isAsync { "async " } else { "" }
        async ++ printPropKey(key) ++ "(" ++ printParams(params) ++ ") " ++ printBlock(body, 0)
      }
    )
    "{" ++ parts->Array.join(", ") ++ "}"
  }
}

and printPropKey = (k: propKey): string =>
  switch k {
  | PKId(s) => if isValidIdent(s) { s } else { jsonStringify(s) }
  | PKStr(s) => jsonStringify(s)
  | PKNum(n) => formatNumber(n)
  | PKComputed(e) => "[" ++ printExpr(~minPrec=pAssign, e) ++ "]"
  }

and printParams = (ps: array<param>): string => {
  let parts = ps->Array.map(p =>
    switch p {
    | PNamed({name, default: None}) => name
    | PNamed({name, default: Some(e)}) => name ++ " = " ++ printExpr(~minPrec=pAssign, e)
    | PRest(name) => "..." ++ name
    }
  )
  parts->Array.join(", ")
}

and printArrow = (params: array<param>, body: arrowBody, isAsync: bool): string => {
  let async = if isAsync { "async " } else { "" }
  let p = switch params {
  | [PNamed({name, default: None})] if !isAsync => name
  | _ => "(" ++ printParams(params) ++ ")"
  }
  let b = switch body {
  | ABExpr(e) =>
    if startsWithBrace(e) {
      "(" ++ printExpr(~minPrec=pAssign, e) ++ ")"
    } else {
      printExpr(~minPrec=pAssign, e)
    }
  | ABBlock(stmts) => printBlock(stmts, 0)
  }
  async ++ p ++ " => " ++ b
}

and printFunctionExpr = (
  name: option<string>,
  params: array<param>,
  body: array<stmt>,
  isAsync: bool,
): string => {
  let async = if isAsync { "async " } else { "" }
  let n = switch name {
  | Some(s) => " " ++ s
  | None => ""
  }
  async ++ "function" ++ n ++ "(" ++ printParams(params) ++ ") " ++ printBlock(body, 0)
}

and printBlock = (stmts: array<stmt>, indent: int): string => {
  if Array.length(stmts) == 0 {
    "{}"
  } else {
    let inner =
      stmts
      ->Array.map(s => indentStr(indent + 1) ++ printStmt(s, indent + 1))
      ->Array.join("\n")
    "{\n" ++ inner ++ "\n" ++ indentStr(indent) ++ "}"
  }
}

// Print a statement that appears in a branch position (the body of an `if`,
// `while`, `for`, ...). Always uses block form for unambiguous output.
and printBranchBody = (s: stmt, indent: int): string =>
  switch s {
  | SBlock(stmts) => printBlock(stmts, indent)
  | _ => printBlock([s], indent)
  }

and printVarDecls = (decls: array<varDecl>): string => {
  let parts = decls->Array.map(d =>
    switch d.init {
    | Some(e) => d.name ++ " = " ++ printExpr(~minPrec=pAssign, e)
    | None => d.name
    }
  )
  parts->Array.join(", ")
}

and printStmt = (s: stmt, indent: int): string =>
  switch s {
  | SExpr(e) =>
    let body = printExpr(~minPrec=0, e)
    let wrapped = if needsParensAtStmtStart(e) {
      "(" ++ body ++ ")"
    } else {
      body
    }
    wrapped ++ ";"
  | SBlock(stmts) => printBlock(stmts, indent)
  | SVar({kind, decls}) => varKindToken(kind) ++ " " ++ printVarDecls(decls) ++ ";"
  | SIf({test, cons, alt}) =>
    let head = "if (" ++ printExpr(~minPrec=0, test) ++ ") "
    let consStr = printBranchBody(cons, indent)
    switch alt {
    | None => head ++ consStr
    | Some(elseStmt) =>
      switch elseStmt {
      | SIf(_) => head ++ consStr ++ " else " ++ printStmt(elseStmt, indent)
      | _ => head ++ consStr ++ " else " ++ printBranchBody(elseStmt, indent)
      }
    }
  | SWhile({test, body}) =>
    "while (" ++ printExpr(~minPrec=0, test) ++ ") " ++ printBranchBody(body, indent)
  | SDoWhile({body, test}) =>
    "do " ++ printBranchBody(body, indent) ++ " while (" ++ printExpr(~minPrec=0, test) ++ ");"
  | SFor({init, test, update, body}) =>
    let i = switch init {
    | None => ""
    | Some(FIExpr(e)) => printExpr(~minPrec=0, e)
    | Some(FIVar({kind, decls})) => varKindToken(kind) ++ " " ++ printVarDecls(decls)
    }
    let t = switch test {
    | None => ""
    | Some(e) => printExpr(~minPrec=0, e)
    }
    let u = switch update {
    | None => ""
    | Some(e) => printExpr(~minPrec=0, e)
    }
    "for (" ++ i ++ "; " ++ t ++ "; " ++ u ++ ") " ++ printBranchBody(body, indent)
  | SForOf({kind, name, iter, body}) =>
    "for (" ++
    varKindToken(kind) ++
    " " ++
    name ++
    " of " ++
    printExpr(~minPrec=pAssign, iter) ++
    ") " ++
    printBranchBody(body, indent)
  | SForIn({kind, name, obj, body}) =>
    "for (" ++
    varKindToken(kind) ++
    " " ++
    name ++
    " in " ++
    printExpr(~minPrec=pAssign, obj) ++
    ") " ++
    printBranchBody(body, indent)
  | SReturn(None) => "return;"
  | SReturn(Some(e)) => "return " ++ printExpr(~minPrec=0, e) ++ ";"
  | SBreak(None) => "break;"
  | SBreak(Some(l)) => "break " ++ l ++ ";"
  | SContinue(None) => "continue;"
  | SContinue(Some(l)) => "continue " ++ l ++ ";"
  | SThrow(e) => "throw " ++ printExpr(~minPrec=0, e) ++ ";"
  | STry({block, catch, finally}) =>
    let head = "try " ++ printBlock(block, indent)
    let c = switch catch {
    | None => ""
    | Some({param: None, body}) => " catch " ++ printBlock(body, indent)
    | Some({param: Some(p), body}) => " catch (" ++ p ++ ") " ++ printBlock(body, indent)
    }
    let f = switch finally {
    | None => ""
    | Some(body) => " finally " ++ printBlock(body, indent)
    }
    head ++ c ++ f
  | SFunction({name, params, body, isAsync}) =>
    let async = if isAsync { "async " } else { "" }
    async ++
    "function " ++
    name ++
    "(" ++
    printParams(params) ++
    ") " ++
    printBlock(body, indent)
  | SLabel({label, body}) => label ++ ": " ++ printStmt(body, indent)
  | SEmpty => ";"
  | SImport(imp) => printImport(imp)
  | SExport(exp) => printExport(exp, indent)
  }

and printImport = (imp: importStmt): string => {
  let pieces = []
  switch imp.default {
  | Some(name) => pieces->Array.push(name)
  | None => ()
  }
  switch imp.namespace {
  | Some(name) => pieces->Array.push("* as " ++ name)
  | None => ()
  }
  if Array.length(imp.named) > 0 {
    let names =
      imp.named
      ->Array.map(s =>
        if s.imported == s.local {
          s.imported
        } else {
          s.imported ++ " as " ++ s.local
        }
      )
      ->Array.join(", ")
    pieces->Array.push("{" ++ names ++ "}")
  }
  let clause = pieces->Array.join(", ")
  if String.length(clause) == 0 {
    "import " ++ jsonStringify(imp.source) ++ ";"
  } else {
    "import " ++ clause ++ " from " ++ jsonStringify(imp.source) ++ ";"
  }
}

and printExport = (e: exportStmt, indent: int): string =>
  switch e {
  | ExDefault(expr) => "export default " ++ printExpr(~minPrec=pAssign, expr) ++ ";"
  | ExDecl(stmt) => "export " ++ printStmt(stmt, indent)
  | ExNamed({specifiers, source}) =>
    let names =
      specifiers
      ->Array.map(s =>
        if s.exported == s.as_ {
          s.exported
        } else {
          s.exported ++ " as " ++ s.as_
        }
      )
      ->Array.join(", ")
    let src = switch source {
    | Some(s) => " from " ++ jsonStringify(s)
    | None => ""
    }
    "export {" ++ names ++ "}" ++ src ++ ";"
  | ExAll({source, as_}) =>
    let alias = switch as_ {
    | Some(a) => "* as " ++ a
    | None => "*"
    }
    "export " ++ alias ++ " from " ++ jsonStringify(source) ++ ";"
  }

let printProgram = (p: program): string =>
  p->Array.map(s => printStmt(s, 0))->Array.join("\n") ++ "\n"
