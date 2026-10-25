## Quasi-quote for plugins: write the code to produce as Nim text, with `$1`,
## `$2`, ... marking where a node goes
##
## It is a module of its own, like `nimparser`, so only the plugins that quote
## code compile a Nim parser

import std / [assertions, strutils]
import pluginkit, nimparser
export pluginkit

const holeName = "pluginquote_hole_"

proc withHoleNames(code: string; count: int): string =
  ## `$1` becomes an identifier the parser accepts in any position, such as
  ## `let $1 = $2`, where `$1` itself would be read as an operator
  result = ""
  var i = 0
  while i < code.len:
    if code[i] == '$' and i + 1 < code.len and code[i + 1] in {'0'..'9'}:
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

proc splice(dest: var NifBuilder; n: var NifCursor; holes: openArray[NifCursor]) =
  case n.kind
  of TagLit:
    copyInto dest, n:
      while n.hasMore:
        splice dest, n, holes
  of Ident:
    let k = holeIndex(n)
    if k > 0:
      var h = holes[k - 1]
      dest.takeTree h
      inc n
    else:
      dest.takeTree n
  else:
    dest.takeTree n

proc quoteStmt*(code: string; holes: openArray[NifCursor];
                info = NoLineInfo): NifBuilder =
  ## The statements in `code`, as a `(stmts ...)` tree, with each `$N` replaced
  ## by the node `holes[N - 1]`. Add it to a result with `addTree`
  var tree = parseStmt(withHoleNames(code, holes.len), info)
  result = createTree()
  splice result, tree, holes

proc quoteExpr*(code: string; holes: openArray[NifCursor];
                info = NoLineInfo): NifBuilder =
  ## Like `quoteStmt` for exactly one expression
  var tree = parseExpr(withHoleNames(code, holes.len), info)
  result = createTree()
  splice result, tree, holes
