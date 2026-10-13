import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('benchmark_launch', ROOT / 'scripts' / 'benchmark_launch.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class BenchmarkLaunchTests(unittest.TestCase):
    def test_ui_target_receives_origin_without_changing_test_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            derived = Path(tmp)
            products = derived / 'Build/Products'
            products.mkdir(parents=True)
            config = products / 'FeedMine.xctestrun'
            original = {'TestConfigurations': [{'TestTargets': [
                {'BlueprintName': 'FeedMineUITests', 'UITargetAppPath': '__TESTROOT__/Debug/FeedMine.app',
                 'UITargetAppEnvironmentVariables': {'KEEP': 'yes'}, 'OnlyTestIdentifiers': ['DiscoveryBenchmarkTests/testB03ThirtyMinuteRunway']},
                {'BlueprintName': 'FeedMineTests', 'EnvironmentVariables': {'KEEP_UNIT': 'yes'}}]}]}
            config.write_bytes(plistlib.dumps(original))
            result = launcher.configured_command(['test-without-building', '-project', 'app.xcodeproj', '-scheme', 'FeedMine',
                '-destination', 'platform=iOS Simulator,id=abc', '-derivedDataPath', str(derived),
                '-only-testing:FeedMineUITests/DiscoveryBenchmarkTests/testB03ThirtyMinuteRunway'], 'http://127.0.0.1:8757')
            self.assertNotIn('-project', result)
            self.assertNotIn('-scheme', result)
            self.assertIn('-xctestrun', result)
            self.assertIn('-only-testing:FeedMineUITests/DiscoveryBenchmarkTests/testB03ThirtyMinuteRunway', result)
            self.assertIn('platform=iOS Simulator,id=abc', result)
            changed = plistlib.loads(config.read_bytes())
            target = changed['TestConfigurations'][0]['TestTargets'][0]
            self.assertEqual(target['UITargetAppEnvironmentVariables'], {'KEEP': 'yes', 'FEEDMINE_BENCH_TRANSPORT_ORIGIN': 'http://127.0.0.1:8757'})
            self.assertEqual(target['OnlyTestIdentifiers'], original['TestConfigurations'][0]['TestTargets'][0]['OnlyTestIdentifiers'])
            self.assertEqual(changed['TestConfigurations'][0]['TestTargets'][1], original['TestConfigurations'][0]['TestTargets'][1])

    def test_refuses_missing_generated_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(RuntimeError):
                launcher.configured_command(['test-without-building', '-derivedDataPath', tmp], 'http://127.0.0.1:8757')

    def test_non_test_commands_are_preserved(self):
        command = ['build-for-testing', '-project', 'app.xcodeproj', '-scheme', 'FeedMine']
        self.assertEqual(launcher.configured_command(command, 'http://127.0.0.1:8757'), command)


if __name__ == '__main__':
    unittest.main()
