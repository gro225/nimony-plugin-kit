## Just enough vector types for the plasma-shaped experiment; the real shd
## library lives in src/shd/core.nim and is not ported

type
  Vec2* = object
    x*, y*: float
  Vec3* = object
    x*, y*, z*: float
  Vec4* = object
    x*, y*, z*, w*: float

proc vec2*(x, y: float): Vec2 = Vec2(x: x, y: y)
proc vec3*(x, y, z: float): Vec3 = Vec3(x: x, y: y, z: z)
proc vec4*(v: Vec3, w: float): Vec4 = Vec4(x: v.x, y: v.y, z: v.z, w: w)

proc `-`*(a: Vec2, b: float): Vec2 = Vec2(x: a.x - b, y: a.y - b)
proc `*`*(a, b: Vec2): Vec2 = Vec2(x: a.x * b.x, y: a.y * b.y)
proc `*`*(a: Vec3, b: float): Vec3 = Vec3(x: a.x * b, y: a.y * b, z: a.z * b)
proc length*(a: Vec2): float = a.x * a.x + a.y * a.y
proc smoothstep*(a, b, x: float): float = x

template uniform*() {.pragma.}
template uniformRange*(lo, hi: float) {.pragma.}

# builtin uniforms of the real shd, here plain lets so the typed body can read them
let time* = 0.0
let resolution* = Vec2(x: 1.0, y: 1.0)

proc sin*(x: float): float = x
proc `+`*(a: float, b: Vec2): Vec2 = b
