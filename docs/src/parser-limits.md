# Parser Resource Limits

Reading Prolog **text** is bounded by a set of configurable resource limits so
that untrusted source cannot exhaust memory or stack. Every parser entry point
enforces them: `read-prolog-term`, `read-prolog-clause`, `parse-prolog`, and the
`consult`/`ensure_loaded`/`load_files` source loaders.

Each bound is a special variable you can rebind; the defaults are conservative
but generous for ordinary source. Binding a variable to `nil` disables that
single limit.

## The bounds

| Special variable                      | Bounds                                             | Default   |
| ------------------------------------- | -------------------------------------------------- | --------- |
| `*max-prolog-source-characters*`      | total source characters consumed                   | `1048576` |
| `*max-prolog-delimiter-depth*`        | maximum nesting of `(`, `[`, `{`                   | `256`     |
| `*max-prolog-parser-depth*`           | expression-parser recursion depth                  | `256`     |
| `*max-prolog-tokens*`                 | total tokens produced, excluding EOF               | `65536`   |
| `*max-prolog-identifier-length*`      | length of one unquoted name lexeme                 | `1024`    |
| `*max-prolog-quoted-lexeme-length*`   | content length of one quoted atom or string lexeme | `65536`   |
| `*max-prolog-numeric-lexeme-length*`  | length of one numeric lexeme                       | `4096`    |
| `*max-prolog-interned-symbols*`       | cumulative count of new symbols the parser interns | `65536`   |

!!! note "One of these is not like the others"
    `*max-prolog-interned-symbols*` is a **cumulative, process-wide** bound
    tracked across parse calls rather than a per-parse limit. It exists so a
    stream of adversarial source cannot permanently intern an unbounded number
    of symbols.

## What happens when a bound is exceeded

The parser signals `prolog-parser-resource-error`, whose readers describe the
violation:

- `prolog-parser-resource-error-resource` — which limit was hit (a string such
  as `"IDENTIFIER_LENGTH"`).
- `prolog-parser-resource-error-limit` — the configured limit value.
- `prolog-parser-resource-error-observed` — the observed value that exceeded it.
- `prolog-parser-resource-error-position` — the source position at the failure.

This condition is a plain Common Lisp `error`, **not** a `prolog-runtime-error`,
because it is raised in the lexer beneath the engine's condition hierarchy.

## Direct readers vs. inside the engine

- The direct reader APIs (`read-prolog-term`, `read-prolog-clause`,
  `parse-prolog`) and a direct `consult-prolog` call let
  `prolog-parser-resource-error` propagate **as-is**.
- When the same limit is hit *inside* the engine while running a
  `consult`/`ensure_loaded`/`load_files` goal, it is translated into a catchable
  ISO `resource_error/1` term — for example
  `error(resource_error(identifier_length), _)` — so Prolog-level `catch/3` can
  intercept it.

## Raising or disabling a limit

For legitimately large, trusted input, rebind the relevant special higher, or to
`nil` to disable that one limit:

```lisp
(let ((*max-prolog-source-characters* (* 8 1024 1024)))  ; 8 MiB
  (parse-prolog big-source-string))

(let ((*max-prolog-tokens* nil))                          ; disable this bound
  (parse-prolog token-heavy-source))
```

Because `*max-prolog-interned-symbols*` is cumulative, a long-lived process that
parses a great deal of distinct source may trip it even on individually small
inputs; rebind it (or reset the parser's symbol table) if that happens.

## See also

- [Conditions and Errors](conditions.md) — the full condition catalogue.
- [Troubleshooting](troubleshooting.md#parsing-signalled-prolog-parser-resource-error)
  — a focused recovery recipe.
- [Semantics](semantics.md#parser-resource-limits) — where limits sit in the
  parsing model.
