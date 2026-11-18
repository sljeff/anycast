#!/usr/bin/env python3
"""Fast preflight for native/ (no Xcode, python3 stdlib only).

  native/scripts/preflight.py                 # all checks vs merge-base with origin/main
  native/scripts/preflight.py --repo-only     # only the whole-repo release checks
  native/scripts/preflight.py --base <ref>    # diff against another ref

A. Diff rules: only lines ADDED relative to the merge base are inspected, so
   there is no baseline to maintain. Allow one line with a trailing
   "// preflight:allow <reason>" comment.
B. Whole-repo release checks: iPad stays declared, the .appex path release-core
   verifies matches project.yml, AppIcons has no duplicate names.

Exit 1 on any finding. Tests: python3 -m unittest discover -s native/scripts/tests
"""

import argparse
import os
import re
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

APP = "native/Anycast/Sources/"
KIT = "native/AnycastKit/Sources/"
DESIGN_SYSTEM = APP + "DesignSystem/"
APP_ICONS = DESIGN_SYSTEM + "AppIcons.swift"
PROJECT_YML = "native/project.yml"
RELEASE_WORKFLOW = ".github/workflows/release-core.yml"

PRE_SETTINGS_FILES = tuple(
    APP + "App/" + name
    for name in ("AppDelegate.swift", "SceneDelegate.swift", "AppEnvironment.swift", "StartupSequence.swift")
)

SYSTEM_COLORS = "Red|Green|Blue|Orange|Yellow|Pink|Purple|Teal|Indigo|Mint|Cyan|Brown"
COLOR_PATTERN = (
    r"\bUIColor\s*\(\s*(?:red|white|hue)\s*:|#colorLiteral\b|\.system(?:%s)\b" % SYSTEM_COLORS
)
TIMER_PATTERN = (
    r"\bTimer\.scheduledTimer\b|\bTimer\s*\(\s*(?:timeInterval|fire)\b"
    r"|\bDispatchSource\.makeTimerSource\b|\bCADisplayLink\s*\("
)


class Rule(object):
    def __init__(self, name, pattern, advice, include, exclude=()):
        self.name = name
        self.regex = re.compile(pattern)
        self.advice = advice
        self.include = tuple(include)
        self.exclude = tuple(exclude)

    def applies_to(self, path):
        if not any(path.startswith(p) for p in self.include):
            return False
        return not any(path.startswith(p) for p in self.exclude)


RULES = [
    Rule("new UIActivityIndicatorView", r"\bUIActivityIndicatorView\b",
         "use the shared skeleton / LoadingDelay instead", [APP]),
    Rule("new UIImage(systemName:)", r"\bUIImage\s*\(\s*systemName\s*:",
         "use AppIcons instead", [APP], [APP_ICONS]),
    Rule("new hard-coded colour", COLOR_PATTERN,
         "use a Theme role instead", [APP], [DESIGN_SYSTEM]),
    Rule("SQLite/GRDB in the app target", r"^\s*(?:@\w+\s+)*import\s+GRDB\b|\bDatabaseQueue\b|\bDatabasePool\b",
         "use an AnycastKit repository instead", [APP]),
    Rule("app-only SDK imported in AnycastKit",
         r"^\s*(?:@\w+\s+)*import\s+(?:Kingfisher|Firebase\w*|Sentry|RevenueCat|Lottie|GoogleSignIn|ChatLayout|MarqueeLabel)\b",
         "keep the kit data/network/logic only; import it in the app target instead", [KIT]),
    Rule("timer in a pre-settings startup file", TIMER_PATTERN,
         "create timers after StartupSequence.onReady instead", PRE_SETTINGS_FILES),
]

ALLOW = re.compile(r"//\s*preflight:allow\b")


def strip_comment(line):
    """Drops a trailing // comment (naive: a // inside a string also cuts)."""
    index = line.find("//")
    return line if index < 0 else line[:index]


def parse_diff(diff_text):
    """Returns {path: [(line_number, text)]} for added lines of a -U0 diff."""
    added = {}
    path = None
    number = 0
    for raw in diff_text.splitlines():
        if raw.startswith("+++ "):
            target = raw[4:].strip()
            path = target[2:] if target.startswith("b/") else None
        elif raw.startswith("@@"):
            match = re.match(r"@@ -\S+ \+(\d+)", raw)
            number = int(match.group(1)) if match else 0
        elif raw.startswith("+") and path:
            added.setdefault(path, []).append((number, raw[1:]))
            number += 1
    return added


def check_added(added):
    findings = []
    for path in sorted(added):
        if not path.endswith(".swift"):
            continue
        for number, text in added[path]:
            if ALLOW.search(text):
                continue
            code = strip_comment(text)
            for rule in RULES:
                if rule.applies_to(path) and rule.regex.search(code):
                    findings.append("%s:%d — %s — %s (or add // preflight:allow <reason>)"
                                    % (path, number, rule.name, rule.advice))
    return findings


def target_block(project_text, target):
    """The text of one top-level target in project.yml ('' when missing)."""
    match = re.search(r"^  %s:\n((?:(?:    .*)?\n)+)" % re.escape(target), project_text, re.M)
    return match.group(1) if match else ""


def check_device_family(project_text):
    findings = []
    for target in ("Anycast", "ShareExtension"):
        block = target_block(project_text, target)
        if not re.search(r"^\s*TARGETED_DEVICE_FAMILY:\s*[\"']?1,2[\"']?\s*(?:#.*)?$", block, re.M):
            findings.append('%s — target %s must declare TARGETED_DEVICE_FAMILY: "1,2" — keep iPad declared (store upload rejects otherwise)'
                            % (PROJECT_YML, target))
    return findings


def check_appex(release_text, project_text):
    block = target_block(project_text, "ShareExtension")
    match = re.search(r"^\s*PRODUCT_NAME:\s*[\"']?([^\"'\s#]+)", block, re.M)
    product = match.group(1) if match else "ShareExtension"
    findings = []
    names = set()
    for number, line in enumerate(release_text.splitlines(), 1):
        for name in re.findall(r"PlugIns/([^/\"'\s]+)\.appex", line):
            names.add(name)
            if name != product:
                findings.append("%s:%d — checks %s.appex but project.yml builds %s.appex — use %s.appex instead"
                                % (RELEASE_WORKFLOW, number, name, product, product))
    if not names:
        findings.append("%s — no PlugIns/<name>.appex check found — keep verifying %s.appex" % (RELEASE_WORKFLOW, product))
    return findings


def check_duplicate_icons(icons_text):
    seen = {}
    findings = []
    for number, line in enumerate(icons_text.splitlines(), 1):
        match = re.match(r"\s*(?:\w+\s+)*static\s+(?:let|var)\s+(\w+)\b", strip_comment(line))
        if not match:
            continue
        name = match.group(1)
        if name in seen:
            findings.append("%s:%d — duplicate static %s (first at line %d) — use a distinct name instead"
                            % (APP_ICONS, number, name, seen[name]))
        else:
            seen[name] = number
    return findings


def read(path):
    with open(os.path.join(REPO, path), encoding="utf-8") as handle:
        return handle.read()


def repo_checks():
    project = read(PROJECT_YML)
    return (check_device_family(project)
            + check_appex(read(RELEASE_WORKFLOW), project)
            + check_duplicate_icons(read(APP_ICONS)))


def git(*args):
    return subprocess.run(("git", "-C", REPO) + args, check=True, capture_output=True, text=True).stdout


def diff_checks(base_ref):
    try:
        base = git("merge-base", base_ref, "HEAD").strip()
    except subprocess.CalledProcessError:
        return ["preflight — cannot find merge base with %s — fetch it (git fetch origin main) or pass --base" % base_ref]
    # Merge base vs working tree: includes uncommitted edits, equals HEAD in CI.
    added = parse_diff(git("diff", "-U0", "--no-color", base, "--", "native"))
    # Untracked files (local runs before git add) count as entirely added.
    for path in git("ls-files", "--others", "--exclude-standard", "--", "native").split("\n"):
        if path.endswith(".swift"):
            added[path] = list(enumerate(read(path).splitlines(), 1))
    return check_added(added)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--base", default="origin/main", help="ref to take the merge base with (default origin/main)")
    parser.add_argument("--repo-only", action="store_true", help="skip the diff rules")
    args = parser.parse_args(argv)
    findings = repo_checks()
    if not args.repo_only:
        findings += diff_checks(args.base)
    for line in findings:
        print(line)
    if findings:
        print("preflight: %d finding(s)" % len(findings))
        return 1
    print("preflight: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
