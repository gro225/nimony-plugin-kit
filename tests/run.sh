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
msg=$(nimony check bad.nim 2>&1 | head -1)
rm -f bad.nim
check "glsl example: sem error is reported at its own line" \
  "bad.nim(18, 13) Error: undeclared identifier: 'lengthh'" "$msg"

cd ../../tests || exit 1
msg=$(nimony check novars.nim 2>&1 | head -1)
check "kit: fail reports at the node, first error only" \
  "novars.nim(7, 7) Error: no variables allowed here: b" "$msg"
check "quote: holes are replaced by nodes" "hi
hi
42" "$(nimony c -r quote.nim 2>/dev/null)"

cp deps/twice.nim deps/twice.keep
sed -i.bak 's/let \$1 = \$2 \* 10/let = $2 * 10/' deps/twice.nim
msg=$(nimony check quote.nim 2>&1 | head -1)
mv deps/twice.keep deps/twice.nim; rm -f deps/twice.nim.bak
check "quote: a syntax error points into the quoted code" \
  "quote.nim(9, 9) Error: identifier expected, but got '=' (at 1, 5 of the parsed code)" "$msg"
exit $fail
