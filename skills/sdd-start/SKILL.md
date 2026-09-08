---
name: sdd-start
description: Arranca el ciclo Spec-Driven Development de un ticket o feature — crea la entrada en la carpeta central de specs (ANDO_SPECS_DIR), la draftea delegando a spec-writer, te la muestra completa, y la marca status:approved cuando la aprobás. Es el punto de entrada del flujo; después vienen implementación, /rdd-review, /spec-delta-apply y /sdd-archive. Invocar con "/sdd-start <TICKET-ID|descripción>" antes de crear el branch o escribir código.
trigger: /sdd-start
args: TICKET-ID | descripción corta de la feature
---

# sdd-start

Punto de entrada del flujo SDD. Su salida es **una spec aprobada en `ANDO_SPECS_DIR`**, no código y no un branch.

## Paso 1 — Resolver identificador y carpeta

```bash
: "${ANDO_SPECS_DIR:?ANDO_SPECS_DIR no configurado — setealo en ~/.claude/settings.json (env) y en tu shell rc}"
test -d "$ANDO_SPECS_DIR" || { echo "ANDO_SPECS_DIR apunta a un dir inexistente: $ANDO_SPECS_DIR"; exit 1; }
```

Del argumento del usuario:
- Si matchea un ID de tracker (`^[A-Z]+-[0-9]+$`, ej. `SITE-1234`) → ese es el `<TICKET-ID>`.
- Si es una descripción libre → generar un slug corto en `SCREAMING-KEBAB` como ID (ej. "agregar login con Google" → `LOGIN-GOOGLE`). Confirmárselo al usuario antes de seguir.

**Validá el `<TICKET-ID>` antes de interpolarlo en cualquier comando** — sólo `[A-Z0-9-]`. Guardalo en `$ticket_id`.

## Paso 2 — Chequear si ya existe

```bash
SPEC="$ANDO_SPECS_DIR/$ticket_id.md"
if [ -f "$SPEC" ]; then
  awk '/^---[[:space:]]*$/{c++;next} c==1 && /^status:/{print}' "$SPEC"
fi
```

- Si existe con `status: draft` → mostrarla y ofrecer continuar desde el Paso 4 (revisión/aprobación), sin re-draftear.
- Si existe con `status: approved` o `done` → avisar que ya está y **no** sobrescribir. Terminar acá.
- Si no existe → seguir al Paso 3.

## Paso 3 — Draftear con spec-writer

Delegar al agente **`spec-writer`** vía Agent tool, pasándole:
- El ticket/descripción tal como lo dio el usuario (+ link al tracker si lo hay).
- El repo path donde se va a implementar (preguntar si no es obvio del cwd).
- Instrucción de **guardar el documento en `$ANDO_SPECS_DIR/<TICKET-ID>.md`** además de devolverlo completo.

Cuando `spec-writer` termine, el orquestador (no el agente) se asegura de que el archivo tenga el frontmatter correcto al tope — si `spec-writer` no lo incluyó, agregarlo con `Edit`/`Write`:

```yaml
---
ticket: <TICKET-ID>
status: draft
created_at: <YYYY-MM-DD>
repo: <path relativo o nombre del repo>
---
```

(el resto del archivo es el cuerpo de la spec que devolvió `spec-writer`).

## Paso 4 — Mostrar y pedir aprobación

Mostrar la spec **completa** al usuario (no un resumen). Señalar explícitamente:
- Las **preguntas abiertas** que dejó `spec-writer`, si las hay — no se puede aprobar con preguntas abiertas sin resolver.
- Qué queda **fuera de scope**.

Preguntar: *¿la aprobás como está, querés cambios, o hay preguntas abiertas para resolver primero?*

- **Cambios** → aplicarlos (vos o re-delegando a `spec-writer` con el feedback) y volver a mostrar. El archivo sigue en `status: draft`.
- **Preguntas abiertas sin resolver** → dejar en `draft`, listar qué falta decidir. No aprobar.
- **Aprobada** → Paso 5.

## Paso 5 — Marcar aprobada

Con `Edit` sobre `$ANDO_SPECS_DIR/<TICKET-ID>.md`:

```
status: draft  →  status: approved
```

Agregar `approved_at: <YYYY-MM-DD>` bajo `status`.

## Paso 6 — Próximos pasos (informar, no ejecutar)

```
✅ Spec aprobada: $ANDO_SPECS_DIR/<TICKET-ID>.md (status: approved)

Siguiente:
  1. git checkout -b feature/<TICKET-ID>
  2. Implementar según la spec (delegando a agentes; test-strategist si querés plan de tests)
  3. /rdd-review sobre el branch antes de crear el PR
  4. /spec-delta-apply <TICKET-ID>   (si hay delta de specs de módulo)
  5. Crear el PR → /sdd-archive <TICKET-ID>   (marca la spec 'done')

El gate SDD (ando-sdd-gate.sh) ahora dejará pasar 'git push' de feature/<TICKET-ID>
porque la spec está approved.
```

**No** crear el branch ni escribir código en este skill — eso es el paso siguiente, decisión del usuario.

## Lo que este skill NO hace

- No crea branch ni commitea.
- No implementa nada.
- No aprueba una spec con preguntas abiertas pendientes.
- No sobrescribe una spec ya `approved` o `done`.
