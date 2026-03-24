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
4. **Updates constraints** via `dart pub add <name>:^<resolvable>` for each
   dependency where the declared constraint is behind.

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
[GitHub](https://github.com/<your-handle>/pubup).

## License

MIT — see [LICENSE](LICENSE) for details.
