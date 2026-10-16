#!/bin/bash
# Contrato de ando-kit-check.sh: stdout = un JSON, stderr = progreso, exit 0/1/2.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
setup_home

CHECK="$REPO_ROOT/scripts/ando-kit-check.sh"

OUT="$TEST_TMP/out"; ERR="$TEST_TMP/err"
bash "$CHECK" >"$OUT" 2>"$ERR"; rc=$?

jq -e . "$OUT" >/dev/null 2>&1 && case_pass "stdout es JSON válido" || case_fail "stdout es JSON válido"
assert_eq "stdout es un único documento" "1" "$(jq -s 'length' "$OUT")"
assert_eq "version coincide con VERSION" "$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")" "$(jq -r .version "$OUT")"

SECCIONES="KIT DEPENDENCIAS SYNC HOOKS SETTINGS CLAUDE.md SEGURIDAD OPCIONALES"
for s in $SECCIONES; do
  [ "$(jq --arg s "$s" '.report | has($s)' "$OUT")" = "true" ] \
    && case_pass "sección $s presente" || case_fail "sección $s presente"
done

jq -e '[.report[][] | (.level | IN("ok","warn","fail","info")) and (.text | type == "string")] | all' "$OUT" >/dev/null \
  && case_pass "cada ítem tiene level válido y text string" || case_fail "forma de ítems"

for l in ok warn fail; do
  assert_eq "summary.$l coincide con report" \
    "$(jq --arg l "$l" '[.report[][] | select(.level == $l)] | length' "$OUT")" "$(jq ".summary.$l" "$OUT")"
done

nfail="$(jq .summary.fail "$OUT")"
if [ "$nfail" -gt 0 ]; then assert_eq "exit 1 con fails" "1" "$rc"; else assert_eq "exit 0 sin fails" "0" "$rc"; fi
# HOME vacío: sin CLAUDE.md ni hooks instalados debe haber fails
[ "$nfail" -gt 0 ] && case_pass "HOME aislado vacío produce fails" || case_fail "HOME aislado vacío produce fails"

[ -s "$ERR" ] && case_pass "stderr tiene progreso" || case_fail "stderr tiene progreso"
assert_not_contains "stderr no contamina stdout" "[ok]" "$(cat "$OUT")"

bash "$CHECK" extra >/dev/null 2>&1; assert_eq "argumentos -> exit 2" "2" "$?"

# Sin fails: HOME mínimo sano
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents"
cp -r "$REPO_ROOT/skills/." "$HOME/.claude/skills/"
cp -r "$REPO_ROOT/agents/." "$HOME/.claude/agents/"
cp "$REPO_ROOT"/hooks/*.sh "$HOME/.local/bin/"
echo "ando-kit" > "$HOME/.claude/CLAUDE.md"
echo '{}' > "$HOME/.claude/settings.json"
bash "$CHECK" >"$OUT" 2>/dev/null; rc=$?
assert_eq "HOME sano: summary.fail=0" "0" "$(jq .summary.fail "$OUT")"
assert_eq "HOME sano: exit 0" "0" "$rc"

finish
