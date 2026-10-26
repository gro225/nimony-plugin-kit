import std / syncio
import ".." / ".." / pluginkit

# pair(A, B): the names of two object types, found with two `need`s in a row,
# which must take one request round and not two. Each run is logged to runs.txt

proc transform(n: NifCursor): NifBuilder =
  try:
    let f = open("runs.txt", fmAppend)
    f.write "run\n"
    f.close()
  except:
    discard
  let call = asPluginCall(n)
  let a = need(call.args[0].symId)
  let b = need(call.args[1].symId)
  if pending(): return createTree()
  result = createTree()
  result.addStrLit name(asTypeDecl(a).name) & "+" & name(asTypeDecl(b).name)

pluginMain transform
