---
name: visual-regression
description: Detecta cambios visuales no intencionales comparando screenshots contra un baseline guardado (Playwright snapshot testing nativo). Complementa a e2e-test — ese cubre flujo funcional y errores de consola/CSP, este cubre "¿algo se movió/rompió visualmente?" tras un cambio de estilos, markup o dependencias de UI. Invocar cuando el usuario pida "revisar si algo cambió visualmente", "regresión visual", "comparar contra el diseño anterior", o antes de mergear un cambio de estilos/CSS/theming amplio.
---

## Cuándo invocar este skill

- "¿este cambio de CSS rompió algo en otra página?"
- "corré una regresión visual antes de mergear esto"
- "quiero un baseline de cómo se ve X ahora, para comparar después"
- Antes de un cambio de dependencia de UI (versión de un design system, un framework de CSS) que puede mover pixeles sin que nadie lo pida explícitamente.

**No es esto** si lo que hace falta es verificar que un flujo funciona (`e2e-test` modo A) o que la página no tira errores (`e2e-test` modo B) — la regresión visual solo mira pixeles, no comportamiento.

## Por qué existe

Un cambio de CSS/markup puede romper visualmente una página que nadie tocó directamente — un margin global, una clase de utilidad reusada, una actualización de dependencia. Nada de eso produce un error de consola ni rompe un test funcional; solo se nota mirando. Automatizar esa mirada con un baseline es mucho más barato que un humano revisando pantalla por pantalla, y mucho más confiable que "me fijo si se ve raro" a ojo.

## Delegación al agente

Se delega siempre a `e2e-test-runner`, **Modo C**. Este skill define cuándo y con qué alcance invocarlo; el agente escribe el spec, corre Playwright dentro de Docker, y compara contra el baseline.

Al lanzar el agente, indicarle explícitamente:
- La URL base del dev server.
- **Qué páginas y qué viewports** comparar — no dejar que el agente adivine un subset. Un buen default cuando el usuario no lo precisa: las 2-3 rutas más visitadas del proyecto, en desktop (1280×720) y mobile (375×667).
- Si es la **primera corrida** (se espera que cree baseline nueva) o una corrida de **comparación** (ya debería existir baseline).

## Baselines: dónde viven y cómo se actualizan

- Playwright los guarda junto al spec, en `<spec>-snapshots/`. Son binarios (PNG) — considerar si el repo los versiona con Git LFS si el proyecto ya lo usa, o los deja fuera de git y cada quien genera los suyos localmente (ambas son válidas; preguntar la convención del repo si no es obvia).
- **Nunca se actualiza un baseline en automático.** Un diff visual siempre se muestra al usuario antes de decidir si es el bug que se buscaba o un cambio intencional que hay que aceptar como nuevo estado "correcto".
- Si el usuario confirma que el cambio es intencional, el agente re-corre con `--update-snapshots` **solo para esa página×viewport puntual** — no refrescar todo el suite de baselines de una sola vez salvo pedido explícito (eso escondería regresiones reales en páginas que no se estaban revisando a propósito).

## Formato de respuesta

El agente devuelve PASS / CHANGED / NUEVA BASELINE por página×viewport, con las rutas de `expected`/`actual`/`diff` para cada `CHANGED` — nunca describe la diferencia en prosa ("el botón se movió un poco"), el diff es la evidencia. Ver el formato completo de Modo C en `agents/e2e-test-runner.md`.

## Formato de salida — AOP v2 (envelope para encadenar agentes)

Este skill orquesta al agente `e2e-test-runner` (Modo C). Al reportar, cerrar con el mismo envelope que devuelve el agente:

```
<!-- AOP:BEGIN -->
{"aop_version":"2.0","agent":"e2e-test-runner","status":"ok|warning|blocked|error","for_human":"resumen <=200 caracteres","for_agent":{"mode":"C","base_url":"http://localhost:4200","visual_changes":[{"page":"/dashboard","viewport":"desktop","diff_pct":2.3,"is_new_baseline":false}]},"next_agent":null,"blockers":[]}
<!-- AOP:END -->
```

Ver la sección "Protocolo AOP v2" en `CLAUDE.md.template` para el significado de cada campo.
