import plugins
import std / [syncio, strutils]

# Experiment 2: typed NIF of a shader body to GLSL ES 3.00, for the subset
# the plasma example needs. Whatever it does not know it writes as /* tag */
# so the gaps show in the output

proc typeName(n: var NifCursor): string =
  case n.kind
  of Symbol:
    let s = symBasename(n.symId)
    result = if s.len > 0: toLowerAscii(s[0]) & s.substr(1) else: s
    inc n
  of TagLit:
    case n.typeKind
    of FT: result = "float"
    of IT: result = "int"
    of BoolT: result = "bool"
    else: result = "/*" & tagText(n) & "*/"
    skip n
  else:
    result = ""
    skip n

const
  errMark = "@@err@@"  ## stands in for a node the plugin cannot read, followed by
  errEnd = "@@end@@"   ## the compiler's message

proc floatText(f: BiggestFloat): string =
  result = $f
  if '.' notin result and 'e' notin result and "inf" notin result:
    result.add ".0"

proc expr(n: var NifCursor): string

proc args(n: var NifCursor): string =
  ## Comma-separated rest of the current node's children
  result = ""
  var first = true
  while n.hasMore:
    if not first: result.add ", "
    first = false
    result.add expr(n)

proc expr(n: var NifCursor): string =
  case n.kind
  of Symbol:
    result = symBasename(n.symId)
    inc n
  of IntLit:
    result = $intValue(n)
    inc n
  of FloatLit:
    result = floatText(floatValue(n))
    inc n
  of TagLit:
    case n.exprKind
    of ErrX:
      var msg = ""
      into n:
        while n.hasMore:
          if n.kind == StrLit and msg.len == 0: msg = stringValue(n)
          skip n
      result = errMark & msg & errEnd
    of InfixX:
      into n:
        if n.kind != Symbol:
          result = expr(n)
          while n.hasMore: skip n
        else:
          let op = symBasename(n.symId)
          inc n
          let a = expr(n)
          let b = expr(n)
          result = "(" & a & " " & op & " " & b & ")"
    of CallX:
      into n:
        if n.kind != Symbol:
          result = expr(n)
          while n.hasMore: skip n
        else:
          let fn = symBasename(n.symId)
          inc n
          result = fn & "(" & args(n) & ")"
    of ExprX, ParX:
      into n:
        result = expr(n)
        while n.hasMore: skip n
    of TrueX:
      result = "true"
      skip n
    of FalseX:
      result = "false"
      skip n
    of NotX:
      into n:
        result = "(!" & expr(n) & ")"
    of NegX:
      into n:
        skip n  # the result type
        result = "(-" & expr(n) & ")"
    of AndX, OrX:
      let op = if n.exprKind == AndX: "&&" else: "||"
      into n:
        let a = expr(n)
        let b = expr(n)
        result = "(" & a & " " & op & " " & b & ")"
    of AddX, SubX, MulX, DivX, ModX, LtX, LeX, EqX, NeqX:
      let op = case n.exprKind
               of AddX: "+"
               of SubX: "-"
               of MulX: "*"
               of DivX: "/"
               of ModX: "%"
               of LtX: "<"
               of LeX: "<="
               of EqX: "=="
               else: "!="
      into n:
        skip n  # the result type
        let a = expr(n)
        let b = expr(n)
        result = "(" & a & " " & op & " " & b & ")"
    of DotX:
      into n:
        let obj = expr(n)
        let field = symBasename(n.symId)
        inc n
        result = obj & "." & field
        # the optional inheritance depth
        while n.hasMore: skip n
    else:
      result = "/*" & tagText(n) & "*/"
      skip n
  else:
    result = "/*?*/"
    skip n

proc stmt(n: var NifCursor; ind: string; lines: var string)

proc stmts(n: var NifCursor; ind: string; lines: var string) =
  into n:
    while n.hasMore:
      stmt n, ind, lines

proc isResult(n: NifCursor): bool =
  n.kind == Symbol and symBasename(n.symId) == "result"

proc stmt(n: var NifCursor; ind: string; lines: var string) =
  case n.stmtKind
  of ResultS:
    skip n
  of AsgnS:
    into n:
      let target = n
      skip n
      let value = expr(n)
      if isResult(target): lines.add ind & "return " & value & ";\n"
      else:
        var t = target
        lines.add ind & expr(t) & " = " & value & ";\n"
  of RetS:
    into n:
      if isResult(n): skip n
      else: lines.add ind & "return " & expr(n) & ";\n"
  of LetS, VarS, GletS, GvarS:
    into n:
      let name = symBasename(n.symId)
      inc n
      skip n
      skip n
      let ty = typeName(n)
      let value = expr(n)
      lines.add ind & ty & " " & name & " = " & value & ";\n"
  of StmtsS:
    stmts n, ind, lines
  of IfS:
    into n:
      var first = true
      while n.hasMore:
        case n.otherKind
        of ElifU:
          into n:
            let cond = expr(n)
            lines.add ind & (if first: "if (" else: "} else if (") & cond & ") {\n"
            stmts n, ind & "  ", lines
        of ElseU:
          into n:
            lines.add ind & "} else {\n"
            stmts n, ind & "  ", lines
        else:
          skip n
        first = false
      lines.add ind & "}\n"
  of WhileS:
    into n:
      let cond = expr(n)
      lines.add ind & "while (" & cond & ") {\n"
      stmts n, ind & "  ", lines
      lines.add ind & "}\n"
  of ForS:
    # for i in a ..< b  and  a .. b
    into n:
      var lo, hi, op = ""
      into n:
        let rangeOp = symBasename(n.symId)
        inc n
        lo = expr(n)
        hi = expr(n)
        op = if rangeOp == "..": "<=" else: "<"
      var name = ""
      into n:  # (unpackflat (let i ...))
        into n:
          name = symBasename(n.symId)
          while n.hasMore: skip n
      lines.add ind & "for (int " & name & " = " & lo & "; " & name & " " & op & " " &
        hi & "; " & name & "++) {\n"
      stmts n, ind & "  ", lines
      lines.add ind & "}\n"
  of BreakS:
    lines.add ind & "break;\n"
    skip n
  of ContinueS:
    lines.add ind & "continue;\n"
    skip n
  else:
    lines.add ind & "/* " & tagText(n) & " */\n"
    skip n

proc procDecl(n: var NifCursor; lines: var string) =
  into n:
    let name = symBasename(n.symId)
    inc n
    skip n; skip n; skip n  # exported, pattern, typevars
    var params: seq[string] = @[]
    into n:                 # (params (param name _ _ type _)*)
      while n.hasMore:
        into n:
          let pn = symBasename(n.symId)
          inc n
          skip n; skip n
          let pt = typeName(n)
          skip n
          params.add pt & " " & pn
    let rt = typeName(n)
    skip n; skip n          # pragmas, effects
    lines.add rt & " " & name & "(" & join(params, ", ") & ") {\n"
    stmts n, "  ", lines
    lines.add "}\n\n"

proc shader(n: var NifCursor): string =
  result = ""
  # (stmts <template name> (stmts <body>))
  into n:
    skip n
    into n:
      while n.hasMore:
        case n.stmtKind
        of ProcS: procDecl n, result
        of GvarS, GletS, VarS, LetS:
          var isUniform = false
          var meta = ""
          var decl = n
          into decl:
            let name = symBasename(decl.symId)
            inc decl
            skip decl
            if decl.otherKind == PragmasU:
              into decl:
                while decl.hasMore:
                  into decl:
                    let pragma = symBasename(decl.symId)
                    inc decl
                    if pragma == "uniform": isUniform = true
                    elif pragma == "uniformRange":
                      isUniform = true
                      into decl:
                        meta = " range " & expr(decl) & " .. " & expr(decl)
                    while decl.hasMore: skip decl
            else:
              skip decl
            let ty = typeName(decl)
            let value = expr(decl)
            if isUniform:
              result.add "uniform " & ty & " " & name & ";  // default " & value & meta & "\n"
            else:
              result.add ty & " " & name & " = " & value & ";\n"
          skip n
        of ConstS:
          var decl = n
          into decl:
            let name = symBasename(decl.symId)
            inc decl
            skip decl; skip decl
            let ty = typeName(decl)
            result.add "const " & ty & " " & name & " = " & expr(decl) & ";\n"
          skip n
        else:
          result.add "// top " & tagText(n) & "\n"
          skip n

proc build(info: LineInfo; src: string): NifBuilder =
  let at = src.find(errMark)
  if at >= 0:
    let stop = src.find(errEnd, at)
    let msg = src.substr(at + errMark.len, stop - 1)
    return errorTree("shader: " & (if msg.len > 0: msg else: "unsupported construct"), info)
  result = createTree()
  result.addStrLit src

var inp = loadPluginInput()
var c = inp
saveTree build(inp.info, shader(c))
