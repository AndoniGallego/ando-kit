---
name: browser-session
description: Tareas puntuales en TU navegador real ya autenticado (vía la extensión Claude in Chrome u otro navegador vinculado del harness) — no un browser aislado y limpio como Playwright. Usar cuando la tarea depende de un estado de sesión que solo existe en tu browser del día a día — logueado en un dashboard de staging, tu email, un SaaS, un admin panel — o para exploración/investigación puntual que no necesita ser repetible. NO usar para checks que tienen que correr igual dos veces (eso es e2e-test/visual-regression, sobre Playwright).
---

# browser-session

## Por qué existe, y por qué es un skill distinto de `e2e-test`

`e2e-test` y `visual-regression` corren sobre Playwright, en un browser aislado y descartable, dentro de Docker — sin tus cookies, sin tus extensiones, sin tu sesión iniciada en ningún lado. Eso es exactamente lo que hace falta para un chequeo repetible: corrés el mismo test dos veces y da el mismo resultado, sin importar quién lo corra ni cuándo.

`browser-session` es lo opuesto a propósito: controla **el navegador que ya tenés abierto**, con tu sesión real intacta. La ventaja es acceso inmediato a cualquier cosa donde ya estés logueado, sin configurar nada. La contra — medida en benchmarks reales de 2026 — es que es más caro en tokens, necesita más pasos, y no es reproducible (falla de forma distinta según el estado del momento) — por eso nunca reemplaza a `e2e-test`/`visual-regression` para suites que corren en CI. Ver la comparación completa en el README del kit.

## Cuándo usar este skill

- "fijate en mi cuenta de X qué…" / "en el staging donde estoy logueado…"
- Reproducir un bug que solo aparece con tu cuenta/datos reales, no con un usuario de test.
- Revisar cómo se ve/comporta algo con tu perfil real (extensiones, configuración, idioma) tal cual lo usás vos.
- Research puntual en el browser: comparar algo entre varias pestañas, juntar información de una página que requiere estar logueado.

## Cuándo NO usar este skill

- Cualquier cosa que tenga que correr igual la próxima vez, en CI, o sin tu sesión personal → `e2e-test` / `visual-regression`.
- Si alcanza con leer una URL pública sin interactuar → `WebFetch`, no abrir un browser entero.
- Si la tarea es sobre código, no sobre lo que se ve en una página → no es un skill de browser.

## Regla dura — es tu identidad real, tratalo con ese cuidado

A diferencia de Playwright (un browser descartable), acá cualquier acción **es una acción real con tu sesión real**: un submit es un submit de verdad, un delete borra de verdad, una compra es una compra de verdad. Antes de cualquier acción que **cambie estado** (enviar un formulario, borrar algo, confirmar una compra, mandar un mensaje, aceptar términos) — **parar y pedir confirmación explícita**, aunque el usuario haya pedido la tarea en general. Navegar, leer, hacer scroll, y completar campos sin enviar son seguros de hacer sin pedir permiso en cada paso; el punto de no-retorno es el que requiere el OK.

Nunca dispares un diálogo nativo del browser (`alert`/`confirm`/`prompt`) — bloquea toda la sesión de automatización. Si un elemento puede disparar uno (ej. un botón "Eliminar" con confirmación nativa), avisar antes de tocarlo en vez de hacerlo y ver qué pasa.

## Paso 1 — Confirmar que hay navegador vinculado

Si las tools de browser (`mcp__claude-in-chrome__*` u otras del harness) están deferidas, cargarlas todas juntas en una sola consulta (nunca una por una). Empezar siempre por el contexto de pestañas actual:

- Tool de contexto de pestañas (ej. `tabs_context`) para ver qué hay abierto **antes** de decidir si abrir una pestaña nueva o reusar una existente.
- **Nunca reusar una pestaña de una sesión anterior.** Solo reusar una pestaña ya abierta si el usuario lo pide explícitamente para esa pestaña puntual; si no, abrir una nueva.

Si no hay navegador vinculado disponible, decirlo y sugerir instalar/activar la extensión — no intentar sustituirlo con Playwright, que es exactamente el approach que este skill existe para no usar.

## Paso 2 — Entender qué estado de sesión hace falta

Antes de navegar a nada, tener claro: ¿qué sitio, con qué cuenta, y qué información o acción puntual se necesita? Si es ambiguo (ej. "fijate en el dashboard" sin decir cuál), preguntar — es tu sesión real, no vale adivinar y terminar mirando algo que no correspondía.

## Paso 3 — Ejecutar, evidencia concreta por paso

Navegar/leer/interactuar según haga falta. Por cada paso relevante, dejar evidencia concreta (qué se leyó, qué se encontró, screenshot si ayuda a mostrar algo visual) — no una descripción vaga de "parece que anda bien". Si algo no carga o no se encuentra, decirlo explícito en vez de asumir que salió bien.

## Paso 4 — Cerrar limpio

Si la pestaña se abrió para esta tarea puntual y no hay motivo para dejarla, cerrarla al terminar (`tabs_close`) — no acumular pestañas huérfanas de tareas anteriores. Si el usuario probablemente quiere seguir mirando lo que se abrió, dejarla y decirlo.

## Anti-patrones

| Atajo | Por qué falla |
|---|---|
| Usar este skill para un test que se va a repetir en CI | Es exactamente el caso que `e2e-test` cubre mejor — reproducible y sin depender de tu sesión personal |
| Ejecutar una acción que cambia estado sin avisar primero | Es tu cuenta real — un error acá no se resetea con `docker rm` |
| Reusar una pestaña de otra sesión sin que lo pidieron | Puede tener contexto/estado de otra tarea, o directamente no seguir existiendo |
| Seguir reintentando cuando un elemento no responde 2-3 veces seguidas | Señal de que hay que parar y preguntar, no repetir la misma acción a ciegas |
