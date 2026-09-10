#!/usr/bin/env python3
"""Linux-side sanity check that iOS targets exist in the committed Xcode project."""
from __future__ import annotations

import re
import sys
from pathlib import Path

PBX = Path(__file__).resolve().parents[1] / "CalendarCountdown.xcodeproj" / "project.pbxproj"


def main() -> int:
    text = PBX.read_text()
    required = [
        "CalendarCountdowniOS",
        "CalendarCountdowniOSWidget",
        "CalendarCountdowniOSTests",
        "CalendarCountdowniOSUITests",
        "CalendarCountdownPersistence",
        "CalendarCountdownPersistenceTests",
        'TARGETED_DEVICE_FAMILY = "1,2"',
        "SDKROOT = iphoneos",
        "Config/iOS-App.entitlements",
        "CalendarCountdowniOSApp.swift",
    ]
    missing = [item for item in required if item not in text]
    native = text.count("isa = PBXNativeTarget")
    if missing or native < 12:
        print("missing", missing, "native_targets", native, file=sys.stderr)
        return 1
    defs = re.findall(r"^\t\t([A-F0-9]{24}) ", text, re.M)
    if len(defs) != len(set(defs)):
        print("duplicate pbxproj object ids", file=sys.stderr)
        return 1
    print(f"ok: {native} native targets, iOS family 1,2 present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
