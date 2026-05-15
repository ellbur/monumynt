// Convenience constructors for building JsAst values.
//
// These wrap the variant constructors with shorter names and sensible
// defaults so example code reads more like the JavaScript it produces.

open JsAst

// --- Atoms ---

let id = (name: string): expr => EId(name)
let num = (n: float): expr => ENum(n)
let int_ = (n: int): expr => ENum(Int.toFloat(n))
let str = (s: string): expr => EStr(s)
let bool_ = (b: bool): expr => EBool(b)
let null = ENull
let undefined = EUndefined

// --- Compound expressions ---

let array_ = (elems: array<expr>): expr => EArray(elems->Array.map(e => AElem(e)))
let arrayWith = (elems: array<arrayElement>): expr => EArray(elems)

let obj = (fields: array<(string, expr)>): expr =>
  EObject(fields->Array.map(((k, v)) => OKV({key: PKId(k), value: v})))

let objWith = (props: array<objectProp>): expr => EObject(props)

let member = (obj: expr, prop: string): expr => EMember({obj, prop})
let index = (obj: expr, index: expr): expr => EIndex({obj, index})

let call = (callee: expr, args: array<expr>): expr =>
  ECall({callee, args: args->Array.map(a => CArg(a))})

let callWith = (callee: expr, args: array<callArg>): expr => ECall({callee, args})

let new_ = (callee: expr, args: array<expr>): expr =>
  ENew({callee, args: args->Array.map(a => CArg(a))})

// --- Parameters ---

let p = (name: string): param => PNamed({name, default: None})
let pDefault = (name: string, default: expr): param =>
  PNamed({name, default: Some(default)})
let pRest = (name: string): param => PRest(name)

let params = (names: array<string>): array<param> => names->Array.map(p)

// --- Functions ---

let arrow = (params: array<param>, body: array<stmt>): expr =>
  EArrow({params, body: ABBlock(body), isAsync: false})

let arrowExpr = (params: array<param>, body: expr): expr =>
  EArrow({params, body: ABExpr(body), isAsync: false})

let asyncArrow = (params: array<param>, body: array<stmt>): expr =>
  EArrow({params, body: ABBlock(body), isAsync: true})

let func = (~name=?, params: array<param>, body: array<stmt>): expr =>
  EFunction({name, params, body, isAsync: false})

let asyncFunc = (~name=?, params: array<param>, body: array<stmt>): expr =>
  EFunction({name, params, body, isAsync: true})

// --- Operators ---

let bin = (op: binOp, left: expr, right: expr): expr => EBin({op, left, right})

let add = bin(Add, ...)
let sub = bin(Sub, ...)
let mul = bin(Mul, ...)
let div = bin(Div, ...)
let mod_ = bin(Mod, ...)
let eq = bin(StrictEq, ...)
let neq = bin(StrictNotEq, ...)
let lt = bin(Lt, ...)
let lte = bin(LtEq, ...)
let gt = bin(Gt, ...)
let gte = bin(GtEq, ...)
let and_ = bin(And, ...)
let or_ = bin(Or, ...)
let nullish = bin(Nullish, ...)

let not_ = (e: expr): expr => EUn({op: Not, operand: e})
let neg = (e: expr): expr => EUn({op: Neg, operand: e})
let typeof_ = (e: expr): expr => EUn({op: Typeof, operand: e})

let assign = (target: expr, value: expr): expr =>
  EAssign({op: Assign, target, value})

let cond = (test: expr, cons: expr, alt: expr): expr => ECond({test, cons, alt})

let await_ = (e: expr): expr => EAwait(e)

// --- Statements ---

let exprStmt = (e: expr): stmt => SExpr(e)

let let_ = (name: string, value: expr): stmt =>
  SVar({kind: Let, decls: [{name, init: Some(value)}]})

let const = (name: string, value: expr): stmt =>
  SVar({kind: Const, decls: [{name, init: Some(value)}]})

let var = (name: string, value: expr): stmt =>
  SVar({kind: Var, decls: [{name, init: Some(value)}]})

let letDecl = (name: string): stmt =>
  SVar({kind: Let, decls: [{name, init: None}]})

let if_ = (test: expr, cons: array<stmt>): stmt =>
  SIf({test, cons: SBlock(cons), alt: None})

let ifElse = (test: expr, cons: array<stmt>, alt: array<stmt>): stmt =>
  SIf({test, cons: SBlock(cons), alt: Some(SBlock(alt))})

let ifElseIf = (test: expr, cons: array<stmt>, alt: stmt): stmt =>
  SIf({test, cons: SBlock(cons), alt: Some(alt)})

let while_ = (test: expr, body: array<stmt>): stmt =>
  SWhile({test, body: SBlock(body)})

let forOf = (name: string, iter: expr, body: array<stmt>): stmt =>
  SForOf({kind: Const, name, iter, body: SBlock(body)})

let ret = (e: expr): stmt => SReturn(Some(e))
let retVoid: stmt = SReturn(None)

let throw_ = (e: expr): stmt => SThrow(e)

let funcDecl = (name: string, params: array<param>, body: array<stmt>): stmt =>
  SFunction({name, params, body, isAsync: false})

let asyncFuncDecl = (name: string, params: array<param>, body: array<stmt>): stmt =>
  SFunction({name, params, body, isAsync: true})

let block = (stmts: array<stmt>): stmt => SBlock(stmts)

// --- Modules ---

let importDefault = (name: string, source: string): stmt =>
  SImport({default: Some(name), namespace: None, named: [], source})

let importNamed = (names: array<string>, source: string): stmt =>
  SImport({
    default: None,
    namespace: None,
    named: names->Array.map(n => {imported: n, local: n}),
    source,
  })

let importStar = (name: string, source: string): stmt =>
  SImport({default: None, namespace: Some(name), named: [], source})

let exportDefault = (e: expr): stmt => SExport(ExDefault(e))
let exportDecl = (s: stmt): stmt => SExport(ExDecl(s))
