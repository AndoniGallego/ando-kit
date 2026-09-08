---
name: sdd-start
description: Arranca el ciclo Spec-Driven Development de una tarea de implementación. Título-primero — deriva un slug legible del título (o el orquestador lo propone a partir de lo pedido); no requiere ticket ni tracker. Crea la entrada en ANDO_SPECS_DIR, la draftea con spec-writer, la muestra completa, y la marca status:approved cuando el usuario la aprueba. Lo INVOCA EL ORQUESTADOR automáticamente cuando detecta trabajo de implementación no trivial (ver Activation Contract); el usuario puede además invocarlo con "/sdd-start <título>".
trigger: /sdd-start
args: título de la tarea | slug | TICKET-ID (todos opcionales)
---

# sdd-start

Punto de entrada del flujo SDD. Su salida es **una spec aprobada en `ANDO_SPECS_DIR`**, no código y no un branch.

## Activation Contract — quién lo dispara

**Principalmente el orquestador, por criterio propio.** Ante un pedido de implementación, antes de tocar código, el orquestador evalúa si la tarea es no trivial:

| Arrancar el flujo SDD | Ir directo, sin spec |
|---|---|
| Introduce comportamiento nuevo observable | Fix de una línea con causa obvia |
| Toca un contrato (firma pública, API, evento, esquema) | Rename / formateo / mover archivos |
| Lógica de negocio nueva o modificada | Cambio de config o copy |
| Migración o backfill de datos | Bump de versión, changelog |
| Relevante a seguridad / permisos / dinero / concurrencia | Ajuste cosmético de UI sin lógica |
| Va a tocar ~3+ archivos, o el approach no es obvio | Algo que el usuario pidió con instrucciones exactas y sin ambigüedad |
| El usuario dijo "esto es delicado" / "no puede fallar" | El usuario pidió explícitamente velocidad sobre rigor |

Si cae en la izquierda: **la spec es requerida**. El orquestador arranca este skill él mismo, avisando en una línea ("esto amerita una spec, arranco `sdd-start`"), y **no implementa código spec-worthy ni hace `git push` / abre PR de la rama `feature/<id>` hasta que la spec esté `status: approved`**. La única forma de saltearla es que el usuario lo vete explícitamente ("no, andá directo") — en ese caso **no se crea el archivo de spec** (su ausencia es la señal de que se decidió no seguir SDD, y el gate queda mudo).

Si cae en la derecha, o hay duda genuina hacia lo trivial: seguir sin spec y decirlo en una línea.

**El usuario también puede invocarlo a mano** (`/sdd-start "rate limiting en el login"`), pero no debería ser necesario — si hace falta tipearlo, es señal de que el orquestador no lo arrancó cuando debía.

El `ando-delegation-reminder.sh` (hook UserPromptSubmit) refuerza esto: cuando el mensaje del usuario tiene intención de implementar, le recuerda al orquestador que evalúe arrancar el flujo.

## Paso 1 — Resolver el título y derivar el slug

```bash
: "${ANDO_SPECS_DIR:?ANDO_SPECS_DIR no configurado — setealo en ~/.claude/settings.json (env) y en tu shell rc}"
test -d "$ANDO_SPECS_DIR" || { echo "ANDO_SPECS_DIR apunta a un dir inexistente: $ANDO_SPECS_DIR"; exit 1; }
```

Determinar el identificador con esta precedencia:

1. **El usuario pasó un `TICKET-ID`** (`^[A-Z]+-[0-9]+$`, ej. `SITE-1234`) → usarlo tal cual como `id`. Guardar el tracker.
2. **El usuario pasó un título o frase** (ej. `"rate limiting en el login"`) → derivar un **slug kebab minúscula**: bajar a minúsculas, sacar acentos, reemplazar no-alfanumérico por `-`, colapsar `-` repetidos, recortar a ~40 chars y 3-5 palabras significativas → `rate-limit-login`.
3. **El usuario no pasó nada** (o el orquestador arrancó el flujo por criterio propio) → **el orquestador propone un slug** a partir de la tarea que se está pidiendo en la conversación, y lo muestra para confirmar:
   > Voy a registrar la spec como **`rate-limit-login`** (`H:\specs\rate-limit-login.md`). ¿Va, o preferís otro nombre?

   Aceptar el que confirme el usuario; si edita, usar el suyo (pasándolo por la misma normalización a kebab).

**Validar el `id` final antes de interpolarlo en cualquier comando** — solo `[a-z0-9._-]` para slug, o `[A-Z0-9-]` para ticket. Guardarlo en `$id`. Si el usuario lo dio como texto libre, nunca usar el texto crudo en shell — usar siempre `$id` ya normalizado.

## Paso 2 — Chequear si ya existe

```bash
SPEC="$ANDO_SPECS_DIR/$id.md"
[ -f "$SPEC" ] && awk '/^---[[:space:]]*$/{c++;next} c==1 && /^status:/{print}' "$SPEC"
```

- Existe con `status: draft` → mostrarla y ofrecer continuar desde el Paso 4, sin re-draftear.
- Existe con `status: approved` o `done` → avisar que ya está y **no** sobrescribir. Terminar acá.
- No existe → Paso 3.

## Paso 3 — Draftear con spec-writer

Delegar al agente **`spec-writer`** (Agent tool), pasándole:
- La tarea tal como la pidió el usuario (+ el `tracker` si lo hay).
- El repo path donde se implementa (preguntar si no es obvio del cwd).
- Instrucción de **guardar el documento en `$ANDO_SPECS_DIR/<id>.md`** además de devolverlo completo.

Cuando termine, el orquestador (no el agente) asegura el frontmatter al tope del archivo:

```yaml
---
id: rate-limit-login
status: draft
created_at: <YYYY-MM-DD>
repo: <path o nombre del repo>
tracker: <URL o ID externo — omitir esta línea si no hay>
---
```

(el resto del archivo es el cuerpo de la spec de `spec-writer`).

## Paso 4 — Mostrar y pedir aprobación

Mostrar la spec **completa** (no un resumen). Señalar explícitamente las **preguntas abiertas** (no se puede aprobar con preguntas abiertas sin resolver) y el **fuera de scope**.

Preguntar: *¿la aprobás como está, querés cambios, o hay preguntas abiertas para resolver primero?*

- **Cambios** → aplicarlos (vos o re-delegando a `spec-writer`) y volver a mostrar. Sigue en `draft`.
- **Preguntas abiertas sin resolver** → dejar en `draft`, listar qué falta decidir. No aprobar.
- **Aprobada** → Paso 5.

## Paso 5 — Marcar aprobada

Con `Edit` sobre `$ANDO_SPECS_DIR/<id>.md`:

```
status: draft  →  status: approved
```

Agregar `approved_at: <YYYY-MM-DD>` bajo `status`.

## Paso 6 — Próximos pasos

El orquestador sigue solo con el flujo (no hace falta que el usuario pida cada paso):

```
✅ Spec aprobada: $ANDO_SPECS_DIR/<id>.md (status: approved)

El orquestador continúa:
  1. git checkout -b feature/<id>
  2. Implementar según la spec (delegando; test-strategist para el plan de tests si aplica)
  3. rdd-review sobre el branch antes de crear el PR
  4. spec-delta-apply <id>   (si hay <id>.delta.md)
  5. Crear el PR → sdd-archive <id>   (marca la spec 'done')

El gate SDD dejará pasar 'git push' de feature/<id> porque la spec está approved.
```

**No** crear el branch ni escribir código en este skill — eso es el paso siguiente.

## Lo que este skill NO hace

- No crea branch ni commitea.
- No implementa nada.
- No aprueba una spec con preguntas abiertas pendientes.
- No sobrescribe una spec ya `approved` o `done`.
- No exige un ticket ni un tracker — el slug del título alcanza.
