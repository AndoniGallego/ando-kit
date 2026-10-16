#!/bin/bash
# Helpers de tests: HOME aislado y asserts simples. Se hace source desde cada test.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0
FAIL=0

setup_home() {
  TEST_TMP="$(mktemp -d)"
  trap 'rm -rf "$TEST_TMP"' EXIT
  export HOME="$TEST_TMP/home"
  mkdir -p "$HOME/.claude" "$HOME/.local/bin"
  export ANDO_KIT_DIR="$REPO_ROOT"
  unset ANDO_KIT_CHECK_SCRIPT ANDO_KIT_DOCTOR_CHECK_TIMEOUT ANDO_SPECS_DIR ANDO_KIT_AUTOUPDATE
}

case_pass() { PASS=$((PASS+1)); echo "  ok   $1"; }
case_fail() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

assert_eq() {
  if [ "$2" = "$3" ]; then case_pass "$1"; else case_fail "$1 (esperado '$2', obtenido '$3')"; fi
}
assert_contains() {
  case "$3" in *"$2"*) case_pass "$1" ;; *) case_fail "$1 (no contiene '$2')" ;; esac
}
assert_not_contains() {
  case "$3" in *"$2"*) case_fail "$1 (contiene '$2')" ;; *) case_pass "$1" ;; esac
}

finish() { echo "pass=$PASS fail=$FAIL"; [ "$FAIL" -eq 0 ]; }
