## Convenience layer over `plugins`: look at a NIF tree the way a macro looks
## at a `NimNode`, with `n[i]`, `n.len` and `for c in n.children`
##
## Nothing is copied. A `NifCursor` is a cheap read-only view, and every proc
## here works on a copy of it, so the cursor you pass in is never moved

{.feature: "assumeSync".}  # the failure record below; a plugin is single threaded

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

# --- errors ------------------------------------------------------------------

var
  failMessage: string
  failInfo: LineInfo
  hasFailed = false

proc fail*(msg: string; at: NifCursor) =
  ## Records an error at the node `at`. Only the first one is kept, and the
  ## walk can carry on, so a plugin does not have to thread an error through
  ## every proc it writes
  if not hasFailed:
    hasFailed = true
    failMessage = msg
    failInfo = at.info

proc failed*(): bool =
  ## True once `fail` has been called
  hasFailed

proc isErr*(n: NifCursor): bool =
  ## True for a node the compiler has already marked as an error
  n.kind == TagLit and n.exprKind == ErrX

proc failOnErr*(n: NifCursor): bool =
  ## If `n` is an error node, records the compiler's own message at its own
  ## position and returns true; otherwise returns false
  result = isErr(n)
  if result:
    var msg = ""
    for c in n.children:
      if c.kind == StrLit and msg.len == 0: msg = stringValue(c)
    fail(if msg.len > 0: msg else: "error in the plugin input", n)

proc finish*(tree: sink NifBuilder): NifBuilder =
  ## The tree the plugin built, or the first recorded error as an error tree
  if hasFailed:
    result = errorTree(failMessage, failInfo)
  else:
    result = tree

proc pluginMain*(transform: proc (n: NifCursor): NifBuilder) =
  ## The whole entry point: loads the input, runs `transform` on it and saves
  ## the result, or the first error recorded with `fail`
  let input = loadPluginInput()
  saveTree finish(transform(input))
