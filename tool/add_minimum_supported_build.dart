import 'dart:convert';
import 'dart:io';

int parseMinimumSupportedBuild(List<String> arguments) {
  const usage =
      'Usage: dart run tool/add_minimum_supported_build.dart --minimum <positive-build>';

  if (arguments.length != 2 || arguments.first != '--minimum') {
    throw const FormatException(usage);
  }

  final minimum = int.tryParse(arguments[1]);
  if (minimum == null) {
    throw FormatException(
      'Invalid --minimum value "${arguments[1]}": expected an integer.\n$usage',
    );
  }
  if (minimum <= 0) {
    throw FormatException(
      'Invalid --minimum value "$minimum": value must be greater than zero.\n$usage',
    );
  }
  return minimum;
}

Future<void> main(List<String> arguments) async {
  try {
    final minimum = parseMinimumSupportedBuild(arguments);
    final manifestFile = File('build/web/version.json');
    final payload = jsonDecode(await manifestFile.readAsString());

    if (payload is! Map<String, dynamic>) {
      throw const FormatException(
        'build/web/version.json must contain a JSON object.',
      );
    }

    payload['minimumSupportedBuild'] = minimum;
    const encoder = JsonEncoder.withIndent('  ');
    await manifestFile.writeAsString('${encoder.convert(payload)}\n');
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln('Error: could not update build/web/version.json: $error');
    exitCode = 66;
  }
}
