import plugins
import helper

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.withTree StmtsS, n.info:
    result.withTree CallS, n.info:
      result.addIdent "echo"
      result.withTree CallX, n.info:
        result.bindSym "hello"

saveTree transform(loadPluginInput())
