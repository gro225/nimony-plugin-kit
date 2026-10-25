import std / syncio

template show() {.plugin: "deps/plug".}

show()
