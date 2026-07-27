import 'package:flutter_test/flutter_test.dart';

import '../tool/add_minimum_supported_build.dart';

void main() {
  test('parses the required --minimum argument', () {
    expect(parseMinimumSupportedBuild(['--minimum', '15']), 15);
  });

  test('rejects a missing --minimum argument', () {
    expect(
      () => parseMinimumSupportedBuild([]),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Usage:'),
        ),
      ),
    );
  });

  test('rejects malformed, zero, and negative minimum values', () {
    expect(
      () => parseMinimumSupportedBuild(['--minimum', 'abc']),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('expected an integer'),
        ),
      ),
    );
    expect(
      () => parseMinimumSupportedBuild(['--minimum', '0']),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('greater than zero'),
        ),
      ),
    );
    expect(
      () => parseMinimumSupportedBuild(['--minimum', '-1']),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('greater than zero'),
        ),
      ),
    );
  });
}
