import std / macros

macro defineDescribe*(T: typedesc): untyped =
  ## Declares `describe(x: T): string`, which writes the object's fields
  let typ = T.getTypeInst[1]
  if typ.getTypeImpl.kind != nnkObjectTy:
    error("defineDescribe needs an object type, " & typ.strVal & " is not one", T)
  let rec = typ.getTypeImpl[2]          # nnkRecList
  let x = ident"x"
  var body = newStmtList()
  let head = typ.strVal & "("
  body.add quote do:
    result = `head`
  var first = true
  for defs in rec:                      # nnkIdentDefs: names..., type, default
    for i in 0 ..< defs.len - 2:
      let fname = ident(defs[i].strVal)
      let label = (if first: "" else: ", ") & defs[i].strVal & ": "
      first = false
      body.add quote do:
        result.add `label` & $(`x`.`fname`)
  body.add quote do:
    result.add ")"
  result = newProc(ident"describe", [ident"string", newIdentDefs(x, typ)], body)
