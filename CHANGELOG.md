## 0.5.1

- **Live progress indicator.** Workspace and single-package runs now show a
  one-line, self-replacing status on stderr while pubup is busy
  (`Scanning packages/auth (3/56)`, `Running flutter pub get`,
  `Retrying very_good_analysis (4/9)`, …) with a blank padding line
  reserved below it for visual breathing room. This eliminates the long
  silent gap between the `Workspace:` header and the first table row on
  large workspaces. The line is animated with a spinner so liveness is
  visible even when one step takes a while.
- The indicator is automatically disabled when stderr is not a TTY (CI
  logs, pipes, agent capture), when `CI=true`, when `TERM=dumb`, or when
  `PUBUP_DISABLE_PROGRESS=1`.
- No CLI changes; stdout output and exit codes are byte-identical to
  previous releases.

## 0.5.0

- **Batch-first workspace updates.** Workspace mode now rewrites all coordinated
  constraints, then runs a single root `pub get`. If resolution fails, pubup
  reverts and retries per dependency (same attribution as 0.4.0).
- Fixes coupled-dependency failures (e.g. `firebase_core`, `firebase_messaging`,
  and `firebase_analytics` must bump together) that could not resolve when
  updated one at a time.
- Typical workspace runs drop from N `pub get` invocations to 1 when everything
  resolves cleanly. No CLI changes.

## 0.4.0

- **Workspace-coordinated updates.** When the root `pubspec.yaml` declares a
  `workspace:` list, pubup now updates shared dependencies atomically across
  all members that declare them: constraints are rewritten in every affected
  `pubspec.yaml`, then a single root-level `pub get` validates the workspace
  graph. This fixes the failure mode where per-package `pub add` calls left
  the workspace in a contradictory intermediate state (e.g. root on
  `very_good_analysis ^10` while members still pin `^6`).
- Non-workspace projects keep the existing batched `pub add` strategy.
- `--package` in workspace mode: coordinated deps are skipped with a warning
  when a declaring member is outside the filter (run without `--package` for a
  workspace-wide bump).
- `dependency_overrides:` are never modified.

## 0.3.0

- Batch all dependency updates for a package into a single `dart pub add`
  (or `flutter pub add`) invocation. Previously pubup invoked `pub add` once
  per dependency, triggering a full pub resolution each time — on a workspace
  with 127 changes this took ~30 minutes. The batched call runs the pub
  solver once per package, typically yielding a 10×+ speedup on large
  workspaces.
- On batched-call failure (e.g. one dep cannot be resolved), pubup
  automatically falls back to per-dependency `pub add` calls so individual
  failures are still attributed to the exact dep that failed.
- No CLI or output-format changes; per-dependency log lines, exit codes,
  and the `Totals:` summary all behave as before.

## 0.2.2

- No user-facing changes.
- Internal: bumped `test` dev dependency to `^1.31.1` (dogfooded via pubup
  itself).
- Internal: `version_test.dart` now reads the version from `pubspec.yaml` at
  test time instead of hardcoding it, so future releases only require
  bumping `pubspec.yaml` and `lib/src/version.dart`.

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
