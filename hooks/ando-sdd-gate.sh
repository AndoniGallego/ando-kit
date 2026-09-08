#!/bin/bash
# ando-sdd-gate.sh — helper de gate SDD (Spec-Driven Development). NO es un hook por
# sí solo: lo invoca ando-prepush-check.sh y su salida se agrega como ADVERTENCIA
# (nunca bloquea — filosofía del kit: avisar, no frenar).
#
# Uso:   ando-sdd-gate.sh <branch>
# stdout: mensajes de advertencia (uno por línea) si falta la spec o no está aprobada;
#         vacío si pasa o si el gate no aplica. Siempre exit 0.
#
# OPT-IN: si ANDO_SPECS_DIR no está seteado, el chequeo de spec externa se omite en
# silencio — solo corre el chequeo de specs/ dentro del repo, si ese dir existe.
#
# Exenciones (nunca se les exige spec):
#   - hotfix/*              → urgencia de prod
#   - feature/kit-*         → cambios al propio kit, sin ticket asociado
#   - branches que no matchean feature/<TICKET-ID>  → no aplica SDD

set -uo pipefail

BRANCH="${1:-}"
[ -z "$BRANCH" ] && exit 0

case "$BRANCH" in
  hotfix/*|feature/kit-*) exit 0 ;;
esac

# TICKET-ID = mayúsculas-guion-números (Jira/Linear style). Si el branch no lo trae, no aplica.
if ! echo "$BRANCH" | grep -qE '^feature/[A-Z]+-[0-9]+'; then
  exit 0
fi

TICKET=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+' | head -1)

# --- 1) Spec externa (opt-in via ANDO_SPECS_DIR) ---
if [ -n "${ANDO_SPECS_DIR:-}" ]; then
  SPEC_FILE="$ANDO_SPECS_DIR/$TICKET.md"
  if [ ! -f "$SPEC_FILE" ]; then
    echo "SDD: falta la spec $SPEC_FILE — generala con el agente spec-writer y aprobala antes del push."
  else
    STATUS=$(awk '/^---[[:space:]]*$/{n++; next} n==1 && /^status:/{sub(/^status:[ \t]*/,""); sub(/[ \t]+$/,""); print; exit}' "$SPEC_FILE")
    if [ "$STATUS" != "approved" ]; then
      echo "SDD: la spec $SPEC_FILE tiene status '${STATUS:-sin frontmatter}' — se espera 'status: approved'."
    fi
  fi
fi

# --- 2) specs/ dentro del repo ---
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
