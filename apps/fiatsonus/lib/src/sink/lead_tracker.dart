/// Finds starvation from the pull stream's lead at each demand (PLAN 4.5).
///
/// Leads are collected per block of [blockDemands] demands and each block
/// is represented by its maximum. The first block is the start-up fill and
/// is discarded; the second sets the reference. A later block whose maximum
/// falls more than the tolerance below the reference is one underrun of
/// that size, and its maximum becomes the new reference.
final class LeadTracker {
  LeadTracker({required this._toleranceMicros, this._blockDemands = 64});

  final int _toleranceMicros;
  final int _blockDemands;

  int _inBlock = 0;
  int _blockMax = 0;
  int _blocks = 0;
  int _reference = 0;
  int _underruns = 0;
  int _starved = 0;
  int _jitter = 0;

  /// Records the lead at one demand.
  void observe(int leadMicros) {
    if (_inBlock == 0 || leadMicros > _blockMax) _blockMax = leadMicros;
    if (++_inBlock < _blockDemands) return;
    _inBlock = 0;
    _closeBlock(_blockMax);
  }

  void _closeBlock(int blockMax) {
    _blocks++;
    if (_blocks == 1) return;
    if (_blocks == 2) {
      _reference = blockMax;
      return;
    }
    final drop = _reference - blockMax;
    if (drop > _toleranceMicros) {
      _underruns++;
      _starved += drop;
      _reference = blockMax;
      return;
    }
    if (drop.abs() > _jitter) _jitter = drop.abs();
    if (blockMax > _reference) _reference = blockMax;
  }

  /// Drops larger than the tolerance.
  int get underruns => _underruns;

  /// Sum of those drops.
  int get starvedMicros => _starved;

  /// Largest deviation from the reference that was not an underrun.
  int get jitterMicros => _jitter;

  /// The steady lead; 0 until the second block.
  int get referenceMicros => _reference;
}
