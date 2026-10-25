import std / strutils
import ".." / ".." / ".." / pluginkit

# Typed NIF of a shader body to GLSL ES 3.00, the same subset as the plugin
# in shd_nim/experiments/plugin, written with the kit's `[]` and `children`
# instead of cursor bookkeeping. A node the plugin cannot read is written as
# /* tag */ so the gaps show in the output

const
  errMark = "@@err@@"  ## stands in for a node that carries an error, followed by
  errEnd = "@@end@@"   ## the compiler's message

proc typeName(n: NifCursor): string =
  if n.kind == Symbol:
    let s = name(n)
    result = toLowerAscii(s[0]) & s.substr(1)
  else:
    case n.typeKind
    of FT: result = "float"
    of IT: result = "int"
    of BoolT: result = "bool"
    else: result = "/*" & tagText(n) & "*/"

proc floatText(f: BiggestFloat): string =
  result = $f
  if '.' notin result and 'e' notin result and "inf" notin result:
    result.add ".0"

proc expr(n: NifCursor): string

proc args(n: NifCursor; first: int): string =
  result = ""
  for i in first ..< n.len:
    if i > first: result.add ", "
    result.add expr(n[i])

proc binary(op, a, b: string): string = "(" & a & " " & op & " " & b & ")"

proc expr(n: NifCursor): string =
  case n.kind
  of Symbol: result = name(n)
  of IntLit: result = $intValue(n)
  of FloatLit: result = floatText(floatValue(n))
  of TagLit:
    case n.exprKind
    of ErrX:
      var msg = ""
      for c in n.children:
        if c.kind == StrLit and msg.len == 0: msg = stringValue(c)
      result = errMark & msg & errEnd
    of InfixX:
      result = if n[0].kind != Symbol: expr(n[0])
               else: binary(name(n[0]), expr(n[1]), expr(n[2]))
    of CallX:
      result = if n[0].kind != Symbol: expr(n[0])
               else: name(n[0]) & "(" & args(n, 1) & ")"
    of ExprX, ParX: result = expr(n[0])
    of TrueX: result = "true"
    of FalseX: result = "false"
    of NotX: result = "(!" & expr(n[0]) & ")"
    of NegX: result = "(-" & expr(n[1]) & ")"
    of AndX: result = binary("&&", expr(n[0]), expr(n[1]))
    of OrX: result = binary("||", expr(n[0]), expr(n[1]))
    of AddX: result = binary("+", expr(n[1]), expr(n[2]))
    of SubX: result = binary("-", expr(n[1]), expr(n[2]))
    of MulX: result = binary("*", expr(n[1]), expr(n[2]))
    of DivX: result = binary("/", expr(n[1]), expr(n[2]))
    of ModX: result = binary("%", expr(n[1]), expr(n[2]))
    of LtX: result = binary("<", expr(n[1]), expr(n[2]))
    of LeX: result = binary("<=", expr(n[1]), expr(n[2]))
    of EqX: result = binary("==", expr(n[1]), expr(n[2]))
    of NeqX: result = binary("!=", expr(n[1]), expr(n[2]))
    of DotX: result = expr(n[0]) & "." & name(n[1])
    else: result = "/*" & tagText(n) & "*/"
  else: result = "/*?*/"

proc stmt(n: NifCursor; ind: string; lines: var string)

proc stmts(n: NifCursor; ind: string; lines: var string) =
  for c in n.children:
    stmt c, ind, lines

proc isResult(n: NifCursor): bool = n.kind == Symbol and name(n) == "result"

proc stmt(n: NifCursor; ind: string; lines: var string) =
  case n.stmtKind
  of ResultS: discard
  of AsgnS:
    if isResult(n[0]): lines.add ind & "return " & expr(n[1]) & ";\n"
    else: lines.add ind & expr(n[0]) & " = " & expr(n[1]) & ";\n"
  of RetS:
    if not isResult(n[0]): lines.add ind & "return " & expr(n[0]) & ";\n"
  of LetS, VarS, GletS, GvarS:
    lines.add ind & typeName(n[3]) & " " & name(n[0]) & " = " & expr(n[4]) & ";\n"
  of StmtsS: stmts n, ind, lines
  of IfS:
    var first = true
    for c in n.children:
      case c.otherKind
      of ElifU:
        lines.add ind & (if first: "if (" else: "} else if (") & expr(c[0]) & ") {\n"
        stmts c[1], ind & "  ", lines
      of ElseU:
        lines.add ind & "} else {\n"
        stmts c[0], ind & "  ", lines
      else: discard
      first = false
    lines.add ind & "}\n"
  of WhileS:
    lines.add ind & "while (" & expr(n[0]) & ") {\n"
    stmts n[1], ind & "  ", lines
    lines.add ind & "}\n"
  of ForS:
    # for i in a ..< b  and  a .. b
    let range = n[0]
    let op = if name(range[0]) == "..": "<=" else: "<"
    let i = name(n[1][0][0])
    lines.add ind & "for (int " & i & " = " & expr(range[1]) & "; " & i & " " & op &
      " " & expr(range[2]) & "; " & i & "++) {\n"
    stmts n[2], ind & "  ", lines
    lines.add ind & "}\n"
  of BreakS: lines.add ind & "break;\n"
  of ContinueS: lines.add ind & "continue;\n"
  else: lines.add ind & "/* " & tagText(n) & " */\n"

proc procDecl(n: NifCursor; lines: var string) =
  # (proc name exported pattern typevars (params ...) rettype pragmas effects body)
  var params: seq[string] = @[]
  for p in n[4].children:
    params.add typeName(p[3]) & " " & name(p[0])
  lines.add typeName(n[5]) & " " & name(n[0]) & "(" & join(params, ", ") & ") {\n"
  stmts n[8], "  ", lines
  lines.add "}\n\n"

proc globalDecl(n: NifCursor; lines: var string) =
  # (var name exported (pragmas (pragma sym args...)*)|. type value)
  var isUniform = false
  var meta = ""
  if n[2].otherKind == PragmasU:
    for p in n[2].children:
      case name(p[0])
      of "uniform": isUniform = true
      of "uniformRange":
        isUniform = true
        meta = " range " & expr(p[1][0]) & " .. " & expr(p[1][1])
      else: discard
  let ty = typeName(n[3])
  if isUniform:
    lines.add "uniform " & ty & " " & name(n[0]) & ";  // default " & expr(n[4]) & meta & "\n"
  else:
    lines.add ty & " " & name(n[0]) & " = " & expr(n[4]) & ";\n"

proc shader(n: NifCursor): string =
  result = ""
  # (stmts <template name> (stmts <body>))
  for c in n[1].children:
    case c.stmtKind
    of ProcS: procDecl c, result
    of GvarS, GletS, VarS, LetS: globalDecl c, result
    of ConstS:
      result.add "const " & typeName(c[3]) & " " & name(c[0]) & " = " & expr(c[4]) & ";\n"
    else: result.add "// top " & tagText(c) & "\n"

proc build(info: LineInfo; src: string): NifBuilder =
  let at = src.find(errMark)
  if at >= 0:
    let stop = src.find(errEnd, at)
    let msg = src.substr(at + errMark.len, stop - 1)
    return errorTree("shader: " & (if msg.len > 0: msg else: "unsupported construct"), info)
  result = createTree()
  result.addStrLit src

let inp = loadPluginInput()
saveTree build(inp.info, shader(inp))
