#!/bin/bash
set -e

COMPILER_CMD="zig build run --"
TESTS_DIR="$(dirname "$0")"
PASS=0
FAIL=0

for zs_file in "$TESTS_DIR"/*.zs; do
  name=$(basename "$zs_file" .zs)
  out="/tmp/zs_e2e_$name"

  echo -n "Testing $name ... "
  if $COMPILER_CMD -i "$zs_file" -o "$out" 2>/tmp/zs_e2e_err.txt && "$out" > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    cat /tmp/zs_e2e_err.txt
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
