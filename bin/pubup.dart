import 'dart:io';

import 'package:pubup/src/cli.dart';

Future<void> main(List<String> arguments) async {
  exit(await runCli(arguments));
}
