#!/bin/bash
# ando-prepush-check.sh — Hook PreToolUse (matcher: Bash)
#
# Red de seguridad no bloqueante antes de un `git push`: Conventional Commits
# en el último commit y TODO/FIXME en los archivos cambiados. Solo advierte
# (systemMessage) — nunca bloquea el push. Si querés un gate más estricto
# para un repo puntual, agregá tus propias reglas en una copia local del
# hook para ese proyecto.
#
# El hook nunca debe romper el flujo principal: cualquier fallo termina en
# exit 0 sin imprimir nada.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Solo actuar en git push
echo "$COMMAND" | grep -qE '^git push' || exit 0

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_DIR" ] && exit 0
cd "$REPO_DIR" || exit 0

WARNINGS=()

# 0. Gate SDD (opt-in) — delega en ando-sdd-gate.sh; su salida son advertencias, nunca bloquea
BRANCH=$(git branch --show-current 2>/dev/null)
if [ -n "$BRANCH" ]; then
  SDD_GATE="$(dirname "${BASH_SOURCE[0]}")/ando-sdd-gate.sh"
  [ -x "$SDD_GATE" ] || SDD_GATE="$HOME/.local/bin/ando-sdd-gate.sh"
  if [ -x "$SDD_GATE" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && WARNINGS+=("$line")
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

if [ ${#WARNINGS[@]} -eq 0 ]; then
  exit 0
fi

# \n literal (dos caracteres) para que sea un escape JSON válido — NO un
# salto de línea real, que rompería el JSON al interpolarlo.
MSG="⚠ Advertencias pre-push (el push procede igual):"
for w in "${WARNINGS[@]}"; do
  MSG="${MSG}\\n  • ${w}"
done

printf '{"systemMessage": "%s"}\n' "$MSG"
exit 0
