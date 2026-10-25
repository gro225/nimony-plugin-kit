import std / syncio
import ".." / ".." / pluginkit

# pair(A, B): the names of two object types, found with two `need`s in a row,
# which must take one request round and not two. Each run is logged to runs.txt

proc transform(n: NifCursor): NifBuilder =
  # (stmts pair <A> <B>)
  try:
    let f = open("runs.txt", fmAppend)
    f.write "run\n"
    f.close()
  except:
    discard
  let a = need(n[1].symId)
  let b = need(n[2].symId)
  if pending(): return createTree()
  result = createTree()
  result.addStrLit name(a[0]) & "+" & name(b[0])

pluginMain transform
