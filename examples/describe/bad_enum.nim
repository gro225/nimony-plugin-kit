import std / syncio

type
  Color = enum
    red, green

template defineDescribe(T: typedesc) {.plugin: "deps/describe".}

defineDescribe(Color)
