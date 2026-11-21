import 'package:flutter_test/flutter_test.dart';

import '../../tool/device/src/battery_history.dart';
import 'fixtures.dart';

void main() {
  group('unplugged window', () {
    test('runs from the first plug=none line to the next plug line', () {
      final window = parseUnpluggedWindow(
        fixture('batterystats_history_unplug.txt'),
      );

      expect(window.start, DateTime.utc(2026, 10, 21, 10, 32, 40, 331));
      expect(window.end, DateTime.utc(2026, 10, 22, 8, 40, 38, 615));
      expect(window.startChargeMah, 4789);
      expect(window.endChargeMah, 4401);
      expect(window.startLevel, 84);
      expect(window.endLevel, 78);
      expect(window.mah, 388);
      expect(window.seconds, closeTo(79678.284, 1e-9));
      expect(window.hours, closeTo(79678.284 / 3600, 1e-9));
      expect(window.mahPerHour, closeTo(388 / (79678.284 / 3600), 1e-9));
      expect(window.levelDrop, 6);
    });

    test('charge carries forward from the last line that states it', () {
      final history = fixture('batterystats_history_unplug.txt')
          .replaceFirst(
            'plug=none volt=4276 charge=4789',
            'plug=none volt=4276',
          )
          .replaceFirst('plug=usb volt=4141 charge=4401', 'plug=usb volt=4141');

      final window = parseUnpluggedWindow(history);

      expect(window.startChargeMah, 4772);
      expect(window.endChargeMah, 4406);
    });

    test('a history that never unplugs has no window', () {
      final plugged = fixture('batterystats_history_unplug.txt')
          .split('\n')
          .takeWhile((l) => !l.contains('plug=none'))
          .join('\n');

      expect(
        () => parseUnpluggedWindow(plugged),
        throwsA(isA<FormatException>()),
      );
    });

    test('a history that never plugs back in has no window', () {
      expect(
        () => parseUnpluggedWindow(fixture('batterystats_history.txt')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('app estimate', () {
    test('the uid line under "Estimated power use"', () {
      expect(
        parseAppEstimateMah(fixture('batterystats_app_chrome.txt'), 'u0a206'),
        23.2,
      );
    });

    test('null when the uid has no estimate line', () {
      expect(
        parseAppEstimateMah(fixture('batterystats_app_bbkmusic.txt'), 'u0a105'),
        isNull,
      );
    });
  });
}
