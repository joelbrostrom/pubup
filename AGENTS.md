# AGENTS.md

Guidance for coding agents (Cursor, Claude Code, Codex, Aider, etc.) using
`pubup` inside Dart or Flutter projects.

## What pubup is

A CLI that rewrites version constraints in `pubspec.yaml` to the latest
resolvable versions, across single packages and workspaces.

- It changes `pubspec.yaml` (and `pubspec.lock` as a side effect of `pub add`).
- It does **not** upgrade past constraints declared by other workspace
  packages or the SDK.
- It is fully non-interactive. It never prompts.

## When to reach for pubup

| Goal | Use |
|------|-----|
| Bump `pubspec.yaml` constraints to the newest resolvable versions | **`pubup`** |
| Only update `pubspec.lock` within existing constraints | `dart pub upgrade` |
| Inspect what is outdated without changing anything | `dart pub outdated` or `pubup --dry-run` |
| Update a single dependency to a specific version | `dart pub add <pkg>:<version>` |

If the user asks to "update dependencies", "bump packages", or "get on the
latest versions" in a Dart/Flutter project, `pubup` is the right tool.

## Recommended workflow

1. **Preview first.** Run `pubup --dry-run` and show the output to the user.
   Nothing is modified.
2. **Apply.** Run `pubup` (optionally with `--package <name>` to scope it).
3. **Verify.** Inspect `git diff pubspec.yaml` to see exact constraint changes.
4. **Test.** Run the project's test suite. Major-version bumps can introduce
   breaking changes that pubup will happily apply — pubup updates constraints,
   it does not evaluate semver risk.
5. **If tests fail**, revert with `git checkout -- pubspec.yaml pubspec.lock`
   or narrow the update with `--package` / `--no-dev`.

## Flags you'll actually use

- `--dry-run` — preview; always start here.
- `--package <name>` — limit to one workspace package. Repeatable.
- `--no-dev` — skip `dev_dependencies`.
- `--root <path>` — when not invoking from the project root.

## Reading the output

- Exit code `0` = success (including "nothing to update").
- Exit code `1` = at least one `dart pub add` failed. Failures are printed
  per-package under each `Package:` block; the trailing `Totals:` line shows
  the aggregate.
- `git diff pubspec.yaml` is the most reliable signal of what changed. Prefer
  it over scraping stdout.

## What pubup will not touch

Skipped automatically (safe to assume these stay as-is):

- `path:`, `git:`, and `sdk:` dependencies
- Constraints that aren't a standard caret range (e.g. `any`, exact pins,
  complex ranges)
- Dependencies already at `^<resolvable>`
- Transitive dependencies (only direct `dependencies` / `dev_dependencies`)

If the user needs one of these updated, do it manually with `dart pub add`.

## Self-update

`pubup update` reinstalls pubup from pub.dev. The CLI also prints a one-line
notice on stderr when a newer version exists. The notice is auto-suppressed
when:

- `CI=true`
- `PUBUP_DISABLE_UPDATE_CHECK=1`
- stderr is not a TTY (i.e. you're capturing it from an agent or pipeline)

You generally do not need to manage this.

## Things not to do

- Don't pipe `pubup` through `yes` or anything similar — it never prompts.
- Don't parse the human-readable summary text for state; read the exit code
  and `git diff` instead.
- Don't run `pubup` and commit in the same step without showing the diff to
  the user first. Dependency bumps deserve a review.
