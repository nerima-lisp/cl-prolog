# Changelog

The authoritative, always-current changelog lives at the repository root:

- [CHANGELOG.md on GitHub](https://github.com/takeokunn/cl-prolog/blob/main/CHANGELOG.md)

It follows a
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)-style format with an
`Unreleased` section at the top. The highlights below summarize recent releases;
consult the full file for the complete, per-entry history.

!!! info "Why this page is a summary"
    The documentation site builds from `docs/` in an offline sandbox and cannot
    embed the root `CHANGELOG.md` directly. To avoid drift, this page links to
    the source of truth and lists only headline changes.

## Unreleased

- **`library(lists)`** predicates: `sum_list/2` (with the `sumlist/2` alias),
  `max_list/2`, `min_list/2`, `numlist/3`, `list_to_set/2`, `subtract/3`,
  `intersection/3`, `union/3`, and `permutation/2`.
- **`library(apply)`** meta-predicates driven through the CPS prover:
  `maplist/2..5`, `foldl/4..6`, `include/3`, `exclude/3`, and `partition/4`.
  The filter predicates test provability only and do not leak their goal's
  bindings.
- **Formatted output**: `format/1,2,3` with the `~w ~p ~q ~a ~s ~d ~D ~f ~e ~g
  ~r ~R ~c ~n ~~` directives and column control (`~t`, `~|`, `~+`), plus
  `tab/1,2` and `print/1,2`.
- New regression suites `builtin-list-extra` and `builtin-format`.

## 0.7.0 — 2026-07-24

- An **SLG tabling engine**: variant-check keys, per-query table sessions,
  answer tables, and fixpoint iteration, threaded through the proof-state
  continuation.
- A **benchmarks harness**: in-process micro-benchmarks and a cross-engine
  comparison script against SWI-Prolog, Trealla, and Scryer Prolog on a shared,
  checksum-verified workload.
- A CI matrix covering `x86_64-linux` and `aarch64-linux`.

## 0.6.0 — 2026-07-19

- Stream I/O and term-reading predicates, including `read_term/3` support for
  `variable_names/1` and `singletons/1`, and `stream_property/2` end-of-stream
  reporting.

## Earlier releases

`0.5.0`, `0.4.1`, `0.4.0`, `0.2.0`, and `0.1.0` established the parser, the
core builtin set, the module system, the transactional source loader, DCG
support, and the public query API. See the full
[CHANGELOG.md](https://github.com/takeokunn/cl-prolog/blob/main/CHANGELOG.md)
for details.

## See also

- [Release Checklist](release-checklist.md) — the evidence bar for shipping.
- [Repository Documentation](repository.md) — contributing and policy files.
