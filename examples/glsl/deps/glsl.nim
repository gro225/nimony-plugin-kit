import std / strutils
import ".." / ".." / ".." / pluginkit

# Typed NIF of a shader body to GLSL ES 3.00, the same subset as the plugin in
# `without-kit`, written with the typed views (`asRoutine`, `asLocal`, ...) and
# `fail`/`pluginMain` for errors. A node the plugin cannot read is written as
# /* tag */ so the gaps show in the output

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

proc binary(op, a, b: string): string = "(" & a & " " & op & " " & b & ")"

proc typedOp(op: string; n: NifCursor): string =
  let o = asTypedOp(n)
  binary(op, expr(o.lhs), expr(o.rhs))

proc expr(n: NifCursor): string =
  case n.kind
  of Symbol: result = name(n)
  of IntLit: result = $intValue(n)
  of FloatLit: result = floatText(floatValue(n))
  of TagLit:
    case n.exprKind
    of ErrX:
      result = ""
      discard failOnErr(n)
    of InfixX:
      let i = asInfix(n)
      result = if i.op.kind != Symbol: expr(i.op)
               else: binary(name(i.op), expr(i.lhs), expr(i.rhs))
    of CallX:
      let c = asCall(n)
      if c.fn.kind != Symbol:
        result = expr(c.fn)
      else:
        var args: seq[string] = @[]
        for a in c.args: args.add expr(a)
        result = name(c.fn) & "(" & join(args, ", ") & ")"
    of ExprX, ParX: result = expr(firstChild(n))
    of TrueX: result = "true"
    of FalseX: result = "false"
    of NotX: result = "(!" & expr(firstChild(n)) & ")"
    of NegX: result = "(-" & expr(asTypedOp(n).lhs) & ")"
    of AndX:
      let b = asBinary(n)
      result = binary("&&", expr(b.lhs), expr(b.rhs))
    of OrX:
      let b = asBinary(n)
      result = binary("||", expr(b.lhs), expr(b.rhs))
    of AddX: result = typedOp("+", n)
    of SubX: result = typedOp("-", n)
    of MulX: result = typedOp("*", n)
    of DivX: result = typedOp("/", n)
    of ModX: result = typedOp("%", n)
    of LtX: result = typedOp("<", n)
    of LeX: result = typedOp("<=", n)
    of EqX: result = typedOp("==", n)
    of NeqX: result = typedOp("!=", n)
    of DotX:
      let d = asDot(n)
      result = expr(d.obj) & "." & name(d.field)
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
    let a = asAsgn(n)
    if isResult(a.lhs): lines.add ind & "return " & expr(a.rhs) & ";\n"
    else: lines.add ind & expr(a.lhs) & " = " & expr(a.rhs) & ";\n"
  of RetS:
    let value = firstChild(n)
    if not isResult(value): lines.add ind & "return " & expr(value) & ";\n"
  of LetS, VarS, GletS, GvarS:
    let l = asLocal(n)
    lines.add ind & typeName(l.typ) & " " & name(l.name) & " = " & expr(l.val) & ";\n"
  of StmtsS: stmts n, ind, lines
  of IfS:
    var first = true
    for b in branches(n):
      if b.isElse:
        lines.add ind & "} else {\n"
      else:
        lines.add ind & (if first: "if (" else: "} else if (") & expr(b.cond) & ") {\n"
      stmts b.body, ind & "  ", lines
      first = false
    lines.add ind & "}\n"
  of WhileS:
    let w = asWhileStmt(n)
    lines.add ind & "while (" & expr(w.cond) & ") {\n"
    stmts w.body, ind & "  ", lines
    lines.add ind & "}\n"
  of ForS:
    # for i in a ..< b  and  a .. b
    let f = asForStmt(n)
    let range = asInfix(f.iter)
    let op = if name(range.op) == "..": "<=" else: "<"
    let i = name(asLocal(firstChild(f.vars)).name)   # (unpackflat (let i ...))
    lines.add ind & "for (int " & i & " = " & expr(range.lhs) & "; " & i & " " & op &
      " " & expr(range.rhs) & "; " & i & "++) {\n"
    stmts f.body, ind & "  ", lines
    lines.add ind & "}\n"
  of BreakS: lines.add ind & "break;\n"
  of ContinueS: lines.add ind & "continue;\n"
  else: lines.add ind & "/* " & tagText(n) & " */\n"

proc procDecl(n: NifCursor; lines: var string) =
  let r = asRoutine(n)
  var params: seq[string] = @[]
  for p in parameters(r):
    params.add typeName(p.typ) & " " & name(p.name)
  lines.add typeName(r.retType) & " " & name(r.name) & "(" & join(params, ", ") & ") {\n"
  stmts r.body, "  ", lines
  lines.add "}\n\n"

proc globalDecl(n: NifCursor; lines: var string) =
  let l = asLocal(n)
  var isUniform = false
  var meta = ""
  if l.pragmas.otherKind == PragmasU:
    for p in l.pragmas.children:
      let pragma = asPragma(p)
      case name(pragma.name)
      of "uniform": isUniform = true
      of "uniformRange":
        isUniform = true
        let bounds = elements(pragma.args[0])        # (tup lo hi)
        meta = " range " & expr(bounds[0]) & " .. " & expr(bounds[1])
      else: discard
  let ty = typeName(l.typ)
  if isUniform:
    lines.add "uniform " & ty & " " & name(l.name) & ";  // default " & expr(l.val) & meta & "\n"
  else:
    lines.add ty & " " & name(l.name) & " = " & expr(l.val) & ";\n"

proc shader(root: NifCursor): string =
  result = ""
  for c in asPluginCall(root).args[0].children:
    case c.stmtKind
    of ProcS: procDecl c, result
    of GvarS, GletS, VarS, LetS: globalDecl c, result
    of ConstS:
      let l = asLocal(c)
      result.add "const " & typeName(l.typ) & " " & name(l.name) & " = " & expr(l.val) & ";\n"
    else: result.add "// top " & tagText(c) & "\n"

proc transform(n: NifCursor): NifBuilder =
  result = createTree()
  result.addStrLit shader(n)

pluginMain transform
