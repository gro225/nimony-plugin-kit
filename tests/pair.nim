import std / syncio

type
  Cat = object
    lives: int
  Dog = object
    good: bool

template pair[A, B](a: typedesc[A], b: typedesc[B]): string {.plugin: "deps/pair".}

const s = pair(Cat, Dog)
echo s
