#!/bin/sh
# Runs every check against the installed nimony; prints one line per check
cd "$(dirname "$0")/.." || exit 1
fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "  want: $2"; echo "  got:  $3"; fail=1; fi
}

check "kit: len, [] and children" \
  'let/5[SymbolDef:a];var/5[SymbolDef:b];proc/9[SymbolDef:f];' \
  "$(cd tests && nimony c -r shape.nim 2>/dev/null)"

cd examples/glsl || exit 1
check "glsl example: plasma" "$(cat plasma.expected)" "$(nimony c -r plasma.nim 2>/dev/null)"
check "glsl example: control flow" "$(cat cf.expected)" "$(nimony c -r cf.nim 2>/dev/null)"

sed 's/let d = length(p)/let d = lengthh(p)/' plasma.nim > bad.nim
msg=$(nimony check bad.nim 2>&1 | head -1 | sed 's/^bad.nim([0-9, ]*) //')
rm -f bad.nim
check "glsl example: sem error is reported" "Error: shader: undeclared identifier: 'lengthh'" "$msg"
exit $fail
