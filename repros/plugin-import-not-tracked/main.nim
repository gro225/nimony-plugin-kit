import std / syncio

template hello(): string {.plugin: "deps/plug".}

echo hello()
