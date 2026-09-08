#!/bin/bash
# doctor.sh — chequeo read-only de salud de la instalación del ando-kit.
# NUNCA modifica nada: si algo está mal, lo reporta, no lo arregla.
#
# Uso:   bash ~/.claude/skills/kit-doctor/scripts/doctor.sh
# Exit:  0 si no hay ❌; 1 si hay al menos un ❌. Los ⚠️ no cambian el exit code.

set -uo pipefail

KIT="${ANDO_KIT_DIR:-$HOME/ando-kit}"
CLAUDE="$HOME/.claude"
HOOKS_BIN="$HOME/.local/bin"
PASS=0; WARN=0; FAIL=0

section() { echo ""; echo "$1"; }
ok()   { echo "  ✅ $1"; PASS=$((PASS+1)); }
warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }
fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
info() { echo "  ℹ️  $1"; }

echo "=== kit-doctor ==="

# --- KIT DIR ---
section "KIT"
if [ -z "${ANDO_KIT_DIR:-}" ]; then
  warn "ANDO_KIT_DIR no está seteado — usando fallback $KIT (setealo en ~/.claude/settings.json → env y en tu shell rc)"
fi
if [ -d "$KIT" ] && [ -d "$KIT/skills" ] && [ -d "$KIT/agents" ] && [ -d "$KIT/hooks" ]; then
  ok "kit en $KIT (skills/ agents/ hooks/ presentes)"
  [ -f "$KIT/VERSION" ] && ok "versión del kit: $(tr -d '[:space:]' < "$KIT/VERSION")" || warn "sin archivo VERSION en el kit"
  if [ -d "$KIT/.git" ]; then
    BEHIND=$(git -C "$KIT" rev-list --count '@..@{u}' 2>/dev/null)
    [ -n "$BEHIND" ] && [ "$BEHIND" -gt 0 ] 2>/dev/null && warn "kit $BEHIND commit(s) atrás de su upstream (git -C \"$KIT\" pull)" || ok "kit git: al día con upstream (o sin upstream configurado)"
    [ -n "$(git -C "$KIT" status --porcelain 2>/dev/null)" ] && info "hay cambios sin commitear en el kit (normal si estás iterando)"
  else
    info "$KIT no es repo git — kit-bump/kit-sync funcionan parcial (sin tags ni historial)"
  fi
else
  fail "no se encontró un kit válido en $KIT"
fi

# --- DEPENDENCIAS ---
section "DEPENDENCIAS"
command -v jq >/dev/null 2>&1 && ok "jq disponible (los hooks lo necesitan)" || fail "jq NO disponible — varios hooks salen sin hacer nada"
command -v git >/dev/null 2>&1 && ok "git disponible" || fail "git NO disponible"

# --- SYNC kit <-> ~/.claude ---
section "SYNC"
sync_dir() {
  local label="$1" src="$2" dst="$3" pat="$4"
  [ -d "$src" ] || { warn "$label: origen $src no existe"; return; }
  local missing=0 diffs=0 f rel
  while IFS= read -r f; do
    rel="${f#"$src"/}"
    if [ ! -e "$dst/$rel" ]; then
      missing=$((missing+1))
    elif ! diff -q "$f" "$dst/$rel" >/dev/null 2>&1; then
      diffs=$((diffs+1))
    fi
  done < <(find "$src" -type f -name "$pat" 2>/dev/null)
  if [ "$missing" -eq 0 ] && [ "$diffs" -eq 0 ]; then
    ok "$label en sync con el kit"
  else
    warn "$label: $missing sin instalar, $diffs distinto(s) — correr 'bash $KIT/install.sh'"
  fi
}
sync_dir "skills" "$KIT/skills" "$CLAUDE/skills" "*.md"
sync_dir "agents" "$KIT/agents" "$CLAUDE/agents" "*.md"

HOOK_DRIFT=0
for f in "$KIT"/hooks/*.sh; do
  b=$(basename "$f")
  if [ ! -f "$HOOKS_BIN/$b" ]; then
    warn "hook $b no instalado en $HOOKS_BIN"; HOOK_DRIFT=1
  elif ! diff -q "$f" "$HOOKS_BIN/$b" >/dev/null 2>&1; then
    warn "hook $b difiere del kit"; HOOK_DRIFT=1
  fi
done
[ "$HOOK_DRIFT" -eq 0 ] && ok "hooks en sync con el kit"

# --- HOOKS: ejecutables y sintaxis ---
section "HOOKS"
for f in "$HOOKS_BIN"/ando-*.sh; do
  [ -e "$f" ] || { warn "no hay hooks ando-* en $HOOKS_BIN — correr install.sh"; break; }
  b=$(basename "$f")
  [ -x "$f" ] || warn "$b no tiene permiso de ejecución (chmod +x)"
  bash -n "$f" 2>/dev/null && : || fail "$b: error de sintaxis"
done
[ "$FAIL" -eq 0 ] && [ -e "$HOOKS_BIN/ando-kit-sync.sh" ] && ok "hooks ejecutables y sin errores de sintaxis"

# --- SETTINGS: hooks registrados ---
section "SETTINGS"
SETTINGS="$CLAUDE/settings.json"
if [ -f "$SETTINGS" ]; then
  ok "settings.json presente"
  for h in ando-kit-sync ando-delegation-reminder ando-context-threshold ando-engram-check-reminder ando-prepush-check ando-rdd-reminder ando-git-trust-check ando-statusline-context; do
    grep -q "$h" "$SETTINGS" && ok "registrado: $h" || warn "hook $h instalado pero NO referenciado en settings.json"
  done
  grep -q "ando-doctor-sessionstart" "$SETTINGS" 2>/dev/null && ok "registrado: ando-doctor-sessionstart (SessionStart)" \
    || { [ -f "$HOOKS_BIN/ando-doctor-sessionstart.sh" ] && info "ando-doctor-sessionstart.sh instalado pero no registrado (agregalo como hook SessionStart si lo querés automático)"; }
else
  fail "no hay $SETTINGS"
fi

# --- CLAUDE.md ---
section "CLAUDE.md"
GLOBAL_MD="$CLAUDE/CLAUDE.md"
if [ -f "$GLOBAL_MD" ]; then
  if grep -q 'ANDO_KIT_DIR\|ando-kit\|Flujo SDD' "$GLOBAL_MD"; then
    ok "~/.claude/CLAUDE.md presente y menciona el kit"
  else
    warn "~/.claude/CLAUDE.md existe pero no parece incluir las reglas del kit — copiá desde CLAUDE.md.template"
  fi
else
  fail "no hay ~/.claude/CLAUDE.md — sin él las reglas de orquestación/SDD/AOP no están activas. Copiá: cp \"\$ANDO_KIT_DIR/CLAUDE.md.template\" ~/.claude/CLAUDE.md"
fi

# --- SEGURIDAD ---
section "SEGURIDAD"
if [ -x "$HOOKS_BIN/ando-git-trust-check.sh" ]; then
  ok "ando-git-trust-check.sh instalado (defensa GitSpawn — bloquea git en repos con .git/config sospechoso)"
  ALLOW_FILE="$CLAUDE/.ando-git-trust-allow"
  if [ -f "$ALLOW_FILE" ]; then
    N=$(grep -c . "$ALLOW_FILE" 2>/dev/null || echo 0)
    info "allowlist de repos propios: $N entrada(s) en $ALLOW_FILE"
  fi
else
  fail "ando-git-trust-check.sh no instalado — sin defensa contra GitSpawn (core.fsmonitor y similares en .git/config de terceros)"
fi
if command -v gitleaks >/dev/null 2>&1; then
  ok "gitleaks disponible ($(gitleaks version 2>/dev/null | head -1)) — chequeo de secretos activo en ando-prepush-check.sh"
else
  info "gitleaks no instalado (opcional) — sin chequeo de secretos en el pre-push. brew install gitleaks / scoop install gitleaks / apt install gitleaks"
fi

# --- OPCIONALES ---
section "OPCIONALES"
if [ -n "${ANDO_SPECS_DIR:-}" ]; then
  [ -d "$ANDO_SPECS_DIR" ] && ok "ANDO_SPECS_DIR → $ANDO_SPECS_DIR (gate SDD activo)" || warn "ANDO_SPECS_DIR apunta a un dir inexistente: $ANDO_SPECS_DIR"
else
  info "ANDO_SPECS_DIR sin setear — el gate SDD no actúa (es opt-in)"
fi
if command -v claude >/dev/null 2>&1; then
  claude mcp list 2>/dev/null | grep -qiE 'engram.*(connected|✓)' && ok "Engram MCP conectado" || info "Engram MCP no aparece conectado (opcional — la memoria persistente no estará disponible)"
fi

echo ""
echo "=== RESUMEN: $PASS ✅  $WARN ⚠️  $FAIL ❌ ==="
[ "$FAIL" -gt 0 ] && exit 1
exit 0
