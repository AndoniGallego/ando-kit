#!/bin/bash
# ando-kit installer — instala skills, agents y hooks personales en Claude Code.
# Idempotente: se puede correr varias veces sin romper nada.
set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
AGENTS_DIR="$HOME/.claude/agents"
RULES_DIR="$HOME/.claude/rules"
HOOKS_DIR="$HOME/.local/bin"

echo "== ando-kit installer =="
echo "Kit encontrado en: $KIT_DIR"
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR" "$RULES_DIR" "$HOOKS_DIR"

echo ""
echo "-- Skills --"
count=0
for d in "$KIT_DIR"/skills/*/; do
  name="$(basename "$d")"
  mkdir -p "$SKILLS_DIR/$name"
  cp -r "$d"* "$SKILLS_DIR/$name/"
  echo "  ✓ $name"
  count=$((count+1))
done
echo "Skills instalados: $count"

echo ""
echo "-- Agents --"
count=0
for f in "$KIT_DIR"/agents/*.md; do
  cp "$f" "$AGENTS_DIR/"
  echo "  ✓ $(basename "$f")"
  count=$((count+1))
done
echo "Agents instalados: $count"

echo ""
echo "-- Rules --"
count=0
for f in "$KIT_DIR"/rules/*.md; do
  cp "$f" "$RULES_DIR/"
  echo "  ✓ $(basename "$f")"
  count=$((count+1))
done
echo "Rules instaladas: $count"

echo ""
echo "-- Hooks --"
count=0
for f in "$KIT_DIR"/hooks/*.sh; do
  cp "$f" "$HOOKS_DIR/"
  chmod +x "$HOOKS_DIR/$(basename "$f")"
  echo "  ✓ $(basename "$f")"
  count=$((count+1))
done
echo "Hooks instalados: $count"

echo ""
echo "-- Variable de entorno ANDO_KIT_DIR --"
SHELL_RC="$HOME/.bashrc"
[ -n "${ZSH_VERSION:-}" ] && SHELL_RC="$HOME/.zshrc"
if ! grep -q "ANDO_KIT_DIR" "$SHELL_RC" 2>/dev/null; then
  echo "export ANDO_KIT_DIR=\"$KIT_DIR\"" >> "$SHELL_RC"
  echo "  ✓ Agregado ANDO_KIT_DIR=$KIT_DIR a $SHELL_RC (abrí una terminal nueva o hacé source)"
else
  echo "  ✓ ANDO_KIT_DIR ya estaba configurado en $SHELL_RC — verificalo apunta a: $KIT_DIR"
fi

echo ""
echo "== settings.json =="
echo "No se edita automáticamente (evita bloqueos del auto-mode). Fusioná esto a mano en ~/.claude/settings.json:"
cat << 'EOF'
{
  "env": {
    "ANDO_KIT_DIR": "<ruta real de este kit>",
    "ANDO_SPECS_DIR": "<opcional: dir donde guardás tus specs <TICKET-ID>.md — habilita el gate SDD>"
  },
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/ando-kit-update-check.sh", "timeout": 10 },
          { "type": "command", "command": "$HOME/.local/bin/ando-doctor-sessionstart.sh", "timeout": 15 }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/ando-git-trust-check.sh", "timeout": 10 },
          { "type": "command", "command": "$HOME/.local/bin/ando-prepush-check.sh", "timeout": 10 },
          { "type": "command", "command": "$HOME/.local/bin/ando-rdd-reminder.sh", "timeout": 10 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/ando-kit-sync.sh", "timeout": 5 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "$HOME/.local/bin/ando-delegation-reminder.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.local/bin/ando-context-threshold.sh", "timeout": 5 },
          { "type": "command", "command": "$HOME/.local/bin/ando-engram-check-reminder.sh", "timeout": 5 }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "$HOME/.local/bin/ando-statusline-context.sh"
  }
}
EOF
echo ""
echo "Notas:"
echo "  - ando-sdd-gate.sh NO se registra como hook — lo invoca ando-prepush-check.sh."
echo "  - ando-doctor-sessionstart.sh es opcional: registralo como SessionStart (arriba) si querés"
echo "    el chequeo de salud automático al arrancar. Corré /kit-doctor cuando quieras el detalle."
echo "  - ando-kit-update-check.sh (sustituto de cron — Windows no tiene): en cada sesión, como"
echo "    mucho una vez cada 12hs, hace 'git fetch' del kit y avisa si hay commits nuevos en"
echo "    origin. Por defecto solo avisa; para que además haga pull+install solo (sólo con el"
echo "    working tree del kit limpio), exportá: ANDO_KIT_AUTOUPDATE=1"
echo "  - ando-git-trust-check.sh (defensa GitSpawn) BLOQUEA git en un repo cuyo .git/config o"
echo "    .git/hooks/ trae algo que ejecuta un programa (fsmonitor/hooksPath/pager/editor/"
echo "    sshCommand/askpass/credential.helper, o un hook ejecutable no-sample). Para tus propios"
echo "    repos que legítimamente usan alguna de estas claves (ej. Watchman):"
echo "    echo \"/ruta/a/tu/repo/.git\" >> ~/.claude/.ando-git-trust-allow"

echo ""
echo "== Listo =="
echo "Skills: $SKILLS_DIR | Agents: $AGENTS_DIR | Rules: $RULES_DIR | Hooks: $HOOKS_DIR"
echo "Revisá README.md y CLAUDE.md.template en $KIT_DIR para terminar de armar tu ~/.claude/CLAUDE.md personal."
