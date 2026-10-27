import unittest

from pacing_probe import measure, judge


class ConsumptionTests(unittest.TestCase):
    def test_stationary_anchor_is_not_consumption_or_a_seen_forward_anchor(self):
        phase = dict(started_at=0, ended_at=10, gestures=2)
        advances = [
            dict(at=1, anchor='a', activity='stationary'),
            dict(at=2, anchor='b', activity='forward'),
            dict(at=3, anchor='a', activity='forward'),
            dict(at=4, anchor='c', activity='stationary'),
        ]
        result = measure(phase, advances)
        self.assertEqual(result['distinct_anchors'], 2)
        self.assertEqual(result['distinct_anchors_per_s'], 0.2)
        self.assertEqual(result['anchors_per_gesture'], 1)
        self.assertEqual(result['stationary_events'], 2)
        self.assertEqual(result['advance_events'], 4)

    def test_revisits_and_repeats_do_not_inflate_consumption(self):
        phase = dict(started_at=0, ended_at=10, gestures=4)
        advances = [dict(at=i + 1, anchor=a, activity='forward')
                    for i, a in enumerate(['a', 'a', 'b', 'a'])]
        result = measure(phase, advances)
        self.assertEqual(result['distinct_anchors'], 2)
        self.assertEqual(result['repeated_anchor_events'], 1)

    def test_forward_after_stationary_on_the_same_anchor_still_counts(self):
        phase = dict(started_at=0, ended_at=10, gestures=1)
        advances = [dict(at=1, anchor='a', activity='stationary'),
                    dict(at=2, anchor='a', activity='forward')]
        self.assertEqual(measure(phase, advances)['distinct_anchors'], 1)


class PhaseIntegrityTests(unittest.TestCase):
    def test_valid_base_and_burst_can_hit(self):
        for rate, expectation in [(1, {'base_distinct_per_s': 1}),
                                  (3, {'burst_distinct_per_s': 3})]:
            with self.subTest(rate=rate):
                count = rate * 10
                phase = dict(started_at=0, ended_at=10, gestures=count)
                advances = [dict(at=i / rate, anchor=str(i), activity='forward')
                            for i in range(count)]
                self.assertEqual(judge(measure(phase, advances), expectation), [])

    def test_zero_gestures_are_preserved_and_cannot_hit(self):
        result = measure(dict(started_at=0, ended_at=1, gestures=0), [])
        self.assertEqual(result['gestures'], 0)
        self.assertEqual(result['gesture_rate_per_s'], 0)
        self.assertIsNone(result['anchors_per_gesture'])
        self.assertTrue(judge(result, {}))

    def test_missing_gesture_count_is_not_invented(self):
        with self.assertRaises(ValueError):
            measure(dict(started_at=0, ended_at=1), [])

    def test_invalid_duration_is_rejected(self):
        for start, end in [(1, 1), (2, 1), (0, float('inf')), (float('nan'), 1)]:
            with self.subTest(start=start, end=end), self.assertRaises(ValueError):
                measure(dict(started_at=start, ended_at=end, gestures=1), [])

    def test_invalid_gesture_count_is_rejected(self):
        for count in [-1, 1.5, True, '10']:
            with self.subTest(count=count), self.assertRaises(ValueError):
                measure(dict(started_at=0, ended_at=1, gestures=count), [])


if __name__ == '__main__':
    unittest.main()
