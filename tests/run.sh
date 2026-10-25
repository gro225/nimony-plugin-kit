#!/bin/sh
# Runs every check against the installed nimony; prints one line per check
cd "$(dirname "$0")/.." || exit 1
fail=0
# A plugin is not rebuilt when a module it imports changes (repros/plugin-import-not-tracked),
# so start from nothing to be sure a check runs the code as it is now
rm -rf tests/nimcache examples/glsl/nimcache examples/glsl/without-kit/nimcache examples/timed/nimony/nimcache examples/describe/nimcache
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
check "glsl example: the version without the kit gives the same output" "$(cat plasma.expected)" "$(cd without-kit && nimony c -r plasma.nim 2>/dev/null)"

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

# a broken copy under another name, so the real plugin and its build never change
sed 's/let \$1 = \$2 \* 10/let = $2 * 10/' deps/twice.nim > deps/twice_bad.nim
sed 's#deps/twice#deps/twice_bad#' quote.nim > quote_bad.nim
msg=$(nimony check quote_bad.nim 2>&1 | head -1)
rm -f deps/twice_bad.nim quote_bad.nim
check "quote: a syntax error points into the quoted code" \
  "quote_bad.nim(9, 9) Error: identifier expected, but got '=' (at 1, 5 of the parsed code)" "$msg"

cd ../examples/timed/nimony || exit 1
out=$(nimony c -r main.nim 2>/dev/null | sed -E 's/^(sum): [0-9]+ us$/\1: N us/')
check "timed: block runs, then its time is printed" "4999950000
sum: N us" "$out"
out=$(nimony c -r collide.nim 2>/dev/null | sed -E 's/^(collide): [0-9]+ us$/\1: N us/')
check "timed: a fresh name does not clash with the block's own" "5
collide: N us" "$out"
out=$(nimony c -r viaimport.nim 2>/dev/null | sed -E 's/^(sum): [0-9]+ us$/\1: N us/')
check "timed: the template is exported from a module" "4999950000
sum: N us" "$out"
cd ../../describe || exit 1
check "describe: a proc generated from an object's fields" "Person(name: Ann, age: 30)
Point(x: 1.5, y: 2.0)" "$(nimony c -r main.nim 2>/dev/null)"
msg=$(nimony check bad_enum.nim 2>&1 | head -1)
check "describe: an enum is refused at the argument" \
  "bad_enum.nim(9, 16) Error: defineDescribe needs an object type, Color is not one" "$msg"
msg=$(nimony check bad_int.nim 2>&1 | head -1)
check "describe: a non-object type is refused at the argument" \
  "bad_int.nim(5, 16) Error: defineDescribe needs an object type, int is not one" "$msg"
cd ../../tests || exit 1
check "kit: pair, two needs are answered in one round" "Cat+Dog" "$(rm -f runs.txt; nimony c -r pair.nim 2>/dev/null)"
check "kit: and the plugin ran twice, not three times" "2" "$(wc -l < runs.txt | tr -d ' ')"
rm -f runs.txt
check "kit: $ and treeRepr" '(stmts (let a . . . (infix + 1 2)) (cmd echo "hi" a))
--
(stmts
  (let a . . .
    (infix + 1 2))
  (cmd echo "hi" a))' "$(nimony c -r show.nim 2>/dev/null)"
exit $fail
