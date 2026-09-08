# Contribuir al ando-kit

Es un kit personal, pero está abierto. Si querés proponer un cambio:

## Antes de tocar nada

- Leé el `README.md` — el modelo mental (skill / agent / hook) y la filosofía de orquestación.
- El kit es agnóstico de proyecto y **no contiene nada propietario de ningún empleador**. Cualquier cosa atada a un stack, una empresa o una herramienta interna no entra.

## Estructura

```
skills/<nombre>/SKILL.md      procedimiento guiado (frontmatter: name, description)
agents/<nombre>.md            ejecutor aislado (frontmatter: name, description, tools, model)
hooks/ando-<nombre>.sh        script de evento del harness (prefijo ando-, set -uo pipefail)
scripts/check.sh              lint del propio kit
install.sh                    instalador idempotente
CLAUDE.md.template             instrucciones globales de ejemplo
```

## Convenciones

**Skills**
- `description` de 1-2 frases, concreta, que diga *cuándo* se activa — es lo que dispara la auto-activación por contexto.
- Pasos numerados con comandos exactos. Una sección "Lo que este skill NO hace" cuando ayuda a acotar.

**Agents**
- `tools: Read, Bash` (string separada por comas). `model: sonnet` / `haiku` (alias bare, nunca un ID con fecha — no envejece).
- Cierran SIEMPRE con el envelope AOP v2 entre marcadores `<!-- AOP:BEGIN -->` / `<!-- AOP:END -->` (ver `README.md`).
- Corren en aislamiento: leen lo que necesitan, devuelven un reporte compacto, nunca vuelcan material crudo.

**Hooks**
- Prefijo `ando-`, `#!/bin/bash`, `set -uo pipefail`.
- **Nunca rompen el flujo principal**: cualquier condición inesperada → `exit 0` sin imprimir.
- Sólo comunican vía `systemMessage` / `additionalContext`. El único que puede bloquear es `ando-prepush-check.sh`, y sólo para el caso auto-infligido del gate SDD.
- Configurables por variable de entorno cuando tenga sentido (`ANDO_*`).

## Antes de commitear

```bash
bash scripts/check.sh        # frontmatter, envelope AOP v2, bash -n en hooks
bash install.sh              # verificar que instala sin romper
```

- Commits con **Conventional Commits** (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, …).
- Si el cambio merece versión: skill `kit-bump` (o a mano: `VERSION` + `CHANGELOG.md` + tag `vX.Y.Z`). `patch` = fix; `minor` = skill/agent/feature nueva; `major` = rompe compatibilidad.
- El CI (`.github/workflows/check.yml`) corre `scripts/check.sh` en cada push a `main` y cada PR.

## Nada de datos personales

Antes de pushear: sin rutas absolutas personales, sin nombres/mails reales en ejemplos, sin tokens, sin hosts internos. Los ejemplos usan placeholders genéricos (`alice`, `src/auth.ts`, `SITE-1234`).
