# External ISO conformance corpus

`inriasuite/` is the **INRIA ISO conformance test suite**, vendored verbatim
(version 0.9, 1999). It is not written here, which is the point: it is an
independent statement of what ISO/IEC 13211-1 requires, so it can contradict
this engine in ways a suite written alongside the engine cannot.

- Tests derived from the formal specification of ISO/IEC 13211-1 by
  **Pierre Deransart, AbdelAli Ed-Dbali and Laurent Cervoni**.
- Batch driver (not used here) by **J. P. E. Hodgson**.
- Obtained from <https://www.deransart.fr/prolog/suites.html>
  (`http://pauillac.inria.fr/~deransar/prolog/inriasuite.tar.gz`).

Each file holds one builtin's cases, one term per line:

```prolog
[Goal, Expected].
```

`Expected` is `success`, `failure`, an ISO error term, or a list of solution
substitutions written with the suite's own `<--` operator. `tests/iso-inria.lisp`
reads these files with this engine's own reader and runs each goal, so a case
exercises the reader, the operator table and the builtin together.

Two files the suite ships are deliberately **not** vendored: `halt`, whose cases
terminate the process by design, and `junk`/`t`, which are scratch files rather
than tests. `file_manip` is vendored but its cases are documentation only — the
suite itself marks them unimplemented.

The suite predates the standard's corrigenda, so a few of its expectations are
themselves disputed; `tests/iso-inria.lisp` records each such case explicitly
rather than quietly skipping it.
