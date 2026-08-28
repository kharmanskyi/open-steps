#!/usr/bin/env bash
# SessionStart hook. Prints the routing table and the previous report for this
# project into the new session's context, then silently records the baseline
# the Stop hook compares against, so work finished in a single reply still gets
# a report. Only what this script prints reaches the model; the script itself
# costs no tokens.
#
# Settings: OPEN_STEPS_MAX_REPORT_LINES (cap on the injected report).
# Kill switch: OPEN_STEPS_NO_SESSION_START=1.

MAX_REPORT_LINES="${OPEN_STEPS_MAX_REPORT_LINES:-80}"

set -uo pipefail

[ -n "${OPEN_STEPS_NO_SESSION_START:-}" ] && exit 0

# shellcheck source-path=SCRIPTDIR
# shellcheck source=fingerprint.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fingerprint.sh"

os_session_id "$(cat 2>/dev/null || true)"
os_find_repos

cat <<'ROUTING'
<session-handover>
These moments require a skill. Invoke it rather than improvising the answer.

- I ask what is next, what is left, or what is blocked -> os-whats-next
- Any technical question you put to me, or any options you offer -> os-ask-simple
- Something hard to undo is about to be agreed, or I ask what could go wrong -> os-what-could-go-wrong
- Any message where you ask me to do something (run a command, paste a value,
  approve, choose, test on a device) -> os-step-by-step
- I ask about other sessions, or to accept work one of them finished -> os-check-work
- Work is finished, or I ask how it went -> os-done-or-not
- I say I did not understand, ask for simpler or shorter, or paste text asking what it means -> os-say-simple

Never offer options without naming a recommendation.
ROUTING

report="$HOME/.claude/open-steps/reports/$OS_SCOPE/latest.md"

if [ -r "$report" ]; then
  total="$(wc -l < "$report" | tr -d ' ')"
  printf '\nLast session in this project (%s), from %s:\n\n' "$OS_SCOPE" "$report"
  head -n "$MAX_REPORT_LINES" "$report"
  if [ "$total" -gt "$MAX_REPORT_LINES" ]; then
    printf '\n[...%s more lines, read the file if you need them]\n' \
      "$((total - MAX_REPORT_LINES))"
  fi
  printf '\nTreat it as a handover, not as current truth: verify anything you are about to rely on.\n'
else
  printf '\nNo previous report for this project.\n'
fi

printf '</session-handover>\n'

# The baseline. A session id already on record (compact, clear) keeps the
# baseline it has, so a pending report is not forgotten. Never printed, and a
# failure here must not cost the session its handover above.
{
  os_state_paths
  os_read_state
  if [ "$OS_PREV_SESSION" != "$OS_SESSION" ]; then
    os_fingerprint
    os_save_state "$OS_PREV_FIRED_AT"
  fi
} >/dev/null 2>&1 || true

exit 0
