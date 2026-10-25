#!/bin/bash
# Statusline de Claude Code: modelo, directorio y % de contexto del orquestador.
# Formato: [Modelo] directorio | Ctx: 12% (120k)
# Umbral visible en permanencia (ANDO_CTX_WARN_PCT, default 80): por encima, delegar o cerrar fase.
# Mismo valor que lee ando-context-threshold.sh; si difieren, el rojo y el aviso no coinciden.
#
# % de contexto = numerador / denominador:
#
# NUMERADOR (tokens usados en el contexto actual):
#   1. input.context_window.total_input_tokens (lo calcula Claude Code: incluye cache reads/writes
#      y excluye subagentes y compactaciones viejas).
#   2. Fallback: ultimo mensaje assistant del hilo principal del transcript
#      (type=="assistant" AND isSidechain!=true). No usar `tac | grep -m1 usage`: matchea turnos de
#      subagentes y el turno de resumen de un /compact, que refleja el contexto PRE-compactacion
#      y explica lecturas de 300%+ en sesiones largas.
#
# DENOMINADOR (ventana del modelo activo):
#   1. input.context_window.context_window_size
#   2. Tabla por modelo (actualizar si cambia una ventana):
#      Sonnet 4.6+/5, Opus 4.x/5.x, Fable 5 -> 1M; Haiku 4.5 -> 200k; desconocido -> 1M.
#
# Segmento del kit (version / desactualizado) desde ~/.claude/.ando-kit-status. Solo jq (sin python3:
# en Windows puede ser el alias de Microsoft Store que no corre nada).

INPUT=$(cat)
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"')
MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // ""')
DIR=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // "~"')
DIR="${DIR//\\//}"
DIR="${DIR##*/}"
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

CONTEXT_WINDOW=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty')
if [ -z "$CONTEXT_WINDOW" ] || [ "$CONTEXT_WINDOW" = "null" ]; then
  case "$MODEL$MODEL_ID" in
    *sonnet-4-6*|*sonnet-4-7*|*sonnet-4-8*|*sonnet-5*|*opus-4*|*opus-5*|*fable-5*) CONTEXT_WINDOW=1000000 ;;
    *haiku-4-5*) CONTEXT_WINDOW=200000 ;;
    *) CONTEXT_WINDOW=1000000 ;;
  esac
fi

PCT="?"
TOKENS=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // empty')
if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ]; then
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TOKENS=$(jq -rc 'select(.type == "assistant" and (.isSidechain != true)) |
        (.message.usage // .usage) as $u
        | select($u != null)
        | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0))
      ' "$TRANSCRIPT" 2>/dev/null | tail -n1)
  fi
fi

TOKENS_K=""
if [ -n "$TOKENS" ] && [ "$TOKENS" != "null" ] && [ "$TOKENS" -gt 0 ] 2>/dev/null; then
  PCT=$(( TOKENS * 100 / CONTEXT_WINDOW ))
  TOKENS_K="$(( TOKENS / 1000 ))k"
fi

WARN_PCT="${ANDO_CTX_WARN_PCT:-80}"
CAUTION_PCT="${ANDO_CTX_CAUTION_PCT:-60}"
[ "$CAUTION_PCT" -lt "$WARN_PCT" ] 2>/dev/null || CAUTION_PCT=$(( WARN_PCT * 6 / 10 ))
CTX_WARN_TOKENS=$(( CONTEXT_WINDOW * WARN_PCT / 100 ))
CTX_CAUTION_TOKENS=$(( CONTEXT_WINDOW * CAUTION_PCT / 100 ))

CYAN='\033[36m'
MAGENTA='\033[35m'
RESET='\033[0m'
BOLD='\033[1m'
GRAY='\033[90m'
YELLOW='\033[33m'

# Verde bajo CAUTION (default 60%), amarillo hasta WARN, rojo desde WARN.
MARK=""
if [ "$PCT" = "?" ]; then
  PCT_COLOR="$GRAY"
elif [ "$TOKENS" -ge "$CTX_WARN_TOKENS" ] 2>/dev/null; then
  PCT_COLOR='\033[31m'
  MARK=" ${BOLD}\033[31m⚠ DELEGAR${RESET}"
elif [ "$TOKENS" -ge "$CTX_CAUTION_TOKENS" ] 2>/dev/null; then
  PCT_COLOR='\033[33m'
else
  PCT_COLOR='\033[32m'
fi

write_cache_atomic() { # ARCHIVO CONTENIDO — temporal en el mismo dir + mv, para que otra instancia no lea a medias
  local tmp
  tmp=$(mktemp "$1.XXXXXX" 2>/dev/null) || return 0
  if printf '%s' "$2" > "$tmp" 2>/dev/null && mv -f "$tmp" "$1" 2>/dev/null; then :; else rm -f "$tmp" 2>/dev/null; fi
  return 0
}

# Estado del kit: version + drift vs upstream. Cacheado (max 1 refresh / 5 min); nunca hace fetch
# (sin red en la statusline): el "↑N" refleja lo que git ya sabe del remoto tras el ultimo fetch/pull.
KIT_MARK=""
KIT_DIR="${ANDO_KIT_DIR:-}"
if [ -n "$KIT_DIR" ] && [ -d "$KIT_DIR/.git" ]; then
  KIT_CACHE="$HOME/.claude/.ando-kit-status"
  if [ ! -f "$KIT_CACHE" ] || [ -n "$(find "$KIT_CACHE" -mmin +5 2>/dev/null)" ]; then
    KV=$(tr -d '[:space:]' < "$KIT_DIR/VERSION" 2>/dev/null)
    BEHIND=$(git -C "$KIT_DIR" rev-list --count 'HEAD..@{u}' 2>/dev/null)
    OUT="v${KV:-?}"
    [ -n "$BEHIND" ] && [ "$BEHIND" -gt 0 ] 2>/dev/null && OUT="$OUT ↑$BEHIND"
    mkdir -p "$(dirname "$KIT_CACHE")" 2>/dev/null
    write_cache_atomic "$KIT_CACHE" "$OUT"
  fi
  KIT_TXT=$(cat "$KIT_CACHE" 2>/dev/null)
  case "$KIT_TXT" in
    "")   : ;;
    *↑*)  KIT_MARK=" | ${YELLOW}${KIT_TXT}${RESET}" ;;
    *)    KIT_MARK=" | ${GRAY}${KIT_TXT}${RESET}" ;;
  esac
fi

printf "${CYAN}[%s]${RESET} ${MAGENTA}%s${RESET} | ${CYAN}Ctx${RESET}: ${PCT_COLOR}%s%%%s${RESET}%b%b\n" \
  "$MODEL" "$DIR" "$PCT" "${TOKENS_K:+ ($TOKENS_K)}" "$MARK" "$KIT_MARK"
