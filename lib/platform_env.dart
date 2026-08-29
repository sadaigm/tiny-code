/// Cross-platform environment access. dart:io Platform throws on the web
/// build, so callers use these getters and the compiler picks the right
/// implementation (conditional import).
library;

export 'platform_env_stub.dart'
    if (dart.library.io) 'platform_env_io.dart';
