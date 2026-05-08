#!/bin/bash
set -e

COMPILER_CMD="zig build run --"
TESTS_DIR="$(dirname "$0")"
PASS=0
FAIL=0

for chisa_file in "$TESTS_DIR"/*.chisa; do
  name=$(basename "$chisa_file" .chisa)
  out="/tmp/chisa_e2e_$name"

  echo -n "Testing $name ... "
  if $COMPILER_CMD -r -i "$chisa_file" -o "$out" 2>/tmp/chisa_e2e_err.txt && "$out" > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    cat /tmp/chisa_e2e_err.txt
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
