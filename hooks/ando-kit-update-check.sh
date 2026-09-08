#!/bin/bash
# ando-kit-update-check.sh — Hook SessionStart
#
# Sustituto liviano del cron/autoupdater que no existe en Windows (ni corre nada en
# background 24/7): aprovecha el arranque de cada sesión de Claude Code para, como
# mucho una vez cada $ANDO_KIT_UPDATE_CHECK_HOURS horas (default 12), hacer un
# `git fetch` real del kit y refrescar el cache que lee la statusline
# (~/.claude/.ando-kit-status — mismo archivo y formato "vX.Y.Z" / "vX.Y.Z ↑N" que ya
# escribe ando-statusline-context.sh sin hacer fetch por su cuenta).
#
# Es la única pieza del kit que hace red sin que se la pidan explícitamente en el
# momento — por eso: rate-limited agresivamente, nunca toca el working tree salvo
# opt-in explícito (ver ANDO_KIT_AUTOUPDATE abajo), y confía en el timeout del propio
# hook en settings.json (no reimplementa timeout de proceso a mano acá) para no colgar
# el arranque de la sesión si la red está caída — si el fetch tarda de más, el harness
# mata el hook y la sesión arranca igual; el próximo chequeo será en $HOURS horas.
#
# Auto-pull + reinstall real es OPT-IN vía ANDO_KIT_AUTOUPDATE=1 (default: off, solo
# avisa). Pisar ~/.claude con un pull automático puede chocar con ediciones locales en
# curso — por eso además, aun con la variable activada, sólo hace pull si el working
# tree del kit está limpio (sin cambios sin commitear) y el merge es fast-forward.

set -uo pipefail

KIT_DIR="${ANDO_KIT_DIR:-}"
[ -n "$KIT_DIR" ] && [ -d "$KIT_DIR/.git" ] || exit 0

HOURS="${ANDO_KIT_UPDATE_CHECK_HOURS:-12}"
MARKER="$HOME/.claude/.ando-kit-update-check"
mkdir -p "$(dirname "$MARKER")" 2>/dev/null

if [ -f "$MARKER" ] && [ -z "$(find "$MARKER" -mmin "+$((HOURS * 60))" 2>/dev/null)" ]; then
  exit 0
fi
touch "$MARKER" 2>/dev/null

git -C "$KIT_DIR" fetch --quiet 2>/dev/null

KV=$(tr -d '[:space:]' < "$KIT_DIR/VERSION" 2>/dev/null)
BEHIND=$(git -C "$KIT_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null)
OUT="v${KV:-?}"
[ -n "$BEHIND" ] && [ "$BEHIND" -gt 0 ] 2>/dev/null && OUT="$OUT ↑$BEHIND"
printf '%s' "$OUT" > "$HOME/.claude/.ando-kit-status" 2>/dev/null

[ -n "$BEHIND" ] && [ "$BEHIND" -gt 0 ] 2>/dev/null || exit 0

if [ "${ANDO_KIT_AUTOUPDATE:-0}" = "1" ]; then
  if [ -z "$(git -C "$KIT_DIR" status --porcelain 2>/dev/null)" ]; then
    if git -C "$KIT_DIR" pull --ff-only --quiet 2>/dev/null; then
      bash "$KIT_DIR/install.sh" >/dev/null 2>&1
      NEWV=$(tr -d '[:space:]' < "$KIT_DIR/VERSION" 2>/dev/null)
      MSG="↕ ando-kit actualizado automáticamente: v$NEWV ($BEHIND commit(s) nuevos, ya instalado)."
    else
      MSG="↕ ando-kit tiene $BEHIND commit(s) nuevos pero el fast-forward falló (historial divergente) — resolvé a mano en $KIT_DIR."
    fi
  else
    MSG="↕ ando-kit tiene $BEHIND commit(s) nuevos pero hay cambios sin commitear en $KIT_DIR — no se auto-actualiza para no pisarlos. Guardalos (kit-sync) y corré: git -C \"$KIT_DIR\" pull && bash \"$KIT_DIR/install.sh\""
  fi
else
  MSG="↕ ando-kit tiene $BEHIND commit(s) nuevos en origin. Actualizar: git -C \"$KIT_DIR\" pull && bash \"$KIT_DIR/install.sh\"  (o export ANDO_KIT_AUTOUPDATE=1 para que sea automático la próxima vez)."
fi

ESC=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
printf '{"systemMessage": "%s"}\n' "$ESC"
exit 0
