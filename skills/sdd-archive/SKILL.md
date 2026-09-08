---
name: sdd-archive
description: Cierre formal de un ticket que siguió un flujo SDD (Spec-Driven Development) — marca la spec como done, guarda en Engram lo que se construyó y verifica que el PR/MR está creado. Invocar al final del ciclo, después de crear el PR.
---

## Paso 1 — Determinar el ticket

El orquestador pasa el ID. Si no se pasó, leerlo del branch actual:

```bash
git rev-parse --abbrev-ref HEAD | grep -oE '[A-Z]+-[0-9]+' | head -1
```

Si el branch no codifica un ticket (ej. `feature/kit-foo`, `hotfix/1.2.3`), seguir sin ticket — los pasos de spec se omiten y solo se hace el receipt en Engram.

## Paso 2 — Cerrar la spec

Buscar la spec en `$ANDO_SPECS_DIR/<TICKET-ID>.md` o en `specs/<TICKET-ID>.md` dentro del repo:

```bash
SPEC="${ANDO_SPECS_DIR:-.}/<TICKET-ID>.md"
[ -f "$SPEC" ] || SPEC="specs/<TICKET-ID>.md"
grep "^status:" "$SPEC" 2>/dev/null || echo "sin spec — omitir paso"
```

Si existe con `status: approved`, marcarla como done (con `Edit`, no `sed -i` a ciegas):

```
status: approved  →  status: done
```

Agregar `archived_at: YYYY-MM-DD` bajo `status`.

## Paso 3 — Guardar en Engram

Llamar a `mem_save` con tipo `project` y topic_key `<TICKET-ID>` (o una descripción corta si no hay ticket). Incluir:
- Qué se construyó (resumen de 2-3 líneas)
- Repos tocados y archivos clave modificados
- Decisiones de arquitectura o patterns usados
- Número de PR/MR creado

## Paso 4 — Verificar specs del módulo

Si el repo tiene un directorio `specs/` de módulos:

```bash
ls specs/ 2>/dev/null || echo "repo sin specs/ — deuda técnica, registrar en Engram, no bloquear"
git diff "$(git merge-base HEAD origin/HEAD 2>/dev/null || echo HEAD~1)"..HEAD -- specs/ 2>/dev/null | head -5 \
  || echo "sin cambios en specs en este branch"
```

- Sin `specs/`: es deuda técnica — registrarla en Engram y sugerir abrir un ticket de documentación. No bloquear el PR por esto.
- Con `specs/` pero sin cambios en el branch: verificar manualmente que el ticket no impactó ningún `requirements.md` o `design.md`. Si impactó, correr `spec-updater` o `spec-delta-apply` antes de mergear.

## Paso 5 — Verificar PR/MR

```bash
gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number' 2>/dev/null \
  || glab mr list --source-branch "$(git branch --show-current)" 2>/dev/null | head -1 \
  || echo "SIN PR — crear antes de cerrar"
```

Si no hay PR: no continuar. Volver a crear el PR primero.

## Paso 6 — Reporte

```text
✅ Spec <TICKET-ID>: status → done
✅ Specs del módulo: actualizadas (o deuda registrada en Engram)
✅ Engram: contexto guardado
✅ PR/MR: #XXX
```
