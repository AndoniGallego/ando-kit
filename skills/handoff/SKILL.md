---
name: handoff
description: Armá en un solo comando el contexto completo para agarrar un ticket o branch de otra persona — issue/ticket, estado del PR/branch, historial git del repo afectado, y spec existente si la hay. Usar cuando se retoma trabajo ajeno ("agarrá lo que dejó Fulano en la rama X") en vez de armar el contexto a mano leyendo el tracker, git log y comentarios de PR por separado.
---

## Paso 1 — Resolver ticket y branch

Input del usuario: un ID de issue/ticket, un nombre de branch, o ambos.

**Validar el identificador antes de usarlo en cualquier comando** — viene de texto libre del usuario y termina interpolado en `git`/`grep`. Aceptar: `^[A-Z]+-[0-9]+$` (Jira/Linear), `^#?[0-9]+$` (GitHub/GitLab), o un slug kebab `^[a-z0-9][a-z0-9._-]*$` (specs locales sin tracker). Si no matchea ninguno, no lo uses en ningún comando shell — pedile al usuario que lo reescriba. Una vez validado, guardalo en `$ticket_id` y usar siempre esa variable.

- Si viene un branch con convención `feature/TICKET-ID-descripcion`, `hotfix/...`, etc.: extraer el ticket ID por regex si aplica (un hotfix puede no tener ticket asociado — está bien si no hay).
- Si viene solo el ticket ID (ya validado): buscar el branch localmente en los repos conocidos con matching literal y límites de palabra:
  ```bash
  git -C <repo> branch -a --format='%(refname:short)' | grep -iE -- "(^|/)${ticket_id}(-|$)"
  ```
  Si no aparece en ningún repo, seguir sin branch. Si aparece en más de uno, pedirle al usuario que desambigüe.
- Si falta todo, pedir el dato al usuario — no adivinar.

## Paso 2 — Fase 1: tracker + PR/branch en paralelo

Despachar en simultáneo (un solo mensaje, dos tool calls):
- Lectura del **issue/ticket** (si se resolvió uno): si hay un agente de tracker configurado en el entorno, delegarle; si no, leer el issue con `gh issue view` / `glab issue view` / el MCP disponible y resumirlo en 3-4 líneas.
- **`pr-analyst`** con el repo + branch (si se resolvió uno) — soporta tanto Modo A (PR abierto) como Modo B (branch sin PR).

Si falta el ticket ID o el branch, saltar la pieza correspondiente y decirlo en el briefing final — no bloquear el resto.

## Paso 3 — Fase 2: historial git del repo afectado

Con el repo afectado (del ticket o del branch), invocar **`git-historian`** sobre ese módulo/repo. Puede ir en paralelo con la Fase 1 si el repo ya se conoce por el nombre del branch; si depende de resolver primero el ticket, esperarlo.

## Paso 4 — Chequear si hay spec existente

**Solo si hay un `ticket_id` validado** (un hotfix puede no tener ninguno — en ese caso saltar este paso y decirlo en el briefing):

```bash
if [ -n "${ticket_id:-}" ] && [ -n "${ANDO_SPECS_DIR:-}" ]; then
  test -f "$ANDO_SPECS_DIR/${ticket_id}.md" && echo FOUND
fi
```

Buscar también un `specs/` dentro del propio repo (`specs/${ticket_id}.md`, `docs/specs/...`). Si existe, leer el frontmatter (`status: draft|approved|done`) y extraer los criterios de aceptación con `Read` — chequeo trivial, no delegar.

## Paso 5 — Armar el briefing

Mostrar el documento completo al usuario (no resumirlo), con esta estructura fija:

```markdown
# Handoff — [TICKET-ID o branch]

## Ticket
[resumen del issue/ticket, o "sin ticket asociado" si no se resolvió uno]

## Branch / PR
[for_human de pr-analyst — incluye si es Modo A o B, críticos/mejoras si hay PR]

## Historial relevante
[resumen de git-historian: autores activos, señales de volatilidad/revert]

## Spec
[si hay spec: status + criterios de aceptación. Si no existe: "sin spec escrita todavía — considerar spec-writer antes de seguir si el cambio no es trivial". Si no hay ticket: "no aplica — sin ticket asociado"]

## Para arrancar
[síntesis de 2-3 líneas: qué falta resolver, qué mirar primero, cualquier bloqueante detectado]
```

## Caso borde: nada se resuelve

Si ni el ticket ni el branch existen en ningún lado accesible, no inventar contexto — decirle al usuario que no se encontró nada y pedir más detalle (¿otro repo? ¿ticket todavía no creado?).
