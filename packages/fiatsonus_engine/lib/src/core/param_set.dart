import '../primitives/dsp_math.dart';
import '../primitives/smoother.dart';
import 'param_spec.dart';

/// Smoothed values for a fixed list of user controls.
final class ParamSet {
  final List<ParamSpec> _specs;
  final List<Smoother> _smoothers;

  /// Keeps an unmodifiable copy of [specs], with one smoother per spec.
  ParamSet(List<ParamSpec> specs)
    : _specs = List.unmodifiable(specs),
      _smoothers = [for (final s in specs) Smoother(s.defaultValue)];

  List<ParamSpec> get specs => _specs;

  /// Index of the control with [id], or -1 when unknown.
  int indexOf(String id) {
    for (var i = 0; i < _specs.length; i++) {
      if (_specs[i].id == id) return i;
    }
    return -1;
  }

  /// Sets every smoother's time constant and snaps every value and target to
  /// its default.
  void prepare(int sampleRate) {
    for (var i = 0; i < _specs.length; i++) {
      final spec = _specs[i];
      _smoothers[i]
        ..prepare(sampleRate, spec.smoothing)
        ..target = spec.defaultValue
        ..snap();
    }
  }

  /// Sets the target of control [id], clamped to 0..1. An unknown id or a
  /// NaN value is ignored.
  void set(String id, double value) {
    if (value.isNaN) return;
    final i = indexOf(id);
    if (i < 0) return;
    _smoothers[i].target = clampD(value, 0.0, 1.0);
  }

  /// Advances every smoother by one block.
  void advance() {
    for (var i = 0; i < _smoothers.length; i++) {
      _smoothers[i].next();
    }
  }

  /// Smoothed value of the control at [index].
  double value(int index) => _smoothers[index].value;

  /// Target of the control at [index].
  double target(int index) => _smoothers[index].target;
}
