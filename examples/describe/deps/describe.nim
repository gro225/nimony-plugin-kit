import ".." / ".." / ".." / pluginquote

# defineDescribe(T): declares `describe(x: T): string`, which writes the
# object's fields as `Person(name: Ann, age: 30)`

proc transform(n: NifCursor): NifBuilder =
  # (stmts defineDescribe <type>)
  let typ = n[1]
  if typ.kind != Symbol:
    fail("defineDescribe needs the name of an object type", typ)
    return createTree()
  let decl = need(typ.symId)            # (type name export typevars pragmas body)
  if pending(): return createTree()
  let body = decl[4]
  if body.typeKind != ObjectT:
    fail("defineDescribe needs an object type, " & name(typ) & " is not one", typ)
    return createTree()

  # (object <inherits> (fld name export pragmas type value)*)
  var fields = createTree()
  fields.withTree StmtsS, n.info:
    var first = true
    for f in body.children:
      if f.otherKind == FldU:
        let label = (if first: "" else: ", ") & name(f[0]) & ": "
        fields.addTree quoteStmt("result.add $1 & $(x.$2)",
                                 [strNode(label), identNode(name(f[0]))], n.info)
        first = false
  result = createTree()
  result.addTree quoteStmt("""proc describe(x: $1): string =
  result = $2
  $3
  result.add ")"
""", [typ, strNode(name(typ) & "("), snapshot(fields)], n.info)

pluginMain transform
