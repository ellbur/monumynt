// Typed AST for a useful subset of JavaScript (ES2017+ / ESM).
//
// This is a build-only representation: it covers the constructs we expect to
// generate when compiling the visual flow language to JavaScript. It does not
// aim for parser-completeness, and several features (classes, generators,
// decorators, JSX, template literals with substitutions, destructuring
// patterns beyond simple parameters) are intentionally omitted.
//
// Identifiers are passed as plain strings. We do not validate that they are
// legal JS identifiers; users of this module are responsible for supplying
// valid names. The pretty-printer will, however, fall back to bracket
// notation for property accesses when the name is not a valid identifier.

type binOp =
  | Add | Sub | Mul | Div | Mod | Exp
  | Eq | NotEq | StrictEq | StrictNotEq
  | Lt | LtEq | Gt | GtEq
  | And | Or | Nullish
  | BitAnd | BitOr | BitXor | Shl | Shr | UShr
  | In | InstanceOf

type unOp =
  | Neg | Pos | Not | BitNot | Typeof | Void | Delete

type updateOp =
  | PreInc | PreDec | PostInc | PostDec

type assignOp =
  | Assign
  | AddAssign | SubAssign | MulAssign | DivAssign | ModAssign | ExpAssign
  | BitAndAssign | BitOrAssign | BitXorAssign
  | ShlAssign | ShrAssign | UShrAssign
  | AndAssign | OrAssign | NullishAssign

type varKind = Var | Let | Const

type rec expr =
  | ENum(float)
  | EStr(string)
  | EBool(bool)
  | ENull
  | EUndefined
  | EId(string)
  | EArray(array<arrayElement>)
  | EObject(array<objectProp>)
  | EMember({obj: expr, prop: string})
  | EIndex({obj: expr, index: expr})
  | ECall({callee: expr, args: array<callArg>})
  | ENew({callee: expr, args: array<callArg>})
  | EArrow({params: array<param>, body: arrowBody, isAsync: bool})
  | EFunction({name: option<string>, params: array<param>, body: array<stmt>, isAsync: bool})
  | EBin({op: binOp, left: expr, right: expr})
  | EUn({op: unOp, operand: expr})
  | EUpdate({op: updateOp, operand: expr})
  | EAssign({op: assignOp, target: expr, value: expr})
  | ECond({test: expr, cons: expr, alt: expr})
  | ESeq(array<expr>)
  | ESpread(expr)
  | EAwait(expr)

and arrayElement =
  | AElem(expr)
  | AHole
  | ASpread(expr)

and objectProp =
  | OKV({key: propKey, value: expr})
  | OShorthand(string)
  | OSpread(expr)
  | OMethod({key: propKey, params: array<param>, body: array<stmt>, isAsync: bool})

and propKey =
  | PKId(string)
  | PKStr(string)
  | PKNum(float)
  | PKComputed(expr)

and callArg =
  | CArg(expr)
  | CSpread(expr)

and param =
  | PNamed({name: string, default: option<expr>})
  | PRest(string)

and arrowBody =
  | ABExpr(expr)
  | ABBlock(array<stmt>)

and stmt =
  | SExpr(expr)
  | SBlock(array<stmt>)
  | SVar({kind: varKind, decls: array<varDecl>})
  | SIf({test: expr, cons: stmt, alt: option<stmt>})
  | SWhile({test: expr, body: stmt})
  | SDoWhile({body: stmt, test: expr})
  | SFor({init: option<forInit>, test: option<expr>, update: option<expr>, body: stmt})
  | SForOf({kind: varKind, name: string, iter: expr, body: stmt})
  | SForIn({kind: varKind, name: string, obj: expr, body: stmt})
  | SReturn(option<expr>)
  | SBreak(option<string>)
  | SContinue(option<string>)
  | SThrow(expr)
  | STry({block: array<stmt>, catch: option<catchClause>, finally: option<array<stmt>>})
  | SFunction({name: string, params: array<param>, body: array<stmt>, isAsync: bool})
  | SLabel({label: string, body: stmt})
  | SEmpty
  | SImport(importStmt)
  | SExport(exportStmt)

and varDecl = {name: string, init: option<expr>}

and forInit =
  | FIExpr(expr)
  | FIVar({kind: varKind, decls: array<varDecl>})

and catchClause = {param: option<string>, body: array<stmt>}

and importStmt = {
  default: option<string>,
  namespace: option<string>,
  named: array<importSpecifier>,
  source: string,
}

and importSpecifier = {imported: string, local: string}

and exportStmt =
  | ExDefault(expr)
  | ExDecl(stmt)
  | ExNamed({specifiers: array<exportSpecifier>, source: option<string>})
  | ExAll({source: string, as_: option<string>})

and exportSpecifier = {exported: string, as_: string}

type program = array<stmt>
