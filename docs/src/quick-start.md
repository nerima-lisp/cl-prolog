# Quick Start

This page gets you from a fresh checkout to a working query in a few minutes.
For an installation deep-dive, see [Installation](installation.md); for a
guided tutorial, see [Your First Program](first-program.md).

## Load the library

Run from the repository root:

```lisp
(require :asdf)
(asdf:load-asd (truename "cl-prolog.asd")) ; run from the repository root
(asdf:load-system :cl-prolog)

(in-package #:cl-prolog)
```

## Define a rulebase and query it

```lisp
(define-rulebase *family*
  ((parent tom bob))
  ((parent bob alice))
  ((ancestor ?x ?y) (parent ?x ?y))
  ((ancestor ?x ?y) (parent ?x ?z) (ancestor ?z ?y)))

(query-prolog *family* '(ancestor tom ?who))
;; => (((?WHO . BOB)) ((?WHO . ALICE)))
```

That is the whole loop: build a rulebase, then ask it questions.

## Reading the syntax

- **Facts** are one-element clauses: `((parent tom bob))`.
- **Rules** are a head clause followed by body goals:
  `((ancestor ?x ?y) (parent ?x ?y))`.
- **Logic variables** are `?`-prefixed symbols: `?x`, `?who`.
- A **solution** is an alist of query-variable bindings. Two solutions above
  mean the query proved twice, binding `?who` to `bob` and then to `alice`.

!!! tip "Ground success vs. failure"
    A ground proof that binds no variables returns `(nil)` — a one-element list
    whose single solution is the empty alist. Failure returns `()`. See
    [Troubleshooting](troubleshooting.md#query-prolog-returned-nil) if that
    surprises you.

## Four ways to ask

```lisp
(query-prolog *family* '(ancestor tom ?who))          ; all solutions, as a list
(query-prolog *family* '(ancestor tom ?who) :limit 2) ; bounded search
(query-prolog-first *family* '(ancestor ?x bob))      ; first solution or NIL
(prolog-succeeds-p *family* '(ancestor tom eve))      ; boolean, stops at first proof
```

Streaming — the function is called as each solution is proven:

```lisp
(map-prolog-solutions
 (lambda (solution) (format t "~&=> ~S~%" solution))
 *family* '(ancestor tom ?who))
```

See [Querying](querying.md) for the full contract of each entry point.

## A taste of the builtins

```lisp
;; arithmetic
(query-prolog (make-rulebase) '(is ?total (+ 20 (* 2 11))))
;; => (((?TOTAL . 42)))

;; list relations need no rulebase clauses at all
(query-prolog (make-rulebase) '(append ?l ?r (a b c)))

;; collect every solution of a subgoal into a bag
(query-prolog *family* '(findall ?child (parent tom ?child) ?children))
;; => (((?CHILDREN BOB)))
```

The full catalogue lives in [Builtin Goals](builtin-goals.md).

## Where to go next

- [Your First Program](first-program.md) — build the family tree step by step.
- [Rule DSL](rule-dsl.md) — `define-rulebase`, `extend-rulebase`, guards.
- [Cookbook](cookbook.md) — task-oriented recipes.
- [Examples](examples.md) — the runnable programs shipped in `examples/`.
