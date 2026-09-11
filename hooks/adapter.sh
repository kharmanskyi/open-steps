#!/usr/bin/env bash
# Adapter for tools that want JSON on stdout where the two hooks print text.
# One copy of the hook logic: this script runs session-start.sh or
# stop-report.sh unchanged and only translates what goes in and what comes out.
#
#   adapter.sh cursor session-start     wraps the handover as additional_context
#   adapter.sh cursor stop              asks for the report as followup_message
#   adapter.sh gemini session-start     wraps the handover as additionalContext
#   adapter.sh gemini stop              refuses the turn: decision deny, reason
#
# Cursor's contract, the parts that matter here:
# - Both events must answer with JSON; anything else counts as a hook failure.
# - A stop cannot be blocked. The one thing it can do is hand Cursor a
#   followup_message, which Cursor submits as the next user message, at most
#   loop_limit times per conversation (5 unless configured).
# - The stop payload has no session_id, only conversation_id. The baseline is
#   keyed by session, so both events use conversation_id here, or the stop
#   would never find the baseline the start took.
# - A stop reports its status. Only a completed stop is asked for a report:
#   after an abort or an error the change stays pending for the next one,
#   and nobody gets an unrequested message submitted on their behalf.
#
# Gemini CLI's contract, the parts that matter here:
# - JSON on stdout too, and nothing else.
# - Every event carries session_id, and GEMINI_SESSION_ID is set on every
#   hook: the payload's is used, the variable when the payload has none.
# - The stop side is AfterAgent, not SessionEnd. SessionEnd is best effort and
#   ignores flow control, so a report asked for from there is never asked
#   for. AfterAgent fires after each final response and takes decision "deny"
#   with a reason, which goes back to the agent as the next prompt. That is
#   what exit 2 with stderr does elsewhere, so the stop keeps its refusal.
# - GEMINI_PROJECT_DIR is set on every hook, and the payload carries cwd.
# - The retry after a deny arrives with stop_hook_active true. It is let
#   through without asking, whatever landed in it: denying the retry is the
#   one way to loop.
# - Its file tool refuses paths outside the workspace, and the reports folder
#   is outside it, while its shell tool is not limited. The reason says so,
#   or the report lands in Gemini's temp folder where no session reads it.
#
# The settings and kill switches of the two scripts apply unchanged, because
# the scripts read them, not this adapter.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool="${1:-}"
event="${2:-}"

usage() {
  printf 'usage: adapter.sh cursor|gemini session-start|stop\n' >&2
  exit 1
}

case "$tool" in cursor|gemini) ;; *) usage ;; esac
case "$event" in session-start|stop) ;; *) usage ;; esac

payload="$(cat 2>/dev/null || true)"

# One string field out of a flat JSON payload, the same way fingerprint.sh
# reads session_id. Good enough for the identifiers these tools send.
field() { # $1 = key
  printf '%s' "$payload" \
    | grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# True when a boolean field is true.
flag() { # $1 = key
  printf '%s' "$payload" | grep -qE "\"$1\"[[:space:]]*:[[:space:]]*true"
}

# A JSON string literal, quotes included. Control characters other than
# newline, tab and return are dropped rather than escaped: none of them can
# appear in what these hooks print. Backslash and quote go through sed, not
# bash's own substitution, because bash 3.2 (macOS /bin/bash) reads a quoted
# replacement differently from bash 4.3 and later and would leave the
# backslash single. LC_ALL=C so a stray non-UTF-8 byte is passed through
# rather than making tr stop early.
json_string() { # $1 = text
  local s
  s="$(printf '%s' "$1" \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037' \
    | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  s=${s//$'\n'/\\n}
  s=${s//$'\t'/\\t}
  s=${s//$'\r'/\\r}
  printf '"%s"' "$s"
}

# The hooks look for the repository from the working directory. Each tool
# names the project on every hook, Cursor in CURSOR_PROJECT_DIR, Gemini CLI in
# GEMINI_PROJECT_DIR and in the payload's cwd; follow it when it is there.
case "$tool" in
  cursor) dir="${CURSOR_PROJECT_DIR:-}" ;;
  gemini) dir="${GEMINI_PROJECT_DIR:-}"; [ -n "$dir" ] || dir="$(field cwd)" ;;
esac
[ -n "$dir" ] && cd "$dir" 2>/dev/null || true

# The session id the hooks will see. Cursor: conversation_id, the one field
# present on both of its events. Gemini CLI: session_id as sent, else the
# GEMINI_SESSION_ID it exports; a stop keyed on anything else would take a
# fresh baseline instead of asking.
case "$tool" in
  cursor) id="$(field conversation_id)"; [ -n "$id" ] || id="$(field session_id)" ;;
  gemini) id="$(field session_id)"; [ -n "$id" ] || id="${GEMINI_SESSION_ID:-}" ;;
esac
inner="$(printf '{"session_id":"%s"}' "$id")"

case "$event" in
  session-start)
    out="$(printf '%s' "$inner" | bash "$HERE/session-start.sh" 2>/dev/null || true)"
    if [ -z "$out" ]; then
      printf '{}\n'
    elif [ "$tool" = "cursor" ]; then
      printf '{"additional_context":%s}\n' "$(json_string "$out")"
    else
      printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$(json_string "$out")"
    fi
    ;;
  stop)
    if [ "$tool" = "cursor" ]; then
      status="$(field status)"
      if [ -n "$status" ] && [ "$status" != "completed" ]; then
        printf '{}\n'
        exit 0
      fi
    fi
    if [ "$tool" = "gemini" ] && flag stop_hook_active; then
      printf '{}\n'
      exit 0
    fi
    err="$(printf '%s' "$inner" | bash "$HERE/stop-report.sh" 2>&1 >/dev/null)"
    code=$?
    # Both tools hand this text to the agent as its next prompt, Cursor as the
    # person's own message, so only the report request goes through: anything
    # bash printed before it (a bad state file, say) stays out. The request
    # starts with "Work landed".
    ask="$(printf '%s\n' "$err" | sed -n '/^Work landed/,$p')"
    [ -n "$ask" ] || ask="$err"
    if [ "$code" -ne 2 ] || [ -z "$ask" ]; then
      printf '{}\n'
    elif [ "$tool" = "cursor" ]; then
      printf '{"followup_message":%s}\n' "$(json_string "$ask")"
    else
      ask="$ask
Save it with the shell tool: the reports folder is outside the workspace, and write_file refuses it."
      printf '{"decision":"deny","reason":%s}\n' "$(json_string "$ask")"
    fi
    ;;
esac

exit 0
