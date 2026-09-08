#!/bin/bash
# ando-prepush-check.sh — Hook PreToolUse (matcher: Bash)
#
# Chequeos antes de un `git push`. Dos niveles:
#
#   • ADVERTENCIAS (el push procede): Conventional Commits en el último commit,
#     TODO/FIXME en los archivos cambiados, y las advertencias no-duras del gate SDD.
#
#   • BLOQUEO (el push NO procede): sólo el gate SDD, y sólo en un caso muy acotado —
#     estás en `feature/<id>` y existe una spec `$ANDO_SPECS_DIR/<id>.md` que NO está
#     `approved`. Es un estado auto-infligido y de resolución inmediata (aprobá tu
#     propia spec, o archivala si decidiste no seguir SDD). Cualquier otra cosa es
#     advertencia, nunca bloqueo.
#
# El hook nunca debe romper el flujo por un error propio: cualquier fallo → exit 0.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
echo "$COMMAND" | grep -qE '^git push' || exit 0

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_DIR" ] && exit 0
cd "$REPO_DIR" || exit 0

WARNINGS=()
ERRORS=()

# 0. Gate SDD — clasifica su salida: líneas "BLOCK: ..." → ERRORS (bloquean),
#    resto → WARNINGS (advierten).
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  SDD_GATE="$(dirname "${BASH_SOURCE[0]}")/ando-sdd-gate.sh"
  [ -x "$SDD_GATE" ] || SDD_GATE="$HOME/.local/bin/ando-sdd-gate.sh"
  if [ -x "$SDD_GATE" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      case "$line" in
        BLOCK:\ *) ERRORS+=("${line#BLOCK: }") ;;
        *)         WARNINGS+=("$line") ;;
      esac
    done < <("$SDD_GATE" "$BRANCH" 2>/dev/null)
  fi
fi

# 1. Conventional Commits en el último commit
LAST_COMMIT=$(git log -1 --pretty=format:"%s" 2>/dev/null)
if [ -n "$LAST_COMMIT" ] && ! echo "$LAST_COMMIT" | grep -qE '^(feat|fix|chore|refactor|docs|test|style|perf|ci|build|revert)(\(.+\))?: .+'; then
  WARNINGS+=("Último commit '$LAST_COMMIT' no sigue Conventional Commits")
fi

# 2. TODO/FIXME en archivos cambiados respecto al branch por defecto (si se puede resolver)
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -n "$DEFAULT_BRANCH" ]; then
  CHANGED_FILES=$(git diff --name-only "origin/${DEFAULT_BRANCH}...HEAD" 2>/dev/null)
else
  CHANGED_FILES=$(git diff --name-only HEAD~1 2>/dev/null)
fi
if [ -n "$CHANGED_FILES" ]; then
  TODO_HITS=$(echo "$CHANGED_FILES" | xargs -r grep -l "TODO\|FIXME" 2>/dev/null)
  if [ -n "$TODO_HITS" ]; then
    HITS_INLINE=$(echo "$TODO_HITS" | tr '\n' ' ')
    WARNINGS+=("TODO/FIXME encontrado en: ${HITS_INLINE}")
  fi
fi

# --- Salida ---
# \n literal (dos caracteres) para que el JSON sea válido al interpolar.
if [ ${#ERRORS[@]} -gt 0 ]; then
  MSG="🚫 Push bloqueado:"
  for e in "${ERRORS[@]}"; do MSG="${MSG}\\n  ✗ ${e}"; done
  for w in "${WARNINGS[@]}"; do MSG="${MSG}\\n  • ${w}"; done
  ESC=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$ESC"
  exit 0
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  MSG="⚠ Advertencias pre-push (el push procede igual):"
  for w in "${WARNINGS[@]}"; do MSG="${MSG}\\n  • ${w}"; done
  ESC=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
  printf '{"systemMessage": "%s"}\n' "$ESC"
fi

exit 0
