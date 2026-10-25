## Quasi-quote for plugins: write the code to produce as Nim text, with `$1`,
## `$2`, ... marking where a node goes
##
## It is a module of its own, like `nimparser`, so only the plugins that quote
## code compile a Nim parser

import std / [assertions, strutils]
import pluginkit, nimparser
export pluginkit

const
  holeName = "pluginquote_hole_"
  freshPrefix = "pluginquote_fresh_"

type
  FreshEntry = object
    name: string
    sym: SymId

proc withHoleNames(code: string; count: int): string =
  ## `$1` becomes an identifier the parser accepts in any position, such as
  ## `let $1 = $2`, where `$1` itself would be read as an operator
  result = ""
  var i = 0
  while i < code.len:
    if code[i] == '$' and i + 2 < code.len and code[i + 1] == '$' and
        code[i + 2] in {'a'..'z', 'A'..'Z', '_'}:
      var j = i + 2
      while j < code.len and code[j] in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
        inc j
      result.add freshPrefix & code.substr(i + 2, j - 1)
      i = j
    elif code[i] == '$' and i + 1 < code.len and code[i + 1] in {'0'..'9'}:
      var j = i + 1
      var num = 0
      while j < code.len and code[j] in {'0'..'9'}:
        num = num * 10 + (ord(code[j]) - ord('0'))
        inc j
      assert num >= 1 and num <= count, "quote: hole $" & $num & " has no argument"
      result.add holeName & $num
      i = j
    else:
      result.add code[i]
      inc i

proc holeIndex(n: NifCursor): int =
  ## The number a hole identifier stands for, or zero for any other token
  result = 0
  if n.kind == Ident:
    let t = identText(n)
    if t.len > holeName.len and t.startsWith(holeName):
      for i in holeName.len ..< t.len:
        result = result * 10 + (ord(t[i]) - ord('0'))

proc freshSym(fresh: var seq[FreshEntry]; name: string; isNew: var bool): SymId =
  ## The symbol for `$$name`; made on first use, which is the definition
  isNew = false
  for e in fresh:
    if e.name == name: return e.sym
  isNew = true
  result = genSym()
  fresh.add FreshEntry(name: name, sym: result)

proc splice(dest: var NifBuilder; n: var NifCursor; holes: openArray[NifCursor];
            fresh: var seq[FreshEntry]; info: LineInfo) =
  case n.kind
  of TagLit:
    copyInto dest, n:
      while n.hasMore:
        splice dest, n, holes, fresh, info
  of Ident:
    let k = holeIndex(n)
    let text = identText(n)
    if k > 0:
      var h = holes[k - 1]
      dest.takeTree h
      inc n
    elif text.startsWith(freshPrefix):
      var isNew = false
      let sym = freshSym(fresh, text.substr(freshPrefix.len), isNew)
      if isNew: dest.addSymDef sym, info
      else: dest.addSymUse sym, info
      inc n
    else:
      dest.takeTree n
  else:
    dest.takeTree n

proc quoteStmt*(code: string; holes: openArray[NifCursor];
                info = NoLineInfo): NifBuilder =
  ## The statements in `code`, as a `(stmts ...)` tree, with each `$N` replaced
  ## by the node `holes[N - 1]`, and each `$$name` by a fresh symbol that cannot
  ## clash with the caller's own `name`: the first one in the text defines it and
  ## the rest refer to it. Add the result to a tree with `addTree`
  var tree = parseStmt(withHoleNames(code, holes.len), info)
  var fresh: seq[FreshEntry] = @[]
  result = createTree()
  splice result, tree, holes, fresh, info

proc quoteExpr*(code: string; holes: openArray[NifCursor];
                info = NoLineInfo): NifBuilder =
  ## Like `quoteStmt` for exactly one expression
  var tree = parseExpr(withHoleNames(code, holes.len), info)
  var fresh: seq[FreshEntry] = @[]
  result = createTree()
  splice result, tree, holes, fresh, info

template boundSym*(name: untyped): NifCursor =
  ## A reference to `name` as the plugin module sees it, so a quote can use
  ## `getMonoTime` without the caller importing it. `name` must be a literal
  block:
    var t = createTree()
    t.bindSym name
    snapshot(t)

# --- nodes to put in holes -----------------------------------------------------

proc strNode*(s: string): NifCursor =
  ## A string literal node, for a hole
  var t = createTree()
  t.addStrLit s
  result = snapshot(t)

proc identNode*(s: string): NifCursor =
  ## An identifier node, for a hole that stands where a name goes
  var t = createTree()
  t.addIdent s
  result = snapshot(t)

proc intNode*(i: BiggestInt): NifCursor =
  ## An integer literal node, for a hole
  var t = createTree()
  t.addIntLit i
  result = snapshot(t)
