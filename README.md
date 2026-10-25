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
| this kit, layers 1 and 3 | 162 |

For reference, the generator in shd's Nim 2 macro (`core.nim`) is about 158
lines for the same job, and it also emits Metal.

## Layer 3: errors from anywhere in a walk (done)

```nim
proc transform(n: NifCursor): NifBuilder =
  for c in n.children:
    if c.stmtKind == VarS:
      fail("no variables allowed here: " & name(c[0]), c)
  result = createTree()
  ...

pluginMain transform
```

- `fail(msg, at)` records an error at the position of the node `at`; the first
  one wins and the walk can carry on, so no proc has to pass an error up
- `failOnErr(n)` does the same for a node the compiler already marked as an
  error, with the compiler's own message and position
- `pluginMain(transform)` is the whole entry point: it loads the input, runs
  `transform`, and saves either its tree or the recorded error

The GLSL example reports `bad.nim(18, 13) Error: undeclared identifier:
'lengthh'` at the offending identifier, where before it pointed at the start of
the block and needed a marker string to get there.

## Layer 2: quote with holes (done)

```nim
import pluginquote          # a separate module: only quoting plugins compile a parser

result.addTree quoteStmt("let $1 = $2 * 10", [n[1], n[2]], n.info)
```

`$1`, `$2`, ... stand for the given nodes and can sit anywhere, including
where an identifier goes (`let $1 = ...`). A syntax error in the quoted text is
reported at the call site with the position inside the text.

Limits: a hole takes a whole node, not text; to build a name from pieces, build
the identifier with `addIdent`. `$` followed by a digit always means a hole.

### A real example: `timed`

`examples/timed` is the same small macro twice, a timing wrapper that exists in
most projects. In Nim 2:

```nim
macro timed*(label: string, body: untyped): untyped =
  result = quote do:
    block:
      let start = getMonoTime()
      `body`
      echo `label`, ": ", (getMonoTime().ticks - start.ticks) div 1000, " us"
```

and as a Nimony plugin with this kit:

```nim
proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.addTree quoteStmt("""block:
  let $$start = $3()
  $1
  echo $2, ": ", ($3().$4 - $$start.$4) div 1000, " us"
""", [n[2], n[1], boundSym("getMonoTime"), boundSym("ticks")], n.info)

pluginMain transform
```

plus `template timed*(label: string, body: untyped) {.plugin: "deps/timed".}` in
a module, so `import timedlib` gives `timed` as `import timed` does in Nim 2.
Both print the same, and the plugin version is about the same size.

Writing it showed what plain `quoteStmt` was missing, and what the compiler is:

- **names the quote introduces** clashed with the caller's own (`start`); `$$start`
  now makes a fresh symbol, the way `quote do` gensyms a `let`
- **library procs the quote calls** had to be imported by the caller;
  `boundSym("getMonoTime")` resolves them where the plugin is written
- the caller still has to import the module of a `boundSym` symbol, and if it
  does not the compiler stops with an internal error
  (`dce2.nim: sowner is not in result`) rather than a message; a smaller case
  is in `repros/bindsym-unimported-module`. This is a compiler matter, not
  something the kit can paper over

## Not done yet

- a hole that takes a string or number directly, without wrapping it in a node
- more real examples of macros that generate code, beyond `timed`; the next one
  worth trying is generating procs from a type

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
