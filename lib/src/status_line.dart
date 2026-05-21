import 'dart:async';
import 'dart:io';

/// Environment variable that disables the live progress indicator when set
/// to any value other than `0` or `false`.
const disableProgressEnv = 'PUBUP_DISABLE_PROGRESS';

/// Reports a short description of the task pubup is currently performing.
///
/// A `null` message means: no task is in progress. Implementations that
/// render a live UI should clear it on `null`.
typedef StatusReporter = void Function(String? message);

/// A no-op [StatusReporter] used when callers don't care about progress.
void noopStatusReporter(String? message) {}

/// Returns whether environment variables say the live progress indicator
/// should be disabled, regardless of TTY status.
///
/// The indicator is disabled when:
/// - `CI=true`
/// - `TERM=dumb`
/// - [disableProgressEnv] is set to a non-empty value other than `0` /
///   `false`.
bool isProgressDisabledByEnvironment(Map<String, String> environment) {
  if (environment['CI'] == 'true') return true;
  if (environment['TERM'] == 'dumb') return true;
  final disable = environment[disableProgressEnv];
  if (disable == null) return false;
  if (disable.isEmpty) return true;
  return disable != '0' && disable.toLowerCase() != 'false';
}

/// Single-line live status indicator that updates in place using ANSI
/// cursor motion.
///
/// Animates a spinner alongside a description of the current task and
/// reserves one blank line of padding below it so the indicator has visual
/// breathing room. On non-interactive output (CI, redirected streams,
/// `TERM=dumb`, or when the `PUBUP_DISABLE_PROGRESS` environment variable
/// is set) the indicator is a no-op so logs stay clean.
///
/// The line is written to [stderr] by default so that capturing pubup's
/// stdout (e.g. into a file or pipe) does not interleave the animation with
/// real output.
class StatusLine {
  /// Creates a [StatusLine].
  ///
  /// [out] defaults to [stderr]. [enabled] forces the indicator on or off
  /// (useful for tests); when `null` (the default), it is auto-detected from
  /// [environment] and [out]'s terminal status.
  StatusLine({
    StringSink? out,
    Duration tickInterval = const Duration(milliseconds: 100),
    Map<String, String>? environment,
    bool? enabled,
    List<String>? frames,
  })  : _out = out ?? stderr,
        _tickInterval = tickInterval,
        _environment = environment ?? Platform.environment,
        _forceEnabled = enabled,
        _frames = frames ?? _defaultFrames;

  final StringSink _out;
  final Duration _tickInterval;
  final Map<String, String> _environment;
  final bool? _forceEnabled;
  final List<String> _frames;

  // Braille spinner — visually pleasing and supported by every modern
  // UTF-8 terminal.
  static const List<String> _defaultFrames = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ];

  Timer? _timer;
  String _message = '';
  int _frame = 0;
  int _lastWidth = 0;

  late final bool _enabled = _forceEnabled ?? _detectEnabled();

  /// Whether this status line will actually render anything.
  bool get isEnabled => _enabled;

  bool _detectEnabled() {
    if (isProgressDisabledByEnvironment(_environment)) return false;
    return _hasTerminal();
  }

  bool _hasTerminal() {
    try {
      if (identical(_out, stderr)) return stderr.hasTerminal;
      if (identical(_out, stdout)) return stdout.hasTerminal;
    } on StdoutException {
      return false;
    }
    return false;
  }

  /// Updates the status line to display [message], or clears it if
  /// [message] is `null`.
  void update(String? message) {
    if (message == null) {
      clear();
      return;
    }
    _message = message;
    if (!_enabled) return;
    _timer ??= Timer.periodic(_tickInterval, (_) => _render());
    _render();
  }

  /// Clears the status line and stops animating.
  void clear() {
    _timer?.cancel();
    _timer = null;
    if (!_enabled) return;
    if (_lastWidth == 0) return;
    // Mirrors the layout written by [_render]: two consecutive lines
    // (spinner row + padding row) are erased and the cursor is moved back
    // up so subsequent output lands at the row the spinner used to
    // occupy.
    _out.write('\r\x1B[K\n\x1B[K\x1B[1A');
    _lastWidth = 0;
  }

  void _render() {
    final spinner = _frames[_frame % _frames.length];
    _frame++;
    var line = '$spinner $_message';
    final maxCols = _terminalColumns();
    if (maxCols != null && line.length > maxCols - 1) {
      // Reserve one column so the cursor doesn't push us onto a new line,
      // which would defeat the cursor-up trick.
      final cut = maxCols - 2;
      if (cut > 0) line = '${line.substring(0, cut)}…';
    }
    // Write the spinner line followed by an empty padding line, then move
    // the cursor back up to the spinner row. The escape sequence breakdown:
    //
    //   \r       — carriage return to column 0 of the spinner row
    //   \x1B[K   — erase from cursor to end of line (clears any prior text)
    //   {line}   — spinner glyph + status message
    //   \n       — newline; cursor advances to the padding row
    //   \x1B[K   — erase that row too
    //   \x1B[1A  — move the cursor up 1 row, back onto the spinner row
    //
    // The padding row stays visibly blank below the spinner, giving the
    // indicator breathing room from whatever appears next in the terminal.
    _out.write('\r\x1B[K$line\n\x1B[K\x1B[1A');
    _lastWidth = line.length;
  }

  int? _terminalColumns() {
    try {
      if (stdout.hasTerminal) return stdout.terminalColumns;
    } on StdoutException {
      return null;
    }
    return null;
  }
}
