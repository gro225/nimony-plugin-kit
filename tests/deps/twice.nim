import ".." / ".." / pluginquote

# twice(x) runs x two times; times10(name, value) declares a constant

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.withTree StmtsS, n.info:
    let call = asPluginCall(n)
    if call.args.len == 1:              # twice(x)
      result.addTree quoteStmt("block:\n  $1\n  $1", [call.args[0]], n.info)
    else:                               # times10(name, value)
      result.addTree quoteStmt("let $1 = $2 * 10", [call.args[0], call.args[1]], n.info)

pluginMain transform
