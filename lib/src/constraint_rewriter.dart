/// Standard caret-version constraint pattern: `^1.2.3`, `1.2.3`,
/// `^1.2.3-beta`, `^1.2.3+build`.
final standardConstraintPattern =
    RegExp(r'^\^?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-+]+)?$');

/// Result of rewriting a constraint in a `pubspec.yaml` string.
class RewriteResult {
  /// Creates a [RewriteResult].
  const RewriteResult({
    required this.content,
    required this.changed,
  });

  /// The updated file content.
  final String content;

  /// Whether at least one constraint line was rewritten.
  final bool changed;
}

/// Surgically replaces the version constraint for [packageName] in [section].
///
/// [section] must be `dependencies` or `dev_dependencies`. Other sections,
/// including `dependency_overrides`, are never modified.
///
/// Only standard caret/plain semver constraints are rewritten; `any`, ranges,
/// and `path`/`git`/`sdk` blocks are left unchanged.
RewriteResult rewriteConstraint({
  required String content,
  required String section,
  required String packageName,
  required String newConstraint,
}) {
  if (section != 'dependencies' && section != 'dev_dependencies') {
    return RewriteResult(content: content, changed: false);
  }

  final lines = content.split('\n');
  var changed = false;
  var currentSection = '';
  String? pendingPackage;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();

    if (!_isIndentedLine(line)) {
      currentSection =
          trimmed.endsWith(':') ? trimmed.substring(0, trimmed.length - 1) : '';
      pendingPackage = null;
      continue;
    }

    if (currentSection != section) {
      pendingPackage = null;
      continue;
    }

    final scalar = _tryRewriteScalarLine(
      line: line,
      packageName: packageName,
      newConstraint: newConstraint,
    );
    if (scalar != null) {
      lines[i] = scalar;
      changed = true;
      pendingPackage = null;
      continue;
    }

    final blockStart = _tryParsePackageBlockStart(line, packageName);
    if (blockStart) {
      pendingPackage = packageName;
      continue;
    }

    if (pendingPackage == packageName) {
      final versionLine = _tryRewriteVersionSubkeyLine(
        line: line,
        newConstraint: newConstraint,
      );
      if (versionLine != null) {
        lines[i] = versionLine;
        changed = true;
        pendingPackage = null;
      }
    }
  }

  return RewriteResult(
    content: lines.join('\n'),
    changed: changed,
  );
}

bool _isIndentedLine(String line) {
  return line.isNotEmpty && line != line.trimLeft();
}

String? _tryRewriteScalarLine({
  required String line,
  required String packageName,
  required String newConstraint,
}) {
  final match = RegExp(
    r'^(\s+)' + RegExp.escape(packageName) + r':\s*(\S+)(\s*#.*)?$',
  ).firstMatch(line);
  if (match == null) return null;

  final old = match.group(2)!;
  if (!standardConstraintPattern.hasMatch(old)) return null;

  final indent = match.group(1)!;
  final comment = match.group(3) ?? '';
  return '$indent$packageName: $newConstraint$comment';
}

bool _tryParsePackageBlockStart(String line, String packageName) {
  return RegExp(
    r'^(\s+)' + RegExp.escape(packageName) + r':\s*$',
  ).hasMatch(line);
}

String? _tryRewriteVersionSubkeyLine({
  required String line,
  required String newConstraint,
}) {
  final match = RegExp(r'^(\s+)version:\s*(\S+)(\s*#.*)?$').firstMatch(line);
  if (match == null) return null;

  final old = match.group(2)!;
  if (!standardConstraintPattern.hasMatch(old)) return null;

  final indent = match.group(1)!;
  final comment = match.group(3) ?? '';
  return '${indent}version: $newConstraint$comment';
}
