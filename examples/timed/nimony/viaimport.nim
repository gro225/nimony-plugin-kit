import std / [syncio, monotimes]
import timedlib

timed "sum":
  var s = 0
  for i in 0 ..< 100000:
    s += i
  echo s
