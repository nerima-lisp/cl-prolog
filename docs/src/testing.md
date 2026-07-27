# Testing

cl-prolog's regression suite is the `cl-prolog/test` ASDF system. It depends on
[cl-weave](https://github.com/nerima-lisp/cl-weave) and covers isolated table
cases, per-query cases, fixtures, and generated relational properties.

## Run the suite

The Nix runner is self-contained and is the authoritative path on supported
systems (`x86_64-linux`, `aarch64-darwin`):

```sh
nix run .
```

Pass any cl-weave CLI options after `--`; for example, to produce a JSON result:

```sh
nix run . -- --reporter json --output cl-prolog-weave-results.json
```

The full verification suite — including packaging, examples, the docs build,
and the structural parse gate — is:

```sh
nix flake check
```

!!! info "Unsupported platforms"
    On platforms outside the two supported systems (e.g. Intel Mac,
    Windows), ensure `cl-weave` is discoverable through ASDF and run the
    suite directly:

    ```sh
    sbcl --script run-tests.lisp
    ```

    Then rely on CI for the Nix `nix flake check` path.

## What `nix flake check` runs

- **`checks.default`** — the cl-weave regression suite, run through
  `run-tests.lisp` under a plain SBCL with the compiled-in default dynamic
  space.
- **`checks.paredit-lint`** — a structural parse gate over every tracked
  `.lisp`/`.asd` file, failing if any is not a balanced S-expression document.
- **`checks.examples`** — loads every shipped example through ASDF
  ([Examples](examples.md)).
- **`checks.docs`** — builds the MkDocs site with `--strict` and fails if it
  does not produce a valid `index.html`.
- **`checks.formatting`** — checks every Nix file against `nixfmt`, via
  treefmt. `nix fmt` fixes what it reports.
- **`checks.package`** — builds `packages.default`, so the package README.md
  advertises (`nix run github:nerima-lisp/cl-prolog`) is actually realised,
  not merely evaluated.
- **`checks.app-test`** — runs `apps.test`, the cl-weave CLI wrapper (a
  distinct code path from `checks.default`: it sets a 4096 MB dynamic space).
- **`checks.coverage`** — builds `packages.coverage` and asserts it produced a
  report; it does not gate on a coverage percentage.

## Coverage

`packages.coverage` runs the regression suite under `sb-cover`, instrumenting
only `cl-prolog` and `cl-prolog/weave` (not the `cl-weave` harness driving
them), and writes an HTML report. Its runner is embedded in `flake.nix` with
`pkgs.writeText`, so it does not read the source-tree `run-coverage.lisp`:

```sh
nix build .#coverage
open result/cover-index.html
```

Outside Nix, `run-coverage.lisp` remains the direct SBCL entry point. With
`cl-weave` discoverable through `CL_SOURCE_REGISTRY`:

```sh
sbcl --script run-coverage.lisp coverage/
```

This is a visibility tool, not an enforced gate: `checks.coverage` fails only
if the report fails to build, not if coverage drops.

## Query test helpers

Load the `cl-prolog/weave` ASDF system to use the public query test helpers:

```lisp
(asdf:load-system :cl-prolog/weave)
```

`deftest-queries` creates an independent cl-weave case and a fresh rulebase for
every query. A leading case label is optional; without one, the printed query is
used.

```lisp
(cl-prolog/weave:deftest-queries family-queries ((make-family-rulebase))
  ("keeps proof order" (parent alice ?child) :ordered
   (((?child . bob)) ((?child . carol))))
  ((parent alice ?child) :set
   (((?child . carol)) ((?child . bob))))
  ((parent alice ?child) :first ((?child . bob)))
  ((parent alice bob) :succeeds)
  ((parent bob alice) :fails)
  ((parent alice bob) :signals cl-prolog:invalid-max-depth-error
   :max-depth :invalid))
```

Assertion kinds:

- `:ordered` — compares the full solution sequence, order included.
- `:set` — ignores only the order of complete solutions; it still compares the
  structure within each solution with `equal`.
- `:first` — compares the first solution's bindings.
- `:succeeds` / `:fails` — assert provability without inspecting bindings.
- `:signals` — asserts a condition is raised, optionally of a given type.

Query options (such as `:max-depth`) follow the expected value or assertion
kind.

Use `assert-query` inside an existing cl-weave case when a table is not needed:

```lisp
(cl-weave:it "finds Alice's first child"
  (cl-prolog/weave:assert-query (make-family-rulebase)
    (parent alice ?child) :first ((?child . bob))))
```

## See also

- [Development](development.md) — the development environment and workflow.
- [Benchmarks](benchmarks.md) — the diagnostic performance harness.
- [Release Checklist](release-checklist.md) — the evidence bar for shipping.
