/// A user control. Its value is always 0..1 at the interface.
final class ParamSpec {
  /// Stable identifier, for example `'flow'` or `'distance'`.
  final String id;

  /// Text shown in the UI.
  final String label;

  /// Value used until the user changes it, in 0..1.
  final double defaultValue;

  /// Time over which a change of this control is smoothed.
  final Duration smoothing;

  const ParamSpec(
    this.id,
    this.label,
    this.defaultValue, {
    this.smoothing = const Duration(milliseconds: 200),
  });
}
