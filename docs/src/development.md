# Development

This page covers the development environment and day-to-day workflow. Testing
and benchmarks have their own pages: [Testing](testing.md) and
[Benchmarks](benchmarks.md).

## Environment

The flake defines outputs for `x86_64-linux` and `aarch64-linux`.
On either of those systems, enter the reproducible development
environment with:

```sh
nix develop        # sbcl, cl-weave, paredit-cli, nixpkgs-fmt, mkdocs-material
```

!!! info "Other platforms have no flake outputs"
    On platforms outside the three supported systems (e.g. Intel Mac,
    Windows), the flake does not expose a development shell, package, check,
    or app. Load the local checkout with ASDF instead (see
    [Installation](installation.md)) and rely on CI for Nix verification.

## Running examples

```sh
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:load-asd (truename "cl-prolog.asd"))' \
  --eval '(asdf:load-system :cl-prolog/examples)'
```

Run this from the repository root. Loading `cl-prolog/examples` loads the
library first and then executes all three example files. The example files are
not standalone scripts, so invoking them directly with `sbcl --script` does not
load the `cl-prolog` package. See [Examples](examples.md) for a walkthrough.

## Testing at a glance

```sh
nix run .          # cl-weave regression suite
nix flake check    # full verification suite
```

`nix flake check` also runs the structural parse gate, the examples check, and
the documentation build. The full testing workflow — including the ASDF
fallback for unsupported platforms and the `cl-prolog/weave` query helpers —
is on the [Testing](testing.md) page.

## Benchmarks at a glance

```sh
sbcl --script benchmarks/performance.lisp      # in-process micro-benchmarks
ITERATIONS=5000 benchmarks/external-comparison.sh   # cross-engine comparison
```

These are diagnostic tools, not part of `nix flake check`. See
[Benchmarks](benchmarks.md).

## Documentation

The site is built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).
The config lives in `docs/mkdocs.yml` and content in `docs/src/`.

=== "Nix"

    ```sh
    nix build .#docs   # rendered site in ./result
    ```

=== "MkDocs directly"

    ```sh
    # from the dev shell, or any environment with mkdocs-material installed
    mkdocs serve -f docs/mkdocs.yml          # live-reloading preview
    mkdocs build -f docs/mkdocs.yml --strict # one-shot strict build
    ```

`--strict` promotes broken links and unlisted pages to build failures, matching
the Nix build and the `checks.documentation` gate. The published site deploys to
GitHub Pages from `.github/workflows/docs.yml` on every push to `main` that
touches `docs/`, `flake.nix`, `flake.lock`, or the workflow itself.

## Design constraints

- no runtime dependencies, SBCL-tested, ANSI-leaning core
- a single canonical public API surface

See [Release Checklist](release-checklist.md) for the evidence bar a change must
clear before shipping.
