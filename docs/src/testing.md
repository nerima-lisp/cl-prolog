# Testing

cl-prolog's regression suite is the `cl-prolog/tests` ASDF system. It depends on
[cl-weave](https://github.com/nerima-lisp/cl-weave) and covers isolated table
cases, per-query cases, fixtures, and generated relational properties.

## Run the suite

The Nix runner is self-contained and is the authoritative path on supported
systems (`x86_64-linux`, `aarch64-linux`):

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
    On platforms outside the three supported systems (e.g. Intel Mac,
    Windows), ensure `cl-weave` is discoverable through ASDF and run the
    suite directly:

    ```sh
    sbcl --non-interactive \
      --eval '(require :asdf)' \
      --load cl-prolog.asd \
      --eval '(asdf:test-system :cl-prolog)'
    ```

    Then rely on CI for the Nix `nix flake check` path.

## What `nix flake check` runs

- **`checks.default`** — the ASDF/cl-weave regression suite, via a plain SBCL
  invocation with the compiled-in default dynamic space.
- **`checks.paredit-lint`** — a structural parse gate over every tracked
  `.lisp`/`.asd` file, failing if any is not a balanced S-expression document.
- **`checks.examples`** — loads every shipped example through ASDF
  ([Examples](examples.md)).
- **`checks.documentation`** — builds the MkDocs site and fails if it does not
  produce a valid `index.html`.
- **`checks.formatting`** — checks `flake.nix` against `nixpkgs-fmt`.
- **`checks.package`** — builds `packages.default`, so the package README.md
  advertises (`nix run github:nerima-lisp/cl-prolog`) is actually realised,
  not merely evaluated.
- **`checks.app-test`** — runs `apps.test`, the cl-weave CLI wrapper (a
  distinct code path from `checks.default`: it sets a 4096 MB dynamic space).

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
