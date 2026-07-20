// The series-parallel context — the poset generalization of the linear
// context path, worked out for the Cross round (product-flows-design.md,
// "The context model"; the on-paper Fork-A discussion recorded in
// ARCHITECTURE.md's poset round).
//
// A context is the structure of iteration axes a value lives under. The linear
// path `array<flowRef>` only expresses a total nesting order; a Cross's product
// puts two axes side by side, order-free, so the context becomes a poset. This
// module is that poset, and it is exactly SERIES-PARALLEL, because the two
// operations that build contexts are the two SP operations:
//
//   - nesting (Uncollect ... in / a dependent inner flow) = SERIES composition
//     (an outer chain, then the new axis inside it);
//   - Cross                                              = PARALLEL composition
//     (two contexts combined with no order between them).
//
// So every well-formed context is series-parallel by construction. The only
// posets outside SP contain an induced "N", and an N is always a repeated-flow
// DIAMOND — one axis reached by two incomparable ancestry paths, left
// unresolved between ALIGN (zip: the two occurrences are one walk → a shared
// series spine) and CROSS (product: two independent axes → parallel of chains).
// Both resolutions are SP; the N is the incoherent middle, which the checker
// witnesses (like bundle mixing) rather than representing. So SP is the COMPLETE
// model of well-formed contexts — this module never needs a general poset.
//
// Axes are keyed by string (Context.flowKey) so the algebra stays a pure
// combinatorial unit, decoupled from Program and trivially testable. The wiring
// layer (Context.res, next sub-step) maps flow refs to keys, computes these
// contexts from the program, and builds the product index `merge` consults.
//
// Cells (partial-collect merged flows) are also set-valued layers but with the
// OPPOSITE polarity (a bigger cell set is more agnostic — `⊇`, not `⊆`) and no
// product-style traversal split; they are not modeled here yet (they arrive with
// the partial-collect merged-context sub-step). This module is products +
// nesting.

type rec t =
  | Root // no axes — the top-level context (the linear path's `[]`)
  | Axis(string) // one iteration axis, keyed by Context.flowKey
  | Series(array<t>) // nesting: element i is strictly outside element i+1
  | Parallel(array<t>) // product: members are order-free (a Cross)

// --- small set helpers (axis keys / order pairs as string arrays) -----------

let dedup = (xs: array<string>): array<string> =>
  xs->Array.reduce([], (acc, x) => acc->Array.includes(x) ? acc : Array.concat(acc, [x]))

let subset = (a: array<string>, b: array<string>): bool => a->Array.every(x => b->Array.includes(x))

// --- constructors, with the light SP normalization (flatten singletons /
//     drop Root; Root is the identity of both compositions) -------------------

let notRoot = (x: t): bool =>
  switch x {
  | Root => false
  | _ => true
  }

let series = (xs: array<t>): t =>
  switch xs->Array.filter(notRoot) {
  | [] => Root
  | [one] => one
  | ys => Series(ys)
  }

let parallel = (xs: array<t>): t =>
  switch xs->Array.filter(notRoot) {
  | [] => Root
  | [one] => one
  | ys => Parallel(ys)
  }

// --- the two derived facts `≤` is defined from ------------------------------

// Every axis key the context contains.
let rec axes = (c: t): array<string> =>
  switch c {
  | Root => []
  | Axis(k) => [k]
  | Series(xs) | Parallel(xs) => xs->Array.reduce([], (acc, x) => Array.concat(acc, axes(x)))
  }

// The strict order the context commits: `a<b` (a strictly outside b), keyed as
// "a<b". Series contributes cross-pairs (every axis of an earlier member outside
// every axis of a later member) plus each member's own pairs; Parallel commits
// no pairs between members (order-free), only each member's own.
let pairKey = (a: string, b: string): string => a ++ "<" ++ b

let rec before = (c: t): array<string> =>
  switch c {
  | Root | Axis(_) => []
  | Parallel(xs) => xs->Array.reduce([], (acc, x) => Array.concat(acc, before(x)))
  | Series(xs) =>
    let within = xs->Array.reduce([], (acc, x) => Array.concat(acc, before(x)))
    let cross = []
    let n = Array.length(xs)
    for i in 0 to n - 1 {
      for j in i + 1 to n - 1 {
        let ai = axes(Array.getUnsafe(xs, i))
        let bj = axes(Array.getUnsafe(xs, j))
        ai->Array.forEach(a => bj->Array.forEach(b => Array.push(cross, pairKey(a, b))))
      }
    }
    Array.concat(within, cross)
  }

// --- `≤` : "S is more agnostic; a value at S is available at R" ---------------
//
// The Fork-A primitive, representation-independent: S ≤ R iff R contains all of
// S's axes AND R's order EXTENDS S's — every strict outer-than S commits, R
// commits too; axes S leaves order-free (a product) R may order however it
// likes. This is "R refines S" / "S is a delete-innermost-then-coarsen of R";
// the linear prefix rule is its all-singletons, all-Series instance.
let leq = (s: t, r: t): bool => subset(axes(s), axes(r)) && subset(before(s), before(r))

// --- merge -------------------------------------------------------------------
//
// Where the combination of two operands lives. Comparable operands: the deeper
// one. Incomparable operands (siblings): the constructed product of EXACTLY
// their axes — NOT a covering superset. This is the one place `merge` and `leq`
// diverge: availability is monotone (`leq` uses ⊆, so a sub-product IS reusable
// inside a bigger product's loop), but a combine's *home* is exact (`==`),
// because a flat cross builds no sub-products (product-flows-design.md, n-ary:
// "a flat three-way cross builds neither {X,Y} nor {Y,Z}"). `products` is the
// program's constructed product contexts (the wiring layer builds it from the
// Cross nodes).
//
// When no exact product exists, the combine is UNDER-DETERMINED — and that is
// not an error to fix by giving Cross more detail. Cross exists to give
// natural-feeling *time-travel* programs a meaning; an under-determined cross is
// just another time-travel program, made concrete by completion picking details
// compatible with the rest of the program. So merge raises `Incomparable` and
// leaves it to completion / the checker, exactly as for any sibling combine —
// including the case where two incomparable products both cover the need
// (merge refuses to silently pick one).
exception Incomparable(t, t)

let sameSet = (a: array<string>, b: array<string>): bool => subset(a, b) && subset(b, a)

let merge = (~products: array<t>, a: t, b: t): t =>
  if leq(a, b) {
    b
  } else if leq(b, a) {
    a
  } else {
    let need = Array.concat(axes(a), axes(b))
    switch products->Array.find(p => sameSet(axes(p), need) && leq(a, p) && leq(b, p)) {
    | Some(p) => p
    | None => throw(Incomparable(a, b))
    }
  }

// --- rendering (tests / debugging) ------------------------------------------

let rec toString = (c: t): string =>
  switch c {
  | Root => "·"
  | Axis(k) => k
  | Series(xs) => "(" ++ xs->Array.map(toString)->Array.join(" > ") ++ ")"
  | Parallel(xs) => "{" ++ xs->Array.map(toString)->Array.join(" || ") ++ "}"
  }
