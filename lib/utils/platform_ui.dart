import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Flutter's Windows accessibility bridge can crash when the semantics tree
/// churns during chat streaming. Exclude semantics on Windows desktop only.
bool get useWindowsA11yWorkaround => !kIsWeb && Platform.isWindows;

Widget withPlatformSemantics(Widget child) {
  if (!useWindowsA11yWorkaround) return child;
  return ExcludeSemantics(child: child);
}
