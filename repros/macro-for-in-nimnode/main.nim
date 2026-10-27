import std / [syncio, macros]

macro each(body: untyped): untyped =
  result = newStmtList()
  for c in body:
    result.add c

each:
  echo "a"
  echo "b"
