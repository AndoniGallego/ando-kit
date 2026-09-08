---
name: hotfix-flow
description: Flujo completo para crear un hotfix urgente a producción — parte de un tag/release ya desplegado (nunca de main), sin necesidad de PR si el pipeline lo permite, y con verificación estricta de qué se commitea. Usar cuando hay que arreglar algo en producción ya, sin esperar el ciclo normal de feature branch + PR + review.
---

Guía el proceso completo de hotfix. Un hotfix parte de lo que está **realmente en producción** (un tag o release), no de `main`/`master` — que puede tener trabajo no validado todavía.

## Reglas fundamentales

- **Base siempre en el tag/release de producción**, nunca en main/master directamente. Si no hay tags formales, usar el commit que se sabe con certeza que está desplegado (preguntar al usuario si no es obvio).
- **Versión con un dígito extra**, si el proyecto versiona explícitamente (ej. `x.x.x` → `x.x.x.1`, o el siguiente disponible si ya hay un hotfix previo sobre el mismo tag). Si el proyecto no versiona archivos, omitir este paso.
- **Solo commitear archivos del hotfix.** Verificar con `git diff --stat` antes de stagear — ignorar cambios locales preexistentes (`.env`, configs locales, artifacts de build) que no son parte del fix.
- **Sin PR si el flujo del repo lo permite** (algunos pipelines taguean automáticamente al pushear a un branch `hotfix/*`). Si el repo no tiene ese automatismo, un PR mínimo sigue siendo más seguro que pushear directo a producción — no asumir que se puede saltar sin confirmarlo.

## Flujo paso a paso

**1. Identificar la base del hotfix**
Si no se indicó, preguntar: ¿de qué tag/versión desplegada partimos?
```bash
git fetch --tags
git tag --sort=-creatordate | head -10   # ver tags recientes
```

**2. Limpiar branches de hotfix anteriores del mismo fix, si existen**
```bash
git branch -D hotfix/<descripcion> 2>/dev/null
git push origin --delete hotfix/<descripcion> 2>/dev/null || true
```

**3. Crear el branch desde el tag/base de producción**
```bash
git checkout -b hotfix/<descripcion> <TAG>
```

**4. Aplicar el cambio mínimo necesario**
Resistir la tentación de aprovechar el hotfix para arreglar otras cosas — cuanto más chico el diff, más rápido y seguro es el review y el rollback si algo sale mal.

**5. Bump de versión, si el proyecto lo requiere**
Actualizar el archivo de versión correspondiente (`package.json`, `composer.json`, `VERSION`, `Cargo.toml`, etc.) según la convención del proyecto.

**6. Verificar antes de commitear**
```bash
git diff --stat
```
Confirmar que solo aparecen los archivos del hotfix — nunca stagear cambios locales preexistentes que aparecieron al hacer checkout del tag.

**7. Commit y push**
```bash
git add <archivos-del-hotfix>
git commit -m "fix: descripción breve del hotfix"
git push origin hotfix/<descripcion>
```

**8. Verificar el resultado**
Si el pipeline tagea automáticamente, confirmar que el nuevo tag apareció. Si el repo requiere PR incluso para hotfixes, abrirlo marcando explícitamente la urgencia para acelerar el review.

## Señales de alerta

- Si `git checkout -b hotfix/x <TAG>` muestra archivos modificados al crear el branch → hay cambios locales preexistentes desde antes. No los commitees junto con el fix.
- Si el pipeline falla porque la versión/tag ya existe → incrementar y volver a pushear, no forzar el tag existente.
