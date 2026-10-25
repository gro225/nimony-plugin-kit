import std / [macros, monotimes]

macro timed*(label: string, body: untyped): untyped =
  ## Runs `body` and prints how long it took
  result = quote do:
    block:
      let start = getMonoTime()
      `body`
      echo `label`, ": ", (getMonoTime().ticks - start.ticks) div 1000, " us"
