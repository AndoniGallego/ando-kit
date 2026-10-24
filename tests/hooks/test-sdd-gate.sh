#!/bin/bash
# ando-sdd-gate.sh: approved y done pasan; draft bloquea; sin archivo, mudo.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
setup_home

GATE="$REPO_ROOT/hooks/ando-sdd-gate.sh"
export ANDO_SPECS_DIR="$TEST_TMP/specs"
mkdir -p "$ANDO_SPECS_DIR"

spec() { printf -- '---\nstatus: %s\n---\ncuerpo\n' "$2" > "$ANDO_SPECS_DIR/$1.md"; }
gate() { (cd "$TEST_TMP" && bash "$GATE" "feature/$1" 2>/dev/null); }

spec t-draft draft
assert_contains "draft bloquea" "BLOCK:" "$(gate t-draft)"
spec t-approved approved
assert_eq "approved pasa" "" "$(gate t-approved)"
spec t-done done
assert_eq "done pasa" "" "$(gate t-done)"
assert_eq "sin spec: mudo" "" "$(gate t-inexistente)"

finish
