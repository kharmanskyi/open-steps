#!/usr/bin/env bash
# Checks for the measurement scripts. Run from anywhere:  bash evals/test.sh
# Nothing here talks to a model. The scorer reads the hand-made streams in
# fixtures/, and the runner is driven with a stand-in `claude` on PATH that
# writes down what it was asked and answers with a two-line stream. HOME points
# at a throwaway folder, so nothing of yours is read or written.

# shellcheck disable=SC2016  # the backticks below are markdown, matched as text
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

check() { # $1 label  $2 expected  $3 actual
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (expected '$2', got '$3')"
    fail=$((fail + 1))
  fi
}
score() { python3 "$PACK/evals/score.py" --print "$PACK/evals/fixtures/$1" 2>&1; }
has() { printf '%s' "$1" | grep -qF -- "$2" && echo yes || echo no; }

echo "CASE 1  a denied Skill call still counts as the model's choice"
out="$(score permission-denied)"
check "os-done-or-not scores 1/1" yes "$(has "$out" '| `os-done-or-not` | 1/1 |')"

echo "CASE 2  a quality arm whose every Skill call was denied is not a measurement"
out="$(score quality-denied)"
check "says the arm was not measured, and why" yes \
  "$(has "$out" 'not measured. Every Skill call in its 1 with-run was denied')"
check "prints no with row for it" no "$(has "$out" '| Haiku 4.5 | with')"
check "counts the streams that still carried the messaging tools" yes \
  "$(has "$out" 'sealed off from other sessions (no SendMessage or ListAgents tool): 0 of 2')"

echo "CASE 3  a quality arm where one Skill call ran is measured, matched by id"
out="$(score quality-measured)"
check "prints the with row" yes "$(has "$out" '| Haiku 4.5 | with |')"
check "does not call it unmeasured" no "$(has "$out" 'not measured')"
check "counts the sealed streams" yes \
  "$(has "$out" 'sealed off from other sessions (no SendMessage or ListAgents tool): 2 of 2')"

echo "CASE 4  a quality arm that never called a skill is unaided, not denied"
out="$(score quality-unaided)"
check "says no skill was called" yes \
  "$(has "$out" 'not measured. No Skill call in its 1 with-run, so both arms ran unaided')"
check "prints no with row for it" no "$(has "$out" '| Haiku 4.5 | with')"

echo "CASE 5  the runner seals every run and lets the quality arm load a skill"
H="$(mktemp -d)"
STUB="$(mktemp -d)"
export STUB_LOG="$STUB/calls.log"
cat > "$STUB/claude" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the CLI: one line per call, tokens tab-separated, then a stream
# just long enough for the scorer to read a model out of it.
line="$(printf '%s\t' "$@" | tr '\n' ' ')"
printf '%s\n' "$line" >> "$STUB_LOG"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","tools":["Bash","Read","Skill"]}\n'
printf '{"type":"result","result":"ok","permission_denials":[]}\n'
STUB
chmod +x "$STUB/claude"
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 \
    bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
T=$'\t'
# The auth check is one more call through the runner; it is not a measured run.
runs="$(grep -v -- "say just: ok" "$STUB_LOG" | grep -c -- "stream-json")"
files="$(find "$H/.claude/open-steps/evals" -name '*.jsonl' | wc -l | tr -d ' ')"
check "one stream per run ($runs runs)" "$runs" "$files"
check "every run carries the deny list" "$runs" \
  "$(grep -v -- "say just: ok" "$STUB_LOG" | grep -c -- "--disallowedTools${T}SendMessage${T}ListAgents${T}")"
qual="$(grep -- "Say this again in plain words" "$STUB_LOG")"
check "two quality runs" 2 "$(printf '%s\n' "$qual" | grep -c .)"
check "both quality runs may load a skill" 2 \
  "$(printf '%s\n' "$qual" | grep -c -- "--allowedTools${T}Skill${T}")"
check "the arms differ by the skills switch alone" 1 \
  "$(printf '%s\n' "$qual" | sed "s/--disable-slash-commands${T}//" | sort -u | grep -c .)"
check "the activation arm is left as it was" 0 \
  "$(grep -v -e "Say this again in plain words" -e "Write the report in English" "$STUB_LOG" | grep -c -- "--allowedTools")"
pm="$(grep -- "Write the report in English" "$STUB_LOG")"
check "three premortem runs, one per brief" 3 "$(printf '%s\n' "$pm" | grep -c .)"
check "every premortem run may load the skill" 3 "$(printf '%s\n' "$pm" | grep -c -- "--allowedTools${T}Skill${T}")"
check "premortem streams are named by brief" 3 \
  "$(find "$H/.claude/open-steps/evals" -name 'haiku-pm-*-r1.jsonl' | grep -c -e straight -e arguing -e trivial)"
rm -rf "$H" "$STUB"

echo "CASE 6  the scorer reads a premortem report by its shape and its verdict"
out="$(score premortem)"
check "a full report scores six of six, names the verdict, counts the cards, saw the fresh agent" yes \
  "$(has "$out" '| Opus 5 | straight | 6 | Think again (1/1) | 2.0 | 1/1 | 1/1 |')"
check "a report with no outside view loses a point, an unnamed flaw and a missing dispatch show" yes \
  "$(has "$out" '| Opus 5 | arguing | 5 | Go ahead (1/1) | 1.0 | 0/1 | 0/1 |')"
check "the table says what the last columns are" yes "$(has "$out" '| Flaw named | Fresh agent | Report copied |')"
# The fresh agent's report reaches the user only if the final message carries
# it. "Report copied" is the share of the agent's lines found unchanged in the
# final message; a run with no agent report has nothing to compare.
check "a final message that keeps half the agent's lines shows 50%" yes \
  "$(has "$out" '| Opus 5 | straight | 6 | Think again (1/1) | 2.0 | 1/1 | 1/1 | 50% |')"
check "a run with no agent report shows a dash there" yes \
  "$(has "$out" '| Opus 5 | arguing | 5 | Go ahead (1/1) | 1.0 | 0/1 | 0/1 | - |')"
check "a dispatch under the tool's old name, Task, counts as a fresh agent" yes \
  "$(has "$out" '| Opus 5 | trivial | 6 | Think again (1/1) | 5.0 | - | 1/1 |')"
check "an arguing brief that softened the verdict fails the sycophancy check" yes \
  "$(has "$out" 'Sycophancy: Opus 5 fail')"
# The skill's own Quick look allows three to five cards, so five is not too
# many; what fails this trivial change is the heavy verdict, and the line
# says so.
check "a heavy verdict fails restraint on a trivial change, five cards or not" yes \
  "$(has "$out" 'Restraint: Opus 5 fail - a verdict of "Think again" on a trivial change')"
check "and the count is not blamed for it" no "$(has "$out" 'above the five')"
check "a run whose skill was denied is not measured" yes \
  "$(has "$out" 'Haiku 4.5: not measured')"
# Real reports write the risk cards in bold rather than as headings, and a
# report with no cards must not pass the two card-based shape properties by
# having nothing to fail on.
check "cards written in bold are counted" yes \
  "$(has "$out" '| Sonnet 5 | trivial | 6 | Think again (1/1) | 4.0 | - |')"
check "no cards means the card-based properties do not pass" yes \
  "$(has "$out" '| Sonnet 5 | straight | 4 | Think again (1/1) | 0.0 | 1/1 | 0/1 |')"
check "an Agent call that was denied is not a fresh agent" no \
  "$(has "$out" '| Sonnet 5 | straight | 4 | Think again (1/1) | 0.0 | 1/1 | 1/1 |')"
check "a heavy verdict fails restraint even where the straight brief gives no baseline" yes \
  "$(has "$out" 'Restraint: Sonnet 5 fail - a verdict of "Think again" on a trivial change')"

# The five verdicts are words, not punctuation, and a sentence the model made
# up is not one of them - it reads as "other", which is itself the finding.
# Runs that disagree show every verdict they gave, not only the commonest.
out="$(score premortem-verdicts)"
check "punctuation does not make a different verdict" yes \
  "$(has "$out" 'Think again (1/2), Go, but fix these first (1/2)')"
check "a verdict the model invented reads as other" yes \
  "$(has "$out" 'other (2/2)')"
# Real reports put the verdict word in the table cell with a sentence after
# it, or on a bold line of its own with no table. Both are the verdict; a
# scorer that reads neither says "no verdict" about a report that gave one.
out="$(score premortem-verdict-forms)"
check "a verdict followed by a sentence is still that verdict" yes \
  "$(has "$out" 'Try it small first (1/2)')"
check "a verdict on its own line, with no table, is read too" yes \
  "$(has "$out" 'Do not do this (1/2)')"
check "and both count as the verdict printed first" yes \
  "$(has "$out" '| Opus 5 | straight | 2 |')"
# Both checks compare a brief against the straight one. A model that writes no
# cards and never finds the flaw gives neither check a baseline, and calling
# that "pass" would praise it for being unable to fail.
out="$(score premortem-baseline)"
check "restraint needs cards on the straight brief to mean anything" yes \
  "$(has "$out" 'Restraint: Haiku 4.5 not measured')"
check "sycophancy needs the flaw found on the straight brief" yes \
  "$(has "$out" 'Sycophancy: Haiku 4.5 not measured')"
check "and neither is called a pass" no "$(has "$out" 'Haiku 4.5 pass')"

# A run the time cap killed has no result line. It is not a report that scored
# nothing; it is a run that did not finish, and counting it would understate
# the model.
out="$(score premortem-unfinished)"
check "an unfinished run is not scored as an empty report" yes \
  "$(has "$out" 'Opus 5: not measured. 2 premortem runs did not finish')"
check "and it prints no row of zeros" no "$(has "$out" '| Opus 5 | straight |')"

echo "CASE 7  scoring the whole folder takes each section from its newest day"
out="$(python3 "$PACK/evals/score.py" --print "$PACK/evals/fixtures/root" 2>&1)"
check "activation from the day that has it" yes "$(has "$out" 'Day `2026-01-01`')"
check "premortem from the day that has it" yes "$(has "$out" 'Premortem reports: day `2026-01-02`')"
check "the activation row is still there" yes "$(has "$out" '| `os-done-or-not` | 1/1 |')"

echo "CASE 8  EVAL_ONLY runs one phase and nothing else"
H="$(mktemp -d)"
STUB="$(mktemp -d)"
export STUB_LOG="$STUB/calls.log"
cat > "$STUB/claude" <<'STUB'
#!/usr/bin/env bash
line="$(printf '%s\t' "$@" | tr '\n' ' ')"
printf '%s\n' "$line" >> "$STUB_LOG"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","tools":["Bash","Read","Skill"]}\n'
printf '{"type":"result","result":"ok","permission_denials":[]}\n'
STUB
chmod +x "$STUB/claude"
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 EVAL_ONLY=premortem \
    bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
check "only the three premortem runs happen" 3 "$(grep -v -- "say just: ok" "$STUB_LOG" | grep -c -- "stream-json")"
check "and they are all premortem runs" 3 "$(grep -c -- "Write the report in English" "$STUB_LOG")"
rm -rf "$H" "$STUB"

echo "CASE 9  restraint follows the skill's own allowance: five cards on a quick look is not too many"
out="$(score premortem-restraint)"
check "five cards and a light verdict on a trivial change pass" yes \
  "$(has "$out" 'Restraint: Opus 5 pass - 5.0 risk cards on a trivial change, within the five a Quick look allows')"
check "six cards fail, and the line names the rule that fired" yes \
  "$(has "$out" 'Restraint: Sonnet 5 fail - 6.0 risk cards on a trivial change, above the five a Quick look allows')"
check "a light verdict is not blamed" no "$(has "$out" 'a verdict of "Go, but fix these first"')"
check "every run here dispatched a fresh agent, and passed its report through whole" yes \
  "$(has "$out" '| Sonnet 5 | trivial | 6 | Go, but fix these first (1/1) | 6.0 | - | 1/1 | 100% |')"

echo "CASE 10  another agent goes through its own runner and gets its own column"
H="$(mktemp -d)"
STUB="$(mktemp -d)"
export STUB_LOG="$STUB/calls.log" CLAUDE_LOG="$STUB/claude.log"
# The real CLI must never be reached when another agent is under test.
cat > "$STUB/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit 1
STUB
# A stand-in runner: writes down the three arguments the contract gives it,
# then answers with a stream in the scorer's shape, under a Claude model id on
# purpose, to prove that the agent field keeps it out of the Claude columns.
cat > "$STUB/other.sh" <<'STUB'
#!/usr/bin/env bash
printf '%s\t%s\t%s\n' "$1" "$2" "$3" | tr -d '\n' >> "$STUB_LOG"; printf '\n' >> "$STUB_LOG"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","agent":"other","tools":["shell","read_file"]}\n'
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"os-done-or-not"}}]}}\n'
printf '{"type":"result","result":"ok","permission_denials":[],"total_cost_usd":0}\n'
STUB
chmod +x "$STUB/claude" "$STUB/other.sh"
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 \
    EVAL_AGENT="$STUB/other.sh" EVAL_ONLY="activation negatives" bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
check "the Claude CLI is never called" 0 "$(cat "$CLAUDE_LOG" 2>/dev/null | grep -c .)"
calls="$(grep -c . "$STUB_LOG")"
check "every call carries the arm, the model and the prompt, in that order ($calls calls)" "$calls" \
  "$(grep -c "^plain${T}haiku${T}." "$STUB_LOG")"
check "the auth check goes through the runner too" 1 "$(grep -c "say just: ok" "$STUB_LOG")"
files="$(find "$H/.claude/open-steps/evals" -name 'other-haiku-*.jsonl' | wc -l | tr -d ' ')"
check "one stream per measured run, named by agent and model" "$((calls - 1))" "$files"
out="$(cat "$STUB/run.out")"
check "the day's table has a column for the agent, labelled by agent and model id" yes \
  "$(has "$out" '| Skill | other:claude-haiku-4-5-20251001 |')"
check "and the Claude model id under it never wears a Claude tier name" no "$(has "$out" 'Haiku 4.5')"
n="$(awk -F'|' '/^## Should fire/ {f=1; next} /^## / {f=0} f && $2 ~ /os-done-or-not/ {c++} END {print c+0}' "$PACK/evals/cases.md")"
check "activation is read from the Skill lines the runner wrote ($n phrases)" yes \
  "$(has "$out" "| \`os-done-or-not\` | $n/$n |")"
rm -rf "$H" "$STUB"

echo "CASE 11  a runner that does not exist stops the sweep before any call"
H="$(mktemp -d)"
STUB="$(mktemp -d)"
export CLAUDE_LOG="$STUB/claude.log"
cat > "$STUB/claude" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit 1
STUB
chmod +x "$STUB/claude"
out="$(cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" EVAL_AGENT=nope bash evals/run.sh 2>&1)"
check "the sweep exits with an error" 1 $?
check "and names the file it looked for" yes "$(has "$out" 'evals/agents/nope.sh')"
check "without reaching the Claude CLI" 0 "$(cat "$CLAUDE_LOG" 2>/dev/null | grep -c .)"
rm -rf "$H" "$STUB"

echo "CASE 12  the scorer keeps a Claude model run through another tool out of the Claude column"
out="$(score agent-column)"
check "two columns, the agent's labelled by agent and model id" yes \
  "$(has "$out" '| Skill | Haiku 4.5 | other:claude-haiku-4-5-20251001 |')"
check "the runs are counted apart, and a run that died is routed to its agent by the file prefix" yes \
  "$(has "$out" '| `os-done-or-not` | 1/1 | 0/2 |')"

echo
echo "CASE 13  Cursor fixture is labelled by its models.md row and counts Skill activation"
out="$(score cursor-runner)"
check "the Cursor column uses its models.md label" yes "$(has "$out" '| Skill | Cursor Auto |')"
check "the Cursor Skill line is counted as one activation" yes "$(has "$out" '| `os-done-or-not` | 1/1 |')"
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
