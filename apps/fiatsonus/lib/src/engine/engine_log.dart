/// Writes [line] to the log. In release builds it reaches logcat with the
/// tag `flutter`. The only place in the app that prints.
void logLine(String line) {
  // ignore: avoid_print
  print(line);
}
