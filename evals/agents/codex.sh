#!/usr/bin/env bash
# The runner for Codex CLI: one measured run, as evals/run.sh asks for it.
#
# Called like every runner in this folder, inside a throwaway git repository:
#   evals/agents/codex.sh ARM MODEL PROMPT
# The contract is in evals/README.md, "Measuring another agent". The pack is
# installed the way docs/other-agents.md says: the skills copied into
# ~/.agents/skills/, the routing block in ~/.codex/AGENTS.md. What is measured
# is whether that install switches on by itself, so nothing here points Codex
# at a skill.
#
# What counts as opening a skill: a shell command that reads a pack skill's
# SKILL.md. Codex has no skill tool. It lists each skill with the location of
# its SKILL.md, and its own instructions say the agent must read that file
# before acting on the skill, so the read is the choice. A command is an
# opening when either of these holds, and it makes one Skill call per skill
# it opened: a command that opened two gives one line with two calls, as
# Claude Code writes two calls made at once.
#   - The command names the file. The script is read the way the shell
#     reads it, quotes and all, and cut into simple commands at ;, &, |, a
#     newline, ( and ). One of them runs cat, sed, head, tail, nl, less,
#     more, bat or awk on a path ending in <skill>/SKILL.md, where <skill>
#     is the name of a folder in this pack's skills/ that holds a SKILL.md,
#     in whatever folder the path runs through. SKILL.md.bak is another
#     file. The program is the first word past any shell keyword (if, then,
#     do and the like), a { and the wrappers time, env, command, exec and
#     nohup with their options. The inside of a $( ) or of backticks, bare,
#     in double quotes or in an unquoted heredoc's lines, is a script of its
#     own; in single quotes it is text.
#   - The output shows the file. The command finished and what it printed
#     holds each of the first three non-empty lines of the skill's
#     instructions, the ones after the frontmatter, each on a line of its
#     own after at most a file name or a line number (grep -n, rg, nl). A
#     SKILL.md quoted inside other text, as in another run's transcript, is
#     not shown. This catches the reads
#     no command line names: a `find ... | xargs cat`, a glob, a path in a
#     variable, a python open(), a `grep ''` or `rg -n .`.
# A relative path is read from the last cd or pushd in the same script, so
# `cd ~/.agents/skills/os-x && cat SKILL.md` counts; a popd goes back, and a
# cd inside ( ) ends where the subshell does.
# Not an opening:
#   - a command that lists, searches or tests the skills folder (ls, grep -l,
#     rg, find, test) and prints no more than names or a matching line;
#   - a read of a file under references/;
#   - a write: a path after >, >>, 2> or &>, and a sed or awk that edits in
#     place;
#   - `command -v cat`, which looks cat up and runs nothing;
#   - what quotes, a comment or a heredoc's lines hold, which is text;
#   - anything in a script the shell refuses to run: a quote, a $( or a
#     backtick left open, or a ) that no ( opened outside a case pattern.
# A read the sandbox declined still counts, and is listed as refused. A read
# of the frontmatter alone, `head -5` say, counts: the agent opened the file,
# as Claude Code's Skill call counts before the skill says anything. A read
# only the output can show, stopped before the three lines, is a miss. A
# number in results.md means this and no more.
#
# Read from a real run of Codex CLI 0.157.1, `codex exec --json`: the event
# and item types, and command as one string, [shell, -lc, script]. Also read
# from how Codex builds its events, not seen in a run: command as a list, and
# the "declined" status, which a read-only sandbox does not give a read. A
# later build that renames them turns every run into a miss, never into a
# hit, so a column of zeros is the first thing to check after an upgrade.
set -u -o pipefail
arm="$1" model="$2" prompt="$3"
# The quality arms need what Codex does not have headless: a way to allow a
# skill in one arm and turn every skill off in the other (claude.sh does it
# with --allowedTools and --disable-slash-commands). The premortem phase runs
# with the "with" arm, so it is left out too, and issue #39, closed by PR #42,
# asked for the activation and off-topic runs only.
case "$arm" in
  plain) ;;
  *) echo "codex.sh: the $arm arm is not run on Codex; use EVAL_ONLY=\"activation negatives\"" >&2
     exit 2 ;;
esac
PACK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# The converter: Codex's own events pass through as they came, so the stream
# stays the whole transcript and the reading can be checked against it. The
# scorer reads only the three kinds of line the contract names, and skips the
# rest. It is given as -c because stdin is the stream. It is read with read,
# not $(cat <<...): bash 3.2, which macOS ships, parses a heredoc inside $( )
# as script and trips on the quotes and parentheses in the Python.
IFS= read -r -d '' convert <<'PY' || true
import json
import os
import re
import shlex
import sys

model, pack = sys.argv[1], sys.argv[2]
SKILLS = {d for d in os.listdir(os.path.join(pack, "skills"))
          if os.path.isfile(os.path.join(pack, "skills", d, "SKILL.md"))}
READERS = {"cat", "sed", "head", "tail", "nl", "less", "more", "bat", "awk"}
SHELLS = {"bash", "sh", "zsh"}
# A path that ends in SKILL.md: SKILL.md.bak or SKILL.mdx is another file.
SKILL_PATH = re.compile(r"[^\s'\"=]*SKILL\.md(?![\w.~-])")
# Words in front of the program that run it rather than being it: shell
# keywords, a { group, and the wrappers time, env, command, exec and nohup.
PREFIXES = {"if", "then", "else", "elif", "while", "until", "do", "!", "{",
            "time", "env", "command", "exec", "nohup"}
# The options of those wrappers that take a value: env -u NAME, time -o FILE.
VALUED = {"env": {"-u", "-C", "-S", "--unset", "--chdir"}, "time": {"-o", "-f", "--output", "--format"}}
ASSIGNMENT = re.compile(r"^\w+=")
CUTS = ";&|()\n"


def opening_lines(name):
    # The first three non-empty lines of the skill's instructions, after the
    # frontmatter: each of them is in a command's output when it showed the
    # file.
    with open(os.path.join(pack, "skills", name, "SKILL.md"), encoding="utf-8") as f:
        text = f.read()
    body = text.split("\n---\n", 1)[1] if text.startswith("---\n") else text
    return [line.strip() for line in body.splitlines() if line.strip()][:3]


OPENINGS = {name: opening_lines(name) for name in SKILLS}


def words_of(text):
    try:
        return shlex.split(text)
    except ValueError:
        return text.split()


def script_of(command):
    # Codex runs a command as [shell, -lc, script], in the stream either as
    # that list or joined into one string.
    words = command if isinstance(command, list) else words_of(str(command))
    if len(words) >= 3 and os.path.basename(words[0]) in SHELLS and words[1] in ("-c", "-lc"):
        return words[2]
    # Anything else is the script itself; a list is quoted back, so an
    # argument keeps its spaces and its ; or |.
    return shlex.join(words) if isinstance(command, list) else str(command)


class Script:
    # The script read once, left to right, the way the shell reads it, into
    # parts: the words of one simple command with their quotes taken off, the
    # scripts it runs inside a $( ) or backticks, and the cut that ends it
    # (;, &&, |, a newline, ( or ), or "" at the end). What is quoted stays
    # inside its word: a ) or a << in quotes cuts nothing. A # at the start
    # of a word opens a comment, a heredoc's lines are text, and < and >
    # come out as words of their own, so a caller can tell 2>&1 from a cut.
    # It never fails: a quote, a $( or a backtick left open marks the script
    # broken, as the shell finds it, and the rest is read as text.

    def __init__(self, text):
        self.s, self.i, self.parts, self.broken = text, 0, [], False
        self.words, self.subs, self.word, self.heredocs = [], [], None, []
        self.read()

    def peek(self, k=0):
        j = self.i + k
        return self.s[j] if j < len(self.s) else ""

    def add(self, text):
        self.word = (self.word or "") + text

    def end_word(self):
        if self.word is not None:
            self.words.append(self.word)
            self.word = None

    def cut(self, how):
        self.end_word()
        self.parts.append((self.words, self.subs, how))
        self.words, self.subs = [], []

    def read(self):
        while self.i < len(self.s):
            c = self.peek()
            if c in " \t\r":
                self.end_word()
                self.i += 1
            elif c == "\n":
                self.cut("\n")
                self.i += 1
                self.heredoc_lines()
            elif c == "#" and self.word is None:
                while self.i < len(self.s) and self.peek() != "\n":
                    self.i += 1
            elif c == "\\":
                if self.peek(1) != "\n":
                    self.add(self.peek(1))
                self.i += 2
            elif c == "'":
                self.single_quoted()
            elif c == '"':
                self.double_quoted()
            elif c in "$`" and self.substitution():
                pass
            elif c in "<>" or (c == "&" and self.peek(1) == ">"):
                self.redirection()
            elif c in CUTS:
                j = self.i + 1
                if c in ";&|":
                    while j < len(self.s) and self.s[j] in ";&|":
                        j += 1
                self.cut(self.s[self.i:j])
                self.i = j
            else:
                self.add(c)
                self.i += 1
        self.cut("")

    def single_quoted(self):
        end = self.s.find("'", self.i + 1)
        if end < 0:
            self.broken, end = True, len(self.s)
        self.add(self.s[self.i + 1:end])
        self.i = end + 1

    def double_quoted(self):
        self.add("")
        self.i += 1
        while self.i < len(self.s) and self.peek() != '"':
            if self.peek() == "\\":
                self.add(self.peek(1))
                self.i += 2
            elif not (self.peek() in "$`" and self.substitution()):
                self.add(self.peek())
                self.i += 1
        self.broken |= self.i >= len(self.s)
        self.i += 1

    def substitution(self):
        # $( ) or backticks at self.i: its inside is a script the shell runs.
        # $(( )) is arithmetic and runs nothing. False when neither is here.
        s, i = self.s, self.i
        if s.startswith("$((", i):
            end = s.find("))", i)
            end = len(s) if end < 0 else end + 2
            self.add(s[i:end])
        elif s.startswith("$(", i):
            depth, j, quote = 1, i + 2, ""
            while j < len(s) and depth:
                if quote:
                    quote = "" if s[j] == quote else quote
                elif s[j] in "'\"":
                    quote = s[j]
                elif s[j] == "(":
                    depth += 1
                elif s[j] == ")":
                    depth -= 1
                j += 1
            self.broken |= depth > 0
            self.subs.append(s[i + 2:j - 1] if not depth else s[i + 2:j])
            self.add(s[i:j])
            end = j
        elif s[i] == "`":
            end = s.find("`", i + 1)
            if end < 0:
                self.broken, end = True, len(s)
            self.subs.append(s[i + 1:end])
            self.add(s[i:end + 1])
            end += 1
        else:
            return False
        self.i = end
        return True

    def redirection(self):
        # <<< is a here-string; << and <<- open a heredoc, whose delimiter is
        # the next word with its quotes taken off. A quoted delimiter keeps
        # $( ) in the heredoc's lines from running.
        self.end_word()
        s, i = self.s, self.i
        for op in ("<<<", "<<-", "<<", "&>>", "&>"):
            if s.startswith(op, i):
                break
        else:
            op = s[i]
            while i + len(op) < len(s) and s[i + len(op)] in "<>&|" and len(op) < 2:
                op += s[i + len(op)]
        self.words.append(op)
        self.i = i + len(op)
        if op in ("<<", "<<-"):
            while self.peek() in " \t":
                self.i += 1
            start = self.i
            while self.i < len(s) and s[self.i] not in " \t\n;&|()<>":
                self.i += 1
            raw = s[start:self.i]
            quoted = any(q in raw for q in "'\"\\")
            self.heredocs.append((re.sub(r"['\"\\]", "", raw), op == "<<-", quoted))

    def heredoc_lines(self):
        # The lines after a newline that belong to the heredocs opened on the
        # line before, each up to its delimiter on a line of its own (tabs in
        # front taken off only for <<-).
        for delimiter, tabs, quoted in self.heredocs:
            while self.i < len(self.s):
                end = self.s.find("\n", self.i)
                end = len(self.s) if end < 0 else end
                line = self.s[self.i:end]
                self.i = end + 1
                if (line.lstrip("\t") if tabs else line) == delimiter:
                    break
                if not quoted:
                    self.subs += Script(line).all_subs()
        self.heredocs = []

    def all_subs(self):
        return [sub for _, subs, _ in self.parts for sub in subs]


def skills_named(command):
    return reads_in(script_of(command), "")


def reads_in(script, cwd):
    # The skills whose SKILL.md a reader is run on. A cd or a pushd moves
    # where a relative path is read from, joined as written; a bare cd or a
    # cd - forgets it, a popd puts back the one before (and with nothing
    # pushed stays, as bash does), and a ) puts back the one its ( saw.
    # Between case and esac, a ) with no ( ends a pattern. Anywhere else it
    # is a syntax error, as is a quote left open, and a script the shell
    # refuses runs nothing.
    names, subshell_cwds, pushed, cases = set(), [], [], 0
    parsed = Script(script)
    if parsed.broken:
        return names
    for words, subs, cut in parsed.parts:
        for sub in subs:
            names |= reads_in(sub, cwd)
        program, args = program_of([w for w in words if not ASSIGNMENT.match(w)])
        cases += words[:1] == ["case"]
        cases -= "esac" in words[:1] and cases > 0
        if program in ("cd", "pushd"):
            if program == "pushd":
                pushed.append(cwd)
            target = args[0] if args else ""
            cwd = "" if target in ("", "-") else os.path.join(cwd, target)
        elif program == "popd":
            cwd = pushed.pop() if pushed else cwd
        elif program in READERS and not edits_in_place(program, args):
            names |= skills_in(args, cwd)
        if cut == "(":
            subshell_cwds.append(cwd)
        elif cut == ")":
            if subshell_cwds:
                cwd = subshell_cwds.pop()
            elif not cases:
                return set()
    return names


def program_of(words):
    # The program a part runs and its arguments, past the prefixes in front
    # of it and their options (time -p, env -i, env -u NAME). `command -v
    # cat` only looks cat up, so it runs nothing.
    while words and os.path.basename(words[0]) in PREFIXES:
        wrapper, words = os.path.basename(words[0]), words[1:]
        while words and words[0].startswith("-"):
            if wrapper == "command" and words[0] in ("-v", "-V"):
                return "", []
            words = words[2:] if words[0] in VALUED.get(wrapper, ()) else words[1:]
    return (os.path.basename(words[0]), words[1:]) if words else ("", [])


def edits_in_place(program, args):
    # sed -i, sed --in-place and gawk's -i inplace write the file they name.
    if program == "sed":
        return any(w.startswith("--in-place") or re.match(r"^-[a-zA-Z]*i", w) for w in args)
    return program == "awk" and "inplace" in args


def skills_in(args, cwd):
    # The pack skills whose SKILL.md an argument names. The word after a
    # redirection that writes (>, >>, 2>, &>) is the file written, not read.
    names, written = set(), False
    for arg in args:
        if ">" in arg and set(arg) <= set("<>&|"):
            written = True
            continue
        if written:
            written = False
            continue
        for path in SKILL_PATH.findall(arg):
            folders = os.path.normpath(os.path.join(cwd, path)).split("/")
            if len(folders) >= 2 and folders[-1] == "SKILL.md" and folders[-2] in SKILLS:
                names.add(folders[-2])
    return names


# What may stand in front of a printed line: a file name, a line number, or
# both, as grep -n, grep -H, rg and nl or cat -n put them there.
LINE_PREFIX = re.compile(r"^\s*(?:[^\s:]+:)?(?:\d+[:\t-])?\s*$")


def skills_shown(output):
    # The skills whose instructions a finished command printed, whatever
    # command it was. Each opening line has to stand on a line of its own,
    # after nothing but a LINE_PREFIX: a transcript that holds a SKILL.md
    # inside a JSON string, as another run's stream does, did not show it.
    printed = output.splitlines()

    def shown(line):
        return any(p.rstrip().endswith(line) and LINE_PREFIX.match(p.rstrip()[:-len(line)])
                   for p in printed)

    return {name for name, lines in OPENINGS.items() if lines and all(shown(line) for line in lines)}


def emit(line):
    # Flushed line by line: a run the time cap kills keeps what it wrote.
    print(json.dumps(line), flush=True)


def call_id(item_id, name):
    # One id for a Skill call and for its denial, so the scorer can match them.
    return f"{item_id}-{name}"


opened, denied, answer = set(), [], ""
for raw in sys.stdin:
    try:
        event = json.loads(raw)
    except ValueError:
        continue
    emit(event)
    kind, item = event.get("type", ""), event.get("item") or {}
    if kind == "thread.started":
        # The model is the one asked for: the stream names a thread, not a
        # model. A run that dies before this line has no init line, and the
        # scorer routes it by the file name run.sh gave it.
        emit({"type": "system", "subtype": "init", "model": model, "agent": "codex"})
    elif kind in ("item.started", "item.updated", "item.completed"):
        done = kind == "item.completed"
        if item.get("type") == "agent_message" and done:
            answer = item.get("text", "")
        if item.get("type") != "command_execution":
            continue
        item_id = item.get("id", "")
        names = skills_named(item.get("command", ""))
        if done:
            names |= skills_shown(item.get("aggregated_output") or "")
        # The same command shows up as started and again as completed; each
        # skill it opened is called once, when it first shows.
        new = sorted(n for n in names if (item_id, n) not in opened)
        opened.update((item_id, n) for n in new)
        if new:
            emit({"type": "assistant", "message": {"role": "assistant", "content": [
                {"type": "tool_use", "id": call_id(item_id, n), "name": "Skill", "input": {"skill": n}}
                for n in new]}})
        # A read the sandbox refused is still the choice, and is listed the
        # way Claude Code lists a denied Skill call.
        if done and item.get("status") == "declined":
            denied += [{"tool_name": "Skill", "tool_use_id": call_id(item_id, n)}
                       for n in sorted(n for i, n in opened if i == item_id)]
    elif kind == "turn.completed":
        emit({"type": "result", "result": answer, "permission_denials": denied})
    # turn.failed writes no result line: the run did not finish, and the
    # scorer counts it as unfinished rather than as an answer.
PY
# Read-only sandbox, every run: a skill is opened by reading a file, which the
# sandbox allows, and the throwaway repository stays as run.sh made it for the
# next run. `exec` never waits for an approval, so a command the sandbox
# refuses comes back refused, as a denied tool does on Claude Code.
#
# --ephemeral keeps every run out of ~/.codex/sessions; the stream run.sh
# keeps is the transcript. stdin from /dev/null: `exec` appends piped stdin to
# the prompt as a <stdin> block, and the phrase must arrive as cases.md has it.
#
# There is no turn cap to match claude.sh's --max-turns 12; run.sh's time cap
# per run is the limit here. pipefail carries codex's own exit status through
# the pipe, so a failed login fails run.sh's auth check.
codex exec --json --ephemeral --sandbox read-only --model "$model" -- "$prompt" </dev/null |
  python3 -c "$convert" "$model" "$PACK"
