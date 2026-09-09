---
paths:
  - "**/*.{js,jsx,ts,tsx,vue,svelte}"
---

## Animaciones (GSAP)

Si un proyecto usa GSAP para animaciones, instalar el plugin oficial de skills (una sola vez por máquina, queda disponible en todas las sesiones):

```bash
claude plugin marketplace add greensock/gsap-skills
claude plugin install gsap-skills@gsap-skills
```

Cubre core API, timelines, ScrollTrigger, plugins (SplitText/Flip/Draggable), integración React/frameworks y performance — se auto-activa como skill cuando el contexto es de animación con GSAP, sin invocación manual. Preferir siempre un servicio/wrapper centralizado (ej. un `AnimationService` con `gsap.context()` por componente) por sobre llamar GSAP directo desde cada componente — `gsap.context()` es lo que garantiza cleanup automático al destruir el componente y evita leaks de animaciones activas apuntando a nodos del DOM ya removidos.
