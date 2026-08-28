#!/usr/bin/env python3
"""Static checks so OverlayTweak sources stay compilable without an iOS SDK."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(name: str) -> str:
    return (ROOT / name).read_text(encoding="utf-8")


def properties_in(src: str) -> set[str]:
    names: set[str] = set()
    for m in re.finditer(r"@property\s*\([^)]*\)\s*[^;]*\b(\w+)\s*;", src):
        names.add(m.group(1))
    return names


def methods_in_header(src: str) -> set[str]:
    names: set[str] = set()
    for m in re.finditer(r"^[\+\-]\s*\([^)]+\)\s*([^;\s]+)", src, re.M):
        sel = m.group(1)
        # first selector piece, e.g. setCustomSize:
        names.add(sel.split(":")[0])
    return names


def main() -> int:
    settings = read("SettingsViewController.m")
    mgr_h = read("OverlayManager.h")
    mgr_m = read("OverlayManager.m")
    view_h = read("OverlayView.h")
    view_m = read("OverlayView.m")
    common = read("OverlayCommon.h")

    # Settings properties used via self.foo must be declared.
    iface = re.search(r"@interface SettingsViewController \(\)(.*?)@end", settings, re.S)
    if not iface:
        errors.append("SettingsViewController private @interface missing")
        declared: set[str] = set()
    else:
        declared = properties_in(iface.group(1))

    used = set(re.findall(r"\bself\.([A-Za-z_]\w*)", settings))
    ignore = {
        "view", "contentView", "scrollView", "blurView", "uiBuilt",
        "titleLabel", "layer", "presentedViewController",
    }
    for name in sorted(used - declared - ignore):
        # methods like self.ratioStringForSize aren't properties; skip if followed by (
        if re.search(rf"\bself\.{name}\s*\(", settings):
            continue
        errors.append(f"SettingsViewController: undeclared property self.{name}")

    # OverlayManager API used from Settings must exist on the public header.
    public = methods_in_header(mgr_h) | properties_in(mgr_h)
    public |= {"sharedManager", "overlayWindow"}
    for m in re.finditer(r"\[(?:mgr|\[OverlayManager sharedManager\])\s+([A-Za-z_]\w*)", settings):
        sel = m.group(1)
        if sel not in public:
            errors.append(f"Settings calls OverlayManager {sel} which is not in OverlayManager.h")

    # OLLog must be defined wherever used.
    if "OLLog" in settings and "OverlayCommon.h" not in settings:
        errors.append("Settings uses OLLog but does not import OverlayCommon.h")
    if "#define OLLog" not in common:
        errors.append("OLLog macro missing from OverlayCommon.h")

    # Corrupted fragments that previously broke the build.
    if "pinchGestureeRecognizer" in mgr_m:
        errors.append("OverlayManager.m contains corrupted pinchGestureeRecognizer fragment")
    if mgr_m.count("\n@end\n") < 3:
        errors.append("OverlayManager.m is missing expected @end markers")
    # File must end with @end
    if not mgr_m.rstrip().endswith("@end"):
        errors.append("OverlayManager.m does not end with @end")

    # OverlayView grid API
    if "showsGrid" not in view_h:
        errors.append("OverlayView.h missing showsGrid")
    if "CAShapeLayer" in view_m and "<QuartzCore/QuartzCore.h>" not in view_m:
        errors.append("OverlayView.m uses CAShapeLayer without QuartzCore")

    # Brace balance (rough)
    for name, src in (
        ("OverlayManager.m", mgr_m),
        ("SettingsViewController.m", settings),
        ("OverlayView.m", view_m),
        ("OverlayEntry.m", read("OverlayEntry.m")),
    ):
        if src.count("{") != src.count("}"):
            errors.append(f"{name}: brace mismatch {{ {src.count('{')} }} {src.count('}')}")

    if errors:
        print("FAIL")
        for e in errors:
            print(" -", e)
        return 1
    print("OK: sources look consistent")
    print(f"  Settings properties: {len(declared)}")
    print(f"  OverlayManager public selectors: {len(public)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
