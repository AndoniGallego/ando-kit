---
name: rdd-review
description: Revisión de código con esfuerzo proporcional al riesgo (RDD — Receipt-Driven Development). Congela el diff, clasifica el riesgo en Bajo/Medio/Alto, y escala 0/1/4 agentes de revisión acorde. Corrección acotada a una sola ronda — nunca loop-until-clean. El resultado es informacional, nunca bloquea commit/push/PR. Invocar con "/rdd-review" o "revisá esto con RDD" sobre un branch con un diff claro contra su target, o desde un flujo mayor que quiera una revisión antes de entregar.
license: Apache-2.0
metadata:
  based-on: gentleman-programming/gentle-ai RDD (Receipt-Driven Development)
---

## Activation Contract

Invocar:
- Manualmente (`/rdd-review`, "revisá esto con RDD") para cualquier branch con un diff claro contra su target — features, hotfixes, cambios al propio kit.
- Desde un flujo mayor (un pipeline de tickets, un skill de entrega) que quiera una revisión de esfuerzo proporcional antes de crear el PR/MR.

Requiere: un branch con commits por delante de su target (`origin/<target>..HEAD`), o un diff explícito si se invoca sobre working tree sin commitear.

## Hard Rules

- **Freeze antes que nada.** Capturar el diff una sola vez al arrancar. Ningún lente vuelve a correr `git diff` por su cuenta — todos reciben el texto ya congelado en su prompt. Única excepción: el re-freeze del orquestador tras aplicar un fix (ver Paso 5, punto 3) — nunca lo hace un lente.
- **El resultado es informacional.** Nunca bloquear commit/push/PR — eso lo deciden el agente `deploy-checker` y el hook de pre-push, sin cambios. Un flujo caller puede pausar su propia progresión ante un `ESCALATED` — eso es orquestación del caller, no un gate que RDD imponga.
- **Corrección acotada a una ronda.** Si falla el validador después de esa ronda → `Escalated`. No hay ronda 2.
- **Receipt obligatorio.** `mem_save` en Engram con candidate + tier + resultado antes de dar la revisión por cerrada — incluso si el tier fue Bajo (0 lentes).
- Si `rdd-review` no puede correr (no hay diff, o no hay target claro) → terminar en `RDD: NOT_RUN` con el motivo (ver Output Contract), sin bloquear el resto del flujo.

## Paso 1 — FREEZE: congelar el candidate

Determinar el target (branch principal del repo — `git remote show origin | sed -n 's/.*HEAD branch: //p'`, o `git rev-parse --abbrev-ref origin/HEAD`) y capturar el diff una sola vez:

```bash
git diff origin/<target>...HEAD > /tmp/rdd-candidate-$(date +%s).diff
```

Si se invoca sobre working tree sin commitear (revisión previa a un commit), usar `git diff` (o `git diff --cached` si se pide explícitamente "solo lo stageado") — mismo criterio de captura única.

Este archivo es el **candidate**: la única fuente que van a leer los lentes. Ninguna instrucción posterior de este skill vuelve a invocar `git diff` — todo lo que sigue trabaja sobre el contenido ya capturado. Única excepción: el re-freeze del orquestador tras aplicar un fix (Paso 5, punto 3).

## Paso 2 — RISK: clasificar el candidate

Leer el candidate congelado (paths tocados + un vistazo al contenido) y clasificar:

| Tier | Criterio |
|---|---|
| **Alto** | Toca dinero (pagos, cobros, reembolsos, saldos), auth/SSO/permisos, migraciones de datos o backfills, control de concurrencia (locks, reservas, operaciones atómicas), enforcement de seguridad (CSP, sanitización, secretos), un hotfix a prod sin tests, o cruza boundaries entre módulos/servicios |
| **Medio** | Lógica de negocio nueva/modificada que no cae en Alto |
| **Bajo** | Solo docs, comentarios, config, bump de versión, o rename/format sin cambio de lógica |

Esta clasificación la hace el orquestador leyendo el candidate — no se delega, es una decisión barata y determinística la mayoría de las veces. Si el candidate mezcla señales de distintos tiers, usar el tier más alto de los presentes.

## Paso 3 — ROUTE: elegir cuántos y cuáles lentes

Los 4 lentes (framework "4R"), con el agente sugerido de este kit. Si un agente no existe en el entorno, usar un `general-purpose` con el prompt de foco correspondiente.

| Lente (4R) | Agente | Foco del prompt |
|---|---|---|
| **Risk** | `security-auditor` | seguridad, dinero, exposición de datos, auth, broken access control, injection |
| **Resilience** | `general-purpose` con foco | error handling, rollback, concurrencia, fallas parciales, consistencia |
| **Readability** | `general-purpose` con foco — o `frontend-reviewer` si el diff dominante es de UI (`.vue`/`.jsx`/`.tsx`/`.svelte`/estilos) | naming, complejidad, convenciones del repo, comentarios innecesarios |
| **Reliability** | `pr-analyst` | correctness a nivel diff completo, cobertura de test, regresiones |

**Bajo → 0 lentes.** Structural readback: confirmar en una línea que el candidate es realmente docs/config-only. No delegar nada. Ir directo al Paso 6 (RECEIPT) con outcome `approved`.

**Medio → 1 lente**, elegido por la señal dominante:

| Señal dominante en el candidate | Lente elegido |
|---|---|
| Validación de input, permisos/ownership fuera del core de auth, escaping de output | Risk |
| Máquina de estados, transacciones, manejo de errores/excepciones | Resilience |
| Refactor puro, sin cambio de comportamiento | Readability |
| Feature/fix nuevo sin ninguna señal anterior | Reliability (default) |

Si el candidate matchea más de una fila, usar la primera (de arriba hacia abajo) que aplique.

**Alto → 4 lentes en paralelo.** Despachar los 4 agentes con la tool `Agent`, todos en el mismo mensaje (mismo turno) — mismo patrón que `judgment-day` lanza 2 jueces, extendido a 4.

Prompt base para cada lente (reemplazar `{FOCO}` por la columna "Foco del prompt", `{CANDIDATE}` por el texto congelado del Paso 1):

```
Sos un revisor de código. Detectá el lenguaje/framework del diff y aplicá sus convenciones.
Tu revisión tiene un único foco — no evalúes nada fuera de esto:

FOCO: {FOCO}

CANDIDATE (diff congelado, no vuelvas a correr git diff):
{CANDIDATE}

Formato de cada finding:
- Severidad: CRITICAL | WARNING (real) | WARNING (teórico) | SUGGESTION
- Archivo: path/archivo (línea N si aplica)
- Descripción: qué está mal, por qué importa, si es causado por este candidate o pre-existente
- Fix sugerido: una línea de intención

Si no hay issues dentro de tu foco: VERDICT: CLEAN.
```

## Paso 4 — SYNTHESIZE: clasificar los findings

Cuando todos los lentes despachados completen (si fue tier Alto, esperar los 4 antes de sintetizar — nunca aceptar veredicto parcial), clasificar cada finding:

| Bucket | Criterio |
|--------|---------|
| **Confirmed** | El mismo issue lo señaló más de un lente (solo posible en tier Alto, con 4 lentes) |
| **Suspect** | Solo un lente lo encontró |
| **Contradiction** | Dos lentes toman posiciones opuestas sobre el mismo punto |
| **Pre-existente** | El finding no lo causa este candidate — anotar como follow-up, no bloquea nada |

En tier Medio (1 solo lente) no hay Confirmed/Contradiction posibles — todo lo que reporte ese lente entra directo como candidato a corrección si es severo (CRITICAL o WARNING real) y causado por el candidate.

## Paso 5 — CORRECT: una sola ronda acotada

Si hay findings **severos** (CRITICAL o WARNING real) **causados por el candidate** (no pre-existentes):

Las Contradictions severas del Paso 4 NO entran a esta ronda de corrección — van directo al Paso 6b (ESCALATE) con `outcome: escalated` asignado explícitamente ahí mismo, sin gastar la única ronda de fix, porque no tiene sentido "corregir" algo cuya validez está en disputa entre los propios lentes. Solo Confirmed/Suspect severos alimentan la lista de abajo.

1. Mostrar la lista de findings severos al usuario y pedir OK antes de fixear — mismo criterio que `judgment-day` Paso 5.
2. Con el OK, despachar **un** agente implementador (Agent tool) acotado a esos findings exactos:

```
Sos un agente de fix quirúrgico.
Aplicá SOLO los findings severos listados abajo. No refactorices más allá del fix requerido.
No cambies código no señalado, ni agregues comentarios explicativos.

FINDINGS A FIXEAR:
[lista de Confirmed/Suspect severos del Paso 4]

Antes de commitear: si el repo tiene una suite de tests (npm test, pytest, go test,
composer test, cargo test, etc.), corréla y PARÁ si falla — no commitees un fix que
rompe tests existentes. Reportá el fallo en vez de forzar el commit.

Con los tests en verde, COMMITEALO (no lo dejes en working tree ni staged) — el
validador del Paso 5 compara commits, un fix sin commitear queda invisible para esa
comparación. Conventional Commit (`fix: ...`).

Reportá: archivo, línea, descripción del fix aplicado, el comando de test corrido y
su resultado, y el hash del commit.
```

   Modelo: `haiku` si son 1-2 archivos con fix mecánico, `sonnet` si es multi-archivo o el fix requiere entender lógica de negocio.

3. **Única excepción permitida al freeze del Paso 1:** con el fix ya commiteado, verificar el reporte del agente antes de confiar en él:
   - El hash reportado coincide con `git rev-parse HEAD` (si no coincide, no continuar sin resolver la discrepancia).
   - `git status --porcelain -- <paths de los findings fixeados>` no devuelve nada (sin cambios sueltos en working tree o staged sobre esos paths).

   Con ambas verificaciones en verde, el orquestador (no los lentes) re-captura el candidate una vez, con el mismo comando `git diff origin/<target>...HEAD` del Paso 1, ahora sobre el HEAD ya corregido.
4. **Un** validador read-only: re-correr TODOS los lentes que fueron despachados originalmente en el Paso 3 (no solo el que encontró el problema). En tier Medio esto es 1 lente; en tier Alto son los 4. Mismo prompt del Paso 3, mismo FOCO cada uno, sobre el diff recapturado.
5. Si el validador confirma que los findings severos ya no están → outcome `approved`.
6. Si el validador sigue encontrando el mismo problema (o uno nuevo severo introducido por el fix) → outcome `escalated`. No hay ronda 2 — ir directo al Paso 6b.

Si no hay findings severos causados por el candidate (todo CLEAN, o solo pre-existentes/teóricos/suggestions): outcome `approved` directo, sin correr este paso.

## Paso 6 — RECEIPT: guardar la evidencia

Antes de dar la revisión por cerrada — **siempre**, incluso en tier Bajo con 0 lentes — `mem_save` en Engram:

```
title: "RDD review — <branch o descripción corta>"
type: "decision"
content:
  **What**: RDD review del candidate <branch>@<commit corto>. Tier: <Bajo|Medio|Alto>. Lentes corridos: <lista o "ninguno (structural readback)">. Outcome: <approved|escalated>.
  **Why**: Revisión previa a PR/delivery.
  **Where**: <paths tocados por el candidate>
  **Learned**: <findings severos encontrados y su resolución, si los hubo; o "sin findings severos" si CLEAN>
```

Esto es el "recibo": sobrevive a un `/clear` o pérdida de contexto, y deja rastro de qué se revisó y con qué criterio.

## Paso 6b — ESCALATE: solo si el validador falló

Dispara únicamente en dos casos: el Paso 5 terminó en outcome `escalated`, o el Paso 4 encontró una Contradicción severa que fue directo acá. No es discreción libre del orquestador en ningún otro momento.

| Situación en `Escalated` | Qué sumar |
|---|---|
| Los lentes (tier Alto) dieron hallazgos contradictorios entre sí sobre el mismo punto | `judgment-day` — segunda opinión ciega e independiente sobre el mismo target |
| Hay una decisión puntual y bien acotada en disputa (ej. "¿este rollback es correcto o no?") | `doubt-driven` — iteración enfocada sobre esa decisión específica, con el finding en disputa como CONTRATO |
| Ninguna de las dos aplica claramente | Reportar el `Escalated` al usuario tal cual, sin sumar nada más |

Invocar como máximo una de las dos por escalación. Cuando esa escalación termine, emitir un **segundo** `mem_save` que referencie el candidate/branch del receipt del Paso 6 y agregue qué escalación se sumó y con qué resultado — no se edita el receipt ya guardado.

## Output Contract

Siempre retornar `## RDD Review — {candidate}` con:
- Tier asignado y por qué
- Lentes corridos (o "0 — structural readback")
- Tabla de findings (si hubo alguno)
- Corrección aplicada (si aplica, con agente y modelo usados)
- Resultado del validador (si aplica)
- Confirmación del `mem_save` (receipt)
- Estado final: `RDD: APPROVED ✅ (informational)`, `RDD: ESCALATED ⚠️`, o `RDD: NOT_RUN ⏭ (<motivo>)`

**Recordatorio:** `APPROVED`/`ESCALATED` es informacional. No reemplaza al pre-push hook ni a `deploy-checker` — el commit/push/PR sigue su curso normal independientemente del resultado.
