## 0.2.1

- The once-per-day update notice is now also suppressed automatically when
  stderr is not attached to a TTY (e.g. when pubup is invoked by a coding
  agent, captured by a script, or piped). `CI=true` and
  `PUBUP_DISABLE_UPDATE_CHECK` continue to work as before.
- Added `AGENTS.md` with guidance for coding agents on when and how to invoke
  pubup.

## 0.2.0

- Added `--version` / `-V` flag.
- Added `pubup update` subcommand that reinstalls pubup from pub.dev.
- pubup now checks pub.dev once per day and prints a notice on stderr
  when a newer version is available. Set `PUBUP_DISABLE_UPDATE_CHECK=1`
  or run in CI (`CI=true`) to skip the check.

## 0.1.1

- Tolerate non-JSON content in `flutter pub outdated --json` output.
  Previously the root package scan could fail with
  `FormatException: Unexpected character` when Flutter appended its
  "A new version of Flutter is available" banner after the JSON payload.
  The runner now extracts the JSON object from stdout and ignores any
  surrounding noise.

## 0.1.0

- Initial release.
- Workspace-aware dependency constraint updater for Dart and Flutter projects.
- Supports `--dry-run`, `--[no-]dev`, `--package`, and `--root` flags.
- Automatically detects `dart pub` vs `flutter pub` per package.
- Skips path, git, sdk, and non-standard dependency sources.
