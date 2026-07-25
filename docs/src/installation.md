# Installation

`cl-prolog` is a **dependency-free** Common Lisp library: the core engine pulls
in nothing beyond the ANSI standard. It is developed and tested against
[SBCL](https://www.sbcl.org/), and leans on a portable, ANSI-facing core.

!!! info "Not on Quicklisp yet"
    cl-prolog is not currently distributed by Quicklisp. Install it by cloning
    the repository and making the checkout visible to ASDF.

## Requirements

- A Common Lisp implementation — SBCL is the tested target.
- [ASDF](https://asdf.common-lisp.dev/) (bundled with SBCL) to load the system.
- Optionally [Nix](https://nixos.org/) for the reproducible test and
  documentation workflows.

## Load from a local checkout

Clone the repository and load its ASDF definition directly. Run these commands
from the repository root:

```sh
git clone https://github.com/nerima-lisp/cl-prolog.git
cd cl-prolog
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "cl-prolog.asd"))' \
  --eval '(asdf:load-system :cl-prolog)'
```

From inside a running Lisp, the same three forms load the library:

```lisp
(require :asdf)
(asdf:load-asd (truename "cl-prolog.asd")) ; run from the repository root
(asdf:load-system :cl-prolog)
```

The public package is `cl-prolog`. Enter it — or `:use` it — before writing
queries:

```lisp
(in-package #:cl-prolog)
```

## Register with the ASDF source registry

To load `cl-prolog` from anywhere (not only the repository root), place the
checkout in a directory configured in your
[ASDF source registry](https://asdf.common-lisp.dev/asdf.html#Configuring-ASDF).
Once ASDF can find the `.asd`, a single form loads it:

```lisp
(asdf:load-system :cl-prolog)
```

## Run through Nix

The flake exposes a runner that executes the
[cl-weave](https://github.com/nerima-lisp/cl-weave) regression suite:

```sh
nix run github:nerima-lisp/cl-prolog
```

!!! info "Supported systems"
    The flake defines outputs for `x86_64-linux` and `aarch64-linux`.
    On other platforms (macOS, Windows), use the
    ASDF workflow above instead. See [Development](development.md) for
    details.

## Systems provided

The `cl-prolog.asd` file defines several ASDF systems:

| System                 | Purpose                                              |
| ---------------------- | ---------------------------------------------------- |
| `cl-prolog`            | The production library and public package.           |
| `cl-prolog/tests`      | The cl-weave regression suite ([Testing](testing.md)). |
| `cl-prolog/weave`      | Public query test helpers built on cl-weave.         |
| `cl-prolog/examples`   | Runnable examples ([Examples](examples.md)).         |

## Next steps

- [Quick Start](quick-start.md) — the shortest path to a working query.
- [Your First Program](first-program.md) — a guided family-tree walkthrough.
- [Querying](querying.md) — the query entry points and their contracts.
