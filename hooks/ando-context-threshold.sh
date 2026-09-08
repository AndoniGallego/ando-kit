#!/bin/bash
# ando-context-threshold.sh — Hook UserPromptSubmit
#
# Alerta de contexto al superar el umbral (default 85%): inyecta un systemMessage
# para que Claude cierre la fase actual antes de arrancar trabajo nuevo.
#
# % de contexto = mismo cálculo que ando-statusline-context.sh (ver ese script para
# el detalle completo del numerador/denominador). Resumen: usar
# context_window.total_input_tokens (ya excluye ruido de subagentes y compactaciones
# viejas); si no viene en el JSON, parsear el transcript filtrando estrictamente a
# mensajes assistant del hilo principal (type=="assistant" AND isSidechain!=true) y
# tomando el ÚLTIMO por orden de aparición — NO `tac | grep -m1 "usage"`, que
# matchea cualquier línea con esa substring sin filtrar de dónde viene. El
# denominador tampoco se hardcodea a 200k: depende del modelo activo (Sonnet
# 4.6-5/Opus/Fable = 1M, Haiku 4.5 = 200k).
#
# El hook nunca debe bloquear el flujo: cualquier fallo termina en exit 0.

set -uo pipefail

THRESHOLD_PCT="${ANDO_CONTEXT_THRESHOLD_PCT:-85}"

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

CONTEXT_WINDOW=$(echo "$INPUT" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
if [ -z "$CONTEXT_WINDOW" ] || [ "$CONTEXT_WINDOW" = "null" ]; then
  MODEL_ID=$(echo "$INPUT" | jq -r '(.model.display_name // "") + (.model.id // "")' 2>/dev/null)
  case "$MODEL_ID" in
    *sonnet-4-6*|*sonnet-4-7*|*sonnet-4-8*|*sonnet-5*|*opus-4*|*fable-5*) CONTEXT_WINDOW=1000000 ;;
    *haiku-4-5*) CONTEXT_WINDOW=200000 ;;
    *) CONTEXT_WINDOW=1000000 ;;
  esac
fi

TOKENS=$(echo "$INPUT" | jq -r '.context_window.total_input_tokens // empty' 2>/dev/null)

if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ]; then
  TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(ls -t "$HOME/.claude/projects/"*/*.jsonl 2>/dev/null | head -1)
  fi

  if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    TOKENS=$(jq -rc 'select(.type == "assistant" and (.isSidechain != true)) |
        (.message.usage // .usage) as $u
        | select($u != null)
        | (($u.input_tokens // 0) + ($u.cache_read_input_tokens // 0) + ($u.cache_creation_input_tokens // 0))
      ' "$TRANSCRIPT" 2>/dev/null | tail -n1)
  fi
fi

if [ -z "$TOKENS" ] || [ "$TOKENS" = "null" ]; then exit 0; fi
[ "$TOKENS" -le 0 ] 2>/dev/null && exit 0

PCT=$(( TOKENS * 100 / CONTEXT_WINDOW ))
[ "$PCT" -lt "$THRESHOLD_PCT" ] 2>/dev/null && exit 0

printf '{"systemMessage": "⚠ CONTEXTO AL %s%% — UMBRAL SUPERADO. Antes de arrancar trabajo nuevo: (1) commiteá lo que esté en curso, (2) guardá contexto en Engram con mem_session_summary, (3) avisá qué quedó pendiente para continuar en sesión nueva. No acumules más contexto."}\n' "$PCT"
