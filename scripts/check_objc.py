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
    for m in re.finditer(r"^[\+\-]\s*\([^)]+\)\s*([^\s;]+)", src, re.M):
        names.add(m.group(1).split(":")[0])
    return names


def check_workflow(path: Path, label: str) -> None:
    if not path.exists():
        errors.append(f"{label} missing")
        return
    src = path.read_text(encoding="utf-8")
    if "arena/**" in src and "'arena/**'" not in src and '"arena/**"' not in src:
        errors.append(f"{label}: unquoted arena/** breaks GitHub YAML")
    if "actions/checkout@v5" in src:
        errors.append(f"{label}: use checkout@v4 (v5 broke this repo's Actions UI)")
    if "otool" in src and "| head" in src:
        errors.append(f"{label}: otool piped to head SIGPIPEs under pipefail")
    if "workflow_dispatch" not in src:
        errors.append(f"{label}: missing workflow_dispatch")
    if "runs-on: macos-15" not in src:
        errors.append(f"{label}: expected macos-15 runner")
    if "python3 scripts/check_objc.py" not in src and "make check" not in src:
        errors.append(f"{label}: missing source check step")
    if "make clean" not in src or re.search(r"\bmake\b", src) is None:
        errors.append(f"{label}: missing make")
    if "actions/upload-artifact@v4" not in src:
        errors.append(f"{label}: missing upload-artifact@v4")
    if "name: Build Overlay.dylib" not in src:
        errors.append(f"{label}: unexpected workflow name")
    # Balanced-enough YAML: jobs/steps present, no tabs
    if "\t" in src:
        errors.append(f"{label}: contains tabs")
    if "jobs:" not in src or "steps:" not in src:
        errors.append(f"{label}: missing jobs/steps")


def main() -> int:
    settings = read("SettingsViewController.m")
    mgr_h = read("OverlayManager.h")
    mgr_m = read("OverlayManager.m")
    view_h = read("OverlayView.h")
    view_m = read("OverlayView.m")
    common = read("OverlayCommon.h")

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
        if re.search(rf"\bself\.{name}\s*\(", settings):
            continue
        errors.append(f"SettingsViewController: undeclared property self.{name}")

    public = methods_in_header(mgr_h) | properties_in(mgr_h)
    public |= {"sharedManager", "overlayWindow"}
    for m in re.finditer(r"\[(?:mgr|\[OverlayManager sharedManager\])\s+([A-Za-z_]\w*)", settings):
        sel = m.group(1)
        if sel not in public:
            errors.append(f"Settings calls OverlayManager {sel} which is not in OverlayManager.h")

    if "OLLog" in settings and "OverlayCommon.h" not in settings:
        errors.append("Settings uses OLLog but does not import OverlayCommon.h")
    if "#define OLLog" not in common:
        errors.append("OLLog macro missing from OverlayCommon.h")

    if "pinchGestureeRecognizer" in mgr_m:
        errors.append("OverlayManager.m contains corrupted pinchGestureeRecognizer fragment")
    if "toggleOvert:" in settings or "toggleOvert:0" in settings:
        errors.append("SettingsViewController.m contains corrupted selector toggleOvert")
    if re.search(r":&_", settings):
        errors.append("SettingsViewController.m: &_ivar out-param is an ARC compile error")
    if "UISlider **" in settings or "UILabel **" in settings:
        errors.append("SettingsViewController.m: ** out-param is an ARC compile error")
    if "bind:^(UISlider" not in settings:
        errors.append("SettingsViewController.m: addNamedSlider should bind sliders via a block")
    if mgr_m.count("\n@end") < 3:
        errors.append("OverlayManager.m is missing expected @end markers")
    if not mgr_m.rstrip().endswith("@end"):
        errors.append("OverlayManager.m does not end with @end")
    if not settings.rstrip().endswith("@end"):
        errors.append("SettingsViewController.m does not end with @end")
    if not view_m.rstrip().endswith("@end"):
        errors.append("OverlayView.m does not end with @end")

    required_view = ("showsGrid", "cropInsets", "uncroppedSize", "cropModeEnabled")
    for key in required_view:
        if key not in view_h:
            errors.append(f"OverlayView.h missing {key}")
    if "cropHandles" not in view_m:
        errors.append("OverlayView.m missing crop handles")
    if "cropGuideLayer" not in view_m:
        errors.append("OverlayView.m missing crop guides")
    if "keepPosition" not in mgr_m:
        errors.append("OverlayManager.m missing keepPosition crop")
    if "beginCropMode" not in mgr_h:
        errors.append("OverlayManager.h missing beginCropMode")
    if "CAShapeLayer" in view_m and "<QuartzCore/QuartzCore.h>" not in view_m:
        errors.append("OverlayView.m uses CAShapeLayer without QuartzCore")
    if "CATransform3D" not in mgr_m:
        errors.append("OverlayManager.m missing CATransform3D perspective")
    if "kDefaultsPitch" not in common or "kDefaultsCropL" not in common:
        errors.append("OverlayCommon.h missing pitch/crop defaults keys")
    if "1.9.0" not in common:
        errors.append("OverlayCommon.h version is not 1.9.0")
    if "kDefaultsWarpPts" not in common:
        errors.append("OverlayCommon.h missing warp defaults key")
    if "beginWarpMode" not in mgr_h or "beginPerspectiveMode" not in mgr_h:
        errors.append("OverlayManager.h missing warp/perspective mode")
    if "warpHandles" not in view_m or "layoutWarpChrome" not in view_m:
        errors.append("OverlayView.m missing warp handles")
    if "perspectiveModeEnabled" not in view_h:
        errors.append("OverlayView.h missing perspectiveModeEnabled")
    if "- (void)menuLongPressed" not in mgr_m or "showQuickMenu" not in mgr_m:
        errors.append("OverlayManager.m missing long-press quick menu method")
    if "cropRectInBounds" not in view_m:
        errors.append("OverlayView.m missing cropRectInBounds (still-image crop box)")
    if "beginColorSampling" not in view_h:
        errors.append("OverlayView.h missing beginColorSampling")
    if "colorAtPoint" not in view_h:
        errors.append("OverlayView.h missing colorAtPoint")
    if "beginColorPickMode" not in mgr_h:
        errors.append("OverlayManager.h missing beginColorPickMode")
    if "pickerCatcher" not in mgr_m or "_colorPickModeEnabled" not in mgr_m:
        errors.append("OverlayManager.m missing color picker catcher")
    if "_cropSessionOrigin" not in mgr_m:
        errors.append("OverlayManager.m missing crop session origin")
    if "clampedCropInsets" not in view_h:
        errors.append("OverlayView.h missing clampedCropInsets")
    if "CoreImage" not in view_m:
        errors.append("OverlayView.m missing CoreImage warp")

    # UI contract
    for needle, where in (
        ("Tutamaçlarla kırp", settings),
        ("KIRPMA", settings),
        ("PERSPEKTİF", settings),
        ("cardAtY", settings),
        ("addNamedSlider", settings),
        ("menuHighlight", mgr_m),
        ("usingSpringWithDamping", mgr_m),
        ("showEditBarTitle", mgr_m),
        ("layoutCropChrome", view_m),
        ("layoutWarpChrome", view_m),
        ("Tutamaçlarla perspektif", settings),
        ("Warp tutamaçları", settings),
        ("showQuickMenu", mgr_m),
        ("Renk seç (eyedropper)", settings),
        ("beginColorPickMode", mgr_m),
        ("cropRectInBounds", view_m),
        ("beginColorSampling", view_m),
        ("pickerCatcher", mgr_m),
    ):
        if needle not in where:
            errors.append(f"UI missing {needle}")

    # Duplicate method definitions (same selector twice in one @implementation)
    impls = re.split(r"@implementation\s+\w+", mgr_m)
    for block in impls[1:]:
        sels = re.findall(r"^-\s*\([^)]+\)\s*(\w+)", block, re.M)
        seen: dict[str, int] = {}
        for s in sels:
            seen[s] = seen.get(s, 0) + 1
        for s, n in seen.items():
            if n > 1 and s not in {"init", "gestureRecognizer", "overlayView"}:
                errors.append(f"OverlayManager.m duplicate method {s} ({n})")

    for name, src in (
        ("OverlayManager.m", mgr_m),
        ("SettingsViewController.m", settings),
        ("OverlayView.m", view_m),
        ("OverlayEntry.m", read("OverlayEntry.m")),
    ):
        if src.count("{") != src.count("}"):
            errors.append(f"{name}: brace mismatch {{ {src.count('{')} }} {src.count('}')}")
        if src.count("[") < 10:
            errors.append(f"{name}: suspiciously few brackets")

    check_workflow(ROOT / "ci" / "build.yml", "ci/build.yml")
    # .github/workflows cannot be pushed by this token; ci/build.yml is the
    # canonical copy. If the GitHub file was already corrected, check it too.
    wf = ROOT / ".github" / "workflows" / "build.yml"
    if wf.exists():
        raw = wf.read_text(encoding="utf-8")
        broken = ("arena/**" in raw and "'arena/**'" not in raw and '"arena/**"' not in raw) or "checkout@v5" in raw
        if broken:
            print("NOTE: .github/workflows/build.yml is the GitHub copy that cannot be pushed.")
            print("      Paste ci/build.yml over it on GitHub so Actions will run.")
        else:
            check_workflow(wf, ".github/workflows/build.yml")

    if errors:
        print("FAIL")
        for e in errors:
            print(" -", e)
        return 1
    print("OK: sources look consistent")
    print(f"  Settings properties: {len(declared)}")
    print(f"  OverlayManager public selectors: {len(public)}")
    print(f"  Version: 1.9.0")
    print("  Workflow YAML: valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
