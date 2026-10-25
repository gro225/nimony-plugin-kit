## Convenience layer over `plugins`: look at a NIF tree the way a macro looks
## at a `NimNode`, with `n[i]`, `n.len` and `for c in n.children`
##
## Nothing is copied. A `NifCursor` is a cheap read-only view, and every proc
## here works on a copy of it, so the cursor you pass in is never moved

import std / assertions
import plugins
export plugins

proc len*(n: NifCursor): int =
  ## Number of children of the compound node `n`, zero for an atom
  result = 0
  if n.kind == TagLit:
    var c = firstChild(n)
    while c.hasMore:
      inc result
      skip c

proc `[]`*(n: NifCursor; i: int): NifCursor =
  ## Child number `i` of the compound node `n`, counting from zero
  assert n.kind == TagLit, "`[]` needs a compound node"
  assert i >= 0 and i < n.len, "child index out of range"
  result = firstChild(n)
  var k = 0
  while k < i:
    skip result
    inc k

iterator children*(n: NifCursor): NifCursor {.sideEffect.} =
  ## The children of `n`, each as a cursor positioned at that child
  if n.kind == TagLit:
    var c = firstChild(n)
    while c.hasMore:
      yield c
      skip c

proc name*(n: NifCursor): string =
  ## Text of a symbol (without the module suffix) or of an identifier
  case n.kind
  of Symbol, SymbolDef: result = symBasename(n.symId)
  of Ident: result = identText(n)
  else: result = ""
