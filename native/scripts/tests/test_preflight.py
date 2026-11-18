import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import preflight  # noqa: E402

UI = "native/Anycast/Sources/UI/Screens/Foo.swift"


def diff(path, *added, start=10):
    body = "".join("+%s\n" % line for line in added)
    return ("diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -9,0 +%d,%d @@\n%s"
            % (path, path, path, path, start, len(added), body))


def run(path, *added):
    return preflight.check_added(preflight.parse_diff(diff(path, *added)))


class DiffRules(unittest.TestCase):
    def test_parse_diff_line_numbers(self):
        added = preflight.parse_diff(diff(UI, "a", "b", start=20))
        self.assertEqual(added[UI], [(20, "a"), (21, "b")])

    def test_deleted_file_is_ignored(self):
        text = "--- a/x.swift\n+++ /dev/null\n@@ -1,1 +0,0 @@\n-UIActivityIndicatorView()\n"
        self.assertEqual(preflight.parse_diff(text), {})

    def test_activity_indicator(self):
        out = run(UI, "let s = UIActivityIndicatorView(style: .large)")
        self.assertEqual(len(out), 1)
        self.assertIn(UI + ":10", out[0])
        self.assertIn("LoadingDelay", out[0])

    def test_system_symbol_outside_app_icons(self):
        self.assertEqual(len(run(UI, 'UIImage(systemName: "play.fill")')), 1)

    def test_system_symbol_allowed_in_app_icons(self):
        path = "native/Anycast/Sources/DesignSystem/AppIcons.swift"
        self.assertEqual(run(path, 'UIImage(systemName: "play.fill")'), [])

    def test_hard_coded_colours(self):
        for line in ("UIColor(red: 1, green: 0, blue: 0, alpha: 1)", "UIColor(white: 0.5, alpha: 1)",
                     "UIColor(hue: 0.1, saturation: 1, brightness: 1, alpha: 1)",
                     "let c = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 1)", "view.tintColor = .systemRed",
                     "x = .systemGreen"):
            self.assertEqual(len(run(UI, line)), 1, line)

    def test_colours_allowed_in_design_system(self):
        self.assertEqual(run("native/Anycast/Sources/DesignSystem/Theme.swift", "UIColor(white: 0.5, alpha: 1)"), [])

    def test_theme_roles_and_label_colours_pass(self):
        self.assertEqual(run(UI, "view.backgroundColor = theme.surface", "x = .label", "y = .systemBackground"), [])

    def test_allow_comment(self):
        self.assertEqual(run(UI, "UIColor(red: 1, green: 0, blue: 0, alpha: 1) // preflight:allow brand mark"), [])

    def test_comment_only_mention_passes(self):
        self.assertEqual(run(UI, "// replaces UIActivityIndicatorView"), [])

    def test_grdb_in_app_target(self):
        self.assertEqual(len(run(UI, "import GRDB")), 1)
        self.assertEqual(run("native/AnycastKit/Sources/Db.swift", "import GRDB"), [])

    def test_kit_app_sdk(self):
        self.assertEqual(len(run("native/AnycastKit/Sources/X.swift", "import Kingfisher")), 1)

    def test_timer_in_startup_file(self):
        path = "native/Anycast/Sources/App/AppDelegate.swift"
        line = "Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in }"
        self.assertEqual(len(run(path, line)), 1)
        self.assertEqual(run(UI, line), [])

    def test_non_swift_and_other_trees_ignored(self):
        self.assertEqual(run("native/README.md", "UIActivityIndicatorView"), [])
        self.assertEqual(run("native/AnycastTests/T.swift", "UIColor(white: 0, alpha: 1)"), [])


PROJECT = """targets:
  Anycast:
    type: application
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1,2"
  ShareExtension:
    type: app-extension
    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1,2"
  AnycastTests:
    type: bundle.unit-test
"""

NO_EXT_FAMILY = PROJECT.replace('''    settings:
      base:
        TARGETED_DEVICE_FAMILY: "1,2"
  AnycastTests:''', "  AnycastTests:")


class RepoChecks(unittest.TestCase):
    def test_device_family_ok(self):
        self.assertEqual(preflight.check_device_family(PROJECT), [])

    def test_device_family_missing_ipad(self):
        out = preflight.check_device_family(PROJECT.replace('"1,2"', '"1"', 1))
        self.assertEqual(len(out), 1)
        self.assertIn("target Anycast", out[0])

    def test_device_family_absent_for_extension(self):
        out = preflight.check_device_family(NO_EXT_FAMILY)
        self.assertEqual(len(out), 1)
        self.assertIn("target ShareExtension", out[0])

    def test_appex_match(self):
        self.assertEqual(preflight.check_appex('p="$APP/PlugIns/ShareExtension.appex"\n', PROJECT), [])

    def test_appex_mismatch(self):
        out = preflight.check_appex('a\np="$APP/PlugIns/ShareExt.appex"\n', PROJECT)
        self.assertEqual(len(out), 1)
        self.assertIn(":2", out[0])

    def test_appex_follows_product_name(self):
        project = PROJECT.replace("    type: app-extension\n",
                                  "    type: app-extension\n    settings:\n      base:\n        PRODUCT_NAME: Share\n", 1)
        self.assertEqual(preflight.check_appex("x/PlugIns/Share.appex", project), [])

    def test_appex_missing_check(self):
        self.assertEqual(len(preflight.check_appex("nothing", PROJECT)), 1)

    def test_duplicate_icons(self):
        text = '    static let a = symbol("x")\n    static let b = symbol("y")\n    static let a = symbol("z")\n'
        out = preflight.check_duplicate_icons(text)
        self.assertEqual(len(out), 1)
        self.assertIn(":3", out[0])

    def test_unique_icons(self):
        self.assertEqual(preflight.check_duplicate_icons("static let a = 1\nstatic let b = 2\n"), [])


if __name__ == "__main__":
    unittest.main()
