import std / [syncio, monotimes]

template timed(label: string, body: untyped) {.plugin: "deps/timed".}

# the block declares its own `start`; the macro's own one must not clash
timed "collide":
  var start = 5
  echo start
