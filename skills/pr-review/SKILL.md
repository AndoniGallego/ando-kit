---
name: pr-review
description: Revisión técnica de Pull/Merge Requests en GitHub o GitLab (detecta y usa gh o glab según cuál esté disponible). Solo lectura — nunca crea, edita, mergea, cierra ni comenta en PRs/repos salvo pedido explícito aparte. Trae el diff completo, identifica bugs reales, riesgos de seguridad obvios y calidad de la división en commits, y devuelve un reporte estructurado de críticos vs. mejoras opcionales.
---

# pr-review

## Regla dura — solo lectura

Este skill **nunca** ejecuta acciones que modifiquen estado remoto: no crear PRs/MRs, no comentar, no aprobar, no mergear, no cerrar, no pushear. Si el usuario quiere alguna de esas acciones, debe pedirlo explícitamente como un paso separado, después de ver el reporte. Ante la duda, no ejecutar el comando de escritura.

## Paso 1 — Detectar la plataforma y el CLI disponible

```bash
command -v gh >/dev/null 2>&1 && echo "gh disponible"
command -v glab >/dev/null 2>&1 && echo "glab disponible"
```

Si el repo remoto es de GitHub, usar `gh`. Si es de GitLab, usar `glab`. Si ambos CLIs están instalados, decidir por la URL del remoto (`git remote -v`). Si no hay CLI disponible para la plataforma correspondiente, avisar al usuario en vez de intentar workarounds con curl a la API sin autenticación.

## Paso 2 — Traer el diff completo y metadata

GitHub:
```bash
gh pr view <numero> --json title,body,author,commits,files
gh pr diff <numero>
```

GitLab:
```bash
glab mr view <numero>
glab mr diff <numero>
```

Siempre traer el diff completo, no solo los nombres de archivo — los bugs reales están en el contenido, no en la lista de paths tocados. Si el diff es muy largo (varios miles de líneas), leerlo por archivo priorizando los que tienen lógica de negocio, auth, manejo de dinero o inputs externos por sobre los que son solo config, lockfiles o assets generados.

## Paso 3 — Identificar bugs reales (no solo estilo)

Priorizar por impacto, en este orden:

1. **Lógica incorrecta**: condiciones invertidas, off-by-one, casos límite no manejados (lista vacía, null, cero, string vacío), comparaciones con el tipo equivocado, race conditions en código concurrente/async.
2. **Manejo de errores**: excepciones tragadas silenciosamente, recursos no liberados (conexiones, file handles, locks), falta de rollback en operaciones que deberían ser atómicas.
3. **Contratos rotos**: la función cambia de comportamiento pero los callers existentes no fueron actualizados; un tipo de retorno o firma cambia de forma incompatible.
4. **Estilo y naming**: siempre al final, y solo si hay espacio en el reporte — nunca mezclado entre los hallazgos críticos.

## Paso 4 — Riesgos de seguridad obvios

Buscar explícitamente, sin necesidad de que el PR lo mencione:

- **Secrets hardcodeados**: API keys, tokens, contraseñas, connection strings pegados en el código en vez de leídos de config/env.
- **Inyección**: concatenación de input de usuario en queries SQL, comandos de shell, o construcción de HTML/JS sin escapar (XSS).
- **Falta de validación de input**: datos que llegan de request/params/body y se usan directamente sin chequear tipo, rango o formato antes de una operación sensible (escritura a DB, llamada a otro servicio, acceso a filesystem).
- **Autorización faltante**: un endpoint o acción nueva que no verifica que el usuario tiene permiso sobre el recurso que está tocando (ej. acceder a un recurso por ID sin validar ownership).

No es necesario un audit de seguridad exhaustivo — el objetivo es atrapar lo obvio que un reviewer humano atento vería, no reemplazar una herramienta de SAST.

## Paso 5 — Evaluar la división en commits

- ¿Cada commit es una unidad lógica coherente, o hay un commit gigante que mezcla varias cosas no relacionadas?
- ¿Hay commits tipo "fix typo" o "wip" que deberían haberse squasheado antes de abrir el PR?
- ¿El mensaje de cada commit explica el *por qué*, o solo repite el *qué* que ya se ve en el diff?
- Si el PR es grande (por ejemplo 500+ líneas de cambio no generado), señalar si hubiera sido razonable dividirlo en PRs más chicos y revisables por separado.

## Paso 6 — Reporte estructurado

Siempre devolver el reporte en este formato, sin mezclar categorías:

```
## Resumen
<1-2 líneas: qué hace el PR y si en términos generales está en buen estado>

## Hallazgos críticos
- [archivo:línea] Descripción del bug/riesgo y por qué importa
- ...
(si no hay ninguno: "Ninguno detectado")

## Riesgos de seguridad
- [archivo:línea] Descripción y por qué es explotable/riesgoso
(si no hay ninguno: "Ninguno detectado")

## Mejoras opcionales
- [archivo:línea] Sugerencia de estilo, naming, simplificación
- ...

## Commits
<Comentario breve sobre la división en commits y mensajes>

## Veredicto
<Aprobable tal cual / Aprobable con comentarios menores / Necesita cambios antes de mergear>
```

Los hallazgos críticos y los riesgos de seguridad van siempre separados de las mejoras opcionales — nunca en una sola lista plana. El usuario debe poder decidir en 10 segundos si el PR es mergeable o no con solo mirar esas dos secciones.
