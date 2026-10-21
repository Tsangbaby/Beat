#!/usr/bin/env python3
"""Execute production startup seams on cloud Mac; never install the tweak."""
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(command, timeout=180, marker=None):
    print('+', ' '.join(map(str, command)), flush=True)
    result = subprocess.run(list(map(str, command)), cwd=ROOT, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, flush=True)
    if result.returncode != 0:
        raise RuntimeError(f'command failed: {result.returncode}')
    if marker is not None and marker not in result.stdout:
        raise RuntimeError(f'missing executed pass marker: {marker}')
    return result.stdout


def main():
    if platform.system() != 'Darwin':
        raise SystemExit('Apple startup tests require the authorized cloud Mac')
    support = ROOT / 'Sources/Support'
    fixtures = ROOT / 'tests/apple'
    with tempfile.TemporaryDirectory(prefix='stheno-apple-startup-', dir=os.environ.get('RUNNER_TEMP')) as temp:
        temp = Path(temp)
        c_object, objc_object = temp / 'types.o', temp / 'method.o'
        run(['xcrun', 'clang', '-c', '-Wall', '-Wextra', '-Werror', support / 'SthenoTypeEncoding.c', '-o', c_object])
        run(['xcrun', 'clang++', '-c', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
             support / 'SthenoMethodABI.mm', '-o', objc_object])
        native = temp / 'NativeABITests'
        run(['xcrun', 'clang++', '-fobjc-arc', '-I', support, fixtures / 'NativeABITests.mm',
             c_object, objc_object, '-framework', 'Foundation', '-framework', 'CoreGraphics', '-o', native])
        run([native], marker='NATIVE_ABI_ALL_PASS')
        # Test the actual production backend, with only Orion's descriptor API shimmed.
        run(['xcrun', 'swiftc', '-emit-library', '-emit-module', '-module-name', 'Orion',
             fixtures / 'OrionDescriptorShim.swift', '-emit-module-path', temp / 'Orion.swiftmodule',
             '-o', temp / 'libOrion.dylib'])
        backend = temp / 'BackendTests'
        run(['xcrun', 'swiftc', '-parse-as-library', '-I', temp, '-L', temp, '-lOrion',
             '-import-objc-header', support / 'SthenoMethodABI.h',
             ROOT / 'Sources/Stheno/SthenoValidatedBackend.swift', fixtures / 'BackendTests.swift',
             c_object, objc_object, '-Xlinker', '-rpath', '-Xlinker', temp, '-o', backend])
        run([backend], marker='PRODUCTION_BACKEND_PASS')

        sdk = run(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path']).strip()
        runtimes = json.loads(run(['xcrun', 'simctl', 'list', 'runtimes', '--json']))['runtimes']
        usable = [r for r in runtimes if r.get('isAvailable') and r.get('platform') == 'iOS'
                  and r['version'].startswith('17.')]
        # Some simctl versions omit the platform field; use the actual identifier.
        if not usable:
            usable = [r for r in runtimes if r.get('isAvailable')
                      and '.iOS-' in r['identifier'] and r['version'].startswith('17.')]
        if not usable:
            raise RuntimeError('No supported iOS 17 simulator runtime installed; no silent skip/download')
        runtime = max(usable, key=lambda r: tuple(map(int, r['version'].split('.'))))
        devices = json.loads(run(['xcrun', 'simctl', 'list', 'devicetypes', '--json']))['devicetypes']
        device_type = next(d['identifier'] for d in devices if d['name'] == 'iPhone 15')
        udid = run(['xcrun', 'simctl', 'create', 'Stheno startup safety smoke', device_type, runtime['identifier']]).strip()
        try:
            run(['xcrun', 'simctl', 'boot', udid])
            run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], timeout=240)
            app = temp / 'OverlaySmoke.app'
            app.mkdir()
            manifest = {
                'CFBundleIdentifier': 'dev.stheno.startup.smoke', 'CFBundleName': 'OverlaySmoke',
                'CFBundleExecutable': 'OverlaySmoke', 'CFBundlePackageType': 'APPL',
                'CFBundleVersion': '1', 'CFBundleShortVersionString': '1', 'MinimumOSVersion': '15.0',
                'LSRequiresIPhoneOS': True, 'UILaunchScreen': {},
                'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False,
                    'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [{
                        'UISceneConfigurationName': 'Smoke',
                        'UISceneDelegateClassName': 'OverlaySmoke.SmokeSceneDelegate'}]}},
            }
            (app / 'Info.plist').write_bytes(plistlib.dumps(manifest))
            arch = run(['uname', '-m']).strip()
            run(['xcrun', 'swiftc', '-parse-as-library', '-module-name', 'OverlaySmoke', '-sdk', sdk,
                 '-target', f'{arch}-apple-ios15.0-simulator',
                 ROOT / 'Sources/Stheno/UI/OverlayWindow.swift', fixtures / 'BaselineSthenoWindow.swift',
                 fixtures / 'OverlaySmoke.swift', '-o', app / 'OverlaySmoke'])
            run(['codesign', '--force', '--sign', '-', app])
            run(['xcrun', 'simctl', 'install', udid, app])
            run(['xcrun', 'simctl', 'launch', '--console', udid, 'dev.stheno.startup.smoke'],
                marker='OVERLAY_SMOKE_ALL_PASS', timeout=180)
            print('APPLE_STARTUP_ALL_PASS runtime=' + runtime['identifier'] +
                  ' evidence=production-seams-not-iOS15-SpringBoard', flush=True)
        finally:
            run(['xcrun', 'simctl', 'shutdown', udid])
            run(['xcrun', 'simctl', 'delete', udid])


if __name__ == '__main__':
    main()
