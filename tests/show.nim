import std / syncio

template show(body: untyped): string {.plugin: "deps/show".}

const s = show:
  let a = 1 + 2
  echo "hi", a

echo s
