import std / monotimes
import timed

timed "sum":
  var s = 0
  for i in 0 ..< 100000:
    s += i
  echo s
