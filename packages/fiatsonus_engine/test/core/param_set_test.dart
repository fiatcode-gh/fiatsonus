import 'package:fiatsonus_engine/fiatsonus_engine.dart';
import 'package:test/test.dart';

const _flow = ParamSpec('flow', 'Flow', 0.6);
const _distance = ParamSpec(
  'distance',
  'Distance',
  0.4,
  smoothing: Duration(milliseconds: 50),
);

ParamSet _prepared() => ParamSet([_flow, _distance])..prepare(48000);

void main() {
  test('values and targets start at the defaults', () {
    final p = _prepared();
    expect(p.value(0), 0.6);
    expect(p.target(0), 0.6);
    expect(p.value(1), 0.4);
    expect(p.target(1), 0.4);
  });

  test('indexOf finds ids and returns -1 for unknown ones', () {
    final p = _prepared();
    expect(p.indexOf('flow'), 0);
    expect(p.indexOf('distance'), 1);
    expect(p.indexOf('nope'), -1);
  });

  test('set clamps to 0..1', () {
    final p = _prepared();
    p.set('flow', -1);
    expect(p.target(0), 0.0);
    p.set('flow', 2);
    expect(p.target(0), 1.0);
  });

  test('set ignores NaN', () {
    final p = _prepared()..set('flow', 0.9);
    p.set('flow', double.nan);
    expect(p.target(0), 0.9);
  });

  test('set ignores an unknown id', () {
    final p = _prepared();
    expect(() => p.set('nope', 0.5), returnsNormally);
    expect(p.target(0), 0.6);
    expect(p.target(1), 0.4);
  });

  test('value moves toward the target across advance and reaches it', () {
    final p = _prepared()..set('flow', 1.0);
    var previous = p.value(0);
    for (var i = 0; i < 20; i++) {
      p.advance();
      expect(p.value(0), greaterThan(previous));
      previous = p.value(0);
    }
    for (var i = 0; i < 1000; i++) {
      p.advance();
    }
    expect(p.value(0), 1.0);
  });

  test('a 50 ms spec moves faster than a 200 ms spec', () {
    final p = _prepared()
      ..set('flow', 1.0)
      ..set('distance', 1.0);
    p.advance();
    p.advance();
    final flowMoved = p.value(0) - 0.6;
    final distanceMoved = p.value(1) - 0.4;
    expect(distanceMoved / 0.6, greaterThan(flowMoved / 0.4));
  });

  test('specs cannot be modified by the caller', () {
    final source = [_flow];
    final p = ParamSet(source);
    source.add(_distance);
    expect(p.specs, [_flow]);
    expect(() => p.specs.add(_distance), throwsUnsupportedError);
  });

  test('an invalid index is a RangeError', () {
    final p = _prepared();
    expect(() => p.value(2), throwsRangeError);
    expect(() => p.target(-1), throwsRangeError);
  });
}
