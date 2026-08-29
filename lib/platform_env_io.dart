/// IO (desktop) implementation of the platform environment.
library;

import 'dart:io';

bool get isWeb => false;
bool get isLinux => Platform.isLinux;
String get homeDir =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
String get currentPath => Directory.current.path;
