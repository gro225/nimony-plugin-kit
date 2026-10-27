An ordinary Nim 2 style macro that walks its argument with `for c in body` stops
the compiler with an assertion. The same macro with an index loop works.

```sh
nimony c -r main.nim
```

Result on nightly 0.6.3-83f492b48:

```
Error: unhandled exception: iterinliner.nim(607, 3) `iter.exprKind in CallKinds`  [AssertionDefect]
```

Replacing the loop with `var i = 0; while i < body.len: result.add body[i]; inc i`
prints `a` and `b` as expected. Searched nim-lang/nimony for `iterinliner` and the
assertion text; the other `iterinliner` issues are about different failures.
