#!/bin/bash
# PreToolUse Read|Bash|Grep|Glob — deniega .env reales (.env, .envrc, .env.*) salvo plantillas.
# Sin jq ni python3 falla cerrado: si el stdin menciona .env, deniega.
IFS= read -r -d '' INPUT || true

deny() {
  local reason="${1:-Los archivos .env reales (.env, .envrc, .env.*) tienen secretos y no se leen. Solo se permiten .env.example, .env.dist, .env.sample y .env.template.}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

HAVE_JQ=0; HAVE_PY=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1
# python3 puede ser el alias de la Microsoft Store (existe en el PATH pero no corre): se prueba que ejecute de verdad.
PYX=()
for cand in "python3" "python" "py -3"; do
  if $cand -c "import json, shlex" >/dev/null 2>&1; then read -r -a PYX <<<"$cand"; HAVE_PY=1; break; fi
done
if [ "$HAVE_JQ" = 0 ] && [ "$HAVE_PY" = 0 ]; then
  [[ "$INPUT" == *.env* ]] && deny
  exit 0
fi

field() {
  if [ "$HAVE_JQ" = 1 ]; then
    printf '%s' "$INPUT" | jq -r "$1 // \"\"" 2>/dev/null
  else
    printf '%s' "$INPUT" | "${PYX[@]}" -c '
import json, sys
d = json.load(sys.stdin)
for k in sys.argv[1].split(".")[1:]:
    d = d.get(k) if isinstance(d, dict) else None
print(d if isinstance(d, str) else "")' "$1" 2>/dev/null
  fi
}

# Windows: C:\a\b y C:/a/b → /c/a/b (forma de Git Bash). Pasar "\" a "/" solo endurece el chequeo en Linux.
winpath() {
  local p="${1//\\//}"
  [[ "$p" =~ ^([A-Za-z]):(/.*)?$ ]] && p="/${BASH_REMATCH[1],,}${BASH_REMATCH[2]}"
  printf '%s' "$p"
}

TOOL=$(field .tool_name)
CWD=$(winpath "$(field .cwd)")
[ -n "$CWD" ] || CWD="$PWD"

env_name_denied() {
  local b="${1%/}" l
  b="${b##*/}"
  case "$b" in
    .env.example|.env.dist|.env.sample|.env.template) return 1 ;;
  esac
  l="${b,,}"
  case "$l" in
    .env|.envrc|.env.*) return 0 ;;
  esac
  return 1
}

# Evalúa la ruta tal cual (contra cwd) y su resolución con symlinks.
env_denied() {
  local p abs real
  p=$(winpath "$1")
  [ -n "$p" ] || return 1
  case "$p" in
    "~"|"~/"*) p="$HOME${p#\~}" ;;
    '$HOME'*) p="$HOME${p#\$HOME}" ;;
    '${HOME}'*) p="$HOME${p#\$\{HOME\}}" ;;
  esac
  case "$p" in /*) abs="$p" ;; *) abs="$CWD/$p" ;; esac
  env_name_denied "$abs" && return 0
  real=$(realpath -m -- "$abs" 2>/dev/null) || real=""
  [ -n "$real" ] && env_name_denied "$real" && return 0
  return 1
}

expand_braces() {
  local s="$1" pre alt post p parts
  if [[ "$s" =~ ^(.*)\{([^{}]*)\}(.*)$ ]]; then
    pre="${BASH_REMATCH[1]}"; alt="${BASH_REMATCH[2]}"; post="${BASH_REMATCH[3]}"
    IFS=, read -ra parts <<<"$alt"
    for p in "${parts[@]}"; do expand_braces "$pre$p$post"; done
  else
    printf '%s\n' "$s"
  fi
}

# Un glob puede matchear un nombre denegado. Modo shell (default): "*" no matchea dotfiles, el glob debe empezar con ".".
# Modo rg ($2 = rg, Grep/Glob tools): "*" matchea dotfiles y se expanden {a,b}.
env_glob_denied() {
  local g="$1" mode="${2:-sh}" seg n hit=1 line
  local -a cands
  [ -n "$g" ] || return 1
  if [ "$mode" = rg ]; then mapfile -t cands < <(expand_braces "$g"); else cands=("$g"); fi
  shopt -s nocasematch
  for line in "${cands[@]}"; do
    seg="${line%/}"; seg="${seg##*/}"
    [ -n "$seg" ] || continue
    if [[ "$seg" != *[\*\?\[]* ]]; then
      env_name_denied "$seg" && hit=0
      continue
    fi
    [ "$mode" = rg ] || [[ "$seg" == .* ]] || continue
    for n in .env .env.local .env.production .env.x.local .envrc; do
      # shellcheck disable=SC2053
      [[ "$n" == $seg ]] && hit=0
    done
  done
  shopt -u nocasematch
  return $hit
}

# Búsqueda recursiva: deniega si el directorio tiene un .env real (nombre denegado, sin plantillas) que la búsqueda no excluye.
# $1 dir, $2 typed (1 = -t/--type/--ignore-file), $3 exclusiones y $4 positivos (un patrón por línea). Deja el nombre relativo en HIT.
HIT=""
glob_seg() { local g="${1%/}"; printf '%s' "${g##*/}"; }
TIMED_OUT=0; FILES=""
now_ms() {
  local t
  if [ -n "${EPOCHREALTIME:-}" ]; then t="${EPOCHREALTIME/[.,]/}"; echo $((t / 1000)); else echo $(($(date +%s) * 1000)); fi
}
DEADLINE_MS=$(($(now_ms) + 3500))
TIMEOUT_BIN=""
# Solo el timeout de coreutils: en Windows "timeout" puede ser timeout.exe, que no corre el comando (Git Bash trae el bueno en /usr/bin).
# Sin ninguno, tmo da 127 y la búsqueda recursiva se deniega.
for t in timeout gtimeout /usr/bin/timeout; do
  command -v "$t" >/dev/null 2>&1 || continue
  _v=$("$t" --version 2>/dev/null </dev/null) || _v=""
  [[ "$_v" == *coreutils* ]] && { TIMEOUT_BIN="$t"; break; }
done
unset _v
# Ejecuta "$@" con lo que queda del presupuesto global (máx. 2s por comando). rc 124 si el presupuesto se agotó; 127 sin timeout.
tmo() {
  local rem=$((DEADLINE_MS - $(now_ms)))
  [ -n "$TIMEOUT_BIN" ] || return 127
  [ "$rem" -gt 0 ] || return 124
  [ "$rem" -le 2000 ] || rem=2000
  "$TIMEOUT_BIN" "$((rem / 1000)).$(printf '%03d' $((rem % 1000)))" "$@"
}
# Lista los archivos candidatos a .env bajo $1 (rutas relativas). Dentro de un repo git usa ls-files (tracked, untracked e ignorados);
# fuera, find acotado. Cualquier vencimiento, binario ausente o rc inesperado deja TIMED_OUT=1 (el llamador deniega).
list_env_candidates() {
  local dir="$1" rc out out2 inrepo=0
  if command -v git >/dev/null 2>&1; then
    tmo git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; rc=$?
    case "$rc" in
      0) inrepo=1 ;;
      128|1) ;;
      *) TIMED_OUT=1; return ;;
    esac
  fi
  if [ "$inrepo" = 1 ]; then
    local -a ps=(':(glob,icase)**/.env*' ':(glob,icase)**/.envrc' ':(glob,icase).env*' ':(glob,icase).envrc' ':(exclude,glob)**/node_modules/**' ':(exclude,glob)**/vendor/**')
    out=$(tmo git -C "$dir" ls-files -co --exclude-standard -- "${ps[@]}" 2>/dev/null); rc=$?
    [ "$rc" -eq 0 ] || { TIMED_OUT=1; return; }
    out2=$(tmo git -C "$dir" ls-files --others --ignored --exclude-standard -- "${ps[@]}" 2>/dev/null); rc=$?
    [ "$rc" -eq 0 ] || { TIMED_OUT=1; return; }
    FILES=$(printf '%s\n%s\n' "$out" "$out2" | grep -iE '(^|/)\.env(rc|\..*)?$' | sort -u | head -n 50)
    return
  fi
  out=$(tmo find "$dir" -mindepth 1 -maxdepth 6 \( -name .git -o -name node_modules -o -name vendor \) -prune -o ! -type d \
    \( -iname .env -o -iname .envrc -o -iname '.env.*' \) -print 2>/dev/null | head -n 50; echo "rc=${PIPESTATUS[0]}")
  case "${out##*rc=}" in 0|1|141) ;; *) TIMED_OUT=1; return ;; esac
  FILES=$(printf '%s\n' "${out%rc=*}" | sed "s#^$dir/##")
}
# true si UNA exclusión (sin distinguir nada más que prefijo **/) cubre a la vez .env, .envrc y .env.<nombre cualquiera>:
# en la práctica .env*, **/.env* o *. Cualquier otra combinación obliga a listar los candidatos reales.
excl_covers_env() {
  local excl="$1" e p n all
  [ -n "$excl" ] || return 1
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    while IFS= read -r p; do
      while [[ "$p" == '**/'* ]]; do p="${p#'**/'}"; done
      [[ "$p" == */* ]] && continue
      all=1
      for n in .env .envrc .env.zq7x9nonce; do
        # shellcheck disable=SC2053
        [[ "$n" == $p ]] || { all=0; break; }
      done
      [ "$all" = 1 ] && return 0
    done < <(expand_braces "$e")
  done <<<"$excl"
  return 1
}
recursive_env_hit() {
  local dir="$1" typed="$2" excl="$3" pos="$4" f b e p ok matched
  [ -d "$dir" ] || return 1
  [ "$typed" = 1 ] && return 1
  TIMED_OUT=0; FILES=""
  excl_covers_env "$excl" && [ -z "$pos" ] && return 1
  list_env_candidates "$dir"
  [ "$TIMED_OUT" = 1 ] && return 0
  shopt -s nocasematch
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    b="${f##*/}"
    env_name_denied "$b" || continue
    ok=0
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      while IFS= read -r p; do
        # shellcheck disable=SC2053
        [[ "$b" == $(glob_seg "$p") ]] && ok=1
      done < <(expand_braces "$e")
    done <<<"$excl"
    if [ "$ok" = 0 ] && [ -n "$pos" ]; then
      matched=0
      while IFS= read -r e; do
        [ -n "$e" ] || continue
        while IFS= read -r p; do
          # shellcheck disable=SC2053
          [[ "$b" == $(glob_seg "$p") ]] && matched=1
        done < <(expand_braces "$e")
      done <<<"$pos"
      [ "$matched" = 0 ] && ok=1
    fi
    if [ "$ok" = 0 ]; then HIT="$f"; shopt -u nocasematch; return 0; fi
  done <<<"$FILES"
  shopt -u nocasematch
  return 1
}
deny_recursive() {
  local n="${HIT//[^A-Za-z0-9._\/-]/?}"
  [ "$TIMED_OUT" = 1 ] && n="no se pudo comprobar a tiempo"
  deny "Búsqueda recursiva sobre un directorio con .env real ($n). Reintentá excluyéndolo: grep -r --exclude='.env*' ..., rg -g '!.env*' ... o, en la tool Grep, glob: '!**/.env*'."
}
resolve_dir() {
  local p
  p=$(winpath "$1")
  case "$p" in
    "~"|"~/"*) p="$HOME${p#\~}" ;;
    '$HOME'*) p="$HOME${p#\$HOME}" ;;
  esac
  case "$p" in /*) printf '%s' "$p" ;; *) printf '%s' "$CWD/$p" ;; esac
}

case "$TOOL" in
  Read)
    env_denied "$(field .tool_input.file_path)" && deny
    ;;
  Grep)
    env_denied "$(field .tool_input.path)" && deny
    G=$(field .tool_input.glob)
    case "$G" in '!'*) ;; *) env_glob_denied "$G" rg && deny ;; esac
    GT=$(field .tool_input.type); GP=$(field .tool_input.path)
    [ -n "$GP" ] || GP="$CWD"
    EX=""; PO=""; TY=0
    [ -n "$GT" ] && [ -z "$G" ] && TY=1
    if [ -n "$G" ]; then case "$G" in '!'*) EX="${G#!}" ;; *) PO="$G" ;; esac; fi
    recursive_env_hit "$(resolve_dir "$GP")" "$TY" "$EX" "$PO" && deny_recursive
    ;;
  Glob)
    env_glob_denied "$(field .tool_input.pattern)" rg && deny
    ;;
  Bash)
    CMD=$(field .tool_input.command)
    if [ "$HAVE_PY" = 0 ]; then
      [[ "$CMD" == *.env* ]] && deny
      exit 0
    fi
    while IFS= read -r -d '' tok; do
      case "$tok" in
        $'\x04'*) deny "docker compose config imprime el .env interpolado (secretos). Usá config --no-interpolate, o --env-file /dev/null junto con --no-env-resolution." ;;
        $'\x05'*) deny "El comando ejecuta código de intérprete que menciona .env: eso puede leer secretos y no se permite. Si solo filtrás texto, evitá ejecutar código de intérprete que mencione .env; usá grep/jq sobre el archivo concreto." ;;
        $'\x02'*) env_denied "${tok#?}" && deny; continue ;;
        $'\x03'*)
          IFS=$'\x1f' read -r rdir rtyped rexcl rpos <<<"${tok#?}"
          rexcl="${rexcl//$'\x1e'/$'\n'}"; rpos="${rpos//$'\x1e'/$'\n'}"
          recursive_env_hit "$(resolve_dir "$rdir")" "$rtyped" "$rexcl" "$rpos" && deny_recursive
          continue ;;
      esac
      tok="${tok#[\"\'\`\(]}"; tok="${tok%[\"\'\`\)]}"
      [ -n "$tok" ] || continue
      cands=("$tok" "${tok##*=}")
      [[ "$tok" =~ ^-[A-Za-z]+(.+)$ ]] && cands+=("${BASH_REMATCH[1]}")
      if [[ "$tok" == *'{'*[,]*'}'* || "$tok" == *'{'*..*'}'* ]]; then
        while IFS= read -r b; do cands+=("$b"); done < <(expand_braces "$tok")
      fi
      if [[ "$tok" == *[\$\`]* || "$tok" == *'{'* || "$tok" == SUBST ]] && { [[ "${CMD,,}" == *env* ]] || [[ "${CMD,,}" =~ \.e($|[^a-z0-9_]) || "$CMD" =~ \.[\$\`\{] ]] || [[ "$CMD" =~ \\[x0u] || "$CMD" == *\$\'* ]]; }; then
        deny "Operando con variable, sustitución o llaves que puede expandirse a un .env en un comando que menciona env o escapes: no se puede verificar. Escribí el nombre de archivo literal."
      fi
      for cand in "${cands[@]}"; do
        while [[ "$cand" == [@\<:]* ]]; do cand="${cand#?}"; done
        if [[ "${cand,,}" == *.env* || "$cand" == *[\*\?\[]* || -L "$CWD/$cand" || -L "$cand" ]]; then
          env_denied "$cand" && deny
          [[ "$cand" == *[\*\?\[]* ]] && env_glob_denied "$cand" && deny
        fi
      done
    done < <(printf '%s' "$CMD" | "${PYX[@]}" -c '
import re, shlex, sys

EXEC_FLAGS = {"-c", "-lc", "-cl", "-ic", "-e", "--command"}

INTERP = re.compile(r"^(python|pypy)[0-9.]*$|^php[0-9.]*$|^(node|nodejs|perl|ruby|irb|awk|gawk|mawk|nawk|lua|luajit|deno|bun|rscript|tclsh|bash|sh|zsh|dash|ksh)$", re.I)
INTERP_LINE = re.compile(r"(^|[\s;&|(`])((python|pypy)[0-9.]*|php[0-9.]*|node|nodejs|perl|ruby|irb|awk|gawk|mawk|nawk|lua|luajit|deno|bun|rscript|tclsh|bash|sh|zsh|dash|ksh)(\s|$)", re.I)
ENV_TPL = re.compile(r"\.env\.(example|dist|sample|template)(?![A-Za-z0-9_])")
ENV_MENTION = re.compile(r"\.env(rc)?(?![A-Za-z0-9_])", re.I)

# Limite conocido: un literal partido dentro del codigo del interprete (open(".e"+"nv")) no se detecta; no hay analisis semantico.
# El guard frena lecturas accidentales del agente, no es un sandbox: no cubre nombres armados dinamicamente sin "env" literal (cat $(ls -A)).
def mentions_env(text):
    return bool(ENV_MENTION.search(ENV_TPL.sub("", text)))

def strip_heredocs(cmd):
    out, pend, hits, body, head = [], [], False, [], ""
    for line in cmd.split("\n"):
        if pend:
            if line.strip() == pend[0]:
                pend.pop(0)
                if not pend:
                    if INTERP_LINE.search(head) and mentions_env("\n".join(body)):
                        hits = True
                    body = []
            else:
                body.append(line)
            continue
        out.append(line)
        for m in re.finditer(r"(?<!<)<<(?!<)-?[ \t]*([\"\x27]?)([A-Za-z_][A-Za-z0-9_]*)\1", line):
            pend.append(m.group(2))
            head = line
    return "\n".join(out), hits

def split_subst(cmd):
    """Devuelve (comando sin sustituciones, [interiores])."""
    inner, buf, i, n = [], [], 0, len(cmd)
    while i < n:
        if cmd.startswith("$(", i):
            d, j = 1, i + 2
            while j < n and d:
                d += (cmd[j] == "(") - (cmd[j] == ")")
                j += 1
            inner.append(cmd[i + 2:j - 1 if d == 0 else j])
            buf.append(" SUBST ")
            i = j
        elif cmd[i] == "`":
            j = cmd.find("`", i + 1)
            j = n if j < 0 else j
            inner.append(cmd[i + 1:j])
            buf.append(" SUBST ")
            i = j + 1
        else:
            buf.append(cmd[i])
            i += 1
    return "".join(buf), inner

PUNCT = set("();<>|&")

def split_lines(cmd):
    """Newline y \\r sin entrecomillar separan comandos igual que ;. Imita las reglas de comillas de shlex."""
    out, i, n, q = [], 0, len(cmd), ""
    while i < n:
        c = cmd[i]
        if q == "\x27":
            q = "" if c == "\x27" else q
        elif q == "\"":
            if c == "\\" and i + 1 < n and cmd[i + 1] == "\n":
                i += 2
                continue
            if c == "\\" and i + 1 < n:
                out.append(c)
                i += 1
                c = cmd[i]
            elif c == "\"":
                q = ""
        elif c in "\x27\"":
            q = c
        elif c == "\\" and i + 1 < n:
            if cmd[i + 1] == "\n":
                i += 2
                continue
            out.append(c)
            i += 1
            c = cmd[i]
        elif c in "\n\r":
            c = " ; "
        out.append(c)
        i += 1
    return "".join(out)

def long_rec(name, val):
    """GNU grep acepta prefijos unicos de opciones largas: --rec, --dir=rec."""
    if len(name) >= 4 and ("--recursive".startswith(name) or "--dereference-recursive".startswith(name)):
        return True
    return len(name) >= 4 and "--directories".startswith(name) and bool(val) and "recurse".startswith(val)

def dir_abbr(name):
    return len(name) >= 4 and "--directories".startswith(name)
VAL_SHORT = {"grep": "efABCmdD", "egrep": "efABCmdD", "fgrep": "efABCmdD", "rg": "efABCmgtTjdEMr", "ag": "efABCmGg", "ack": "ABCmg"}
VAL_LONG = {"--include", "--exclude", "--exclude-dir", "--exclude-from", "--regexp", "--file", "--max-count", "--after-context",
            "--before-context", "--context", "--glob", "--iglob", "--type", "--type-not", "--ignore-file", "--max-depth",
            "--replace", "--ignore", "--pager", "--path-to-ignore", "--binary-files", "--devices", "--directories"}
GIT_REV = {"show", "cat-file", "archive", "grep"}
WRAP = {"sudo", "time", "nice", "command", "nohup", "env"}

def search_record(cmd, args, forced=False):
    """Registro \x03 si la búsqueda es recursiva; None si no."""
    shorts = VAL_SHORT.get(cmd, "")
    rec = forced or cmd in ("rg", "ag", "ack")
    excl, pos, typed, operands = [], [], 0, []
    have_pat = False
    i, n, done = 0, len(args), False
    while i < n:
        a = args[i]
        i += 1
        if done or not a.startswith("-") or a == "-":
            operands.append(a)
            continue
        if a == "--":
            done = True
            continue
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if not eq and (name in VAL_LONG or dir_abbr(name)) and i < n:
                val = args[i]
                i += 1
            if cmd in ("grep", "egrep", "fgrep") and long_rec(name, val):
                rec = True
            elif name in ("--regexp", "--file"):
                have_pat = True
            elif name == "--files":
                have_pat = True
            elif name in ("--exclude", "--ignore"):
                excl.append(val)
            elif name == "--include":
                pos.append(val)
            elif name in ("--glob", "--iglob"):
                (excl.append(val[1:]) if val.startswith("!") else pos.append(val))
            elif name in ("--type", "--ignore-file"):
                typed = 1
            continue
        j = 1
        while j < len(a):
            c = a[j]
            if cmd in ("grep", "egrep", "fgrep") and c in "rR":
                rec = True
            if c in shorts:
                val = a[j + 1:]
                if not val and i < n:
                    val = args[i]
                    i += 1
                if c == "d" and cmd in ("grep", "egrep", "fgrep") and val and "recurse".startswith(val):
                    rec = True
                if c in "ef":
                    have_pat = True
                if c == "g" and cmd == "rg":
                    (excl.append(val[1:]) if val.startswith("!") else pos.append(val))
                if c == "t" and cmd == "rg":
                    typed = 1
                break
            j += 1
    if not rec:
        return None
    if not have_pat and operands:
        operands = operands[1:]
    if not operands:
        operands = ["."]
    sep = "\x1f"
    return ["\x03" + sep.join([d, str(typed), "\x1e".join(excl), "\x1e".join(pos)]) for d in operands]

SANITIZE_LONG = ("--exclude", "--include", "--glob", "--iglob", "--ignore")

def sanitize(words, lo, hi):
    """Las exclusiones/inclusiones de una búsqueda no son rutas: se neutralizan para el chequeo por token."""
    for k in range(lo, hi):
        w = words[k]
        if w.startswith(tuple(x + "=" for x in SANITIZE_LONG)):
            words[k] = "--opt"
        elif k > lo and (words[k - 1] in SANITIZE_LONG or words[k - 1] == "-g"):
            words[k] = "X"

COMPOSE_VAL = {"-f", "--file", "-p", "--project-name", "--profile", "--env-file", "--project-directory", "--ansi", "--parallel",
               "--progress", "-H", "--host", "--context", "-c", "--log-level", "--config"}

def compose_config_leak(seg):
    """Token \x04 si es `docker [compose] config` que imprime el .env interpolado."""
    name = seg[0].rsplit("/", 1)[-1]
    if name == "docker-compose":
        args = seg[1:]
    elif name == "docker" and "compose" in seg:
        args = seg[seg.index("compose") + 1:]
    else:
        return None
    j, envnull = 0, False
    while j < len(args) and args[j].startswith("-"):
        a = args[j]
        if a == "--env-file" and j + 1 < len(args):
            envnull = envnull or args[j + 1] == "/dev/null"
        elif a == "--env-file=/dev/null":
            envnull = True
        j += 2 if (a in COMPOSE_VAL) else 1
    if j >= len(args) or args[j] not in ("config", "convert"):
        return None
    flags, out, m, rest = set(), False, j + 1, args
    while m < len(rest):
        a = rest[m]
        m += 1
        if a in ("-o", "--output", "--format", "--hash"):
            out = out or a in ("-o", "--output")
            m += 1
        elif a.startswith("--output=") or (a.startswith("-o") and len(a) > 2 and not a.startswith("--")):
            out = True
        elif not a.startswith(("--format=", "--hash=")):
            flags.add(a)
    if "--environment" in flags:
        return "\x04"
    if "--no-interpolate" in flags or ("--no-env-resolution" in flags and envnull and not out):
        return None
    return "\x04"

RISKY = {"xargs", "eval", "source", ".", "bash", "sh", "zsh", "dash", "ksh", "parallel", "exec", "read"}
FIND_EXEC = {"-exec", "-execdir", "-ok", "-okdir"}

def plain_search(cmd, args, cwd):
    """grep/egrep/fgrep/rg no recursivos: [(indice, reemplazo)] de los patrones (no son rutas); None si hay recursion o duda."""
    shorts = VAL_SHORT[cmd]
    have_pat, targets, operands, i, n, done = False, [], [], 0, len(args), False
    while i < n:
        a = args[i]
        i += 1
        if done or not a.startswith("-") or a == "-":
            operands.append(i - 1)
            continue
        if a == "--":
            done = True
            continue
        if a.startswith("--"):
            name, eq, val = a.partition("=")
            if not eq and (name in VAL_LONG or dir_abbr(name)) and i < n:
                val = args[i]
                i += 1
            if cmd != "rg" and long_rec(name, val):
                return None
            if name == "--regexp":
                have_pat = True
                targets.append((i - 1, "--opt") if eq else (i - 1, "X"))
            elif name in ("--file", "--files"):
                have_pat = True
            continue
        j = 1
        while j < len(a):
            c = a[j]
            if cmd != "rg" and c in "rR":
                return None
            if c in shorts:
                val = a[j + 1:]
                dv = val or (args[i] if i < n else "")
                if c == "d" and cmd != "rg" and dv and "recurse".startswith(dv):
                    return None
                if not val and i < n:
                    val = args[i]
                    i += 1
                    if c == "e":
                        targets.append((i - 1, "X"))
                elif c == "e":
                    targets.append((i - 1, a[:j + 1] + "X"))
                if c in "ef":
                    have_pat = True
                break
            j += 1
    if not have_pat:
        if not operands:
            return None
        targets.append((operands[0], "X"))
        operands = operands[1:]
    if cmd == "rg":
        if not operands:
            return None
        for o in operands:
            f = os.path.expanduser(args[o])
            if os.path.isdir(f if os.path.isabs(f) else os.path.join(CWD, f)):
                return None
    return targets

def git_text_args(sub, args):
    """git commit -m / git log --grep: el valor es texto, no ruta."""
    out, i, n = [], 0, len(args)
    while i < n:
        a = args[i]
        i += 1
        if a == "--":
            break
        if sub == "log" and a.startswith("--grep="):
            out.append((i - 1, "--grep=X"))
        elif sub == "log" and a == "--grep" and i < n:
            out.append((i, "X"))
            i += 1
        elif sub == "commit" and a.startswith("--message="):
            out.append((i - 1, "--message=X"))
        elif sub == "commit" and a == "--message" and i < n:
            out.append((i, "X"))
            i += 1
        elif sub == "commit" and a.startswith("-") and not a.startswith("--") and "m" in a:
            k = a.index("m")
            if not all(ch in "aqvnsepu" for ch in a[1:k]):
                continue
            if k == len(a) - 1 and i < n:
                out.append((i, "X"))
                i += 1
            elif k < len(a) - 1:
                out.append((i - 1, a[:k + 1] + "X"))
    return out

def analyze(words, depth=0):
    bounds, start = [], 0
    for idx, w in enumerate(words):
        if w and all(ch in PUNCT for ch in w):
            bounds.append((start, idx))
            start = idx + 1
    bounds.append((start, len(words)))
    out = []
    risky = depth > 0 or "SUBST" in words or any(w in FIND_EXEC for w in words)
    paren = any("(" in w or ")" in w for w in words if w and all(ch in PUNCT for ch in w))
    for lo, hi in bounds:
        seg = words[lo:hi]
        k = 0
        while k < len(seg) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[k]) or seg[k] in WRAP):
            k += 1
        if k < len(seg) and seg[k].rsplit("/", 1)[-1] in RISKY:
            risky = True
    for lo, hi in bounds:
        seg = words[lo:hi]
        k = 0
        while k < len(seg) and (re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[k]) or seg[k] in WRAP):
            k += 1
        if k >= len(seg):
            continue
        base = lo + k
        seg = seg[k:]
        name = seg[0].rsplit("/", 1)[-1]
        if not risky:
            nxt = words[hi] if hi < len(words) else ""
            ups = []
            if name in ("echo", "printf") and not paren and not any(c in nxt for c in "|<>"):
                ups = [(q, "X") for q in range(1, len(seg))]
            elif name in ("grep", "egrep", "fgrep", "rg"):
                ups = plain_search(name, seg[1:], CWD) or []
                ups = [(q + 1, r) for q, r in ups]
            elif name == "git":
                j = 1
                while j < len(seg) and seg[j].startswith("-"):
                    j += 2 if seg[j] in ("-C", "-c", "--git-dir", "--work-tree") else 1
                if j < len(seg) and seg[j] in ("commit", "log"):
                    ups = [(q + j + 1, r) for q, r in git_text_args(seg[j], seg[j + 1:])]
            for q, r in ups:
                words[base + q] = r
        for q, w in enumerate(seg):
            if w.rsplit("/", 1)[-1] in ("docker", "docker-compose"):
                leak = compose_config_leak(seg[q:])
                if leak:
                    out.append(leak)
                break
        if name == "git":
            j = 1
            while j < len(seg) and seg[j].startswith("-"):
                j += 2 if seg[j] in ("-C", "-c", "--git-dir", "--work-tree") else 1
            if j < len(seg) and seg[j] in GIT_REV:
                sub = seg[j]
                for w in seg[j + 1:]:
                    if ":" in w:
                        out.append("\x02" + w.rsplit(":", 1)[1])
                if sub == "grep" and any(w in ("--untracked", "--no-index") for w in seg[j + 1:]):
                    out += search_record("grep", seg[j + 1:], forced=True) or []
        elif name in VAL_SHORT:
            out += search_record(name, seg[1:]) or []
            sanitize(words, base, hi)
    return out

def collect(cmd, depth=0):
    if depth > 5:
        return []
    body, hd = strip_heredocs(cmd)
    cmd, inner = split_subst(body)
    cmd = split_lines(cmd)
    toks = ["\x05"] if hd else []
    for sub in inner:
        toks += collect(sub, depth + 1)
    lx = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lx.whitespace_split = True
    lx.commenters = ""
    words = list(lx)
    if any(INTERP.match(w.rsplit("/", 1)[-1]) for w in words) and any(mentions_env(w) for w in words):
        toks.append("\x05")
    toks += analyze(words, depth)
    for k, w in enumerate(words):
        toks.append(w)
        if k and (words[k - 1] in EXEC_FLAGS or words[k - 1] == "eval") and re.search(r"\s", w):
            toks += collect(w, depth + 1)
    return toks

import os
CWD = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else os.getcwd()
cmd = sys.stdin.read()
try:
    out = collect(cmd)
except ValueError:
    out = [".env"] if ".env" in cmd else []
sys.stdout.write("".join(t + "\0" for t in out))
' "$CWD" 2>/dev/null)
    ;;
esac
exit 0
