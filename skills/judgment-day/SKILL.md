---
name: judgment-day
description: Revisión dual ciega — lanza dos jueces independientes en paralelo sobre el mismo target (código, feature, PR, arquitectura), sin que uno vea el veredicto del otro. Sintetiza hallazgos en confirmed/suspect/contradiction y re-juzga tras aplicar fixes hasta llegar a APPROVED o quedar ESCALATED. Trigger: "/judgment-day", "/jd", "juzgalo", "revisión dual", o como escalación de rdd-review ante lentes contradictorios.
license: Apache-2.0
metadata:
  based-on: gentleman-programming/gentle-ai judgment-day
---

# Judgment Day

## Por qué existe este skill

Un solo revisor, aunque sea adversarial (ver skill `doubt-driven`), tiene sus propios puntos ciegos — un estilo de búsqueda que sistemáticamente pasa por alto cierta clase de problemas. **Dos revisores independientes, sin comunicación entre ellos, que llegan al mismo hallazgo por caminos distintos** es una señal mucho más fuerte que cualquiera de los dos por separado. Y cuando discrepan, la discrepancia misma es información: señala una zona ambigua o de alto riesgo que merece atención humana.

## Activation Contract

Invocar cuando el usuario pide explícitamente: `judgment day`, `/jd`, `juzgar`, `juzgalo`, `revisión dual`, `dual review`, `adversarial review`.

O automáticamente como escalación de `rdd-review` (ver su Paso 6b): cuando esa skill llega a `Escalated` y los lentes dieron hallazgos contradictorios entre sí. Ese es el único trigger no-manual permitido.

## Hard Rules

- Lanzar **dos jueces ciegos en paralelo** — nunca revisar el código en el contexto principal.
- Esperar ambos jueces antes de sintetizar; nunca aceptar veredicto parcial.
- Judge A y Judge B usan **agentes distintos** para garantizar perspectivas independientes.
- `WARNING (real)` = el uso normal puede triggerearlo. Si el path es contrived/malicioso/imposible, baja a `WARNING (teórico)`.
- Preguntar antes de fixear en Round 1.
- Después de cualquier ronda de fixes: re-lanzar ambos jueces antes de commit/push/done.
- Terminal states: solo `JUDGMENT: APPROVED ✅` o `JUDGMENT: ESCALATED ⚠️`.
- Después de 2 rondas de fix con issues sin resolver: preguntar al usuario si continuar.

## Paso 1 — Definir el target y el criterio de aprobación

Antes de lanzar nada, dejar explícito:

- **El target exacto**: qué archivos, PR/diff, feature o decisión de arquitectura se está juzgando. "El módulo X" no alcanza si X tiene 40 archivos y solo 5 cambiaron.
- **El criterio de aprobación**: qué constituye un veredicto APPROVED. Ej: "sin bugs de lógica críticos, sin vulnerabilidades de seguridad, contratos de API respetados."
- **El scope de la revisión**: ¿correctness? ¿seguridad? ¿performance? ¿legibilidad? Cuanto más claro el scope, más comparables los dos veredictos.

Si el target no está claro: preguntar el scope, no lanzar jueces.

## Paso 2 — Routing de jueces

Elegir dos agentes **distintos**. Si un agente sugerido no existe en el entorno, usar `general-purpose` con el prompt base de abajo.

| Target | Judge A (correctness/arquitectura) | Judge B (seguridad/edge) |
|--------|-----------------------------------|--------------------------|
| Archivos de código / módulo | `general-purpose` (foco correctness) | `security-auditor` |
| Componentes de frontend / estilos | `frontend-reviewer` | `security-auditor` |
| PR completo o branch | `pr-analyst` | `security-auditor` |
| Arquitectura / diseño de módulo | `code-architect` | `general-purpose` (foco riesgo) |

Si no matchea ninguna fila: Judge A = `general-purpose` (correctness), Judge B = `security-auditor`.

## Paso 3 — Lanzar Judge A y Judge B en paralelo, ciegos entre sí

Despachar **ambos con la tool `Agent` en el mismo mensaje** (mismo turno, para que corran en paralelo de verdad), cada uno con:

- El mismo target y el mismo criterio de aprobación del Paso 1.
- Ninguna referencia al otro juez ni a su eventual veredicto.
- El prompt base según su rol.

**Prompt base Judge A (correctness/arquitectura):**

```
Sos un revisor de código adversarial. Detectá el lenguaje/framework del target y aplicá
sus convenciones. Tu único trabajo es encontrar problemas. Asumí que el autor es demasiado confiado.

TARGET: [archivos / feature / branch]

Revisá:
- Correctness: errores lógicos, mismatches con el comportamiento esperado
- Casos límite: estados no contemplados, inputs edge-case
- Error handling: propagación, recovery, rollback, fallas parciales
- Performance: N+1, loops innecesarios, queries sin índice
- Contratos de arquitectura: capas/boundaries respetados, dependencias en la dirección correcta
[criterios custom si los hay]

Formato de cada finding:
- Severidad: CRITICAL | WARNING (real) | WARNING (teórico) | SUGGESTION
- Archivo: path/archivo (línea N si aplica)
- Descripción: qué está mal y por qué importa
- Fix sugerido: una línea de intención

WARNING rule: el uso normal puede triggerarlo → WARNING (real); path contrived/imposible → WARNING (teórico).
Si no hay issues: VERDICT: CLEAN.
```

**Prompt base Judge B (seguridad/edge-cases):**

```
Sos un auditor de seguridad adversarial. Detectá el lenguaje/framework del target.
Tu único trabajo es encontrar vulnerabilidades y edge cases de seguridad. Asumí que el autor ignoró la seguridad.

TARGET: [archivos / feature / branch]

Revisá:
- Injection: SQL/NoSQL por concatenación, command injection, template injection
- XSS / output sin escapar; deserialización insegura
- CSRF: endpoints que mutan estado sin token verificado
- Exposición de datos: campos sensibles (password, token, card) en responses o logs
- Auth boundaries: acceso a recursos sin verificar ownership/permisos
- Race conditions: operaciones no atómicas sobre estado compartido (stock, saldos, estados)
- Secretos hardcodeados, path traversal
[criterios custom si los hay]

Formato de cada finding:
- Severidad: CRITICAL | WARNING (real) | WARNING (teórico) | SUGGESTION
- Archivo: path/archivo (línea N si aplica)
- Descripción: vulnerabilidad y vector de explotación concreto
- Fix sugerido: una línea de intención

WARNING rule igual que Judge A.
Si no hay issues: VERDICT: CLEAN.
```

## Paso 4 — Sintetizar los hallazgos

Cuando ambos jueces completen, cruzar los **hallazgos puntuales** (no los veredictos generales):

| Bucket | Criterio |
|--------|---------|
| **Confirmed** | El mismo hallazgo (o uno equivalente) aparece en ambos jueces. Máxima confianza — tratar como real salvo evidencia fuerte en contra. |
| **Suspect** | Solo un juez lo marcó. Puede ser real y no cubierto por el otro, o un falso positivo. Requiere una mirada adicional antes de descartarlo, sobre todo si es crítico. No auto-fixear. |
| **Contradiction** | Los jueces toman posiciones opuestas sobre el mismo punto. Señal de ambigüedad real — no resolver por mayoría automática. |
| **INFO** | `WARNING (teórico)` o `SUGGESTION` de cualquiera. |

Presentar la síntesis de forma explícita — el valor del proceso está en ver dónde coinciden y dónde no.

## Paso 5 — Reportar y pedir autorización (Round 1)

```
## Judgment Day — {target} (Round {N})

| Finding | Judge A | Judge B | Severidad | Status |
|---------|---------|---------|-----------|--------|
| ...     | ✅/❌   | ✅/❌   | CRITICAL  | Confirmed |

Confirmed: N | Suspect: M | Contradictions: K | INFO: J

¿Autorizo aplicar fixes a los Confirmed?
```

**Antes de fixear cualquier Confirmed: pedir OK explícito.** Los Suspect críticos se investigan puntualmente (leer el código, correr el escenario) antes de decidir — no se auto-fixean. Las Contradictions no se resuelven arbitrariamente.

## Paso 6 — Fix agent (solo para Confirmed autorizados)

Despachar un agente implementador vía Agent tool. Modelo: `haiku` para fixes mecánicos (1-2 archivos, cambio aislado), `sonnet` para multi-archivo o con lógica compleja.

```
Sos un agente de fix quirúrgico.
Aplicá SOLO los issues confirmados listados abajo.

Issues confirmados a fixear:
[tabla de Confirmed del Paso 4]

Instrucciones:
- Fixear solo los issues confirmados. No refactorizar más allá del fix requerido.
- No cambiar código no señalado, ni agregar comentarios explicativos.
- Si el mismo patrón aparece en otros archivos ya tocados, fixearlo en todas las ocurrencias.
- Reportar: archivo, línea, descripción del fix aplicado.
```

## Paso 7 — Re-juzgar

Después de cualquier ronda de fixes: **volver al Paso 3 y re-lanzar una nueva ronda completa de jueces ciegos** sobre el estado actualizado. No asumir que el fix resolvió el problema sin verificación independiente. Re-sintetizar (Paso 4).

**Criterio de aprobación:** cero Confirmed CRITICAL y cero Confirmed `WARNING (real)`. Los theoretical warnings y suggestions pueden quedar sin fixear.

## Paso 8 — Terminal state

- **`JUDGMENT: APPROVED ✅`**: ambos jueces, en la ronda más reciente, devuelven CLEAN o solo INFO, y no quedan contradictions sin resolver.
- **`JUDGMENT: ESCALATED ⚠️`**: persisten contradictions no resueltas, o hallazgos suspect críticos que no se pueden confirmar ni descartar, o el proceso no converge tras 2-3 rondas. Comunicar al usuario que la decisión requiere criterio humano — no forzar un APPROVED para cerrar el ciclo.

## Output Contract

Siempre retornar `## Judgment Day — {target}` con:
- Número de round actual
- Tabla de veredicto completa (todos los findings clasificados)
- Conteo: `Confirmed: N | Suspect: M | Contradictions: K | INFO: J`
- Fixes aplicados (si los hay, con agente y modelo usados)
- Resultado del re-judging (si aplica)
- Estado final: `JUDGMENT: APPROVED ✅` o `JUDGMENT: ESCALATED ⚠️`
