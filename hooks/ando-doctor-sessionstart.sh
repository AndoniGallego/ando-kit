#!/bin/bash
# ando-doctor-sessionstart.sh — Hook SessionStart
#
# Corre kit-doctor una vez al iniciar sesión. SILENCIOSO si todo está ✅ — solo
# habla cuando hay algo real para reportar (⚠️ o ❌). No bloquea nada: es un aviso.
#
# Skip rápido si querés arrancar sin esperar el chequeo:
#   ANDO_SKIP_DOCTOR=1 claude
#
# El hook nunca debe romper el arranque: cualquier fallo termina en exit 0.

set -uo pipefail

[ -n "${ANDO_SKIP_DOCTOR:-}" ] && exit 0

DOCTOR="$HOME/.claude/skills/kit-doctor/scripts/doctor.sh"
[ -f "$DOCTOR" ] || exit 0

OUTPUT=$(bash "$DOCTOR" 2>/dev/null) || true
RESUMEN=$(printf '%s\n' "$OUTPUT" | grep 'RESUMEN:' || true)

# Contar ⚠️ y ❌ del resumen ("=== RESUMEN: N ✅  M ⚠️  K ❌ ===")
WARN=$(printf '%s\n' "$RESUMEN" | grep -oE '[0-9]+ ⚠️' | grep -oE '[0-9]+' || echo 0)
FAIL=$(printf '%s\n' "$RESUMEN" | grep -oE '[0-9]+ ❌' | grep -oE '[0-9]+' || echo 0)

if { [ "${WARN:-0}" -eq 0 ] && [ "${FAIL:-0}" -eq 0 ]; } 2>/dev/null; then
  exit 0
fi

# Hay algo para reportar: mostrar solo las líneas problemáticas + el resumen.
PROBLEMS=$(printf '%s\n' "$OUTPUT" | grep -E '  (⚠️|❌)' || true)
printf 'kit-doctor detectó %s advertencia(s) y %s error(es) al iniciar sesión:\n%s\n\nCorré /kit-doctor para el detalle y los fixes sugeridos.\n' \
  "${WARN:-0}" "${FAIL:-0}" "$PROBLEMS"

exit 0
