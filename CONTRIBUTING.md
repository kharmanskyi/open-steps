# Contributing

The pack moves on its own, so nothing here is required of you. If you do want
to change something, seven rules cover it. They hold whichever tool you use:
Claude Code, Codex CLI, Cursor CLI or Gemini CLI.

1. **A real example is worth the most.** A report your own agent wrote that
   you couldn't use, next to what you wish it had said. Take it from your own
   work, where you hold every right, or invent the case. You may change names.
   Do not send client work with the private parts cut out, because redaction
   still leaks context. Every format here started as one of those, and almost
   every one changed a rule afterwards. It goes in the skill's `references/`
   folder, and its first line says where it came from, the way the examples
   already there do.
2. **Issue or pull request, either is fine.** An issue opens with a short
   form, and a pull request with a short checklist. Small and specific beats
   big and vague.
3. **English only in the files.** The skills detect what language you speak
   and answer in it. Writing one language into a skill file would break that
   for everyone else.
4. **Check the plugin manifest if you have Claude Code.** Run
   `claude plugin validate --strict .claude-plugin/plugin.json`. It opens every
   skill file and fails on a broken header that would otherwise make the skill
   fail silently. `claude plugin validate .` checks the marketplace manifest
   only, so on its own it proves nothing about the skills. CI runs both on
   every pull request, so without Claude Code you can leave this to CI.
5. **One skill, one moment.** If a skill needs two different "use this when"
   stories, it's two skills.
6. **Keep the tool list short.** On Claude Code, a skill's `allowed-tools`
   lets the listed tools run without a permission prompt in the turn the skill
   runs. So list only what the skill's own body names, and scope each entry.
   Codex, Cursor and Gemini CLI ignore the field, per their documentation (not
   tested). A skill must read correctly without it: name a script or a
   reference file by its place next to `SKILL.md`, the way
   `os-what-could-go-wrong` falls back to `references/premortem-prompt.md`.
   The syntax is under
   [Claude Code permission syntax](#claude-code-permission-syntax).
7. **Keep a `SKILL.md` short.** The longest one here is 172 lines. Past about
   that, it carries something that belongs in a script or in `references/`.
   The measured half of `os-big-picture` moved into `scripts/census.sh` for
   this reason, and got tests out of it.

## Claude Code permission syntax

These notes are about Claude Code only, since the other tools ignore
`allowed-tools`.

- Read-only `git` needs no entry. Claude Code already treats it as read-only.
- Claude Code never reads a path rule for `Write`. Use `Edit(path)` in its
  place. It also covers creating the file.
- Grant a script the skill ships by the exact command the skill runs. For
  `bash ${CLAUDE_SKILL_DIR}/scripts/name.sh`, the rule is
  `Bash(bash ${CLAUDE_SKILL_DIR}/scripts/name.sh *)`. A Bash rule matches the
  whole command text, so a rule without the leading `bash` never applies. The
  rule keeps the grant to that one file wherever the pack is installed.
- `${CLAUDE_SKILL_DIR}` is set by Claude Code only. What happened to the `!`
  line on Codex CLI is in
  [docs/other-agents.md](docs/other-agents.md#the-skills).

## Measuring another tool

Want the evals to measure another tool? Runners for
[Gemini CLI](https://github.com/kharmanskyi/open-steps/issues/38) and
[Cursor](https://github.com/kharmanskyi/open-steps/issues/40) are open issues.
The contract is in
[Measuring another agent](evals/README.md#measuring-another-agent), and
`evals/agents/codex.sh`, the Codex CLI runner, is a worked example for a tool
with no skill tool.

## Tests

`bash hooks/test.sh` tests both hooks, the adapter for Cursor and Gemini CLI,
`doctor.sh` and the scripts the skills ship. It uses throwaway repositories
and a throwaway home folder, so it touches nothing of yours.
`bash evals/test.sh` tests the scorer and the runners. It uses stand-ins for
`claude` and `codex`, so no model is called. Neither needs Claude Code. To run
a hook by hand, add `</dev/null`. Each hook reads from standard input, and
without it the hook waits for a payload that never comes.

`hooks/test.sh` covers a skill's scripts this way. `os-big-picture` measures its
map with `skills/os-big-picture/scripts/census.sh`, and case 13 builds
throwaway repositories with forged commit dates (`GIT_COMMITTER_DATE`) to check
both sides of the signal: a quiet part nothing reaches must be named, and a
quiet part something still reaches must not be. Anything a skill can hand to a
script belongs in one, because prose in a `SKILL.md` cannot be tested and a
script can.

CI runs both test files on every pull request, on Linux and on macOS. A shell
construct that works on only one of them then shows up as a failed check, not
in somebody's terminal. CI also checks the plugin manifest with
`claude plugin validate`, and checks the sign-off below.

The formula that decides whether real work happened lives in
`hooks/fingerprint.sh`, shared by both hooks on purpose. Change it in one place
only, and run the checks: two hooks computing it differently would ask for a
report at the start of every session.

## Sign-off

Use `git commit -s`, which adds a `Signed-off-by` line. It is how you state
that you wrote the change, or otherwise have the right to release it under
this repository's licence, and a check on every pull request requires it. To
add it to commits you already made: `git rebase --signoff origin/main`.

That matters most for an example: say in the pull request that it contains
neither confidential nor third-party data.

## Examples

The examples in `references/` are not checked by anything automatic, and
neither is the wording of a `SKILL.md`. Both still need a person. If you change
a rule inside a `SKILL.md`, read the example next to it and make sure it still
obeys that rule. This has already caught two examples that taught the opposite
of what their skill said.
