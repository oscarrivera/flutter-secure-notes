import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final container = await AppContainer.production();
  runApp(SecureNotesApp(container: container));
}
