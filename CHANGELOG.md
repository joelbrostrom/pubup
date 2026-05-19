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
