# Benchmarks

The `benchmarks/` directory holds diagnostic performance tools. They are **not**
part of `nix flake check` or the regression suite — they exist to measure and
compare, not to gate releases.

## In-process micro-benchmarks

`benchmarks/performance.lisp` runs micro-benchmarks and reports
warm-steady-state timing and allocation per operation:

```sh
sbcl --script benchmarks/performance.lisp
```

It covers:

- alias-chain resolution,
- predicate and first-argument indexing,
- recursive path queries,
- branching path queries.

Each is measured after warm-up so the numbers reflect steady state rather than
first-call compilation.

## Cross-engine comparison

`benchmarks/external-comparison.sh` cross-checks cl-prolog against
[SWI-Prolog](https://www.swi-prolog.org/),
[Trealla](https://github.com/trealla-prolog/trealla), and
[Scryer Prolog](https://github.com/mthom/scryer-prolog) on a shared workload
(`benchmarks/external-workload.pl` and `benchmarks/external-cl-prolog.lisp`):

```sh
ITERATIONS=5000 benchmarks/external-comparison.sh
```

Before comparing wall-clock time, it verifies that **every engine returns an
identical solution count, checksum, and fingerprint** — a correctness gate that
prevents comparing engines that disagree on the answer. It shells out to
`nix shell nixpkgs#{swi-prolog,trealla,scryer-prolog}`, so it requires Nix and
network access to the binary cache. Each engine run is capped at 60 seconds per
iteration count.

!!! note "Diagnostic, not a gate"
    These scripts are tools for investigating performance regressions and
    cross-engine parity. They are intentionally excluded from the verification
    suite so that CI does not depend on external Prolog binaries or timing
    stability.

## See also

- [Testing](testing.md) — the regression suite and query helpers.
- [Architecture](architecture.md) — the proof-state prover the benchmarks
  measure.
