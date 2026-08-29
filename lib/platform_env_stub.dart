/// Web implementation: dart:io Platform/Directory throw on the web compile
/// target, so everything degrades to inert defaults.
library;

bool get isWeb => true;
bool get isLinux => false;
String get homeDir => '/';
String get currentPath => '/';
