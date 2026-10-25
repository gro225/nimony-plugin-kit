import std / syncio
import vec

template glsl(body: typed): string {.plugin: "deps/glsl".}

const src = glsl:
  var speed {.uniformRange: (0.0, 4.0).} = 1.0
  var rings {.uniformRange: (2.0, 60.0).} = 18.0
  var tint {.uniform.} = vec3(0.2, 0.6, 1.0)

  const TAU = 6.283185307

  proc wave(d, phase: float): float =
    sin(d * rings - phase) * 0.5 + 0.5

  proc main(uv: Vec2): Vec4 =
    let p = (uv - 0.5) * vec2(resolution.x / resolution.y, 1.0)
    let d = length(p)

    let phase = time * speed * TAU * 0.25
    let w = wave(d, phase)

    let falloff = 1.0 - smoothstep(0.05, 0.75, d)
    let color = tint * w * falloff

    return vec4(color, 1.0)

echo src
