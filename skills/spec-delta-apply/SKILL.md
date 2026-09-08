---
name: spec-delta-apply
description: Aplica el delta de specs de un módulo al working tree antes de crear el PR. Lee <TICKET-ID>.delta.md, modifica los requirements.md del módulo (ADDED/MODIFIED/REMOVED), y marca el delta como archived. Los archivos quedan en el working tree para que el developer los revise y commitee junto con el código.
trigger: /spec-delta-apply
args: TICKET-ID
---

## Invocación

```
/spec-delta-apply TICKET-ID
```

Correr después de terminar la implementación y el review por agentes, antes de crear el PR/MR.

## Paso 1 — Leer el delta

```bash
SPECS_DIR="${ANDO_SPECS_DIR:?ANDO_SPECS_DIR no configurado}"
DELTA="$SPECS_DIR/<TICKET-ID>.delta.md"
[ -f "$DELTA" ] || { echo "ERROR: delta no encontrado en $DELTA"; exit 1; }
```

Reemplazar `<TICKET-ID>` con el argumento recibido. Leer el archivo delta completo con `Read`.

Si `status: archived`: avisar que ya fue aplicado y salir sin cambios.

## Paso 2 — Leer frontmatter

Del delta extraer:
- `repo_path` → path (relativo a `$ANDO_PROJECTS_ROOT` o absoluto) del repo destino
- `bootstrap` → `true` o `false`

## Paso 3 — Modo bootstrap (si `bootstrap: true`)

1. Crear la estructura mínima de specs:
   ```bash
   mkdir -p "<repo_path>/specs/modules"
   ```
2. Crear `specs/README.md` mínimo si no existe.
3. Crear los archivos de módulo que el delta menciona (los listados en las secciones H2).

Si `bootstrap: false` y `specs/` no existe → error con instrucción clara: "El repo no tiene specs/. Revisar si bootstrap debería ser true en el delta."

## Paso 4 — Aplicar operaciones del delta

Parsear el delta sección por sección:
- **H2** = ruta relativa del archivo destino dentro de `repo_path` (ej: `specs/modules/use-cases/requirements.md`)
- **H3** = operación con nombre (ej: `### ADDED: UC-007 ExtendReservation`)

Para cada archivo destino (`H2`):

1. Leer el archivo actual con `Read` (o verificar que no existe si es ADDED en bootstrap).
2. Para cada operación `H3`:

   **`ADDED: Nombre`** — La sección no existe en el target. Agregar el bloque completo al final de la sección correspondiente.

   **`MODIFIED: Nombre`** — Buscar la sección por nombre exacto en el target, reemplazar su contenido con el del delta. Usar `Edit` con suficiente contexto para que el match sea único.

   **`REMOVED: Nombre`** — Mover la sección al bloque `## Deprecated` del target (crearlo si no existe), agregando la fecha de hoy en formato `YYYY-MM-DD`.

3. Aplicar los cambios con `Edit` (o `Write` para archivos nuevos).

## Paso 5 — Actualizar specs/README.md

Si el delta agrega módulos nuevos que no están en `specs/README.md`, agregarlos.

## Paso 6 — Marcar el delta como archived

Con `Edit`, actualizar el frontmatter del delta:

```
status: pending  →  status: archived
```

Agregar una línea `archived_at: YYYY-MM-DD` bajo `status`.

## Paso 7 — Imprimir resumen

```
✅ spec-delta-apply <TICKET-ID> aplicado

Archivos modificados en <repo_path>/:
  specs/modules/use-cases/requirements.md  (+UC-XXX NombreCasoDeUso)
  ...

Revisá los cambios:
  git -C <repo_path> diff specs/

Cuando conforme, stagear junto con el código:
  git add specs/ src/ ...
```

## Lo que este skill NO hace

- No ejecuta `git add` ni `git commit` — el developer revisa y stagea manualmente.
- No toca `$ANDO_SPECS_DIR/<TICKET-ID>.md` — ese archivo lo cierra `/sdd-archive`.
- No crea el PR.
