---
name: resolve-version-conflict
description: Resuelve el conflicto de merge típico en un archivo de versión (package.json, composer.json, VERSION, Cargo.toml) cuando otro PR/MR ya mergeó un bump sobre la misma rama base. Acepta la versión entrante y re-bumpea encima. Usar cuando un PR/MR propio queda bloqueado por conflicto justo en la línea de versión.
---

Resuelve el conflicto típico de "me robaron la versión": otro PR/MR mergeó un bump de versión antes que el tuyo, y ahora tu branch está bloqueado por conflicto en el archivo de versión del proyecto.

## Cuándo usar este skill

- Un PR/MR muestra conflictos de merge.
- El conflicto está específicamente en el archivo de versión (`"version"` en `package.json`/`composer.json`, contenido de `VERSION`, `version =` en `Cargo.toml`).
- La causa es que otro PR/MR se mergeó antes con un bump sobre la misma base.

## Proceso

**1. Identificar branches del PR/MR**

```bash
# GitHub
gh pr view <NUMERO> --json headRefName,baseRefName

# GitLab
glab mr view <MR_ID> --output json | jq -r '.source_branch, .target_branch'
```

**2. Actualizar la rama base local**

```bash
git fetch origin
git checkout <rama-base>
git pull origin <rama-base>
```

**3. Volver a la feature branch y mergear la base actualizada**

```bash
git checkout <rama-feature>
git merge origin/<rama-base>
```

Si git resuelve el merge automáticamente (sin conflicto): saltar al paso 5.

**4. Resolver el conflicto en el archivo de versión**

Aceptar la versión entrante (rama base) — es la fuente de verdad del historial de releases:

```bash
git checkout --theirs <archivo-de-version>
git add <archivo-de-version>
git commit --no-edit
```

**5. Ver la versión actual y re-bumpear encima**

```bash
grep -E '"version"|^version' <archivo-de-version>
```

Bumpear un patch sobre la versión que quedó (la de la rama base) y commitear:

```bash
git add <archivo-de-version>
git commit -m "chore: bump version X.Y.Z → X.Y.(Z+1)"
```

**6. Push**

```bash
git push origin <rama-feature>
```

El PR/MR debería aparecer sin conflictos.

## Casos especiales

### La rama local tiene cambios sin commitear

Si el checkout de la rama base falla por cambios locales:

```bash
git stash push -u -m "WIP pre-merge stash"
# hacer los pasos 2–6
git stash pop    # restaurar después del push
```

Si el `stash pop` genera conflicto en el archivo de versión:

```bash
git checkout HEAD -- <archivo-de-version>   # restaura solo ese archivo, preserva el resto del WIP
git stash drop stash@{0}                     # descarta el stash ya aplicado
```

### La rama local divergió del remoto (non-fast-forward)

Si el push falla porque el remoto tiene commits que el local no tiene:

```bash
git merge origin/<rama-feature>
```

Si hay conflicto en el archivo de versión en este merge secundario: tomar la versión local (`--ours`), que ya incorpora el bump de la rama base.

```bash
git checkout --ours <archivo-de-version>
git add <archivo-de-version>
git commit --no-edit
git push origin <rama-feature>
```

### Múltiples repos con el mismo conflicto

Procesar en paralelo si son independientes. Verificar al final que cada PR/MR quedó sin badge de conflicto.

## Verificación final

Abrir el PR/MR y confirmar que ya no muestra conflicto de merge.
