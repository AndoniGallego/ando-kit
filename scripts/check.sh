#!/bin/bash
# check.sh — lint del propio ando-kit. Valida que todo skill/agent/hook esté bien
# formado antes de commitear o compartir. Corre en segundos, sin dependencias más
# allá de bash y (opcional) shellcheck.
#
# Uso:   bash scripts/check.sh
# Exit:  0 si todo pasa, 1 si hay al menos un FAIL. Los WARN no cambian el exit code.

set -uo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR"

FAIL=0
WARN=0
PASS=0

red()   { printf '  \033[31m✗ %s\033[0m\n' "$1"; FAIL=$((FAIL+1)); }
yellow(){ printf '  \033[33m⚠ %s\033[0m\n' "$1"; WARN=$((WARN+1)); }
green() { printf '  \033[32m✓ %s\033[0m\n' "$1"; PASS=$((PASS+1)); }

# --- Extraer el bloque de frontmatter YAML (entre el primer par de '---') ---
frontmatter() {
  awk '/^---[[:space:]]*$/{c++; next} c==1{print} c>=2{exit}' "$1"
}

echo "== ando-kit check =="
echo "Kit: $KIT_DIR"

# ---------------------------------------------------------------- Skills
echo ""
echo "-- Skills --"
if [ -d skills ]; then
  for d in skills/*/; do
    name="$(basename "$d")"
    f="$d/SKILL.md"
    if [ ! -f "$f" ]; then
      red "$name: falta SKILL.md"
      continue
    fi
    fm="$(frontmatter "$f")"
    if [ -z "$fm" ]; then
      red "$name: SKILL.md sin frontmatter (--- ... ---)"
      continue
    fi
    fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
    fm_desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
    [ -z "$fm_name" ] && { red "$name: frontmatter sin 'name:'"; continue; }
    [ -z "$fm_desc" ] && { red "$name: frontmatter sin 'description:'"; continue; }
    if [ "$fm_name" != "$name" ] && [ "$(printf '%s' "$fm_name" | tr '[:upper:]' '[:lower:]')" != "$name" ]; then
      yellow "$name: 'name: $fm_name' no coincide con el directorio"
    fi
    [ "${#fm_desc}" -lt 40 ] && yellow "$name: description muy corta (${#fm_desc} car) — el trigger puede fallar"
    green "$name"
  done
else
  yellow "no hay directorio skills/"
fi

# ---------------------------------------------------------------- Agents
echo ""
echo "-- Agents --"
if [ -d agents ]; then
  for f in agents/*.md; do
    [ -e "$f" ] || { yellow "no hay agentes"; break; }
    name="$(basename "$f" .md)"
    fm="$(frontmatter "$f")"
    if [ -z "$fm" ]; then red "$name: sin frontmatter"; continue; fi
    fm_name="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
    fm_desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
    [ -z "$fm_name" ] && { red "$name: frontmatter sin 'name:'"; continue; }
    [ -z "$fm_desc" ] && { red "$name: frontmatter sin 'description:'"; continue; }
    [ "$fm_name" != "$name" ] && yellow "$name: 'name: $fm_name' no coincide con el archivo"
    grep -q '<!-- AOP:BEGIN -->' "$f" || yellow "$name: sin envelope AOP v2 (convención del kit)"
    green "$name"
  done
else
  yellow "no hay directorio agents/"
fi

# ---------------------------------------------------------------- Hooks
echo ""
echo "-- Hooks --"
if [ -d hooks ]; then
  for f in hooks/*.sh; do
    [ -e "$f" ] || { yellow "no hay hooks"; break; }
    name="$(basename "$f")"
    head -1 "$f" | grep -q '^#!' || yellow "$name: sin shebang"
    if ! bash -n "$f" 2>/dev/null; then
      red "$name: error de sintaxis (bash -n)"
      continue
    fi
    if command -v shellcheck >/dev/null 2>&1; then
      shellcheck -S warning "$f" >/dev/null 2>&1 || yellow "$name: shellcheck reporta observaciones (bash -n OK)"
    fi
    green "$name"
  done
else
  yellow "no hay directorio hooks/"
fi

# ---------------------------------------------------------------- Meta
echo ""
echo "-- Meta --"
[ -f VERSION ] && green "VERSION ($(cat VERSION | tr -d '[:space:]'))" || yellow "sin archivo VERSION"
[ -f README.md ] && green "README.md" || red "falta README.md"
[ -f install.sh ] && green "install.sh" || red "falta install.sh"
[ -f CHANGELOG.md ] && green "CHANGELOG.md" || yellow "sin CHANGELOG.md"

# ---------------------------------------------------------------- Resumen
echo ""
echo "== Resumen =="
printf '  %s✓ %d PASS%s   %s⚠ %d WARN%s   %s✗ %d FAIL%s\n' \
  "$(tput setaf 2 2>/dev/null)" "$PASS" "$(tput sgr0 2>/dev/null)" \
  "$(tput setaf 3 2>/dev/null)" "$WARN" "$(tput sgr0 2>/dev/null)" \
  "$(tput setaf 1 2>/dev/null)" "$FAIL" "$(tput sgr0 2>/dev/null)"

[ "$FAIL" -gt 0 ] && exit 1
exit 0
