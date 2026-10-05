# Security

Open Steps is a pack of skills, two hooks and a few scripts that run inside a
coding agent on your own machine. This page says what runs, what it touches,
and how to tell us about a problem.

## What runs on your machine

- The skills are text the agent reads. They do not run by themselves.
- The two hooks, `hooks/session-start.sh` and `hooks/stop-report.sh`, run at
  the start and end of a session. They read the state of your git
  repositories and write reports under `~/.claude/open-steps/reports/`. On
  Cursor and Gemini CLI they run through `hooks/adapter.sh`.
- Two small scripts run when a skill asks for them: `scripts/census.sh` in
  `os-big-picture` reads git history; `scripts/prompt.sh` in
  `os-what-could-go-wrong` prints a prompt file.
- `doctor.sh` is the install check. It reads files and changes nothing.

None of these files makes a network call. The agent itself talks to its model
and to GitHub when a skill asks it to run `gh`; that traffic is the agent's,
not the pack's. The skills tell the agent to merge a pull request whose checks
are green and whose review is approved; the README section "What it does on
its own" says how to turn that off.

## What we count as a vulnerability

- A way for text the agent reads, such as a repository file, a pull request
  or a session id, to make one of the pack's scripts run a command.
- A hook or script writing outside the reports folder and the one file
  `os-big-picture` keeps in the project.
- A pre-approved tool rule in a skill's header that reaches further than its
  wording says.
- Anything that sends data off the machine.

Not vulnerabilities: a skill not switching on, a wrong verdict in a report, or
the agent ignoring the routing block. Those are issues, and the issue form is
the place for them.

## How to report one

Use GitHub's private vulnerability reporting for this repository: the
"Report a vulnerability" button under the Security tab, or
https://github.com/kharmanskyi/open-steps/security/advisories/new. Please do
not open a public issue for a security problem.

Say what you ran, on which tool and version, and what happened. A transcript
or the exact file that triggered it is the most useful thing you can attach.

You will get an answer within seven days. A confirmed problem is fixed in a
release, and the release notes say what it was and which versions it touched,
with credit to you unless you ask otherwise.

## Supported versions

The latest release is the one that gets fixes. Updating is `git pull` inside
your clone and, on Claude Code, `claude plugin update open-steps@open-steps`.
