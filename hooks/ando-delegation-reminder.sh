#!/bin/bash
# ando-delegation-reminder.sh — Hook UserPromptSubmit
#
# Detecta de qué trata el mensaje del usuario y recuerda qué skill/agent de
# ando-kit debería manejarlo, en vez de hacerlo a mano en el contexto
# principal. Si no matchea ninguna categoría, no dice nada (no es ruido en
# cada mensaje, solo cuando aplica).
#
# Reemplaza al recordatorio genérico anterior por uno consciente de
# keywords, mapeado al roster real de ando-kit. Podés desactivarlo con
# ANDO_DELEGATION_REMINDER_DISABLED=1.
#
# El hook nunca debe romper el flujo principal: cualquier fallo termina en
# exit 0 sin imprimir nada.

set -uo pipefail

if [ "${ANDO_DELEGATION_REMINDER_DISABLED:-0}" = "1" ]; then
    exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

MESSAGE=$(echo "$INPUT" | jq -r '.prompt // .message // ""' 2>/dev/null | tr '[:upper:]' '[:lower:]')
[ -z "$MESSAGE" ] && exit 0

HINTS=()

# --- Revisión de PR/MR ---
if echo "$MESSAGE" | grep -qE '\b(pr|mr|pull.?request|merge.?request|diff)\b.*\b(revis|review)|revis[aá].*\b(pr|mr)\b'; then
  HINTS+=("skill pr-review o agente pr-analyst → analizar el PR/MR completo. No leer el diff crudo en el contexto principal.")
fi

# --- Seguridad ---
if echo "$MESSAGE" | grep -qE '\b(xss|csrf|sql.?inject|seguridad|security|vuln|secrets?|csp)\b'; then
  HINTS+=("agente security-auditor → auditar antes de commitear. No hacer la auditoría vos mismo.")
fi

# --- Documentación ---
if echo "$MESSAGE" | grep -qE '\b(documenta|readme|claude\.md|arquitectura|architecture)\b'; then
  HINTS+=("agente doc-writer (+ skill cognitive-doc-design para la forma del doc) → generar la documentación en vez de escribirla directo en el contexto principal.")
fi

# --- Repo desconocido / onboarding ---
if echo "$MESSAGE" | grep -qE '\b(repo.?nuevo|no.?conozco.?(este|el).?(repo|c[oó]digo|proyecto)|onboard|primera.?vez|entender.?el.?(repo|c[oó]digo|proyecto)|c[oó]mo.?est[aá].?armado)\b'; then
  HINTS+=("skill codebase-onboard → recorrido guiado (estructura, stack, flujos, convenciones) antes de tocar código; opcionalmente genera un CLAUDE.md.")
fi

# --- Frontend / componentes / estilos ---
if echo "$MESSAGE" | grep -qE '\.(vue|jsx|tsx|svelte)\b|\b(componente|component|css|scss|estilos?|accesibilidad|a11y|render|re.?render|vuex|redux|pinia|store)\b'; then
  HINTS+=("agente frontend-reviewer → revisar componentes/estilos (estado, contratos de props/eventos, a11y, rendering). No hacer la revisión en el contexto principal.")
fi

# --- Changelog / release ---
if echo "$MESSAGE" | grep -qE '\b(changelog|release|notas.?de.?versi[oó]n|historial.?de.?cambios|bump.?de.?versi[oó]n)\b'; then
  HINTS+=("agente changelog-writer + skill kit-bump → generar el CHANGELOG y el bump de versión. No leer git log completo en el contexto principal.")
fi

# --- Deploy / pre-push ---
if echo "$MESSAGE" | grep -qE '\b(pre.?deploy|listo.?para.?(pr|mr|push)|antes.?del.?(pr|mr|push)|hacer.?push)\b'; then
  HINTS+=("agente deploy-checker → validar todo antes del push/PR. No correr los checks a mano.")
fi

# --- Hotfix ---
if echo "$MESSAGE" | grep -qE '\bhotfix\b|arreglo.?urgente|fix.?urgente.?a.?produc'; then
  HINTS+=("skill hotfix-flow → branch desde el tag de producción, no desde main.")
fi

# --- Conflicto de versión ---
if echo "$MESSAGE" | grep -qE 'conflicto.*(versi[oó]n|composer|package\.json)|version.*conflict'; then
  HINTS+=("skill resolve-version-conflict → resolver el conflicto en el archivo de versión.")
fi

# --- Historial git ---
if echo "$MESSAGE" | grep -qE '\b(historial|git.?log|qu[eé].?cambi[oó]|qui[eé]n.?toc[oó]|blame)\b'; then
  HINTS+=("agente git-historian → resumir el historial. No correr git log -p en el contexto principal.")
fi

# --- Investigación de bugs ---
if echo "$MESSAGE" | grep -qE '\b(investig|debug|por.?qu[eé].?falla|por.?qu[eé].?no.?funciona|ra[ií]z.?del.?problema|causa.?del.?bug|bug)\b'; then
  HINTS+=("skill investigar-bug → guía el flujo sistemático. No empezar a explorar código sin este skill.")
fi

# --- Implementación nueva (feature/fix) → evaluar el Paso 0 del flujo SDD ---
if echo "$MESSAGE" | grep -qE '\b(implement[aá]|hac[eé]lo|cre[aá]|agrega|nueva.?feature|nuevo.?m[oó]dulo|escrib[ií].?el.?c[oó]digo|dise[ñn]ar|antes.?de.?implementar|qu[eé].?approach|sdd|spec)\b'; then
  HINTS+=("Flujo SDD Paso 0: ANTES de tocar código, evaluá si la tarea es no trivial (comportamiento nuevo / contrato / lógica de negocio / migración / seguridad / 3+ archivos). Si lo es → arrancá vos el skill sdd-start (no esperes que el usuario tipee /sdd-start); la spec es requerida y no se implementa/pushea sin status: approved. Si es trivial → seguí directo y decilo en una línea.")
fi

# --- Testing / integración ---
if echo "$MESSAGE" | grep -qE '\b(prob[aá]|test|verific[aá]|que.?funciona|flujo.?completo|end.?to.?end|e2e|integraci[oó]n)\b'; then
  HINTS+=("agente integration-test-runner → probar en container con estado antes/después. No armar el script ad-hoc en el contexto principal.")
fi

# --- Flujos asíncronos ---
if echo "$MESSAGE" | grep -qE '\b(cola|queue|worker|evento.?asincr|async.?flow|sqs|pub.?sub)\b'; then
  HINTS+=("agente async-flow-verifier → verificar el pipeline queue→worker→sink por checkpoints, no inspeccionar colas/logs a mano.")
fi

# --- BD / base de datos ---
if echo "$MESSAGE" | grep -qE '\b(restaur[aá].*(base|db)|import[aá].*dump|pis[aá].*(base|db))\b'; then
  HINTS+=("skill db-restore → import con backup previo y confirmación antes de cualquier DROP.")
fi
if echo "$MESSAGE" | grep -qE '\b(query|consulta.?sql|revis[aá].*(tabla|fila|registro)|estado.?en.?(la.?)?(base|db|bd)|backup.?de.?(la.?)?(base|db|bd))\b'; then
  HINTS+=("agente db-analyst → queries read-only o backup en una DB local, sin volcar el resultset al contexto principal. Para restore destructivo, skill db-restore.")
fi

# --- Revisión adversarial / crítica ---
if echo "$MESSAGE" | grep -qE '\b(revisi[oó]n.?adversarial|doubt.?driven|judgment.?day|juzg|revisi[oó]n.?dual)\b'; then
  HINTS+=("skill doubt-driven (revisor único con contexto fresco) o judgment-day (dos jueces ciegos en paralelo) según el nivel de riesgo del cambio.")
fi

# --- Revisión proporcional al riesgo (RDD) ---
if echo "$MESSAGE" | grep -qE '\b(rdd|receipt.?driven|revis[aá].*(diff|branch|rama)|revisi[oó]n.*proporcional)\b'; then
  HINTS+=("skill rdd-review → congela el diff, clasifica riesgo Bajo/Medio/Alto y escala 0/1/4 lentes. Informacional, no bloquea.")
fi

# --- Retomar trabajo ajeno ---
if echo "$MESSAGE" | grep -qE '\b(handoff|retom[aá]|agarr[aá].*(ticket|rama|branch|lo.?que.?dej[oó])|contexto.?de.?(la.?rama|el.?ticket))\b'; then
  HINTS+=("skill handoff → arma en un paso el contexto completo (ticket + PR/branch + historial git + spec) para agarrar trabajo de otra persona.")
fi

# --- Qué testear / estrategia de tests ---
if echo "$MESSAGE" | grep -qE '\b(qu[eé].?test|estrategia.?de.?test|plan.?de.?test|qu[eé].?cubrir|cobertura.?de.?test)\b'; then
  HINTS+=("agente test-strategist → decide qué testear y con qué prioridad ANTES de escribir el primer test, dada la spec aprobada.")
fi

# --- Comentarios de PR/issue ---
if echo "$MESSAGE" | grep -qE '\b(comentario|coment[aá]).*(pr|mr|issue|review)'; then
  HINTS+=("skill comment-writer → redactar el comentario con el tono/formato correcto.")
fi

if [ ${#HINTS[@]} -gt 0 ]; then
  # Construir la lista con \n literal (dos caracteres, no un salto de línea real)
  # para que sea un escape JSON válido al interpolarla en additionalContext —
  # `printf '\n'` interpretaría el salto de línea de verdad y rompería el JSON.
  HINT_LIST=""
  for h in "${HINTS[@]}"; do
    HINT_LIST="${HINT_LIST}\\n  • ${h}"
  done
  printf '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "Antes de hacer esto en el contexto principal, evaluá delegar:%s"}}\n' "$HINT_LIST"
fi

exit 0
