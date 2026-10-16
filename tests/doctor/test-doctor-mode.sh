#!/bin/bash
# doctor.sh: modo normal con ando-kit-check.sh y modo degradado ante script ausente/colgado/roto.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
setup_home

DOCTOR="$REPO_ROOT/skills/kit-doctor/scripts/doctor.sh"
export ANDO_KIT_DOCTOR_CHECK_TIMEOUT=1

# Stubs
STUB_OK="$TEST_TMP/stub-ok.sh"
cat > "$STUB_OK" <<'EOS'
#!/bin/bash
echo '{"version":"0","report":{"STUB":[{"level":"ok","text":"desde el stub"},{"level":"warn","text":"aviso stub"},{"level":"info","text":"nota stub"}]},"summary":{"ok":1,"warn":1,"fail":0}}'
EOS
STUB_FAIL="$TEST_TMP/stub-fail.sh"
cat > "$STUB_FAIL" <<'EOS'
#!/bin/bash
echo '{"version":"0","report":{"STUB":[{"level":"fail","text":"roto stub"}]},"summary":{"ok":0,"warn":0,"fail":1}}'
exit 1
EOS
STUB_HANG="$TEST_TMP/stub-hang.sh"
printf '#!/bin/bash\nsleep 30\n' > "$STUB_HANG"
STUB_EXIT2="$TEST_TMP/stub-exit2.sh"
printf '#!/bin/bash\necho fatal >&2\nexit 2\n' > "$STUB_EXIT2"
STUB_GARBAGE="$TEST_TMP/stub-garbage.sh"
printf '#!/bin/bash\necho "esto no es json"\n' > "$STUB_GARBAGE"
STUB_BADSHAPE="$TEST_TMP/stub-badshape.sh"
printf '#!/bin/bash\necho %s\n' "'{\"report\":{\"X\":[{\"level\":\"ok\",\"text\":5}]}}'" > "$STUB_BADSHAPE"

run_doctor() { OUT="$(ANDO_KIT_CHECK_SCRIPT="$1" bash "$DOCTOR" 2>/dev/null)"; RC=$?; }

# Modo normal con el script real
OUT="$(ANDO_KIT_DOCTOR_CHECK_TIMEOUT=60 bash "$DOCTOR" 2>/dev/null)"; RC=$?
assert_not_contains "script real: sin modo degradado" "modo degradado" "$OUT"
assert_contains "script real: renderiza secciones" "KIT" "$OUT"
assert_contains "script real: línea RESUMEN" "=== RESUMEN:" "$OUT"

# Stub sano: se renderiza lo del stub
run_doctor "$STUB_OK"
assert_contains "stub ok: texto del stub" "✅ desde el stub" "$OUT"
assert_contains "stub ok: warn" "⚠️  aviso stub" "$OUT"
assert_contains "stub ok: info" "ℹ️  nota stub" "$OUT"
assert_contains "stub ok: resumen" "RESUMEN: 1 ✅  1 ⚠️  0 ❌" "$OUT"
assert_not_contains "stub ok: sin degradado" "modo degradado" "$OUT"
assert_eq "stub ok: exit 0" "0" "$RC"

# Stub con fail: exit 1 del doctor
run_doctor "$STUB_FAIL"
assert_contains "stub fail: ❌" "❌ roto stub" "$OUT"
assert_eq "stub fail: exit 1" "1" "$RC"

# Modos degradados
if timeout --version 2>&1 | grep -q GNU; then
  run_doctor "$STUB_HANG"
  assert_contains "cuelga: modo degradado por timeout" "modo degradado: ando-kit-check.sh excedió 1s" "$OUT"
  assert_contains "cuelga: igual produce RESUMEN" "=== RESUMEN:" "$OUT"
else
  echo "  skip timeout GNU no disponible"
fi

run_doctor "$STUB_EXIT2"
assert_contains "exit 2: modo degradado" "modo degradado: ando-kit-check.sh salió con código 2" "$OUT"
assert_contains "exit 2: chequeos embebidos corren" "KIT" "$OUT"

run_doctor "$STUB_GARBAGE"
assert_contains "basura: modo degradado" "modo degradado: ando-kit-check.sh devolvió JSON inválido" "$OUT"

run_doctor "$STUB_BADSHAPE"
assert_contains "forma incorrecta: modo degradado" "JSON inválido" "$OUT"

run_doctor "$TEST_TMP/no-existe.sh"
assert_contains "inexistente: modo degradado" "modo degradado: ando-kit-check.sh no encontrado" "$OUT"
assert_contains "inexistente: RESUMEN" "=== RESUMEN:" "$OUT"

finish
