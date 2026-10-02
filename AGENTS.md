# AGENTS.md

Guidance for coding agents (Cursor, Claude Code, Codex, Aider, etc.) using
`pubup` inside Dart or Flutter projects.

## What pubup is

A CLI that rewrites version constraints in `pubspec.yaml` to the latest
resolvable versions, across single packages and workspaces.

- It changes `pubspec.yaml` (and `pubspec.lock` via `pub add` or root `pub get`
  in workspace mode).
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
   Nothing is modified. Check that the `SDK:` line shows the SDK the project
   is meant to use.
2. **Apply.** Run `pubup` (optionally with `--package <name>` to scope it).
3. **Verify.** Inspect `git diff -- '*pubspec.yaml'` to see exact constraint
   changes in every workspace member.
4. **Test.** Run the project's test suite. Major-version bumps can introduce
   breaking changes that pubup will happily apply — pubup updates constraints,
   it does not evaluate semver risk.
5. **If tests fail**, revert with
   `git checkout -- '*pubspec.yaml' '*pubspec.lock'` (this covers workspace
   members too) or narrow the update with `--package` / `--no-dev`.

## Flags you'll actually use

- `--dry-run` — preview; always start here.
- `--package <name>` — limit scanning to specific workspace package(s);
 repeatable. In workspace mode, coordinated deps that are also declared in
 unfiltered members are skipped with a warning — use no `--package` filter
 for workspace-wide shared bumps (e.g. `very_good_analysis` across all
 packages).
- `--no-dev` — skip `dev_dependencies`.
- `--bump <major|minor|patch>` — cap how far constraints may move. Use
 `--bump minor` to refresh dependencies without taking new major versions,
 or `--bump patch` to take patch-level fixes only. When the latest
 resolvable version exceeds the bound, pubup queries pub.dev for the full
 version list and picks the highest in-bound version above the locked one.
 Deps with no qualifying version are surfaced under `Skipped` as
 `above --bump`.
- `--prereleases` — allow stable dependencies to move to pre-releases. Off by
 default; only use it when the user asks for pre-releases.
- `--sdk <path>` — run pub with a specific Flutter or Dart SDK. Only needed
 when neither the FVM pin nor `PATH` points at the SDK the project uses.
- `--root <path>` — when not invoking from the project root.

## Reading the output

- The header line `SDK: Flutter 3.38.5, Dart 3.10.4 (...)` shows which SDK
  pub ran with and where it came from. The SDK decides which versions are
  resolvable.
- Exit code `0` = success (including "nothing to update").
- Exit code `1` = at least one update or member scan failed. Each failure is
  listed in the `Failures` section above the `Summary`.
- The `Held back` section lists dependencies whose latest version another
  dependency or the SDK blocks. pubup cannot move them; report them to the
  user. They do not affect the exit code.
- `git diff -- '*pubspec.yaml'` is the most reliable signal of what changed.
  Prefer it over scraping stdout.

## What pubup will not touch

Skipped automatically (safe to assume these stay as-is):

- `path:`, `git:`, and `sdk:` dependencies
- Constraints that aren't a standard caret range (e.g. `any`, exact pins,
  complex ranges)
- Dependencies already at `^<resolvable>`
- Stable dependencies whose only newer version is a pre-release, unless
  `--prereleases` is passed. When `pub outdated` reports a pre-release as
  resolvable, pubup picks the newest stable version below it instead.
- Transitive dependencies (only direct `dependencies` / `dev_dependencies`)
- `dependency_overrides:` (workspace and single-package mode)

If the user needs one of these updated, do it manually with `dart pub add`.

## Which SDK pubup runs

pubup runs `pub` with the first SDK it finds: `--sdk <path>`, then the FVM pin
in `.fvmrc` (`.fvm/versions/<version>`), then the legacy `.fvm/flutter_sdk`
link, then `flutter`/`dart` on `PATH`. FVM projects therefore do not need
`fvm exec pubup`.

If stderr warns that `.fvmrc` pins a version that is not linked, run
`fvm use <version>` and re-run pubup. Otherwise pub resolves against the
`PATH` SDK, which may be older or newer than the project's.

## Dart pub workspaces

When the root `pubspec.yaml` has a `workspace:` section, pub resolves **one
shared graph** for all members. pubup uses coordinated updates: it bumps every
outdated shared dependency in **every** member that declares it, then runs
**one** root `pub get`. If that fails, it reverts and retries per dependency so
failures are attributed exactly (e.g. Firebase packages that must move together
resolve in the big batch; a single bad dep still surfaces on retry). Per-member
`pub add` alone cannot succeed for non-overlapping major bumps (e.g. root on
`^10` while a member still pins `^6`).

## Progress indicator

When run in a terminal, pubup prints a self-replacing status line on
stderr while it is busy (per-member `pub outdated` scans, the root
`pub get`, per-dep retries). The line is auto-suppressed when:

- stderr is not a TTY (i.e. you're capturing it from an agent or pipeline)
- `CI=true`
- `TERM=dumb`
- `PUBUP_DISABLE_PROGRESS=1`

You generally do not need to manage this. If your tooling tries to parse
stderr as plain text and chokes on `\r`, set `PUBUP_DISABLE_PROGRESS=1`.

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
