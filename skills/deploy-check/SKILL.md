---
name: deploy-check
description: Checklist pre-push / pre-PR de un repo — version bump, código de debug olvidado, TODO/FIXME, Conventional Commits, convención de nombres de branch, y que los tests pasen. Interfaz fina sobre el agente deploy-checker. Invocar antes de git push o de crear un PR/MR.
---

Este skill es una **interfaz fina**: toda la lógica de validación vive en el agente
`deploy-checker` (`~/.claude/agents/deploy-checker.md`). No correr los checks en el
contexto principal — el agente los ejecuta en aislamiento y devuelve solo el reporte.

## Paso 1 — Determinar el input del agente

1. **Repo path** (obligatorio): path absoluto del repo a validar. Default: el repo del
   directorio actual (`git rev-parse --show-toplevel`).
2. **Contexto opcional**: si el proyecto tiene una convención propia (nombres de branch,
   archivo de versión, comando de tests no estándar), pasárselo al agente en el prompt.

## Paso 2 — Delegar a `deploy-checker`

Invocar el agente `deploy-checker` via Agent tool:

```
Validá el repo <repo_path>. Corré todos tus checks pre-deploy (version bump si el repo
versiona, debug code, TODO/FIXME, branch name, Conventional Commits, tests) y devolveme
el reporte ✅/❌/⚠️ completo con el veredicto final.
[Convención del proyecto, si aplica: <detalle>]
```

Si hay varios repos tocados en la sesión, despachar un agente por repo (en paralelo).

## Paso 3 — Actuar sobre el reporte

- **LISTO ✅** → seguir con el flujo (avisar al usuario antes de push / crear el PR).
- **CON ADVERTENCIAS ⚠️** → mostrarlas al usuario y dejar que decida si procede.
- **BLOQUEADO ❌** → mostrar los issues, corregirlos (delegando a los agentes que
  correspondan) y volver a despachar `deploy-checker` hasta que pase.

El agente nunca bloquea por sí solo — el veredicto es informativo, la decisión de pushear es del usuario.
