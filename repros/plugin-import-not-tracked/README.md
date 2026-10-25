A template plugin imports a sibling module. After the sibling is edited the
plugin is not rebuilt, so the program keeps using the old plugin output.

```sh
nimony c -r main.nim            # prints: one
# change "one" to "two" in deps/helper.nim
nimony c -r main.nim            # still prints: one
touch deps/plug.nim
nimony c -r main.nim            # prints: two
```

Result on nightly 0.6.3-83f492b48. Only a change to the plugin's own file
rebuilds it. Expected: a change to any module the plugin imports rebuilds it,
as it does for an ordinary program.

Why it matters: a plugin that imports shared code (the standard library's
`typetraits` plugin imports `typetraits_render`) can silently run stale code
after an edit, and a failing test can look like it passes.
