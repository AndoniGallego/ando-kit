#!/bin/bash
# ando-kit-sync.sh — Hook PostToolUse (matcher: Write|Edit)
#
# Sincroniza automáticamente, en ambas direcciones, agents/skills/hooks entre
# ~/.claude/ (entorno activo) y el repo del ando-kit (ANDO_KIT_DIR):
#
#   ~/.claude/skills/<skill>/**  <->  ando-kit/skills/<skill>/**  (directorio completo)
#   ~/.claude/agents/*.md        <->  ando-kit/agents/*.md
#   ~/.claude/rules/*.md         <->  ando-kit/rules/*.md
#   ~/.local/bin/ando-*.sh       <->  ando-kit/hooks/*.sh
#
# Se dispara en cada Write/Edit. Si el archivo no está en ninguna ruta
# monitoreada, sale silenciosamente. Los hooks NUNCA deben romper el flujo
# principal: cualquier condición inesperada se loggea y sale con exit 0.

set -uo pipefail

ANDO_KIT_DIR="${ANDO_KIT_DIR:-$HOME/ando-kit}"
LOG_FILE="${ANDO_KIT_SYNC_LOG:-$HOME/.claude/logs/ando-kit-sync.log}"
CLAUDE="$HOME/.claude"
HOOKS_BIN="$HOME/.local/bin"

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    printf '[%s] %s\n' "$(date -Iseconds 2>/dev/null || date)" "$1" >> "$LOG_FILE" 2>/dev/null
}

if [ ! -d "$ANDO_KIT_DIR" ]; then
    log "ANDO_KIT_DIR ($ANDO_KIT_DIR) no existe — skip sync"
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    log "jq no disponible — skip sync"
    exit 0
fi

INPUT_JSON="$(cat)"

TOOL_NAME="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_name // empty' 2>/dev/null)"
FILE_PATH="$(printf '%s' "$INPUT_JSON" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"

if [ -z "$FILE_PATH" ]; then
    log "no se pudo extraer file_path del payload (tool_name=$TOOL_NAME) — skip"
    exit 0
fi

case "$TOOL_NAME" in
    Write|Edit) ;;
    *)
        log "tool_name=$TOOL_NAME no es Write/Edit — skip"
        exit 0
        ;;
esac

if [ ! -f "$FILE_PATH" ]; then
    log "archivo fuente no existe (¿fue borrado?): $FILE_PATH — skip"
    exit 0
fi

sync_copy() {
    SRC="$1"
    DEST="$2"
    DEST_DIR="$(dirname "$DEST")"
    if ! mkdir -p "$DEST_DIR" 2>/dev/null; then
        log "no se pudo crear $DEST_DIR — skip"
        return 1
    fi
    if cp -f "$SRC" "$DEST" 2>/dev/null; then
        log "sync OK: $SRC -> $DEST"
        return 0
    fi
    log "cp falló: $SRC -> $DEST"
    return 1
}

# ~/.claude/skills/<skill>/** -> ando-kit/skills/<skill>/** (directorio completo)
if [[ "$FILE_PATH" == "$CLAUDE/skills/"* ]]; then
    REL_PATH="${FILE_PATH#"$CLAUDE"/skills/}"
    sync_copy "$FILE_PATH" "$ANDO_KIT_DIR/skills/$REL_PATH"
    exit 0
fi

# ando-kit/skills/<skill>/** -> ~/.claude/skills/<skill>/**
if [[ "$FILE_PATH" == "$ANDO_KIT_DIR/skills/"* ]]; then
    REL_PATH="${FILE_PATH#"$ANDO_KIT_DIR"/skills/}"
    sync_copy "$FILE_PATH" "$CLAUDE/skills/$REL_PATH"
    exit 0
fi

# ~/.claude/agents/*.md -> ando-kit/agents/
if [[ "$FILE_PATH" == "$CLAUDE/agents/"*.md ]]; then
    REL_PATH="${FILE_PATH#"$CLAUDE"/agents/}"
    sync_copy "$FILE_PATH" "$ANDO_KIT_DIR/agents/$REL_PATH"
    exit 0
fi

# ando-kit/agents/*.md -> ~/.claude/agents/
if [[ "$FILE_PATH" == "$ANDO_KIT_DIR/agents/"*.md ]]; then
    REL_PATH="${FILE_PATH#"$ANDO_KIT_DIR"/agents/}"
    sync_copy "$FILE_PATH" "$CLAUDE/agents/$REL_PATH"
    exit 0
fi

# ~/.claude/rules/*.md -> ando-kit/rules/
if [[ "$FILE_PATH" == "$CLAUDE/rules/"*.md ]]; then
    REL_PATH="${FILE_PATH#"$CLAUDE"/rules/}"
    sync_copy "$FILE_PATH" "$ANDO_KIT_DIR/rules/$REL_PATH"
    exit 0
fi

# ando-kit/rules/*.md -> ~/.claude/rules/
if [[ "$FILE_PATH" == "$ANDO_KIT_DIR/rules/"*.md ]]; then
    REL_PATH="${FILE_PATH#"$ANDO_KIT_DIR"/rules/}"
    sync_copy "$FILE_PATH" "$CLAUDE/rules/$REL_PATH"
    exit 0
fi

# ~/.local/bin/ando-*.sh -> ando-kit/hooks/
if [[ "$FILE_PATH" == "$HOOKS_BIN/ando-"*.sh ]]; then
    FILENAME="$(basename "$FILE_PATH")"
    if sync_copy "$FILE_PATH" "$ANDO_KIT_DIR/hooks/$FILENAME"; then
        chmod +x "$ANDO_KIT_DIR/hooks/$FILENAME" 2>/dev/null
    fi
    exit 0
fi

# ando-kit/hooks/*.sh -> ~/.local/bin/
if [[ "$FILE_PATH" == "$ANDO_KIT_DIR/hooks/"*.sh ]]; then
    FILENAME="$(basename "$FILE_PATH")"
    if sync_copy "$FILE_PATH" "$HOOKS_BIN/$FILENAME"; then
        chmod +x "$HOOKS_BIN/$FILENAME" 2>/dev/null
    fi
    exit 0
fi

exit 0
