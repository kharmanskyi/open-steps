#!/usr/bin/env bash
# Shared by both hooks, sourced. They must compute the baseline identically:
# if they ever disagreed, the Stop hook would compare against a baseline it
# cannot reproduce and ask for a report at the start of every session.

OS_MAX_REPOS="${OPEN_STEPS_MAX_REPOS:-25}"

# Session id from a hook payload; constant fallback, never empty. The id comes
# from another program and ends up in the state file, so it is kept only when
# it is a plain identifier. Anything else becomes the fallback.
OS_SESSION_PATTERN='^[A-Za-z0-9._:-]{1,128}$'
os_session_id() { # $1 = raw payload
  local id
  id="$(printf '%s' "${1:-}" \
    | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
  if [[ "$id" =~ $OS_SESSION_PATTERN ]]; then
    OS_SESSION="$id"
  else
    OS_SESSION="nosession"
  fi
}

# The working directory's repository, or every repository one level below it
# (a hub of checkouts). Deeper nesting is not scanned.
os_find_repos() { # sets OS_REPOS, OS_SCOPE
  OS_REPOS=()
  local root sub entry count=0
  if root="$(git rev-parse --show-toplevel 2>/dev/null)" && [ -n "$root" ]; then
    OS_REPOS=("$root")
    OS_SCOPE="$(basename "$root")"
    return 0
  fi
  OS_SCOPE="$(basename "$PWD")"
  for entry in */; do
    [ -e "${entry}.git" ] || continue   # dir or file: worktrees too
    sub="$(git -C "$entry" rev-parse --show-toplevel 2>/dev/null)" || continue
    [ -n "$sub" ] || continue
    OS_REPOS+=("$sub")
    count=$((count + 1))
    [ "$count" -ge "$OS_MAX_REPOS" ] && break
  done
}

# Files this pack writes into the project itself. They are excluded from the
# fingerprint for the same reason reports live outside the repository: writing
# one must never look like work landing, or the map the agent just updated
# asks for a report about itself once the cooldown expires.
OS_SELF_WRITTEN=(':(exclude)BIG-PICTURE.md')

# HEAD plus dirty-file content per repository. Content, not just names:
# `git status --porcelain` alone cannot see a file edited twice.
os_fingerprint() { # sets OS_FINGERPRINT, OS_HEADS, OS_DIRTY, OS_CHANGED
  OS_FINGERPRINT=""; OS_HEADS=""; OS_DIRTY=0; OS_CHANGED=""
  [ "${#OS_REPOS[@]}" -eq 0 ] && return 0
  local parts="" r head dirty n content
  for r in "${OS_REPOS[@]}"; do
    head="$(git -C "$r" rev-parse HEAD 2>/dev/null || echo none)"
    dirty="$(git -C "$r" status --porcelain -- . "${OS_SELF_WRITTEN[@]}" 2>/dev/null || true)"
    n="$(printf '%s' "$dirty" | grep -c . || true)"
    : "${n:=0}"
    content="$(git -C "$r" diff HEAD -- . "${OS_SELF_WRITTEN[@]}" 2>/dev/null || true)"
    parts="$parts|$r:$head:$(printf '%s\n%s' "$dirty" "$content" | cksum | tr -d ' ')"
    OS_DIRTY=$((OS_DIRTY + n))
    [ "$n" -gt 0 ] && OS_CHANGED="$OS_CHANGED $(basename "$r")"
  done
  OS_FINGERPRINT="$(printf '%s' "$parts" | cksum | tr -d ' ')"
  OS_HEADS="$(printf '%s' "$parts" | grep -oE ':[0-9a-f]{40}:' | tr -d '\n')"
}

os_state_paths() { # sets OS_STATE_DIR, OS_STATE_FILE
  OS_STATE_DIR="$HOME/.claude/open-steps/reports/${OS_SCOPE:-unknown}"
  OS_STATE_FILE="$OS_STATE_DIR/.stop-state"
}

# Every value in the state file is a session id, a checksum, commit hashes or
# a timestamp, so each one fits this set. The file is read line by line, never
# run as a script, and a value outside the set is ignored. That also covers a
# file written by an older version of these hooks.
OS_STATE_VALUE='^[A-Za-z0-9._:-]*$'

# shellcheck disable=SC2034  # OS_PREV_* are read by the sourcing hook
os_read_state() {
  OS_PREV_SESSION=""; OS_PREV_FINGERPRINT=""; OS_PREV_HEADS=""; OS_PREV_FIRED_AT=0
  [ -f "$OS_STATE_FILE" ] || return 0
  local key value
  while IFS='=' read -r key value || [ -n "$key" ]; do
    [[ "$value" =~ $OS_STATE_VALUE ]] || continue
    case "$key" in
      OS_STATE_SESSION) OS_PREV_SESSION="$value" ;;
      OS_STATE_FINGERPRINT) OS_PREV_FINGERPRINT="$value" ;;
      OS_STATE_HEADS) OS_PREV_HEADS="$value" ;;
      OS_STATE_FIRED_AT) [[ "$value" =~ ^[0-9]+$ ]] && OS_PREV_FIRED_AT="$value" ;;
    esac
  done 2>/dev/null < "$OS_STATE_FILE"
}

os_state_line() { # $1 = key, $2 = value; a value outside the set is left empty
  if [[ "$2" =~ $OS_STATE_VALUE ]]; then
    printf '%s=%s\n' "$1" "$2"
  else
    printf '%s=\n' "$1"
  fi
}

os_save_state() { # $1 = timestamp of the last report request
  mkdir -p "$OS_STATE_DIR" 2>/dev/null || return 1
  local fired="${1:-0}"
  [[ "$fired" =~ ^[0-9]+$ ]] || fired=0
  {
    os_state_line OS_STATE_SESSION "$OS_SESSION"
    os_state_line OS_STATE_FINGERPRINT "$OS_FINGERPRINT"
    os_state_line OS_STATE_HEADS "$OS_HEADS"
    os_state_line OS_STATE_FIRED_AT "$fired"
  } > "$OS_STATE_FILE"
}
