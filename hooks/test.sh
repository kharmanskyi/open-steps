#!/usr/bin/env bash
# Checks for both hooks. Run from anywhere:  bash hooks/test.sh
# Every case runs in a throwaway repository with HOME pointed at a throwaway
# folder, so nothing of yours is read or written.

# shellcheck disable=SC2016  # some checks match literal ${...} text in files
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

echo "CASE 15  the doctor reads the copy that runs, not the clone it sits in"
# Claude Code runs the copy named in installed_plugins.json. A marketplace
# added from a local folder records the clone itself as its location, so a
# doctor that starts from the marketplace list reads the clone - the one thing
# its own header says it never does - and says ok about a file the running
# copy does not have. Both registries here are hand-made; the clone is real.
H="$(mktemp -d)"; C="$H/cache-copy"
mkdir -p "$H/.claude/plugins" "$C"
cp -R "$PACK/." "$C" && rm -rf "$C/.git"
rm -f "$C/hooks/adapter.sh"
printf '{"open-steps":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
  "$PACK" "$PACK" > "$H/.claude/plugins/known_marketplaces.json"
printf '{"version":2,"plugins":{"open-steps@open-steps":[{"scope":"user","installPath":"%s","version":"0.0.0"}]}}\n' \
  "$C" > "$H/.claude/plugins/installed_plugins.json"
out="$(HOME="$H" bash "$PACK/doctor.sh" 2>/dev/null)"
printf '%s\n' "$out" | grep -Fq "FAULT        The hook file adapter.sh is missing from the installed copy."
check "a file missing from the running copy is a fault, not an ok read off the clone" 0 $?
printf '%s\n' "$out" | grep -Fq "The installed copy is at $(cd "$C" && pwd -P)."
check "the copy it read is the one the registry names" 0 $?
printf '%s\n' "$out" | grep -Fq "installed_plugins.json"
check "it says which registry decided" 0 $?
cp "$PACK/hooks/adapter.sh" "$C/hooks/adapter.sh"
out="$(HOME="$H" bash "$PACK/doctor.sh" 2>/dev/null)"
printf '%s\n' "$out" | grep -Fq "ok           The hook file adapter.sh is in place."
check "the same file present in the running copy reads ok" 0 $?
# Two versions on one machine are the update path at work, not a fault.
awk '{sub(/"version": *"[^"]*"/, "\"version\": \"0.0.0\"")}1' "$C/.claude-plugin/plugin.json" > "$H/pj" \
  && mv "$H/pj" "$C/.claude-plugin/plugin.json"
pv="$(grep -oE '"version": *"[^"]*"' "$PACK/.claude-plugin/plugin.json" | head -1 | sed -E 's/.*"([^"]*)"$/\1/')"
out="$(HOME="$H" bash "$PACK/doctor.sh" 2>/dev/null)"
printf '%s\n' "$out" | grep -Fq "fact         The installed copy is version 0.0.0 and this clone is version $pv."
check "a version gap between the copies is reported as a fact" 0 $?
# A registry entry pointing at a folder with no plugin is a broken install;
# searching on from there would land on the clone and read ok off it.
mkdir -p "$H/gone"
printf '{"version":2,"plugins":{"open-steps@open-steps":[{"scope":"user","installPath":"%s","version":"0.0.0"}]}}\n' \
  "$H/gone" > "$H/.claude/plugins/installed_plugins.json"
out="$(HOME="$H" bash "$PACK/doctor.sh" 2>/dev/null)"
printf '%s\n' "$out" | grep -Fq "FAULT        Claude Code's plugin registry, installed_plugins.json, names $H/gone as the installed copy, but there is no plugin there."
check "a registry entry with no plugin behind it is a fault, not a reason to read the clone" 0 $?
printf '%s\n' "$out" | grep -Fq "ok           The hook file adapter.sh is in place."
check "and nothing is read off the clone in that case" 1 $?

echo "CASE 16  the premortem prompt travels by script, not by cat"
# Claude Code runs a skill's inline commands before the skill loads, and since
# 2.1.222 a bare cat of a file outside the session's working directory is
# refused there, which aborts the whole skill: the agent never sees it. A
# script in the skill's own folder is the documented way to bring a file in,
# and it is not refused. The script must print the prompt file exactly, and
# the skill must ask for it by the same command in both places it names it.
SK="$PACK/skills/os-what-could-go-wrong"
[ -f "$SK/scripts/prompt.sh" ]
check "the script exists" 0 $?
bash "$SK/scripts/prompt.sh" 2>/dev/null | cmp -s - "$SK/references/premortem-prompt.md"
check "it prints the prompt file byte for byte" 0 $?
grep -Fq '!`bash ${CLAUDE_SKILL_DIR}/scripts/prompt.sh`' "$SK/SKILL.md"
check "the skill loads the prompt through the script" 0 $?
grep -Fq '"Bash(bash ${CLAUDE_SKILL_DIR}/scripts/prompt.sh)"' "$SK/SKILL.md"
check "and pre-approves exactly that command" 0 $?
grep -Fq 'cat ${CLAUDE_SKILL_DIR}' "$SK/SKILL.md"
check "no inline cat of a skill file is left" 1 $?

echo "CASE 17  the premortem skill hands the report over whole"
# Measured 2026-09-13: Sonnet 5 shrank a fresh agent's 18-25k-character report
# to 0.8-8.5k in its final message, Haiku 4.5 22k to 4k; Opus 5 passed it
# through. Step 3 now says mechanically what the final message is, and this
# pins the sentence so a later edit cannot soften it back. The skill also
# stays within its one-screen ceiling of 150 lines.
grep -Fq "a tool result is visible only to" "$SK/SKILL.md"
check "step 3 says the user cannot see the agent's answer" 0 $?
grep -Fq "copied whole, first line to last" "$SK/SKILL.md"
check "and makes the final message the report itself" 0 $?
grep -Fq "never instead of it" "$SK/SKILL.md"
check "and puts the agent's own words after it, never in its place" 0 $?
[ "$(wc -l < "$SK/SKILL.md" | tr -d ' ')" -le 150 ]
check "the skill fits its 150-line ceiling" 0 $?

echo "CASE 18  the doctor on Codex, Cursor and Gemini CLI installs"
# Codex, Cursor and Gemini CLI read one skills folder, ~/.agents/skills, and
# each has a folder of its own too. The doctor once took any copy in the shared
# folder as a Codex install and judged every machine as if Claude Code were on
# it, so a correct install on any of the three read as broken, with exit 9.
# Each home below is a correct install as docs/other-agents.md describes it.
# The doctor runs with only HOME and a PATH holding the tools it calls, so a
# claude command on the machine running this suite cannot leak in. Two-sided:
# a real fault in each still reads as one.
err="$(mktemp)"
dhome() {
  H="$(mktemp -d)"
  mkdir -p "$H/bin"
  # type -P, not command -v: a shell function by the same name has no path.
  for t in awk basename dirname find grep head sed tr; do
    ln -s "$(type -P "$t")" "$H/bin/$t"
  done
}
doctor() { env -i HOME="$H" PATH="$H/bin" "$BASH" "$PACK/doctor.sh" 2>"$err"; }
shared() { mkdir -p "$H/.agents/skills" && cp -R "$PACK"/skills/os-* "$H/.agents/skills/"; }
own() { mkdir -p "$H/$1/skills" && cp -R "$PACK"/skills/os-* "$H/$1/skills/"; }
said() { printf '%s\n' "$out" | grep -Eq "$1"; }
# The summary line is what a sound install prints. Checking only for the
# absence of a fault would pass on a doctor that printed nothing at all.
sound() { # $1 which install
  said '^  FAULT'; check "$1: no fault" 1 $?
  said '^  No fault found\.$'; check "$1: the result says no fault found" 0 $?
  check "$1: exit 0" 0 "$code"
  [ ! -s "$err" ]; check "$1: nothing on stderr" 0 $?
}
gemini_hooks() { # $1 the adapter path the settings name
  mkdir -p "$H/.gemini"
  printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","name":"open-steps-session-start","command":"bash %s gemini session-start"}]}],"AfterAgent":[{"hooks":[{"type":"command","name":"open-steps-stop-report","command":"bash %s gemini stop"}]}]}}\n' \
    "$1" "$1" > "$H/.gemini/settings.json"
}
wire_gemini() {
  gemini_hooks "$PACK/hooks/adapter.sh"
  cat "$PACK/docs/routing-block.md" > "$H/.gemini/GEMINI.md"
}
wire_cursor() { # $1 the adapter path the hooks file names
  mkdir -p "$H/.cursor"
  printf '{"version":1,"hooks":{"sessionStart":[{"command":"%s cursor session-start","timeout":10}],"stop":[{"command":"%s cursor stop","timeout":10}]}}\n' \
    "$1" "$1" > "$H/.cursor/hooks.json"
}
wire_codex() {
  mkdir -p "$H/.codex"
  cat "$PACK/docs/routing-block.md" > "$H/.codex/AGENTS.md"
  printf '[[hooks.session_start]]\n[[hooks.session_start.hooks]]\ntype = "command"\ncommand = "%s/hooks/session-start.sh"\ntimeout_sec = 10\n\n[[hooks.stop]]\n[[hooks.stop.hooks]]\ntype = "command"\ncommand = "%s/hooks/stop-report.sh"\ntimeout_sec = 10\n' \
    "$PACK" "$PACK" > "$H/.codex/config.toml"
}
wire_claude() {
  mkdir -p "$H/.claude/plugins"
  printf '{"version":2,"plugins":{"open-steps@open-steps":[{"scope":"user","installPath":"%s","version":"0.0.0"}]}}\n' \
    "$PACK" > "$H/.claude/plugins/installed_plugins.json"
  printf '{"enabledPlugins":{"open-steps@open-steps":true}}\n' > "$H/.claude/settings.json"
  cat "$PACK/docs/routing-block.md" > "$H/.claude/CLAUDE.md"
}
fake_claude() { printf '#!/bin/sh\nexit 0\n' > "$H/bin/claude" && chmod +x "$H/bin/claude"; }

dhome; shared; wire_gemini
# The hooks keep their reports under ~/.claude on every tool, so after one
# session a Gemini CLI machine has that folder too. It is not Claude Code.
mkdir -p "$H/.claude/open-steps/reports/proj"
echo "a report" > "$H/.claude/open-steps/reports/proj/latest.md"
out="$(doctor)"; code=$?
sound "Gemini CLI only"
said '^  not checked  No sign of Claude Code was found: no claude command on the PATH'
check "Gemini CLI only: the Claude Code parts read not checked, not faulted" 0 $?
said '^  ok +All [0-9]+ skills are copied into the shared skills folder'
check "Gemini CLI only: the shared folder copy reads ok" 0 $?
said 'is the shared skills folder, read by Codex, Cursor and Gemini CLI\.$'
check "Gemini CLI only: the folder is named as shared by the three, and Claude Code is left out of it" 0 $?
said '^  fact +Codex was not found'
check "Gemini CLI only: no Codex, so no Codex checks" 0 $?
said '^  fact +Your Gemini CLI instructions file has the whole routing block'
check "Gemini CLI only: the routing block is reported as a fact" 0 $?
said '^  fact +.*/\.gemini/settings\.json names both hook commands, adapter\.sh gemini session-start and adapter\.sh gemini stop, and the AfterAgent event'
check "Gemini CLI only: the wired hooks are reported as a fact" 0 $?
said '^  ok +The file Gemini CLI runs at the end of a session is there\.'
check "Gemini CLI only: the adapter path in the settings was looked up" 0 $?
# Claude Code on the machine with nothing of the pack in its files is not a
# broken install while the pack is set up for another tool.
fake_claude
out="$(doctor)"; code=$?
sound "Gemini CLI next to a Claude Code without the pack"
said '^  fact +Claude Code is here, and nothing of the pack is set up for it'
check "with a claude command and nothing of the pack for it, Claude Code is a fact" 0 $?
rm "$H/bin/claude"; echo '{}' > "$H/.claude.json"
out="$(doctor)"; code=$?
said '^  fact +Claude Code is here, and nothing of the pack is set up for it'
check "~/.claude.json is a sign of Claude Code" 0 $?
check "and with the pack set up for Gemini CLI it is not a fault" 0 "$code"
# A routing block in CLAUDE.md is the pack set up for Claude Code, so Claude
# Code is judged again, and a plugin missing behind it is a fault.
cat "$PACK/docs/routing-block.md" > "$H/.claude/CLAUDE.md"
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "a Claude Code routing block with no plugin behind it is a fault" 0 $?
check "and the exit code names the skills" 1 "$code"

# With the pack found for no other tool, Claude Code on the machine is judged.
dhome; fake_claude
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "a claude command and the pack found for no tool: the missing install is a fault" 0 $?
check "and the exit code says so" 9 "$code"
dhome; echo '{}' > "$H/.claude.json"
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "~/.claude.json and the pack found for no tool: the same fault" 0 $?

dhome; shared; wire_cursor "$PACK/hooks/adapter.sh"
out="$(doctor)"; code=$?
sound "Cursor only"
said '^  fact +.*/\.cursor/hooks\.json names both hook commands, adapter\.sh cursor session-start and adapter\.sh cursor stop'
check "Cursor only: the wired hooks are reported as a fact" 0 $?

dhome; shared; wire_codex
out="$(doctor)"; code=$?
sound "Codex only"
said '^  ok +Your Codex instructions file has the whole routing block'
check "Codex only: the Codex part ran" 0 $?
said '^  ok +The file Codex runs at the end of a session is there\.'
check "Codex only: and read the hook paths" 0 $?
rm "$H/.codex/config.toml"
out="$(doctor)"; code=$?
said '^  FAULT +Codex has no settings file, so its hooks are not set up\.'
check "Codex without its hooks is still a fault" 0 $?
check "and the exit code names the hooks" 3 "$code"

# A ~/.codex from Codex itself, with nothing of the pack in it, next to a copy
# in the shared folder: no other tool that reads that folder is here, so the
# copy is Codex's, and Codex is judged in full.
dhome; shared
mkdir -p "$H/.codex"; echo '{}' > "$H/.codex/auth.json"
out="$(doctor)"; code=$?
said '^  FAULT +Your Codex instructions file is not there'
check "Codex as the one reader of the shared copy: no routing block is a fault" 0 $?
said '^  FAULT +Codex has no settings file, so its hooks are not set up\.'
check "Codex as the one reader of the shared copy: no hooks is a fault" 0 $?
check "and the exit code names both" 9 "$code"
printf 'model = "gpt-5"\n' > "$H/.codex/config.toml"
out="$(doctor)"; code=$?
said '^  FAULT +The Codex settings file sets up no hook for the start of a session and the end of a session\.$'
check "a Codex settings file without the pack is judged the same way" 0 $?
# With Gemini CLI here too, the copy could be either tool's, so it says so.
wire_gemini
out="$(doctor)"; code=$?
sound "Codex and Gemini CLI sharing one copy"
said '^  fact +Codex shares the copy in the shared skills folder with Gemini CLI'
check "the fact names the tools that could be reading the copy" 0 $?

# The tools' own folders count as a copy for that tool.
dhome; own .gemini; wire_gemini
out="$(doctor)"; code=$?
sound "Gemini CLI with the skills in its own folder"
said "^  ok +The pack's [0-9]+ skills are copied into Gemini CLI's own skills folder"
check "Gemini CLI's own folder: the copy there reads ok" 0 $?
said '^  fact +No skills from this pack are in the shared skills folder\.$'
check "Gemini CLI's own folder: it says the shared folder was read and has none" 0 $?
dhome; own .codex; wire_codex
out="$(doctor)"; code=$?
sound "Codex with the skills in its own folder"
dhome; own .cursor; wire_cursor "$PACK/hooks/adapter.sh"
out="$(doctor)"; code=$?
sound "Cursor with the skills in its own folder"

# Claude Code alone, with nothing in the shared folders.
dhome; wire_claude
out="$(doctor)"; code=$?
sound "Claude Code only"
said '^  ok +The plugin is switched on\.'
check "Claude Code only: the Claude Code part ran" 0 $?

# Shortcuts in the shared folder rename the skills on Codex.
dhome; mkdir -p "$H/.agents/skills"; ln -s "$PACK"/skills/os-* "$H/.agents/skills/"; wire_gemini
out="$(doctor)"; code=$?
sound "shortcut skills without Codex"
said '^  fact +These skills in the shared skills folder are shortcuts, not copies:'
check "shortcut skills without Codex: reported as a fact" 0 $?
said '^  not checked  What Cursor and Gemini CLI do with a shortcut was not checked\.'
check "and what was not checked has its own line" 0 $?
said '^  fact .*not checked'
check "no fact line carries a not checked" 1 $?
mkdir -p "$H/.codex"; echo '{}' > "$H/.codex/auth.json"
out="$(doctor)"; code=$?
sound "shortcut skills next to a Codex with nothing of the pack"
said '^  fact +These skills in the shared skills folder are shortcuts, not copies:'
check "shortcut skills next to a Codex with nothing of the pack: a fact, not blamed on Codex" 0 $?
wire_codex
out="$(doctor)"; code=$?
said '^  FAULT +These skills in the shared skills folder are shortcuts, not copies, so Codex gives them other names:'
check "shortcut skills with Codex set up: a fault" 0 $?
check "and the exit code names the skills" 1 "$code"

dhome; shared; rm -rf "$H/.agents/skills/os-done-or-not"; wire_gemini
out="$(doctor)"; code=$?
said '^  FAULT +Part of the pack is in the shared skills folder, but these skills are not: os-done-or-not'
check "a partial copy in the shared folder is a fault" 0 $?
check "and the exit code names the skills" 1 "$code"

dhome; wire_codex
out="$(doctor)"; code=$?
said '^  FAULT +Codex is set up for this pack, but none of its skills are'
check "Codex set up with no copy of the skills is a fault" 0 $?
check "and the exit code names the skills" 1 "$code"

dhome; shared; wire_gemini; gemini_hooks "open-steps/hooks/adapter.sh"
out="$(doctor)"; code=$?
said '^  not checked  .*/\.gemini/settings\.json gives adapter\.sh gemini stop a path that is not a full path'
check "a hook path that is not a full path is not checked, not faulted" 0 $?
check "and it is not a fault" 0 "$code"

# The documentation's example paths read as wired and point at nothing.
dhome; shared; wire_gemini; gemini_hooks "/path/to/open-steps/hooks/adapter.sh"
out="$(doctor)"; code=$?
said '^  FAULT +.*/\.gemini/settings\.json still holds the example path'
check "Gemini CLI hooks on the example path are a fault" 0 $?
check "and the exit code names the hooks" 3 "$code"
said 'names both hook commands'
check "and they are not reported as wired" 1 $?
gemini_hooks "$H/gone/hooks/adapter.sh"
out="$(doctor)"; code=$?
said "^  FAULT +Gemini CLI runs a file that is not there at the start of a session: $H/gone/hooks/adapter\.sh"
check "Gemini CLI hooks on a path with no file are a fault" 0 $?
check "and the exit code names the hooks" 3 "$code"
dhome; shared; wire_cursor "/absolute/path/to/open-steps/hooks/adapter.sh"
out="$(doctor)"; code=$?
said '^  FAULT +.*/\.cursor/hooks\.json still holds the example path'
check "Cursor hooks on the example path are a fault" 0 $?
check "and the exit code names the hooks" 3 "$code"

dhome; shared; wire_claude; mkdir -p "$H/.gemini"
cat "$PACK/docs/routing-block.md" > "$H/.gemini/GEMINI.md"
out="$(doctor)"; code=$?
sound "Claude Code with a Gemini CLI copy"
said '^  ok +The plugin is switched on\.'
check "Claude Code with a Gemini CLI copy: the Claude Code part ran" 0 $?
said '^  fact +Codex was not found'
check "Claude Code with a Gemini CLI copy: the copy is not taken for Codex" 0 $?
said 'read by Codex, Cursor and Gemini CLI\. Claude Code does not read it; it runs the plugin.s copy\.$'
check "with Claude Code here, the shared folder line says Claude Code does not read it" 0 $?
rm "$H/.claude/CLAUDE.md"
out="$(doctor)"; code=$?
said '^  FAULT +Your Claude Code instructions file is not there'
check "a missing Claude Code routing block is still a fault" 0 $?
check "and the exit code names the routing block" 2 "$code"

# A marketplace Claude Code knows about is where a plugin comes from, not an
# install. Added from the clone itself, its folder is the clone, and reading it
# as the installed copy says ok about a plugin that is not there.
dhome; shared; wire_gemini
mkdir -p "$H/.claude/plugins"; echo '{}' > "$H/.claude.json"
printf '{"open-steps":{"source":{"source":"directory","path":"%s"},"installLocation":"%s"}}\n' \
  "$PACK" "$PACK" > "$H/.claude/plugins/known_marketplaces.json"
printf '{"version":2,"plugins":{}}\n' > "$H/.claude/plugins/installed_plugins.json"
printf '{"enabledPlugins":{}}\n' > "$H/.claude/settings.json"
out="$(doctor)"; code=$?
sound "Gemini CLI next to a Claude Code marketplace with no plugin installed"
said '^  fact +Claude Code is here, and nothing of the pack is set up for it'
check "a marketplace with no plugin installed: nothing of the pack is set up for Claude Code" 0 $?
said 'running from the installed copy|The installed copy is at'
check "and the marketplace folder is not read as the installed copy" 1 $?
# A marketplace from GitHub lands in a folder of its own under plugins.
mk="$H/.claude/plugins/marketplaces/open-steps"
mkdir -p "$mk/.claude-plugin"
cp "$PACK/.claude-plugin/plugin.json" "$PACK/.claude-plugin/marketplace.json" "$mk/.claude-plugin/"
cp -R "$PACK/skills" "$mk/"
printf '{"open-steps":{"source":{"source":"github","repo":"someone/open-steps"},"installLocation":"%s"}}\n' \
  "$mk" > "$H/.claude/plugins/known_marketplaces.json"
out="$(doctor)"; code=$?
sound "Gemini CLI next to a Claude Code marketplace folder from GitHub"
said 'The installed copy is at'
check "a marketplace folder from GitHub is not read as the installed copy" 1 $?
# With no other tool, the same Claude Code is judged, and has no plugin.
rm -rf "$H/.agents" "$H/.gemini"
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "a marketplace alone is a Claude Code with no installed copy" 0 $?

# Faults in Claude Code's own files still show next to a working Gemini CLI.
dhome; shared; wire_gemini; mkdir -p "$H/.claude/plugins"
printf '{"version":2,"plugins":{"open-steps@open-steps":[{"scope":"user","installPath":"%s","version":"0.0.0"}]}}\n' \
  "$H/gone" > "$H/.claude/plugins/installed_plugins.json"
out="$(doctor)"; code=$?
said "^  FAULT +Claude Code's plugin registry, installed_plugins.json, names $H/gone as the installed copy, but there is no plugin there\."
check "a stale registry entry next to Gemini CLI is a fault" 0 $?
dhome; shared; wire_gemini; mkdir -p "$H/.claude"
printf '{"enabledPlugins":{"open-steps@open-steps":true}}\n' > "$H/.claude/settings.json"
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "a plugin switched on in the settings with no copy behind it, next to Gemini CLI, is a fault" 0 $?

# A copy in the shared folder counts for another tool only when a tool that
# reads that folder is here.
dhome; shared; mkdir -p "$H/.claude/plugins"; echo '{}' > "$H/.claude.json"
printf '{"enabledPlugins":{}}\n' > "$H/.claude/settings.json"
out="$(doctor)"; code=$?
said '^  FAULT +No installed copy of the pack was found\. Claude Code cannot see it\.'
check "a shared copy no tool reads does not excuse a Claude Code without the plugin" 0 $?
check "and the exit code says so" 9 "$code"
dhome; shared
out="$(doctor)"; code=$?
said '^  FAULT +The pack was found for no tool: its skills are in .*/\.agents/skills, but'
check "a shared copy with no tool and no Claude Code: the pack is found for no tool" 0 $?
check "and the exit code names the skills" 1 "$code"

# A Codex with nothing of the pack in it is not the one reader of the shared
# copy while the pack is set up for Claude Code.
dhome; shared; wire_claude; mkdir -p "$H/.codex"; echo '{}' > "$H/.codex/auth.json"
out="$(doctor)"; code=$?
sound "Claude Code with an extra shared copy and a Codex with nothing of the pack"
said '^  fact +The copy in the shared skills folder may be for Codex'
check "the shared copy is reported as one that may be Codex's" 0 $?
dhome; wire_claude; mkdir -p "$H/.codex"; echo '{}' > "$H/.codex/auth.json"
printf 'model = "gpt-5"\n' > "$H/.codex/config.toml"
out="$(doctor)"; code=$?
sound "Claude Code next to a Codex with nothing of the pack"

# With no Claude Code, nothing would be judged, so an empty machine must not
# read as a sound install.
dhome
out="$(doctor)"; code=$?
said '^  FAULT +No copy of the pack was found for any tool'
check "the pack found for no tool is a fault, not a clean result" 0 $?
said '^  FAULT +No copy.*\.codex/skills.*\.cursor/skills.*\.gemini/skills'
check "and the fault names the folders it read" 0 $?
check "and the exit code names the skills" 1 "$code"
rm -f "$err"


echo "CASE 19  a session id that is really a command"
# The session id comes from the tool's payload and is written to the state
# file. An id with ; or $( ) in it must never run, whether it arrives now or
# sits in a state file an older version wrote. Such an id is replaced by the
# fallback, so the hooks still work: the change at the end is still asked for.
H="$(mktemp -d)"; newrepo
P="$(mktemp -d)"
for bad in "x;touch $P/semicolon" "\$(touch $P/substitution)" "\`touch $P/backtick\`"; do
  start "$bad"; check "session start with a hostile id" 0 $?
  stop "$bad"; check "stop with a hostile id, nothing changed" 0 $?
done
state="$H/.claude/open-steps/reports/$(basename "$W")/.stop-state"
grep -q '^OS_STATE_SESSION=nosession$' "$state"
check "the id is replaced by the fallback" 0 $?
printf 'OS_STATE_SESSION=x;touch %s/legacy\nOS_STATE_FIRED_AT=$(touch %s/legacy)\n' "$P" "$P" > "$state"
stop "x"; check "a hostile state file from an older version is read, not run" 0 $?
start "\$(touch $P/substitution)"
export OPEN_STEPS_COOLDOWN=0
echo change >> a.txt
stop "\$(touch $P/substitution)"; check "the fallback id still asks when work lands" 2 $?
unset OPEN_STEPS_COOLDOWN
[ -z "$(ls -A "$P")" ]; check "no command in any id ran" 0 $?
rm -rf "$P"

echo
echo "passed $pass, failed $fail"
[ "$fail" -eq 0 ]
