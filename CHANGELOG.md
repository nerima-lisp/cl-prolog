# Changelog

All notable changes to `cl-prolog` are recorded in this file.

The format follows a simple Keep a Changelog style.  Unreleased work
accumulates in an `Unreleased` section at the top of the file, which is renamed
to the version being cut at release time.

## 1.0.1 - 2026-07-26

### Fixed

- **A malformed Lisp-shape rule no longer terminates the query with a Lisp
  error.** When `asserta/1`, `assertz/1` or `retract/1` received the Lisp clause
  shape `(:- HEAD . BODY-GOALS)` with a head that is not callable — say
  `(assertz (:- 42 (color a red)))` — the branch that builds the ISO
  `type_error(callable, Culprit)` named an unbound variable as the culprit.
  Instead of the standard error, the query died with an SBCL
  `UNBOUND-VARIABLE`, which no `catch/3` and no `prolog-type-error` handler can
  intercept. The culprit is now the offending head, and the same input raises
  `prolog-type-error` as ISO 13211-1 8.9.1.3 requires.
- **A rule whose head is a bare atom is now accepted in both spellings of a
  clause.** `assertz((warm :- color(a, red)))`, the `:-`/2 term Prolog source
  reads, normalizes its head through the same path a list head takes, so it
  asserts `warm/0`. The Lisp shape `(assertz (:- warm (color a red)))` tested
  the raw head instead and rejected it, even though the documentation describes
  the two shapes as asserting a rule either way. Both now store the identical
  clause, and `clause/2` reports the same body for each.
- **An uninstantiated head in the Lisp clause shape raises an
  instantiation_error.** `(assertz (:- ?head (color a red)))` reached the same
  broken culprit expression; it now signals `prolog-instantiation-error`,
  matching how a bare `assertz(X)` is already handled.

The `:-`/2 branch that reads a rule from Prolog source text was never affected;
these three defects were confined to the engine's internal Lisp clause shape,
which is why the ISO conformance suite did not reach them. `tests/builtin-
dynamic-database.lisp` now covers all three, asserting the specific condition
class — a bare "signals something" expectation accepts the Lisp `UNBOUND-VARIABLE`
just as readily as the ISO error and would not have caught the original defect.

## 1.0.0 - 2026-07-25

First stable release: the exported surface is now considered stable.

This release fixes the ISO 13211-1 conformance defects a first systematic audit
of the standard's syntax and builtin error contracts turned up — reachable from
ordinary Prolog source text, and each now covered by
`tests/iso-conformance.lisp`, which states its cases as the standard does.

### Fixed

- **atoms are now identified by their text**, as ISO 13211-1 6.4.2 requires.
  Quoting an atom used to produce a *different* atom — `hello == 'hello'` was
  false — because an unquoted name was interned upcased while a quoted one kept
  its spelling. The two encodings now live in different packages
  (`cl-prolog.verbatim-atoms` holds any text containing an upper-case letter),
  which makes the text/symbol mapping a bijection, and `=/2`, `==/2`,
  `compare/3` and `sort/2` all decide identity on text. Consequences, each a
  behavior change:
    - `writeq/1` and `print/1` no longer lose case: `'FooBar'` printed as
      `foobar`, so `term_to_atom/2` could not round-trip a mixed-case atom
    - `atom_codes/2`, `atom_chars/2`, `char_code/2`, `atom_string/2`,
      `upcase_atom/2`, `downcase_atom/2`, `char_type/2` and `format/2`'s `~a`
      and `~s` report the atom's text rather than its upcased symbol name —
      `atom_codes(abc, X)` gave `[65,66,67]` and `format("~a", [hello])`
      printed `HELLO`
    - the standard order of terms ranks atoms by their characters (ISO 7.2.3),
      so `'B' @< a` holds; it previously compared upcased symbol names, then
      home packages, then creation order, which also let `X == Y` be false for
      a pair `X = Y` unified
    - `[]` is the atom of text `"[]"`: `[] == '[]'` and `atom_length([], 2)`
    - `char_conversion/2` and `open/3` receive the character and pathname their
      argument spells, not an upcased one
  New exported `prolog-atom` and `prolog-atom-text` name an atom by its text
  from Lisp, which is now the only way to write one whose text is not lower
  case; see [Semantics](docs/src/semantics.md#atoms).
- **an atom that is an operator can now be written as a term**, per ISO 6.3.3.1
  (as an argument) and 6.3.4.3 (bracketed). `functor(T, +, 2)`,
  `T =.. [+, 1, 2]`, `X = (-)`, `atom_length(-, 1)`, `current_op(P, T, +)`,
  `compare(<, A, B)` and `sort(0, @<, L, S)` all raised a syntax error, which
  made `op/3`, `sort/4`, `predsort/3` and `compare/3` unusable from Prolog
  source. An operator with no operand after it now reads as its atom; an
  operator used unbracketed as another operator's left operand still does not,
  as ISO requires the brackets there
- **a run of graphic characters is now one token**, per ISO 6.4.2, and an
  undeclared one is an atom. The tokenizer matched the longest *declared*
  operator instead, so `:- op(700, xfx, ===).` — declaring an operator that by
  definition does not exist yet — split `===` into `==` and `=` and failed to
  parse
- **`assertz/1`, `asserta/1`, `retract/1` and `retractall/1` now convert a
  `:-`/2 term to a clause**, per ISO 7.6.1. Only the Lisp-level
  `(:- HEAD . BODY-GOALS)` shape was recognized, so `assertz((h :- Body))` from
  Prolog source stored the whole `:-`/2 term as a *fact head* and left `h`
  undefined; runtime rule assertion was broken outright. `clause/2` returns the
  body in the shape source text spells it, and a fact matches
  `retract((h :- true))`
- **an atom is now quoted only when it cannot read back bare**, per ISO 6.4.2.
  `writeq/1`, `print/1`, `~q` and `write_canonical/1` quoted every atom that was
  not a plain atom name, so a graphic token printed as `'+'`, `'=..'`, `'@<'`,
  `'\+'` and the solo chars as `'!'`, `';'` — all of which are name tokens
  needing no quotes. Still quoted, each because the reader forces it: `,` and
  `|` (they would read back as separators), `{}` (not yet read as an atom), a
  lone `.` (the end token per ISO 6.4.8), and a compound's functor unless it is
  a plain name (this reader does not yet require `(` to follow a functor with no
  layout, so a bare `+(1,2)` would read as the prefix operator applied to
  `(1,2)`, and `write_canonical/1` output has to stay re-readable)
- **the lexer now reads the numeric notations of ISO 6.4.4**: the character-code
  constant `0'c` (including `0''`, `0'\n` and `0'\x41\`) and the radix constants
  `0x`, `0o`, `0b`. None of them parsed, so `X is 0'a` — the way a character code
  is written — was a syntax error, and so was reading a term containing one from
  a stream, since the source splitter also mistook `0'`'s quote for the start of
  a quoted atom
- **escape sequences in a quoted token are now decoded**, per ISO 6.4.2.1. A
  `\` passed the following character through verbatim instead, so `'a\nb'` held
  the letter `n` rather than a newline. `\a \b \e \f \n \r \t \v \0`, the radix
  forms `\xHH\` and `\OOO\`, `\\ \' \" \``, and the `\`-newline continuation are
  all honored, in `'...'` and `"..."` alike
- **the bitwise operators of ISO 6.3.4.4 table 7 are now declared**: `/\`, `\/`,
  `xor` at 500 yfx, `<<` and `>>` at 400 yfx, and prefix `\` at 200 fy. Their
  evaluable functors already existed, so `X is 1 << 3` and `X is 12 /\ 10` were
  computable but unwritable
- `asserta/1` and `assertz/1` **no longer accept an unbound argument**: they
  stored a clause whose head was a fresh variable, which no call could ever
  match, instead of raising the instantiation_error ISO 8.9.1.3 requires. A
  rule with a variable head is rejected the same way
- `compare/3` validates a bound Order argument (ISO 8.4.2.3): a non-atom is a
  `type_error(atom, _)` and an atom other than `<`, `=`, `>` a
  `domain_error(order, _)`, where both silently failed
- `clause/2` rejects a non-callable Body with `type_error(callable, _)` (ISO
  8.8.1.3) instead of failing, and `current_input/1` and `current_output/1`
  reject a non-stream argument with `domain_error(stream, _)` (ISO 8.11.1.3),
  which used to fail silently and hide a misspelled alias
- `number_chars/2` and `number_codes/2` raise `syntax_error/1` for text that
  spells no number, as ISO 8.16.7.3 and 8.16.8.3 require, rather than
  `domain_error(number_text, _)`; the `prolog-syntax-error` condition is now
  exported. `read_term_from_atom/3` validates its options through the same
  read-option checker `read_term/2,3` uses, so an unsupported option is a
  `domain_error(read_option, _)` instead of being accepted and ignored
- `atom_number/2` still fails rather than raising on unparseable text, and now
  decides that before running its continuation, so an error raised by a later
  goal is no longer mistaken for its own and swallowed
- a bare `{}` reads as the atom of that name (ISO 6.3.6)
- **`(If -> Then)` without an else branch now works.** ISO 7.8.7 makes if-then a
  control construct in its own right, which fails when the condition fails; only
  the if-then-*else* form had a solver, so the common `( Cond -> Then )` raised
  `existence_error(procedure, (->)/2)`. `(If *-> Then)` likewise
- **arithmetic now follows ISO 9.x where it had drifted**: `**` is 9.3.1's float
  power (`2 ** 3` is `8.0`) while `^` is 9.3.10's integer-preserving one (`2 ^ 3`
  is `8`), raising an integer to a negative integer power is
  `type_error(float, Base)`, and dividing two integers exactly stays integral
  (`4 / 2` was `2.0`). Float overflow and underflow reach Prolog as
  `evaluation_error(float_overflow)` / `(underflow)` instead of escaping as a
  host condition
- **stream and I/O error contracts corrected** across ISO 8.11-8.14: a
  designator that could never name a stream is `domain_error(stream_or_alias)`
  rather than `existence_error`; `open/3,4` reports a non-atom mode as
  `type_error(atom)`; `get_char/2` and `peek_char/2` reject a bound non-character
  argument with `type_error(in_character)` where they silently failed;
  `get_byte`/`put_byte` use `type_error(in_byte)` / `type_error(byte)` and check
  the argument *before* the stream, and the stream's permission error names the
  stream's actual type as the culprit (`text_stream`) rather than the required
  one; `write_term/2,3` reports an unsupported option in the `write_option`
  domain; and `current_char_conversion/2` rejects a non-character argument
- `char_code/2` raises `representation_error(character_code)` for an integer that
  names no character, per ISO 8.16.6.3, rather than a domain error; the
  `prolog-representation-error` condition is new and exported
- `current_prolog_flag/2` raises `domain_error(prolog_flag, F)` for an atom that
  names no flag (ISO 8.17.2.3) instead of failing
- one operator name now means one operator in the operator table, whichever
  symbol spells it, so redefining a standard operator through `op/3` replaces
  its entry instead of adding a second invisible one at a different priority
- `numbervars/3` uses the ISO 8.14.2 functor `'$VAR'`, whose text is upper
  case; the distinct lower-case atom `'$var'` is no longer written as a
  variable name
- CI: the SBCL check timeout now sends a follow-up `SIGKILL`, since SBCL can
  defer a bare `SIGTERM` past a tight compiled loop; `nix flake check`'s step
  now carries its own budget narrower than the job's, so a hang reports an
  attributable timeout instead of an ambiguous job cancellation
- CI: `packages.default` and `apps.test` (the two entry points README.md
  documents) are now actually built by `nix flake check`, not merely
  evaluated — `apps.test` in particular exercises a genuinely different code
  path (cl-weave's own dynamic-space sizing) that was previously untested
- CI: tag releases now require a green `nix flake check` on the tagged commit
  before publishing, closing a gap where a red `main` could still be tagged
  and released; the release workflow's `:version` extraction is now anchored
  the same way `flake.nix`'s already was, so a comment merely mentioning
  `:version` can no longer shadow the real field
- CI: a missing `CACHIX_CACHE` repository variable now emits a build warning
  instead of silently falling back to an uncached build with no other signal
- `docs.yml`'s path filter now includes `cl-prolog.asd`, so a version-only
  bump reliably retriggers a documentation rebuild

### Added

- `tests/atom-canonicalization.lisp`: the atom text/symbol bijection, quoting
  invisibility, case significance, `writeq` round-tripping (including a
  property test over generated mixed-case texts), text-based ordering, and the
  agreement of `=/2`, `==/2` and `compare/3`
- regression coverage for operator atoms as arguments, graphic-token lexing,
  and `:-`/2 clause conversion through `assertz`/`retract`/`clause`
- `.github/dependabot.yml` for the `github-actions` ecosystem (root workflows
  and the `setup-nix` composite action)
- `.github/workflows/benchmarks.yml`: runs the self-contained micro-benchmarks
  on `workflow_dispatch` and a weekly schedule only — never on push or pull
  request, consistent with benchmarks being diagnostic rather than a gate

### Changed

- split three of the largest source files along existing internal seams,
  with no behavior change: `data.lisp` into `logic-variable.lisp` /
  `clause.lisp` / `predicate-index.lisp` / `data.lisp`; `unification.lisp`
  into `environment-index.lisp` / `unification.lisp`; `prover.lisp` into
  `proof-state.lisp` / `prover.lisp`
- consolidated repeated macro-shaped code across the engine and builtins:
  duplicated constraint-hook and first-solution proof-search prologues in
  `prover.lisp`/`builtins/control.lisp`; the dual `:current`/`:explicit`
  stream builtin bodies in `builtins/io-streams.lisp`/`builtins/io-code.lisp`;
  the `aggregate_all/3` reducer dispatch, several scalar-argument guard
  checks, and three-way duplicated builtin triples across `builtins/*.lisp`;
  the runtime-error condition classes and their `%raise-*` wrappers now
  generate from one shared table instead of two hand-maintained lists
- removed an unused clause-indexing structure (four `rulebase` slots plus
  their maintenance code) that was superseded by the predicate-descriptor
  index and had no production reader; removed a vestigial cycle-detection
  parameter from the unification indexer left over from before the
  tortoise-and-hare occurs-check
- upgraded `cl-weave` `v0.4.0` → `v1.0.0` (additive; fixes an integer-shrinker
  bug and a swallowed-hook-timeout bug relevant to this suite) and pinned
  `paredit-cli` to `v0.7.0` (previously an unpinned input silently frozen
  three commits behind what it appeared to track)
- `src/weave.lisp`'s `:set` query-assertion kind now reports structured
  missing/unexpected solutions on failure via a `cl-weave:defmatcher`
  (`:to-solve`) instead of collapsing to a bare pass/fail boolean
- rewrote several `tests/*.lisp` cases to use the existing `deftest-queries`/
  `assert-query` helpers instead of hand-rolled `dolist`/`signals-condition`
  boilerplate, and added coverage for five previously-untested branches
  (string-scanner escape handling, `%text-of` coercion arms, `sub_string/5`'s
  fully-enumerated mode, a decimal-digit-limit boundary, and a `format/2`
  column directive)
- `flake.nix` now also builds on `aarch64-darwin`, verified locally end to
  end (`nix build`, `nix develop`, `nix flake check`) — the prior
  Linux-only restriction was self-imposed, not inherited from either flake
  input
- all in-repo `github.com/takeokunn/cl-prolog` references now point at
  `github.com/nerima-lisp/cl-prolog`, the project's current org

## 0.8.0 - 2026-07-25

### Added

- `library(assoc)`: `empty_assoc/1`, `put_assoc/4`, `get_assoc/3`,
  `del_assoc/4`, `list_to_assoc/2`, `assoc_to_list/2`, `assoc_to_keys/2`,
  `assoc_to_values/2` — association maps keyed by the standard order of terms
  (`builtins/assoc.lisp`)
- `library(pairs)`: `pairs_keys_values/3` (bidirectional), `pairs_keys/2`,
  `pairs_values/2` (`builtins/pairs.lisp`)
- `plus/3`, the integer relation `A + B =:= C` usable in any single-unknown
  mode
- a SWI-compatible **string** term type (represented as a Common Lisp string):
  the `double_quotes` flag gains a `string` value and is now honored by the
  reader (`"..."` produces codes/chars/atom/string per the flag); `string/1`
  and `atomic/1` classify strings; the standard order of terms places String
  between Atom and Compound; `==`/`compare` use content equality; and the term
  writer prints strings raw for `write` and as escaped `"..."` for
  `writeq`/`write_canonical`
- string builtins (`builtins/string.lisp`): `string_length/2`,
  `string_concat/3` (relational), `atom_string/2`, `string_to_atom/2`,
  `number_string/2`, `string_chars/2`, `string_codes/2`, `term_string/2`,
  `text_concat/3`, `sub_string/5`, `split_string/4`, plus the shared `%text-of`
  text-coercion helper
- an `occurs_check` Prolog flag (`true` default, `false`, `error`): `=/2`
  consults it — `false` allows a cyclic binding, `error` raises when a cycle
  would form; `unify_with_occurs_check/2` always checks; clause-resolution
  unification stays occurs-checked for safety
- regression suites `builtin-string` and `builtin-occurs-check`
- character classification `char_type/2` and `code_type/2` (simple types plus
  the `digit(W)`, `to_lower/1`, `to_upper/1`, `upper/1`, `lower/1`, `code/1`
  parametric types) and case folding `upcase_atom/2`, `downcase_atom/2`
  (`builtins/char-type.lisp`)
- `term_to_atom/2` (bidirectional term/text conversion) and
  `read_term_from_atom/3`, routing parser failures through catchable ISO
  `syntax_error`/`resource_error` (`builtins/term-io.lisp`)
- `sort/4` (key-and-order sort with `@<`/`@=<`/`@>`/`@>=`, key 0 = whole term),
  `predsort/3` (comparison-predicate sort dropping `=` duplicates), and
  `aggregate_all/3` (`count`, `count/1`, `sum`, `max`, `min`, `bag`, `set`)
  (`builtins/collection.lisp`)
- evaluable arithmetic functions `gcd/2`, `atan2/2`, `msb/1`, `lsb/1`,
  `popcount/1`, and the constant `e` (`builtins/arithmetic.lisp`)
- regression suites `builtin-char-type` and `builtin-term-io`, plus `sort/4`,
  `predsort/3`, `aggregate_all/3`, and arithmetic-function coverage
- `library(lists)` predicates: `sum_list/2` (with the `sumlist/2` alias),
  `max_list/2`, `min_list/2`, `numlist/3`, `list_to_set/2`, `subtract/3`,
  `intersection/3`, `union/3`, and `permutation/2` (`builtins/list-extra.lisp`)
- `library(apply)` meta-predicates driven through the CPS prover:
  `maplist/2` and up (variadic in the number of lists), `foldl/4..6`,
  `include/3`, `exclude/3`, and `partition/4` (`builtins/apply.lisp`); element
  goals are cut-opaque like `call/1`, and the filter predicates test
  provability only and do not leak their goal's bindings
- formatted output: `format/1,2,3` supporting the `~w ~p ~q ~a ~s ~d ~D ~f ~e
  ~g ~r ~R ~c ~n ~~` directives, the `` ~`c `` fill character, `~*`
  argument-supplied counts, and column control (`~t` fill, `~|` absolute
  column, `~+` relative column), plus `tab/1,2` and `print/1,2`
  (`builtins/format.lisp`); format strings may be atoms, code lists, character
  lists, or Common Lisp strings. `~p` quotes like `print/1`, and `~e`/`~g` use
  the C/Prolog exponent convention
- `*max-prolog-builtin-output-length*`: a configurable, exported bound on the
  characters or list elements a single builtin call may materialize, so
  `format` fill/repeat/newline runs, `tab/1`, and `numlist/3` ranges raise a
  catchable `resource_error` instead of exhausting memory on hostile input
- regression suites `builtin-list-extra` and `builtin-format` covering the new
  predicates, their error contracts, and resource bounds

### Security

- malformed `format` directives, out-of-range `~r` radices, invalid `~c`
  character codes, and too-few-argument errors now raise catchable ISO errors
  instead of escaping to the host as uncatchable Common Lisp conditions
- `numlist/3`, `tab/1`, and `format`'s repeat/fill/newline counts are bounded
  against `*max-prolog-builtin-output-length*`, closing unbounded-allocation
  denial-of-service vectors reachable from untrusted queries
- `char_type/2`, `code_type/2`, `sort/4`, and `aggregate_all/3` guard their
  compound arguments with a proper-list check before measuring length, so a
  partial list (e.g. `char_type(a, [x|y])`) raises a catchable ISO error
  instead of an uncatchable host `type_error`
- the `<<` left-shift arithmetic result size is now bounded against
  `*max-prolog-arithmetic-result-bits*` (like `**`/`^`), so `1 << huge` raises
  a catchable `resource_error` instead of allocating an unbounded bignum (`>>`
  only shrinks the result and needs no bound)

### Changed

- the term writer is now cycle-safe: it marks each cons on the current path and
  emits `...` on revisiting one, so writing a cyclic term (which the
  `occurs_check=false` flag lets a user build) terminates instead of recursing
  forever; acyclic shared subterms still print in full
- `list_to_set/2` deduplicates in O(n log n) via an index-tagged standard-order
  sort instead of the previous O(n^2) linear scan, preserving first-occurrence
  order
- `aggregate_all/3` evaluates the `sum`/`max`/`min` template as an arithmetic
  expression (so `sum(X*2)` works), matching SWI
- `predsort/3` fails (rather than raising) when its comparison predicate has no
  proof, matching SWI; its merge step is iterative to keep the control stack
  O(log n) on large lists
- `char_type/2`/`code_type/2` `graphic` now denotes the Prolog symbol-char
  class (distinct from `graph`)

## 0.7.0 - 2026-07-24

### Added

- an SLG tabling engine (`table-variant.lisp`, `tabling.lisp`): variant-check
  keys, per-query table sessions, answer tables, and fixpoint iteration,
  threaded through the proof-state continuation so builtin-dispatched goals
  inherit the active tabling context
- a benchmarks harness (`benchmarks/`): in-process micro-benchmarks and a
  cross-engine comparison script against SWI-Prolog, Trealla, and Scryer
  Prolog on a shared, checksum-verified workload
- a CI matrix covering `x86_64-linux` and `aarch64-linux`

### Changed

- `get_code`/`peek_code` track end-of-stream identically to
  `get_char`/`peek_char` per ISO 8.11.3/8.11.4; stream alias validation is
  shared across the IO builtins
- goal-dispatch and DCG expansion hardened; finite-domain constraint
  handling refined
- environment indexing in unification uses a bounded overlay over an
  immutable base table instead of a full rehash on every binding, avoiding
  an O(n) rebuild per variable binding
- the parser, term/atom builtins, and source-loader were split into focused
  modules (lexer/grammar layers, term-inspect/compare/construct,
  atom-ops/text-conversion/atom-number-conversion,
  source-io/directives/registry/rollback) with no behavior change
- the regression suite was reorganized into thematic files (engine-runtime
  index-and-depth/foreign-and-registration/error-contract,
  builtin-collections/list/dynamic-database/arithmetic-and-flags) with a
  shared query helper lifted into `tests/support/core.lisp`
- documentation (architecture, API reference, builtin goals, querying,
  semantics, development, troubleshooting) synced with the module split and
  the new tabling and benchmarking surfaces

## 0.6.0 - 2026-07-19

### Added

- parser resource limits exported as configurable specials
  (`*max-prolog-source-characters*`, `*max-prolog-tokens*`,
  `*max-prolog-parser-depth*`, `*max-prolog-delimiter-depth*`,
  `*max-prolog-identifier-length*`, `*max-prolog-quoted-lexeme-length*`,
  `*max-prolog-numeric-lexeme-length*`, `*max-prolog-interned-symbols*`)
  with a new `prolog-parser-resource-error` condition, surfaced to Prolog
  code as catchable ISO `resource_error/1` terms

### Changed

- quoted `?`-prefixed atoms such as `'?x'` are now real atoms interned in
  `cl-prolog.user-atoms` instead of being misread as logic variables
- goal dispatch validates goals per ISO: variable goals raise
  `instantiation_error` and non-callable or improper-list goals raise
  `type_error`
- untrusted input no longer permanently interns symbols: syntax-error
  descriptions, missing-source pathnames, stream handles, operator
  specifiers, and arithmetic operator keys use uninterned symbols or table
  lookups; exponentiation results are bounded
- unification environments are hash-indexed and substitution is iterative,
  `assertz` and tabled-answer deduplication are O(1), left recursion is
  detected via strongly connected components, `bagof`/`setof` grouping is
  O(n log n), and `all_different` uses augmenting-path matching
- documentation matches the shipped API: real install/run instructions
  (cl-prolog is not on Quicklisp), accurate `phrase`/`phrase-all` and
  `unify` contracts, the complete exported-symbol reference, Linux-only
  flake outputs stated explicitly, and concrete security-reporting and
  code-of-conduct procedures

### Fixed

- parsed finite-domain ranges work: `X in 1..5` produced the prefix term
  `('..' 1 5)`, which the finite-domain store rejected; both the parsed
  prefix and Lisp-shaped infix range forms are now accepted
- closing the stream selected as `current_input`/`current_output` resets
  the selection to `user_input`/`user_output` instead of leaving a dangling
  stream entry
- `member/2` and `append/3` terminate on cyclic lists, and cyclic source
  lists passed to `consult`/`load_files` raise a resource error instead of
  looping
- a `.` inside `{...}` no longer ends a clause early during source
  splitting
- finite-domain arithmetic expressions no longer raise program errors from
  an outdated internal call site

## 0.5.0 - 2026-07-13

### Added

- predicate indexing for faster clause selection, with behavior preserved for
  variables, cyclic terms, dynamic predicates, and module-qualified calls
- explicit tabling, depth-limited calls, cyclic-term predicates, finite-domain
  helpers, and additional control and collection predicates
- broader ISO conformance coverage for arithmetic, meta-calls, modules,
  streams, term reading, exceptions, and relational list operations

### Changed

- CI and supported Nix flake systems now target Linux only; GitHub Actions runs
  the complete checks on Ubuntu
- module, query, depth-limit, constraint, dynamic-predicate, and stream state
  handling now preserve their execution context consistently
- documentation now covers the expanded runtime surface, Linux-only CI, and
  current release verification workflow

### Fixed

- unification, substitution, and query projection terminate safely for cyclic
  terms
- qualified and meta-callable goals now validate bindings, visibility, arity,
  and error terms consistently
- `length/2`, finite-domain equality, Prolog number recognition,
  `read_term/3` singleton reporting, and end-of-stream transitions now follow
  their intended relational or ISO semantics

## 0.4.1 - 2026-07-12

### Changed

- the stream read/write builtins (`read`/`read_term`, `write`-family, `nl`,
  `flush_output`, character/byte I/O, `at_end_of_stream`) moved from
  `io.lisp` into the new `io-streams.lisp`, defined through a shared
  `%define-io-dual-builtin` macro that derives the current-stream and
  explicit-stream variants from one specification; the macro validates its
  clause plist at macroexpansion time so a malformed definition fails the
  build instead of compiling a builtin that silently always fails
- `%io-options` and `%io-read-options` share one option-list parser
  (`%io-parse-option-list`) instead of two divergent copies
- `query-prolog` and `query-prolog-first` reuse the solution-mapping core
  of `map-prolog-solutions` instead of re-decoding their options through
  the public entry point
- `deftest-table` / `deftest-unification` expand each table spec into its
  own named cl-weave case, so a failing spec is reported individually

### Added

- a regression test that `read_term/2` rejects unsupported read options
  with an ISO domain error

## 0.4.0 - 2026-07-12

### Added

- the remaining ISO 13211-1 built-ins: `open/3`, `write_canonical/1,2`,
  `halt/0,1` (raising the exported `prolog-halt` condition so embedders
  choose how to exit; `catch/3` does not intercept it), `char_conversion/2`,
  and `current_char_conversion/2`; conversions are rulebase-local and apply
  during `read_term` and `consult` when the `char_conversion` flag is `on`,
  leaving quoted tokens untouched
- the remaining ISO source directives: `include/1` splices the included
  file's terms into the including source unit, `set_prolog_flag/2` and
  `char_conversion/2` execute during loading and affect subsequent terms,
  and `discontiguous/1` / `multifile/1` declarations are validated and
  accepted (the engine already resolves clauses independently of textual
  grouping)

- cl-weave (Vitest-shaped) testing library integration: the new
  `cl-prolog/tests` ASDF system exercises the public engine surface with
  `describe` / `it` / `expect` suites (unification, family relations, list and
  control-flow builtins, goal validation)
- `flake.nix` gains a `cl-weave` input and a `cl-prolog/tests` check, so
  `nix flake check` runs the complete ASDF suite locally and in CI with no
  project-local runner
- `flake.nix` gains a `paredit-cli` input: `nix develop` puts the `paredit`
  structural S-expression CLI on `PATH` for renames, moves, and other
  refactors of Lisp sources, and `checks.paredit-lint` fails `nix flake
  check` if any tracked `.lisp`/`.asd` file is not a balanced S-expression
  document

### Changed

- Prolog flag names use their ISO spellings (`max_arity`,
  `integer_rounding_function`, `char_conversion`, `double_quotes`), and
  `integer_rounding_function` reports `toward_zero`, matching the
  `truncate`-based `//`
- `define-builtin` no longer emits a per-call arity re-check: solver
  dispatch already guarantees the arity, so the check was unreachable
- cut (`!`) is now implemented with `CATCH`/`THROW` tags carried through the
  proof state instead of dynamically-scoped condition handlers, so a cut in a
  clause body correctly prunes both the alternatives of goals to its left and
  the remaining clauses of its own predicate — without leaking through
  predicate invocations that merely run in its continuation
- `and`, `or`, and the taken branch of `->` / `*->` are transparent to cut,
  while `call/1`, `once/1`, `\+/1`, `findall`-family goals, `catch/3`, and the
  condition of `->` keep cuts local, matching ISO
- calling a builtin name at an unsupported arity (e.g. `=/1`) signals the ISO
  `existence_error` for that predicate indicator instead of an engine-specific
  arity error

### Fixed

- the bitwise arithmetic operator names `\\`, `/\\`, and `\\/` and the
  `\\+` / `\\==` exports were written with a single backslash inside
  multiple-escape bars, which the reader treats as an escaped `|`; the
  runaway token silently swallowed the entire binary arithmetic table, so
  every `is/2` query over a binary operator died on an unbound table
- `atan/2` now checks both operands are real and evaluates in double-float,
  so `atan(0, -1) =:= pi` holds
- `stream_property/2` no longer crashes computing `end_of_stream` for input
  streams (an internal helper was called with the wrong argument count)
- `(and true !)`-style conjunctions whose first goal is a bare atom are no
  longer misread as a single compound goal

## 0.2.0 - 2026-07-10

Engine and API overhaul. The public surface was re-cut to the ideal API;
compatibility aliases were removed rather than deprecated.

### Added

- `map-prolog-solutions`: streaming query primitive exposing the engine's
  CPS contract directly (per-solution callback, `:limit`, `:project`,
  `:environment`, `:max-depth`)
- `:limit` keyword on `query-prolog`; `query-prolog-first` and
  `prolog-succeeds-p` now stop searching at the first proof
- `define-builtin`: public, arity-checked registry for builtin goal solvers;
  the head name may be a list of aliases (used by `!=` / `/=`)
- `invalid-goal-error` condition (with `invalid-goal-error-goal` reader) for
  malformed goals: wrong builtin arity, non-callable goal terms, and
  non-function `:when` guards now fail fast instead of failing silently
- `fresh-logic-variable` for writing custom builtins
- compiled `(:when EXPR)` guards: the `prolog` / `def-rule` / DCG `brace`
  macros compile guard expressions into closures over their logic variables
- `phrase` returns `(values remainder matched-p)`, distinguishing "no parse"
  from "full parse"
- table-driven test DSL (`deftest-queries`) and a broader regression suite
  (goal shapes, cut semantics, clause ordering, streaming, extensibility)
- GitHub Actions CI running tests and the benchmark smoke
- `.github` community files and CI badge in `README.md`

### Changed

- sources moved from the repository root to `src/`, split by concern:
  `engine.lisp` now holds only the CPS provers and builtin registry, with
  builtins in `builtins.lisp`, DCG runtime in `dcg-runtime.lisp`, and the
  query API in `query.lisp`
- builtin and DCG solvers now stream through `EMIT` continuations end to end
  instead of collecting intermediate solution lists
- cut is structured around `%with-cut-barrier` / `%propagate-cut` with
  documented semantics: facts before rules, cut prunes the running clause's
  choice points and the predicate's remaining rule clauses
- variables inside facts are freshly renamed per use, fixing binding leaks
  across goals (`((same ?x ?x))` used to contaminate later goals)
- `unify` failure is now `(values nil nil)`; the `:unify-fail` sentinel is
  gone
- `prolog-match` documents fall-through to `nil`; `extend-rulebase` no
  longer copies clause lists it freshly consed

### Removed (breaking)

- `substitute-term` (use `logic-substitute`)
- `*max-proof-depth*` (use `*max-prolog-depth*`)
- `unify-failed-p`, `when-unify-succeeds`, `when-unify-fails`
  (use the two-value protocol of `unify`)
- `query-prolog-cps`, `prolog-succeeds-p-cps`
  (use `map-prolog-solutions`; the old functions were collect-then-callback
  wrappers, not CPS)
- runtime evaluation of `(:when EXPR)` goals in query data: `:when` now
  requires a function object; expression guards belong in the DSL macros

## 0.1.0 - 2026-07-09

Initial release: macro-first rulebase DSL, CPS proof search, builtin goals,
DCG support, examples, benchmark scenarios, Nix packaging, and repository policy files
(`SECURITY.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `CONTRIBUTING.md`,
release checklist and troubleshooting documentation).
