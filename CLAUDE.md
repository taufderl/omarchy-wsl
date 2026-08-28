# CLAUDE.md

Working conventions for this repo, separate from the project's technical scope (see `README.md` / `PLAN.md` for that). These are general good-practice defaults, not project-specific rules — adjust freely as real preferences surface.

## Git

- Don't commit or push unless asked. If asked to commit further work while on `main`, branch first rather than committing directly to the default branch.
- Never force-push, rewrite history, or discard uncommitted changes without explicit confirmation for that specific action.
- Write commit messages that explain *why*, not just *what* — the diff already shows what changed.
- Never commit secrets, credentials, tokens, or private keys. If a build step needs one, it comes from the environment/a local untracked file, never from a file in this repo.

## Making changes

- No shortcuts or hacks that quietly paper over a real problem (this repo's whole premise per `PLAN.md`) — if something can't be done properly, say so and document the gap instead of faking it.
- Prefer editing/extending existing scripts and patterns already in the repo over introducing a parallel way of doing the same thing.
- Don't leave placeholder code, stub logic, or TODOs in place of a working implementation without flagging it explicitly.
- Before declaring something done, verify it actually works (run it, run the relevant test) rather than assuming from reading the code.

## Communicating status

- Report results plainly: if a build/test fails, say so with the actual output, not a softened summary.
- If a step was skipped or deferred, say that outright rather than letting it look finished.
- Don't re-litigate decisions already recorded in `PLAN.md` (e.g. no-Hyprland-desktop v1 scope) — treat them as settled unless the project owner reopens them.
