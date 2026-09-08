---
name: investigar-bug
description: Guía un flujo sistemático de investigación de bugs — reproducir el síntoma, revisar historial relevante, formular hipótesis falsables, verificarlas con evidencia y recién entonces proponer un fix. Usar ante cualquier bug o comportamiento inesperado, antes de tocar código o proponer una solución. Agnóstico de stack o lenguaje.
---

# Investigar Bug

## Por qué existe este skill

El error más caro en debugging no es tardar más — es "arreglar" algo que no era la causa real. Ese fix falso da una falsa sensación de resolución, deja el bug real latente, y a veces introduce un problema nuevo. Este skill fuerza una secuencia: **entender antes de hipotetizar, hipotetizar antes de verificar, verificar antes de arreglar.**

**Regla dura: no proponer ni implementar un fix hasta haber confirmado la causa raíz con evidencia concreta (log, output de test, print, stack trace, dato en base de datos, etc.). "Creo que es esto" no es suficiente para tocar código de producción.**

## Paso 1 — Reproducir y describir el síntoma exacto

Antes de mirar código, dejar por escrito (aunque sea en la respuesta al usuario, no hace falta un archivo):

- ¿Cuál es el comportamiento observado, literal? (mensaje de error completo, screenshot, valor incorrecto, etc.)
- ¿Cuál es el comportamiento esperado?
- ¿Es reproducible de forma determinística, o es intermitente?
- ¿Bajo qué condiciones aparece? (input específico, entorno, carga, timing, usuario, browser)
- ¿Desde cuándo pasa? ¿Siempre pasó o es una regresión?

Si no se puede reproducir de forma confiable, ese es el primer objetivo: encontrar los pasos mínimos que lo disparan. Un bug que no se puede reproducir no se puede verificar como resuelto.

No avanzar al paso 2 sin poder responder estas preguntas con precisión. "Falla a veces" no alcanza — hay que acotar cuándo.

## Paso 2 — Revisar historial reciente del área afectada

Antes de leer el código como si fuera nuevo, revisar qué cambió recientemente en los archivos/módulos involucrados:

- `git log --oneline -- <archivo/carpeta>` para ver commits recientes en la zona.
- `git blame` sobre las líneas sospechosas para identificar cuándo y por qué se escribieron así.
- Si hay un changelog, tickets o PRs vinculados, revisarlos — puede que el bug sea un efecto secundario documentado o no de un cambio intencional.
- Si el bug es una regresión, `git bisect` (o revisión manual del rango de commits) entre la última versión buena y la primera mala acota drásticamente el espacio de búsqueda.

Este paso suele ahorrar horas: muchos bugs son la consecuencia directa y reciente de un cambio identificable, no un misterio profundo del sistema.

## Paso 3 — Formular 2-3 hipótesis concretas y falsables

Una hipótesis útil es específica y se puede refutar con un experimento concreto. Ejemplos de buena vs. mala hipótesis:

- Mala: "algo está mal con el estado" (no es falsable, no dice qué observar).
- Buena: "la variable `X` llega `null` porque el callback `Y` se ejecuta antes de que `Z` complete — se puede verificar logueando `X` justo antes del uso."

Para cada hipótesis, anotar:
1. Qué predice exactamente si es cierta.
2. Qué evidencia la confirmaría.
3. Qué evidencia la refutaría.
4. Cómo se obtiene esa evidencia (log puntual, test aislado, inspección de datos, debugger, print).

Priorizar las hipótesis por probabilidad y por costo de verificación — empezar por la más barata de descartar.

## Paso 4 — Verificar cada hipótesis con evidencia real

No usar razonamiento como sustituto de evidencia. Para cada hipótesis, ejecutar el experimento mínimo que la confirme o refute:

- Agregar logs/prints temporales en los puntos exactos indicados por la hipótesis.
- Escribir un test aislado que reproduzca la condición sospechada.
- Inspeccionar el estado real (base de datos, response de API, valor de variable) en el momento del fallo.
- Si la evidencia no confirma la hipótesis, descartarla explícitamente y pasar a la siguiente — no forzar una interpretación que la salve.

Iterar hasta tener una hipótesis confirmada con evidencia reproducible, no solo plausible. Si las 2-3 hipótesis iniciales se descartan, volver al paso 1 o 2: probablemente falta información sobre el síntoma o el historial.

Limpiar cualquier log/print temporal agregado durante la investigación antes de pasar al fix, salvo que decida mantenerse como logging permanente (en ese caso, decirlo explícitamente).

## Paso 5 — Proponer el fix, con la evidencia que lo respalda

Recién acá se propone la solución. El fix debe:

- Atacar la causa raíz confirmada, no el síntoma.
- Venir acompañado de la evidencia concreta que demuestra la causa (referenciar el log/test/output del paso 4).
- Incluir cómo se va a verificar que el fix realmente resuelve el problema (idealmente un test que falle antes del fix y pase después).
- Mencionar si el fix tiene efectos colaterales conocidos o zonas de riesgo relacionadas.

Si en algún punto se siente la tentación de "probar a cambiar esto a ver si arregla" sin haber confirmado por qué — es una señal de que se está saltando el proceso. Volver al paso 3.

## Atajos que cuestan caro

| Atajo | Por qué falla |
|-------|---------------|
| Empezar a escribir el fix antes del paso 5 | Ataca el síntoma sin entender la causa; el fix suele ser incorrecto o incompleto |
| "Ya sé qué es, me salteo la hipótesis" | Sin hipótesis escrita no hay forma de verificarla ni de que otro la valide antes de implementar |
| Leer el módulo entero en vez del flujo del bug | Consume tiempo y contexto sin propósito; seguir el camino exacto entrada→proceso→salida es mucho más eficiente |
| Verificar directamente en producción | Crea side effects y expone datos; verificar en local o con datos de test |
| Asumir que el bug es nuevo porque no hay commits recientes | Puede ser latente, disparado por un cambio de datos o de config — el historial de datos importa tanto como el de código |
| Descartar una hipótesis refutada "salvándola" con una interpretación forzada | Si la evidencia la refuta, se descarta y se pasa a la siguiente — no se la rescata |

## Mapa síntoma → hipótesis prioritaria (genérico)

| Síntoma observable | Hipótesis a investigar primero |
|-------------------|-------------------------------|
| Falla solo en prod, anda en local | Config, env var, feature flag o cron activo en prod que no está en local |
| Intermitente bajo carga | Race condition, lock contention, timeout o pool de conexiones agotado |
| Regresión después de un deploy reciente | Diff del lockfile de dependencias — alguna dep rompió compatibilidad; probar revertir el bump |
| Solo para ciertos usuarios | Un atributo del usuario (plan, segmento, país, estado) que activa un code path distinto |
| Solo a ciertas horas | Job programado o tarea batch que altera estado antes del flujo |
| Error 500 sin detalle en la respuesta | Ir a los logs del servidor/worker en el momento exacto del fallo — el stack trace real casi siempre está ahí |
| El front no renderiza / componente no monta | Error JS temprano, recurso bloqueado (CSP/CORS), o token/sesión expirada — mirar la consola del browser y la pestaña Network |
