import plugins
import helper

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.addStrLit greeting()

saveTree transform(loadPluginInput())
