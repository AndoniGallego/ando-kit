---
name: ui-design-system
description: Define o afina la identidad visual de una app de escritorio o dashboard de negocio. Paleta, tipografía, estilo de componentes, densidad y UX, consultando una base local de estilos, paletas, pares tipográficos y guías UX, y bajando el resultado a los tokens CSS que el proyecto ya tiene. Usar cuando se pide "que se vea más lindo/profesional", elegir colores o fuentes, revisar contraste, estados vacíos/error/carga o accesibilidad de una UI.
---

# ui-design-system

Datos y búsqueda local, derivados de nextlevelbuilder/ui-ux-pro-max-skill (MIT, ver `data/LICENSE-UPSTREAM.md`). Sin red, solo lectura.

## Cuándo NO usarla

Lógica de negocio, backend, performance no visual. Y si el pedido es un cambio de una línea en un color: editá el token y listo.

## Procedimiento

1. **Leer los tokens que ya existen** en el proyecto (en Mostrador: `frontend/src/app.css`, bloque `:root` y sus reasignaciones de tema oscuro). Todo lo que salga de esta skill se expresa como valor de un token existente. No se inventan tokens nuevos salvo que falte una función (por ejemplo, un color de acento secundario), y en ese caso se agrega en claro y oscuro a la vez.
2. **Consultar** (las consultas van en inglés, los datos están en inglés; 2 a 5 palabras clave por consulta):
   ```bash
   python "C:/Users/andon/.claude/skills/ui-design-system/scripts/search.py" "<consulta>" --domain <dominio> -n 3
   ```
   Dominios: `style`, `color`, `typography`, `ux`, `product`, `reasoning`, `chart`, `motion`, `svelte`, `vue`, `html`. Sin `--domain` devuelve el mejor resultado de cada uno. Si `python` no está, `py -3`.
   Orden sugerido: `product` y `reasoning` (qué estilo recomienda para ese rubro), después `style`, `color`, `typography`, y `ux` para el detalle de cada componente.
3. **Verificar el encaje** antes de aplicar: el resultado tiene que ser de escritorio o web (ignorar filas `Type: Mobile` o de plataformas táctiles puras), compatible con modo claro y oscuro, y con el usuario real (no técnico, texto grande, una sola PC).
4. **Bajar a tokens**: mapear cada decisión a un token (`--color-accion`, `--color-panel`, `--radio`, `--sombra-baja`, etc.). Comparar contraste con el token actual y cambiar solo si la mejora es visible y medible. Los tests de contraste del proyecto (si existen) mandan.
5. **Aplicar de a poco** (un eje por commit: paleta, después tipografía, después componentes) y verificar con la app recién levantada, no solo con HMR.

## Restricciones de este entorno

- **Offline**: los `CSS Import` de `typography.csv` apuntan a Google Fonts. Para una app que corre sin internet hay que empaquetar la fuente localmente (archivos `.woff2` en `public/` y `@font-face`), respetando la licencia OFL de cada una. Nunca dejar el `@import url(https://...)`.
- **Tauri/WebView2**: probar en la ventana real; las sombras grandes, `backdrop-filter` y blur son caros en PCs viejas. Preferir sombras de dos capas chicas.
- **Motion**: las guías del dominio `motion` traen snippets de GSAP; usar solo los de intensidad baja y respetar `prefers-reduced-motion`.

## Checklist UX/a11y para apps de negocio

- Contraste de texto >= 4.5:1 (AA), texto grande e iconos >= 3:1; bordes de controles >= 3:1. Verificar en claro y en oscuro.
- Foco visible en todo elemento interactivo (outline 2 a 3px, nunca `outline: none` sin reemplazo); navegación completa por teclado, orden lógico, Enter/Escape coherentes en formularios y modales.
- Objetivos de click/táctil >= 44px (en un mostrador táctil o con guantes, mejor 56px), con separación entre botones destructivos y de confirmación.
- El color nunca es la única señal: estado con icono o texto ("Sin stock", "Anulada"), además del color.
- Estados de cada vista: cargando (esqueleto o spinner con texto), vacío (mensaje + acción concreta: "Todavía no cargaste productos. Cargar el primero"), error (qué pasó y qué hacer, junto al campo, sin jerga), éxito (confirmación visible, no solo un toast que desaparece).
- Formularios: etiqueta visible (no solo placeholder), error cerca del campo, teclado numérico y formato de moneda ARS, valores por defecto sensatos.
- Acciones destructivas o de dinero (anular venta, borrar, cerrar caja): confirmación explícita con el nombre de lo que se afecta, y deshacer cuando sea posible.
- Tablas densas: números alineados a la derecha con cifras tabulares (`font-variant-numeric: tabular-nums`), fila de encabezado fija, hover de fila, sin scroll horizontal en el ancho normal de la PC.
- `prefers-reduced-motion`: sin animaciones de movimiento; transiciones de 150 a 300ms, solo `opacity` y `transform`; ninguna animación bloquea una acción.
- Consistencia: un solo estilo de icono (SVG, nunca emoji), un solo radio por nivel (control, tarjeta, hoja), una escala de espaciado (4/8/12/16/24/32).

## Contenido

- `data/`: `styles`, `colors`, `typography`, `ux-guidelines`, `products`, `ui-reasoning`, `charts`, `motion`, y `stacks/` de Svelte, Vue y HTML+Tailwind. Datos sin modificar; se descartaron los demás stacks, landings, iconos, fuentes de Google y performance de React.
- `scripts/search.py`: búsqueda BM25 por palabras clave, stdlib, solo lee `data/` y escribe a stdout.
