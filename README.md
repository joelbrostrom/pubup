# pubup

A Dart CLI tool that automatically updates `pubspec.yaml` dependency constraints
to the latest resolvable versions — across single packages and Dart/Flutter
workspaces.

Unlike `dart pub upgrade`, which only updates `pubspec.lock` within existing
constraints, `pubup` rewrites the version constraints in your
`pubspec.yaml` files so they reflect what is actually resolvable today.

## Installation

```bash
dart pub global activate pubup
```

Make sure `~/.pub-cache/bin` is on your `PATH`.

## Updating

```bash
# Manual upgrade
dart pub global activate pubup

# Or use the built-in command
pubup update
```

pubup checks pub.dev for new releases at most once per day and prints a
notice on stderr when a newer version is available. The check is skipped
automatically when:

- `CI=true`
- `PUBUP_DISABLE_UPDATE_CHECK=1`
- stderr is not a TTY (e.g. invoked by a coding agent, captured by a script,
  or piped)

## For coding agents

If you're an LLM-driven coding agent (or you ship one), see
[AGENTS.md](AGENTS.md) for the recommended workflow, when to prefer `pubup`
over `dart pub upgrade`, and how to interpret exit codes.

## Usage

Run from the root of any Dart or Flutter project:

```bash
# Preview what would change (no files modified)
pubup --dry-run

# Apply updates to all workspace packages
pubup

# Update only a specific package in a workspace
pubup --package my_package

# Skip dev_dependencies
pubup --no-dev

# Avoid major-version bumps (only update within the current major)
pubup --bump minor

# Only take patch updates
pubup --bump patch

# Specify a custom project root
pubup --root /path/to/project
```

## Limiting how far constraints move

By default `pubup` bumps each constraint to the latest resolvable version,
including across major versions. Pass `--bump` to keep updates inside a
narrower window so you can refresh dependencies without taking breaking
changes:

| Flag | What gets bumped |
|------|------------------|
| `--bump major` (default) | Latest resolvable, including new major versions. |
| `--bump minor` | Highest version that keeps the leading segment unchanged (e.g. `1.2.3` → up to `1.x.y`, `0.1.2` → up to `0.x.y`). |
| `--bump patch` | Highest version that keeps the leading two segments unchanged (e.g. `1.2.3` → up to `1.2.x`). |

When the latest resolvable version exceeds the bound, pubup queries
[pub.dev's package API](https://pub.dev/api/packages/) for the full version
list and picks the highest non-prerelease version that fits — so you still
get the newest patch (or minor+patch) instead of skipping the dependency
entirely.

If no in-bound version above the currently locked one exists, the dependency
is reported under `Skipped` as `above --bump` in the summary.

## How it works

1. **Discovers workspace packages** from the root `pubspec.yaml` `workspace:`
   section. Falls back to the root package only if no workspace is defined.
2. **Runs `dart pub outdated --json --show-all`** (or `flutter pub` for Flutter
   packages) for each package.
3. **Compares declared constraints** in `pubspec.yaml` against the latest
   resolvable version reported by pub.
4. **Updates constraints** using one of two strategies:
   - **Workspace projects** (root declares `workspace:`): shared dependencies
     are updated **coordinated** across every member that declares them.
     pubup rewrites all affected `pubspec.yaml` files, then runs one root-level
     `pub get` for the whole batch. On solver failure, it retries per dependency
     to attribute the exact failure.
   - **Single-package projects**: a single batched `dart pub add` per package
     (all out-of-date deps in one call). If the batched call fails, pubup
     falls back to per-dependency `dart pub add` calls so individual failures
     are reported accurately.

With `--package`, workspace mode only considers outdated deps reported for the
filtered members. A coordinated bump is **skipped** (with a warning) when
another workspace member also declares that dependency but is outside the
filter — run without `--package` for a workspace-wide update.

## What gets skipped

The tool intentionally skips dependencies that:

- Use `path:`, `git:`, or `sdk:` sources
- Have `any` or non-standard version constraints
- Are already at `^<resolvable>` (up to date)
- Are transitive (not declared directly in your pubspec)
- Entries under `dependency_overrides:` (never modified)

## CLI flags

| Flag | Description | Default |
|------|-------------|---------|
| `--dry-run` | Preview changes without modifying files | `false` |
| `--[no-]dev` | Include `dev_dependencies` | `true` |
| `--package <name>` | Filter to specific workspace package(s); repeatable | all |
| `--root <path>` | Project root directory | `.` |
| `--bump <level>` | Cap how far constraints move: `major`, `minor`, or `patch` | `major` |
| `--version`, `-V` | Print the current version | — |

### Subcommands

| Command | Description |
|---------|-------------|
| `update` | Reinstall pubup from pub.dev (`dart pub global activate pubup`) |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | All updates succeeded (or nothing to update) |
| `1` | One or more updates failed |

## Example output

Single package:

```
Package: . (flutter pub)

  go_router           direct  ^17.0.0  ->  ^17.1.0
  firebase_core       direct  ^4.2.1   ->  ^4.6.0
  very_good_analysis  dev     ^10.0.0  ->  ^10.2.0

Summary
-------
  Updated  3
  Failed   0
```

Workspace (rows show shared `from` constraints across members and how many
members each coordinated update touches):

```
Workspace: my-app (flutter pub)

  build_runner        dev     ^2.4.13, ^2.4.15  ->  ^2.15.0    8 members
  freezed             dev     ^3.0.3, ^3.0.6    ->  ^3.2.5     6 members
  very_good_analysis  dev     ^6.0.0            ->  ^10.2.0    39 members
  bloc                direct  ^9.0.0            ->  ^9.2.1     4 members
  go_router           direct  ^15.1.2           ->  ^17.2.3    2 members

Summary
-------
  Updated  175 constraints across 56 dependencies
  Failed   0
  Skipped  54 up-to-date, 84 non-hosted, 3041 transitive
```

When updates fail, the resolver error is wrapped under a `Failures` section
above the summary so the totals stay visible at the bottom of the output.

## Contributing

Contributions are welcome! Please file issues and pull requests on
[GitHub](https://github.com/joelbrostrom/pubup).

## License

MIT — see [LICENSE](LICENSE) for details.
