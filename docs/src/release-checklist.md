# Release Checklist

This is the minimum evidence bar for calling a revision releasable.

## Documentation Review

Confirm that these files still describe the current code:

- `README.md`
- `docs/src/api-reference.md` — the exported symbol index
- `docs/src/builtin-goals.md` and `docs/src/arithmetic.md` — goal behavior
- `docs/src/conditions.md` and `docs/src/parser-limits.md` — error surface
- `docs/src/architecture.md`
- `docs/src/troubleshooting.md`
- `docs/src/compatibility.md` — the supported-surface promise

If the public surface changed, update the docs in the same change. The MkDocs
build is `--strict`, so a broken cross-link or a page missing from
`docs/mkdocs.yml`'s `nav` fails the documentation check — run it before
shipping (see [Development](development.md#documentation)).

## Verification Commands

Run:

```sh
nix run .          # on Linux
nix flake check
```

## What Must Be Green

- ASDF/cl-weave regression suite
- Nix packaging check when Nix is part of the release process
- the MkDocs documentation build (`checks.docs`)

## Refuse To Ship When

Do not ship when:

- public API changed without matching documentation updates
- examples no longer execute
- release docs or policy files are missing from the tracked tree
- tests pass only because regression coverage was silently removed

## Cutting a Release

Pushing a `vX.Y.Z` tag triggers `.github/workflows/release.yml`, which creates
the GitHub Release as an empty **draft**. One precondition is enforced by the
workflow — get it right *before* tagging, or the release job fails and you
must delete and recreate the tag:

- **Version guard.** The tag minus its `v` prefix must equal `:version` in
  `cl-prolog.asd`. That field is the single source of truth the flake also
  reads (`flake.nix`'s `projectVersion`), so bump `cl-prolog.asd` first and let
  the tag follow it.

The release body is **not** generated. The GitHub Release description is this
project's only canonical release history, and writing it is a judgement call
about what a user of this package has to change in their own code — so the
workflow leaves it empty and stops. After the job goes green:

```sh
gh release edit "vX.Y.Z" --notes-file <file> --draft=false
```

Until that command runs the release stays a draft: it does not appear under
"Latest release" and does not reach anyone downstream.
