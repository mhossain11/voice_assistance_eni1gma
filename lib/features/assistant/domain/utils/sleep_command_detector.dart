final RegExp _punctuation = RegExp(r"[^a-z0-9\s']");
final RegExp _spaces = RegExp(r'\s+');

const _sleepCommands = {
  'sleep',
  'go to sleep',
  'enigma sleep',
  'enigma go to sleep',
  'stop listening',
  'stop listening now',
  'you can sleep',
  "that's all",
  'that is all',
};

bool isSleepCommand(String text) {
  final normalized = text
      .toLowerCase()
      .trim()
      .replaceAll(_punctuation, ' ')
      .replaceAll(_spaces, ' ')
      .trim();
  return _sleepCommands.contains(normalized);
}
