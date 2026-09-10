#!/usr/bin/env python3
"""Generate iOS + Persistence targets on top of the HEAD XcodeGen pbxproj.

Idempotent: always starts from `git show HEAD:Source/CalendarCountdown.xcodeproj/project.pbxproj`.
On a Mac, prefer `xcodegen generate` from project.yml; this script is the Linux fallback
that keeps a committed project file with iPhone/iPad destinations.
"""
from __future__ import annotations

import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PBX = ROOT / "CalendarCountdown.xcodeproj" / "project.pbxproj"
REPO = ROOT.parent


def hid(name: str) -> str:
    return hashlib.sha1(f"ccv2|{name}".encode()).hexdigest()[:24].upper()


def git_head_pbxproj() -> str:
    return subprocess.check_output(
        ["git", "show", "HEAD:Source/CalendarCountdown.xcodeproj/project.pbxproj"],
        cwd=REPO,
        text=True,
    )


def ref_id(text: str, comment: str) -> str:
    match = re.search(
        rf"([A-F0-9]{{24}}) /\* {re.escape(comment)} \*/ = {{isa = PBXFileReference",
        text,
    )
    if not match:
        raise SystemExit(f"missing file reference: {comment}")
    return match.group(1)


def variant_id(text: str, comment: str) -> str:
    match = re.search(
        rf"([A-F0-9]{{24}}) /\* {re.escape(comment)} \*/ = \{{\s*isa = PBXVariantGroup",
        text,
    )
    if not match:
        raise SystemExit(f"missing variant group: {comment}")
    return match.group(1)


def insert_before(text: str, marker: str, block: str) -> str:
    if marker not in text:
        raise SystemExit(f"missing marker: {marker}")
    return text.replace(marker, block + marker)


def append_children(text: str, after_line: str, lines: list[str]) -> str:
    needle = after_line + "\n"
    if needle not in text:
        raise SystemExit(f"missing children line: {after_line}")
    extra = "".join(f"{line}\n" for line in lines)
    return text.replace(needle, after_line + "\n" + extra, 1)


def build_file(key: str, comment: str, file_ref: str) -> tuple[str, str]:
    bid = hid(f"build:{key}")
    return bid, (
        f"\t\t{bid} /* {comment} in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {comment} */; }};"
    )


def resource_file(key: str, comment: str, file_ref: str) -> tuple[str, str]:
    bid = hid(f"res:{key}")
    return bid, (
        f"\t\t{bid} /* {comment} in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {comment} */; }};"
    )


def framework_file(key: str, comment: str, file_ref: str) -> tuple[str, str]:
    bid = hid(f"fw:{key}")
    return bid, (
        f"\t\t{bid} /* {comment} in Frameworks */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ref} /* {comment} */; }};"
    )


def swift_ref(path: str, filename: str) -> tuple[str, str]:
    rid = hid(f"file:{path}")
    return rid, (
        f"\t\t{rid} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = "
        f"sourcecode.swift; path = {filename}; sourceTree = \"<group>\"; }};"
    )


def product_ref(key: str, comment: str, explicit_type: str, path: str) -> tuple[str, str]:
    rid = hid(f"product:{key}")
    return rid, (
        f"\t\t{rid} /* {comment} */ = {{isa = PBXFileReference; explicitFileType = "
        f"{explicit_type}; includeInIndex = 0; path = {path}; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )


def sources_phase(key: str, build_ids: list[tuple[str, str]]) -> tuple[str, str]:
    pid = hid(f"phase:sources:{key}")
    files = "\n".join(f"\t\t\t\t{bid} /* {name} in Sources */," for bid, name in build_ids)
    block = f"""		{pid} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    return pid, block


def frameworks_phase(key: str, build_ids: list[tuple[str, str]]) -> tuple[str, str]:
    pid = hid(f"phase:fw:{key}")
    files = "\n".join(f"\t\t\t\t{bid} /* {name} in Frameworks */," for bid, name in build_ids)
    block = f"""		{pid} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
{files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    return pid, block


def resources_phase(key: str, build_ids: list[tuple[str, str]]) -> tuple[str, str]:
    pid = hid(f"phase:res:{key}")
    files = "\n".join(f"\t\t\t\t{bid} /* {name} in Resources */," for bid, name in build_ids)
    block = f"""		{pid} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{files}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    return pid, block


def copy_header_phase(key: str) -> tuple[str, str]:
    pid = hid(f"phase:header:{key}")
    block = f"""		{pid} /* Copy Swift Objective-C Interface Header */ = {{
			isa = PBXShellScriptBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			inputPaths = (
				"$(DERIVED_SOURCES_DIR)/$(SWIFT_OBJC_INTERFACE_HEADER_NAME)",
			);
			name = "Copy Swift Objective-C Interface Header";
			outputPaths = (
				"$(BUILT_PRODUCTS_DIR)/include/$(PRODUCT_MODULE_NAME)/$(SWIFT_OBJC_INTERFACE_HEADER_NAME)",
			);
			runOnlyForDeploymentPostprocessing = 0;
			shellPath = /bin/sh;
			shellScript = "ditto \\"${{SCRIPT_INPUT_FILE_0}}\\" \\"${{SCRIPT_OUTPUT_FILE_0}}\\"\\n";
		}};
"""
    return pid, block


def embed_phase(key: str, build_id: str, comment: str) -> tuple[str, str]:
    pid = hid(f"phase:embed:{key}")
    block = f"""		{pid} /* Embed Foundation Extensions */ = {{
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 13;
			files = (
				{build_id} /* {comment} in Embed Foundation Extensions */,
			);
			name = "Embed Foundation Extensions";
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""
    return pid, block


def native_target(
    name: str,
    product_name: str,
    product_ref: str,
    product_comment: str,
    product_type: str,
    phases: list[tuple[str, str]],
    dependencies: list[str],
) -> str:
    tid = hid(f"target:{name}")
    cfg = hid(f"cfglist:{name}")
    phase_lines = "\n".join(f"\t\t\t\t{pid} /* {label} */," for pid, label in phases)
    dep_lines = "\n".join(f"\t\t\t\t{did} /* PBXTargetDependency */," for did in dependencies)
    return f"""		{tid} /* {name} */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {cfg} /* Build configuration list for PBXNativeTarget "{name}" */;
			buildPhases = (
{phase_lines}
			);
			buildRules = (
			);
			dependencies = (
{dep_lines}
			);
			name = {name};
			packageProductDependencies = (
			);
			productName = {product_name};
			productReference = {product_ref} /* {product_comment} */;
			productType = "{product_type}";
		}};
"""


def dependency(key: str, target_name: str, target_id: str) -> tuple[str, str, str]:
    proxy = hid(f"proxy:{key}")
    dep = hid(f"dep:{key}")
    proxy_block = f"""		{proxy} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = 6EC488ABDD974036BC95F55D /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {target_id};
			remoteInfo = {target_name};
		}};
"""
    dep_block = f"""		{dep} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {target_id} /* {target_name} */;
			targetProxy = {proxy} /* PBXContainerItemProxy */;
		}};
"""
    return dep, proxy_block, dep_block


def configs(name: str, settings: str) -> str:
    debug_id = hid(f"cfg:{name}:debug")
    release_id = hid(f"cfg:{name}:release")
    list_id = hid(f"cfglist:{name}")
    return f"""		{debug_id} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings}
			}};
			name = Debug;
		}};
		{release_id} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{settings}
			}};
			name = Release;
		}};
		{list_id} /* Build configuration list for PBXNativeTarget "{name}" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{debug_id} /* Debug */,
				{release_id} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		}};
"""


def main() -> None:
    text = git_head_pbxproj()
    existing_ids = set(re.findall(r"\b([A-F0-9]{24})\b", text))

    core_existing = [
        "AppLocalization.swift",
        "DateSupport.swift",
        "LunarDateResolver.swift",
        "Models.swift",
        "Persistence.swift",
        "ProductConstants.swift",
        "TrackedEvents.swift",
        "WidgetSnapshot.swift",
    ]
    core_new = [
        "AppRoute.swift",
        "CloudRecords.swift",
        "CountdownCloudModels.swift",
        "DomainV2.swift",
    ]
    persist_files = [
        "AppBroker.swift",
        "AppDatabase.swift",
        "CloudKitSyncEngine.swift",
        "CloudProfileSession.swift",
        "DomainStore.swift",
    ]
    shared_files = [
        "AppSectionSidebar.swift",
        "ColorHex.swift",
        "WorkModuleViews.swift",
    ]
    service_files = ["Workspace.swift"]
    mobile_files = ["CalendarCountdowniOSApp.swift", "MobileRootView.swift"]
    widget_ios_files = ["CalendarCountdowniOSWidget.swift"]
    persist_tests = ["AppDatabaseAndServiceTests.swift"]
    ios_tests = ["CalendarCountdowniOSTests.swift"]
    ios_uitests = ["CalendarCountdowniOSUITests.swift"]
    ios_app_shared = [
        "AddEventView.swift",
        "AppModel.swift",
        "FocusAppearance.swift",
        "MainView.swift",
    ]

    file_refs: dict[str, str] = {}
    file_ref_blocks: list[str] = []
    build_blocks: list[str] = []

    def add_swift(path: str) -> str:
        filename = path.split("/")[-1]
        rid, block = swift_ref(path, filename)
        file_refs[path] = rid
        file_ref_blocks.append(block)
        return rid

    for name in core_new:
        add_swift(f"Core/{name}")
    for name in persist_files:
        add_swift(f"Persistence/{name}")
    for name in shared_files:
        add_swift(f"SharedUI/{name}")
    for name in service_files:
        add_swift(f"Services/{name}")
    add_swift("App/RootView.swift")
    for name in mobile_files:
        add_swift(f"Mobile/{name}")
    for name in widget_ios_files:
        add_swift(f"WidgetiOS/{name}")
    for name in persist_tests:
        add_swift(f"PersistenceTests/{name}")
    for name in ios_tests:
        add_swift(f"MobileTests/{name}")
    for name in ios_uitests:
        add_swift(f"MobileUITests/{name}")

    persist_product, persist_product_block = product_ref(
        "libPersistence.a", "libCalendarCountdownPersistence.a", "archive.ar", "libCalendarCountdownPersistence.a"
    )
    persist_tests_product, persist_tests_product_block = product_ref(
        "PersistenceTests.xctest",
        "CalendarCountdownPersistenceTests.xctest",
        "wrapper.cfbundle",
        "CalendarCountdownPersistenceTests.xctest",
    )
    ios_app_product, ios_app_product_block = product_ref(
        "CalendarCountdowniOS.app",
        "CalendarCountdown.app",
        "wrapper.application",
        "CalendarCountdown.app",
    )
    ios_widget_product, ios_widget_product_block = product_ref(
        "CalendarCountdowniOSWidget.appex",
        "CalendarCountdowniOSWidget.appex",
        '"wrapper.app-extension"',
        "CalendarCountdowniOSWidget.appex",
    )
    ios_tests_product, ios_tests_product_block = product_ref(
        "CalendarCountdowniOSTests.xctest",
        "CalendarCountdowniOSTests.xctest",
        "wrapper.cfbundle",
        "CalendarCountdowniOSTests.xctest",
    )
    ios_uitests_product, ios_uitests_product_block = product_ref(
        "CalendarCountdowniOSUITests.xctest",
        "CalendarCountdowniOSUITests.xctest",
        "wrapper.cfbundle",
        "CalendarCountdowniOSUITests.xctest",
    )
    file_ref_blocks.extend(
        [
            persist_product_block,
            persist_tests_product_block,
            ios_app_product_block,
            ios_widget_product_block,
            ios_tests_product_block,
            ios_uitests_product_block,
        ]
    )

    cloudkit_ref = hid("file:CloudKit.framework")
    sqlite_ref = hid("file:libsqlite3.tbd")
    file_ref_blocks.append(
        f"\t\t{cloudkit_ref} /* CloudKit.framework */ = {{isa = PBXFileReference; lastKnownFileType = "
        f"wrapper.framework; name = CloudKit.framework; path = System/Library/Frameworks/CloudKit.framework; sourceTree = SDKROOT; }};"
    )
    file_ref_blocks.append(
        f"\t\t{sqlite_ref} /* libsqlite3.tbd */ = {{isa = PBXFileReference; lastKnownFileType = "
        f'"sourcecode.text-based-dylib-definition"; name = libsqlite3.tbd; path = usr/lib/libsqlite3.tbd; sourceTree = SDKROOT; }};'
    )

    new_ids = {hid(f"file:{path}") for path in [
        *(f"Core/{n}" for n in core_new),
        *(f"Persistence/{n}" for n in persist_files),
        *(f"SharedUI/{n}" for n in shared_files),
        *(f"Services/{n}" for n in service_files),
        "App/RootView.swift",
        *(f"Mobile/{n}" for n in mobile_files),
        *(f"WidgetiOS/{n}" for n in widget_ios_files),
        *(f"PersistenceTests/{n}" for n in persist_tests),
        *(f"MobileTests/{n}" for n in ios_tests),
        *(f"MobileUITests/{n}" for n in ios_uitests),
    ]} | {
        persist_product,
        persist_tests_product,
        ios_app_product,
        ios_widget_product,
        ios_tests_product,
        ios_uitests_product,
        cloudkit_ref,
        sqlite_ref,
        hid("target:CalendarCountdownPersistence"),
        hid("target:CalendarCountdownPersistenceTests"),
        hid("target:CalendarCountdowniOS"),
        hid("target:CalendarCountdowniOSWidget"),
        hid("target:CalendarCountdowniOSTests"),
        hid("target:CalendarCountdowniOSUITests"),
    }
    overlap = new_ids & existing_ids
    if overlap:
        raise SystemExit(f"id collision with HEAD pbxproj: {overlap}")

    core_lib = "1E8AC3FCC01295977EDB1CC2"
    eventkit = ref_id(text, "EventKit.framework")
    widgetkit = ref_id(text, "WidgetKit.framework")
    swiftui = ref_id(text, "SwiftUI.framework")
    assets = ref_id(text, "Assets.xcassets")
    infoplist = variant_id(text, "InfoPlist.strings")
    localizable = variant_id(text, "Localizable.strings")
    eventkit_repo = ref_id(text, "EventKitRepository.swift")
    core_target = "A010F775DC7149AFD453D6CB"

    existing_core_refs = {name: ref_id(text, name) for name in core_existing}
    existing_app_refs = {name: ref_id(text, name) for name in ios_app_shared}

    def add_source(key: str, comment: str, file_ref: str) -> tuple[str, str]:
        bid, block = build_file(key, comment, file_ref)
        build_blocks.append(block)
        return bid, comment

    core_new_macos = [
        add_source(f"core-macos:{name}", name, file_refs[f"Core/{name}"]) for name in core_new
    ]
    persist_lib_sources = [
        add_source(f"persist:{name}", name, file_refs[f"Persistence/{name}"]) for name in persist_files
    ]
    persist_test_sources = [
        add_source(f"persisttest:{name}", name, file_refs[f"PersistenceTests/{name}"])
        for name in persist_tests
    ]
    macos_app_extra = [
        add_source("app:RootView.swift", "RootView.swift", file_refs["App/RootView.swift"]),
        *[
            add_source(f"app:{name}", name, file_refs[f"SharedUI/{name}"])
            for name in shared_files
        ],
        *[
            add_source(f"app:{name}", name, file_refs[f"Services/{name}"])
            for name in service_files
        ],
    ]

    ios_core_sources = [
        add_source(f"ios-core:{name}", name, existing_core_refs[name]) for name in core_existing
    ] + [
        add_source(f"ios-core:{name}", name, file_refs[f"Core/{name}"]) for name in core_new
    ]
    ios_calendar_sources = [
        add_source("ios:EventKitRepository.swift", "EventKitRepository.swift", eventkit_repo)
    ]
    ios_persist_sources = [
        add_source(f"ios-persist:{name}", name, file_refs[f"Persistence/{name}"])
        for name in persist_files
    ]
    ios_shared_sources = [
        add_source(f"ios-shared:{name}", name, file_refs[f"SharedUI/{name}"])
        for name in shared_files
    ]
    ios_service_sources = [
        add_source(f"ios-service:{name}", name, file_refs[f"Services/{name}"])
        for name in service_files
    ]
    ios_app_sources = [
        add_source(f"ios-app:{name}", name, existing_app_refs[name]) for name in ios_app_shared
    ] + [
        add_source(f"ios-mobile:{name}", name, file_refs[f"Mobile/{name}"]) for name in mobile_files
    ]
    ios_widget_sources = [
        add_source(f"ios-widget-core:{name}", name, existing_core_refs[name]) for name in core_existing
    ] + [
        add_source(f"ios-widget-core:{name}", name, file_refs[f"Core/{name}"]) for name in core_new
    ] + [
        add_source(f"ios-widget:{name}", name, file_refs[f"WidgetiOS/{name}"])
        for name in widget_ios_files
    ]
    ios_test_sources = [
        add_source(f"ios-tests:{name}", name, file_refs[f"MobileTests/{name}"]) for name in ios_tests
    ]
    ios_uitest_sources = [
        add_source(f"ios-uitests:{name}", name, file_refs[f"MobileUITests/{name}"])
        for name in ios_uitests
    ]

    ios_assets_id, ios_assets_block = resource_file("ios:Assets", "Assets.xcassets", assets)
    ios_info_id, ios_info_block = resource_file("ios:InfoPlist", "InfoPlist.strings", infoplist)
    ios_loc_id, ios_loc_block = resource_file("ios:Localizable", "Localizable.strings", localizable)
    widget_info_id, widget_info_block = resource_file("iosw:InfoPlist", "InfoPlist.strings", infoplist)
    widget_loc_id, widget_loc_block = resource_file("iosw:Localizable", "Localizable.strings", localizable)
    build_blocks.extend(
        [ios_assets_block, ios_info_block, ios_loc_block, widget_info_block, widget_loc_block]
    )

    persist_core_fw, persist_core_fw_block = framework_file(
        "persist:core", "libCalendarCountdownCore.a", core_lib
    )
    persist_ck_fw, persist_ck_fw_block = framework_file("persist:ck", "CloudKit.framework", cloudkit_ref)
    persist_sqlite_fw, persist_sqlite_fw_block = framework_file("persist:sqlite", "libsqlite3.tbd", sqlite_ref)
    persist_tests_lib_fw, persist_tests_lib_fw_block = framework_file(
        "persisttests:lib", "libCalendarCountdownPersistence.a", persist_product
    )
    persist_tests_core_fw, persist_tests_core_fw_block = framework_file(
        "persisttests:core", "libCalendarCountdownCore.a", core_lib
    )
    app_persist_fw, app_persist_fw_block = framework_file(
        "macosapp:persist", "libCalendarCountdownPersistence.a", persist_product
    )
    app_ck_fw, app_ck_fw_block = framework_file("macosapp:ck", "CloudKit.framework", cloudkit_ref)
    ios_ek_fw, ios_ek_fw_block = framework_file("ios:ek", "EventKit.framework", eventkit)
    ios_wk_fw, ios_wk_fw_block = framework_file("ios:wk", "WidgetKit.framework", widgetkit)
    ios_ck_fw, ios_ck_fw_block = framework_file("ios:ck", "CloudKit.framework", cloudkit_ref)
    ios_sqlite_fw, ios_sqlite_fw_block = framework_file("ios:sqlite", "libsqlite3.tbd", sqlite_ref)
    ios_swiftui_fw, ios_swiftui_fw_block = framework_file("ios:swiftui", "SwiftUI.framework", swiftui)
    ios_widget_wk_fw, ios_widget_wk_fw_block = framework_file("iosw:wk", "WidgetKit.framework", widgetkit)
    ios_widget_swiftui_fw, ios_widget_swiftui_fw_block = framework_file(
        "iosw:swiftui", "SwiftUI.framework", swiftui
    )
    embed_widget_id = hid("build:embed-ios-widget")
    embed_widget_block = (
        f"\t\t{embed_widget_id} /* CalendarCountdowniOSWidget.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {ios_widget_product} /* CalendarCountdowniOSWidget.appex */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    build_blocks.extend(
        [
            persist_core_fw_block,
            persist_ck_fw_block,
            persist_sqlite_fw_block,
            persist_tests_lib_fw_block,
            persist_tests_core_fw_block,
            app_persist_fw_block,
            app_ck_fw_block,
            ios_ek_fw_block,
            ios_wk_fw_block,
            ios_ck_fw_block,
            ios_sqlite_fw_block,
            ios_swiftui_fw_block,
            ios_widget_wk_fw_block,
            ios_widget_swiftui_fw_block,
            embed_widget_block,
        ]
    )

    persist_src_id, persist_src_block = sources_phase("persist", persist_lib_sources)
    persist_fw_id, persist_fw_block = frameworks_phase(
        "persist",
        [
            (persist_core_fw, "libCalendarCountdownCore.a"),
            (persist_ck_fw, "CloudKit.framework"),
            (persist_sqlite_fw, "libsqlite3.tbd"),
        ],
    )
    persist_hdr_id, persist_hdr_block = copy_header_phase("persist")
    persist_test_src_id, persist_test_src_block = sources_phase("persisttests", persist_test_sources)
    persist_test_fw_id, persist_test_fw_block = frameworks_phase(
        "persisttests",
        [
            (persist_tests_lib_fw, "libCalendarCountdownPersistence.a"),
            (persist_tests_core_fw, "libCalendarCountdownCore.a"),
        ],
    )
    ios_src_id, ios_src_block = sources_phase(
        "ios-app",
        ios_core_sources
        + ios_calendar_sources
        + ios_persist_sources
        + ios_shared_sources
        + ios_service_sources
        + ios_app_sources,
    )
    ios_fw_id, ios_fw_block = frameworks_phase(
        "ios-app",
        [
            (ios_ek_fw, "EventKit.framework"),
            (ios_wk_fw, "WidgetKit.framework"),
            (ios_ck_fw, "CloudKit.framework"),
            (ios_sqlite_fw, "libsqlite3.tbd"),
            (ios_swiftui_fw, "SwiftUI.framework"),
        ],
    )
    ios_res_id, ios_res_block = resources_phase(
        "ios-app",
        [
            (ios_assets_id, "Assets.xcassets"),
            (ios_info_id, "InfoPlist.strings"),
            (ios_loc_id, "Localizable.strings"),
        ],
    )
    ios_embed_id, ios_embed_block = embed_phase(
        "ios-app", embed_widget_id, "CalendarCountdowniOSWidget.appex"
    )
    ios_widget_src_id, ios_widget_src_block = sources_phase("ios-widget", ios_widget_sources)
    ios_widget_fw_id, ios_widget_fw_block = frameworks_phase(
        "ios-widget",
        [
            (ios_widget_wk_fw, "WidgetKit.framework"),
            (ios_widget_swiftui_fw, "SwiftUI.framework"),
        ],
    )
    ios_widget_res_id, ios_widget_res_block = resources_phase(
        "ios-widget",
        [
            (widget_info_id, "InfoPlist.strings"),
            (widget_loc_id, "Localizable.strings"),
        ],
    )
    ios_tests_src_id, ios_tests_src_block = sources_phase("ios-tests", ios_test_sources)
    ios_uitests_src_id, ios_uitests_src_block = sources_phase("ios-uitests", ios_uitest_sources)

    persist_target = hid("target:CalendarCountdownPersistence")
    persist_tests_target = hid("target:CalendarCountdownPersistenceTests")
    ios_target = hid("target:CalendarCountdowniOS")
    ios_widget_target = hid("target:CalendarCountdowniOSWidget")
    ios_tests_target = hid("target:CalendarCountdowniOSTests")
    ios_uitests_target = hid("target:CalendarCountdowniOSUITests")

    dep_persist_core, proxy1, dep1 = dependency("persist-core", "CalendarCountdownCore", core_target)
    dep_persisttests, proxy2, dep2 = dependency(
        "persisttests-persist", "CalendarCountdownPersistence", persist_target
    )
    dep_ios_widget, proxy3, dep3 = dependency(
        "ios-widget", "CalendarCountdowniOSWidget", ios_widget_target
    )
    dep_ios_tests, proxy4, dep4 = dependency("ios-tests-app", "CalendarCountdowniOS", ios_target)
    dep_ios_uitests, proxy5, dep5 = dependency("ios-uitests-app", "CalendarCountdowniOS", ios_target)
    dep_macos_persist, proxy6, dep6 = dependency(
        "macos-app-persist", "CalendarCountdownPersistence", persist_target
    )

    persist_settings = """
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.Persistence;
				PRODUCT_MODULE_NAME = CalendarCountdownPersistence;
				SDKROOT = macosx;
				SKIP_INSTALL = YES;
				OTHER_LDFLAGS = (
					"$(inherited)",
					"-lsqlite3",
				);
"""
    persist_test_settings = """
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.PersistenceTests;
				SDKROOT = macosx;
"""
    ios_app_settings = """
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = Config/iOS-App.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = "Config/iOS-App-Info.plist";
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				OTHER_LDFLAGS = (
					"$(inherited)",
					"-lsqlite3",
				);
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.ios;
				PRODUCT_MODULE_NAME = CalendarCountdown;
				PRODUCT_NAME = CalendarCountdown;
				SDKROOT = iphoneos;
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = "1,2";
"""
    ios_widget_settings = """
				APPLICATION_EXTENSION_API_ONLY = YES;
				CODE_SIGN_ENTITLEMENTS = Config/iOS-Widget.entitlements;
				CODE_SIGN_STYLE = Automatic;
				INFOPLIST_FILE = "Config/iOS-Widget-Info.plist";
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.ios.Widget;
				PRODUCT_MODULE_NAME = CalendarCountdowniOSWidget;
				PRODUCT_NAME = CalendarCountdowniOSWidget;
				SDKROOT = iphoneos;
				SKIP_INSTALL = YES;
				SUPPORTS_MACCATALYST = NO;
				TARGETED_DEVICE_FAMILY = "1,2";
"""
    ios_test_settings = """
				BUNDLE_LOADER = "$(TEST_HOST)";
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.ios.Tests;
				SDKROOT = iphoneos;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/CalendarCountdown.app/CalendarCountdown";
"""
    ios_uitest_settings = """
				GENERATE_INFOPLIST_FILE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 18.0;
				PRODUCT_BUNDLE_IDENTIFIER = app.calendarcountdown.CalendarCountdown.ios.UITests;
				SDKROOT = iphoneos;
				TARGETED_DEVICE_FAMILY = "1,2";
				TEST_TARGET_NAME = CalendarCountdowniOS;
"""

    persist_group = hid("group:Persistence")
    shared_group = hid("group:SharedUI")
    services_group = hid("group:Services")
    mobile_group = hid("group:Mobile")
    widget_ios_group = hid("group:WidgetiOS")
    persist_tests_group = hid("group:PersistenceTests")
    ios_tests_group = hid("group:MobileTests")
    ios_uitests_group = hid("group:MobileUITests")

    def group_block(gid: str, name: str, children: list[tuple[str, str]]) -> str:
        lines = "\n".join(f"\t\t\t\t{cid} /* {cname} */," for cid, cname in children)
        return f"""		{gid} /* {name} */ = {{
			isa = PBXGroup;
			children = (
{lines}
			);
			path = {name};
			sourceTree = "<group>";
		}};
"""

    groups = (
        group_block(persist_group, "Persistence", [(file_refs[f"Persistence/{n}"], n) for n in persist_files])
        + group_block(shared_group, "SharedUI", [(file_refs[f"SharedUI/{n}"], n) for n in shared_files])
        + group_block(services_group, "Services", [(file_refs[f"Services/{n}"], n) for n in service_files])
        + group_block(mobile_group, "Mobile", [(file_refs[f"Mobile/{n}"], n) for n in mobile_files])
        + group_block(widget_ios_group, "WidgetiOS", [(file_refs[f"WidgetiOS/{n}"], n) for n in widget_ios_files])
        + group_block(
            persist_tests_group,
            "PersistenceTests",
            [(file_refs[f"PersistenceTests/{n}"], n) for n in persist_tests],
        )
        + group_block(ios_tests_group, "MobileTests", [(file_refs[f"MobileTests/{n}"], n) for n in ios_tests])
        + group_block(
            ios_uitests_group, "MobileUITests", [(file_refs[f"MobileUITests/{n}"], n) for n in ios_uitests]
        )
    )

    targets = (
        native_target(
            "CalendarCountdownPersistence",
            "CalendarCountdownPersistence",
            persist_product,
            "libCalendarCountdownPersistence.a",
            "com.apple.product-type.library.static",
            [
                (persist_src_id, "Sources"),
                (persist_fw_id, "Frameworks"),
                (persist_hdr_id, "Copy Swift Objective-C Interface Header"),
            ],
            [dep_persist_core],
        )
        + native_target(
            "CalendarCountdownPersistenceTests",
            "CalendarCountdownPersistenceTests",
            persist_tests_product,
            "CalendarCountdownPersistenceTests.xctest",
            "com.apple.product-type.bundle.unit-test",
            [(persist_test_src_id, "Sources"), (persist_test_fw_id, "Frameworks")],
            [dep_persisttests],
        )
        + native_target(
            "CalendarCountdowniOS",
            "CalendarCountdown",
            ios_app_product,
            "CalendarCountdown.app",
            "com.apple.product-type.application",
            [
                (ios_src_id, "Sources"),
                (ios_res_id, "Resources"),
                (ios_fw_id, "Frameworks"),
                (ios_embed_id, "Embed Foundation Extensions"),
            ],
            [dep_ios_widget],
        )
        + native_target(
            "CalendarCountdowniOSWidget",
            "CalendarCountdowniOSWidget",
            ios_widget_product,
            "CalendarCountdowniOSWidget.appex",
            "com.apple.product-type.app-extension",
            [
                (ios_widget_src_id, "Sources"),
                (ios_widget_res_id, "Resources"),
                (ios_widget_fw_id, "Frameworks"),
            ],
            [],
        )
        + native_target(
            "CalendarCountdowniOSTests",
            "CalendarCountdowniOSTests",
            ios_tests_product,
            "CalendarCountdowniOSTests.xctest",
            "com.apple.product-type.bundle.unit-test",
            [(ios_tests_src_id, "Sources")],
            [dep_ios_tests],
        )
        + native_target(
            "CalendarCountdowniOSUITests",
            "CalendarCountdowniOSUITests",
            ios_uitests_product,
            "CalendarCountdowniOSUITests.xctest",
            "com.apple.product-type.bundle.ui-testing",
            [(ios_uitests_src_id, "Sources")],
            [dep_ios_uitests],
        )
    )

    cfg_blocks = (
        configs("CalendarCountdownPersistence", persist_settings)
        + configs("CalendarCountdownPersistenceTests", persist_test_settings)
        + configs("CalendarCountdowniOS", ios_app_settings)
        + configs("CalendarCountdowniOSWidget", ios_widget_settings)
        + configs("CalendarCountdowniOSTests", ios_test_settings)
        + configs("CalendarCountdowniOSUITests", ios_uitest_settings)
    )

    text = insert_before(text, "/* End PBXBuildFile section */", "\n".join(build_blocks) + "\n")
    text = insert_before(text, "/* End PBXFileReference section */", "\n".join(file_ref_blocks) + "\n")
    text = insert_before(text, "/* End PBXGroup section */", groups)
    text = insert_before(text, "/* End PBXNativeTarget section */", targets)
    text = insert_before(
        text,
        "/* End PBXContainerItemProxy section */",
        proxy1 + proxy2 + proxy3 + proxy4 + proxy5 + proxy6,
    )
    text = insert_before(
        text,
        "/* End PBXTargetDependency section */",
        dep1 + dep2 + dep3 + dep4 + dep5 + dep6,
    )
    text = insert_before(
        text,
        "/* End PBXSourcesBuildPhase section */",
        persist_src_block
        + persist_test_src_block
        + ios_src_block
        + ios_widget_src_block
        + ios_tests_src_block
        + ios_uitests_src_block,
    )
    text = insert_before(
        text,
        "/* End PBXFrameworksBuildPhase section */",
        persist_fw_block + persist_test_fw_block + ios_fw_block + ios_widget_fw_block,
    )
    text = insert_before(text, "/* End PBXResourcesBuildPhase section */", ios_res_block + ios_widget_res_block)
    text = insert_before(text, "/* End PBXShellScriptBuildPhase section */", persist_hdr_block)
    text = insert_before(text, "/* End PBXCopyFilesBuildPhase section */", ios_embed_block)
    text = insert_before(text, "/* End XCConfigurationList section */", cfg_blocks)

    core_children = "\n".join(
        f"\t\t\t\t{file_refs[f'Core/{name}']} /* {name} */," for name in core_new
    )
    text = text.replace(
        "\t\t\t\t241317BB23CE634E81423861 /* WidgetSnapshot.swift */,\n",
        "\t\t\t\t241317BB23CE634E81423861 /* WidgetSnapshot.swift */,\n" + core_children + "\n",
        1,
    )
    core_sources = "\n".join(
        f"\t\t\t\t{bid} /* {name} in Sources */," for bid, name in core_new_macos
    )
    text = text.replace(
        "\t\t\t\t8F3047F9F8BDFF082AD33699 /* WidgetSnapshot.swift in Sources */,\n",
        "\t\t\t\t8F3047F9F8BDFF082AD33699 /* WidgetSnapshot.swift in Sources */,\n" + core_sources + "\n",
        1,
    )
    app_children = f"\t\t\t\t{file_refs['App/RootView.swift']} /* RootView.swift */,\n"
    text = text.replace(
        "\t\t\t\t056E118F36D92693F8D13E2E /* MenuBarContentView.swift */,\n",
        "\t\t\t\t056E118F36D92693F8D13E2E /* MenuBarContentView.swift */,\n" + app_children,
        1,
    )
    app_sources = "\n".join(f"\t\t\t\t{bid} /* {name} in Sources */," for bid, name in macos_app_extra)
    text = text.replace(
        "\t\t\t\t9B9961711EE60D16A5727842 /* MenuBarContentView.swift in Sources */,\n",
        "\t\t\t\t9B9961711EE60D16A5727842 /* MenuBarContentView.swift in Sources */,\n" + app_sources + "\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t2D6867EF6859A4E8A124CC14 /* WidgetKit.framework in Frameworks */,\n",
        "\t\t\t\t2D6867EF6859A4E8A124CC14 /* WidgetKit.framework in Frameworks */,\n"
        f"\t\t\t\t{app_persist_fw} /* libCalendarCountdownPersistence.a in Frameworks */,\n"
        f"\t\t\t\t{app_ck_fw} /* CloudKit.framework in Frameworks */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t9C05DA74B95AE0D47C4DFB9F /* PBXTargetDependency */,\n",
        "\t\t\t\t9C05DA74B95AE0D47C4DFB9F /* PBXTargetDependency */,\n"
        f"\t\t\t\t{dep_macos_persist} /* PBXTargetDependency */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t129BCC9B8619489B2610BFD8 /* Widget */,\n",
        "\t\t\t\t129BCC9B8619489B2610BFD8 /* Widget */,\n"
        f"\t\t\t\t{persist_group} /* Persistence */,\n"
        f"\t\t\t\t{shared_group} /* SharedUI */,\n"
        f"\t\t\t\t{services_group} /* Services */,\n"
        f"\t\t\t\t{mobile_group} /* Mobile */,\n"
        f"\t\t\t\t{widget_ios_group} /* WidgetiOS */,\n"
        f"\t\t\t\t{persist_tests_group} /* PersistenceTests */,\n"
        f"\t\t\t\t{ios_tests_group} /* MobileTests */,\n"
        f"\t\t\t\t{ios_uitests_group} /* MobileUITests */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t7BD05FE988DA963486060135 /* WidgetKit.framework */,\n",
        "\t\t\t\t7BD05FE988DA963486060135 /* WidgetKit.framework */,\n"
        f"\t\t\t\t{cloudkit_ref} /* CloudKit.framework */,\n"
        f"\t\t\t\t{sqlite_ref} /* libsqlite3.tbd */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t1E8AC3FCC01295977EDB1CC2 /* libCalendarCountdownCore.a */,\n",
        "\t\t\t\t1E8AC3FCC01295977EDB1CC2 /* libCalendarCountdownCore.a */,\n"
        f"\t\t\t\t{persist_product} /* libCalendarCountdownPersistence.a */,\n"
        f"\t\t\t\t{persist_tests_product} /* CalendarCountdownPersistenceTests.xctest */,\n"
        f"\t\t\t\t{ios_app_product} /* CalendarCountdown.app */,\n"
        f"\t\t\t\t{ios_widget_product} /* CalendarCountdowniOSWidget.appex */,\n"
        f"\t\t\t\t{ios_tests_product} /* CalendarCountdowniOSTests.xctest */,\n"
        f"\t\t\t\t{ios_uitests_product} /* CalendarCountdowniOSUITests.xctest */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\t6377F8DF46BFFCC3C602C1D1 /* CalendarCountdownCoreTests */,\n",
        "\t\t\t\t6377F8DF46BFFCC3C602C1D1 /* CalendarCountdownCoreTests */,\n"
        f"\t\t\t\t{persist_target} /* CalendarCountdownPersistence */,\n"
        f"\t\t\t\t{persist_tests_target} /* CalendarCountdownPersistenceTests */,\n"
        f"\t\t\t\t{ios_target} /* CalendarCountdowniOS */,\n"
        f"\t\t\t\t{ios_widget_target} /* CalendarCountdowniOSWidget */,\n"
        f"\t\t\t\t{ios_tests_target} /* CalendarCountdowniOSTests */,\n"
        f"\t\t\t\t{ios_uitests_target} /* CalendarCountdowniOSUITests */,\n",
        1,
    )
    text = text.replace(
        "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n",
        "\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n"
        "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 18.0;\n",
    )

    PBX.write_text(text)
    print("wrote", PBX)
    print("targets:")
    for name in [
        "CalendarCountdownPersistence",
        "CalendarCountdownPersistenceTests",
        "CalendarCountdowniOS",
        "CalendarCountdowniOSWidget",
        "CalendarCountdowniOSTests",
        "CalendarCountdowniOSUITests",
    ]:
        print(f"  {name} {hid(f'target:{name}')}")


if __name__ == "__main__":
    main()
