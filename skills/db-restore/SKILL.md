---
name: db-restore
description: Importa un dump SQL local a una base de datos que corre en Docker — detecta el dump disponible, ofrece backup previo, pide confirmación antes de cualquier operación destructiva, y verifica el resultado antes/después. Invocar cuando el usuario mencione importar, restaurar o pisar una base de datos local.
---

## Cuándo invocar este skill

Invocar cuando el usuario diga algo como:
- "quiero importar el dump de X"
- "pisá la base local con el dump nuevo"
- "restaurá la DB a partir de este backup"

## Regla dura

**Nunca ejecutar un DROP/restore sin confirmación explícita del usuario**, sin importar cuán obvio parezca el pedido. Una base de datos local puede tener trabajo de otra sesión o datos que el usuario todavía necesita.

## Paso 1 — Resolver el dump

Si el usuario no indicó la ruta exacta, buscar en la ubicación habitual de dumps del proyecto (ej. `~/dumps/`, `./backups/`, la que el repo use):

```bash
ls -la ~/dumps/ 2>/dev/null
ls -la ./backups/ 2>/dev/null
```

- Si hay `.sql` y `.sql.gz` del mismo dump → preferir `.sql` si el volumen lo permite (más rápido, sin descomprimir dentro del container).
- Si hay varios archivos que podrían matchear → listarlos y preguntar cuál usar.
- Si no se encuentra ninguno → pedir la ruta exacta al usuario, no asumir.

## Paso 2 — Resolver el container y la base destino

```bash
docker ps --format '{{.Names}}\t{{.Image}}' | grep -i -E 'mysql|postgres|mariadb'
```

Confirmar con el usuario el nombre exacto del container y de la base destino si hay más de un candidato.

## Paso 3 — Obtener el estado actual de la DB

```bash
# MySQL/MariaDB
docker exec <container> mysql -u<user> -p<pass> -e "SHOW TABLES FROM <db>;" | wc -l

# PostgreSQL
docker exec <container> psql -U <user> -d <db> -c "\dt" | wc -l
```

Mostrar al usuario cuántas tablas tiene la base actualmente, para que la confirmación del paso 5 sea informada.

## Paso 4 — Ofrecer backup

Preguntar siempre antes de continuar:

> "¿Querés hacer un backup de la base actual antes de pisarla?"

- Si **sí**:
  ```bash
  docker exec <container> mysqldump -u<user> -p<pass> <db> > ~/dumps/backup-<db>-$(date +%Y%m%d-%H%M%S).sql
  # o para Postgres:
  docker exec <container> pg_dump -U <user> <db> > ~/dumps/backup-<db>-$(date +%Y%m%d-%H%M%S).sql
  ```
  Confirmar que el archivo de backup se generó y tiene tamaño mayor a 0 antes de continuar.
- Si **no** → continuar al paso 5, dejando explícito en el resumen final que no se hizo backup.

## Paso 5 — Confirmación final

Mostrar resumen y pedir confirmación explícita antes de ejecutar nada destructivo:

```text
Estoy por ejecutar:
  DROP DATABASE <db>  (o el equivalente que el import requiera)
  Importar: <path del dump> → <db>
  Backup previo: <sí, path> | <no>

¿Confirmar? (s/n)
```

No ejecutar el import hasta recibir confirmación afirmativa explícita.

## Paso 6 — Ejecutar el import

```bash
# MySQL/MariaDB
docker exec -i <container> mysql -u<user> -p<pass> <db> < <path-del-dump>

# PostgreSQL (recrear si el dump es un dump completo con CREATE DATABASE)
docker exec -i <container> psql -U <user> <db> < <path-del-dump>
```

## Paso 7 — Reportar resultado

Al finalizar, verificar y mostrar:
- Tablas antes vs. después del import.
- Archivo importado (path y tamaño).
- Si se hizo backup: path exacto donde quedó guardado.

Si el conteo de tablas después del import es 0 o claramente incorrecto, reportarlo como posible falla en vez de darlo por exitoso solo porque el comando no devolvió error.
