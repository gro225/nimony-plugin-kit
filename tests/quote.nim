import std / syncio

template twice(x: untyped) {.plugin: "deps/twice".}
template times10(name, value: untyped) {.plugin: "deps/twice".}

twice:
  echo "hi"

times10(answer, 4)
echo answer + 2
