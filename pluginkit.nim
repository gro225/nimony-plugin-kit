## Convenience layer over `plugins`: look at a NIF tree the way a macro looks
## at a `NimNode`, with `n[i]`, `n.len` and `for c in n.children`
##
## Nothing is copied. A `NifCursor` is a cheap read-only view, and every proc
## here works on a copy of it, so the cursor you pass in is never moved

{.feature: "assumeSync".}  # the failure record below; a plugin is single threaded

import std / [assertions, strutils]
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

# --- printing a tree -----------------------------------------------------------

proc atomText(n: NifCursor): string =
  ## One token as text; a symbol keeps its module suffix and a definition gets a
  ## leading colon, as in the NIF text form
  case n.kind
  of Symbol: result = symText(n)
  of SymbolDef: result = ":" & symText(n)
  of Ident: result = identText(n)
  of StrLit:
    result = "\""
    for ch in stringValue(n):
      case ch
      of '"': result.add "\\\""
      of '\n': result.add "\\n"
      of '\\': result.add "\\\\"
      else: result.add ch
    result.add "\""
  of IntLit: result = $intValue(n)
  of UIntLit: result = $uintValue(n) & "u"
  of FloatLit: result = $floatValue(n)
  of CharLit: result = "'" & $charLit(n) & "'"
  of DotToken: result = "."
  else: result = "?" & $n.kind

proc lispRepr*(n: NifCursor): string =
  ## The node on one line, like `(add (f 64) d 2.0)`
  if n.kind == TagLit:
    result = "(" & tagText(n)
    for c in n.children:
      result.add " " & lispRepr(c)
    result.add ")"
  else:
    result = atomText(n)

proc `$`*(n: NifCursor): string =
  ## Same as `lispRepr`, so `echo n` and `"" & $n` show the node
  lispRepr(n)

proc hasCompoundChild(n: NifCursor): bool =
  result = false
  for c in n.children:
    if c.kind == TagLit: result = true

proc treeRepr*(n: NifCursor): string =
  ## The node over several lines, indented. The atoms before the first nested
  ## node stay on the line of the tag, and a node that holds only atoms stays on
  ## one line, so a tree reads like its source shape
  if n.kind != TagLit or not hasCompoundChild(n):
    result = lispRepr(n)
  else:
    result = "(" & tagText(n)
    var inHead = true
    for c in n.children:
      if inHead and c.kind != TagLit:
        result.add " " & atomText(c)
      else:
        inHead = false
        result.add "\n"
        for line in treeRepr(c).split('\n'):
          result.add "  " & line & "\n"
        result.setLen result.len - 1
    result.add ")"

# --- errors ------------------------------------------------------------------

var
  failMessage: string
  failInfo: LineInfo
  hasFailed = false
  wanted: seq[SymId] = @[]       ## declarations asked for with `need`, not yet given
  provided: NifCursor            ## the `(stmts (type ...)*)` the compiler gave back
  providedLoaded = false

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
  ## The tree the plugin built; the first recorded error as an error tree; or,
  ## when `need` asked for declarations, the request that makes the compiler run
  ## the plugin again with them
  if hasFailed:
    result = errorTree(failMessage, failInfo)
  elif wanted.len > 0:
    result = needTypes(wanted)
  else:
    result = tree

# --- type declarations ---------------------------------------------------------

proc need*(s: SymId): NifCursor =
  ## The declaration `(type name export typevars pragmas body)` of the type
  ## named by `s`. The first time round the compiler has not given it yet: this
  ## records the request and returns a cursor that must not be read, and
  ## `pending()` says so. `pluginMain` then asks the compiler for everything
  ## requested in one go and runs the plugin again, now with the declarations
  if not providedLoaded:
    provided = loadTypeDefinitions()
    providedLoaded = true
  for d in provided.children:
    if d[0].symId == s:
      return d
  var known = false
  for w in wanted:
    if w == s: known = true
  if not known: wanted.add s
  result = provided

proc pending*(): bool =
  ## True when a `need` could not be answered yet. Check it once, after asking
  ## for everything the plugin wants, and return an empty tree: `pluginMain`
  ## turns it into the request
  wanted.len > 0

proc pluginMain*(transform: proc (n: NifCursor): NifBuilder) =
  ## The whole entry point: loads the input, runs `transform` on it and saves
  ## the result, or the first error recorded with `fail`
  let input = loadPluginInput()
  saveTree finish(transform(input))
