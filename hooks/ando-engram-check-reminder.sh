#!/bin/bash
# ando-engram-check-reminder.sh — Hook UserPromptSubmit
#
# Recuerda consultar Engram antes de decir "no tengo contexto de esto". Se
# dispara en cada mensaje del usuario. Inyecta additionalContext (NO visible
# al usuario, solo refuerzo interno) para reforzar la regla de memoria: antes
# de afirmar falta de contexto, correr mem_search en Engram.

echo '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": "Si el usuario menciona algo específico (un proceso, una convención propia, un pedido recurrente) que no reconocés de inmediato, corré mem_search en Engram ANTES de decir que no tenés contexto — puede estar ya documentado."}}'
exit 0
