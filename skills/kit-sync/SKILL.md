---
name: kit-sync
description: Documenta y ejecuta la sincronización del ando-kit personal — un hook (ando-kit-sync.sh) copia automáticamente al repo del kit (ANDO_KIT_DIR) cada cambio hecho en ~/.claude/skills/ o ~/.claude/agents/. Usar cuando el usuario dice "actualizá mi kit" (git pull + re-correr instalador) o "quiero guardar este cambio en mi kit" (verificar que el hook ya copió, commit + push manual, sin PR por ser repo personal de un solo usuario).
---

# kit-sync

El ando-kit es un repo git personal de un solo usuario. No hay PRs, no hay reviewers, no hay MR board — el flujo es directo: editar local, el hook copia al repo del kit, commit y push manual cuando el usuario lo pide.

## Cómo funciona la sincronización automática

El hook `ando-kit-sync.sh` (en `~/.local/bin/`, asumido ya instalado) está enganchado a los eventos de escritura de Claude Code sobre:
- `~/.claude/skills/**`
- `~/.claude/agents/*.md`

Cada vez que se crea o modifica un archivo bajo esas rutas, el hook copia el archivo al repo del kit, ubicado en la ruta que apunta la variable de entorno `ANDO_KIT_DIR`. El hook **no** hace commit ni push — solo copia el archivo al working tree del repo del kit. El commit y el push quedan siempre como paso manual explícito.

Verificar que la variable está seteada antes de asumir que el hook puede correr:
```bash
echo "$ANDO_KIT_DIR"
```
Si está vacía, el hook no tiene dónde copiar — avisar al usuario en vez de asumir un path por default.

## Caso 1 — el usuario dice "actualizá mi kit" / "traé lo último del kit"

Esto significa: traer al entorno local lo que ya está en el repo remoto del kit (dirección repo → local), no al revés.

```bash
cd "$ANDO_KIT_DIR" && git pull
```

Después de traer los cambios, re-correr el instalador del kit para que los skills/agents actualizados queden reflejados en `~/.claude/`:

```bash
"$ANDO_KIT_DIR"/install.sh   # o el script de setup equivalente que exponga el kit
```

Si el kit no tiene un instalador dedicado, el paso mínimo aceptable es copiar manualmente los archivos actualizados de `$ANDO_KIT_DIR/skills/` y `$ANDO_KIT_DIR/agents/` a `~/.claude/skills/` y `~/.claude/agents/` respectivamente. Confirmar con el usuario cuál de las dos formas aplica en su instalación antes de asumir.

## Caso 2 — el usuario dice "guardá este cambio en mi kit" / "quiero que esto quede en el kit"

Esto significa: local → repo del kit → remoto. Pasos, en orden:

1. **Verificar que el hook ya copió el cambio.** No asumir — comparar el archivo local contra su copia en el kit:
   ```bash
   diff ~/.claude/skills/<skill-tocado>/SKILL.md "$ANDO_KIT_DIR"/skills/<skill-tocado>/SKILL.md
   ```
   Si `diff` no muestra nada, el hook funcionó y el archivo ya está sincronizado en el working tree del kit. Si hay diferencias, copiar el archivo manualmente antes de seguir — no confiar ciegamente en que el hook corrió.

2. **Revisar el diff del repo del kit** antes de commitear, para confirmar que solo se está llevando el cambio esperado:
   ```bash
   cd "$ANDO_KIT_DIR" && git status && git diff
   ```

3. **Commit y push directos a la rama principal.** Al ser un repo personal de un solo usuario, no hace falta branch de feature ni PR:
   ```bash
   cd "$ANDO_KIT_DIR"
   git add <archivos-relevantes>
   git commit -m "<tipo>: <descripción breve del cambio>"
   git push
   ```
   Preferir agregar archivos específicos por nombre en vez de `git add -A`, para evitar arrastrar cambios sin relación que puedan estar sueltos en el working tree del kit.

4. Confirmar al usuario con el hash del commit y que el push fue exitoso.

## Qué hacer si el hook no copió el cambio

Si en el paso de verificación del Caso 2 aparece diferencia entre el archivo local y el del kit, no perder tiempo debuggeando el hook en el momento — copiar el archivo a mano para no bloquear al usuario, y dejar una nota de que el hook debería revisarse (posibles causas: el hook no está registrado en la config de hooks de Claude Code, `ANDO_KIT_DIR` cambió de valor, o el path tocado no matchea el patrón que el hook escucha).

## Qué no hacer

- No crear branches ni PRs para cambios del kit — es un repo de un solo usuario, agrega fricción sin beneficio.
- No hacer `git pull` con cambios locales sin commitear en `$ANDO_KIT_DIR` sin avisar antes — puede generar conflictos que el usuario no espera.
- No asumir la ubicación de `ANDO_KIT_DIR` si la variable no está seteada; preguntar o pedir que la exporte antes de continuar.
