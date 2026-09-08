#!/bin/bash
# ando-git-trust-check.sh — Hook PreToolUse (matcher: Bash)
#
# Defensa contra GitSpawn (Manifold Security, jun-sep 2026): un repo puede traer en su
# .git/config claves como `core.fsmonitor` que nombran un programa arbitrario, y Git lo
# ejecuta en cualquier operación que refresque el índice — `git status`, `git diff`,
# `git add`... exactamente lo que un agente corre solo, sin que nadie lo pida, para
# "entender el repo". El repo no necesita que hagas nada: alcanza con que el agente
# corra su primer `git status` en un directorio cuyo .git ya tenía esto (llegó como
# carpeta/zip/`cp -r`, no como `git clone <url>` de un remoto real — clonar por URL NO
# transmite el .git/config del origen).
#
# Este hook intercepta CUALQUIER comando `git ...` (lo corra el usuario o el modelo) y,
# antes de dejarlo pasar, audita el repo en juego. La auditoría misma NUNCA invoca al
# binario `git` — lee `.git/config` y `.git/hooks/` como archivos de texto/filesystem,
# para no arriesgarse a disparar el propio payload que está buscando.
#
# Claves que se consideran peligrosas en un `.git/config` LOCAL de un repo (no en tu
# ~/.gitconfig global, donde configurarlas vos mismo es normal): cualquiera que "nombre
# un programa" — fsmonitor, hooksPath, pager, editor, sshCommand, askpass,
# credential.helper. Es raro que un repo compartido legítimamente traiga esto en su
# config local; si aparece, es la bandera roja.
#
# Cache: una vez vetado un repo (sin hallazgos), no se re-audita hasta que cambie el
# mtime de su .git/config. Allowlist: `~/.claude/.ando-git-trust-allow` — un gitdir
# absoluto por línea, para repos propios que legítimamente usan alguna de estas claves
# (ej. fsmonitor=true con Watchman en un monorepo grande).
#
# Filosofía del kit: los hooks nunca rompen el flujo por error propio (jq ausente,
# archivo ilegible → exit 0). Pero cuando el chequeo SÍ puede correr y encuentra algo,
# bloquea de verdad — esto es una defensa de seguridad, no una nota de estilo.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
echo "$COMMAND" | grep -qE '(^|[;&|]|\butil\b)\s*git(\.exe)?\s' || exit 0

# --- Resolver el directorio de arranque: preferir `git -C <dir>` o un `cd <dir> &&/;`
#     al principio del comando; si no, el cwd del propio hook (== cwd del Bash tool). ---
START_DIR="$PWD"
GITC=$(echo "$COMMAND" | grep -oE 'git -C[[:space:]]+[^ ]+' | head -1 | sed -E 's/git -C[[:space:]]+//; s/[[:space:]]+$//')
CDPATH_MATCH=$(echo "$COMMAND" | grep -oE '^cd[[:space:]]+[^;&]+' | head -1 | sed -E 's/^cd[[:space:]]+//; s/[[:space:]]+$//')
if [ -n "$GITC" ]; then
  START_DIR="$GITC"
elif [ -n "$CDPATH_MATCH" ]; then
  case "$CDPATH_MATCH" in
    /*) START_DIR="$CDPATH_MATCH" ;;
    *)  START_DIR="$PWD/$CDPATH_MATCH" ;;
  esac
fi
[ -d "$START_DIR" ] || START_DIR="$PWD"

# --- Encontrar el .git real subiendo directorios, SIN invocar git. ---
DIR="$START_DIR"
GITDIR=""
while [ -n "$DIR" ] && [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
  if [ -d "$DIR/.git" ]; then
    GITDIR="$DIR/.git"
    break
  fi
  if [ -f "$DIR/.git" ]; then
    REL=$(sed -n 's/^gitdir:[[:space:]]*//p' "$DIR/.git" 2>/dev/null | head -1)
    case "$REL" in
      /*) GITDIR="$REL" ;;
      "") GITDIR="" ;;
      *)  GITDIR="$DIR/$REL" ;;
    esac
    break
  fi
  NEXT=$(dirname "$DIR")
  [ "$NEXT" = "$DIR" ] && break
  DIR="$NEXT"
done

[ -n "$GITDIR" ] && [ -d "$GITDIR" ] || exit 0
CONFIG="$GITDIR/config"
[ -f "$CONFIG" ] || exit 0

# --- Allowlist: repos propios que ya revisaste y confiás. ---
ALLOW_FILE="$HOME/.claude/.ando-git-trust-allow"
GITDIR_ABS="$(cd "$GITDIR" 2>/dev/null && pwd)"
if [ -n "$GITDIR_ABS" ] && [ -f "$ALLOW_FILE" ] && grep -qxF "$GITDIR_ABS" "$ALLOW_FILE" 2>/dev/null; then
  exit 0
fi

# --- Cache: no re-auditar hasta que cambie .git/config. ---
CACHE_DIR="$HOME/.claude/.ando-git-trust"
mkdir -p "$CACHE_DIR" 2>/dev/null
KEY=$(printf '%s' "${GITDIR_ABS:-$GITDIR}" | cksum | cut -d' ' -f1)
CACHE_FILE="$CACHE_DIR/$KEY"
CONFIG_MTIME=$(stat -c '%Y' "$CONFIG" 2>/dev/null || stat -f '%m' "$CONFIG" 2>/dev/null || echo "")
if [ -n "$CONFIG_MTIME" ] && [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE" 2>/dev/null)" = "$CONFIG_MTIME" ]; then
  exit 0
fi

# --- Auditoría (solo lectura de archivos, cero invocaciones a git). ---
FLAGS=()

DANGEROUS_KEYS='fsmonitor|hookspath|pager|editor|sshcommand|askpass|helper'
while IFS= read -r line; do
  clean=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$clean" ] && FLAGS+=("clave riesgosa en .git/config: $clean")
done < <(grep -inE "^[[:space:]]*($DANGEROUS_KEYS)[[:space:]]*=" "$CONFIG" 2>/dev/null | grep -vE '=[[:space:]]*(true|false|1|0)?[[:space:]]*$')

if [ -d "$GITDIR/hooks" ]; then
  while IFS= read -r h; do
    FLAGS+=("hook ejecutable no-default: $h")
  done < <(find "$GITDIR/hooks" -maxdepth 1 -type f ! -name '*.sample' \( -perm -u+x -o -perm -g+x -o -perm -o+x \) 2>/dev/null)
fi

if [ ${#FLAGS[@]} -eq 0 ]; then
  [ -n "$CONFIG_MTIME" ] && printf '%s' "$CONFIG_MTIME" > "$CACHE_FILE" 2>/dev/null
  exit 0
fi

MSG="🚫 GitSpawn check: $CONFIG (o $GITDIR/hooks) tiene configuración que ejecuta un programa arbitrario en el próximo git status/diff/add/commit — patrón de GitSpawn (jun-2026, Manifold Security)."
for f in "${FLAGS[@]}"; do MSG="${MSG}\\n  ⚠ ${f}"; done
MSG="${MSG}\\n\\nInspeccioná $CONFIG a mano antes de correr git en este directorio. Si el repo es tuyo y sabés por qué está esa clave (ej. Watchman), agregalo al allowlist: echo \\\"${GITDIR_ABS:-$GITDIR}\\\" >> \\\"$ALLOW_FILE\\\""
ESC=$(printf '%s' "$MSG" | sed 's/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$ESC"
exit 0
