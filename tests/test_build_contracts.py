"""Phase-one regression gates. Source/frontend gates are not device tests."""
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


def read(relative):
    return (ROOT / relative).read_text(encoding="utf-8")


class CameraARC(unittest.TestCase):
    def test_exact_camera_hook_compiles_with_arc(self):
        source = read("Sources/SthenoCamera/SthenoCamera.xm")
        body = re.search(
            r"static void hook_updateClientStateCondition\([^\n]+\) \{.*?^\}",
            source, re.M | re.S,
        )
        self.assertIsNotNone(body)
        clang = shutil.which("clang")
        if not clang:
            self.skipTest("clang unavailable; Apple-target CI remains required")
        fixture = """typedef signed char BOOL;
__attribute__((objc_root_class)) @interface ARCProbe
- (id)retain;
- (oneway void)release;
@end
static BOOL gCameraKeepAlive;
static void SthenoReloadCameraPreference(void);
static void (*orig_updateClientStateCondition)(id, SEL, void *, id);
""" + body.group(0)
        result = subprocess.run(
            [clang, "-x", "objective-c++", "-fobjc-runtime=ios-15.0",
             "-fobjc-arc", "-fsyntax-only", "-"],
            input=fixture, text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("SthenoReloadCameraPreference();", body.group(0))
        self.assertIn("if (!gCameraKeepAlive)", body.group(0))
        self.assertIn("orig_updateClientStateCondition(self, _cmd, condition, retainedValue);", body.group(0))


class NativePathBridge(unittest.TestCase):
    def test_all_targets_use_the_same_typed_root_path_bridge(self):
        header = ROOT / "Sources/Support/SthenoPaths.h"
        self.assertTrue(header.is_file(), "missing typed Objective-C/C path bridge")
        self.assertIn('extern "C"', header.read_text())
        self.assertIn("SthenoJBRootPath", header.read_text())
        implementation = read("Sources/Support/SthenoPaths.mm")
        self.assertIn("#include <roothide.h>", implementation)
        self.assertIn("return jbroot(path);", implementation)
        for path in ["Sources/Stheno/Global.swift",
                     "Sources/SthenoCamera/SthenoCamera.xm",
                     "Sources/SthenoKeyboard/SthenoKeyboard.xm"]:
            source = read(path)
            self.assertIn("SthenoJBRootPath", source, path)
            self.assertNotIn('extern NSString *jbroot', source, path)
            self.assertNotIn('@_silgen_name("_Z6jbrootP8NSString")', source, path)
        makefile = read("Makefile")
        for name in ["Stheno", "SthenoCamera", "SthenoKeyboard"]:
            declaration = re.search(r"^" + name + r"_FILES\s*=([^\n]+)", makefile, re.M)
            self.assertIsNotNone(declaration)
            self.assertIn("Sources/Support/SthenoPaths.mm", declaration.group(1))
        self.assertIn("SthenoPaths.h", read("Stheno-Bridging-Header.h"))


class OrionCompileGraph(unittest.TestCase):
    def test_hooks_have_real_declarations_and_preprocessed_bootstrap(self):
        sources = list((ROOT / "Sources/Stheno").rglob("*.swift"))
        hook_sources = [p for p in sources if p.parent.name == "Hooks" and "ClassHook<" in p.read_text()]
        self.assertEqual(len(hook_sources), 3)
        for path in hook_sources:
            self.assertTrue(path.name.endswith(".x.swift"), path.name)
        self.assertNotIn("public class SpringBoard", read("Sources/Stheno/PrivateSDK.swift"))
        self.assertIn("@interface SpringBoard : UIApplication", read("Sources/Support/SthenoPrivateSDK.h"))
        tweak = read("Sources/Stheno/Tweak.x.swift")
        self.assertIn("SthenoGroup().activate()", tweak)
        self.assertIn("struct SthenoEntry: Tweak", tweak)
        self.assertNotIn("class SthenoController: Tweak", read("Sources/Stheno/SthenoController.swift"))
        switcher = read("Sources/Stheno/Hooks/Switcher.x.swift")
        self.assertNotIn("gesture.translation(", switcher)
        self.assertNotIn("var _handleClick: Bool", switcher)
        self.assertNotIn("import FrontBoard", read("Sources/Stheno/Hooks/Scene.x.swift"))


class RingDisplayContract(unittest.TestCase):
    def test_authorized_ring_rebuild_is_visible_and_not_a_uiview_body(self):
        ui = read("Sources/Stheno/UI/UI.swift")
        ring = ui[ui.index("public struct RingView: View"):ui.index("public struct TrashAppView: View")]
        self.assertNotIn("container.addSubview(view)", ring)
        self.assertNotIn("func updateUIView", ring)
        self.assertNotIn("EmptyView", ring)
        self.assertIn("@ObservedObject var ringState", ring)
        self.assertIn("TabIcon(", ring)
        self.assertIn("ForEach(", ring)
        self.assertIn("cos(", ring)
        self.assertIn("sin(", ring)
        self.assertIn("not an original", ring)
        self.assertNotRegex(ui, r"@Environment\(")
        self.assertIn("@StateObject private var ringState", ui)


class IOKitABI(unittest.TestCase):
    def test_state_uses_imported_c_abi(self):
        self.assertIn("<IOKit/IOKitLib.h>", read("Stheno-Bridging-Header.h"))
        self.assertNotIn('@_silgen_name("IOServiceMatching")', read("Sources/Stheno/State/State.swift"))


class CloudSwiftRegressions(unittest.TestCase):
    def test_state_imports_match_observed_apple_compiler_contracts(self):
        state = read("Sources/Stheno/State/State.swift")
        self.assertIn("self.snapshots[bundleID] = Snapshot", state)
        self.assertIn("SignedStamp.cachedValueStorage = SignedStamp.deviceCode()", state)
        self.assertIn('IOServiceMatching("IOPlatformExpertDevice")?.takeUnretainedValue()', state)


class OrionBlockABI(unittest.TestCase):
    def test_unknown_hook_callbacks_are_opaque_object_pointers(self):
        scene = read("Sources/Stheno/Hooks/Scene.x.swift")
        self.assertIn("completion: AnyObject?", scene)
        self.assertIn("withResult result: AnyObject?", scene)
        self.assertNotIn("@convention(block)", scene)
        self.assertNotIn("completion?(", scene)


if __name__ == "__main__":
    unittest.main()
