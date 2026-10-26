## Typed views of the constructs a plugin reads: `asRoutine`, `asLocal`,
## `asTypeDecl`, ... Each returns an object whose fields are cursors at the named
## parts of the node, so a plugin says `r.params` and not "child number four"
##
## The slot positions live here and nowhere else, which is the idea of `decls.nim`
## inside the compiler (`asTypeDecl`, `asRoutine`, `asLocal`, `asForStmt`); the
## names of the objects and fields follow it. A view is a plain copy of cursors, so
## the node it was made from does not move

import std / assertions
import plugins

proc slot(n: NifCursor; i: int): NifCursor =
  ## Child `i` of the compound node `n`; private, the views below are the way in
  assert n.kind == TagLit, "a view needs a compound node"
  result = firstChild(n)
  var k = 0
  while k < i:
    skip result
    inc k

iterator children*(n: NifCursor): NifCursor {.sideEffect.} =
  ## The children of `n`, each as a cursor positioned at that child
  if n.kind == TagLit:
    var c = firstChild(n)
    while c.hasMore:
      yield c
      skip c

proc name*(n: NifCursor): string =
  ## Text of a symbol (without the module suffix) or of an identifier
  case n.kind
  of Symbol, SymbolDef: result = symBasename(n.symId)
  of Ident: result = identText(n)
  else: result = ""

type
  Local* = object
    ## `let`, `var`, `const`, a parameter or a field:
    ## `(let name export pragmas type value)`
    name*, exported*, pragmas*, typ*, val*: NifCursor

  Routine* = object
    ## `(proc name export pattern typevars params rettype pragmas effects body)`,
    ## the same for `func`, `iterator`, `template` and the others
    name*, exported*, pattern*, typevars*, params*, retType*,
      pragmas*, effects*, body*: NifCursor

  TypeDecl* = object
    ## `(type name export typevars pragmas body)`
    name*, exported*, typevars*, pragmas*, body*: NifCursor

  ObjectDecl* = object
    ## `(object parent field*)`; `fields` walks the plain fields
    parentType*: NifCursor
    node: NifCursor

  ForStmt* = object
    ## `(for iter vars body)`
    iter*, vars*, body*: NifCursor

  WhileStmt* = object
    ## `(while cond body)`
    cond*, body*: NifCursor

  Branch* = object
    ## One arm of an `if`: `(elif cond body)`, or `(else body)` with `isElse`
    isElse*: bool
    cond*, body*: NifCursor

  Call* = object
    ## `(call fn arg*)`; `args` walks the arguments
    fn*: NifCursor
    node: NifCursor

  Infix* = object
    ## `(infix op lhs rhs)`
    op*, lhs*, rhs*: NifCursor

  Binary* = object
    ## `(and lhs rhs)`, `(or lhs rhs)`
    lhs*, rhs*: NifCursor

  TypedOp* = object
    ## An operator that carries its result type: `(add type lhs rhs)`, and the
    ## unary `(neg type operand)`, where `rhs` is empty
    typ*, lhs*, rhs*: NifCursor

  Asgn* = object
    ## `(asgn lhs rhs)`
    lhs*, rhs*: NifCursor

  Dot* = object
    ## `(dot object field)`
    obj*, field*: NifCursor

  Pragma* = object
    ## `(pragma name arg*)`; the arguments are positional because the pragma's
    ## own parameters are
    name*: NifCursor
    args*: seq[NifCursor]

  PluginCall* = object
    ## What a template plugin receives: `(stmts name arg*)`, the arguments in the
    ## order of the template's parameters
    name*: NifCursor
    args*: seq[NifCursor]

proc asLocal*(c: NifCursor): Local =
  Local(name: slot(c, 0), exported: slot(c, 1), pragmas: slot(c, 2),
        typ: slot(c, 3), val: slot(c, 4))

proc asRoutine*(c: NifCursor): Routine =
  Routine(name: slot(c, 0), exported: slot(c, 1), pattern: slot(c, 2),
          typevars: slot(c, 3), params: slot(c, 4), retType: slot(c, 5),
          pragmas: slot(c, 6), effects: slot(c, 7), body: slot(c, 8))

proc isGeneric*(r: Routine): bool =
  r.typevars.otherKind == TypevarsU

proc asTypeDecl*(c: NifCursor): TypeDecl =
  TypeDecl(name: slot(c, 0), exported: slot(c, 1), typevars: slot(c, 2),
           pragmas: slot(c, 3), body: slot(c, 4))

proc isGeneric*(t: TypeDecl): bool =
  t.typevars.otherKind == TypevarsU

proc asObjectDecl*(c: NifCursor): ObjectDecl =
  assert c.typeKind == ObjectT, "asObjectDecl needs an object type"
  ObjectDecl(parentType: slot(c, 0), node: c)

iterator fields*(o: ObjectDecl): Local {.sideEffect.} =
  ## The plain fields; a `case` or `when` part of the object is skipped
  var first = true
  for f in o.node.children:
    if first:
      first = false                     # the parent type
    elif f.otherKind in {FldU, GfldU}:
      yield asLocal(f)

iterator parameters*(r: Routine): Local {.sideEffect.} =
  ## The parameters of a routine, as `Local`s
  if r.params.kind == TagLit:
    for p in r.params.children:
      yield asLocal(p)

proc asForStmt*(c: NifCursor): ForStmt =
  ForStmt(iter: slot(c, 0), vars: slot(c, 1), body: slot(c, 2))

proc asWhileStmt*(c: NifCursor): WhileStmt =
  WhileStmt(cond: slot(c, 0), body: slot(c, 1))

iterator branches*(c: NifCursor): Branch {.sideEffect.} =
  ## The arms of an `if` statement in order, the `else` last
  for arm in c.children:
    case arm.otherKind
    of ElifU: yield Branch(cond: slot(arm, 0), body: slot(arm, 1))
    of ElseU: yield Branch(isElse: true, body: slot(arm, 0))
    else: discard

proc asCall*(c: NifCursor): Call =
  Call(fn: slot(c, 0), node: c)

iterator args*(call: Call): NifCursor {.sideEffect.} =
  var first = true
  for a in call.node.children:
    if first: first = false             # the callee
    else: yield a

proc asInfix*(c: NifCursor): Infix =
  Infix(op: slot(c, 0), lhs: slot(c, 1), rhs: slot(c, 2))

proc asBinary*(c: NifCursor): Binary =
  Binary(lhs: slot(c, 0), rhs: slot(c, 1))

proc asTypedOp*(c: NifCursor): TypedOp =
  ## `rhs` is left at the cursor's default for a unary operator
  result = TypedOp(typ: slot(c, 0), lhs: slot(c, 1))
  var n = 0
  for _ in c.children: inc n
  if n > 2: result.rhs = slot(c, 2)

proc asAsgn*(c: NifCursor): Asgn =
  Asgn(lhs: slot(c, 0), rhs: slot(c, 1))

proc asDot*(c: NifCursor): Dot =
  Dot(obj: slot(c, 0), field: slot(c, 1))

proc asPluginCall*(c: NifCursor): PluginCall =
  ## The call a template plugin was started for, from `loadPluginInput()`
  assert c.stmtKind == StmtsS, "a plugin call is a (stmts name arg*)"
  result = PluginCall(name: slot(c, 0), args: @[])
  var first = true
  for a in c.children:
    if first: first = false
    else: result.args.add a

proc asPragma*(c: NifCursor): Pragma =
  assert c.kind == TagLit, "a pragma is (pragma name arg*)"
  result = Pragma(name: slot(c, 0), args: @[])
  var first = true
  for a in c.children:
    if first: first = false
    else: result.args.add a

proc elements*(n: NifCursor): seq[NifCursor] =
  ## The children of `n` as a list, for the places where position is what the
  ## construct means, such as a tuple `(tup lo hi)`
  result = @[]
  for c in n.children:
    result.add c
