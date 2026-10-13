#!/usr/bin/env python3
"""Inject only the trusted UI transport origin into Xcode's generated test configuration.

The frozen evaluator, driver, corpus, selected tests and durations remain unchanged.
See Apple's local xcodebuild.xctestrun(5): UITargetAppEnvironmentVariables.
"""
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile


def configured_command(arguments, origin):
    if 'test-without-building' not in arguments:
        return arguments
    if '-derivedDataPath' not in arguments:
        raise RuntimeError('benchmark test invocation has no derived data path')
    derived = Path(arguments[arguments.index('-derivedDataPath') + 1])
    configs = list((derived / 'Build/Products').glob('*.xctestrun'))
    if len(configs) != 1:
        raise RuntimeError(f'expected one generated xctestrun, found {len(configs)}')
    config = configs[0]
    data = plistlib.loads(config.read_bytes())
    configured = 0

    def inject(value):
        nonlocal configured
        if isinstance(value, dict):
            if 'UITargetAppPath' in value:
                environment = value.setdefault('UITargetAppEnvironmentVariables', {})
                environment['FEEDMINE_BENCH_TRANSPORT_ORIGIN'] = origin
                configured += 1
            for child in list(value.values()):
                inject(child)
        elif isinstance(value, list):
            for child in value:
                inject(child)

    inject(data)
    if configured == 0:
        raise RuntimeError('generated xctestrun has no UI target application')
    config.write_bytes(plistlib.dumps(data))
    result = []
    index = 0
    while index < len(arguments):
        if arguments[index] in ('-project', '-workspace', '-scheme'):
            index += 2
        else:
            result.append(arguments[index])
            index += 1
    return result + ['-xctestrun', str(config)]


def main():
    if sys.argv[1:2] == ['--shim']:
        try:
            command = configured_command(sys.argv[2:], os.environ['FEEDMINE_BENCH_TRANSPORT_ORIGIN'])
        except (RuntimeError, KeyError, ValueError, OSError) as error:
            print(f'benchmark launch refused: {error}', file=sys.stderr)
            return 2
        if 'test-without-building' in command:
            print('benchmark launch: exact transport origin configured for UI target app', flush=True)
        return subprocess.call([os.environ['FEEDMINE_BENCH_REAL_XCODEBUILD'], *command])
    real = shutil.which('xcodebuild')
    if real is None:
        raise RuntimeError('xcodebuild is unavailable')
    environment = dict(os.environ, FEEDMINE_BENCH_REAL_XCODEBUILD=real)
    with tempfile.TemporaryDirectory(prefix='feedmine-benchmark-launch-') as tmp:
        shim = Path(tmp) / 'xcodebuild'
        shim.write_text('#!/usr/bin/env python3\nimport os,sys\nos.execv(sys.executable, [sys.executable, '
                        + repr(str(Path(__file__).resolve())) + ', "--shim", *sys.argv[1:]])\n')
        shim.chmod(0o755)
        environment['PATH'] = tmp + os.pathsep + environment['PATH']
        return subprocess.call(['bench/run.sh', *sys.argv[1:]], env=environment)


if __name__ == '__main__':
    sys.exit(main())
