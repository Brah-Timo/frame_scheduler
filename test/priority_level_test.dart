import 'package:flutter_test/flutter_test.dart';
import 'package:frame_scheduler/frame_scheduler.dart';

void main() {
  group('PriorityLevel — weight ordering', () {
    test('critical has the highest weight', () {
      expect(PriorityLevel.critical.weight, 4);
    });

    test('high has weight 3', () {
      expect(PriorityLevel.high.weight, 3);
    });

    test('normal has weight 2', () {
      expect(PriorityLevel.normal.weight, 2);
    });

    test('low has the lowest weight (1)', () {
      expect(PriorityLevel.low.weight, 1);
    });

    test('weights are strictly decreasing', () {
      final weights = PriorityLevel.values.map((p) => p.weight).toList();
      for (int i = 0; i < weights.length - 1; i++) {
        expect(weights[i], greaterThan(weights[i + 1]));
      }
    });
  });

  group('PriorityLevel — display helpers', () {
    test('displayName for critical is "Critical"', () {
      expect(PriorityLevel.critical.displayName, 'Critical');
    });

    test('displayName for high is "High"', () {
      expect(PriorityLevel.high.displayName, 'High');
    });

    test('displayName for normal is "Normal"', () {
      expect(PriorityLevel.normal.displayName, 'Normal');
    });

    test('displayName for low is "Low"', () {
      expect(PriorityLevel.low.displayName, 'Low');
    });

    test('badge for critical is "[C]"', () {
      expect(PriorityLevel.critical.badge, '[C]');
    });

    test('badge for high is "[H]"', () {
      expect(PriorityLevel.high.badge, '[H]');
    });

    test('badge for normal is "[N]"', () {
      expect(PriorityLevel.normal.badge, '[N]');
    });

    test('badge for low is "[L]"', () {
      expect(PriorityLevel.low.badge, '[L]');
    });

    test('each level has a non-empty emoji', () {
      for (final p in PriorityLevel.values) {
        expect(p.emoji, isNotEmpty);
      }
    });
  });

  group('PriorityLevel — comparators', () {
    test('critical.isHigherThan(high) is true', () {
      expect(PriorityLevel.critical.isHigherThan(PriorityLevel.high), isTrue);
    });

    test('low.isLowerThan(normal) is true', () {
      expect(PriorityLevel.low.isLowerThan(PriorityLevel.normal), isTrue);
    });

    test('high.isHigherThan(critical) is false', () {
      expect(PriorityLevel.high.isHigherThan(PriorityLevel.critical), isFalse);
    });

    test('isAtLeast with equal level is true', () {
      expect(PriorityLevel.normal.isAtLeast(PriorityLevel.normal), isTrue);
    });

    test('low.isAtLeast(critical) is false', () {
      expect(PriorityLevel.low.isAtLeast(PriorityLevel.critical), isFalse);
    });

    test('critical.isAtLeast(low) is true', () {
      expect(PriorityLevel.critical.isAtLeast(PriorityLevel.low), isTrue);
    });
  });

  group('PriorityLevel — upgrade', () {
    test('low.upgraded == normal', () {
      expect(PriorityLevel.low.upgraded, PriorityLevel.normal);
    });

    test('normal.upgraded == high', () {
      expect(PriorityLevel.normal.upgraded, PriorityLevel.high);
    });

    test('high.upgraded == critical', () {
      expect(PriorityLevel.high.upgraded, PriorityLevel.critical);
    });

    test('critical.upgraded == critical (capped)', () {
      expect(PriorityLevel.critical.upgraded, PriorityLevel.critical);
    });
  });

  group('PriorityLevel — downgrade', () {
    test('critical.downgraded == high', () {
      expect(PriorityLevel.critical.downgraded, PriorityLevel.high);
    });

    test('high.downgraded == normal', () {
      expect(PriorityLevel.high.downgraded, PriorityLevel.normal);
    });

    test('normal.downgraded == low', () {
      expect(PriorityLevel.normal.downgraded, PriorityLevel.low);
    });

    test('low.downgraded == low (floor)', () {
      expect(PriorityLevel.low.downgraded, PriorityLevel.low);
    });
  });
}
