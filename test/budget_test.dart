import 'package:bayar/core/dates.dart';
import 'package:bayar/domain/budget.dart';
import 'package:bayar/domain/pay_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

final _t = DateTime.utc(2026, 1, 1);

Envelope envelope(String id) => Envelope(id: id, name: id, sortOrder: 0, createdAt: _t, updatedAt: _t);

Allocation alloc(String envelopeId, DateTime cycleStart, int sen) => Allocation(
  id: '$envelopeId-${toIsoDate(cycleStart)}',
  envelopeId: envelopeId,
  cycleStart: cycleStart,
  amountSen: sen,
  createdAt: _t,
  updatedAt: _t,
);

Spending spend(String envelopeId, DateTime on, int sen, {DateTime? created}) => Spending(
  id: '$envelopeId-$on-$sen',
  envelopeId: envelopeId,
  amountSen: sen,
  spentOn: on,
  createdAt: created ?? _t,
  updatedAt: created ?? _t,
);

void main() {
  group('allocationFor (plans carry over)', () {
    final oct = dateOf(2026, 10, 25);
    final nov = dateOf(2026, 11, 25);
    final dec = dateOf(2026, 12, 25);

    test('an exact row wins', () {
      expect(allocationFor([alloc('food', oct, 70000)], 'food', oct), 70000);
    });

    test('a cycle with no row inherits the latest earlier one', () {
      final all = [alloc('food', oct, 70000), alloc('food', nov, 80000)];
      expect(allocationFor(all, 'food', dec), 80000);
      expect(allocationFor(all, 'food', nov), 80000);
    });

    test('earlier cycles are not affected by a later change', () {
      final all = [alloc('food', oct, 70000), alloc('food', nov, 80000)];
      expect(allocationFor(all, 'food', oct), 70000);
    });

    test('nothing before the first row means zero', () {
      expect(allocationFor([alloc('food', nov, 80000)], 'food', oct), 0);
    });

    test('other envelopes do not leak in', () {
      expect(allocationFor([alloc('fuel', oct, 30000)], 'food', oct), 0);
    });

    test('a later row can be set back to zero', () {
      final all = [alloc('food', oct, 70000), alloc('food', nov, 0)];
      expect(allocationFor(all, 'food', dec), 0);
    });
  });

  group('buildEnvelopeView', () {
    // Day 19 of 31 in the cycle 25 Oct .. 24 Nov.
    final cycle = PayCycle.containing(dateOf(2026, 11, 12), paydayDay: 25);
    final today = dateOf(2026, 11, 12);
    final start = cycle.start;

    EnvelopeView view({required int budget, List<Spending> spendings = const [], DateTime? on}) => buildEnvelopeView(
      envelope: envelope('food'),
      allocations: [alloc('food', start, budget)],
      spendings: spendings,
      cycle: cycle,
      today: on ?? today,
    );

    test('left is budget minus what was spent in this cycle', () {
      final v = view(
        budget: 70000,
        spendings: [spend('food', dateOf(2026, 11, 1), 12000), spend('food', dateOf(2026, 11, 10), 30000)],
      );
      expect(v.budgetSen, 70000);
      expect(v.spentSen, 42000);
      expect(v.leftSen, 28000);
    });

    test('spending from other cycles and other envelopes is ignored', () {
      final v = view(
        budget: 70000,
        spendings: [
          spend('food', dateOf(2026, 10, 24), 99999), // before this cycle
          spend('food', dateOf(2026, 11, 25), 99999), // after it
          spend('fuel', dateOf(2026, 11, 5), 99999), // another envelope
          spend('food', dateOf(2026, 10, 25), 1000), // first day counts
          spend('food', dateOf(2026, 11, 24), 2000), // last day counts
        ],
      );
      expect(v.spentSen, 3000);
    });

    test('daily safe amount is what is left divided over the days left, today included', () {
      // 13 days left (12 Nov .. 24 Nov). 28000 / 13 = 2153.8 -> 2154.
      final v = view(budget: 70000, spendings: [spend('food', dateOf(2026, 11, 1), 42000)]);
      expect(v.dailySafeSen, 2154);
    });

    test('daily safe is zero once the envelope is empty or overspent', () {
      expect(view(budget: 1000, spendings: [spend('food', dateOf(2026, 11, 1), 1000)]).dailySafeSen, 0);
      expect(view(budget: 1000, spendings: [spend('food', dateOf(2026, 11, 1), 1500)]).dailySafeSen, 0);
    });

    test('spendings are listed newest first', () {
      final v = view(
        budget: 70000,
        spendings: [
          spend('food', dateOf(2026, 11, 3), 100),
          spend('food', dateOf(2026, 11, 9), 200),
          spend('food', dateOf(2026, 11, 9), 300, created: DateTime.utc(2026, 11, 9, 12)),
        ],
      );
      expect(v.spendings.map((s) => s.amountSen), [300, 200, 100]);
    });

    test('left fraction is clamped for drawing the bar', () {
      expect(view(budget: 1000, spendings: [spend('food', dateOf(2026, 11, 1), 5000)]).leftFraction, 0);
      expect(view(budget: 0).leftFraction, 0);
      expect(view(budget: 1000).leftFraction, 1);
    });

    group('pace', () {
      // Day 19 of 31, so about 38.7% of the budget should be left.
      test('no budget means no pace', () => expect(view(budget: 0).pace, Pace.none));

      test('untouched money is well under pace', () {
        expect(view(budget: 70000).pace, Pace.underPace);
      });

      test('about the right amount left is on track', () {
        // 39% left: expected 38.7%.
        expect(view(budget: 100000, spendings: [spend('food', dateOf(2026, 11, 1), 61000)]).pace, Pace.onTrack);
      });

      test('a little less than expected is fast', () {
        // 30% left vs 38.7% expected.
        expect(view(budget: 100000, spendings: [spend('food', dateOf(2026, 11, 1), 70000)]).pace, Pace.fast);
      });

      test('more spent than budgeted is over', () {
        expect(view(budget: 1000, spendings: [spend('food', dateOf(2026, 11, 1), 1001)]).pace, Pace.over);
      });

      test('spending exactly the budget is not over, it is just empty (and fast)', () {
        expect(view(budget: 1000, spendings: [spend('food', dateOf(2026, 11, 1), 1000)]).pace, Pace.fast);
      });

      test('on day 1 with nothing spent, you are on track', () {
        final v = view(budget: 70000, on: dateOf(2026, 10, 25));
        expect(v.pace, Pace.onTrack);
        expect(v.expectedLeftFraction, closeTo(1 - 1 / 31, 0.0001));
      });
    });
  });
}
