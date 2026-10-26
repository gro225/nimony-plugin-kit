import ".." / ".." / pluginkit

# show(body): the body's tree, once with `$` and once with treeRepr, as a string

proc transform(n: NifCursor): NifBuilder =
  let body = asPluginCall(n).args[0]
  result = createTree()
  result.addStrLit $body & "\n--\n" & treeRepr(body)

pluginMain transform
