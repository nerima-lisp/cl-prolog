# Compatibility

What `cl-prolog` promises to keep working, and what it deliberately does not.

## Supported surface

Changes preserve the documented `cl-prolog` public API, the CPS query surface,
and the separation between rule data and solver logic. Specifically:

- documented public `cl-prolog` behavior, as described in
  [API Reference](api-reference.md)
- macro-first rule definition and CPS query semantics, as described in
  [Rule DSL](rule-dsl.md) and [Querying](querying.md)
- reproducible packaging and example execution through the flake

## Not supported

- **Undocumented `%...` internals.** Symbols prefixed with `%` are private.
  They are not exported, they are not in [API Reference](api-reference.md), and
  they change without a changelog entry.
- **Full ISO Prolog behavior.** This is a focused Prolog runtime, not a
  standalone ISO system. [Semantics](semantics.md) records which parts of
  ISO/IEC 13211-1 the engine implements and where it departs; the INRIA
  conformance corpus in `t/iso/` measures how far that goes.
- **Unbounded relational enumeration in every argument direction.** A goal that
  is relational in one mode is not guaranteed to enumerate in all of them.
  [Builtin Goals](builtin-goals.md) states the modes each builtin supports.

## Implementation support

SBCL only. `sb-posix` is used directly and CI runs SBCL exclusively, so
portability to other Common Lisp implementations is neither claimed nor
verified.

## Versioning

The `:version` in `cl-prolog.asd` is the single source of truth: `flake.nix`
reads it, and the release workflow refuses to publish a tag that disagrees
with it. Breaking changes to the supported surface above are recorded under
their release heading in
[CHANGELOG.md](https://github.com/nerima-lisp/cl-prolog/blob/main/CHANGELOG.md).
