# nimony-plugin-kit

A small layer over Nimony's `plugins` module, meant to make writing a plugin
about as easy as writing a Nim 2 macro. It is a proposal for the compiler, kept
as a separate repository until it is worth sending upstream.

## Why

Plugins replace macros, but the cursor API makes the common "read a tree and
produce something from it" job harder than it was with `NimNode`:

- nothing names the parts of a construct: a plugin reads a `proc` by entering it
  with `into` and counting `skip`s, and a miscount shows up only in the output
- `into` asserts that its body consumed every child, so an early exit needs
  extra skipping
- there is no quasi-quote with holes (`nimparser` parses a string, but nothing
  splices nodes into it)
- an error found deep in a walk has to travel up by hand: globals need
  `assumeSync` and exceptions are `raises`

## Layer 1: typed views of the constructs (done)

Reading a node by position (`n[4]` for the parameters) puts the slot numbers in
every plugin and breaks the day a slot is added. The compiler's own `decls.nim`
solves it with typed views (`asTypeDecl`, `asRoutine`, `asLocal`, `asForStmt`):
an object whose fields are cursors at the named parts. This layer is that, for
plugins; the names follow `decls.nim`. It came from a comment by Araq on
nim-lang/nimony#2786, who pointed at `asTypeDecl` and said positional `n[i]` is
the wrong idea; the first version of this kit had `n[i]`.

```nim
import pluginkit

let r = asRoutine(n)
for p in parameters(r):                 # each parameter is a Local
  echo name(p.name), ": ", p.typ        # `$` prints a node
echo r.retType
```

| view | node | fields |
|---|---|---|
| `asLocal` | `let`, `var`, `const`, a parameter, a field | `name exported pragmas typ val` |
| `asRoutine` | `proc`, `func`, `iterator`, `template`, ... | `name exported pattern typevars params retType pragmas effects body` |
| `asTypeDecl` | `type` | `name exported typevars pragmas body` |
| `asObjectDecl` | `object` | `parentType`, and `fields(o)` yields each plain field as a `Local` |
| `asForStmt`, `asWhileStmt` | `for`, `while` | `iter vars body`, `cond body` |
| `branches(n)` | `if` | yields each `Branch`: `isElse cond body` |
| `asCall`, `asInfix`, `asDot`, `asAsgn` | calls and operators | `fn` and `args(c)`; `op lhs rhs`; `obj field`; `lhs rhs` |
| `asBinary`, `asTypedOp` | `and`/`or`; `add`, `lt`, `neg`, ... | `lhs rhs`; `typ lhs rhs` |
| `asPragma`, `asPluginCall` | a pragma; what a template plugin receives | `name args`; `name args` |

Also `for c in n.children`, `name(n)` (a symbol without its module suffix, or an
identifier) and `elements(n)` for the places where position is the meaning, such
as a tuple.

Nothing is copied: a view holds cursors, which are cheap reference-counted
views, so the node it was made from never moves. Only the constructs the
examples needed are done; adding one is a few lines in `plugindecls.nim`.

## Measured on a real plugin

`examples/glsl` is a typed-block-to-GLSL translator (uniforms with ranges,
`const`, `if`/`elif`/`else`, `for`, `while`, operators, calls, sem errors passed
through). The same plugin, with byte-identical output on both samples:

| written with | lines |
|---|---|
| `into` / `skip` / `hasMore` (`examples/glsl/without-kit`) | 313 |
| this kit | 176 |

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

### A second example: a proc generated from a type

`examples/describe` declares `describe(x: T): string` for an object type, which
writes `Person(name: Ann, age: 30)`. That needs the fields of `T`, so the plugin
asks the compiler for the declaration with `needTypes` and is run again with it.
The Nim 2 macro (`examples/describe/nim2`) and the plugin print the same, and
refuse an enum or `int` with the same message at the same position.

| written with | lines |
|---|---|
| Nim 2 macro (`getTypeImpl`, `newProc`) | 24 |
| Nimony plugin with this kit | 33 |

The plugin is longer, and it is fair to say why: the list of field statements is
built as a tree before it is spliced into the proc, and a type's declaration
comes from the compiler rather than from a call. Two things in the Nim 2 version are
easy to get wrong and the plugin does not have them: a field is an
`nnkIdentDefs` that can hold several names (`x, y: float`), where the plugin
sees one `fld` per name, and the type check had to be moved ahead of the field
access to give a message instead of a crash.

The standard library's own `typetraits` plugin writes `slot(decl, idx)`
(`firstChild` and a skip loop) with named constants for the positions, and scans
for declarations with `into`; with the views that is `asTypeDecl(decl).body` and
`for d in defs.children`.

## Printing a tree

`treeRepr(n)` and `lispRepr(n)` (also `$n`) print a node the way Nim 2's
`treeRepr` and `repr` do:

```
(stmts
  (let a . . .
    (infix + 1 2))
  (cmd echo "hi" a))
```

`lispRepr` is the same on one line. A symbol keeps its module suffix and a
definition gets a leading colon, as in the NIF text form.

## Asking for type declarations from top to bottom

A plugin cannot look a type up: it runs in its own process, so it returns
`needTypes` and the compiler runs it again with the declarations. `need` hides
the round:

```nim
let decl = need(typ.symId)      # (type name export typevars pragmas body)
if pending(): return createTree()
let body = decl[4]              # from here on the declaration is really there
```

Every `need` before the `pending()` check goes into one request, so two types
cost two runs of the plugin in all, not three (`tests/pair.nim` counts the
runs). The request is sent by `pluginMain`, and an error recorded with `fail`
wins over it. The result of `need` must not be read while `pending()` is true.

It saves little code. What it removes is
the need to know there are rounds at all, and the chance to ask twice for the
same declaration, which the compiler rejects.

## What the kit does not solve

These come from how plugins are built, so a library over `plugins` cannot fix
them:

- **A plugin lives in a file of its own**, and the template points to it with a
  string, `{.plugin: "deps/x".}`. A macro is written next to the code that uses
  it. For a small local macro of a few lines that is a lot of ceremony. Only the
  compiler could change it, for instance with a plugin block written in place.
- **A plugin cannot call code from the module that uses it.** A Nim 2 macro runs
  in the VM and can call a proc written earlier in the same file. A plugin sees
  only what it imports, so shared code has to move to a module of its own. That
  can be seen as cleaner, but it is a different habit.
- **`bindSym` and the compiler error described above:** until it is fixed, a
  hygienic symbol works only if the calling module imports its module too.
- **A change to a module a plugin imports does not rebuild the plugin**
  (`repros/plugin-import-not-tracked`), so a stale plugin can run after an edit.
  The test runner clears the caches for this reason.
- **The API is young.** The kit leans on `firstChild`, the tag enums and
  `nifcore`, and Nimony is at 0.6.x, so any of them can change, and the kit with
  them.

## Not done yet

- a hole that takes a string or number directly, without wrapping it in a node
- generic types and objects with inheritance in `describe`; only plain objects
  are handled
- a macro that works on a whole block of code rather than a call or a type (a
  DSL), other than the GLSL translator

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
