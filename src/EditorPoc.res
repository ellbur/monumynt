// ============================================================================
// EditorPoc — a working miniature of plans/editor-state-management-design.md.
//
// The host language is deliberately NOT the flow language: it is a simply
// typed lambda calculus (Int / Bool / functions, plus Add, If and Let for
// texture), and the derived information is types plus type-error witnesses.
// Everything else is the design doc at small scale:
//
//   - Refs-by-record: a term embeds its children's records, so a record's
//     pointer identity covers its entire upstream (here: subtree) cone.
//   - Edits are path copies that keep ids: the rebuilt path is exactly the
//     set of records whose derived answers may change; everything off the
//     path is shared, and known shared.
//   - The basic implementation is the semantics: `transfer` is the one pure
//     typing function, `checkFresh` is the plain recursion over it (the
//     oracle), and `checkStored` is the SAME function wrapped in a cache —
//     droppable at any moment, observable only as time.
//   - Keys cover reads: a check is keyed on (record pointer, environment
//     restricted to the record's free variables). An edit that rebuilds a
//     binder without changing what a neighbour reads still hits — the env
//     slice is the result-equality cutoff surface.
//   - No invalidation, only keying: entries for superseded versions are
//     correct answers to questions no longer asked. Undo, branch switching
//     and previews are therefore cache hits; a hypothetical version is just
//     a version, and discarding it needs no rollback.
//   - History is a step-DAG with the fold cached per node (head-first). A
//     dropped `versionCache` is refolded from the parent plus the step's
//     recorded replacement record — steps are the durable record; caches
//     evict.
//
// Exercised by src/EditorPocTest.res (`npm run poc`).
// ============================================================================

// ---------------------------------------------------------------------------
// Types of the little language
// ---------------------------------------------------------------------------

type rec ty =
  | TInt
  | TBool
  | TFun(ty, ty)

let rec tyToString = (t: ty): string =>
  switch t {
  | TInt => "Int"
  | TBool => "Bool"
  | TFun(a, b) => "(" ++ tyToString(a) ++ " -> " ++ tyToString(b) ++ ")"
  }

let rec tyEqual = (a: ty, b: ty): bool =>
  switch (a, b) {
  | (TInt, TInt) => true
  | (TBool, TBool) => true
  | (TFun(a1, b1), TFun(a2, b2)) => tyEqual(a1, a2) && tyEqual(b1, b2)
  | _ => false
  }

// ---------------------------------------------------------------------------
// Terms: refs-by-record, ids stable across path copy
// ---------------------------------------------------------------------------

type rec term = {id: int, node: nodeKind}
and nodeKind =
  | IntLit(int)
  | BoolLit(bool)
  | Var(string)
  | Lam({param: string, paramTy: ty, body: term})
  | App({fn: term, arg: term})
  | Add({left: term, right: term})
  | Let({name: string, bound: term, body: term})
  | If({cond: term, then_: term, else_: term})

let nextId = ref(0)
let mintId = (): int => {
  nextId := nextId.contents + 1
  nextId.contents
}

let mkInt = (n: int): term => {id: mintId(), node: IntLit(n)}
let mkBool = (b: bool): term => {id: mintId(), node: BoolLit(b)}
let mkVar = (x: string): term => {id: mintId(), node: Var(x)}
let mkLam = (param: string, paramTy: ty, body: term): term => {
  id: mintId(),
  node: Lam({param, paramTy, body}),
}
let mkApp = (fn: term, arg: term): term => {id: mintId(), node: App({fn, arg})}
let mkAdd = (left: term, right: term): term => {id: mintId(), node: Add({left, right})}
let mkLet = (name: string, bound: term, body: term): term => {
  id: mintId(),
  node: Let({name, bound, body}),
}
let mkIf = (cond: term, then_: term, else_: term): term => {
  id: mintId(),
  node: If({cond, then_, else_}),
}

let children = (t: term): array<term> =>
  switch t.node {
  | IntLit(_) | BoolLit(_) | Var(_) => []
  | Lam({body}) => [body]
  | App({fn, arg}) => [fn, arg]
  | Add({left, right}) => [left, right]
  | Let({bound, body}) => [bound, body]
  | If({cond, then_, else_}) => [cond, then_, else_]
  }

let rec size = (t: term): int => children(t)->Array.reduce(1, (acc, c) => acc + size(c))

let collectIds = (t: term): array<int> => {
  let out: array<int> = []
  let rec go = (u: term) => {
    out->Array.push(u.id)
    children(u)->Array.forEach(go)
  }
  go(t)
  out
}

let rec findById = (t: term, id: int): option<term> =>
  if t.id == id {
    Some(t)
  } else {
    let cs = children(t)
    let rec scan = (i: int): option<term> =>
      switch cs->Array.get(i) {
      | None => None
      | Some(c) =>
        switch findById(c, id) {
        | Some(r) => Some(r)
        | None => scan(i + 1)
        }
      }
    scan(0)
  }

let rec termToString = (t: term): string =>
  switch t.node {
  | IntLit(n) => Int.toString(n)
  | BoolLit(b) => b ? "true" : "false"
  | Var(x) => x
  | Lam({param, paramTy, body}) =>
    "(\\" ++ param ++ ":" ++ tyToString(paramTy) ++ ". " ++ termToString(body) ++ ")"
  | App({fn, arg}) => "(" ++ termToString(fn) ++ " " ++ termToString(arg) ++ ")"
  | Add({left, right}) => "(" ++ termToString(left) ++ " + " ++ termToString(right) ++ ")"
  | Let({name, bound, body}) =>
    "(let " ++ name ++ " = " ++ termToString(bound) ++ " in " ++ termToString(body) ++ ")"
  | If({cond, then_, else_}) =>
    "(if " ++
    termToString(cond) ++
    " then " ++
    termToString(then_) ++
    " else " ++
    termToString(else_) ++ ")"
  }

// Structural equality including ids — what a refold must reproduce exactly.
let rec termEqual = (a: term, b: term): bool =>
  a.id == b.id &&
  switch (a.node, b.node) {
  | (IntLit(x), IntLit(y)) => x == y
  | (BoolLit(x), BoolLit(y)) => x == y
  | (Var(x), Var(y)) => x == y
  | (Lam(l1), Lam(l2)) =>
    l1.param == l2.param && tyEqual(l1.paramTy, l2.paramTy) && termEqual(l1.body, l2.body)
  | (App(a1), App(a2)) => termEqual(a1.fn, a2.fn) && termEqual(a1.arg, a2.arg)
  | (Add(a1), Add(a2)) => termEqual(a1.left, a2.left) && termEqual(a1.right, a2.right)
  | (Let(l1), Let(l2)) =>
    l1.name == l2.name && termEqual(l1.bound, l2.bound) && termEqual(l1.body, l2.body)
  | (If(i1), If(i2)) =>
    termEqual(i1.cond, i2.cond) && termEqual(i1.then_, i2.then_) && termEqual(i1.else_, i2.else_)
  | _ => false
  }

// ---------------------------------------------------------------------------
// The derived information: types + witnesses, as data
// ---------------------------------------------------------------------------

type witness = {at: int, message: string}

type checkResult = {ty: option<ty>, witnesses: array<witness>}

let witnessEqual = (a: witness, b: witness): bool => a.at == b.at && a.message == b.message

let resultEqual = (a: checkResult, b: checkResult): bool => {
  let tyOk = switch (a.ty, b.ty) {
  | (None, None) => true
  | (Some(x), Some(y)) => tyEqual(x, y)
  | _ => false
  }
  tyOk &&
  Array.length(a.witnesses) == Array.length(b.witnesses) && {
    let ok = ref(true)
    a.witnesses->Array.forEachWithIndex((w, i) =>
      switch b.witnesses->Array.get(i) {
      | Some(w2) =>
        if !witnessEqual(w, w2) {
          ok := false
        }
      | None => ok := false
      }
    )
    ok.contents
  }
}

let resultToString = (r: checkResult): string => {
  let t = switch r.ty {
  | Some(t) => tyToString(t)
  | None => "<no type>"
  }
  if Array.length(r.witnesses) == 0 {
    t
  } else {
    t ++
    " with " ++
    Int.toString(Array.length(r.witnesses)) ++
    " witness(es): " ++
    r.witnesses->Array.map(w => w.message)->Array.join("; ")
  }
}

// ---------------------------------------------------------------------------
// Environments
// ---------------------------------------------------------------------------

// A binding whose bound side errored maps to None: the error is witnessed at
// the binder, and uses of the name stay quiet rather than cascading.
type env = list<(string, option<ty>)>

let rec envLookup = (env: env, x: string): option<option<ty>> =>
  switch env {
  | list{} => None
  | list{(y, t), ...rest} => y == x ? Some(t) : envLookup(rest, x)
  }

// ---------------------------------------------------------------------------
// The one transfer function (node-local typing rules)
// ---------------------------------------------------------------------------

// `recur` is how subterms are checked: the oracle passes plain recursion,
// the store passes the memoizing wrapper. Same rules either way — the store
// is a cache of this function, semantically nothing.
let transfer = (recur: (env, term) => checkResult, env: env, t: term): checkResult =>
  switch t.node {
  | IntLit(_) => {ty: Some(TInt), witnesses: []}
  | BoolLit(_) => {ty: Some(TBool), witnesses: []}
  | Var(x) =>
    switch envLookup(env, x) {
    | Some(t') => {ty: t', witnesses: []}
    | None => {ty: None, witnesses: [{at: t.id, message: "unbound variable " ++ x}]}
    }
  | Lam({param, paramTy, body}) => {
      let r = recur(list{(param, Some(paramTy)), ...env}, body)
      {ty: r.ty->Option.map(b => TFun(paramTy, b)), witnesses: r.witnesses}
    }
  | App({fn, arg}) => {
      let rf = recur(env, fn)
      let ra = recur(env, arg)
      let ws = Array.concat(rf.witnesses, ra.witnesses)
      switch (rf.ty, ra.ty) {
      | (Some(TFun(p, out)), Some(a)) =>
        tyEqual(p, a)
          ? {ty: Some(out), witnesses: ws}
          : {
              ty: None,
              witnesses: Array.concat(
                ws,
                [
                  {
                    at: t.id,
                    message: "argument has type " ++
                    tyToString(a) ++
                    " but the function expects " ++
                    tyToString(p),
                  },
                ],
              ),
            }
      | (Some(TFun(_, _)), None) => {ty: None, witnesses: ws}
      | (Some(nonFun), _) => {
          ty: None,
          witnesses: Array.concat(
            ws,
            [{at: t.id, message: "cannot apply a value of type " ++ tyToString(nonFun)}],
          ),
        }
      | (None, _) => {ty: None, witnesses: ws}
      }
    }
  | Add({left, right}) => {
      let rl = recur(env, left)
      let rr = recur(env, right)
      let ws = Array.concat(rl.witnesses, rr.witnesses)
      let extra: array<witness> = []
      let side = (label: string, r: checkResult) =>
        switch r.ty {
        | Some(TInt) | None => ()
        | Some(other) =>
          extra->Array.push({
            at: t.id,
            message: label ++ " operand of + has type " ++ tyToString(other),
          })
        }
      side("left", rl)
      side("right", rr)
      let ty = switch (rl.ty, rr.ty) {
      | (Some(TInt), Some(TInt)) => Some(TInt)
      | _ => None
      }
      {ty, witnesses: Array.concat(ws, extra)}
    }
  | Let({name, bound, body}) => {
      let rb = recur(env, bound)
      let r = recur(list{(name, rb.ty), ...env}, body)
      {ty: r.ty, witnesses: Array.concat(rb.witnesses, r.witnesses)}
    }
  | If({cond, then_, else_}) => {
      let rc = recur(env, cond)
      let rt = recur(env, then_)
      let re = recur(env, else_)
      let ws = Array.concat(rc.witnesses, Array.concat(rt.witnesses, re.witnesses))
      let extra: array<witness> = []
      switch rc.ty {
      | Some(TBool) | None => ()
      | Some(other) =>
        extra->Array.push({at: t.id, message: "if condition has type " ++ tyToString(other)})
      }
      let ty = switch (rt.ty, re.ty) {
      | (Some(t1), Some(t2)) =>
        if tyEqual(t1, t2) {
          Some(t1)
        } else {
          extra->Array.push({
            at: t.id,
            message: "if branches disagree: " ++ tyToString(t1) ++ " vs " ++ tyToString(t2),
          })
          None
        }
      | _ => None
      }
      {ty, witnesses: Array.concat(ws, extra)}
    }
  }

// ---------------------------------------------------------------------------
// The oracle: the basic implementation IS the semantics
// ---------------------------------------------------------------------------

let rec checkFresh = (env: env, t: term): checkResult => transfer(checkFresh, env, t)

// ---------------------------------------------------------------------------
// The store: constructive traces keyed by (record pointer, env slice)
// ---------------------------------------------------------------------------

type stats = {
  mutable computes: int, // transfer-function runs — the design doc's assertable unit
  mutable hits: int,
  mutable misses: int,
}

type store = {
  // Outer key: the record pointer — under refs-by-record it covers the whole
  // subtree cone, and weakness makes entries die with their versions.
  // Inner key: the environment restricted to the record's free variables —
  // everything the transfer function reads that the pointer doesn't cover.
  types: WeakMap.t<term, Map.t<string, checkResult>>,
  fv: WeakMap.t<term, array<string>>,
  stats: stats,
}

let makeStore = (): store => {
  types: WeakMap.make(),
  fv: WeakMap.make(),
  stats: {computes: 0, hits: 0, misses: 0},
}

let resetStats = (s: store): unit => {
  s.stats.computes = 0
  s.stats.hits = 0
  s.stats.misses = 0
}

let sortedDedup = (a: array<string>): array<string> => {
  let sorted = a->Array.toSorted(String.compare)
  let out: array<string> = []
  sorted->Array.forEach(x =>
    if out->Array.length == 0 || out->Array.getUnsafe(Array.length(out) - 1) != x {
      out->Array.push(x)
    }
  )
  out
}

// Free variables, memoized per record pointer (a pure function of the record).
let rec freeVars = (store: store, t: term): array<string> =>
  switch WeakMap.get(store.fv, t) {
  | Some(v) => v
  | None => {
      let v = switch t.node {
      | IntLit(_) | BoolLit(_) => []
      | Var(x) => [x]
      | Lam({param, body}) => freeVars(store, body)->Array.filter(x => x != param)
      | App({fn, arg}) => sortedDedup(Array.concat(freeVars(store, fn), freeVars(store, arg)))
      | Add({left, right}) =>
        sortedDedup(Array.concat(freeVars(store, left), freeVars(store, right)))
      | Let({name, bound, body}) =>
        sortedDedup(
          Array.concat(freeVars(store, bound), freeVars(store, body)->Array.filter(x => x != name)),
        )
      | If({cond, then_, else_}) =>
        sortedDedup(
          Array.concat(
            freeVars(store, cond),
            Array.concat(freeVars(store, then_), freeVars(store, else_)),
          ),
        )
      }
      store.fv->WeakMap.set(t, v)->ignore
      v
    }
  }

// The env-slice half of the key: what this record's check actually reads of
// the environment, canonically encoded. "!" = unbound, "?" = bound-but-errored.
let envSliceKey = (store: store, env: env, t: term): string =>
  freeVars(store, t)
  ->Array.map(x =>
    x ++
    "=" ++
    switch envLookup(env, x) {
    | None => "!"
    | Some(None) => "?"
    | Some(Some(ty)) => tyToString(ty)
    }
  )
  ->Array.join(";")

let rec checkStored = (store: store, env: env, t: term): checkResult => {
  let slice = envSliceKey(store, env, t)
  let inner = switch WeakMap.get(store.types, t) {
  | Some(m) => m
  | None => {
      let m = Map.make()
      store.types->WeakMap.set(t, m)->ignore
      m
    }
  }
  switch Map.get(inner, slice) {
  | Some(r) => {
      store.stats.hits = store.stats.hits + 1
      r
    }
  | None => {
      store.stats.misses = store.stats.misses + 1
      let r = transfer((e, u) => checkStored(store, e, u), env, t)
      store.stats.computes = store.stats.computes + 1
      Map.set(inner, slice, r)
      r
    }
  }
}

// ---------------------------------------------------------------------------
// Edits: path copy, ids kept
// ---------------------------------------------------------------------------

// Applies `build` to the node with `targetId`, path-copying to the root.
// Rebuilt ancestors keep their ids (new records, same identity); everything
// off the path is shared. Returns (new root, the built replacement subterm,
// touched ids root-to-target) — the step's own enumeration of its footprint.
let rec replaceBuild = (t: term, targetId: int, build: term => term): option<(
  term,
  term,
  array<int>,
)> =>
  if t.id == targetId {
    let ns = build(t)
    Some((ns, ns, [t.id]))
  } else {
    switch t.node {
    | IntLit(_) | BoolLit(_) | Var(_) => None
    | Lam({param, paramTy, body}) =>
      replaceBuild(body, targetId, build)->Option.map(((b, ns, path)) => (
        {id: t.id, node: Lam({param, paramTy, body: b})},
        ns,
        Array.concat([t.id], path),
      ))
    | App({fn, arg}) =>
      switch replaceBuild(fn, targetId, build) {
      | Some((f, ns, path)) =>
        Some(({id: t.id, node: App({fn: f, arg: arg})}, ns, Array.concat([t.id], path)))
      | None =>
        replaceBuild(arg, targetId, build)->Option.map(((a, ns, path)) => (
          {id: t.id, node: App({fn: fn, arg: a})},
          ns,
          Array.concat([t.id], path),
        ))
      }
    | Add({left, right}) =>
      switch replaceBuild(left, targetId, build) {
      | Some((l, ns, path)) =>
        Some(({id: t.id, node: Add({left: l, right: right})}, ns, Array.concat([t.id], path)))
      | None =>
        replaceBuild(right, targetId, build)->Option.map(((r, ns, path)) => (
          {id: t.id, node: Add({left: left, right: r})},
          ns,
          Array.concat([t.id], path),
        ))
      }
    | Let({name, bound, body}) =>
      switch replaceBuild(bound, targetId, build) {
      | Some((b, ns, path)) =>
        Some(({id: t.id, node: Let({name, bound: b, body: body})}, ns, Array.concat([t.id], path)))
      | None =>
        replaceBuild(body, targetId, build)->Option.map(((b, ns, path)) => (
          {id: t.id, node: Let({name, bound: bound, body: b})},
          ns,
          Array.concat([t.id], path),
        ))
      }
    | If({cond, then_, else_}) =>
      switch replaceBuild(cond, targetId, build) {
      | Some((c, ns, path)) =>
        Some((
          {id: t.id, node: If({cond: c, then_, else_: else_})},
          ns,
          Array.concat([t.id], path),
        ))
      | None =>
        switch replaceBuild(then_, targetId, build) {
        | Some((th, ns, path)) =>
          Some((
            {id: t.id, node: If({cond: cond, then_: th, else_: else_})},
            ns,
            Array.concat([t.id], path),
          ))
        | None =>
          replaceBuild(else_, targetId, build)->Option.map(((e, ns, path)) => (
            {id: t.id, node: If({cond: cond, then_: then_, else_: e})},
            ns,
            Array.concat([t.id], path),
          ))
        }
      }
    }
  }

// ---------------------------------------------------------------------------
// History: the step-DAG, head-first, with the fold cached per node
// ---------------------------------------------------------------------------

type step = {
  desc: string,
  targetId: int,
  newSub: term, // the built replacement record — refold reuses it verbatim
  touchedIds: array<int>,
}

type rec historyNode = {
  step: option<step>, // None for the root of history
  parents: array<historyNode>, // the step-DAG; parents[0] is the undo target
  mutable versionCache: option<term>, // cache of the fold of ancestry — evictable
}

let makeHistoryRoot = (initial: term): historyNode => {
  step: None,
  parents: [],
  versionCache: Some(initial),
}

// The fold of ancestry. A dropped cache is refolded from the parent's
// version plus the step: same ids everywhere, same shared records off the
// path and for the replacement — only the path records are fresh pointers,
// so a refolded version re-checks at path cost, not program cost.
let rec versionOf = (h: historyNode): term =>
  switch h.versionCache {
  | Some(v) => v
  | None =>
    switch (h.step, h.parents->Array.get(0)) {
    | (Some(s), Some(p)) => {
        let parentV = versionOf(p)
        switch replaceBuild(parentV, s.targetId, _ => s.newSub) {
        | Some((v, _, _)) => {
            h.versionCache = Some(v)
            v
          }
        | None => failwith("refold: step target vanished from the parent version")
        }
      }
    | _ => failwith("history root lost its version")
    }
  }

// ---------------------------------------------------------------------------
// The working record
// ---------------------------------------------------------------------------

type session = {
  mutable head: historyNode,
  mutable store: store, // the cache tier — droppable at any moment
}

let makeSession = (initial: term): session => {
  head: makeHistoryRoot(initial),
  store: makeStore(),
}

let applyEdit = (s: session, ~desc: string, ~targetId: int, ~build: term => term): option<
  historyNode,
> =>
  switch replaceBuild(versionOf(s.head), targetId, build) {
  | None => None
  | Some((v, newSub, touchedIds)) => {
      let h = {
        step: Some({desc, targetId, newSub, touchedIds}),
        parents: [s.head],
        versionCache: Some(v),
      }
      s.head = h
      Some(h)
    }
  }

let undo = (s: session): bool =>
  switch s.head.parents->Array.get(0) {
  | Some(p) => {
      s.head = p
      true
    }
  | None => false
  }

let checkHead = (s: session): checkResult => checkStored(s.store, list{}, versionOf(s.head))

let dropStore = (s: session): unit => s.store = makeStore()

// ---------------------------------------------------------------------------
// Previews: hypothetical versions over the shared store
// ---------------------------------------------------------------------------

type preview = {
  previewStep: step,
  previewVersion: term,
  previewResult: checkResult,
}

// A hypothetical version is just a version — applied to the head, never
// appended to the DAG, checked through the shared store. Discarding needs no
// rollback; committing reuses the previewed version, so the apply is all hits.
let previewEdit = (s: session, ~desc: string, ~targetId: int, ~build: term => term): option<
  preview,
> =>
  replaceBuild(versionOf(s.head), targetId, build)->Option.map(((v, newSub, touchedIds)) => {
    previewStep: {desc, targetId, newSub, touchedIds},
    previewVersion: v,
    previewResult: checkStored(s.store, list{}, v),
  })

let commitPreview = (s: session, p: preview): historyNode => {
  let h = {
    step: Some(p.previewStep),
    parents: [s.head],
    versionCache: Some(p.previewVersion),
  }
  s.head = h
  h
}

// ---------------------------------------------------------------------------
// The demand-driven cursor query
// ---------------------------------------------------------------------------

// The type at a node, demanding only that node's cone (plus the bound sides
// of Lets on the path, needed for the environment — through the store, so
// usually hits). The view asks for what it shows; nothing else is computed.
let typeAt = (s: session, targetId: int): option<checkResult> => {
  let rec go = (env: env, t: term): option<checkResult> =>
    if t.id == targetId {
      Some(checkStored(s.store, env, t))
    } else {
      switch t.node {
      | IntLit(_) | BoolLit(_) | Var(_) => None
      | Lam({param, paramTy, body}) => go(list{(param, Some(paramTy)), ...env}, body)
      | App({fn, arg}) =>
        switch go(env, fn) {
        | Some(r) => Some(r)
        | None => go(env, arg)
        }
      | Add({left, right}) =>
        switch go(env, left) {
        | Some(r) => Some(r)
        | None => go(env, right)
        }
      | Let({name, bound, body}) =>
        switch go(env, bound) {
        | Some(r) => Some(r)
        | None => {
            let rb = checkStored(s.store, env, bound)
            go(list{(name, rb.ty), ...env}, body)
          }
        }
      | If({cond, then_, else_}) =>
        switch go(env, cond) {
        | Some(r) => Some(r)
        | None =>
          switch go(env, then_) {
          | Some(r) => Some(r)
          | None => go(env, else_)
          }
        }
      }
    }
  go(list{}, versionOf(s.head))
}
