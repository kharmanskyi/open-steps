# Contributing

The pack moves on its own, so nothing here is required of you. If you do want
to change something, seven rules cover it.

1. **A real example is worth the most.** A report your own agent wrote that
   you couldn't use, next to what you wish it had said. Take out anything
   private. Every format here started as one of those, and almost every one
   changed a rule afterwards. It goes in the skill's `references/` folder.
2. **Issue or pull request, either is fine.** No template, no ceremony. Small
   and specific beats big and vague.
3. **English only in the files.** The skills detect what language you speak
   and answer in it. Writing one language into a skill file would break that
   for everyone else.
4. **Run `claude plugin validate .` first.** It catches broken file headers
   that would otherwise make a skill fail silently.
5. **One skill, one moment.** If a skill needs two different "use this when"
   stories, it's two skills.
6. **Keep the tool list short.** A skill's `allowed-tools` skips permission
   prompts for the turn it runs in, so list only what the skill's own body
   names, and scope it. Read-only `git` needs no entry: Claude Code already
   treats it as read-only. `Write(path)` is not a rule Claude Code reads, use
   `Edit(path)`. A script the skill ships is granted by its path -
   `Bash(${CLAUDE_SKILL_DIR}/scripts/name.sh *)` - which keeps the grant to
   that one file wherever the pack is installed.
7. **Keep a `SKILL.md` under 167 lines**, the length of the longest one here.
   Past that it is carrying something that belongs in a script or in
   `references/`. The measured half of `os-big-picture` moved into
   `scripts/census.sh` for exactly this reason, and got tests out of it.

Testing the hooks: `bash hooks/test.sh` puts both of them through twelve
scenarios in throwaway repositories, with a throwaway home directory, so it
touches nothing of yours. Run one by hand instead and remember that both read
from standard input: add `</dev/null` or they sit there waiting for a payload
that never comes.

The same file covers the scripts a skill ships. `os-big-picture` measures its
map with `skills/os-big-picture/scripts/census.sh`, and cases 11 and 12 build
throwaway repositories with forged commit dates (`GIT_COMMITTER_DATE`) to check
both sides of the signal: a quiet part nothing reaches must be named, and a
quiet part something still reaches must not be. Anything a skill can hand to a
script belongs in one, because prose in a `SKILL.md` cannot be tested and a
script can.

Both of those run on every pull request, the hook suite on Linux and macOS
both, so a shell construct that only works on one of them shows up as a failed
check rather than in somebody's terminal. Nothing else is automatic: the
`references/` examples and the wording of a `SKILL.md` still need a person.

**Sign off your commits.** Use `git commit -s`, which adds a `Signed-off-by`
line. It is how you state that you wrote the change, or otherwise have the right
to release it under this repository's licence, and a check on every pull request
requires it. To add it to commits you already made:
`git rebase --signoff origin/main`.

That matters most for an example: it must be synthetic, or from work where you
hold every right. Not client material and not a redacted real report, because
redaction still leaks context. Say in the pull request that it contains neither
confidential nor third-party data.

The formula that decides whether real work happened lives in
`hooks/fingerprint.sh`, shared by both hooks on purpose. Change it in one place
only, and run the checks: two hooks computing it differently would ask for a
report at the start of every session.

One thing that is easy to miss: the examples in `references/` are not checked
by anything automatic. If you change a rule inside a `SKILL.md`, read the
example next to it and make sure it still obeys that rule. This has already
caught two examples that taught the opposite of what their skill said.
