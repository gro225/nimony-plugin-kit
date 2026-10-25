# nimony-plugin-kit

A small layer over Nimony's `plugins` module, meant to make writing a plugin
about as easy as writing a Nim 2 macro. It is a proposal for the compiler, kept
as a separate repository until it is worth sending upstream.

## Why

Plugins replace macros, but the cursor API makes the common "read a tree and
produce something from it" job harder than it was with `NimNode`:

- no `n[i]`, `n.len` or `for c in n`; reading a node means entering it with
  `into` and counting `skip`s, and a miscount shows up only in the output
- `into` asserts that its body consumed every child, so an early exit needs
  extra skipping
- there is no quasi-quote with holes (`nimparser` parses a string, but nothing
  splices nodes into it)
- an error found deep in a walk has to travel up by hand: globals need
  `assumeSync` and exceptions are `raises`

## Layer 1: look at a node like a `NimNode` (done)

```nim
import pluginkit

for p in n[4].children:            # the (params ...) of a proc
  echo name(p[0]), ": ", typeName(p[3])
```

- `n.len` is the number of children, zero for an atom
- `n[i]` is child `i`, counting from zero
- `for c in n.children` visits every child
- `name(n)` is the text of a symbol (without module suffix) or identifier

Nothing is copied: each of these works on a copy of the `NifCursor`, which is a
cheap reference-counted view, so the cursor you pass in never moves.

## Measured on a real plugin

`examples/glsl` is a typed-block-to-GLSL translator (uniforms with ranges,
`const`, `if`/`elif`/`else`, `for`, `while`, operators, calls, sem errors passed
through). The same plugin, with byte-identical output on both samples:

| written with | lines |
|---|---|
| `into` / `skip` / `hasMore` | 313 |
| this kit | 174 |

For reference, the generator in shd's Nim 2 macro (`core.nim`) is about 158
lines for the same job, and it also emits Metal.

## Not done yet

- layer 2: `quoteStmt("let $1 = $2", name, value)` over `parseStmt`, splicing
  cursors into the parsed tree
- layer 3: a plugin entry point that takes `transform` returning a result or an
  error with a position, and an error type that can be returned from deep
  inside a walk without the marker-string workaround the example still uses
- an error from the shader body is reported at the start of the block, not at
  the offending line; the `err` node would have to carry its own position

## Run the checks

```sh
tests/run.sh
```

Needs a nightly that has the plugin sources in the archive (0.6.3-83f492b48 or
newer) with `nimony` on `PATH`.

## Notes from writing it

- an iterator over cursors must be `{.sideEffect.}`, or `firstChild` is
  rejected inside it
- `import std / assertions` is needed in a module that uses `assert`; `plugins`
  imports it but does not re-export it
- a global touched from a proc is rejected unless the module opts in with
  `{.feature: "assumeSync".}`
