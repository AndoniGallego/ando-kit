#!/bin/bash
# Statusline y hook de umbral: calculo del Ctx, colores/umbral, bandas del hook y segmento del kit.
source "$(dirname "${BASH_SOURCE[0]}")/../lib/helpers.sh"
setup_home

SL="$REPO_ROOT/hooks/ando-statusline-context.sh"
TH="$REPO_ROOT/hooks/ando-context-threshold.sh"
export ANDO_CTX_STATE_DIR="$TEST_TMP/state"; mkdir -p "$ANDO_CTX_STATE_DIR"
unset ANDO_KIT_DIR ANDO_CTX_WARN_PCT ANDO_CTX_SAVE_PCT ANDO_CTX_CAUTION_PCT ANDO_CONTEXT_THRESHOLD_PCT

plain() { sed 's/\x1b\[[0-9;]*m//g'; }
sl() { bash "$SL" <<<"$1"; }
slp() { sl "$1" | plain; }
W='"context_window":{"context_window_size":1000000,"total_input_tokens":%s}'
win() { printf "{$W}" "$1"; }

assert_eq "formato base" "[Opus] proyecto | Ctx: 10% (100k)" \
  "$(slp '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"/x/proyecto"},"context_window":{"context_window_size":1000000,"total_input_tokens":100000}}')"
assert_contains "verde bajo 60%" $'\x1b[32m' "$(sl "$(win 100000)")"
assert_contains "amarillo entre 60% y 80%" $'\x1b[33m' "$(sl "$(win 700000)")"
assert_eq "sin aviso a 70%" "" "$(slp "$(win 700000)" | grep DELEGAR)"
assert_contains "rojo y DELEGAR desde 80%" "Ctx: 85% (850k) ⚠ DELEGAR" "$(slp "$(win 850000)")"
assert_contains "rojo ANSI desde 80%" $'\x1b[31m' "$(sl "$(win 850000)")"
assert_eq "umbral configurable: 85% con WARN=90 no marca" "" "$(ANDO_CTX_WARN_PCT=90 slp "$(win 850000)" | grep DELEGAR)"
assert_contains "umbral configurable: 30% con WARN=25" "DELEGAR" "$(ANDO_CTX_WARN_PCT=25 slp "$(win 300000)")"

assert_contains "Haiku 4.5 sin context_window_size: ventana 200k" "Ctx: 50% (100k)" \
  "$(slp '{"model":{"id":"claude-haiku-4-5"},"context_window":{"total_input_tokens":100000}}')"
assert_contains "opus-5 sin context_window_size: ventana 1M" "Ctx: 10% (100k)" \
  "$(slp '{"model":{"id":"claude-opus-5-5"},"context_window":{"total_input_tokens":100000}}')"

tr="$TEST_TMP/s.jsonl"
cat > "$tr" <<'JSONL'
{"type":"assistant","message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":49000}}}
{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":900000}}}
{"type":"user","message":{"content":"usage"}}
JSONL
assert_contains "fallback al transcript ignora sidechain" "Ctx: 5% (50k)" \
  "$(slp "{\"transcript_path\":\"$tr\",\"context_window\":{\"context_window_size\":1000000}}")"
assert_eq "ruta Windows: solo el directorio; ? sin tokens" "[Claude] proyecto | Ctx: ?%" \
  "$(slp '{"workspace":{"current_dir":"C:\\Users\\yo\\proyecto"}}')"
assert_eq "sin kit configurado: sin segmentos extra" "" "$(slp "$(win 1000)" | grep -E '\| v|Cursor|doctor')"

kit="$TEST_TMP/kit"; mkdir -p "$kit/.git"; echo "1.2.3" > "$kit/VERSION"
assert_contains "segmento de version del kit" "| v1.2.3" "$(ANDO_KIT_DIR="$kit" slp "$(win 1000)")"
printf 'v1.2.3 ↑2' > "$HOME/.claude/.ando-kit-status"
assert_contains "kit atrasado (cache fresco)" "| v1.2.3 ↑2" "$(ANDO_KIT_DIR="$kit" slp "$(win 1000)")"

th() { bash "$TH" <<<"$1"; }
j='{"session_id":"s1",'"$W"'}'
assert_eq "hook: bajo 70% no avisa" "" "$(th "$(printf "$j" 600000)")"
assert_contains "hook: 70% pide guardar" "mem_session_summary" "$(th "$(printf "$j" 710000)")"
assert_eq "hook: misma banda no repite" "" "$(th "$(printf "$j" 720000)")"
assert_contains "hook: 80% avisa umbral superado" "UMBRAL SUPERADO" "$(th "$(printf "$j" 810000)")"
assert_eq "hook: warn no vuelve a save" "" "$(th "$(printf "$j" 750000)")"
rm -f "$ANDO_CTX_STATE_DIR"/ando-ctx-band-*
assert_eq "hook: salida JSON valida con additionalContext" "UserPromptSubmit" \
  "$(th "$(printf "$j" 810000)" | jq -r .hookSpecificOutput.hookEventName)"
rm -f "$ANDO_CTX_STATE_DIR"/ando-ctx-band-*
assert_contains "hook: mismo umbral configurable que la statusline" "UMBRAL SUPERADO" "$(ANDO_CTX_WARN_PCT=25 th "$(printf "$j" 300000)")"

finish
