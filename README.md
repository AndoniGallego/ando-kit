# ando-kit

**v2.0.0**

Kit de Claude Code — skills, agents y hooks para usar en cualquier proyecto. Contenido original, escrito desde conocimiento general de la industria (metodologías de debugging, arquitectura hexagonal/DDD, OWASP, Spec/Receipt-Driven Development, buenas prácticas de PR review). No contiene nada propietario de ningún empleador — se puede compartir libremente.

## Instalar

```bash
bash install.sh
```

Copia:
- `skills/*` → `~/.claude/skills/`
- `agents/*.md` → `~/.claude/agents/`
- `hooks/*.sh` → `~/.local/bin/` (con permisos de ejecución)

Y te deja un snippet de `settings.json` para fusionar a mano (no lo edita automáticamente — Claude Code puede bloquear ediciones directas a ese archivo).

Después de instalar: copiá y completá `CLAUDE.md.template` en `~/.claude/CLAUDE.md` o en el `CLAUDE.md` de cada proyecto.

## Qué incluye

**Skills**
| Skill | Qué hace |
|---|---|
| `codebase-onboard` | Primer contacto guiado con un repo desconocido: estructura, stack, flujos, convenciones + draft de CLAUDE.md |
| `investigar-bug` | Metodología sistemática de investigación: reproducir → historial → hipótesis → verificar → recién ahí fix |
| `doubt-driven` | Revisión adversarial (CLAIM→EXTRACT→DOUBT→RECONCILE→STOP) con subagente ciego al razonamiento propio |
| `judgment-day` | Revisión dual ciega (dos jueces en paralelo) con síntesis y re-juicio |
| `rdd-review` | Revisión de esfuerzo proporcional al riesgo: congela el diff, tiering Bajo/Medio/Alto, 0/1/4 lentes, receipt en Engram. Informacional |
| `code-architect` | Guía de arquitectura antes de implementar (Hexagonal / DDD / adaptar) + reglas de código al implementar |
| `pr-review` | Revisión técnica de PRs/MRs, solo lectura |
| `work-unit-commits` | Planificar commits atómicos y revisables antes de implementar |
| `handoff` | Arma en un paso el contexto para retomar trabajo ajeno (ticket + PR/branch + historial git + spec) |
| `sdd-start` | Punto de entrada del flujo SDD: draftea la spec en `ANDO_SPECS_DIR` con `spec-writer`, te la muestra, la marca `approved` |
| `sdd-archive` | Cierre formal de un ticket SDD: spec → done, contexto a Engram, verifica PR |
| `spec-delta-apply` | Aplica un delta de specs (ADDED/MODIFIED/REMOVED) al working tree antes del PR |
| `deploy-check` | Interfaz fina sobre el agente `deploy-checker` para el checklist pre-push/pre-PR |
| `kit-sync` | Cómo mantener este kit actualizado y guardar tus propios cambios |
| `cognitive-doc-design` | Diseñar documentación (READMEs, RFCs, docs de review) que reduce carga cognitiva |
| `comment-writer` | Redactar comentarios de PR/issue cálidos, directos y cortos |
| `kit-bump` | Bump de versión del kit (patch/minor/major), CHANGELOG y tag git |
| `hotfix-flow` | Hotfix urgente partiendo del tag de producción, sin PR si el pipeline lo permite |
| `resolve-version-conflict` | Resolver conflictos de merge en el archivo de versión (package.json/composer.json/VERSION) |
| `db-restore` | Importar un dump a una DB en Docker con backup previo y confirmación antes del DROP |
| `e2e-test` | Correr tests e2e de navegador (Playwright, vía Docker) contra un dev server local: flujo de usuario o auditoría de consola/CSP |
| `kit-doctor` | Chequeo read-only de la instalación del kit: sync, hooks ejecutables, registro en settings.json, opcionales |

**Agents**
| Agent | Qué hace |
|---|---|
| `git-historian` | Resume historial git de un archivo/módulo sin volcar `git log -p` completo |
| `code-architect` | Versión agente (contexto aislado) del skill homónimo — propone arquitectura antes de implementar |
| `test-strategist` | Decide qué testear y con qué prioridad antes del primer test (dinero/estado/seguridad/concurrencia vs bajo valor) |
| `frontend-reviewer` | Revisión de componentes de UI agnóstica de framework: estado, contratos de props/eventos, a11y, rendering, estilos |
| `db-analyst` | DB local (Docker): modo Query (read-only) y Backup, sin volcar el resultset. Restore destructivo → skill `db-restore` |
| `doc-writer` | Genera documentación técnica enfocada en el WHY, no en repetir el código |
| `changelog-writer` | Genera CHANGELOG (Keep a Changelog) desde el último tag |
| `spec-writer` | Genera spec técnica antes de implementar una feature |
| `security-auditor` | Audita XSS/SQLi/CSRF/command injection/secrets/headers, agnóstico de stack |
| `pr-analyst` | Analiza un PR/MR completo (gh o glab) sin volcar el diff crudo |
| `spec-updater` | Sincroniza specs (requirements/design/tasks) con la implementación real, marcando ADDED/MODIFIED/DEPRECATED |
| `deploy-checker` | Checklist pre-push/pre-deploy: debug code, TODO/FIXME, Conventional Commits, tests — reporta ✅/❌/⚠️ |
| `integration-test-runner` | Test de integración en container (invocación directa o HTTP), estado antes/después, limpieza |
| `async-flow-verifier` | Verifica un pipeline queue→worker→sink por checkpoints tipados (PASS/FAIL/TIMEOUT) |
| `e2e-test-runner` | Corre un flujo e2e de navegador (Playwright headless vía Docker) o auditoría de consola/CSP, agnóstico de proyecto y framework |

Todos los agentes de este kit cierran su respuesta con un envelope AOP v2 (JSON de una línea, `status`/`for_human`/`for_agent`/`next_agent`/`blockers`) además de su reporte legible, para que el orquestador pueda encadenarlos pasando campos estructurados en vez de releer el output completo — ver la sección "Protocolo AOP v2" en `CLAUDE.md.template`.

**Hooks**
| Hook | Cuándo dispara |
|---|---|
| `ando-kit-sync.sh` | PostToolUse Write/Edit — sincroniza skills/agents/hooks en ambas direcciones entre `~/.claude` y este repo |
| `ando-context-threshold.sh` | UserPromptSubmit — alerta (systemMessage) al superar el 85% de contexto usado |
| `ando-delegation-reminder.sh` | UserPromptSubmit — detecta de qué trata el mensaje y recuerda qué skill/agent delegarlo |
| `ando-engram-check-reminder.sh` | UserPromptSubmit — recuerda consultar Engram antes de decir "no tengo contexto" |
| `ando-prepush-check.sh` | PreToolUse Bash (git push) — advierte (no bloquea) sobre Conventional Commits, TODO/FIXME y el gate SDD |
| `ando-sdd-gate.sh` | Helper de `ando-prepush-check.sh` — gate SDD opt-in (via `ANDO_SPECS_DIR`): advierte si un branch `feature/<TICKET>` no tiene spec aprobada. Nunca bloquea |
| `ando-doctor-sessionstart.sh` | SessionStart — corre `kit-doctor` al iniciar sesión; silencioso si todo OK, avisa solo si hay ⚠️/❌. Registrarlo aparte en `settings.json` (ver snippet de `install.sh`) |
| `ando-statusline-context.sh` | StatusLine — modelo, directorio y % de contexto usado, con umbrales de color y aviso ⚠ DELEGAR en ≥85% |

### Skills vs agents — los pares

Algunas capacidades existen como **skill** (procedimiento que seguís en el contexto principal, paso a paso) y como **agent** (ejecutor en contexto aislado que devuelve solo un reporte + envelope AOP v2). No es redundancia: elegí según si querés conducir vos o delegar la ejecución.

| Capacidad | Skill (conducís vos) | Agent (contexto aislado) |
|---|---|---|
| Arquitectura previa | `code-architect` | `code-architect` |
| Checklist pre-deploy | `deploy-check` | `deploy-checker` |
| Revisión de PR/MR | `pr-review` | `pr-analyst` |
| Tests e2e de navegador | `e2e-test` | `e2e-test-runner` |
| Restore / query de DB local | `db-restore` (import con confirmación) | `db-analyst` (query read-only + backup) |

## Plugins externos recomendados (fuera de este kit)

No todo tiene que reinventarse como skill propia. Para GSAP, existe un plugin oficial de GreenSock (autor de la librería) con skills de Claude Code — no es contenido de este kit, se instala aparte vía marketplace:

```bash
claude plugin marketplace add greensock/gsap-skills
claude plugin install gsap-skills@gsap-skills
```

Cubre core API, timelines, ScrollTrigger, plugins (SplitText/Flip/Draggable), integración con frameworks (React/Vue/Svelte) y performance. MIT license, mantenido por GreenSock. Ver la sección "Animaciones (GSAP)" de `CLAUDE.md.template` para la convención de uso recomendada (servicio centralizado + `gsap.context()`).

## Mantenerlo actualizado

El hook `ando-kit-sync.sh` copia automáticamente, en ambas direcciones, lo que edites en `~/.claude/skills/`, `~/.claude/agents/` o `~/.local/bin/ando-*.sh` y este repo (`ANDO_KIT_DIR`). Ver el skill `kit-sync` para el flujo completo de guardar cambios, y `kit-bump` para versionar.

## SDD / RDD (opcional)

Flujo Spec/Receipt-Driven Development ligero y agnóstico de tracker:

```
/sdd-start <TICKET>   →  draft de spec en ANDO_SPECS_DIR, revisión, status: approved
   ↓
git checkout -b feature/<TICKET>  →  implementar  (test-strategist para el plan de tests)
   ↓
/rdd-review           →  revisión proporcional al riesgo del branch
/spec-delta-apply     →  aplica delta de specs de módulo (si aplica)
   ↓
crear PR  →  /sdd-archive <TICKET>   →  status: done
```

`ANDO_SPECS_DIR` es una carpeta plana y global (`<TICKET-ID>.md` con frontmatter `status: draft|approved|done`). El gate `ando-sdd-gate.sh` es **opt-in**: solo actúa si esa variable está seteada — advierte (no bloquea) si vas a pushear `feature/<TICKET>` sin la spec `approved`. Sin la variable, las skills SDD siguen disponibles pero el hook queda mudo.

## Origen

Armado a partir de patrones genéricos de ingeniería de software y de un kit personal previo del autor — no contiene nada propietario de ningún empleador. Libre de compartir.
