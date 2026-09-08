---
name: kit-doctor
description: Chequeo rápido de salud de la instalación del ando-kit — kit encontrado y versionado, sync entre el repo y ~/.claude, hooks ejecutables y sin errores de sintaxis, hooks registrados en settings.json, y opcionales (gate SDD, Engram). Read-only, nunca modifica nada. Invocar cuando algo "anda raro", después de instalar el kit en una máquina nueva, o cuando un amigo reporta que un hook/skill no dispara.
---

# kit-doctor

Diagnóstico read-only de la instalación local del ando-kit. **Nunca modifica nada** — si algo está mal, lo reporta y vos decidís el fix.

## Paso 1 — Correr el chequeo

```bash
bash "$HOME/.claude/skills/kit-doctor/scripts/doctor.sh"
```

(o desde el repo del kit: `bash "$ANDO_KIT_DIR/skills/kit-doctor/scripts/doctor.sh"`)

Salida: secciones con `✅` / `⚠️` / `❌` y un resumen. Exit code 1 si hay algún `❌`.

## Paso 2 — Interpretar y proponer el fix

| Síntoma en el reporte | Fix sugerido (proponer al usuario, no aplicar solo) |
|---|---|
| `ANDO_KIT_DIR no está seteado` | Agregarlo a `~/.claude/settings.json` → `env` y al shell rc (`~/.bashrc` / `~/.zshrc`) |
| `skills/agents/hooks: N sin instalar o distinto` | `bash "$ANDO_KIT_DIR/install.sh"` |
| `hook X no tiene permiso de ejecución` | `chmod +x ~/.local/bin/ando-*.sh` (o re-correr `install.sh`, que ya lo hace) |
| `hook X: error de sintaxis` | Bug real en el kit — revisar el archivo, correr `bash scripts/check.sh` en el repo |
| `hook X instalado pero NO referenciado en settings.json` | Fusionar el snippet de hooks que imprime `install.sh` en `~/.claude/settings.json` |
| `jq NO disponible` | Instalar `jq` (`apt install jq` / `brew install jq` / `choco install jq`) — sin él varios hooks salen sin hacer nada |
| `kit N commit(s) atrás de su upstream` | `git -C "$ANDO_KIT_DIR" pull` y después `install.sh` |
| `no es repo git` | `git init` en el kit si querés que `kit-bump`/`kit-sync` funcionen del todo |
| `ANDO_SPECS_DIR apunta a un dir inexistente` | Crear el dir o corregir la variable; o quitarla si no usás el gate SDD |
| `Engram MCP no conectado` | Opcional — reiniciar Claude Code, o instalar el plugin de memoria si lo querés |

## Paso 3 — Reporte al usuario

Resumí en 2-3 líneas: qué está sano, qué necesita acción, y el comando exacto para cada fix pendiente. No aplicar cambios sin confirmación — este skill diagnostica, no repara.

## Cuándo NO hace falta

Si todo viene funcionando y no cambiaste nada de la instalación, no aporta. Es para después de instalar, migrar de máquina, o cuando un comportamiento esperado (un hook, un skill que debería auto-activarse) no aparece.
