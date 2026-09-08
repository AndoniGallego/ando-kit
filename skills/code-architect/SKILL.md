---
name: code-architect
description: Guía decisiones de arquitectura antes de implementar una feature o módulo nuevo. Propone Hexagonal (Ports & Adapters) para módulos aislados, DDD lightweight para dominios con reglas de negocio complejas, o adapta al patrón ya existente cuando se extiende código legacy. Siempre empuja testabilidad vía inyección de dependencias. Agnóstico de lenguaje. Invocar antes de escribir la primera línea de una feature no trivial.
---

# code-architect

Este skill se invoca **antes de implementar**, nunca durante ni después. Su output es una propuesta de estructura de clases/módulos con justificación — no código de producción terminado.

> Hay también un **agente** `code-architect` con el mismo criterio: usalo cuando querés la propuesta hecha en **contexto aislado** (el agente explora el repo y devuelve solo el diseño + envelope AOP v2, sin gastar el contexto principal). Este skill es para cuando ya estás en el flujo y querés guiar la decisión vos mismo paso a paso.

## Paso 1 — Diagnóstico: ¿qué tipo de trabajo es?

Antes de proponer nada, responder tres preguntas:

1. **¿Es código nuevo y aislado, o se extiende algo existente?**
   Revisar el árbol de directorios y los imports del área a tocar. Si el 80% del trabajo cae dentro de un módulo/paquete ya existente, es una extensión — no un módulo nuevo, aunque la feature en sí sea nueva.
2. **¿El dominio tiene reglas de negocio no triviales?**
   Señales de que sí: invariantes que deben cumplirse siempre (ej. "un pedido no puede tener total negativo"), estados con transiciones válidas/inválidas, cálculos que combinan múltiples fuentes de datos, reglas que cambian según configuración o tenant.
   Señales de que no: es un CRUD, un endpoint que traduce request→query→response sin lógica intermedia, un script de una sola pasada.
3. **¿Qué tan grande es el blast radius si la arquitectura elegida resulta ser excesiva?**
   Si la feature puede morir o cambiar de forma radical en semanas, preferir la opción más simple de las aplicables.

## Paso 2 — Elegir la estrategia según el diagnóstico

### (a) Arquitectura Hexagonal (Ports & Adapters) — módulo/servicio nuevo y aislado
Usar cuando el código nuevo no depende fuertemente de infraestructura existente y se puede aislar del resto del sistema.

Estructura mínima a proponer:
- **Domain / Core**: entidades y lógica de negocio pura, sin imports de framework, DB ni HTTP.
- **Ports**: interfaces que el core necesita hacia afuera (ej. `UserRepository`, `NotificationSender`) y interfaces que el core expone hacia adentro (ej. `CreateOrderUseCase`).
- **Adapters**: implementaciones concretas de los ports — el controller HTTP, el repositorio SQL, el cliente de la API externa. Los adapters dependen del core, nunca al revés.
- **Composition root**: el único lugar donde se instancian adapters concretos y se inyectan en el core (constructor injection, factory, o el contenedor DI del framework si ya existe uno).

Justificación a dar siempre: el core queda testeable con dobles de prueba simples (fakes/mocks) sin levantar DB ni red, y los adapters son reemplazables sin tocar lógica de negocio.

### (b) DDD lightweight — dominio complejo, módulo nuevo o existente
Usar cuando el diagnóstico del paso 1 detectó reglas de negocio no triviales, sea o no código nuevo. Combinable con Hexagonal (DDD para modelar el core, Hexagonal para aislarlo).

Elementos a proponer, solo los que agreguen valor real — no aplicar los cinco porque sí:
- **Entidad**: objeto con identidad y ciclo de vida, encapsula sus propias invariantes (no setters públicos que permitan estado inválido).
- **Value Object**: objeto inmutable definido por sus valores, sin identidad (ej. `Money`, `EmailAddress`, `DateRange`). Útil para eliminar validaciones repetidas.
- **Servicio de dominio**: lógica que no pertenece naturalmente a una sola entidad (ej. una operación que combina dos agregados).
- **Repositorio (interfaz)**: abstrae la persistencia del agregado, vive en el dominio; su implementación es un detalle de infraestructura.
- **Agregado**: si hay un cluster de entidades que debe mantenerse consistente como unidad, definir la raíz de agregado y forzar que las modificaciones pasen por ella.

Justificación a dar siempre: nombrar los conceptos del negocio explícitamente en el código reduce el costo de entender y modificar las reglas más adelante, y concentra la validación en un solo lugar en vez de dispersarla en controllers o servicios.

### (c) Adaptarse al patrón existente — extensión de código ya existente
Usar cuando el diagnóstico del paso 1 indica que se está extendiendo algo existente, salvo que el módulo existente sea un desastre reconocido y el usuario pida explícitamente refactor.

Regla dura: **no imponer una arquitectura nueva sobre código legacy sin necesidad.** Antes de proponer estructura:
- Identificar el patrón dominante actual (MVC, transaction script, ya-hexagonal, capas ad-hoc, lo que sea).
- Replicar las convenciones de nombres, capas y ubicación de archivos que ya usa el módulo.
- Si el módulo existente no tiene tests ni forma de inyectar dependencias, es aceptable introducir una interfaz puntual solo para la pieza nueva que se está agregando — no reescribir el resto para justificar la interfaz.

Justificación a dar siempre: consistencia dentro de un mismo módulo vale más que la pureza arquitectónica de una pieza aislada; un patrón mixto sin necesidad real aumenta la carga cognitiva de todo el que toque ese código después.

## Paso 3 — Testabilidad vía inyección de dependencias, sin excepción

Cualquiera sea la opción elegida, la propuesta final debe garantizar:
- Las dependencias externas (DB, red, reloj, filesystem, servicios de terceros) entran por constructor o parámetro de función — nunca instanciadas directamente dentro de la lógica que se quiere testear.
- Es posible escribir un test de la lógica de negocio central sin levantar infraestructura real.
- Si el lenguaje/framework tiene un contenedor DI establecido en el proyecto, usar ese; si no existe, constructor injection manual es suficiente — no introducir un framework DI nuevo solo para esto.

## Paso 4 — Entregable

El output de este skill siempre incluye:
1. Diagnóstico breve (1-3 líneas) de por qué se eligió (a), (b), (c) o una combinación.
2. Esqueleto de clases/interfaces (nombres, responsabilidades, dependencias entre ellas) — pseudocódigo o firmas, no implementación completa.
3. Justificación de 2-4 líneas de por qué esa estructura y no otra alternativa considerada.
4. Nota explícita de qué queda fuera de scope para no sobre-diseñar (YAGNI).

## Apéndice — Reglas de código al implementar

Estas reglas aplican al **escribir el código**, no solo al diseñarlo. Verificarlas antes de dar por cerrado cualquier archivo. Agnósticas de lenguaje.

### Testabilidad (siempre, sin excepción)

- **DI por constructor / parámetro — nunca instanciar dependencias internas** dentro de la lógica que se quiere testear. Todo lo que toca I/O (DB, filesystem, HTTP externo, email, reloj del sistema, RNG) va detrás de una interfaz/puerto e inyectado.
- **Nada de `static` / singletons globales en lógica de negocio** — no se pueden sustituir en un test. Inyectar el colaborador.
- **Value Objects para primitivos con significado** — un `ProductId` y una `Quantity` no se pueden pasar en el orden equivocado; dos `int` sueltos sí.

### Estilo (aplica a cada archivo)

- **Sin magic numbers ni magic strings.** Todo literal con significado de dominio va a una constante con nombre que explique el porqué. Excepción razonable: `0`, `1`, `-1`, `''`, `[]` en contextos triviales (índices, incrementos, chequeos de vacío) — salvo que el `0`/`1` codifique un estado o flag de negocio, en cuyo caso también va a constante. Nunca repetir el mismo literal en dos lugares.
- **Una función, una responsabilidad (SRP).** Cada función hace una cosa, a un solo nivel de abstracción. Señales de olor: más de ~20-30 líneas o 3+ niveles de anidación; el nombre necesita un "y" (`validateAndSave`, `parseAndSend`); mezcla decisión de negocio + I/O + formateo en el mismo cuerpo; hay comentarios que separan "bloques" internos → cada bloque quiere ser una función. El método público queda como una lista legible de pasos con nombre revelador; cada paso privado es testeable y tiene un solo motivo para cambiar.
- **Logging por el canal estándar del proyecto**, nunca `print`/`echo`/`var_dump`/`console.log` de debug dejados en el código. Si el proyecto tiene un logger inyectable, usarlo; en un core hexagonal, definir un puerto de logging e inyectar el adapter.
- **Imports explícitos y ordenados** según la convención del lenguaje — no FQN inline repetidos cuando el lenguaje permite importar y referenciar por nombre corto.
