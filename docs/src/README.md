# cl-prolog

`cl-prolog` is a small, **dependency-free** Prolog engine for Common Lisp, built
around three ideas:

- **macro-first rule definition** — clauses are data, macros own the syntax
- **CPS proof search** — the engine emits solutions through continuations;
  callers choose streaming or collection
- **data / logic separation** — rulebases are plain structs the engine walks

The public package is `cl-prolog`. It implements a focused Prolog runtime rather
than mirroring every facility of a standalone ISO Prolog system.

## Quick start

```lisp
(require :asdf)
(asdf:load-asd (truename "cl-prolog.asd")) ; run from the repository root
(asdf:load-system :cl-prolog)

(in-package #:cl-prolog)

(define-rulebase *family*
  ((parent tom bob))
  ((parent bob alice))
  ((ancestor ?x ?y) (parent ?x ?y))
  ((ancestor ?x ?y) (parent ?x ?z) (ancestor ?z ?y)))

(query-prolog *family* '(ancestor tom ?who))
;; => (((?WHO . BOB)) ((?WHO . ALICE)))
```

Facts are one-element clauses; rules are a head followed by body goals. Logic
variables are `?`-prefixed symbols.

!!! tip "New here?"
    Start with [Installation](installation.md) and [Quick Start](quick-start.md),
    then follow [Your First Program](first-program.md) to build a knowledge base
    step by step.

## Explore the docs

<div class="grid cards" markdown>

-   :material-rocket-launch: **Getting Started**

    ---

    Install the library, run your first query, and build a family tree.

    [:octicons-arrow-right-24: Installation](installation.md) ·
    [Quick Start](quick-start.md) ·
    [First Program](first-program.md)

-   :material-book-open-variant: **Guide**

    ---

    Querying, the rule DSL, builtins, arithmetic, DCG grammars, and recipes.

    [:octicons-arrow-right-24: Querying](querying.md) ·
    [Builtin Goals](builtin-goals.md) ·
    [Cookbook](cookbook.md)

-   :material-file-document-outline: **Reference**

    ---

    The exported symbol index, proof semantics, conditions, and parser limits.

    [:octicons-arrow-right-24: API Reference](api-reference.md) ·
    [Semantics](semantics.md) ·
    [Conditions](conditions.md)

-   :material-cog-outline: **Internals & Project**

    ---

    The CPS engine's architecture, testing, benchmarks, and release process.

    [:octicons-arrow-right-24: Architecture](architecture.md) ·
    [Testing](testing.md) ·
    [Development](development.md)

</div>

## Feature highlights

- A **macro-first DSL**: `prolog`, `define-rulebase`, `extend-rulebase`,
  `def-rule`, and `:when` guards compiled to closures.
- **Streaming or collecting** query APIs over one CPS core:
  `map-prolog-solutions`, `query-prolog`, `query-prolog-first`,
  `prolog-succeeds-p`.
- A broad builtin set — control and meta-call, collection and sorting, the
  dynamic database, arithmetic, ISO string/atom predicates, `library(lists)`,
  `library(apply)`, formatted output, and finite-domain constraints.
- An **SLG tabling engine** with automatic left-recursion handling.
- **DCG** grammar rules and combinators.
- A **transactional source loader** for Prolog text with configurable
  [parser resource limits](parser-limits.md).
- **Foreign predicates** via `define-foreign-predicate` as the supported
  extension surface.

## Install

cl-prolog is not currently distributed by Quicklisp. Clone the repository and
either load its ASDF definition directly or place the checkout in a directory
configured in your
[ASDF source registry](https://asdf.common-lisp.dev/asdf.html#Configuring-ASDF).

```sh
git clone https://github.com/nerima-lisp/cl-prolog.git
cd cl-prolog
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "cl-prolog.asd"))' \
  --eval '(asdf:load-system :cl-prolog)'
```

To run the cl-weave regression suite through the Linux-only Nix app:

```sh
nix run github:nerima-lisp/cl-prolog
```

See [Installation](installation.md) for the full matrix of load paths and the
Linux-only Nix caveat.
