import ".." / ".." / pluginquote

# twice(x) runs x two times; times10(name, value) declares a constant

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.withTree StmtsS, n.info:
    if n.len == 2:                      # (stmts twice x)
      result.addTree quoteStmt("block:\n  $1\n  $1", [n[1]], n.info)
    else:                               # (stmts times10 name value)
      result.addTree quoteStmt("let $1 = $2 * 10", [n[1], n[2]], n.info)

pluginMain transform
