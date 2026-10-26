import std / monotimes
import ".." / ".." / ".." / ".." / pluginquote

# timed(label): runs the block and prints how long it took

proc transform(n: NifCursor): NifBuilder =
  let call = asPluginCall(n)       # timed(label, body)
  result = createTree()
  result.addTree quoteStmt("""block:
  let $$start = $3()
  $1
  echo $2, ": ", ($3().$4 - $$start.$4) div 1000, " us"
""", [call.args[1], call.args[0], boundSym("getMonoTime"), boundSym("ticks")], n.info)

pluginMain transform
