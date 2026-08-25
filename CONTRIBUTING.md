# Contributing

The pack moves on its own, so nothing here is required of you. If you do want
to change something, six rules cover it.

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
   `Edit(path)`.

Testing the hooks: `bash hooks/test.sh` puts both of them through nine
scenarios in throwaway repositories, with a throwaway home directory, so it
touches nothing of yours. Run one by hand instead and remember that both read
from standard input: add `</dev/null` or they sit there waiting for a payload
that never comes.

The formula that decides whether real work happened lives in
`hooks/fingerprint.sh`, shared by both hooks on purpose. Change it in one place
only, and run the checks: two hooks computing it differently would ask for a
report at the start of every session.

One thing that is easy to miss: the examples in `references/` are not checked
by anything automatic. If you change a rule inside a `SKILL.md`, read the
example next to it and make sure it still obeys that rule. This has already
caught two examples that taught the opposite of what their skill said.
