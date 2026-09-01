#!/usr/bin/env bash
# Shared by both hooks, sourced. They must compute the baseline identically:
# if they ever disagreed, the Stop hook would compare against a baseline it
# cannot reproduce and ask for a report at the start of every session.

OS_MAX_REPOS="${OPEN_STEPS_MAX_REPOS:-25}"

# Session id from a hook payload; constant fallback, never empty.
os_session_id() { # $1 = raw payload
  OS_SESSION="$(printf '%s' "${1:-}" \
    | grep -oE '"session_id"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/')"
  : "${OS_SESSION:=nosession}"
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
OS_SELF_WRITTEN=(':(exclude)ROADMAP.md')

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

# shellcheck disable=SC2034  # OS_PREV_* are read by the sourcing hook
os_read_state() {
  OS_PREV_SESSION=""; OS_PREV_FINGERPRINT=""; OS_PREV_HEADS=""; OS_PREV_FIRED_AT=0
  [ -f "$OS_STATE_FILE" ] || return 0
  # shellcheck disable=SC1090
  . "$OS_STATE_FILE" 2>/dev/null || true
  OS_PREV_SESSION="${OS_STATE_SESSION:-}"
  OS_PREV_FINGERPRINT="${OS_STATE_FINGERPRINT:-}"
  OS_PREV_HEADS="${OS_STATE_HEADS:-}"
  OS_PREV_FIRED_AT="${OS_STATE_FIRED_AT:-0}"
}

os_save_state() { # $1 = timestamp of the last report request
  mkdir -p "$OS_STATE_DIR" 2>/dev/null || return 1
  {
    printf 'OS_STATE_SESSION=%s\n' "$OS_SESSION"
    printf 'OS_STATE_FINGERPRINT=%s\n' "$OS_FINGERPRINT"
    printf 'OS_STATE_HEADS=%s\n' "$OS_HEADS"
    printf 'OS_STATE_FIRED_AT=%s\n' "${1:-0}"
  } > "$OS_STATE_FILE"
}
