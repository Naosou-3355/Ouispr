#!/usr/bin/env python3
"""apply-beta-variant.py: turn this checkout into "Ouispr Beta", the trial app.

The Beta is the same code installed NEXT TO the everyday Ouispr instead of over it,
so a redesign can be tried on the iPhone without touching the app that works or the
dictations it holds. This script rewrites, in the working tree only:

  - the bundle identifiers   com.pivi.dictus[.x]          -> com.pivi.ouisprbeta[.x]
  - the App Group            group.solutions.pivi.dictus  -> group.solutions.pivi.ouisprbeta
  - the URL scheme           ouispr                       -> ouisprbeta
  - the name under the icon  Ouispr                       -> Ouispr Beta
  - the icon                 AppIcon                      -> AppIconBeta

The app reads which one it is from its bundle identifier (OuisprVariant.swift), and
the values here must stay the ones written there.

NEVER COMMIT WHAT THIS SCRIPT CHANGES. It is for a throwaway checkout (the "Unsigned
IPA" workflow) or for a build that restores the files afterwards.

Usage: scripts/apply-beta-variant.py [--check]
  --check  change nothing, only say whether every expected value was found
"""
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = ["OuisprApp", "OuisprKeyboard", "OuisprShare", "OuisprWidgets"]
SHIPPED = ["OuisprApp", "OuisprKeyboard"]

STANDARD_BUNDLE = "com.pivi.dictus"
BETA_BUNDLE = "com.pivi.ouisprbeta"
STANDARD_GROUP = "group.solutions.pivi.dictus"
BETA_GROUP = "group.solutions.pivi.ouisprbeta"
STANDARD_SCHEME = "ouispr"
BETA_SCHEME = "ouisprbeta"
STANDARD_NAME = "Ouispr"
BETA_NAME = "Ouispr Beta"


def fail(message):
    sys.exit(f"apply-beta-variant: {message}")


def project(text):
    """Bundle identifiers and icon name in project.pbxproj."""
    pattern = re.compile(
        r"PRODUCT_BUNDLE_IDENTIFIER = " + re.escape(STANDARD_BUNDLE) + r"(\.[a-z]+)?;"
    )
    text, identifiers = pattern.subn(
        lambda match: f"PRODUCT_BUNDLE_IDENTIFIER = {BETA_BUNDLE}{match.group(1) or ''};", text
    )
    # Two configurations (Debug, Release) for each of the four targets.
    if identifiers != 2 * len(TARGETS):
        fail(f"expected {2 * len(TARGETS)} bundle identifiers in the project, found {identifiers}")
    text, icons = re.subn(
        r"ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;",
        "ASSETCATALOG_COMPILER_APPICON_NAME = AppIconBeta;",
        text,
    )
    if icons != 2:
        fail(f"expected 2 app icon settings in the project, found {icons}")
    return text


def entitlements(data, name):
    groups = data.get("com.apple.security.application-groups")
    if groups != [STANDARD_GROUP]:
        fail(f"{name}: expected the App Group [{STANDARD_GROUP}], found {groups}")
    data["com.apple.security.application-groups"] = [BETA_GROUP]
    return data


def info(data, name):
    # Only the two bundles the Beta ships show a name: under the icon and in the
    # keyboard list. The share sheet and the widgets are left out of the Beta.
    if name in SHIPPED:
        if data.get("CFBundleDisplayName") != STANDARD_NAME:
            fail(f"{name}: expected the display name {STANDARD_NAME}, found {data.get('CFBundleDisplayName')}")
        data["CFBundleDisplayName"] = BETA_NAME
    if name == "OuisprApp":
        url_types = data.get("CFBundleURLTypes") or []
        if len(url_types) != 1 or url_types[0].get("CFBundleURLSchemes") != [STANDARD_SCHEME]:
            fail(f"{name}: expected the single URL scheme {STANDARD_SCHEME}")
        url_types[0]["CFBundleURLSchemes"] = [BETA_SCHEME]
        url_types[0]["CFBundleURLName"] = BETA_BUNDLE
    elif "CFBundleURLTypes" in data:
        fail(f"{name}: an extension registers a URL scheme, which this script does not rename")
    return data


def main():
    check_only = sys.argv[1:] == ["--check"]
    if sys.argv[1:] and not check_only:
        fail("unknown argument. Usage: scripts/apply-beta-variant.py [--check]")

    if not (ROOT / "OuisprApp/Assets.xcassets/AppIconBeta.appiconset/Contents.json").is_file():
        fail("the Beta icon (AppIconBeta.appiconset) is missing")

    writes = []
    project_path = ROOT / "Ouispr.xcodeproj/project.pbxproj"
    writes.append((project_path, project(project_path.read_text(encoding="utf-8")).encode("utf-8")))
    for target in TARGETS:
        for relative, transform in (
            (f"{target}/{target}.entitlements", entitlements),
            (f"{target}/Info.plist", info),
        ):
            path = ROOT / relative
            with path.open("rb") as handle:
                data = plistlib.load(handle)
            writes.append((path, plistlib.dumps(transform(data, target), fmt=plistlib.FMT_XML)))

    # Every file was read and checked before the first one is written, so a failed
    # check leaves the checkout exactly as it was.
    if check_only:
        print(f"apply-beta-variant: {len(writes)} files would change, every expected value found")
        return
    for path, content in writes:
        path.write_bytes(content)
    print(f"apply-beta-variant: this checkout now builds {BETA_NAME} ({BETA_BUNDLE}, {BETA_GROUP})")


if __name__ == "__main__":
    main()
