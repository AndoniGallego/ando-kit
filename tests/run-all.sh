#!/bin/bash
# Corre cada tests/**/test-*.sh en su propio directorio temporal.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FAILED=0
TOTAL=0

while IFS= read -r t; do
  TOTAL=$((TOTAL+1))
  tmp="$(mktemp -d)"
  echo "== ${t#"$TESTS_DIR"/}"
  if ! (cd "$tmp" && bash "$t"); then
    FAILED=$((FAILED+1))
    echo "  -> FALLÓ"
  fi
  rm -rf "$tmp"
done < <(find "$TESTS_DIR" -name 'test-*.sh' | sort)

echo ""
echo "tests: $TOTAL, fallidos: $FAILED"
[ "$FAILED" -eq 0 ]
