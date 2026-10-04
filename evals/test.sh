#!/usr/bin/env bash
# Checks for the measurement scripts. Run from anywhere:  bash evals/test.sh
# Nothing here talks to a model. The scorer reads the hand-made streams in
# fixtures/.
# The runners are driven with a stand-in `claude`, `codex` or `gemini` on PATH that
# writes down what it was asked and answers with a short stream. HOME points
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
# count TEXT PATTERN: how many times PATTERN occurs in TEXT, several on one
# line counted apart.
count() { local text="$1"; shift; printf '%s\n' "$text" | grep -o "$@" | grep -c .; }
# The recording stand-ins write their arguments down tab-separated.
TAB=$'\t'
# stand_in NAME: the script on stdin becomes the stand-in NAME.
stand_in() { cat > "$STUB/$1" && chmod +x "$STUB/$1"; }
# A throwaway folder of stand-ins, put first on PATH by the case that makes
# it. Every file a stand-in writes is named here: how it was called in
# STUB_LOG, or CLAUDE_LOG for a claude that must not be reached, and what
# arrived on its stdin in STUB_STDIN. stub-record is the line a recording
# stand-in starts with: its arguments as one line of STUB_LOG, tab-separated.
new_stubs() {
  STUB="$(mktemp -d)"
  export STUB_LOG="$STUB/calls.log" CLAUDE_LOG="$STUB/claude.log" STUB_STDIN="$STUB/stdin"
  stand_in stub-record <<'STUB'
#!/usr/bin/env bash
line="$(printf '%s\t' "$@" | tr '\n' ' ')"
printf '%s\n' "$line" >> "$STUB_LOG"
STUB
}
# Stand-in for the CLI: one line per call, tokens tab-separated, then a stream
# just long enough for the scorer to read a model out of it.
recording_claude() {
  stand_in claude <<'STUB'
#!/usr/bin/env bash
stub-record "$@"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","tools":["Bash","Read","Skill"]}\n'
printf '{"type":"result","result":"ok","permission_denials":[]}\n'
STUB
}
# The real CLI must never be reached when another agent is under test.
unreachable_claude() {
  stand_in claude <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit 1
STUB
}

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
new_stubs
recording_claude
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 \
    bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
# The auth check is one more call through the runner; it is not a measured run.
runs="$(grep -v -- "say just: ok" "$STUB_LOG" | grep -c -- "stream-json")"
files="$(find "$H/.claude/open-steps/evals" -name '*.jsonl' | wc -l | tr -d ' ')"
check "one stream per run ($runs runs)" "$runs" "$files"
check "every run carries the deny list" "$runs" \
  "$(grep -v -- "say just: ok" "$STUB_LOG" | grep -c -- "--disallowedTools${TAB}SendMessage${TAB}ListAgents${TAB}")"
qual="$(grep -- "Say this again in plain words" "$STUB_LOG")"
check "two quality runs" 2 "$(printf '%s\n' "$qual" | grep -c .)"
check "both quality runs may load a skill" 2 \
  "$(printf '%s\n' "$qual" | grep -c -- "--allowedTools${TAB}Skill${TAB}")"
check "the arms differ by the skills switch alone" 1 \
  "$(printf '%s\n' "$qual" | sed "s/--disable-slash-commands${TAB}//" | sort -u | grep -c .)"
check "the activation arm is left as it was" 0 \
  "$(grep -v -e "Say this again in plain words" -e "Write the report in English" "$STUB_LOG" | grep -c -- "--allowedTools")"
pm="$(grep -- "Write the report in English" "$STUB_LOG")"
check "three premortem runs, one per brief" 3 "$(printf '%s\n' "$pm" | grep -c .)"
check "every premortem run may load the skill" 3 "$(printf '%s\n' "$pm" | grep -c -- "--allowedTools${TAB}Skill${TAB}")"
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
new_stubs
recording_claude
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
new_stubs
unreachable_claude
# A stand-in runner: writes down the three arguments the contract gives it,
# then answers with a stream in the scorer's shape, under a Claude model id on
# purpose, to prove that the agent field keeps it out of the Claude columns.
stand_in other.sh <<'STUB'
#!/usr/bin/env bash
stub-record "$@"
printf '{"type":"system","subtype":"init","model":"claude-haiku-4-5-20251001","agent":"other","tools":["shell","read_file"]}\n'
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"os-done-or-not"}}]}}\n'
printf '{"type":"result","result":"ok","permission_denials":[],"total_cost_usd":0}\n'
STUB
( cd "$PACK" && HOME="$H" PATH="$STUB:$PATH" N_RUNS=1 EVAL_MODEL=haiku EVAL_PARALLEL=1 \
    EVAL_AGENT="$STUB/other.sh" EVAL_ONLY="activation negatives" bash evals/run.sh > "$STUB/run.out" 2>&1 )
check "the runner finishes" 0 $?
check "the Claude CLI is never called" 0 "$(cat "$CLAUDE_LOG" 2>/dev/null | grep -c .)"
calls="$(grep -c . "$STUB_LOG")"
check "every call carries the arm, the model and the prompt, in that order ($calls calls)" "$calls" \
  "$(grep -c "^plain${TAB}haiku${TAB}." "$STUB_LOG")"
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
new_stubs
unreachable_claude
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

echo "CASE 13  the Codex runner turns a read of SKILL.md into one Skill call"
H="$(mktemp -d)"
new_stubs
# A stand-in codex: writes down its arguments and what arrived on stdin, then
# answers with events in the shape `codex exec --json` writes. A Skill call's
# id is the item's id and the skill's name. The commands in it, by item:
#   1  reads os-done-or-not, seen as started and again as completed
#   0, 2, 3  list the skills, read a file under references/ and a SKILL.md
#      that is not the pack's, search and test a SKILL.md: no opening
#   4  reads os-say-simple after a cd into skills/; the sandbox declines it
#   5, 6  read os-check-work and os-whats-next with a | or a ; inside a
#      quoted argument, which does not cut the command
#   8  reads a bare SKILL.md after a cd into os-big-picture's folder
#   9  names no SKILL.md, but prints os-ask-simple's whole file
#   10  greps os-step-by-step's SKILL.md and prints only the matching line:
#      no opening
#   11  cds into os-step-by-step's folder in a subshell, then reads the
#      SKILL.md of the folder it is back in: no opening
#   12  edits os-step-by-step's SKILL.md with sed -i and writes it with a >:
#      no opening
#   13  after an if's then, reads two skills with one cat
#   14  reads through time, env and command, and after a pushd
#   15  reads inside a quoted $( ) and inside backticks
#   16  writes a heredoc whose text names a SKILL.md: no opening
#   17  has a ) that no ( opened, so the shell runs none of it: no opening
#   18  reads os-ask-simple in a case pattern, whose ) no ( opened
#   19  reads os-say-simple after a ) in quotes, with one in a comment
#   20  reads os-check-work after a << in quotes, which opens no heredoc
#   21  reads SKILL.md.bak, and a $( ) in single quotes, which is text: no
#      opening
#   22  reads os-whats-next after a heredoc whose delimiter is E'OF'
#   23  reads os-big-picture through env -u NAME
#   24  leaves a quote open, so the shell runs none of it: no opening
#   25  prints another run's stream, which holds os-ask-simple's file inside
#      a JSON string: no opening
#   26  names no SKILL.md, but prints os-ask-simple's file numbered, as
#      grep -n does
stand_in codex <<'STUB'
#!/usr/bin/env bash
stub-record "$@"
cat > "$STUB_STDIN"
[ -n "${STUB_FAIL:-}" ] && { echo "Not logged in" >&2; exit 1; }
cat <<'J'
{"type":"thread.started","thread_id":"t-1"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"/bin/bash -lc 'ls ~/.agents/skills'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc \"sed -n '1,200p' ~/.agents/skills/os-done-or-not/SKILL.md\"","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc \"sed -n '1,200p' ~/.agents/skills/os-done-or-not/SKILL.md\"","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"command_execution","command":"cat ~/.agents/skills/os-whats-next/references/a.md /x/not-os-done-or-not/SKILL.md","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/bash -lc 'grep -l name ~/.agents/skills/os-whats-next/SKILL.md; test -f ~/.agents/skills/os-check-work/SKILL.md'","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":["/bin/bash","-lc","cd ~/.agents/skills && cat os-say-simple/SKILL.md"],"aggregated_output":"","exit_code":1,"status":"declined"}}
{"type":"item.completed","item":{"id":"item_5","type":"command_execution","command":"/bin/bash -lc \"awk '/^#|^-/' ~/.agents/skills/os-check-work/SKILL.md\"","aggregated_output":"","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_6","type":"command_execution","command":["sed","-n","/name;description/p","/home/u/.agents/skills/os-whats-next/SKILL.md"],"aggregated_output":"","exit_code":0,"status":"completed"}}
J
# The rest are written by python, which quotes them.
python3 - "$STUB_SKILL" <<'PY'
import json, sys
S = "~/.agents/skills/"


def item(n, command, output="", status="completed"):
    print(json.dumps({"type": "item.completed", "item": {
        "id": f"item_{n}", "type": "command_execution", "command": command,
        "aggregated_output": output, "exit_code": 0, "status": status}}))


item(8, f"/bin/zsh -lc \"cd {S}os-big-picture && sed -n '1,240p' SKILL.md\"")
item(9, f'/bin/zsh -lc "find {S}os-ask-simple -name S*.md | xargs cat"', open(sys.argv[1]).read())
item(10, f"/bin/zsh -lc 'grep -n name {S}os-step-by-step/SKILL.md'", "2:name: os-step-by-step\n")
item(11, f"/bin/zsh -lc '(cd {S}os-step-by-step); cat SKILL.md'", status="failed")
item(12, f'/bin/zsh -lc "sed -i s/a/b/ {S}os-step-by-step/SKILL.md; echo x | cat > {S}os-step-by-step/SKILL.md"', status="failed")
item(13, f"if [ -f {S}os-what-could-go-wrong/SKILL.md ]; then cat {S}os-what-could-go-wrong/SKILL.md {S}os-done-or-not/SKILL.md; fi")
item(14, f"time env LC_ALL=C command cat {S}os-say-simple/SKILL.md; pushd {S}os-check-work && head SKILL.md")
item(15, f'x="$(cat {S}os-whats-next/SKILL.md)"; echo "`sed -n 1p {S}os-big-picture/SKILL.md`"')
item(16, f"cat > /tmp/notes.md <<'E'\nhead {S}os-step-by-step/SKILL.md\nE")
item(17, f"cd {S}os-step-by-step; echo ) ; cat SKILL.md", status="failed")
item(18, f"case $x in a) cat {S}os-ask-simple/SKILL.md;; esac")
item(19, f"tr ')' ']' </dev/null; cat {S}os-say-simple/SKILL.md # done)")
item(20, f"git log --grep='<<END'\ncat {S}os-check-work/SKILL.md")
item(21, f"cat {S}os-step-by-step/SKILL.md.bak; echo '$(cat {S}os-step-by-step/SKILL.md)'")
item(22, f"cat > /tmp/notes.md <<E'OF'\nhead {S}os-step-by-step/SKILL.md\nEOF\ncat {S}os-whats-next/SKILL.md")
item(23, f"env -u HOME cat {S}os-big-picture/SKILL.md")
item(24, f'cat "{S}os-step-by-step/SKILL.md', status="failed")
text = open(sys.argv[1]).read()
item(25, "tail -n 40 ~/.claude/open-steps/evals/day/codex-run.jsonl", json.dumps({"aggregated_output": text}) + "\n")
item(26, f"grep -rn '' {S}os-ask-simple/", "".join(f"{n}:{line}\n" for n, line in enumerate(text.splitlines(), 1)))
PY
cat <<'J'
{"type":"item.completed","item":{"id":"item_7","type":"agent_message","text":"Done: yes."}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1}}
J
STUB
out="$(cd "$STUB" && echo "piped" | HOME="$H" STUB_SKILL="$PACK/skills/os-ask-simple/SKILL.md" PATH="$STUB:$PATH" \
  bash "$PACK/evals/agents/codex.sh" plain gpt-6-sol "Are we done?")"
check "the runner finishes" 0 $?
check "one run, read-only and ephemeral, the model and the prompt passed through" 1 \
  "$(grep -c -- "^exec${TAB}--json${TAB}--ephemeral${TAB}--sandbox${TAB}read-only${TAB}--model${TAB}gpt-6-sol${TAB}--${TAB}Are we done?${TAB}$" "$STUB_LOG")"
check "nothing piped reaches codex, so the phrase arrives alone" 0 "$(wc -c < "$STUB_STDIN" | tr -d ' ')"
check "the init line names the model asked for and the agent" 1 \
  "$(count "$out" '"subtype": "init", "model": "gpt-6-sol", "agent": "codex"')"
check "one Skill call per skill opened, 18 in all, none for a search, a test or a write" 18 \
  "$(count "$out" '"name": "Skill"')"
check "a read codex reports as started and again as completed is called once" 1 \
  "$(count "$out" '"id": "item_1-os-done-or-not"')"
check "the call carries the skill's short name" 1 \
  "$(count "$out" '"id": "item_1-os-done-or-not", "name": "Skill", "input": {"skill": "os-done-or-not"}')"
check "a | or a ; inside quotes does not cut the read apart" 2 \
  "$(count "$out" -e '"id": "item_5-os-check-work"' -e '"id": "item_6-os-whats-next"')"
check "a bare SKILL.md read after a cd into the skill's folder counts" 1 "$(count "$out" '"id": "item_8-os-big-picture"')"
check "a command that names no SKILL.md but prints one, whole or numbered, counts" 2 \
  "$(count "$out" -e '"id": "item_9-os-ask-simple"' -e '"id": "item_26-os-ask-simple"')"
check "a matching line, a cd that ended with its subshell, a write, text, a refused script and a quoted SKILL.md do not" 0 \
  "$(count "$out" -E '"id": "item_(0|2|3|10|11|12|16|17|21|24|25)-')"
check "a read after then, of two skills, gives one line with both calls" 1 \
  "$(printf '%s\n' "$out" | grep -F '"id": "item_13-os-what-could-go-wrong"' | grep -cF '"id": "item_13-os-done-or-not"')"
check "a read through time, env, env -u NAME and command, and one after a pushd, count" 3 \
  "$(count "$out" -e '"id": "item_14-os-say-simple"' -e '"id": "item_14-os-check-work"' -e '"id": "item_23-os-big-picture"')"
check "a ) in a case pattern, in quotes or in a comment, and a << in quotes, cut nothing" 3 \
  "$(count "$out" -e '"id": "item_18-os-ask-simple"' -e '"id": "item_19-os-say-simple"' -e '"id": "item_20-os-check-work"')"
check "a heredoc ends at its delimiter with the quotes taken off, and the read after it counts" 1 \
  "$(count "$out" '"id": "item_22-os-whats-next"')"
check "a read inside a quoted \$( ) and inside backticks counts" 2 \
  "$(count "$out" -e '"id": "item_15-os-whats-next"' -e '"id": "item_15-os-big-picture"')"
check "a read the sandbox declined still counts, and is listed as refused" 1 \
  "$(count "$out" '"permission_denials": \[{"tool_name": "Skill", "tool_use_id": "item_4-os-say-simple"}\]')"
check "the result line carries the last message" 1 "$(count "$out" '"type": "result", "result": "Done: yes."')"
check "codex's own events pass through" 1 "$(count "$out" '"type": "turn.completed"')"
( cd "$STUB" && HOME="$H" STUB_FAIL=1 PATH="$STUB:$PATH" bash "$PACK/evals/agents/codex.sh" plain gpt-6-sol "say just: ok" >/dev/null 2>&1 )
check "a codex that fails fails the runner, so the auth check stops the sweep" 1 $?
for arm in with without; do
  err="$(HOME="$H" PATH="$STUB:$PATH" bash "$PACK/evals/agents/codex.sh" "$arm" gpt-6-sol x 2>&1 >/dev/null)"
  check "the $arm arm exits 2" 2 $?
  check "with one line on stderr" 1 "$(printf '%s\n' "$err" | grep -c .)"
done
rm -rf "$H" "$STUB"
# fixtures/codex/ is hand-made in the shape this runner writes, Codex's own
# events kept: an init line after thread.started, each Skill call as its
# read starts, with an id made of the item and the skill, and a result line.
# In the run of the first os-done-or-not phrase the agent opened that skill
# and then os-big-picture, as gpt-6-sol often opens a second; in the run of
# the second it opened os-big-picture alone, the wrong skill, which is a miss.
out="$(score codex)"
check "the scorer labels the Codex column by its models.md row" yes \
  "$(has "$out" '| Skill | GPT-6 Sol (Codex) |')"
check "a run that opened the skill asked for is a hit, and one that opened only another a miss" yes \
  "$(has "$out" '| `os-done-or-not` | 1/2 |')"
check "a day with no quality or premortem runs says both were not run" 2 "$(count "$out" -x 'Not run.')"
check "a column from another tool says where its meaning is defined" yes "$(has "$out" 'defined in that runner')"

echo "CASE 14  the Gemini CLI runner turns an activate_skill call into one Skill call"
H="$(mktemp -d)"
new_stubs
# A stand-in gemini: writes down its arguments and what arrived on stdin,
# then answers with events in the shape `gemini -p -o stream-json` writes.
# A Skill call's id is the call's own id. The calls in it:
#   call_1  activates os-done-or-not; the tool comes back not registered,
#           as it does headless without --yolo
#   call_2  activates os-big-picture, and this one succeeds
#   call_3  activates a skill that is not the pack's: no line
#   call_4  reads os-say-simple's SKILL.md with the file tool: no line
#   call_5  runs a shell command: no line
# The answer arrives in two delta pieces and one whole message.
stand_in gemini <<'STUB'
#!/usr/bin/env bash
stub-record "$@"
cat > "$STUB_STDIN"
[ -n "${STUB_FAIL:-}" ] && { echo "Authentication failed" >&2; exit 1; }
cat <<'J'
{"type":"init","timestamp":"t","session_id":"s-1","model":"gemini-3.5-flash-lite"}
{"type":"message","timestamp":"t","role":"user","content":"<hook_context>...</hook_context>\n\nAre we done?"}
{"type":"tool_use","timestamp":"t","tool_name":"activate_skill","tool_id":"activate_skill__call_1","parameters":{"name":"os-done-or-not"}}
{"type":"tool_result","timestamp":"t","tool_id":"activate_skill__call_1","status":"error","output":"Tool \"activate_skill\" not found.","error":{"type":"tool_not_registered","message":"Tool \"activate_skill\" not found."}}
{"type":"tool_use","timestamp":"t","tool_name":"activate_skill","tool_id":"activate_skill__call_2","parameters":{"name":"os-big-picture"}}
{"type":"tool_result","timestamp":"t","tool_id":"activate_skill__call_2","status":"success","output":"Skill **os-big-picture** activated."}
{"type":"tool_use","timestamp":"t","tool_name":"activate_skill","tool_id":"activate_skill__call_3","parameters":{"name":"someone-elses-skill"}}
{"type":"tool_result","timestamp":"t","tool_id":"activate_skill__call_3","status":"error","output":"Skill \"someone-elses-skill\" not found.","error":{"type":"invalid_tool_params","message":"Skill not found."}}
{"type":"tool_use","timestamp":"t","tool_name":"read_file","tool_id":"read_file__call_4","parameters":{"file_path":"/home/u/.agents/skills/os-say-simple/SKILL.md"}}
{"type":"tool_result","timestamp":"t","tool_id":"read_file__call_4","status":"error","output":"Path not in workspace","error":{"type":"invalid_tool_params","message":"Path not in workspace"}}
{"type":"tool_use","timestamp":"t","tool_name":"run_shell_command","tool_id":"run_shell_command__call_5","parameters":{"command":"cat ~/.agents/skills/os-check-work/SKILL.md"}}
{"type":"tool_result","timestamp":"t","tool_id":"run_shell_command__call_5","status":"error","output":"Tool \"run_shell_command\" not found.","error":{"type":"tool_not_registered","message":"Tool \"run_shell_command\" not found."}}
{"type":"message","timestamp":"t","role":"assistant","content":"Done: ","delta":true}
{"type":"message","timestamp":"t","role":"assistant","content":"yes.","delta":true}
{"type":"message","timestamp":"t","role":"assistant","content":" Nothing landed."}
J
if [ -n "${STUB_UNFINISHED:-}" ]; then
  echo '{"type":"result","timestamp":"t","status":"error","error":{"type":"RESOURCE_EXHAUSTED","message":"quota"},"stats":{"total_tokens":1}}'
else
  echo '{"type":"result","timestamp":"t","status":"success","stats":{"total_tokens":1,"tool_calls":5}}'
fi
STUB
out="$(cd "$STUB" && echo "piped" | HOME="$H" PATH="$STUB:$PATH" \
  bash "$PACK/evals/agents/gemini-cli.sh" plain gemini-3.5-flash-lite "Are we done?")"
check "the runner finishes" 0 $?
check "one headless run in the stream shape, untrusted, the prompt and the model passed through" 1 \
  "$(grep -c -- "^-p${TAB}Are we done?${TAB}-m${TAB}gemini-3.5-flash-lite${TAB}-o${TAB}stream-json${TAB}--skip-trust${TAB}$" "$STUB_LOG")"
check "nothing piped reaches gemini, so the phrase arrives alone" 0 "$(wc -c < "$STUB_STDIN" | tr -d ' ')"
check "the init line names the model the stream carries and the agent" 1 \
  "$(count "$out" '"subtype": "init", "model": "gemini-3.5-flash-lite", "agent": "gemini-cli"')"
check "one Skill call per pack skill activated, none for another skill, a file read or a shell command" 2 \
  "$(count "$out" '"name": "Skill"')"
check "the call carries the tool's own id and the skill's short name" 1 \
  "$(count "$out" '"id": "activate_skill__call_1", "name": "Skill", "input": {"skill": "os-done-or-not"}')"
check "a call that came back not registered is listed as refused, one that ran is not" 1 \
  "$(count "$out" '"permission_denials": \[{"tool_name": "Skill", "tool_use_id": "activate_skill__call_1"}\]')"
check "the result line carries the answer, delta pieces and whole messages joined" 1 \
  "$(count "$out" '"type": "result", "result": "Done: yes. Nothing landed."')"
check "gemini's own events pass through" 1 "$(count "$out" '"type": "tool_result", "timestamp": "t", "tool_id": "activate_skill__call_2"')"
out="$(cd "$STUB" && HOME="$H" STUB_UNFINISHED=1 PATH="$STUB:$PATH" \
  bash "$PACK/evals/agents/gemini-cli.sh" plain gemini-3.5-flash-lite "Are we done?" 2>/dev/null)"
check "a run whose result is an error writes no result line, so the scorer sees it unfinished" 0 \
  "$(count "$out" '"type": "result", "result":')"
check "and still keeps the call the model made" 1 "$(count "$out" '"skill": "os-done-or-not"')"
( cd "$STUB" && HOME="$H" STUB_FAIL=1 PATH="$STUB:$PATH" bash "$PACK/evals/agents/gemini-cli.sh" plain gemini-3.5-flash-lite "say just: ok" >/dev/null 2>&1 )
check "a gemini that fails fails the runner, so the auth check stops the sweep" 1 $?
for arm in with without; do
  err="$(HOME="$H" PATH="$STUB:$PATH" bash "$PACK/evals/agents/gemini-cli.sh" "$arm" gemini-3.5-flash-lite x 2>&1 >/dev/null)"
  check "the $arm arm exits 2" 2 $?
  check "with one line on stderr" 1 "$(printf '%s\n' "$err" | grep -c .)"
done
rm -rf "$H" "$STUB"
# fixtures/gemini-cli/ is hand-made in the shape this runner writes, Gemini's
# own events kept: an init line after Gemini's, each Skill call as its
# activate_skill call arrives, under the call's own id, and a result line
# listing the calls that came back not registered. In the run of the first
# os-done-or-not phrase the agent activated that skill and then
# os-big-picture; in the run of the second it activated os-big-picture alone,
# the wrong skill, which is a miss.
out="$(score gemini-cli)"
check "the scorer labels the Gemini CLI column by its models.md row" yes \
  "$(has "$out" '| Skill | Gemini 3.5 Flash Lite (Gemini CLI) |')"
check "an activation the tool refused still counts as the model's choice: a hit for the right skill, a miss for another" yes \
  "$(has "$out" '| `os-done-or-not` | 1/2 |')"

echo
echo "CASE 15  Cursor fixture is labelled by its models.md row and counts Skill activation"
out="$(score cursor-runner)"
check "the Cursor column uses its models.md label" yes "$(has "$out" '| Skill | Cursor (Auto) |')"
check "the Cursor Skill line is counted as one activation" yes "$(has "$out" '| `os-done-or-not` | 1/1 |')"
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
