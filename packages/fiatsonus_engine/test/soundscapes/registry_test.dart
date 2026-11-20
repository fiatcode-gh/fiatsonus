import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:test/test.dart';

void main() {
  test('lists the waterfall only', () {
    expect(soundscapeIds, ['waterfall']);
  });

  test('creates a new waterfall per call', () {
    final a = createSoundscape('waterfall');
    final b = createSoundscape('waterfall');
    expect(a, isA<Waterfall>());
    expect(a!.id, 'waterfall');
    expect(identical(a, b), isFalse);
  });

  test('returns null for an unknown id', () {
    expect(createSoundscape('nope'), isNull);
  });
}
