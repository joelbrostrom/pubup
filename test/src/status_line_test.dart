import 'package:pubup/src/status_line.dart';
import 'package:test/test.dart';

void main() {
  group('isProgressDisabledByEnvironment', () {
    test('returns true when CI=true', () {
      expect(isProgressDisabledByEnvironment(const {'CI': 'true'}), isTrue);
    });

    test('returns true when TERM=dumb', () {
      expect(isProgressDisabledByEnvironment(const {'TERM': 'dumb'}), isTrue);
    });

    test('returns true when PUBUP_DISABLE_PROGRESS=1', () {
      expect(
        isProgressDisabledByEnvironment(const {'PUBUP_DISABLE_PROGRESS': '1'}),
        isTrue,
      );
    });

    test('returns true when PUBUP_DISABLE_PROGRESS is empty', () {
      expect(
        isProgressDisabledByEnvironment(const {'PUBUP_DISABLE_PROGRESS': ''}),
        isTrue,
      );
    });

    test('returns false when PUBUP_DISABLE_PROGRESS=0 or =false', () {
      for (final value in const ['0', 'false', 'False', 'FALSE']) {
        expect(
          isProgressDisabledByEnvironment({'PUBUP_DISABLE_PROGRESS': value}),
          isFalse,
          reason: 'PUBUP_DISABLE_PROGRESS=$value should not disable progress',
        );
      }
    });

    test('returns false when no relevant env var is set', () {
      expect(isProgressDisabledByEnvironment(const {}), isFalse);
      expect(
        isProgressDisabledByEnvironment(const {'CI': 'false'}),
        isFalse,
      );
    });
  });

  group('StatusLine', () {
    test('forced-disabled status line writes nothing', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: false,
        frames: const ['*'],
      );

      expect(status.isEnabled, isFalse);

      status.update('Scanning packages/auth (3/56)');
      status.clear();

      expect(buffer.toString(), isEmpty);
    });

    test('renders spinner + message and reserves a blank padding row below',
        () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['*'],
      );

      status.update('Scanning packages/auth (3/56)');

      expect(
        buffer.toString(),
        '\r\x1B[K* Scanning packages/auth (3/56)\n\x1B[K\x1B[1A',
      );
    });

    test('clear() erases both the spinner row and the padding row below', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['*'],
      );

      status.update('Scanning');
      buffer.clear();

      status.clear();

      expect(buffer.toString(), '\r\x1B[K\n\x1B[K\x1B[1A');
    });

    test('update(null) clears the line', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['*'],
      );

      status.update('Scanning');
      buffer.clear();

      status.update(null);

      expect(buffer.toString(), '\r\x1B[K\n\x1B[K\x1B[1A');
    });

    test('multiple updates rerender in place using cursor motion', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['*'],
      );

      status.update('Scanning packages/auth (3/56)');
      status.update('Running flutter pub get');

      final out = buffer.toString();
      expect(out, contains('Scanning packages/auth (3/56)'));
      expect(out, contains('Running flutter pub get'));
      // Each render emits one cursor-up sequence so the next render lands
      // back on the spinner row.
      expect('\x1B[1A'.allMatches(out).length, 2);
    });

    test('shorter follow-up message erases trailing chars via \\x1B[K', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['*'],
      );

      status.update('Scanning packages/auth (3/56)');
      buffer.clear();

      status.update('Done');

      final lastWrite = buffer.toString();
      expect(lastWrite, contains('Done'));
      // The erase-to-end-of-line escape replaces the old space-padding
      // approach for clobbering leftover characters.
      expect(lastWrite, contains('\x1B[K'));
    });

    test('cycles through provided frames on successive updates', () {
      final buffer = StringBuffer();
      final status = StatusLine(
        out: buffer,
        enabled: true,
        frames: const ['A', 'B', 'C'],
      );

      status.update('Scanning');
      status.update('Scanning');
      status.update('Scanning');
      status.update('Scanning');

      final out = buffer.toString();
      expect(out, contains('A Scanning'));
      expect(out, contains('B Scanning'));
      expect(out, contains('C Scanning'));
      // Frame index wraps back to A on the 4th render.
      expect('A Scanning'.allMatches(out).length, 2);

      status.clear();
    });
  });
}
