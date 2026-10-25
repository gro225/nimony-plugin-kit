import std / syncio

template defineDescribe(T: typedesc) {.plugin: "deps/describe".}

defineDescribe(int)
