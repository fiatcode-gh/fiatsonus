import '../core/soundscape.dart';
import 'waterfall/waterfall.dart';

/// Ids of every soundscape [createSoundscape] can build.
const List<String> soundscapeIds = ['waterfall'];

/// A new, unprepared soundscape for [id], or null for an unknown id.
Soundscape? createSoundscape(String id) => switch (id) {
  'waterfall' => Waterfall(),
  _ => null,
};
