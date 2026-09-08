# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/1.0.0/).
Versionado semántico.

## [2.4.0] — 2026-09-08

Defensa contra **GitSpawn** (Manifold Security, jun-2026): una clase de vulnerabilidad
real en agentes de código con IA (Claude Code, Codex, Cursor, Grok Build, Goose, Hermes
Agent, Qwen Code) donde un repo ejecuta un programa arbitrario apenas el agente corre su
primer `git status`/`diff`/`add`, vía claves de `.git/config` como `core.fsmonitor` que
nombran un programa.

### Added

- **`ando-git-trust-check.sh`** (hook PreToolUse `Bash`, cualquier comando `git`) —
  audita `.git/config` y `.git/hooks/` del repo en juego **leyéndolos como archivos**
  (nunca invoca `git` para el chequeo, para no arriesgarse a disparar lo que busca).
  Si encuentra `fsmonitor`/`hooksPath`/`pager`/`editor`/`sshCommand`/`askpass`/
  `credential.helper` seteados a algo no-booleano, o un hook ejecutable no-`.sample`,
  **bloquea** (`permissionDecision: deny`). Cachea el veredicto por repo (invalida al
  cambiar `.git/config`) y respeta un allowlist (`~/.claude/.ando-git-trust-allow`) para
  repos propios que legítimamente usan alguna de estas claves (ej. Watchman).
- **README** — sección "Seguridad" explicando el mecanismo y la defensa, incluida la
  advertencia sobre el segundo vector de GitSpawn en `/code-review ultra` (Claude Code),
  confirmado sin parchear públicamente al momento de escribir esto.
- **`CLAUDE.md.template`** (y `~/.claude/CLAUDE.md`) — sección "Seguridad — GitSpawn".
- **`kit-doctor`** — chequea que `ando-git-trust-check.sh` esté instalado y reporta el
  tamaño del allowlist.

## [2.3.0] — 2026-09-08

Pulido: consistencia, visibilidad y dos backstops.

### Added

- **`ando-rdd-reminder.sh`** (hook PreToolUse `Bash`) — al `gh pr create` / `glab mr create`
  desde `feature/<id>`, recuerda correr `rdd-review` si el branch no pasó por ahí o cambió
  desde entonces. La señal es `.git/ando-rdd-reviewed` (SHA que `rdd-review` deja al
  terminar, en su nuevo Paso 7). No bloquea.
- **`ando-statusline-context.sh`** — ahora muestra `kit vX.Y.Z` y, si tu local quedó atrás
  del upstream, `↑N` en amarillo. Cacheado (máx 1 refresh cada 5 min); nunca corre `git`
  en cada render ni hace `fetch`.
- **`CONTRIBUTING.md`** — convenciones de skills/agents/hooks, checklist pre-commit, versionado.
- **`work-unit-commits`** integrado al `CLAUDE.md`: regla explícita de planificar los commits
  antes de un cambio multi-archivo.

### Changed

- **Umbral de contexto unificado a 80%** en `ando-context-threshold.sh`,
  `ando-statusline-context.sh` (rojo + ⚠ DELEGAR) y `CLAUDE.md.template`. Antes el doc decía
  "60-70%" y los hooks disparaban al 85%.
- **`kit-doctor`** — chequea también `ando-rdd-reminder` entre los hooks registrados.
- **`kit-bump`** — instrucción de inserción en `CHANGELOG.md` corregida (no asumía un
  `## [Unreleased]` que el archivo no tiene).

## [2.2.0] — 2026-09-07

Cambio de fondo en el flujo SDD: deja de ser un comando manual y pasa a ser
**arrancado por el orquestador**, con la spec **requerida** cuando la tarea es no trivial.

### Changed

- **`sdd-start`** — reescrito:
  - **Título-primero.** Deriva un slug kebab legible (`rate-limit-login`) del título de
    la tarea, o el orquestador lo propone a partir de lo pedido. Ya no requiere un
    `TICKET-ID` (sigue aceptándolo para quien tenga tracker). Frontmatter: `id:` +
    `tracker:` opcional.
  - **Lo dispara el orquestador**, no el usuario. El "Activation Contract" define los
    criterios de "no trivial"; si la tarea los cruza, la spec es **requerida** y no se
    implementa ni se pushea `feature/<id>` sin `status: approved`. La única salida es
    que el usuario vete el flujo explícitamente (ahí no se crea el archivo de spec).
- **`ando-sdd-gate.sh`** — reescrito con la nueva filosofía: la existencia de
  `$ANDO_SPECS_DIR/<id>.md` es la señal de "se consideró necesaria". Si el archivo no
  existe → mudo (no más nag "te falta la spec"). Si existe y no está `approved` → emite
  `BLOCK:`. Ahora matchea slugs kebab además de `TICKET-ID`.
- **`ando-prepush-check.sh`** — clasifica la salida del gate: líneas `BLOCK:` se
  promueven a `permissionDecision: deny` (el `git push` **no procede** hasta resolver);
  el resto sigue siendo advertencia. Es el único punto del kit que puede bloquear, y
  sólo para el caso auto-infligido "spec a medias en tu propio branch".
- **`sdd-archive`, `handoff`, `spec-delta-apply`** — aceptan `id` como slug kebab
  además de `TICKET-ID`.
- **`ando-delegation-reminder.sh`** — la rama de implementación ahora instruye el
  Paso 0 del flujo SDD (evaluar y arrancar `sdd-start` sin esperar al usuario).
- **`CLAUDE.md.template`** (y `~/.claude/CLAUDE.md`) — nueva sección "Flujo SDD — lo
  arranca el orquestador" con la tabla de criterios y la cadena completa encadenada.
- **`README.md`** — reescrito completo: por qué es útil el kit, el modelo mental
  skill/agent/hook, y cada skill/agent/hook explicado (qué hace y por qué).

### Added

- **`LICENSE`** (MIT) — el repo es público.

## [2.1.1] — 2026-09-07

### Added

- **CI** (`.github/workflows/check.yml`) — corre `scripts/check.sh` (con shellcheck)
  en cada push a `main` y en cada PR.

### Fixed

- El header del `README.md` decía `v2.0.0` en el tag `v2.1.0` — corregido a la versión real.

## [2.1.0] — 2026-09-07

### Added

- **Skill `sdd-start`** — punto de entrada del flujo Spec-Driven: resuelve el
  identificador, draftea la spec en `ANDO_SPECS_DIR` delegando a `spec-writer`, la
  muestra completa, y la marca `status: approved` cuando el usuario la aprueba (no
  antes, y no si quedan preguntas abiertas). Cierra informando los pasos siguientes
  (branch, `/rdd-review`, `/spec-delta-apply`, `/sdd-archive`) sin ejecutarlos.
- **`ANDO_SPECS_DIR` documentado como carpeta central** — carpeta plana y global de
  specs (`<TICKET-ID>.md` con frontmatter `status: draft|approved|done`), fuera de los
  repos. El README de esa carpeta describe la convención y el ciclo.

### Changed

- **README** — el flujo SDD/RDD ahora se muestra como pipeline de punta a punta
  arrancando en `/sdd-start`.
- **`CLAUDE.md.template`** — `/sdd-start` agregado al índice de skills.
- **`ando-delegation-reminder.sh`** — la rama de "spec / diseño previo" ahora apunta a
  `/sdd-start` y matchea también `sdd` / `spec-driven`.

## [2.0.0] — 2026-09-07

Absorción de mejoras genéricas del kit corporativo del que este deriva (v2.x),
des-acopladas de cualquier stack o herramienta propietaria, más mejoras propias
de mantenibilidad y onboarding. Todo el contenido nuevo está escrito para servir
en cualquier proyecto. Primera versión versionada en git (tag `v2.0.0`).

### Added

- **Skill `codebase-onboard`** — primer contacto guiado con un repo desconocido:
  estructura, stack, flujos principales, convenciones, zonas de riesgo, y draft de
  `CLAUDE.md` vía `doc-writer`.
- **Skill `kit-doctor`** (+ `scripts/doctor.sh`) — chequeo read-only de la instalación
  del kit: `ANDO_KIT_DIR`, sync repo↔`~/.claude`, hooks ejecutables y sin errores de
  sintaxis, hooks registrados en `settings.json`, opcionales (gate SDD, Engram). Nunca
  modifica nada; propone el fix.
- **Hook `ando-doctor-sessionstart.sh`** — SessionStart: corre `kit-doctor` al iniciar
  sesión; silencioso si todo OK, avisa solo si hay ⚠️/❌. Opt-in (registrarlo en
  `settings.json`).
- **Agente `frontend-reviewer`** — revisión de componentes de UI agnóstica de framework
  (React/Vue/Svelte/…): estado, contratos de props/eventos, accesibilidad, rendering,
  organización de estilos. Cableado en `judgment-day` y `rdd-review`.
- **Agente `db-analyst`** — DB local en Docker: modo Query (read-only) y Backup, reporte
  compacto sin volcar el resultset. Restore destructivo → delega al skill `db-restore`.
- **`scripts/check.sh`** — lint del propio kit: valida frontmatter de skills/agents,
  envelope AOP v2 en agents, `bash -n` (+ shellcheck si está) en hooks. Exit 1 si hay FAIL.
- **Skill `rdd-review`** — revisión de código con esfuerzo proporcional al riesgo
  (Receipt-Driven Development). Congela el diff, clasifica el riesgo en Bajo/Medio/Alto
  y escala 0/1/4 agentes de revisión. Corrección acotada a una ronda, receipt en Engram,
  escalación a `judgment-day`/`doubt-driven`. Informacional — nunca bloquea.
- **Skill `handoff`** — arma en un paso el contexto completo para retomar trabajo ajeno
  (issue/ticket + estado del PR/branch vía `pr-analyst` + historial vía `git-historian` +
  spec existente).
- **Skill `sdd-archive`** — cierre formal de un ticket con flujo SDD: marca la spec como
  done, guarda en Engram lo construido, verifica que el PR existe.
- **Skill `spec-delta-apply`** — aplica un delta de specs (ADDED/MODIFIED/REMOVED) al
  working tree antes de crear el PR, para que el developer lo revise y commitee con el código.
- **Skill `deploy-check`** — interfaz fina sobre el agente `deploy-checker` para el
  checklist pre-push / pre-PR.
- **Agente `code-architect`** — versión agente (contexto aislado) del skill homónimo:
  propone Hexagonal / DDD / adaptación al patrón existente antes de implementar.
- **Agente `test-strategist`** — decide qué testear y con qué prioridad antes de escribir
  el primer test, separando rutas críticas (dinero, estado, seguridad, concurrencia) de
  casos de bajo valor. Cierra con envelope AOP v2.
- **Hook `ando-sdd-gate.sh`** — gate SDD opt-in (via `ANDO_SPECS_DIR`): advierte —nunca
  bloquea— si un branch `feature/<TICKET-ID>` no tiene spec aprobada, o si el repo tiene
  `specs/` sin tocar en el branch. Lo invoca `ando-prepush-check.sh`.

### Changed

- **`judgment-day`** — reescrito con Activation Contract, Hard Rules, tabla de routing de
  jueces (genérica), prompts base explícitos para Judge A/B, y Output Contract. Suma el
  trigger de escalación desde `rdd-review`.
- **`doubt-driven`** — reestructurado en CLAIM → EXTRACT → DOUBT → RECONCILE → STOP, con
  tabla de precedencia de findings y tabla de "shortcuts que cuestan caro". Suma el
  trigger de escalación desde `rdd-review`.
- **`code-architect`** (skill) — nuevo apéndice "Reglas de código al implementar":
  testabilidad (DI, sin static, value objects) y estilo (sin magic numbers, SRP, logging
  por el canal estándar), agnóstico de lenguaje.
- **`investigar-bug`** — suma tabla de "atajos que cuestan caro" y mapa genérico
  síntoma → hipótesis prioritaria.
- **`ando-delegation-reminder.sh`** — nuevas ramas de keywords para `rdd-review`,
  `handoff`, `test-strategist`, `codebase-onboard`, `frontend-reviewer` y `db-analyst`.
- **`ando-prepush-check.sh`** — ahora incorpora las advertencias de `ando-sdd-gate.sh`.
- **`code-architect`** (skill) — nota que aclara la relación con el agente homónimo.
- **`README.md`** — sección "Skills vs agents — los pares" que documenta los solapamientos
  intencionales (skill = conducís vos, agent = contexto aislado).
- **`install.sh`** — el snippet de `settings.json` ahora incluye SessionStart + los 6 hooks
  + statusline; se documenta `ANDO_SPECS_DIR` como opt-in.

## [1.0.0] — 2026-07-10

Primera versión del ando-kit: skills, agents y hooks personales de Claude Code,
escritos desde patrones genéricos de ingeniería de software.
