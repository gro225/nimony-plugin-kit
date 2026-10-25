## `import timedlib` gives `timed`, the way `import timed` does in the Nim 2 version

template timed*(label: string, body: untyped) {.plugin: "deps/timed".}
