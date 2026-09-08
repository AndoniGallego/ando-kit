#!/bin/bash
# ando-sdd-gate.sh — helper de gate SDD. NO es un hook por sí solo: lo invoca
# ando-prepush-check.sh y clasifica su salida así:
#   - líneas que empiezan con "BLOCK: " → ando-prepush-check las promueve a un
#     `decision: block` (el push NO procede hasta resolver).
#   - cualquier otra línea → advertencia (el push procede).
#
# Uso:   ando-sdd-gate.sh <branch>
# stdout: 0+ líneas (ver arriba); vacío si el gate no aplica. Siempre exit 0.
#
# FILOSOFÍA (el usuario cambió de opinión sobre esto — 2026-09-07):
# la spec es REQUERIDA cuando el orquestador la consideró necesaria. La señal
# persistida de "se consideró necesaria" es la EXISTENCIA del archivo
# $ANDO_SPECS_DIR/<id>.md. Por eso:
#   - archivo NO existe  → el orquestador no arrancó SDD para esto (tarea trivial,
#                          o el usuario lo vetó) → gate MUDO. No se nag "te falta la spec".
#   - archivo existe y status=approved → OK, mudo.
#   - archivo existe y status != approved → BLOCK: hay una spec a medias para esta rama.
#
# OPT-IN: sin ANDO_SPECS_DIR seteado, el chequeo de spec se omite (solo corre el
# chequeo de specs/ dentro del repo, y ese es siempre advertencia, nunca BLOCK).
#
# Exenciones (nunca se les pide spec):
#   - hotfix/*        → urgencia de prod
#   - feature/kit-*   → cambios al propio kit
#   - ramas que no matchean feature/<algo>

set -uo pipefail

BRANCH="${1:-}"
[ -z "$BRANCH" ] && exit 0

case "$BRANCH" in
  hotfix/*|feature/kit-*) exit 0 ;;
esac

# id = lo que sigue a "feature/". Acepta slug kebab (rate-limit-login) o TICKET-ID (SITE-1234).
case "$BRANCH" in
  feature/*) ID="${BRANCH#feature/}" ;;
  *) ID="" ;;
esac

# --- 1) Spec en ANDO_SPECS_DIR (la requerida) ---
if [ -n "$ID" ] && [ -n "${ANDO_SPECS_DIR:-}" ]; then
  # Sanitizar: solo un segmento de path, caracteres seguros.
  case "$ID" in
    */*|..*|"") : ;;  # id raro → no arriesgar, saltar
    *)
      if echo "$ID" | grep -qE '^[A-Za-z0-9._-]+$'; then
        SPEC_FILE="$ANDO_SPECS_DIR/$ID.md"
        if [ -f "$SPEC_FILE" ]; then
          STATUS=$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^status:/{sub(/^status:[ \t]*/,""); sub(/[ \t]+$/,""); print; exit}' "$SPEC_FILE")
          if [ "$STATUS" != "approved" ]; then
            echo "BLOCK: la spec $SPEC_FILE está en '${STATUS:-sin frontmatter}' y es requerida antes de pushear $BRANCH. Aprobala (sdd-start la retoma desde el paso de revisión), o archivala/borrala si decidiste no seguir SDD para esta tarea."
          fi
        fi
      fi
      ;;
  esac
fi

# --- 2) specs/ dentro del repo (siempre advertencia, nunca BLOCK) ---
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/specs" ]; then
  MERGE_BASE=$(git merge-base HEAD "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" 2>/dev/null \
    || git merge-base HEAD origin/HEAD 2>/dev/null \
    || git merge-base HEAD origin/main 2>/dev/null \
    || git merge-base HEAD origin/master 2>/dev/null)
  if [ -n "$MERGE_BASE" ]; then
    SPECS_CHANGED=$(git diff --name-only "$MERGE_BASE"..HEAD -- specs/ 2>/dev/null | wc -l | tr -d ' ')
    if [ "$SPECS_CHANGED" -eq 0 ]; then
      echo "SDD: el repo tiene specs/ pero ningún archivo fue actualizado en este branch — correr spec-updater si el cambio impactó requirements/design."
    fi
  fi
fi

exit 0
