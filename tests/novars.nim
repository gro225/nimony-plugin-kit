import std / syncio

template novars(body: typed): string {.plugin: "deps/novars".}

const s = novars:
  let a = 1
  var b = 2
  var c = 3

echo s
