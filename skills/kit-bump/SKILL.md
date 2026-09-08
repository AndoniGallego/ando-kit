---
name: kit-bump
description: Bump de versión del ando-kit — determina patch/minor/major según los cambios, actualiza el archivo VERSION, hace commit y crea el tag git. Usar antes de mergear a main cuando hay cambios que merecen una nueva versión.
---

Sos el administrador de versiones del ando-kit. Tu tarea es determinar el tipo de bump correcto, actualizar `VERSION`, commitear y taggear.

## Reglas de versionado (semver)

| Tipo | Cuándo | Ejemplo |
|------|--------|---------|
| **patch** | Corrección de bugs en skills/agents/hooks/install sin nueva funcionalidad | 1.3.0 → 1.3.1 |
| **minor** | Nuevo skill, nuevo agent, nueva feature en install | 1.3.0 → 1.4.0 |
| **major** | Cambio que rompe compatibilidad (ej: restructura de carpetas, cambio de API pública) | 1.3.0 → 2.0.0 |

## Paso 1 — Leer versión actual

```bash
cat VERSION
# → 1.3.0
```

Si el kit todavía no tiene un archivo `VERSION`, crear uno empezando en `0.1.0` en vez de fallar.

## Paso 2 — Determinar tipo de bump

Revisar qué cambió desde el último tag:

```bash
git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline
git diff $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --stat
```

Aplicar la tabla de arriba. Si el usuario especificó el tipo explícitamente, usarlo sin preguntar.

## Paso 3 — Calcular nueva versión

```bash
CURRENT=$(cat VERSION)
MAJOR=$(echo $CURRENT | cut -d. -f1)
MINOR=$(echo $CURRENT | cut -d. -f2)
PATCH=$(echo $CURRENT | cut -d. -f3)

# patch:
NEW="${MAJOR}.${MINOR}.$((PATCH + 1))"

# minor:
NEW="${MAJOR}.$((MINOR + 1)).0"

# major:
NEW="$((MAJOR + 1)).0.0"
```

## Paso 3.5 — Actualizar CHANGELOG.md

Delegar al agente `changelog-writer` via Agent tool con este input:
- Repo path: el directorio del kit (`ANDO_KIT_DIR`)
- Tag destino: `v$NEW`

El agente devuelve el bloque `## [X.Y.Z] — YYYY-MM-DD` agrupado por tipo. Insertarlo en
`CHANGELOG.md` como la entrada más nueva — arriba de la última `## [x.y.z]`, debajo del
encabezado del archivo. Si el kit todavía no tiene `CHANGELOG.md`, crearlo con ese formato
(Keep a Changelog). No leer el git log completo en el contexto principal — para eso existe el agente.

Si el agente no devolvió un bloque o `CHANGELOG.md` no cambió después de la edición,
**no agregar `CHANGELOG.md` al stage** e informar al usuario antes de continuar.

## Paso 4 — Actualizar VERSION y commitear

```bash
echo "$NEW" > VERSION
git add VERSION CHANGELOG.md
git commit -m "chore: bump version $CURRENT → $NEW"
```

## Paso 5 — Crear tag

```bash
git tag "v$NEW"
```

## Paso 6 — Confirmar antes de pushear

Mostrar al usuario:
- Versión anterior y nueva
- Commits incluidos en este release (desde el tag anterior)
- La entrada nueva del CHANGELOG.md
- Comando que se va a ejecutar: `git push && git push origin v$NEW`

Esperar confirmación explícita ("sí", "hacelo", "push") antes de pushear.

## Paso 7 — Push (solo si el usuario confirma)

```bash
git push && git push origin "v$NEW"
```

## Formato de salida al usuario

```
Versión actual: 1.3.0
Tipo de bump:   minor (nuevo skill hotfix-flow)
Nueva versión:  1.4.0

Commits incluidos:
  3ee087b feat: agregar skill hotfix-flow

¿Confirmás push de v1.4.0? [sí/no]
```
