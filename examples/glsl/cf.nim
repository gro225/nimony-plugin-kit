import std / syncio
import vec

template glsl(body: typed): string {.plugin: "deps/glsl".}

const src = glsl:
  var speed {.uniform.} = 1.0
  var rings {.uniformRange: (0.0, 4.0).} = 18.0
  const TAU = 6.283185307

  proc main(uv: Vec2): Vec4 =
    var acc = 0.0
    for i in 0 ..< 4:
      acc = acc + speed
    if acc > 2.0:
      acc = acc - 1.0
    elif acc < 0.0:
      acc = 0.0
    else:
      acc = acc * TAU
    return vec4(vec3(acc, rings, 0.0), 1.0)
echo src
