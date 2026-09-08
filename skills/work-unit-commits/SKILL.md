---
name: work-unit-commits
description: Planifica commits como unidades de trabajo revisables antes de implementar un feature multi-archivo — cada commit compila, tiene un propósito único descriptible en una línea, y el conjunto cuenta una historia legible para el reviewer. Usar al planear un feature de varios pasos o antes de preparar una serie de commits para un PR/MR, en vez de acumular todo en un commit gigante al final.
---

# Work Unit Commits

## Por qué existe este skill

Un commit gigante al final de un feature ("implement feature X", 40 archivos cambiados) es prácticamente imposible de revisar en serio — el reviewer termina aprobando por cansancio, no por haber entendido cada cambio. Además, un commit gigante es una unidad de rollback atómica: si algo falla, no hay forma de revertir solo la parte problemática. Planificar los commits **antes** de escribir el código (no reordenar al final con `git rebase -i` como parche) obliga a pensar la implementación misma como una secuencia de pasos coherentes, lo cual mejora también el diseño.

## Cuándo usar este skill

- Antes de arrancar a implementar cualquier feature que toque más de 2-3 archivos o que tenga más de un paso lógico.
- Antes de preparar una serie de commits para un PR/MR, si el trabajo ya se hizo de forma desordenada y hay que reorganizarlo.
- Cuando un feature mezcla naturalmente varios tipos de cambio (ej. refactor + feature nueva, o migración + código que la usa) — la tentación de mezclarlo todo en un commit es máxima justo en estos casos.

## Paso 1 — Descomponer el feature en unidades de trabajo, no en archivos

Antes de tocar código, listar los pasos lógicos del feature completo. Una unidad de trabajo no es "los cambios en el archivo X" — es un paso coherente del problema que se está resolviendo. Ejemplos de buena descomposición:

1. Agregar el modelo/entidad nueva (sin usarla todavía).
2. Agregar la capa de acceso a datos para esa entidad.
3. Agregar la lógica de negocio que la usa.
4. Exponer el endpoint/comando que dispara esa lógica.
5. Actualizar la UI/CLI que consume el endpoint.

Cada unidad puede tocar uno o varios archivos — lo que importa es que tenga un propósito único y coherente, no que respete límites de archivo.

## Paso 2 — Verificar que cada unidad cumple las tres propiedades

Para cada unidad de trabajo planificada, confirmar:

1. **Compila / pasa el linter por sí sola.** Si alguien hace checkout de ese commit exacto, el proyecto debe construir sin errores de sintaxis o de imports rotos — aunque la feature todavía no esté completa end-to-end.
2. **Tiene un propósito único, describible en una línea de imperativo.** Si al escribir el mensaje de commit hace falta un "y también" o una lista con viñetas para describir qué hace, probablemente son dos unidades, no una.
3. **Es revisable de forma aislada.** Un reviewer humano debería poder entender el cambio mirando solo ese diff más el mensaje de commit, sin necesitar leer los commits siguientes para que tenga sentido (aunque el comportamiento completo del feature sí dependa de la secuencia completa).

Si una unidad no cumple alguna de las tres, partirla o fusionarla con la adyacente hasta que las cumpla.

## Paso 3 — Ordenar las unidades de forma que cada una deje el repo en estado consistente

El orden importa tanto como la descomposición:

- Las unidades de base (modelos, tipos, utilidades) van antes que las que las consumen.
- Si es posible, el código muerto o no invocado que se agrega en un paso intermedio debe estar claramente marcado como "todavía no conectado" (o cubierto por tests propios), no dejarlo ambiguo.
- Los cambios de infraestructura/config que un paso necesita (migraciones, flags, dependencias nuevas) van en su propio commit, antes del código que los usa.
- Si algún paso deja el sistema en un estado intencionalmente incompleto pero no roto (ej. una función nueva sin caller todavía), es válido — lo que no es válido es un estado que no compila o que rompe tests existentes.

## Paso 4 — Ejecutar la implementación commit por commit, no todo y después separar

Implementar y commitear cada unidad en el momento, siguiendo el plan del paso 1-3, en vez de escribir todo el feature de corrido y tratar de separarlo en retrospectiva con `git add -p`. Separar en retrospectiva es más lento, más propenso a errores (mezclar líneas que no debían ir juntas) y tienta a rendirse y hacer un commit grande "total ya está todo escrito".

Si en el medio de la implementación aparece la necesidad de un paso no planificado (ej. un fix a algo que se rompió), evaluar: ¿es parte de la unidad actual, o merece su propio commit atómico? Regla general: un fix a algo introducido en el mismo trabajo va en el commit que lo introdujo (si no se pusheó todavía) o en un commit `fix:` propio (si ya se pusheó).

## Paso 5 — Revisar la secuencia completa antes de abrir el PR/MR

Antes de pushear, correr `git log --oneline <base>..HEAD` y leer la secuencia de mensajes como si fuera un extraño: ¿cuenta una historia coherente? ¿cada mensaje describe con precisión lo que su diff hace? ¿hay algún commit que en realidad debería fusionarse con otro, o partirse en dos?

Este es el momento de usar `git rebase -i` para ajustes menores de orden o squash — pero como pulido final de un plan ya bueno, no como sustituto de haber planificado la descomposición desde el principio.
