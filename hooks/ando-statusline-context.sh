#!/bin/bash
# Statusline de Claude Code — modelo, directorio y % de contexto usado.
# Visibilidad permanente del umbral de orquestación (80%): por encima, delegar o cerrar fase.
#
# % de contexto = (numerador / denominador), resueltos así:
#
# NUMERADOR (tokens usados en el contexto actual):
#   1. input.context_window.total_input_tokens (Claude Code ya lo calcula: incluye cache
#      reads/writes y excluye ruido de subagentes/compactaciones viejas — es la fuente de
#      verdad real de "cuánto contexto ocupa la sesión ahora mismo").
#   2. Fallback: parsear el transcript .jsonl línea por línea (no con `tac | grep -m1`,
#      que matchea CUALQUIER línea con la substring "usage" sin filtrar de dónde viene),
#      filtrando estrictamente a mensajes assistant del hilo principal
#      (type=="assistant" AND isSidechain!=true) y tomando el ÚLTIMO de esos por orden
#      de aparición. Esto evita dos fuentes de inflación real observadas:
#        a) Entradas "sidechain" de subagentes (Task tool) que también tienen su propio
#           bloque "usage" interleavado en el mismo archivo.
#        b) El turno de resumen que genera un /compact, cuyo "usage.input_tokens" refleja
#           TODO el contexto pre-compactación que se está resumiendo (potencialmente
#           cientos de miles de tokens) y no el tamaño real post-compactación. Si ese
#           turno queda como "el último con la palabra usage", un tail-grep ingenuo lo
#           toma como numerador y explica lecturas de 300%+ en sesiones largas con
#           varias compactaciones — no es una suma acumulativa, es tomar el turno
#           equivocado.
#
# DENOMINADOR (ventana de contexto del modelo activo):
#   1. input.context_window.context_window_size (Claude Code ya lo calcula por sesión/modelo)
#   2. Tabla de fallback por nombre de modelo (por si el campo no viniera en el JSON)
#   3. Default hardcoded si nada de lo anterior está disponible.
#
# Fallback table — actualizar si aparece un modelo nuevo o cambia su ventana:
#   Sonnet 4.6/4.7/4.8, Sonnet 5, Opus 4.x, Fable 5  -> 1,000,000 tokens
#   Haiku 4.5                                        -> 200,000 tokens
#   Default (modelo desconocido)                     -> 1,000,000 (Sonnet 5 es el modelo
#                                                        de sesión actual y el más común
#                                                        en esta cuenta; ajustar si cambia)

INPUT=$(cat)
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"')
MODEL_ID=$(echo "$INPUT" | jq -r '.model.id // ""')
DIR=$(basename "$(echo "$INPUT" | jq -r '.workspace.current_dir // "~"')")
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty')

CONTEXT_WINDOW=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty')
if [ -z "$CONTEXT_WINDOW" ] || [ "$CONTEXT_WINDOW" = "null" ]; then
  case "$MODEL$MODEL_ID" in
    *sonnet-4-6*|*sonnet-4-7*|*sonnet-4-8*|*sonnet-5*|*opus-4*|*fable-5*) CONTEXT_WINDOW=1000000 ;;
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

if [ -n "$TOKENS" ] && [ "$TOKENS" != "null" ] && [ "$TOKENS" -gt 0 ] 2>/dev/null; then
  PCT=$(( TOKENS * 100 / CONTEXT_WINDOW ))
fi

CYAN='\033[36m'
MAGENTA='\033[35m'
RESET='\033[0m'
BOLD='\033[1m'
GRAY='\033[90m'
YELLOW='\033[33m'

# Formatear tokens para display (en miles)
USAGE_DISPLAY=""
if [ -n "$TOKENS" ] && [ "$TOKENS" != "null" ] && [ "$TOKENS" -gt 0 ] 2>/dev/null; then
  TOK_K=$(( TOKENS / 1000 ))
  if [ "$CONTEXT_WINDOW" -ge 1000000 ]; then
    WIN_DISPLAY="1M"
  else
    WIN_DISPLAY="$(( CONTEXT_WINDOW / 1000 ))k"
  fi
  USAGE_DISPLAY=" ${GRAY}(${TOK_K}k/${WIN_DISPLAY})${RESET}"
fi

# Porcentaje: verde <60, amarillo 60-79, rojo ≥80
if [ "$PCT" = "?" ]; then
  PCT_COLOR='\033[90m'
  MARK=""
elif [ "$PCT" -ge 80 ] 2>/dev/null; then
  PCT_COLOR='\033[31m'
  MARK=" ${BOLD}\033[31m⚠ DELEGAR${RESET}"
elif [ "$PCT" -ge 60 ] 2>/dev/null; then
  PCT_COLOR='\033[33m'
  MARK=""
else
  PCT_COLOR='\033[32m'
  MARK=""
fi

# --- Estado del kit: versión + drift vs upstream. Cacheado (máx 1 refresh / 5 min) —
#     NUNCA corre git en cada render, y NUNCA hace fetch (sin red en la statusline):
#     el "↑N" refleja lo que git ya sabe del remoto tras el último fetch/pull.
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
    printf '%s' "$OUT" > "$KIT_CACHE" 2>/dev/null
  fi
  KIT_TXT=$(cat "$KIT_CACHE" 2>/dev/null)
  case "$KIT_TXT" in
    "")   : ;;
    *↑*)  KIT_MARK=" | ${YELLOW}kit ${KIT_TXT}${RESET}" ;;
    *)    KIT_MARK=" | ${GRAY}kit ${KIT_TXT}${RESET}" ;;
  esac
fi

printf "${CYAN}[%s]${RESET} ${MAGENTA}%s${RESET} | Ctx orquestador: ${PCT_COLOR}%s%%${RESET}%b%b%b\n" "$MODEL" "$DIR" "$PCT" "$USAGE_DISPLAY" "$MARK" "$KIT_MARK"
