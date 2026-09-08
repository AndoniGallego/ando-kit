---
name: doubt-driven
description: Revisión adversarial con contexto fresco antes de dar por buena una decisión no trivial — lógica de pagos, migraciones de datos, cambios de seguridad, concurrencia, hotfixes a prod. Invoca un subagente revisor pasándole solo el artefacto final y el contrato, nunca el razonamiento propio, para evitar sesgo de confirmación. Usar antes de dar por cerrado un cambio de alto riesgo, o como escalación de rdd-review ante una decisión puntual en disputa.
---

# Doubt-Driven Review

## Por qué existe este skill

Un agente (o una persona) que acaba de implementar algo tiene un sesgo estructural: ya construyó una narrativa de por qué su solución es correcta, y tiende a buscar evidencia que la confirme en vez de evidencia que la refute. Revisar el propio trabajo con la misma mente que lo escribió rara vez encuentra el error — porque el error suele estar escondido exactamente en el punto ciego que generó la solución.

La única forma efectiva de contrarrestarlo es que **otra mente, sin el razonamiento previo, mire el resultado final con la misión explícita de encontrar por qué está mal** — no de confirmar que está bien.

## Cuándo usar

- El cambio toca lógica de pago/cobros/reembolsos/saldos, o cualquier flujo con dinero real.
- Migraciones de datos (esquema, backfills, scripts que tocan producción).
- Cambios de seguridad (auth, permisos, CSP, sanitización, manejo de secretos).
- Control de concurrencia (locks, reservas, operaciones que deben ser atómicas).
- La decisión cruza boundaries entre módulos/servicios.
- Hotfixes urgentes a prod sin suite de tests que los respalde.
- La sesión lleva mucho tiempo activa y puede haber sesgo acumulado.
- Como escalación automática de `rdd-review` (Paso 6b), cuando hay una decisión puntual y acotada en disputa.

**No usar para:** cambios mecánicos (renombrar, formatear, bump de versión), instrucciones explícitas del usuario que no requieren interpretación, cambios de una línea con corrección obvia, o cuando el usuario pidió explícitamente velocidad sobre rigor.

## Paso 1 — CLAIM: nombrar la decisión

Escribir en 2-3 líneas qué decisión se está tomando y por qué importa.

```
DECISIÓN: [qué estás eligiendo hacer]
IMPACTO: [qué se rompe si está mal]
ALTERNATIVA DESCARTADA: [qué no elegiste y por qué]
```

Si no podés articularlo en 3 líneas, tenés intuición, no una decisión. Detenerse y clarificar antes de continuar.

## Paso 2 — EXTRACT: aislar el artefacto y el contrato

Identificar la unidad mínima revisable: el código, diff, script de migración o config que representa la decisión — lo que efectivamente se va a ejecutar o mergear. **No un resumen de lo que se hizo, el contenido real.**

El artefacto tiene dos partes:
- **ARTEFACTO:** el código o diff concreto (paths + líneas relevantes).
- **CONTRATO:** las constraints que debe cumplir — qué tiene que ser verdad para que la decisión sea correcta. Escribirlo como un requirement externo y verificable, no como una defensa del approach elegido.

Ejemplo de contrato bien definido:
```
CONTRATO:
- No puede haber doble reserva para el mismo id en la tabla de reservas
- El rollback ante fallo del pago debe liberar la reserva sin side effects
- Idempotente: reintentar la operación no duplica efectos
- La migración mueve todas las filas de A a B sin pérdida y sin downtime
```

**Explícitamente NO incluir:** el razonamiento de por qué se implementó así, los intentos previos descartados, ni ninguna justificación de por qué el autor cree que está bien. Si el revisor ve el razonamiento original, hereda el mismo sesgo.

## Paso 3 — DOUBT: invocar el revisor adversarial

Delegar a un subagente con contexto fresco (Agent tool). El prompt **debe ser adversarial**:

```
Sos un revisor de código senior. Detectá el lenguaje/framework del artefacto y aplicá sus convenciones.
Asumí que el autor es demasiado confiado. Tu trabajo es encontrar qué está mal.

ARTEFACTO:
[pegar el código o diff]

CONTRATO (lo que debe cumplir):
[pegar el contrato del Paso 2]

Revisá si el artefacto cumple el contrato. Buscá:
- Violaciones de las constraints definidas
- Race conditions o side effects no contemplados
- Fallas parciales: ¿qué pasa si el proceso se corta a la mitad?
- Casos límite e inputs maliciosos o inesperados que el autor no consideró
- Suposiciones implícitas no validadas
- Gaps entre lo que el código hace y lo que el contrato requiere

Pedí evidencia concreta por cada hallazgo (línea de código, escenario reproducible).
Terminá con un veredicto: aprobado / aprobado con reservas (listar) / rechazado (listar por qué).
```

Qué subagente usar: el reviewer especializado que corresponda al dominio si existe (`security-auditor` para cambios de seguridad, `pr-analyst` para un diff completo), o `general-purpose` con el prompt adversarial de arriba para una decisión de arquitectura.

## Paso 4 — RECONCILE: procesar los findings

Re-leer el artefacto contra cada finding usando esta precedencia:

| Clasificación | Criterio | Acción |
|---|---|---|
| **Contrato mal leído** | El revisor malinterpretó el requisito | Clarificar el contrato, re-loop |
| **Válido + accionable** | Problema real que el artefacto no resuelve | Cambiar el artefacto, re-loop |
| **Trade-off válido** | Problema real pero aceptable con el contexto | Documentar explícitamente la decisión |
| **Ruido** | El revisor no tenía contexto suficiente | Anotar y continuar |

Vos seguís siendo el orquestador. El output del revisor es input, no veredicto. No racionalizar por qué un problema real "en realidad no importa" sin evidencia propia que lo respalde.

## Paso 5 — STOP: cuándo terminar

Detener el ciclo cuando:
- La siguiente iteración devuelve solo findings triviales o duplicados.
- Se completaron 3 ciclos.
- El usuario dice "ship it".

Si después de 3 ciclos siguen apareciendo findings sustanciales, **el artefacto no está listo** — escalar al usuario en lugar de seguir loopeando. Si el riesgo es especialmente alto, considerar una doble revisión ciega en paralelo (ver skill `judgment-day`).

Documentar el resultado (aprobado / con qué reservas) antes del push o deploy.

## Shortcuts que cuestan caro

| Atajo | Por qué falla |
|---|---|
| Pasarle el razonamiento al revisor junto con el artefacto | El revisor valida en lugar de dudar — exactamente lo que querés evitar |
| Usar el mismo contexto de sesión como "revisor" | No es contexto fresco — tiene los mismos sesgos acumulados |
| Hacer 3 ciclos donde ningún finding es accionable | Es doubt theater: estás validando, no dudando |
| Saltear el contrato y pedir "revisá esto" | Sin contrato el revisor no tiene referencia — los findings son genéricos e inútiles |
| Aplicar todos los findings sin re-leer el artefacto | El revisor puede equivocarse; la decisión final es tuya |
| Aceptar un "se ve bien" sin que el revisor haya buscado activamente fallas | Un revisor que no buscó no es lo mismo que un revisor que buscó y no encontró nada |
| Usarlo en cambios mecánicos | Overhead sin beneficio — reservar para decisiones de alto impacto |
