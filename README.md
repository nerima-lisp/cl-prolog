# cl-prolog

[![CI](https://github.com/nerima-lisp/cl-prolog/actions/workflows/ci.yml/badge.svg)](https://github.com/nerima-lisp/cl-prolog/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A small, dependency-free Prolog engine for Common Lisp. Rulebases are plain
data, proof search is continuation-passing, and the builtin goal set is
extensible. The public package is `cl-prolog`.

## Quick Start

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

Prolog source text works too:

```lisp
(query-prolog (consult-prolog #p"family.pl") (read-prolog-term "ancestor(tom, Who)"))
```

## Install

cl-prolog is not on Quicklisp. Clone it and load its ASDF definition, or put
the checkout on your [ASDF source registry](https://asdf.common-lisp.dev/asdf.html#Configuring-ASDF):

```sh
git clone https://github.com/nerima-lisp/cl-prolog.git
```

With Nix, `nix run github:nerima-lisp/cl-prolog` runs the regression suite.

## Documentation

<https://nerima-lisp.github.io/cl-prolog/> — querying, builtin goals, the rule
DSL, DCG support, arithmetic, and semantics. The source lives in
[`docs/src`](docs/src/README.md); see [Installation](docs/src/installation.md)
and [Development](docs/src/development.md) to build and test locally.

## Project Policy

[Changelog](CHANGELOG.md) ·
[Contributing](CONTRIBUTING.md) ·
[Code of Conduct](CODE_OF_CONDUCT.md) ·
[Security](SECURITY.md) ·
[Support](SUPPORT.md)

## License

MIT — see [LICENSE](LICENSE).
