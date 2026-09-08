---
name: codebase-onboard
description: Primer contacto guiado con un repositorio desconocido — mapea la estructura, detecta stack y convenciones, encuentra los puntos de entrada y los flujos principales, y produce (opcionalmente) un borrador de CLAUDE.md. Usar al empezar a trabajar en un repo que no conocés, o cuando falta un CLAUDE.md útil. Agnóstico de lenguaje.
---

# Codebase Onboard

## Por qué existe

Aterrizar en un repo desconocido y empezar a tocar código sin entender su forma es la fuente #1 de cambios que "funcionan" pero rompen una convención, duplican algo que ya existía, o meten una dependencia en la capa equivocada. Este skill fuerza un recorrido corto y ordenado **antes** de la primera edición, y deja el entendimiento por escrito para que no haya que repetirlo.

**Regla:** no proponer ni hacer cambios de código hasta terminar el Paso 4. Explorar para entender, no para editar.

## Paso 1 — Forma del repo (barato, sin leer código todavía)

```bash
# Raíz, tamaño y lenguajes
git -C . rev-parse --show-toplevel
find . -maxdepth 2 -type d | grep -vE '/(node_modules|vendor|\.git|dist|build|target|__pycache__)/' | sort
# Manifiestos → stack y scripts
ls package.json composer.json pyproject.toml requirements.txt go.mod Cargo.toml pom.xml build.gradle Gemfile 2>/dev/null
# Señales de tooling
ls .github/workflows .gitlab-ci.yml Dockerfile docker-compose.yml Makefile .pre-commit-config.yaml 2>/dev/null
```

Anotar: lenguaje(s) principal(es), gestor de paquetes, cómo se corre (scripts de `package.json` / `Makefile` / `composer.json`), cómo se testea, si hay CI y qué valida.

## Paso 2 — Convenciones y documentación existente

- Leer `README.md`, `CONTRIBUTING.md`, `docs/`, `ADR/`, `CLAUDE.md` si existe — no asumir que están al día, pero sí registrar lo que dicen.
- Detectar el estilo: linter/formatter configurado (`.eslintrc`, `ruff.toml`, `.php-cs-fixer`, `rustfmt.toml`), convención de commits (mirar `git log --oneline -20`), convención de nombres de branch (`git branch -a`).
- Si el repo es grande, delegar el **historial** al agente `git-historian` sobre los directorios que parezcan el core — qué se toca seguido, qué tiene reverts, quién lo mantiene.

## Paso 3 — Puntos de entrada y flujos principales

Con un agente `Explore` (o lectura acotada si el repo es chico), identificar:
- **Entry points**: `main`, `index`, el server bootstrap, los comandos CLI, los handlers de ruta, los cron/workers.
- **Los 2-3 flujos más importantes** end-to-end (request → capa de aplicación → dominio → persistencia; o evento → handler → efecto). Un párrafo por flujo, con los archivos clave.
- **La arquitectura de facto**: ¿capas (hexagonal, MVC, layered)? ¿módulos por feature? ¿monolito con paquetes? ¿dónde vive la lógica de negocio vs la infraestructura?
- **Dónde NO tocar sin cuidado**: migraciones, código legacy marcado, adaptadores de terceros, generado automáticamente.

No leer todos los archivos — seguir los flujos. Cortar cuando el modelo mental sea suficiente para ubicar un cambio típico.

## Paso 4 — Entregable: briefing (y draft de CLAUDE.md si se pide)

Mostrar al usuario un briefing con esta estructura:

```markdown
# Onboarding — <repo>

## Stack y cómo se corre
- Lenguaje / package manager: ...
- Levantar: `<comando>` · Testear: `<comando>` · Lint: `<comando>`
- CI valida: ...

## Estructura
[árbol anotado de los directorios que importan, 1 línea cada uno]

## Arquitectura de facto
[2-4 líneas: patrón, dónde vive la lógica de negocio, boundaries]

## Flujos principales
1. <nombre> — <archivos clave, en orden>
2. ...

## Convenciones
- Commits: ... · Branches: ... · Estilo: ...

## Zonas de riesgo / no tocar sin cuidado
- ...

## Preguntas abiertas
- [lo que no se pudo deducir del código y conviene confirmar con alguien]
```

Si el usuario pide un `CLAUDE.md`: delegar al agente `doc-writer` pasándole este briefing como insumo, y guardar el resultado en la raíz del repo (o en `~/.claude/CLAUDE.md` si el usuario lo prefiere global). El `doc-writer` se enfoca en el WHY y las invariantes no obvias — no repetir lo que los nombres ya dicen.

## Anti-patrones

| Atajo | Por qué falla |
|---|---|
| Empezar a editar con el modelo mental a medias | El cambio choca con una convención o duplica algo existente que no viste |
| Leer archivo por archivo en orden alfabético | Consume contexto sin construir el mapa; seguir flujos es mucho más denso en señal |
| Copiar el README como si fuera la verdad actual | Los README envejecen; contrastá con el código y el `git log` reciente |
| Generar un CLAUDE.md que enumera carpetas | Eso ya lo ve cualquiera con `ls`; el valor está en el WHY y en las trampas |
