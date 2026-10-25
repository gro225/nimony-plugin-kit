import std / syncio

type
  Person = object
    name: string
    age: int

  Point = object
    x, y: float

template defineDescribe(T: typedesc) {.plugin: "deps/describe".}

defineDescribe(Person)
defineDescribe(Point)

echo describe(Person(name: "Ann", age: 30))
echo describe(Point(x: 1.5, y: 2.0))
