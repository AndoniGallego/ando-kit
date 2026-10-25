#!/bin/bash
# UserPromptSubmit hook: avisa al orquestador antes de que el contexto crezca de mas.
# Umbrales como % de la ventana del modelo. Dos bandas, cada una avisa UNA vez por sesion:
#   SAVE (ANDO_CTX_SAVE_PCT, default 70%): guardar el resumen de sesion en memoria YA.
#   WARN (ANDO_CTX_WARN_PCT, default 80%): cerrar fase y compactar / abrir sesion nueva.
# ANDO_CONTEXT_THRESHOLD_PCT (nombre anterior) se sigue aceptando como alias de WARN.
# La statusline lee el mismo ANDO_CTX_WARN_PCT para el rojo.
#
# TOKENS: misma resolucion que ando-statusline-context.sh (total_input_tokens del input; si no,
# ultimo turno no-sidechain del transcript de esta sesion). El hook nunca bloquea: ante un fallo, exit 0.

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

CONTEXT_WINDOW=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
if [ -z "$CONTEXT_WINDOW" ] || [ "$CONTEXT_WINDOW" = "null" ]; then
  MODEL_ID=$(echo "$INPUT" | jq -r '(.model.display_name // "") + (.model.id // "")' 2>/dev/null)
  case "$MODEL_ID" in
    *sonnet-4-6*|*sonnet-4-7*|*sonnet-4-8*|*sonnet-5*|*opus-4*|*opus-5*|*fable-5*) CONTEXT_WINDOW=1000000 ;;
    *haiku-4-5*) CONTEXT_WINDOW=200000 ;;
    *) CONTEXT_WINDOW=1000000 ;;
  esac
fi

WARN_PCT="${ANDO_CTX_WARN_PCT:-${ANDO_CONTEXT_THRESHOLD_PCT:-80}}"
SAVE_PCT="${ANDO_CTX_SAVE_PCT:-70}"
[ "$SAVE_PCT" -lt "$WARN_PCT" ] 2>/dev/null || SAVE_PCT=$(( WARN_PCT * 7 / 8 ))
SAVE_TOKENS=$(( CONTEXT_WINDOW * SAVE_PCT / 100 ))
WARN_TOKENS=$(( CONTEXT_WINDOW * WARN_PCT / 100 ))

TOKENS=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')

if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ]; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  # Solo el transcript de este session_id: caer al .jsonl mas reciente reportaba el contexto de otra sesion.
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    TRANSCRIPT=""
    [ -n "$SESSION_ID" ] && TRANSCRIPT=$(ls "$HOME/.claude/projects/"*/"$SESSION_ID.jsonl" 2>/dev/null | head -1)
  fi
  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TOKENS=$(jq -rc 'select(.type == "assistant" and (.isSidechain != true)) |
        (.message.usage // .usage) as $u
        | select($u != null)
        | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0))
      ' "$TRANSCRIPT" 2>/dev/null | tail -n1)
  fi
fi

STATE_DIR="${ANDO_CTX_STATE_DIR:-${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}}"
MARKER=""
[ -n "$SESSION_ID" ] && MARKER="$STATE_DIR/ando-ctx-band-$SESSION_ID"

if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ]; then exit 0; fi
[ "$TOKENS" -le 0 ] 2>/dev/null && exit 0

if [ "$TOKENS" -lt "$SAVE_TOKENS" ] 2>/dev/null; then
  [ -n "$MARKER" ] && rm -f "$MARKER" 2>/dev/null
  exit 0
fi

if [ "$TOKENS" -ge "$WARN_TOKENS" ] 2>/dev/null; then BAND=warn; else BAND=save; fi

LAST=""
[ -n "$MARKER" ] && [ -f "$MARKER" ] && LAST=$(cat "$MARKER" 2>/dev/null)
if [ "$LAST" = "$BAND" ] || { [ "$LAST" = "warn" ] && [ "$BAND" = "save" ]; }; then exit 0; fi
[ -n "$MARKER" ] && echo "$BAND" > "$MARKER" 2>/dev/null

K=$(( TOKENS / 1000 ))
PCT=$(( TOKENS * 100 / CONTEXT_WINDOW ))
if [ "$BAND" = "save" ]; then
  MSG=$(printf 'CONTEXTO EN %sk TOKENS (%s%% de la ventana), el umbral es %s%% (%sk). Antes de responder este mensaje: (1) commitea lo que este en curso si corresponde, (2) guarda en memoria (mem_session_summary) un resumen de sesion con el estado (que se hizo, decisiones, archivos tocados, proximo paso concreto), (3) recien entonces segui con el pedido. Delega el trabajo restante a agentes; no releas archivos ya cubiertos.' "$K" "$PCT" "$WARN_PCT" "$(( WARN_TOKENS / 1000 ))")
else
  MSG=$(printf 'CONTEXTO EN %sk TOKENS (%s%% de la ventana), UMBRAL SUPERADO (%s%%, %sk). Si no hay un resumen de sesion reciente en memoria, guardalo ahora. Cerra la fase actual (commit + mem_session_summary) y avisale al usuario que compacte (/compact) o abra sesion nueva. No lances agentes nuevos desde un contexto de este tamano.' "$K" "$PCT" "$WARN_PCT" "$(( WARN_TOKENS / 1000 ))")
fi
jq -n --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $msg}}'
