import ".." / ".." / pluginkit

# Describes the statements of a typed block as "tag/childCount" lines, using
# nothing but the kit's `len`, `[]` and `children`

proc describe(n: NifCursor): string =
  result = ""
  for s in n.children:
    result.add tagText(s) & "/" & $s.len
    if s.len > 0:
      result.add "[" & $s[0].kind & ":" & name(s[0]) & "]"
    result.add ";"

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  # (stmts <template name> (stmts <body>))
  result.addStrLit describe(n[1])

saveTree transform(loadPluginInput())
