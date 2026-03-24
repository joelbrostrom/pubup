## 0.1.0

- Initial release.
- Workspace-aware dependency constraint updater for Dart and Flutter projects.
- Supports `--dry-run`, `--[no-]dev`, `--package`, and `--root` flags.
- Automatically detects `dart pub` vs `flutter pub` per package.
- Skips path, git, sdk, and non-standard dependency sources.
