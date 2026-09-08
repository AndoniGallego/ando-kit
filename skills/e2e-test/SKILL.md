---
name: e2e-test
description: Corre tests e2e de navegador (Playwright) contra un dev server local — flujo de usuario (login, navegación, formularios) o auditoría (CSP, errores de consola, requests fallidos). Agnóstico de proyecto y framework de frontend. Invocar cuando el usuario pida "correr un e2e", "probar el flujo de X en el browser", o "auditar la consola/CSP de la página".
---

## Cuándo invocar este skill

Invocar cuando el usuario diga algo como:
- "corré un e2e del login" / "probá el flujo de checkout en el browser"
- "fijate si la página tira errores de consola o de CSP"
- "necesito tests de Playwright para X"

Este skill es el complemento de browser de `integration-test-runner` (que cubre backend: invocación directa o HTTP dentro de un container). Si lo que hay que verificar es una llamada HTTP o un flujo dentro de un container sin renderizar nada en el browser, ese es el agente correcto, no este.

Si la tarea depende de **tu sesión real** (logueado en un dashboard, un SaaS, tu cuenta) en vez de un flujo repetible contra un browser limpio, usar `browser-session` en su lugar — controla tu navegador real, no un Playwright descartable.

## Por qué Playwright

Playwright es el estándar de facto para e2e en frontend moderno (incluido Angular) desde la deprecación de Protractor: cross-browser real (Chromium/Firefox/WebKit) con binarios propios en vez de depender de drivers externos, auto-wait que elimina la mayoría del flakiness de timing, paralelización nativa sin costo de SaaS, y soporte multi-tab/multi-origin. Cypress sigue siendo una alternativa válida (mejor debugging interactivo, testing de componentes), pero para un flujo e2e genérico headless en CI/local, Playwright es la opción por defecto de este kit.

## Delegación al agente

La ejecución en sí (correr los tests, capturar evidencia, dar el veredicto por paso) se delega siempre al agente `e2e-test-runner` — no armar el script de Playwright ni parsear su output en el contexto principal. Este skill define CUÁNDO y CÓMO invocarlo; el agente hace el trabajo aislado.

Al lanzar el agente, indicarle explícitamente:
- La URL base del dev server (default `http://localhost:4200` si es un proyecto Angular con `ng serve` estándar; confirmar si el proyecto usa otro puerto/framework).
- El modo: **A** (flujo de usuario) con la secuencia de pasos esperada, o **B** (auditoría) con las rutas a revisar.
- Si el dev server ya está corriendo o hay que levantarlo (y con qué comando exacto).

## Instalación en un proyecto nuevo (una sola vez)

```bash
npm install -D @playwright/test --legacy-peer-deps
```

**No instalar los binarios de browser en el host** (`npx playwright install` sin más se salta esta regla — evitarlo). Los ~300MB+ por navegador viven en la imagen oficial de Docker de Playwright, que ya los trae preinstalados y versionados junto con `@playwright/test`. Instalarlos a mano en el host de desarrollo es trabajo redundante y una fuente más de desincronización de versiones.

Config mínimo (`playwright.config.ts` en la raíz del proyecto):

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:4200', // ajustar al puerto real del dev server
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
```

## Cómo correr los tests — siempre vía Docker, nunca browsers instalados en el host

1. Resolver la versión exacta de `@playwright/test` instalada, para usar la imagen de Docker que matchea (evita el mismatch de protocolo entre el runner y los browsers de la imagen):
   ```bash
   node -e "console.log(require('./package.json').devDependencies['@playwright/test'])"
   ```
2. Con el dev server ya corriendo en el host (`ng serve` u equivalente, fuera del container), correr los tests dentro del container oficial de Playwright, montando el repo como volumen y usando la red del host para que el container alcance el dev server en `localhost`:
   ```bash
   docker run --rm --network host \
     -v "$(pwd):/work" -w /work \
     mcr.microsoft.com/playwright:v1.61.1-noble \
     npx playwright test --reporter=list
   ```
   - `--network host` funciona directo en Linux; en Windows/Mac con Docker Desktop, `--network host` no aplica igual — usar `http://host.docker.internal:4200` como `baseURL` en el config (override con `PLAYWRIGHT_BASE_URL` o editando el config) en vez de `localhost`.
   - Reemplazar el tag `v1.61.1-noble` por la versión resuelta en el paso 1 (`vX.Y.Z-noble`) — un mismatch entre la versión de `@playwright/test` y la imagen puede romper la ejecución o dar falsos negativos.
3. Si el proyecto prefiere no depender de `docker run` suelto, un `docker-compose.yml` de dos servicios (uno para el dev server, otro para el runner de Playwright apuntando al primero por nombre de servicio en vez de `localhost`) es la alternativa más prolija — pero no es necesario para un uso puntual.
4. Instalar solo Chromium es el default razonable (cubre la mayoría de los bugs de flujo/CSP sin el costo de descargar Firefox/WebKit) — la imagen de Docker ya trae los tres, así que correr contra otro browser es tan simple como agregar el proyecto correspondiente en `playwright.config.ts` y no cuesta una instalación adicional.

## Modos de uso

| Modo | Cuándo | Qué produce |
|---|---|---|
| **A — Flujo de usuario** | Verificar que un flujo específico funciona end-to-end (login, checkout, submit de formulario) | PASS/FAIL por paso, screenshot solo en el paso que falla |
| **B — Auditoría** | "¿la página tira errores?" sin un flujo puntual en mente | Conteo de errores de consola, violaciones CSP, requests fallidos por página |

## Reporte esperado

El agente devuelve PASS/FAIL por paso (modo A) o el conteo de hallazgos por categoría (modo B), nunca el HTML report ni el trace completo de Playwright. Si hay un fallo, la ruta del screenshot generado (`e2e/screenshots/...`) es la evidencia — no describir el screenshot en prosa, solo referenciarlo.

## Formato de salida — AOP v2 (envelope para encadenar agentes)

Este skill orquesta al agente `e2e-test-runner`. Al reportar el resultado al usuario o a un agente siguiente en la cadena, cerrar con el mismo envelope AOP v2 que devuelve el agente (o uno equivalente si el skill agregó pasos propios antes/después):

```
<!-- AOP:BEGIN -->
{"aop_version":"2.0","agent":"e2e-test","status":"ok|warning|blocked|error","for_human":"resumen en <=200 caracteres","for_agent":{"mode":"A","base_url":"http://localhost:4200","steps_passed":3,"steps_total":5,"failed_step":null,"screenshots":[]},"next_agent":null,"blockers":[]}
<!-- AOP:END -->
```

Ver la sección "Protocolo AOP v2" en `CLAUDE.md.template` para el significado exacto de cada campo.
