import ".." / ".." / pluginkit

# Rejects `var` in a typed block, to check that `fail` reports at the node

proc check(n: NifCursor) =
  for c in n.children:
    if c.stmtKind == VarS:
      fail("no variables allowed here: " & name(c[0]), c)
    elif c.stmtKind == StmtsS:
      check c

proc transform(n: NifCursor): NifBuilder =
  check n[1]
  result = createTree()
  result.addStrLit "fine"

pluginMain transform
