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

# Specify a custom project root
pubup --root /path/to/project
```

## How it works

1. **Discovers workspace packages** from the root `pubspec.yaml` `workspace:`
   section. Falls back to the root package only if no workspace is defined.
2. **Runs `dart pub outdated --json --show-all`** (or `flutter pub` for Flutter
   packages) for each package.
3. **Compares declared constraints** in `pubspec.yaml` against the latest
   resolvable version reported by pub.
4. **Updates constraints** via a single batched `dart pub add` per package
   (all out-of-date deps in one call), so the pub solver runs once per
   package instead of once per dependency. If the batched call fails — for
   example, when one dep cannot be resolved — pubup falls back to
   per-dependency `dart pub add` calls so individual failures are reported
   accurately.

## What gets skipped

The tool intentionally skips dependencies that:

- Use `path:`, `git:`, or `sdk:` sources
- Have `any` or non-standard version constraints
- Are already at `^<resolvable>` (up to date)
- Are transitive (not declared directly in your pubspec)

## CLI flags

| Flag | Description | Default |
|------|-------------|---------|
| `--dry-run` | Preview changes without modifying files | `false` |
| `--[no-]dev` | Include `dev_dependencies` | `true` |
| `--package <name>` | Filter to specific workspace package(s); repeatable | all |
| `--root <path>` | Project root directory | `.` |
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

```
Package: . (flutter pub)
  - direct go_router: ^17.0.0 -> ^17.1.0 (resolved=17.1.0, resolvable=17.1.0)
  - direct firebase_core: ^4.2.1 -> ^4.6.0 (resolved=4.6.0, resolvable=4.6.0)
  - dev    very_good_analysis: ^10.0.0 -> ^10.2.0 (resolved=10.2.0, resolvable=10.2.0)

Summary
=======
- .: changed=3, failed=0

Totals: attempted=3, changed=3, failed=0
```

## Contributing

Contributions are welcome! Please file issues and pull requests on
[GitHub](https://github.com/joelbrostrom/pubup).

## License

MIT — see [LICENSE](LICENSE) for details.
