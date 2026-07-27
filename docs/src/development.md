# Development

This page covers the development environment and day-to-day workflow. Testing
and benchmarks have their own pages: [Testing](testing.md) and
[Benchmarks](benchmarks.md).

## Environment

The flake defines outputs for `x86_64-linux` and `aarch64-darwin` (Apple
Silicon). On either system, enter the reproducible development environment
with:

```sh
nix develop        # sbcl, cl-weave, paredit-cli, treefmt, mkdocs-material
```

!!! info "Other platforms have no flake outputs"
    On platforms outside the two supported systems (e.g. Intel Mac,
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
nix run .                     # cl-weave regression suite, via the cl-weave CLI
sbcl --script run-tests.lisp  # requires cl-weave on CL_SOURCE_REGISTRY
nix flake check               # full verification suite
nix fmt                       # format Nix sources (treefmt)
```

`nix flake check` also runs the structural parse gate, the examples check, and
the documentation build. The full testing workflow — including the ASDF
fallback for unsupported platforms and the `cl-prolog/weave` query helpers —
is on the [Testing](testing.md) page. For the plain SBCL command, ensure
`cl-weave` is discoverable through `CL_SOURCE_REGISTRY` as described there.

## Track new files before trusting `nix flake check`

Git-backed flake input selection drops untracked files *before* this
repository's own source filter runs. A new docs page, example, or test file
that exists only in a dirty worktree is therefore absent from every Nix build,
and `nix flake check` will pass without ever seeing it — or fail with a
confusing "file does not exist" from inside the sandbox.

```sh
git add path/to/new-file.lisp   # then re-run
nix flake check
```

## Structural refactors

`nix develop` puts [paredit](https://github.com/nerima-lisp/paredit-cli) on
`PATH`. Prefer it over hand-editing parentheses for renames, moves, and other
structural changes to Lisp sources:

```sh
paredit inspect check --file src/engine.lisp
paredit refactor rename-function --from old-name --to new-name --output json src/*.lisp
```

Run a plan or preview command without `--write` first, review the JSON, then
re-run with `--write`. `checks.paredit-lint` fails the build if any tracked
`.lisp` or `.asd` file stops being a balanced S-expression document.

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
the Nix build and the `checks.docs` gate. The published site deploys to
GitHub Pages from `.github/workflows/docs.yml` on every push to `main` that
touches `docs/`, `flake.nix`, `flake.lock`, or the workflow itself.

## Design constraints

- no runtime dependencies, SBCL-tested, ANSI-leaning core
- a single canonical public API surface

See [Release Checklist](release-checklist.md) for the evidence bar a change must
clear before shipping.
