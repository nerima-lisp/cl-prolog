# Querying

Every query takes an explicit rulebase and a goal, and returns solutions. There
is no global database — see [Rule DSL](rule-dsl.md) for building rulebases and
[Architecture](../reference/architecture.md#explicit-dynamic-mutation) for why state is
explicit.

```lisp
(query-prolog rb '(ancestor tom ?who))          ; all solutions
(query-prolog rb '(ancestor tom ?who) :limit 2) ; bounded search
(query-prolog-first rb '(ancestor ?x bob))      ; first solution or NIL
(prolog-succeeds-p rb '(ancestor tom eve))      ; boolean, stops at first proof

;; streaming: the function is called as each solution is proven
(map-prolog-solutions
 (lambda (solution) (format t "~&=> ~S~%" solution))
 rb '(ancestor tom ?who))
```

`with-prolog-query` binds variables from the first solution; `prolog-match`
dispatches like `cond` over queries (both are covered in the
[Rule DSL](rule-dsl.md#available-forms)).

## Entry points

| Function                | Returns                                              |
| ----------------------- | ---------------------------------------------------- |
| `map-prolog-solutions`  | Nothing useful; calls your function per solution.    |
| `query-prolog`          | A list of solution alists.                           |
| `query-prolog-first`    | The first solution alist, or `nil`.                  |
| `prolog-succeeds-p`     | A boolean.                                            |
| `solution-binding`      | One variable's value from a solution alist.          |

- **`map-prolog-solutions`** — the primitive. Calls a function once per solution
  **as it is proven** (streaming CPS). Keywords: `:max-depth`, `:environment`,
  `:project`, `:limit`.
- **`query-prolog`** — collects solutions into a list. Same keywords. This is
  `map-prolog-solutions` with an accumulating callback.
- **`query-prolog-first`** — first solution or `nil` (searches with `:limit 1`).
- **`prolog-succeeds-p`** — boolean; stops at the first proof. Supports
  `:max-depth`. A single-goal call with no `:environment`/`:max-depth` that
  resolves through a tabled or left-recursive predicate is memoized per
  rulebase revision; a cache hit returns `t` without re-running the proof or
  any side effects the goal would otherwise perform.
- **`solution-binding`** — looks one variable up in a solution alist.

## Keyword options

| Keyword         | Meaning                                                         |
| --------------- | -------------------------------------------------------------- |
| `:limit`        | `nil` or a positive integer; caps the number of solutions.     |
| `:max-depth`    | `nil` (unbounded) or a non-negative integer; bounds user-rule resolution. |
| `:project`      | `nil` returns raw proof environments instead of binding alists. |
| `:environment`  | A starting binding environment for the search.                 |

`map-prolog-solutions`, `query-prolog`, `query-prolog-first`, and (for
`:max-depth`) `prolog-succeeds-p` accept these. See the
[API Reference](../reference/api.md#queries) for the exact per-function support.

## Result conventions

A solution is an alist of query-variable bindings. The empty-vs-`(nil)`
distinction trips up newcomers, so it is worth stating precisely:

| Outcome                          | Result   |
| -------------------------------- | -------- |
| No proof (failure)               | `()`     |
| One ground proof, no variables   | `(nil)`  |
| Proofs that bind variables       | `(((?x . a)) ((?x . b)) ...)` |

- `:project nil` returns raw proof environments instead of projected alists.
- Ground success is the empty alist `nil`, so "one ground proof" is the
  one-element list `(nil)`, while failure is the empty list `()`.

!!! tip "See it in Troubleshooting"
    If `(nil)` or a `nil` from `query-prolog-first` surprises you, the
    [Troubleshooting](troubleshooting.md) page walks through each case.

## Depth bounds

`:max-depth` optionally bounds **user-rule** resolution (the default is `NIL`,
meaning unbounded). Depth decreases when proof enters a user rule, not for every
builtin or unification step.

- `nil` — unbounded search (the default).
- `0` — disables rule expansion entirely; facts and builtins still match.
- `n` — permits up to `n` levels of user-rule expansion.

Exhaustion signals `prolog-depth-limit-exceeded` rather than masquerading as
logical failure, so an incomplete search is never reported as "no solutions".
See [Semantics](../reference/semantics.md) and [Conditions and Errors](../reference/conditions.md).

## Validation

The option list is validated up front, so mistakes fail loudly instead of being
silently ignored:

- `:limit` must be `nil` or a positive integer; any other value signals a
  `type-error`.
- An odd-length option list or an unrecognized keyword signals a
  `program-error`.
- An invalid `:max-depth` (not `nil` or a non-negative integer) signals
  `invalid-max-depth-error`.

## Next steps

- [Rule DSL](rule-dsl.md) — build and extend the rulebases you query.
- [Builtin Goals](builtin-goals.md) — the goals you can put in a query.
- [Cookbook](cookbook.md) — streaming, counting, and bounded-search recipes.
