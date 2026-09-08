# ando-kit

**v2.7.0** · Kit de Claude Code — skills, agents y hooks para usar en cualquier proyecto.

Contenido original, escrito desde conocimiento general de la industria (debugging sistemático, arquitectura hexagonal/DDD, OWASP, Spec/Receipt-Driven Development, buenas prácticas de review). No contiene nada propietario de ningún empleador — **libre de compartir**.

---

## Por qué existe

Claude Code hace lo que le pedís. Sin un andamiaje, en tareas largas eso deriva en tres problemas recurrentes:

1. **El contexto se llena.** El hilo principal lee diffs enormes, logs, código desconocido — y a las dos horas está ahogado, respondiendo peor.
2. **Los cambios se hacen sin diseño previo.** Se empieza a codear antes de decidir los casos límite y los contratos; el retrabajo aparece después.
3. **La revisión es opcional y desigual.** A veces se revisa a fondo, a veces no, y no queda registro de con qué criterio.

Este kit ataca los tres con una estructura opinada:

- **Orquestación.** El contexto principal *decide y coordina*; los agentes *ejecutan* en aislamiento y devuelven sólo un resumen. Una statusline y un hook vigilan el uso de ventana y empujan a delegar antes de que sea tarde.
- **Spec-Driven, arrancado por el orquestador.** Ante una tarea de implementación no trivial, Claude arranca solo el flujo SDD: escribe una spec, te la hace aprobar, y recién ahí implementa. No hace falta que tipees ningún comando.
- **Escalera de revisión proporcional al riesgo.** Desde un revisor adversarial único hasta dos jueces ciegos en paralelo, según lo que esté en juego — con receipt en memoria persistente.
- **Anti-slop.** Investigación de bugs con hipótesis-antes-de-fix; commits planificados como unidades revisables; documentación pensada para reducir carga cognitiva.

Casi todo esto Claude podría hacerlo si se lo pedís bien cada vez. El valor del kit es que pasa a ser **el default, consistente, y disparado automáticamente** — por el criterio del orquestador o por hooks.

---

## El modelo mental

| Pieza | Qué es | Cuándo |
|---|---|---|
| **Skill** | Un procedimiento guiado paso a paso, con comandos exactos y puntos de decisión. Se auto-activa por contexto o lo invoca el orquestador. | "Hacé *este proceso*" (investigar un bug, arrancar una spec, revisar un PR). |
| **Agent** | Un ejecutor que corre en **contexto aislado**, lee lo que necesita, y devuelve sólo un reporte + un envelope estructurado. | "Andá a hacer *esto* sin gastarme la ventana" (resumir historial git, auditar seguridad, correr un test de integración). |
| **Hook** | Un script que dispara automáticamente en un evento del harness (prompt submit, pre-`git push`, session start). Determinístico. | Recordatorios y gates que no pueden depender de que el modelo se acuerde. |

**Principio rector:** el contexto principal orquesta, no ejecuta. Lecturas voluminosas y tareas mecánicas de más de un paso van a agentes. El orquestador recibe el resumen, decide el siguiente paso, coordina.

---

## Instalar

```bash
bash install.sh
```

Copia `skills/*` → `~/.claude/skills/`, `agents/*.md` → `~/.claude/agents/`, `hooks/*.sh` → `~/.local/bin/` (con permiso de ejecución), y te imprime un snippet de `settings.json` para fusionar a mano (no lo edita solo).

Después: copiá `CLAUDE.md.template` a `~/.claude/CLAUDE.md` y completá los datos de tu setup. Opcional: exportá `ANDO_SPECS_DIR` (ver "Flujo SDD/RDD").

Diagnóstico en cualquier momento: `/kit-doctor`.

---

## Flujo SDD/RDD

El ciclo Spec/Receipt-Driven, **arrancado y encadenado por el orquestador** (vos no pedís cada paso):

```
Pedís una feature
   ↓  el orquestador evalúa: ¿es no trivial? (comportamiento nuevo / contrato /
   ↓  lógica de negocio / migración / seguridad / 3+ archivos)
   ↓  SÍ → la spec es requerida
sdd-start        → deriva un slug del título, draftea la spec con spec-writer en
                   ANDO_SPECS_DIR, te la muestra, la marca status: approved
   ↓
git checkout -b feature/<id>  →  implementar  (test-strategist arma el plan de tests)
   ↓
rdd-review       → revisión proporcional al riesgo del branch (0/1/4 lentes)
spec-delta-apply → aplica delta de specs de módulo, si hay <id>.delta.md
   ↓
crear el PR  →  sdd-archive <id>   →  status: done + receipt en Engram
```

**`ANDO_SPECS_DIR`** es una carpeta plana y global (`<id>.md` con frontmatter `status: draft|approved|done`; `<id>` es un slug kebab o un `TICKET-ID`). Es **opt-in**: si no la exportás, las skills SDD siguen disponibles pero el gate no actúa.

**El gate (`ando-sdd-gate.sh`)** es lo único del kit que puede **bloquear** un `git push`, y sólo en un caso: estás en `feature/<id>`, existe `$ANDO_SPECS_DIR/<id>.md`, y no está `approved`. Es un estado auto-infligido de resolución inmediata (aprobá tu propia spec, o archivala si decidiste no seguir SDD). Sin spec para esa rama — porque la tarea era trivial o vos vetaste el flujo — el gate no dice nada.

---

## Skills

### Investigar y revisar

| Skill | Qué hace y por qué |
|---|---|
| `investigar-bug` | Fuerza la secuencia reproducir → historial → hipótesis falsable → verificar con evidencia → recién ahí fix. El error caro no es tardar, es "arreglar" lo que no era la causa. Incluye tabla de atajos que cuestan caro y mapa síntoma→hipótesis. |
| `doubt-driven` | Revisión adversarial de contexto fresco (CLAIM→EXTRACT→DOUBT→RECONCILE→STOP). Le pasás al revisor **sólo el artefacto y el contrato, nunca tu razonamiento** — si ve tu razonamiento, valida en vez de dudar. Para cambios de alto impacto. |
| `judgment-day` | Dos jueces independientes en paralelo, ciegos entre sí, sobre el mismo target. Coincidencia = señal fuerte; contradicción = zona ambigua que merece un humano. Re-juzga tras cada fix hasta `APPROVED` o `ESCALATED`. |
| `rdd-review` | Revisión de **esfuerzo proporcional al riesgo**: congela el diff, lo clasifica Bajo/Medio/Alto, y escala 0/1/4 agentes de revisión. Corrección acotada a una ronda. Deja un receipt en Engram. Informacional — nunca bloquea. Escala a `judgment-day`/`doubt-driven` ante contradicciones. |
| `pr-review` | Revisión técnica de un PR/MR (GitHub o GitLab). Sólo lectura — no crea, edita, mergea ni comenta. Trae el diff completo, separa críticos de mejoras opcionales. |

### Diseñar e implementar

| Skill | Qué hace y por qué |
|---|---|
| `codebase-onboard` | Primer contacto guiado con un repo desconocido: forma del repo, stack, convenciones, 2-3 flujos end-to-end, zonas de riesgo. Opcionalmente genera un `CLAUDE.md` vía `doc-writer`. Antes de la primera edición, no después. |
| `code-architect` | Guía de arquitectura **antes de implementar** — Hexagonal (módulo nuevo aislado), DDD lightweight (dominio complejo), o adaptación al patrón existente (legacy). Apéndice con reglas al escribir código (DI, sin `static`, sin magic numbers, SRP). |
| `sdd-start` | Punto de entrada del flujo SDD (ver arriba). Título-primero: no requiere ticket. Lo arranca el orquestador. |
| `work-unit-commits` | Planificar los commits como unidades revisables **antes** de implementar un cambio multi-archivo: cada commit compila, tiene un propósito describible en una línea, y el conjunto cuenta una historia legible para el reviewer. |

### Spec-Driven

| Skill | Qué hace |
|---|---|
| `spec-delta-apply` | Aplica un delta de specs de módulo (`ADDED`/`MODIFIED`/`REMOVED`) al working tree antes del PR, para que lo revises y commitees junto con el código. |
| `sdd-archive` | Cierre formal: marca la spec `done`, guarda en Engram qué se construyó, verifica que el PR existe. |
| `handoff` | Arma en un paso el contexto para retomar trabajo ajeno: issue/ticket + estado del PR/branch + historial git del repo + spec existente. En vez de juntar eso a mano de tres fuentes. |

### Release y deploy

| Skill | Qué hace |
|---|---|
| `deploy-check` | Interfaz fina sobre el agente `deploy-checker` — checklist pre-push/pre-PR (debug code, TODO/FIXME, Conventional Commits, nombre de branch, tests). |
| `hotfix-flow` | Hotfix urgente partiendo del **tag de producción**, no de main, sin PR si el pipeline lo permite. Con verificación estricta de qué se commitea. |
| `resolve-version-conflict` | El conflicto de merge típico en el archivo de versión (`package.json`/`composer.json`/`VERSION`) cuando otro PR ya bumpeó sobre la misma base: acepta la entrante y re-bumpea encima. |
| `kit-bump` | Bump de versión del propio kit (patch/minor/major según los cambios), actualiza `VERSION`, commit y tag git. |

### Docs y comunicación

| Skill | Qué hace |
|---|---|
| `cognitive-doc-design` | Diseñar documentación (READMEs, RFCs, guías, docs de review) que reduce carga cognitiva — estructura, orden, qué omitir. |
| `comment-writer` | Redactar comentarios de PR/issue cálidos, directos y cortos. |

### Infra y testing

| Skill | Qué hace |
|---|---|
| `db-restore` | Importar un dump a una DB en Docker: detecta el dump, ofrece backup previo, **pide confirmación antes del DROP**, verifica el resultado. |
| `e2e-test` | Tests e2e de navegador (Playwright, vía Docker) contra un dev server local: flujo de usuario (login, navegación, formularios) o auditoría (CSP, errores de consola, requests fallidos). |
| `visual-regression` | Detecta cambios visuales no intencionales — screenshot vs baseline con el snapshot testing nativo de Playwright, vía el mismo agente `e2e-test-runner` (Modo C). Complementa a `e2e-test`: ese cubre comportamiento, este cubre pixeles. |
| `browser-session` | Tareas puntuales en **tu navegador real ya logueado** (Claude in Chrome), no un Playwright descartable — cuando la tarea depende de una sesión/cuenta real. Ver "Playwright vs tu navegador real" abajo para cuándo usar cada uno. |

### Meta

| Skill | Qué hace |
|---|---|
| `kit-sync` | El flujo para guardar tus propios cambios al kit y mantenerlo actualizado. |
| `kit-doctor` | Chequeo **read-only** de la instalación: `ANDO_KIT_DIR`, sync repo↔`~/.claude`, hooks ejecutables y sin errores de sintaxis, hooks registrados en `settings.json`, opcionales. Nunca modifica; propone el fix. |

---

## Agents

Corren en **contexto aislado** y cierran con un envelope AOP v2 (JSON de una línea: `status` / `for_human` / `for_agent` / `next_agent` / `blockers`) además del reporte legible, para que el orquestador encadene agentes pasando campos estructurados en vez de releer el output completo.

| Agent | Para qué |
|---|---|
| `git-historian` | Resume el historial git de un archivo/módulo (qué cambió, por qué, quién, señales de volatilidad) sin volcar `git log -p` al orquestador. |
| `code-architect` | Versión agente del skill homónimo — propone arquitectura en aislamiento y devuelve sólo el diseño. |
| `test-strategist` | Decide **qué testear y con qué prioridad antes de escribir el primer test** — separa rutas críticas (dinero, estado, seguridad, concurrencia) de casos de bajo valor que no vale cubrir. |
| `frontend-reviewer` | Revisión de componentes de UI agnóstica de framework (React/Vue/Svelte/…): estado, contratos de props/eventos, accesibilidad, rendering, organización de estilos. |
| `db-analyst` | DB local en Docker — modo Query (read-only, rechaza mutaciones) y Backup, con reporte compacto. Restore destructivo → delega al skill `db-restore`. |
| `doc-writer` | Genera documentación técnica enfocada en el **por qué** y las invariantes no obvias, no en repetir lo que los nombres ya dicen. |
| `changelog-writer` | Genera un bloque de CHANGELOG (Keep a Changelog) desde el último tag, agrupado por tipo. |
| `spec-writer` | Genera la spec técnica antes de implementar: comportamiento esperado, contratos, casos límite explícitos, fuera de scope, preguntas abiertas. Devuelve el documento completo. |
| `spec-updater` | Sincroniza `requirements/design/tasks` con la implementación real después de un cambio, marcando `ADDED`/`MODIFIED`/`DEPRECATED`. |
| `security-auditor` | Audita XSS, SQLi, CSRF, command injection, secrets hardcodeados, path traversal, deserialización insegura, headers faltantes. Findings priorizados por severidad con archivo:línea y vector de explotación concreto. |
| `pr-analyst` | Analiza un PR/MR completo (`gh` o `glab`), incluidos comentarios de bots tipo CodeRabbit, sin volcar el diff crudo. También branches sin PR. |
| `deploy-checker` | Corre todas las validaciones pre-deploy en aislamiento y devuelve un reporte ✅/❌/⚠️ por check. |
| `integration-test-runner` | Test de integración dentro de un container (invocación directa o HTTP/curl), captura estado antes/después, hace cleanup, reporta PASS/FAIL sin volcar logs. |
| `async-flow-verifier` | Verifica que un evento se propagó por un pipeline `cola → worker → sink` por checkpoints tipados (PASS/FAIL/TIMEOUT), sin volcar payloads. |
| `e2e-test-runner` | Corre un flujo e2e de navegador (Playwright headless), una auditoría de consola/CSP, o una regresión visual (screenshot vs baseline), con capturas sólo en fallos/diffs. |

---

## Hooks

| Hook | Evento | Qué hace |
|---|---|---|
| `ando-kit-sync.sh` | PostToolUse `Write\|Edit` | Sincroniza en ambas direcciones `skills/` `agents/` `hooks/` entre `~/.claude` y el repo del kit (`ANDO_KIT_DIR`). Editás en un lado, aparece en el otro. |
| `ando-delegation-reminder.sh` | UserPromptSubmit | Detecta de qué trata tu mensaje y le recuerda al orquestador qué skill/agent delegar — y, si hay intención de implementar, que evalúe el Paso 0 del flujo SDD. Silencioso si no matchea nada. |
| `ando-context-threshold.sh` | UserPromptSubmit | Al superar el 85% de la ventana de contexto, inyecta un aviso para cerrar la fase actual (commit + resumen a Engram) antes de arrancar trabajo nuevo. |
| `ando-engram-check-reminder.sh` | UserPromptSubmit | Recuerda consultar la memoria persistente (Engram) antes de afirmar "no tengo contexto de esto". |
| `ando-prepush-check.sh` | PreToolUse `Bash` (`git push`) | Advierte sobre Conventional Commits y TODO/FIXME (el push procede). Promueve a **bloqueo** las líneas `BLOCK:` del gate SDD, y bloquea directo si `gitleaks` (opcional, si está instalado) encuentra un secreto real en los commits a pushear. |
| `ando-sdd-gate.sh` | *(helper de `ando-prepush-check.sh`, no se registra)* | Si estás en `feature/<id>` y existe `$ANDO_SPECS_DIR/<id>.md` sin `approved` → emite `BLOCK:` (el push no procede hasta aprobar/archivar la spec). Sin spec para esa rama → mudo. Opt-in vía `ANDO_SPECS_DIR`. |
| `ando-rdd-reminder.sh` | PreToolUse `Bash` (`gh pr create` / `glab mr create`) | Si el branch `feature/<id>` no pasó por `rdd-review` (o cambió desde entonces), lo recuerda antes de crear el PR. La señal es `.git/ando-rdd-reviewed` que `rdd-review` deja al terminar. No bloquea. |
| `ando-git-trust-check.sh` | PreToolUse `Bash` (cualquier `git ...`) | Defensa contra **GitSpawn** (ver sección "Seguridad" abajo). **Bloquea** si el `.git/config` o `.git/hooks/` del repo en juego tiene algo que ejecuta un programa arbitrario. Cache por repo + allowlist para los tuyos. |
| `ando-kit-update-check.sh` | SessionStart | Sustituto de cron (Windows no tiene): como mucho 1 vez cada 12hs, hace `git fetch` del kit y avisa si hay novedades. Con `ANDO_KIT_AUTOUPDATE=1`, hace pull+install solo si el working tree está limpio. Ver "Autoupdate" abajo. |
| `ando-doctor-sessionstart.sh` | SessionStart | Corre `kit-doctor` al iniciar sesión. Silencioso si todo OK; avisa sólo si hay ⚠️/❌. Registrarlo aparte (ver snippet de `install.sh`). |
| `ando-statusline-context.sh` | StatusLine | Modelo, directorio y % de contexto usado, con umbrales de color y aviso ⚠ DELEGAR en ≥85%. |

---

## Seguridad

**GitSpawn** (Manifold Security, jun-2026) es una clase de vulnerabilidad real en agentes de código con IA (Claude Code, Codex, Cursor, Grok Build, Goose, Hermes Agent, Qwen Code): un repo puede traer en su `.git/config` una clave como `core.fsmonitor` que **nombra un programa arbitrario**, y Git lo ejecuta en cualquier operación que refresque el índice — `git status`, `git diff`, `git add`. Exactamente lo que un agente corre solo, sin que nadie lo pida, para "entender el repo". No hace falta que hagas nada: alcanza con que el agente corra su primer `git status` en un directorio cuyo `.git` ya traía esto — típicamente porque el repo llegó como carpeta/zip/`cp -r` en vez de un `git clone <url>` genuino (clonar por URL no transmite el `.git/config` del origen).

`ando-git-trust-check.sh` intercepta **cualquier comando `git`** (lo dispare el usuario o el modelo) y, antes de dejarlo pasar, audita `.git/config` y `.git/hooks/` del repo en juego **leyéndolos como archivos** — nunca invoca al propio `git` para el chequeo, para no arriesgarse a disparar lo que está buscando. Si encuentra `fsmonitor`, `hooksPath`, `pager`, `editor`, `sshCommand`, `askpass` o `credential.helper` seteados a algo que no sea un booleano trivial, o un hook ejecutable que no es el `.sample` por defecto, **bloquea** el comando.

Cachea el veredicto por repo (no re-audita hasta que cambie `.git/config`) y respeta un allowlist para tus propios repos que legítimamente usan alguna de estas claves (ej. `fsmonitor=true` con Watchman en un monorepo grande):

```bash
echo "/ruta/a/tu/repo/.git" >> ~/.claude/.ando-git-trust-allow
```

**Esto es defensa en profundidad, no la única barrera.** Sigue valiendo la higiene básica: no abras con un agente de IA un repo que no clonaste vos mismo por URL, y mirá `.git/config` a mano si tenés dudas. Y ojo con `/code-review ultra` (`claude ultrareview`) específicamente — al momento de escribir esto tiene un segundo vector de GitSpawn (una clave de git config distinta, no revelada públicamente por los investigadores) confirmado sin parchear; evitalo contra repos que no controlás hasta que haya confirmación de fix.

### Secretos en el pre-push (gitleaks, opcional)

Un dato de 2026 (GitGuardian, *State of Secrets Sprawl*): los commits asistidos por IA filtran secretos reales aproximadamente **el doble** que la línea base humana — un agente genera scaffolding/config rápido, y es fácil que un token real se cuele sin que nadie lo mire línea por línea antes del push.

Si tenés [`gitleaks`](https://github.com/gitleaks/gitleaks) instalado (`brew install gitleaks` / `scoop install gitleaks` / `apt install gitleaks`), `ando-prepush-check.sh` lo corre sobre los commits que vas a pushear y **bloquea el push** si encuentra un secreto real — con `--redact`, así el valor del secreto nunca aparece en el mensaje del hook. Sin `gitleaks` instalado, este chequeo simplemente no corre (no hay nag; `kit-doctor` lo señala como opcional). Un secreto ya en el historial no se arregla con un commit nuevo que lo borre — hay que reescribir el historial o rotar la credencial.

## Playwright vs tu navegador real

`e2e-test`/`visual-regression` (Playwright, vía Docker) y `browser-session` (Claude in Chrome, tu navegador real) no son intercambiables — cubren casos distintos, y elegir el equivocado sale caro de una forma u otra.

Playwright **no ejecuta JS falso ni mockeado** — es un motor de browser real (Chromium/Firefox/WebKit) con el JS real del sitio en un DOM real. Lo que no tiene es *tu* sesión: arranca un perfil limpio, sin tus cookies, logins ni extensiones. Ahí es donde `browser-session` gana — controla el navegador que ya tenés abierto, con todo eso intacto.

Pero esa ventaja tiene costo, medido en benchmarks reales de 2026: controlar un navegador real necesitó más pasos y más tokens que Playwright para la misma tarea, y falló de forma no reproducible en flujos de autenticación (no pudo acceder a URLs `chrome-extension://`, necesitó intervención manual). Por eso **nunca es la herramienta para un check que tiene que correr igual la próxima vez** — para eso Playwright, con su browser limpio y descartable, es estrictamente mejor: repetible, más barato, y sin depender de qué pestañas tengas abiertas en el momento.

| | `browser-session` (navegador real) | `e2e-test` / `visual-regression` (Playwright) |
|---|---|---|
| Fortaleza | Sesión/cuenta real ya autenticada, cero configuración | Repetible — mismo resultado dos veces |
| Costo | Más tokens, más pasos por tarea | Más barato, más determinista |
| Para CI / regresión | No | Sí — es la herramienta para esto |
| Para una tarea puntual en tu cuenta real | Sí | No aplica (no tiene tu sesión) |

## Skills vs agents — los pares

Algunas capacidades existen como **skill** (procedimiento que conducís vos) y como **agent** (ejecutor en contexto aislado, devuelve reporte + envelope AOP v2). No es redundancia:

| Capacidad | Skill (conducís vos) | Agent (contexto aislado) |
|---|---|---|
| Arquitectura previa | `code-architect` | `code-architect` |
| Checklist pre-deploy | `deploy-check` | `deploy-checker` |
| Revisión de PR/MR | `pr-review` | `pr-analyst` |
| Tests e2e de navegador | `e2e-test` | `e2e-test-runner` |
| DB local | `db-restore` (import con confirmación) | `db-analyst` (query read-only + backup) |

---

## Mantenerlo

- **Sync automático:** `ando-kit-sync.sh` copia en ambas direcciones lo que edites en `~/.claude/skills|agents` o `~/.local/bin/ando-*.sh` y este repo. Ver el skill `kit-sync`.
- **Versionar:** skill `kit-bump` (o a mano: `VERSION` + `CHANGELOG.md` + tag `vX.Y.Z`).
- **Lint:** `bash scripts/check.sh` valida frontmatter de skills/agents, envelope AOP v2 en agents, y `bash -n` (+ shellcheck si está) en hooks. Corre también en CI (`.github/workflows/check.yml`) en cada push a `main` y cada PR.
- **Diagnóstico:** `/kit-doctor` (read-only, propone fixes).

### Autoupdate (sin cron)

Windows no tiene cron, y este kit no instala ningún daemon en background. `ando-kit-update-check.sh` (hook SessionStart) es el sustituto: en cada sesión, como mucho una vez cada `ANDO_KIT_UPDATE_CHECK_HOURS` horas (default 12), hace `git fetch` del kit y refresca el indicador `kit vX.Y.Z ↑N` de la statusline con datos reales — no la cifra pasiva que había antes de esto.

Por defecto solo **avisa** si hay commits nuevos, con el comando exacto para traerlos. Si preferís que directamente se actualice solo:

```bash
export ANDO_KIT_AUTOUPDATE=1
```

Con la variable seteada, actualiza automáticamente **solo si el working tree del kit está limpio** (sin cambios sin commitear, ni siquiera archivos untracked) y el merge es fast-forward — si no, avisa por qué no lo hizo en vez de arriesgarse a pisar algo que estabas por guardar con `kit-sync`. `/kit-doctor` muestra cuándo fue el último chequeo y si el autoupdate está activo.

---

## Adaptarlo a tu setup

1. `cp CLAUDE.md.template ~/.claude/CLAUDE.md` y completá: herramientas y paths (`gh`/`glab`, package manager, runtime), stack de tus proyectos activos, quirks de testing local.
2. Fusioná el snippet de `settings.json` que imprime `install.sh` (los hooks + statusline).
3. Opcional: `export ANDO_SPECS_DIR=<carpeta>` en tu shell rc y en `settings.json` → `env`, para activar el gate SDD.
4. Memoria persistente: el kit asume un MCP tipo Engram. Si usás otro, ajustá la sección "Memoria persistente" del `CLAUDE.md`.

---

## Plugins externos recomendados

No todo se reinventa como skill propia. Para GSAP hay un plugin oficial de GreenSock con skills de Claude Code (core API, timelines, ScrollTrigger, plugins, integración con frameworks, performance):

```bash
claude plugin marketplace add greensock/gsap-skills
claude plugin install gsap-skills@gsap-skills
```

---

## Origen

Armado a partir de patrones genéricos de ingeniería de software y de un kit personal previo del autor. No contiene nada propietario de ningún empleador. Libre de usar, copiar y adaptar.
