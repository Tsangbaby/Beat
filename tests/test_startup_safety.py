"""Source contracts for the rejected phase-one startup path; NOT handset proof."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(path):
    return (ROOT / path).read_text()


class StartupABIContracts(unittest.TestCase):
    def test_launch_argument_is_opaque_not_a_notification_bridge(self):
        source = read('Sources/Stheno/Hooks/SpringBoard.x.swift')
        self.assertIn('func applicationDidFinishLaunching(_ application: AnyObject?)', source)
        self.assertIn('orig.applicationDidFinishLaunching(application)', source)
        self.assertNotIn('_ notification: Notification', source)

    def test_scene_update_void_and_scene_creation_returns_original_object(self):
        scene = read('Sources/Stheno/Hooks/Scene.x.swift')
        update = re.search(r'func _scene\([^\{]+\{', scene).group()
        self.assertNotIn('-> AnyObject?', update, 'void system callback must not return a retained object')
        create = re.search(r'func _createSceneWithDefinition\([^\{]+\{', scene).group()
        self.assertIn('-> AnyObject?', create, 'system caller requires the created scene return value')
        self.assertIn('return orig._createSceneWithDefinition(definition,', scene)

    def test_banner_options_and_icon_launch_preserve_scalar_void_abi(self):
        scene = read('Sources/Stheno/Hooks/Scene.x.swift')
        self.assertIn('withOptions options: UInt', scene)
        springboard = read('Sources/Stheno/Hooks/SpringBoard.x.swift')
        icon = re.search(r'func iconManager\([^\{]+\{', springboard).group()
        self.assertNotIn('-> Bool', icon)
        self.assertNotIn('return true', springboard[springboard.index('class SBIconControllerHook:'):])

    def test_icon_launch_fails_open_until_a_real_host_already_exists(self):
        source = read('Sources/Stheno/Hooks/SpringBoard.x.swift')
        icon = source[source.index('class SBIconControllerHook:'):]
        self.assertIn('host.scene != nil, !host.views.isEmpty', icon,
                      'showRing defaults true but reconstructed Scene creation is not implemented')
        self.assertIn('return orig.iconManager(manager, launchIconFor: iconView, withActions: actions)', icon)

    def test_unknown_system_callbacks_remain_nullable_opaque_and_uninvoked(self):
        scene = read('Sources/Stheno/Hooks/Scene.x.swift')
        self.assertIn('completion: AnyObject?', scene)
        self.assertIn('withResult result: AnyObject?', scene)
        self.assertIn('source: AnyObject?', scene)
        self.assertIn('originalSource: AnyObject?', scene)
        self.assertNotIn('completion?(false)', scene)
        self.assertNotIn('@convention(block)', scene,
                         'outer @? encoding does not establish the unknown block invoke ABI')


class HookAdmissionContracts(unittest.TestCase):
    def test_orion_uses_a_per_descriptor_abi_gate_and_recoverable_handler(self):
        entry = read('Sources/Stheno/Tweak.x.swift')
        self.assertIn('TweakWithBackend', entry, 'unconditional Substrate admission is unsafe')
        self.assertIn('SthenoValidatedBackend', entry)
        self.assertIn('static func handleError(_ error: OrionHookError)', entry)
        backend = ROOT / 'Sources/Stheno/SthenoValidatedBackend.swift'
        self.assertTrue(backend.exists(), 'no replacement/runtime ABI comparison before installing')
        source = backend.read_text()
        self.assertLess(source.index('SthenoMethodsHaveSameABI('), source.index('upstream.apply('))
        self.assertIn('completion(.failure(', source)
        self.assertNotIn('handleErrorDefault', entry)

    def test_native_modules_gate_installation_and_do_not_call_missing_imps(self):
        keyboard = read('Sources/SthenoKeyboard/SthenoKeyboard.xm')
        self.assertIn('static CGRect (*orig_boundsForInterfaceOrientation)', keyboard)
        self.assertIn('static CGRect hook_boundsForInterfaceOrientation', keyboard)
        self.assertIn('SthenoMethodMatchesTypes', keyboard)
        self.assertIn('if (orig_remoteKeyboardWindowForScreen == NULL) return;', keyboard)
        camera = read('Sources/SthenoCamera/SthenoCamera.xm')
        self.assertIn('SEL _cmd, void *condition, id newValue', camera)
        self.assertIn('SthenoMethodMatchesTypes', camera)


class OverlayStartupContracts(unittest.TestCase):
    def test_idle_bootstrap_does_not_publish_a_fullscreen_window(self):
        source = read('Sources/Stheno/SthenoController.swift')
        self.assertNotIn('window.isHidden = false', source,
                         'bootstrap must not put an unconditional full-screen overlay above SpringBoard')
        self.assertIn('SthenoOverlayPresenter<Container>', source)
        self.assertIn('UIScene.didActivateNotification', source)
        self.assertIn('deviceInfo.$state', source)
        presenter = ROOT / 'Sources/Stheno/UI/OverlayWindow.swift'
        self.assertTrue(presenter.is_file())
        content = presenter.read_text()
        self.assertIn('guard presented, let scene = sceneProvider()', content)
        self.assertIn('hosting.view.backgroundColor = .clear', content)
        self.assertIn('hosting.view.isOpaque = false', content)
        self.assertIn('inputRegions.contains(where:', content)
        self.assertNotIn('makeKeyAndVisible', content)


class BuildEvidenceContracts(unittest.TestCase):
    def test_cloud_runs_apple_execution_before_packaging_on_the_fix_branch(self):
        workflow = read('.github/workflows/build-roothide.yml')
        self.assertIn('fix/ios15-startup-safety', workflow)
        self.assertIn('python3 scripts/run-apple-startup-tests.py', workflow)
        self.assertLess(workflow.index('python3 scripts/run-apple-startup-tests.py'),
                        workflow.index('make package'))

    def test_baseline_window_and_licensing_state_are_immutable(self):
        import hashlib
        source = read('tests/apple/BaselineSthenoWindow.swift')
        body = source[source.index('public final class BaselineSthenoWindow:'):].strip()
        body = body.replace('class BaselineSthenoWindow:', 'class SthenoWindow:', 1)
        self.assertEqual(hashlib.sha256(body.encode()).hexdigest(),
                         '12db774883c49d82947f35dbec00acaec9e8e7aaea03a9eb6e2eeae3e337512c')
        self.assertEqual(hashlib.sha256(read('Sources/Stheno/State/State.swift').encode()).hexdigest(),
                         '81c53bd85998633a9ca517c88b697dc041e20cf3620a6264fef2275229916688')

    def test_all_original_swift_hook_classes_remain_in_the_validated_backend(self):
        classes = set()
        for path in (ROOT / 'Sources/Stheno/Hooks').glob('*.x.swift'):
            classes.update(re.findall(r'class (\w+): ClassHook<', path.read_text()))
        entry = read('Sources/Stheno/Tweak.x.swift')
        registered = re.findall(r'"[^"]+": (\w+)\.self', entry)
        self.assertEqual(set(registered), classes)
        self.assertEqual(len(registered), 16)


if __name__ == '__main__':
    unittest.main()
