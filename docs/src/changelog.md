# Changelog

The authoritative, always-current changelog lives at the repository root:

- [CHANGELOG.md on GitHub](https://github.com/nerima-lisp/cl-prolog/blob/main/CHANGELOG.md)

It follows a
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/)-style format. The
highlights below summarize recent releases; consult the full file for the
complete, per-entry history.

!!! info "Why this page is a summary"
    The documentation site builds from `docs/` in an offline sandbox and cannot
    embed the root `CHANGELOG.md` directly. To avoid drift, this page links to
    the source of truth and lists only headline changes.

## 1.0.1 - 2026-07-26

Three defects in the engine's internal Lisp clause shape `(:- HEAD . BODY-GOALS)`,
all in the same branch of the assert/retract clause converter. The `:-`/2 term
Prolog source text reads was never affected, which is why the ISO conformance
suite did not reach them.

- **A malformed rule raised a Lisp error instead of the ISO one.** Building the
  `type_error(callable, Culprit)` for a non-callable head named an unbound
  variable, so `(assertz (:- 42 (color a red)))` died with an SBCL
  `UNBOUND-VARIABLE` that no `catch/3` or `prolog-type-error` handler could
  intercept. It now raises `prolog-type-error`.
- **A bare atom head is accepted in both spellings of a clause.**
  `assertz((warm :- color(a, red)))` asserts `warm/0`; the Lisp shape
  `(assertz (:- warm (color a red)))` rejected the same rule. Both now store
  the identical clause — see [Builtin Goals](builtin-goals.md).
- **An uninstantiated head raises an instantiation_error**, matching how a bare
  `assertz(X)` is already handled.

## 1.0.0 - 2026-07-25

First stable release: the exported surface is now considered stable. It fixes
the ISO 13211-1 conformance defects a first systematic audit of the standard's
syntax and builtin error contracts turned up, all reachable from ordinary Prolog
source text and now covered by `tests/iso-conformance.lisp`.

- **An atom is its text.** Quoting an atom used to yield a *different* atom, so
  `hello == 'hello'` was false. With the text/symbol mapping now a bijection,
  quoting is invisible and case is significant, and `=/2`, `==/2`, `compare/3`
  and `sort/2` agree on atom identity. This changes existing output:
  `writeq/1` keeps an atom's case, the text-conversion builtins and `format/2`'s
  `~a`/`~s` report the text rather than an upcased symbol name, the standard
  order ranks atoms by their characters, and `[] == '[]'`. New exported
  `prolog-atom` and `prolog-atom-text` name an atom by its text from Lisp —
  see [Semantics](semantics.md#atoms).
- **An atom that is an operator can be written as a term**, as an argument or
  bracketed. `functor(T, +, 2)`, `compare(<, A, B)` and `sort(0, @<, L, S)`
  previously raised a syntax error, which made `op/3`, `sort/4`, `predsort/3`
  and `compare/3` unusable from Prolog source.
- **A run of graphic characters is one token**, and an undeclared one is an
  atom, so `:- op(700, xfx, ===).` parses instead of splitting `===` apart.
- **`assertz/1` and friends convert a `:-`/2 term to a clause.** Runtime rule
  assertion from Prolog source stored the whole term as a fact head and left
  the predicate undefined.
- **An atom is quoted only when it cannot read back bare**, so a graphic token
  now prints as `+`, `=..`, `@<`, `\+` rather than quoted. `,`, `|`, a lone `.`,
  and a compound's non-plain functor stay quoted, each because the reader would
  otherwise read the output back as something else.
- **The lexer reads the ISO 6.4.4 numeric notations** `0'c`, `0x`, `0o`, `0b`,
  and **decodes escape sequences** (ISO 6.4.2.1) in `'...'` and `"..."`, so
  `X is 0'a` parses and `'a\nb'` holds a newline rather than the letter `n`.
- **The bitwise operators of ISO 6.3.4.4 table 7 are declared** (`/\`, `\/`,
  `xor`, `<<`, `>>`, prefix `\`); their evaluable functors existed but had no
  written form.
- **`(If -> Then)` without an else branch works.** ISO 7.8.7 makes if-then its
  own control construct; only the if-then-*else* form had a solver, so the
  common `( Cond -> Then )` raised `existence_error`.
- **Arithmetic follows ISO 9.x**: `**` is the float power and `^` the
  integer-preserving one, exact integer division stays integral, and float
  overflow is a catchable `evaluation_error` rather than a host condition.
- **Error contracts corrected** across the builtins, wherever one failed
  silently or accepted nonsense — `asserta/1` no longer stores a clause with a
  variable head, and `compare/3`, `clause/2`, the stream and character/byte I/O
  predicates, `write_term/2,3`, `char_code/2`, `current_prolog_flag/2`,
  `number_chars/2` and `number_codes/2` now raise what the standard specifies.
  `prolog-syntax-error` and the new `prolog-representation-error` are exported.

## 0.8.0 - 2026-07-25

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
[CHANGELOG.md](https://github.com/nerima-lisp/cl-prolog/blob/main/CHANGELOG.md)
for details.

## See also

- [Release Checklist](release-checklist.md) — the evidence bar for shipping.
