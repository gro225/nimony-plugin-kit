import ".." / ".." / pluginkit

# Describes the statements of a typed block with the typed views: `let a: f64`,
# `var b: i64`, `proc f(x: f64): f64`, and for a tuple-free read of each part

proc describe(body: NifCursor): string =
  result = ""
  for s in body.children:
    case s.stmtKind
    of LetS, VarS:
      let l = asLocal(s)
      result.add tagText(s) & " " & name(l.name) & ":" & $l.typ & ";"
    of ProcS:
      let r = asRoutine(s)
      var ps = ""
      for p in parameters(r):
        ps.add name(p.name) & ":" & $p.typ & ","
      result.add "proc " & name(r.name) & "(" & ps & ")->" & $r.retType & ";"
    else:
      result.add "other " & tagText(s) & ";"

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.addStrLit describe(asPluginCall(n).args[0])

pluginMain transform
