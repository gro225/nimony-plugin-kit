import ".." / ".." / pluginkit

# show(body): the body's tree, once with `$` and once with treeRepr, as a string

proc transform(n: NifCursor): NifBuilder =
  # (stmts show <body>)
  result = createTree()
  result.addStrLit $n[1] & "\n--\n" & treeRepr(n[1])

pluginMain transform
