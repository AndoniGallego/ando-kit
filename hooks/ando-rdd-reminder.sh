#!/bin/bash
# ando-rdd-reminder.sh — Hook PreToolUse (matcher: Bash)
#
# Al crear un PR/MR (`gh pr create` / `glab mr create`) desde un branch `feature/<id>`
# con commits por delante de su base, recuerda correr `rdd-review` si el branch todavía
# no pasó por ahí — o cambió desde la última revisión.
#
# La señal de "ya se revisó" es el archivo `.git/ando-rdd-reviewed`, que el skill
# rdd-review escribe con el SHA de HEAD al terminar. Si falta, o su SHA != HEAD actual
# (commiteaste algo después de revisar), dispara el recordatorio.
#
# NO bloquea — sólo systemMessage. Cualquier fallo propio → exit 0.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
echo "$COMMAND" | grep -qE '\b(gh pr create|glab mr create)\b' || exit 0

REPO_DIR=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$REPO_DIR" ] && exit 0
cd "$REPO_DIR" || exit 0

BRANCH=$(git branch --show-current 2>/dev/null)
case "$BRANCH" in
  feature/kit-*|hotfix/*|"") exit 0 ;;
  feature/*) ;;
  *) exit 0 ;;
esac

# ¿Hay commits por delante de la base?
BASE=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
[ -z "$BASE" ] && BASE=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/@@')
[ -z "$BASE" ] && BASE="origin/main"
MERGE_BASE=$(git merge-base HEAD "$BASE" 2>/dev/null) || exit 0
AHEAD=$(git rev-list --count "$MERGE_BASE"..HEAD 2>/dev/null)
[ -n "$AHEAD" ] && [ "$AHEAD" -gt 0 ] 2>/dev/null || exit 0

HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
MARKER="$(git rev-parse --git-dir 2>/dev/null)/ando-rdd-reviewed"
REVIEWED_SHA=$(cat "$MARKER" 2>/dev/null | tr -d '[:space:]')

if [ "$REVIEWED_SHA" = "$HEAD_SHA" ]; then
  exit 0
fi

if [ -z "$REVIEWED_SHA" ]; then
  MSG="Este branch ($BRANCH) no pasó por rdd-review. Corré /rdd-review antes de crear el PR — el resultado es informacional, no bloquea, pero deja el receipt."
else
  MSG="El branch ($BRANCH) cambió desde el último rdd-review (hay commits nuevos). Re-corré /rdd-review sobre el estado actual antes de crear el PR."
fi

printf '{"systemMessage": "%s"}\n' "$(printf '%s' "$MSG" | sed 's/"/\\"/g')"
exit 0
