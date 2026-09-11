#!/usr/bin/env bash
# Checks for both hooks. Run from anywhere:  bash hooks/test.sh
# Every case runs in a throwaway repository with HOME pointed at a throwaway
# folder, so nothing of yours is read or written.

PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

check() { # $1 label  $2 expected exit  $3 actual exit
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1 (exit $3)"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (expected $2, got $3)"
    fail=$((fail + 1))
  fi
}

newrepo() {
  W="$(mktemp -d)"
  cd "$W" || exit 1
  git init -q
  echo a > a.txt
  git add .
  git -c user.name=t -c user.email=t@t commit -qm init
}

start() { printf '{"session_id":"%s"}' "$1" | HOME="$H" bash "$PACK/hooks/session-start.sh" >/dev/null 2>&1; }
stop() { printf '{"session_id":"%s"}' "$1" | HOME="$H" bash "$PACK/hooks/stop-report.sh" 2>/dev/null; }

echo "CASE 1  work finished in one reply, with the baseline"
H="$(mktemp -d)"; newrepo
start S1
echo change >> a.txt
stop S1; check "asks for a report" 2 $?

echo "CASE 2  baseline taken, nothing changed after it"
H="$(mktemp -d)"; newrepo
start S2
stop S2; check "stays silent" 0 $?

echo "CASE 3  the tree was already dirty before the session"
H="$(mktemp -d)"; newrepo
echo "someone else's edit" >> a.txt
start S3
stop S3; check "stays silent" 0 $?

echo "CASE 4  SessionStart fires again mid-session (compact, clear)"
start S3
echo change >> a.txt
export OPEN_STEPS_COOLDOWN=0
stop S3; check "the pending report survives" 2 $?
stop S3; check "the next stop is silent, no loop" 0 $?
unset OPEN_STEPS_COOLDOWN

echo "CASE 5  fallback: the SessionStart hook never ran"
H="$(mktemp -d)"; newrepo
export OPEN_STEPS_COOLDOWN=0
echo change >> a.txt
stop S5; check "the first stop only takes a baseline" 0 $?
echo more >> a.txt
stop S5; check "the second stop asks" 2 $?
unset OPEN_STEPS_COOLDOWN

echo "CASE 6  the kill switch"
H="$(mktemp -d)"; newrepo
start S6
echo change >> a.txt
OPEN_STEPS_DISABLE=1 stop S6; check "silent when switched off" 0 $?

echo "CASE 7  no repository anywhere"
H="$(mktemp -d)"; D="$(mktemp -d)"; cd "$D" || exit 1
start S7
echo hello > note.txt
stop S7; check "stays silent" 0 $?

echo "CASE 8  the handover the SessionStart hook prints"
H="$(mktemp -d)"; newrepo
out="$(printf '{"session_id":"S8"}' | HOME="$H" bash "$PACK/hooks/session-start.sh" 2>/dev/null)"
case "$out" in
  *"<session-handover>"*os-done-or-not*"</session-handover>"*) check "the routing table is intact" 0 0 ;;
  *) check "the routing table is intact" 0 1 ;;
esac
case "$out" in
  *OS_STATE_*) check "the baseline stays off stdout" 0 1 ;;
  *) check "the baseline stays off stdout" 0 0 ;;
esac

echo "CASE 9  a payload from another agent, with fields these hooks do not know"
# Codex and Gemini CLI send the same session_id inside a fuller payload. The
# baseline is taken from a plain one and the stop reads the fuller one, so a
# session id that failed to parse would fall back, stop matching, and this case
# would go silent instead of asking. That is what makes it worth a case.
H="$(mktemp -d)"; newrepo
start S9
echo change >> a.txt
printf '{"session_id":"S9","cwd":"%s","transcript_path":null,"model":"gpt-5","permission_mode":"default"}' "$PWD" \
  | HOME="$H" bash "$PACK/hooks/stop-report.sh" 2>/dev/null
check "the session id is still found" 2 $?

echo "CASE 10  Cursor: JSON both ways, and a stop that cannot block"
# Cursor answers only to JSON on stdout and cannot block a stop, so the adapter
# wraps the handover as additional_context and turns the report request into a
# followup_message. Its stop payload carries no session_id, only
# conversation_id, so the adapter keys both events on that: a stop that still
# looked for session_id would take a fresh baseline instead of asking.
# CURSOR_PROJECT_DIR is set on every call because Cursor always sets it and
# the adapter follows it; left to the environment, a suite run from inside a
# hook would measure some other repository.
H="$(mktemp -d)"; newrepo
# A previous report with the characters JSON cannot carry raw. The routing
# table has none of them, so without this the escaping is never exercised.
mkdir -p "$H/.claude/open-steps/reports/$(basename "$PWD")"
printf '%s\n' 'path C:\Users \"quoted\" \d' > "$H/.claude/open-steps/reports/$(basename "$PWD")/latest.md"
cstart="$(printf '{"conversation_id":"C10","generation_id":"g1","hook_event_name":"sessionStart","session_id":"S10","workspace_roots":["%s"]}' "$PWD")"
out="$(printf '%s' "$cstart" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor session-start 2>/dev/null)"
case "$out" in
  '{"additional_context":"'*"<session-handover>"*os-done-or-not*'"}') check "the handover arrives as additional_context" 0 0 ;;
  *) check "the handover arrives as additional_context" 0 1 ;;
esac
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = "0" ]; check "on one line, newlines escaped" 0 $?
printf '%s' "$out" | grep -Fq 'path C:\\Users \\\"quoted\\\" \\d' ; check "backslashes doubled and quotes escaped" 0 $?
echo change >> a.txt
cstop='{"conversation_id":"C10","generation_id":"g2","hook_event_name":"stop","status":"aborted","loop_count":0}'
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
[ "$out" = "{}" ]; check "an aborted stop is left alone" 0 $?
cstop='{"conversation_id":"C10","generation_id":"g3","hook_event_name":"stop","status":"completed","loop_count":0}'
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
code=$?
case "$out" in
  '{"followup_message":"Work landed'*os-done-or-not*'"}') check "a completed stop asks through followup_message" 0 0 ;;
  *) check "a completed stop asks through followup_message" 0 1 ;;
esac
check "with exit 0, since 2 cannot block here" 0 $code
# Parsed by a real interpreter where one exists, since the shape checks above
# cannot see a bad escape. Skipped, not failed, where there is none.
py=""
for cand in python3 python; do
  command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import json' >/dev/null 2>&1 && { py="$cand"; break; }
done
if [ -n "$py" ]; then
  printf '%s' "$out" | "$py" -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null
  check "and it parses as JSON" 0 $?
fi
out="$(printf '%s' "$cstop" | HOME="$H" CURSOR_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" cursor stop 2>/dev/null)"
[ "$out" = "{}" ]; check "the next stop is silent, no loop" 0 $?

echo "CASE 11  Gemini CLI: JSON both ways, and a stop that refuses on AfterAgent"
# Gemini CLI wants JSON too, with its own field names: the handover goes in
# hookSpecificOutput.additionalContext, and the report is asked for through
# decision "deny" with a reason, on AfterAgent. SessionEnd would run the same
# script, exit cleanly, and never ask; that is why the event is named here.
# Every Gemini payload carries session_id and every hook gets
# GEMINI_SESSION_ID; the adapter reads the first and falls back to the second.
H="$(mktemp -d)"; newrepo
gstart="$(printf '{"session_id":"G11","transcript_path":"%s/t.json","cwd":"%s","hook_event_name":"SessionStart","timestamp":"2026-01-01T00:00:00Z","source":"startup"}' "$H" "$PWD")"
out="$(printf '%s' "$gstart" | HOME="$H" GEMINI_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" gemini session-start 2>/dev/null)"
case "$out" in
  '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"'*"<session-handover>"*os-done-or-not*'"}}') check "the handover arrives as hookSpecificOutput.additionalContext" 0 0 ;;
  *) check "the handover arrives as hookSpecificOutput.additionalContext" 0 1 ;;
esac
[ "$(printf '%s' "$out" | wc -l | tr -d ' ')" = "0" ]; check "on one line, newlines escaped" 0 $?
grep -q '^OS_STATE_SESSION=G11$' "$H/.claude/open-steps/reports/$(basename "$PWD")/.stop-state"
check "the baseline is keyed on the session id Gemini sent" 0 $?
gafter="$(printf '{"session_id":"G11","transcript_path":"%s/t.json","cwd":"%s","hook_event_name":"AfterAgent","timestamp":"2026-01-01T00:01:00Z","prompt":"append a line","prompt_response":"Done.","stop_hook_active":false}' "$H" "$PWD")"
out="$(printf '%s' "$gafter" | HOME="$H" GEMINI_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" gemini stop 2>/dev/null)"
[ "$out" = "{}" ]; check "nothing landed, AfterAgent lets the turn end" 0 $?
echo change >> a.txt
out="$(printf '%s' "$gafter" | HOME="$H" GEMINI_PROJECT_DIR="$PWD" bash "$PACK/hooks/adapter.sh" gemini stop 2>/dev/null)"
code=$?
# The reason ends with where to save the report: Gemini's file tool refuses
# paths outside the workspace, and the reports folder is one.
case "$out" in
  '{"decision":"deny","reason":"Work landed'*os-done-or-not*'shell tool'*'"}') check "work landed, AfterAgent refuses with the request as the reason" 0 0 ;;
  *) check "work landed, AfterAgent refuses with the request as the reason" 0 1 ;;
esac
check "with exit 0, the refusal is in the JSON" 0 $code
if [ -n "$py" ]; then
  printf '%s' "$out" | "$py" -c 'import json, sys; json.load(sys.stdin)' 2>/dev/null
  check "and it parses as JSON" 0 $?
fi
# Gemini marks the retry it runs after a deny with stop_hook_active true. The
# adapter lets that one through without asking, whatever landed in it, since
# denying the retry is the one way to loop. Shown with the cooldown off and a
# further change, which would otherwise be asked for.
echo more >> a.txt
gretry="${gafter/\"stop_hook_active\":false/\"stop_hook_active\":true}"
out="$(printf '%s' "$gretry" | HOME="$H" GEMINI_PROJECT_DIR="$PWD" OPEN_STEPS_COOLDOWN=0 bash "$PACK/hooks/adapter.sh" gemini stop 2>/dev/null)"
[ "$out" = "{}" ]; check "the retry after the report is let through, no loop" 0 $?
# A payload without session_id: the adapter falls back to GEMINI_SESSION_ID
# and finds the baseline, so the change above is asked for now. Keyed on
# anything else, this stop would take a fresh baseline and answer {}.
gnoid="${gafter/\"session_id\":\"G11\",/}"
out="$(printf '%s' "$gnoid" | HOME="$H" GEMINI_PROJECT_DIR="$PWD" GEMINI_SESSION_ID=G11 OPEN_STEPS_COOLDOWN=0 bash "$PACK/hooks/adapter.sh" gemini stop 2>/dev/null)"
case "$out" in
  '{"decision":"deny","reason":"Work landed'*'"}') check "without session_id in the payload, GEMINI_SESSION_ID finds the same baseline" 0 0 ;;
  *) check "without session_id in the payload, GEMINI_SESSION_ID finds the same baseline" 0 1 ;;
esac

echo "CASE 12  the map this pack writes into the project"
# os-big-picture writes BIG-PICTURE.md inside the repository, unlike reports. If
# the fingerprint counted it, the agent would be asked for a report about the
# file it just wrote, once the cooldown expired. The second assertion is the
# one that matters: excluding it must not swallow real work landing alongside.
H="$(mktemp -d)"; newrepo
start S12
echo "the map" > BIG-PICTURE.md
stop S12; check "the map alone is not work" 0 $?
echo change >> a.txt
stop S12; check "real work alongside it still asks" 2 $?

echo "CASE 13  the census the map is measured from"
# scripts/census.sh is the whole measured half of os-big-picture, so the two
# signals are worth a real repository rather than a promise in prose. Three
# parts with forged commit dates: one touched last week, one untouched for
# eight months that nothing mentions, one untouched for eight months that the
# build script does. Two-sided like CASE 12: the quiet-and-unused part must be
# named, and the quiet-but-wired part must not be, or the map recommends
# deleting a working product.
H="$(mktemp -d)"; W="$(mktemp -d)"; cd "$W" || exit 1
git init -q
# Forged dates, as epoch seconds: git rejects "8 months ago" here, and the
# two date(1) dialects disagree about how to subtract a day.
NOW="$(date +%s)"
commit() { # $1 days ago  $2 message
  local when="@$((NOW - $1 * 86400)) +0000"
  GIT_AUTHOR_DATE="$when" GIT_COMMITTER_DATE="$when" \
    git -c user.name=t -c user.email=t@t commit -qm "$2"
}
mkdir -p fresh quiet_used quiet_orphan
echo "print(1)" > fresh/main.py
echo "print(2)" > quiet_used/lib.py
echo "print(3)" > quiet_orphan/old.py
# The build script reaches one of the two quiet parts and not the other. That
# one mention is the whole difference between `stable` and a retire candidate.
printf '#!/bin/sh\npython quiet_used/lib.py\n' > build.sh
# Housekeeping files, old and unmentioned: they must not read as retire candidates.
printf 'node_modules\n' > .gitignore
printf 'MIT\n' > LICENSE
git add .
commit 240 "everything lands"
echo "print(4)" >> fresh/main.py
git add fresh
commit 6 "only the fresh part moves"

out="$(bash "$PACK/skills/os-big-picture/scripts/census.sh" .)"
signal() { printf '%s\n' "$out" | awk -v p="$1" -F'\t' '$2 == p {print $6}'; }

[ "$(signal fresh)" = "active" ]; check "worked on last week reads active" 0 $?
case "$(signal quiet_orphan)" in
  "unused - "*) check "quiet and unreached reads unused" 0 0 ;;
  *) check "quiet and unreached reads unused" 0 1 ;;
esac
[ "$(signal quiet_used)" = "stable" ]
check "quiet but still reached reads stable, not unused" 0 $?
printf '%s\n' "$out" | awk -F'\t' '$1 == "PART" && ($2 == ".gitignore" || $2 == "LICENSE") {found=1} END {exit found}'
check "housekeeping files stay off the map" 0 $?
# The AGE line: this repository's first commit is eight months back, so the
# liveness column is old enough to mean something and takes no warning.
printf '%s\n' "$out" | awk -F'\t' '$1 == "AGE" && $3 == "ok" {found=1} END {exit !found}'
check "a repository past six months takes no young-repo warning" 0 $?

echo "CASE 14  the census on a repository younger than the quiet window"
# A young project has no quiet code by definition, so every part reads active
# and the map would report a clean bill of health it did not earn. The script
# has to say the column cannot mean anything yet, and from when it will.
H="$(mktemp -d)"; W="$(mktemp -d)"; cd "$W" || exit 1
git init -q
mkdir -p app
echo "print(1)" > app/main.py
git add .
commit 10 "a young project"
out="$(bash "$PACK/skills/os-big-picture/scripts/census.sh" .)"
printf '%s\n' "$out" | awk -F'\t' '$1 == "AGE" && $3 == "young" && $4 ~ /^[0-9]{4}-/ {found=1} END {exit !found}'
check "says young, and names the date it starts to mean something" 0 $?

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
