import std / syncio

template shape(body: typed): string {.plugin: "deps/shape".}

const s = shape:
  let a = 1.5
  var b = 2
  proc f(x: float): float = x

echo s
