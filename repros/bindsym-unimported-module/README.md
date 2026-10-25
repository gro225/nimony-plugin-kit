A template plugin that imports a module and returns a `bindSym` reference to a
proc of it. The calling module does not import that module.

```sh
nimony c -r main.nim
```

Result on nightly 0.6.3-83f492b48:

```
[Error] cannot open: nimcache/hel14jpgv.s.nif
```

With `import deps/helper` added to `main.nim`, it prints `42`.

Expected: the symbol resolves, or sem says clearly that the module is missing.
With a larger module (`std/monotimes`) the same shape gets past sem and then
crashes the backend: ``dce2.nim(70, 15) `sowner in result` sowner is not in
result for getMonoTime``. See `examples/timed`.
