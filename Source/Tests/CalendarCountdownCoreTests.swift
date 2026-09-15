import XCTest
@testable import CalendarCountdownCore

final class CalendarCountdownCoreTests: XCTestCase {
    func testReleaseVersion() {
        XCTAssertEqual(ProductConstants.version, "1.0.17")
    }

    func testZhixingMetricsStayOnACoherentScale() {
        XCTAssertEqual(ZhixingMetrics.space4, 4)
        XCTAssertEqual(ZhixingMetrics.space8, 8)
        XCTAssertEqual(ZhixingMetrics.space12, 12)
        XCTAssertEqual(ZhixingMetrics.space16, 16)
        XCTAssertEqual(ZhixingMetrics.space20, 20)
        XCTAssertEqual(ZhixingMetrics.space24, 24)
        XCTAssertEqual(ZhixingMetrics.space32, 32)
        XCTAssertEqual(ZhixingMetrics.pageInset, 24)
        XCTAssertEqual(ZhixingMetrics.sidebarMinWidth, 220)
        XCTAssertEqual(ZhixingMetrics.sidebarIdealWidth, 236)
        XCTAssertEqual(ZhixingMetrics.sidebarMaxWidth, 248)
        XCTAssertEqual(ZhixingMetrics.cornerSmall, 8)
        XCTAssertEqual(ZhixingMetrics.cornerSheet, 12)
        XCTAssertEqual(ZhixingMetrics.cornerContainer, 16)
        XCTAssertLessThanOrEqual(ZhixingMetrics.identityMarkWidth, 4)
        XCTAssertGreaterThanOrEqual(ZhixingMetrics.identityMarkWidth, 3)
        XCTAssertEqual(ZhixingMetrics.completionRingSize, 21)
        XCTAssertLessThanOrEqual(ZhixingMetrics.accentFillMaxOpacity, 0.15)
        XCTAssertEqual(MissionEditorLayout.cardCornerRadius, ZhixingMetrics.cornerSheet)
        XCTAssertEqual(MissionEditorLayout.horizontalInset, ZhixingMetrics.pageInset)
        XCTAssertGreaterThanOrEqual(ZhixingSurfaceFill.minimumReadable, 0.04)
        XCTAssertTrue(WindowGlassAppearance.userFacingEnabled)
    }

    func testZhixingSurfaceFillStaysReadableAndLayered() {
        XCTAssertTrue(WindowGlassAppearance.userFacingEnabled)
        XCTAssertGreaterThanOrEqual(ZhixingSurfaceFill.minimumReadable, 0.04)
        XCTAssertEqual(ZhixingSurfaceRole.allCases.count, 6)

        for role in ZhixingSurfaceRole.allCases {
            for isDark in [false, true] {
                XCTAssertGreaterThanOrEqual(
                    ZhixingSurfaceFill.opacity(
                        for: role,
                        isDark: isDark,
                        reduceTransparency: false,
                        increaseContrast: false
                    ),
                    ZhixingSurfaceFill.minimumReadable
                )
                XCTAssertEqual(
                    ZhixingSurfaceFill.opacity(
                        for: role,
                        isDark: isDark,
                        reduceTransparency: true,
                        increaseContrast: false
                    ),
                    1
                )
                XCTAssertEqual(
                    ZhixingSurfaceFill.opacity(
                        for: role,
                        isDark: isDark,
                        reduceTransparency: false,
                        increaseContrast: true
                    ),
                    1
                )
                XCTAssertFalse(
                    ZhixingSurfaceFill.usesMaterial(
                        for: role,
                        reduceTransparency: true,
                        increaseContrast: false
                    )
                )
                XCTAssertFalse(
                    ZhixingSurfaceFill.usesMaterial(
                        for: role,
                        reduceTransparency: false,
                        increaseContrast: true
                    )
                )
            }
        }

        XCTAssertFalse(
            ZhixingSurfaceFill.usesMaterial(
                for: .sheet,
                reduceTransparency: false,
                increaseContrast: false
            )
        )
        XCTAssertTrue(
            ZhixingSurfaceFill.usesMaterial(
                for: .sidebar,
                reduceTransparency: false,
                increaseContrast: false
            )
        )

        let lightSidebar = ZhixingSurfaceFill.opacity(
            for: .sidebar,
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        let lightGrouped = ZhixingSurfaceFill.opacity(
            for: .grouped,
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        let lightCanvas = ZhixingSurfaceFill.opacity(
            for: .canvas,
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        let lightSheet = ZhixingSurfaceFill.opacity(
            for: .sheet,
            isDark: false,
            reduceTransparency: false,
            increaseContrast: false
        )
        XCTAssertLessThan(lightGrouped, lightSidebar)
        XCTAssertLessThan(lightSidebar, lightCanvas)
        XCTAssertLessThan(lightCanvas, lightSheet)
        XCTAssertLessThan(lightCanvas, 0.55)
        XCTAssertGreaterThanOrEqual(lightSheet, 0.70)

        XCTAssertEqual(
            ZhixingSurfaceFill.opacity(
                for: .sidebar,
                isDark: false,
                reduceTransparency: false,
                increaseContrast: false
            ),
            ZhixingSurfaceFill.sidebarLight,
            accuracy: 0.000_1
        )

        XCTAssertGreaterThan(
            ZhixingSurfaceFill.opacity(
                for: .sidebar,
                isDark: true,
                reduceTransparency: false,
                increaseContrast: false
            ),
            ZhixingSurfaceFill.opacity(
                for: .sidebar,
                isDark: false,
                reduceTransparency: false,
                increaseContrast: false
            )
        )
        XCTAssertLessThan(
            ZhixingSurfaceFill.opacity(
                for: .row,
                isDark: false,
                hovering: false,
                reduceTransparency: false,
                increaseContrast: false
            ),
            ZhixingSurfaceFill.opacity(
                for: .row,
                isDark: false,
                hovering: true,
                reduceTransparency: false,
                increaseContrast: false
            )
        )
    }

    func testZhixingSurfaceFillOverallTransparencyScalesTogether() {
        XCTAssertEqual(
            ZhixingSurfaceFill.scaled(
                ZhixingSurfaceFill.sidebarLight,
                overallTransparency: WindowGlassAppearance.defaultTransparency
            ),
            ZhixingSurfaceFill.sidebarLight,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            ZhixingSurfaceFill.scaled(
                ZhixingSurfaceFill.canvasLight,
                overallTransparency: 0
            ),
            1,
            accuracy: 0.000_1
        )

        let defaultT = WindowGlassAppearance.defaultTransparency
        let openT = 0.80
        let solidT = 0.20

        for isDark in [false, true] {
            let sidebarDefault = ZhixingSurfaceFill.opacity(
                for: .sidebar,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: defaultT
            )
            let groupedDefault = ZhixingSurfaceFill.opacity(
                for: .grouped,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: defaultT
            )
            let canvasDefault = ZhixingSurfaceFill.opacity(
                for: .canvas,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: defaultT
            )
            let sheetDefault = ZhixingSurfaceFill.opacity(
                for: .sheet,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: defaultT
            )
            XCTAssertLessThan(groupedDefault, sidebarDefault)
            XCTAssertLessThan(sidebarDefault, canvasDefault)
            XCTAssertLessThan(canvasDefault, sheetDefault)

            let sidebarOpen = ZhixingSurfaceFill.opacity(
                for: .sidebar,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: openT
            )
            let groupedOpen = ZhixingSurfaceFill.opacity(
                for: .grouped,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: openT
            )
            let canvasOpen = ZhixingSurfaceFill.opacity(
                for: .canvas,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: openT
            )
            let sheetOpen = ZhixingSurfaceFill.opacity(
                for: .sheet,
                isDark: isDark,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: openT
            )
            XCTAssertLessThan(groupedOpen, sidebarOpen)
            XCTAssertLessThan(sidebarOpen, canvasOpen)
            XCTAssertLessThan(canvasOpen, sheetOpen)
            XCTAssertLessThan(sidebarOpen, sidebarDefault)
            XCTAssertLessThan(canvasOpen, canvasDefault)
            XCTAssertLessThan(sheetOpen, sheetDefault)

            for role in ZhixingSurfaceRole.allCases {
                let solid = ZhixingSurfaceFill.opacity(
                    for: role,
                    isDark: isDark,
                    reduceTransparency: false,
                    increaseContrast: false,
                    overallTransparency: solidT
                )
                let open = ZhixingSurfaceFill.opacity(
                    for: role,
                    isDark: isDark,
                    reduceTransparency: false,
                    increaseContrast: false,
                    overallTransparency: openT
                )
                XCTAssertLessThan(open, solid)
                XCTAssertEqual(
                    ZhixingSurfaceFill.opacity(
                        for: role,
                        isDark: isDark,
                        reduceTransparency: false,
                        increaseContrast: false,
                        overallTransparency: 0
                    ),
                    1,
                    accuracy: 0.000_1
                )
                XCTAssertEqual(
                    ZhixingSurfaceFill.opacity(
                        for: role,
                        isDark: isDark,
                        reduceTransparency: true,
                        increaseContrast: false,
                        overallTransparency: openT
                    ),
                    1,
                    accuracy: 0.000_1
                )
            }
        }

        XCTAssertFalse(
            ZhixingSurfaceFill.usesMaterial(
                for: .sidebar,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: 0
            )
        )
        XCTAssertTrue(
            ZhixingSurfaceFill.usesMaterial(
                for: .sidebar,
                reduceTransparency: false,
                increaseContrast: false,
                overallTransparency: defaultT
            )
        )
    }

    func testCloudSyncPresentationCoversLocalSyncingSyncedAndFailed() {
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .localOnly,
                isSyncing: false,
                hasError: false,
                status: nil
            ),
            .localOnly
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: false,
                status: nil
            ),
            .enabled
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: false,
                status: CloudSyncStatus(mode: .iCloud, pendingOutbox: 0, openConflicts: 0)
            ),
            .enabled
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: true,
                hasError: false,
                status: nil
            ),
            .syncing
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: true,
                hasError: false,
                status: CloudSyncStatus(
                    mode: .iCloud,
                    pendingOutbox: 0,
                    openConflicts: 0,
                    lastFetchAt: Date()
                )
            ),
            .syncing
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: true,
                status: CloudSyncStatus(mode: .iCloud, pendingOutbox: 0, openConflicts: 0)
            ),
            .failed
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: false,
                status: CloudSyncStatus(
                    mode: .iCloud,
                    pendingOutbox: 0,
                    openConflicts: 0,
                    lastFetchAt: Date()
                )
            ),
            .synced
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: false,
                status: CloudSyncStatus(
                    mode: .iCloud,
                    account: .noAccount,
                    pendingOutbox: 0,
                    openConflicts: 0,
                    lastFetchAt: Date()
                )
            ),
            .failed
        )
        XCTAssertEqual(
            CloudSyncPresentation.resolve(
                mode: .iCloud,
                isSyncing: false,
                hasError: false,
                status: CloudSyncStatus(
                    mode: .iCloud,
                    pendingOutbox: 0,
                    openConflicts: 0,
                    lastSendAt: Date()
                )
            ),
            .synced
        )
        XCTAssertEqual(CloudSyncPresentation.localOnly.title, "仅本机")
        XCTAssertEqual(CloudSyncPresentation.enabled.title, "已开启")
        XCTAssertEqual(CloudSyncPresentation.enabled.accessibilityValue, "已开启，待首次同步")
        XCTAssertEqual(CloudSyncPresentation.syncing.title, "同步中")
        XCTAssertEqual(CloudSyncPresentation.synced.title, "已同步")
        XCTAssertEqual(CloudSyncPresentation.failed.title, "失败")
    }

    func testAppSectionCreateActionsStayInsideFourPrimaryModules() {
        XCTAssertEqual(AppSection.countdown.createActionTitle, "新建倒数")
        XCTAssertEqual(AppSection.tasks.createActionTitle, "新建任务")
        XCTAssertEqual(AppSection.missions.createActionTitle, "新建使命")
        XCTAssertEqual(AppSection.habits.createActionTitle, "新建打卡")
        XCTAssertEqual(AppSection.allCases.count, 4)
    }

    func testEveryModuleCreateHelpUsesCommandN() {
        XCTAssertEqual(AppSection.inModuleCreateShortcutDisplay, "⌘N")
        for section in AppSection.allCases {
            XCTAssertTrue(
                section.createHelp.contains(AppSection.inModuleCreateShortcutDisplay),
                "\(section.rawValue) create help should mention ⌘N: \(section.createHelp)"
            )
        }
    }

    func testZhixingIdentityColorIsStableForTheSameUUID() {
        let id = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        XCTAssertEqual(ZhixingIdentity.color(for: id), ZhixingIdentity.color(for: id))
        XCTAssertNotEqual(
            ZhixingIdentity.color(for: id),
            ZhixingIdentity.color(for: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
        )
    }

    func testCompletedTrailKeepsAllItemsAndPutsOpenTasksFirst() {
        let items = [false, true, false, true, true]
        let partitioned = CompletedTrailPresentation.partition(items) { $0 }
        XCTAssertEqual(partitioned.open, [false, false])
        XCTAssertEqual(partitioned.completed, [true, true, true])
        XCTAssertEqual(partitioned.open.count + partitioned.completed.count, items.count)
    }

    func testCompletedTrailRestingFadeAlmostVanishesByFourthCard() {
        let first = CompletedTrailPresentation.resting(index: 0, highContrast: false)
        let fourth = CompletedTrailPresentation.resting(index: 3, highContrast: false)
        let fifth = CompletedTrailPresentation.resting(index: 4, highContrast: false)
        XCTAssertGreaterThan(first.opacity, 0.7)
        XCTAssertGreaterThan(first.opacity, fourth.opacity)
        XCTAssertGreaterThan(fourth.opacity, fifth.opacity)
        XCTAssertLessThan(fifth.opacity, 0.16)
        XCTAssertGreaterThan(fifth.opacity, 0)
        XCTAssertGreaterThan(first.saturation, fifth.saturation)
        XCTAssertLessThan(first.veil, fifth.veil)
    }

    func testCompletedTrailRestoresWhenScrolledIntoReadingFocus() {
        let buried = CompletedTrailPresentation.resolve(
            index: 6,
            normalizedY: 0.92,
            isHighlighted: false,
            highContrast: false
        )
        let inFocus = CompletedTrailPresentation.resolve(
            index: 6,
            normalizedY: 0.30,
            isHighlighted: false,
            highContrast: false
        )
        XCTAssertGreaterThan(inFocus.opacity, buried.opacity)
        XCTAssertGreaterThan(inFocus.opacity, 0.85)
        XCTAssertEqual(inFocus.saturation, 1, accuracy: 0.001)
        XCTAssertEqual(inFocus.veil, 0, accuracy: 0.001)
        XCTAssertEqual(CompletedTrailPresentation.readingFocus(normalizedY: 0.30), 1, accuracy: 0.001)
        XCTAssertEqual(CompletedTrailPresentation.readingFocus(normalizedY: 0.92), 0, accuracy: 0.001)
    }

    func testCompletedTrailHighlightAndHighContrastRaiseReadability() {
        let buried = CompletedTrailPresentation.resolve(
            index: 5,
            normalizedY: 0.95,
            isHighlighted: false,
            highContrast: false
        )
        let highlighted = CompletedTrailPresentation.resolve(
            index: 5,
            normalizedY: 0.95,
            isHighlighted: true,
            highContrast: false
        )
        let highContrast = CompletedTrailPresentation.resolve(
            index: 8,
            normalizedY: 0.95,
            isHighlighted: false,
            highContrast: true
        )
        XCTAssertGreaterThan(highlighted.opacity, 0.9)
        XCTAssertGreaterThan(highContrast.opacity, buried.opacity)
        XCTAssertGreaterThanOrEqual(highContrast.opacity, CompletedTrailPresentation.highContrastFloor)
    }

    func testStatusBarOverviewMigratesLegacyUsersToCountdownOnly() {
        XCTAssertEqual(
            StatusBarOverviewState.migrated(
                countdown: nil,
                mission: nil,
                tasks: nil,
                selectedMissionID: nil
            ),
            .legacyCountdownOnly
        )
        let kept = UUID()
        let migrated = StatusBarOverviewState.migrated(
            countdown: nil,
            mission: nil,
            tasks: nil,
            selectedMissionID: kept
        )
        XCTAssertEqual(migrated.enabledKinds, [.countdown])
        XCTAssertEqual(migrated.selectedMissionID, kept)
        XCTAssertFalse(migrated.showMissionProgress)
        XCTAssertFalse(migrated.showTodayTasks)
    }

    func testStatusBarOverviewToggleCombinationsEnableIndependentKinds() {
        let combos: [(Bool, Bool, Bool, [StatusBarOverviewKind])] = [
            (false, false, false, []),
            (true, false, false, [.countdown]),
            (false, true, false, [.mission]),
            (false, false, true, [.todayTasks]),
            (true, true, false, [.countdown, .mission]),
            (true, false, true, [.countdown, .todayTasks]),
            (false, true, true, [.mission, .todayTasks]),
            (true, true, true, [.countdown, .mission, .todayTasks])
        ]
        for combo in combos {
            let state = StatusBarOverviewState(
                showCountdown: combo.0,
                showMissionProgress: combo.1,
                showTodayTasks: combo.2
            )
            XCTAssertEqual(state.enabledKinds, combo.3)
        }
        XCTAssertEqual(
            StatusBarOverviewState.migrated(
                countdown: false,
                mission: true,
                tasks: true,
                selectedMissionID: nil
            ).enabledKinds,
            [.mission, .todayTasks]
        )
    }

    func testStatusBarItemRegistryNeverDuplicatesAKind() {
        let all = Set(StatusBarOverviewKind.allCases)
        let created = StatusBarItemRegistry.reconcile(desired: all, existingCounts: [:])
        XCTAssertEqual(Set(created.create), all)
        XCTAssertTrue(created.remove.isEmpty)

        let extras = StatusBarItemRegistry.reconcile(
            desired: [.countdown],
            existingCounts: [.countdown: 2, .mission: 1, .todayTasks: 1]
        )
        XCTAssertTrue(extras.create.isEmpty)
        XCTAssertEqual(extras.remove[.countdown], 1)
        XCTAssertEqual(extras.remove[.mission], 1)
        XCTAssertEqual(extras.remove[.todayTasks], 1)

        let off = StatusBarItemRegistry.reconcile(
            desired: [],
            existingCounts: Dictionary(uniqueKeysWithValues: StatusBarOverviewKind.allCases.map { ($0, 1) })
        )
        XCTAssertTrue(off.create.isEmpty)
        XCTAssertEqual(off.remove.count, 3)
    }

    func testStatusBarTodayRemainingCountExcludesInboxAndCompleted() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 9,
                day: 12,
                hour: 15
            ).date
        )
        let today = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 9,
                day: 12,
                hour: 18
            ).date
        )
        let yesterday = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 9,
                day: 11,
                hour: 10
            ).date
        )
        let tomorrow = try XCTUnwrap(
            DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 9,
                day: 13,
                hour: 10
            ).date
        )
        let views = [
            statusBarTaskView(status: .open, due: today, start: nil),
            statusBarTaskView(status: .open, due: yesterday, start: nil),
            statusBarTaskView(status: .open, due: nil, start: today),
            statusBarTaskView(status: .open, due: nil, start: nil),
            statusBarTaskView(status: .completed, due: today, start: nil),
            statusBarTaskView(status: .open, due: tomorrow, start: nil)
        ]
        XCTAssertEqual(
            StatusBarTodaySemantics.remainingCount(views: views, now: now, calendar: calendar),
            3
        )
    }

    func testStatusBarMissionPresentationClearsDeletedSelection() {
        let device = UUID()
        let kept = MissionDefinition(title: "保留", color: "teal", modifiedByDevice: device)
        var removed = MissionDefinition(title: "已删", color: "purple", modifiedByDevice: device)
        removed.deletedAt = Date()
        XCTAssertEqual(StatusBarMissionPresentation.resolvedID(kept.id, among: [kept, removed]), kept.id)
        XCTAssertNil(StatusBarMissionPresentation.resolvedID(removed.id, among: [kept, removed]))
        XCTAssertEqual(StatusBarMissionPresentation.percentText(progress: 0.4), "40%")
        XCTAssertEqual(StatusBarMissionPresentation.percentText(progress: nil), "—")
    }

    func testStatusBarMissionArtworkUsesMonochromeWaterFromBottomAtMenuBarSize() {
        for side in StatusBarMissionArtworkSpec.menuBarSides {
            let empty = StatusBarMissionArtworkSpec.make(progress: nil, side: side)
            XCTAssertEqual(empty.style, .waterOrb)
            XCTAssertEqual(empty.fillRatio, 0)
            XCTAssertTrue(empty.usesTemplateRendering)
            XCTAssertFalse(empty.usesMissionColor)
            XCTAssertEqual(empty.waterRect.height, 0, accuracy: 0.001)
            XCTAssertEqual(empty.waterRect.y, empty.contentInset, accuracy: 0.001)

            let half = StatusBarMissionArtworkSpec.make(progress: 0.5, side: side)
            XCTAssertEqual(half.style, .waterOrb)
            XCTAssertEqual(half.fillRatio, 0.5, accuracy: 0.0001)
            XCTAssertFalse(half.usesMissionColor)
            XCTAssertEqual(half.waterRect.y, half.contentInset, accuracy: 0.001)
            XCTAssertEqual(half.waterFillHeight, half.innerSide * 0.5, accuracy: 0.001)
            XCTAssertGreaterThan(half.waterFillHeight, 4)
            XCTAssertLessThan(half.waterRect.y + half.waterFillHeight, half.side - 0.5)

            let full = StatusBarMissionArtworkSpec.make(progress: 1, side: side)
            XCTAssertEqual(full.waterFillHeight, full.innerSide, accuracy: 0.001)
            XCTAssertEqual(StatusBarMissionArtworkSpec.make(progress: 1.4, side: side).fillRatio, 1)
            XCTAssertEqual(StatusBarMissionArtworkSpec.make(progress: -0.2, side: side).fillRatio, 0)
        }

        let ring = StatusBarMissionArtworkSpec.make(progress: 0.25, side: 16)
        XCTAssertEqual(ring.style, .progressRing)
        XCTAssertFalse(ring.usesMissionColor)
        XCTAssertTrue(ring.usesTemplateRendering)
        XCTAssertEqual(ring.ringSweepDegrees, 90, accuracy: 0.001)
        XCTAssertEqual(StatusBarMissionPresentation.percentText(progress: 0.25), "25%")
    }

    func testMissionColorPaletteUsesStableIdentifiersAndMigratesLegacyHex() {
        XCTAssertEqual(MissionColor.allCases.count, 12)
        XCTAssertEqual(Set(MissionColor.allCases.map(\.rawValue)).count, 12)
        XCTAssertEqual(MissionColor.resolve("teal"), .teal)
        XCTAssertEqual(MissionColor.resolve("#5B8DEF"), .blue)
        XCTAssertEqual(MissionColor.resolve("#34C759"), .green)
        XCTAssertEqual(MissionColor.canonicalStorageValue("not-a-color"), "blue")
    }

    func testMissionEditorLayoutFitsNormalAndNarrowWorkAreas() {
        let normal = MissionEditorLayout.fittingSize(available: CGSize(width: 1_440, height: 900))
        XCTAssertEqual(normal.width, MissionEditorLayout.idealWidth)
        XCTAssertEqual(normal.height, MissionEditorLayout.idealHeight)
        XCTAssertGreaterThan(normal.width, MissionEditorLayout.horizontalInset * 2)

        let compact = MissionEditorLayout.fittingSize(available: CGSize(width: 700, height: 520))
        XCTAssertEqual(compact.width, MissionEditorLayout.idealWidth)
        XCTAssertEqual(compact.height, 520 - MissionEditorLayout.chromeMargin * 2)

        let narrow = MissionEditorLayout.fittingSize(available: CGSize(width: 500, height: 520))
        XCTAssertEqual(narrow.width, 500 - MissionEditorLayout.chromeMargin * 2)
        XCTAssertEqual(narrow.height, 520 - MissionEditorLayout.chromeMargin * 2)
        XCTAssertLessThan(narrow.width, MissionEditorLayout.idealWidth)
        XCTAssertGreaterThanOrEqual(narrow.width, MissionEditorLayout.minimumReadableContentWidth)
        XCTAssertGreaterThan(MissionEditorLayout.contentScrollHeight(windowHeight: narrow.height), 120)

        let tiny = MissionEditorLayout.fittingSize(available: CGSize(width: 400, height: 360))
        XCTAssertLessThanOrEqual(tiny.width, 400)
        XCTAssertLessThanOrEqual(tiny.height, 360)
        XCTAssertGreaterThan(tiny.width, 0)
        XCTAssertGreaterThan(tiny.height, 0)
    }

    func testMissionEditorInlineIconStaysWithTitleChrome() {
        XCTAssertEqual(MissionEditorLayout.identityIconSize, 34)
        XCTAssertGreaterThan(
            MissionEditorLayout.identityIconHitSize,
            MissionEditorLayout.identityIconSize
        )
        XCTAssertLessThan(MissionEditorLayout.iconPopoverWidth, MissionEditorLayout.minWidth)
        XCTAssertGreaterThan(MissionEditorLayout.iconPickerMaxHeight, 120)
    }

    func testCalendarAccessRecoveryPromptsThenOpensSettingsAfterDenial() {
        XCTAssertEqual(CalendarAccessRecovery.action(for: .notDetermined), .requestPrompt)
        XCTAssertEqual(CalendarAccessRecovery.action(for: .writeOnly), .requestPrompt)
        XCTAssertEqual(CalendarAccessRecovery.action(for: .denied), .openSystemSettings)
        XCTAssertEqual(CalendarAccessRecovery.action(for: .restricted), .openSystemSettings)
        XCTAssertEqual(CalendarAccessRecovery.action(for: .fullAccess), .none)
        XCTAssertEqual(
            CalendarAccessRecovery.transition(from: .denied, to: .fullAccess),
            .gainedAccess
        )
        XCTAssertEqual(
            CalendarAccessRecovery.transition(from: .fullAccess, to: .denied),
            .lostAccess
        )
        XCTAssertEqual(
            CalendarAccessRecovery.transition(from: .denied, to: .denied),
            .unchanged
        )
        XCTAssertTrue(CalendarAccessRecovery.shouldLoadCalendarData(.fullAccess))
        XCTAssertFalse(CalendarAccessRecovery.shouldLoadCalendarData(.denied))
        XCTAssertEqual(
            CalendarAccessRecovery.macOSCalendarPrivacyURL.scheme,
            "x-apple.systempreferences"
        )
    }

    func testMissionSelectionFallsBackWhenSelectedMissionIsDeleted() {
        let device = UUID()
        let kept = MissionDefinition(title: "保留", color: "teal", modifiedByDevice: device)
        var removed = MissionDefinition(title: "已删", color: "purple", modifiedByDevice: device)
        removed.deletedAt = Date()
        XCTAssertEqual(MissionSelection.resolvedID(kept.id, among: [kept, removed]), kept.id)
        XCTAssertNil(MissionSelection.resolvedID(removed.id, among: [kept, removed]))
        XCTAssertEqual(MissionSelection.featured(among: [removed, kept])?.id, kept.id)
        XCTAssertEqual(
            MissionSelection.resolvedRoute(.mission(removed.id), among: [kept]),
            .section(.missions)
        )
        XCTAssertEqual(
            MissionSelection.resolvedRoute(.mission(kept.id), among: [kept]),
            .mission(kept.id)
        )
    }

    func testLegacyWidgetMissionDecodesWithDefaultIdentityColor() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "title": "Legacy Mission",
          "progress": 0.5,
          "icon": "flag.fill"
        }
        """
        let item = try JSONCoding.decoder().decode(WidgetMissionItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.color, MissionColor.defaultValue.rawValue)
    }

    func testWindowGlassAppearanceClampsTransparency() {
        XCTAssertEqual(WindowGlassAppearance.clamped(0), 0, accuracy: 0.000_1)
        XCTAssertEqual(WindowGlassAppearance.clamped(0.4), 0.4, accuracy: 0.000_1)
        XCTAssertEqual(
            WindowGlassAppearance.clamped(0.95),
            WindowGlassAppearance.maximumTransparency,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            WindowGlassAppearance.clamped(-0.2),
            WindowGlassAppearance.minimumTransparency,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            WindowGlassAppearance.clamped(.nan),
            WindowGlassAppearance.defaultTransparency,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            WindowGlassAppearance.clamped(.infinity),
            WindowGlassAppearance.maximumTransparency,
            accuracy: 0.000_1
        )
        XCTAssertEqual(WindowGlassAppearance.percent(0.401), 40)
        XCTAssertEqual(
            WindowGlassAppearance.percent(WindowGlassAppearance.maximumTransparency),
            76
        )
        XCTAssertEqual(WindowGlassAppearance.minimumFillOpacity, 0.24, accuracy: 0.000_1)
        XCTAssertEqual(
            WindowGlassAppearance.maximumTransparency,
            1 - WindowGlassAppearance.minimumFillOpacity,
            accuracy: 0.000_1
        )
        XCTAssertTrue(WindowGlassAppearance.userFacingEnabled)
    }

    func testWindowGlassFillOpacityKeepsReadableFloor() {
        XCTAssertEqual(WindowGlassAppearance.fillOpacity(transparency: 0), 1, accuracy: 0.000_1)
        XCTAssertEqual(
            WindowGlassAppearance.fillOpacity(transparency: WindowGlassAppearance.maximumTransparency),
            WindowGlassAppearance.minimumFillOpacity,
            accuracy: 0.000_1
        )
        XCTAssertGreaterThanOrEqual(
            WindowGlassAppearance.fillOpacity(transparency: 1),
            WindowGlassAppearance.minimumFillOpacity
        )
    }

    func testWindowGlassUserFacingPreferenceMigratesRetiredValueOnce() {
        let suiteName = "test.window-glass.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: WindowGlassAppearance.enabledDefaultsKey)
        XCTAssertFalse(defaults.bool(forKey: WindowGlassAppearance.enabledDefaultsKey))

        WindowGlassAppearance.activateCodexGlassPreference(in: defaults)

        XCTAssertTrue(defaults.bool(forKey: WindowGlassAppearance.enabledDefaultsKey))
        XCTAssertTrue(defaults.bool(forKey: WindowGlassAppearance.codexGlassMigrationDefaultsKey))
        XCTAssertTrue(
            WindowGlassAppearance.isUserFacingGlassActive(
                enabledFlag: true,
                reduceTransparency: false
            )
        )
        XCTAssertFalse(
            WindowGlassAppearance.isUserFacingGlassActive(
                enabledFlag: false,
                reduceTransparency: false
            )
        )

        defaults.set(false, forKey: WindowGlassAppearance.enabledDefaultsKey)
        WindowGlassAppearance.activateCodexGlassPreference(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: WindowGlassAppearance.enabledDefaultsKey))
    }

    func testComposerReturnInsertsNewlineUnlessCommandReturnSaves() {
        XCTAssertEqual(ComposerReturnAction.fromReturn(commandPressed: false), .insertNewline)
        XCTAssertEqual(ComposerReturnAction.fromReturn(commandPressed: true), .submit)
    }

    func testMissionSymbolCatalogHasUniqueSystemNames() {
        let names = MissionSymbolCatalog.all.map(\.systemName)
        XCTAssertFalse(names.isEmpty)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.contains(MissionSymbolCatalog.defaultSystemName))
        XCTAssertEqual(MissionSymbolCatalog.resolved("  "), MissionSymbolCatalog.defaultSystemName)
        XCTAssertEqual(MissionSymbolCatalog.title(for: "wrench.fill"), "扳手")
        XCTAssertEqual(MissionSymbolCatalog.groups(matching: "扳手").flatMap(\.symbols).map(\.systemName), ["wrench.fill"])
    }

    func testDeadlineScheduleCanBeUndated() throws {
        let schedule = try TaskSchedule(timeZoneIdentifier: "Asia/Shanghai").validated(kind: .deadline)
        XCTAssertTrue(schedule.isUndated)
    }

    func testCalendarDayCountdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(DateSupport.parseDateOnly("2026-08-30", calendar: calendar))
        let target = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-07", calendar: calendar))
        XCTAssertEqual(CountdownCalculator.daysRemaining(until: target, from: now, calendar: calendar), 8)
        XCTAssertEqual(CountdownCalculator.label(until: now, from: now, calendar: calendar), "今天")
    }

    func testCalendarDayRefreshPolicyRefreshesOnceAfterMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let beforeMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 23, minute: 59))
        )
        let midnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 3))
        )
        var policy = CalendarDayRefreshPolicy(now: beforeMidnight, calendar: calendar)

        XCTAssertFalse(policy.shouldRefresh(at: beforeMidnight, calendar: calendar))
        XCTAssertTrue(policy.shouldRefresh(at: midnight, calendar: calendar))
        XCTAssertFalse(policy.shouldRefresh(
            at: midnight.addingTimeInterval(60),
            calendar: calendar
        ))
        XCTAssertEqual(DateSupport.nextMidnight(after: beforeMidnight, calendar: calendar), midnight)
    }

    func testCalendarDayRefreshPolicyHandlesWakeAfterMultipleDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let beforeSleep = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-02", calendar: calendar))
        let afterWake = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-05", calendar: calendar))
        var policy = CalendarDayRefreshPolicy(now: beforeSleep, calendar: calendar)

        XCTAssertTrue(policy.shouldRefresh(at: afterWake, calendar: calendar))
        XCTAssertFalse(policy.shouldRefresh(at: afterWake, calendar: calendar))
    }

    func testSingleDayAllDayEndSemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let start = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-20", calendar: calendar))

        let exchangeEnd = DateSupport.allDayEventEnd(
            startingAt: start,
            semantics: .inclusiveSameDay,
            calendar: calendar
        )
        let standardEnd = DateSupport.allDayEventEnd(
            startingAt: start,
            semantics: .exclusiveNextDay,
            calendar: calendar
        )

        XCTAssertEqual(DateSupport.dateOnlyString(exchangeEnd, calendar: calendar), "2026-09-20")
        XCTAssertEqual(DateSupport.dateOnlyString(standardEnd, calendar: calendar), "2026-09-21")
        XCTAssertEqual(standardEnd.timeIntervalSince(exchangeEnd), 1)
        XCTAssertFalse(DateSupport.allDayEventExceedsSingleDay(
            startDate: start,
            endDate: exchangeEnd,
            semantics: .inclusiveSameDay,
            calendar: calendar
        ))
        XCTAssertTrue(DateSupport.allDayEventExceedsSingleDay(
            startDate: start,
            endDate: standardEnd,
            semantics: .inclusiveSameDay,
            calendar: calendar
        ))
    }

    func testSingleDayAllDayEndUsesCalendarDayAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let start = try XCTUnwrap(DateSupport.parseDateOnly("2026-03-08", calendar: calendar))
        let end = DateSupport.allDayEventEnd(
            startingAt: start,
            semantics: .inclusiveSameDay,
            calendar: calendar
        )

        XCTAssertEqual(DateSupport.dateOnlyString(end, calendar: calendar), "2026-03-08")
        XCTAssertEqual(end.timeIntervalSince(start), 82_799)
    }

    func testLocalizationResourcesHaveMatchingKeysAndPlaceholders() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localizationRoot = sourceRoot.appendingPathComponent("Localization", isDirectory: true)
        let locales = ["zh-Hans", "en", "ja", "ko", "es", "ru"]
        let reference = try localizationDictionary(
            at: localizationRoot.appendingPathComponent("zh-Hans.lproj/Localizable.strings")
        )
        let referenceInfo = try localizationDictionary(
            at: localizationRoot.appendingPathComponent("zh-Hans.lproj/InfoPlist.strings")
        )

        XCTAssertGreaterThanOrEqual(reference.count, 180)
        XCTAssertNotNil(reference["countdown.remaining_days"])
        XCTAssertNotNil(reference["status.tracked_events_exported"])
        XCTAssertEqual(Set(referenceInfo.keys), [
            "CFBundleDisplayName",
            "CFBundleName",
            "NSCalendarsFullAccessUsageDescription",
            "NSRemindersFullAccessUsageDescription"
        ])

        for locale in locales {
            let localized = try localizationDictionary(
                at: localizationRoot.appendingPathComponent("\(locale).lproj/Localizable.strings")
            )
            let localizedInfo = try localizationDictionary(
                at: localizationRoot.appendingPathComponent("\(locale).lproj/InfoPlist.strings")
            )
            XCTAssertEqual(Set(localized.keys), Set(reference.keys), "Missing Localizable.strings keys for \(locale)")
            XCTAssertEqual(Set(localizedInfo.keys), Set(referenceInfo.keys), "Missing InfoPlist.strings keys for \(locale)")

            for key in reference.keys {
                XCTAssertEqual(
                    formatPlaceholders(in: localized[key] ?? ""),
                    formatPlaceholders(in: reference[key] ?? ""),
                    "Format placeholders differ for \(locale): \(key)"
                )
            }
        }
    }

    func testLunarDatesMatchFirstBatchScreenshots() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let expected: [(gregorianYear: Int, lunarMonth: Int, lunarDay: Int, date: String)] = [
            (2026, 7, 26, "2026-09-07"),
            (2026, 11, 15, "2026-12-23"),
            (2026, 11, 19, "2026-12-27"),
            (2027, 12, 12, "2027-01-19"),
            (2027, 12, 16, "2027-01-23"),
            (2027, 12, 29, "2027-02-05"),
            (2027, 4, 10, "2027-05-15")
        ]

        for item in expected {
            let values = LunarDateResolver.dates(
                month: item.lunarMonth,
                day: item.lunarDay,
                leapMonthPolicy: .regularOnly,
                invalidDayPolicy: .clampToMonthEnd,
                inGregorianYear: item.gregorianYear,
                timeZone: zone
            ).map { DateSupport.dateOnlyString($0, calendar: calendar) }
            XCTAssertTrue(values.contains(item.date), "农历 \(item.lunarMonth)-\(item.lunarDay) 未得到 \(item.date)，实际为 \(values)")
        }
    }

    func testAnnualTitleSelectionMatchesOnlySameCalendarAndTitle() {
        let date = Date()
        let selection = CountdownSelection(
            mode: .annualTitle,
            calendarIdentifier: "holiday-calendar",
            calendarTitle: "中国大陆节假日",
            eventTitle: "元旦"
        )
        let matching = makeEvent(
            id: "one",
            title: "元旦",
            date: date,
            calendarID: "holiday-calendar",
            calendarTitle: "中国大陆节假日"
        )
        let wrongTitle = makeEvent(
            id: "two",
            title: "春节",
            date: date,
            calendarID: "holiday-calendar",
            calendarTitle: "中国大陆节假日"
        )
        XCTAssertTrue(selection.matches(matching))
        XCTAssertFalse(selection.matches(wrongTitle))
    }

    func testExactEventRematchesNextYearViaStableExternalIdentifier() throws {
        let lastYear = try XCTUnwrap(DateSupport.parseDateOnly("2025-09-20"))
        let thisYear = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-20"))
        let selection = CountdownSelection(
            mode: .exactEvent,
            calendarIdentifier: "birthday",
            calendarTitle: "生日",
            eventIdentifier: "old-occurrence-id",
            externalIdentifier: "series-stable",
            eventTitle: "李四",
            occurrenceDate: lastYear
        )
        let nextOccurrence = makeEvent(
            id: "birthday-2026",
            title: "李四",
            date: thisYear,
            calendarID: "birthday",
            calendarTitle: "生日",
            calendarItemIdentifier: "new-occurrence-id",
            externalIdentifier: "series-stable"
        )
        XCTAssertTrue(selection.matches(nextOccurrence))
        XCTAssertEqual(
            CountdownSelectionStore.nextSelectedEvents(
                from: [nextOccurrence],
                selections: [selection]
            ).map(\.id),
            ["birthday-2026"]
        )
    }

    func testExactEventRematchesAfterCalendarIdentifierDrift() throws {
        let date = try XCTUnwrap(DateSupport.parseDateOnly("2026-10-01"))
        let selection = CountdownSelection(
            mode: .exactEvent,
            calendarIdentifier: "stale-calendar-id",
            calendarTitle: "生日",
            eventIdentifier: "gone",
            externalIdentifier: "gone-external",
            eventTitle: "王五",
            occurrenceDate: date
        )
        let rematched = makeEvent(
            id: "now",
            title: "王五",
            date: date,
            calendarID: "new-calendar-id",
            calendarTitle: "生日"
        )
        XCTAssertTrue(selection.belongsToSameCalendar(as: rematched))
        XCTAssertTrue(selection.matches(rematched))
    }

    func testAnnualTitleRematchesAfterCalendarIdentifierDrift() {
        let date = Date()
        let selection = CountdownSelection(
            mode: .annualTitle,
            calendarIdentifier: "old-holidays",
            calendarTitle: "中国大陆节假日",
            eventTitle: "元旦"
        )
        let rematched = makeEvent(
            id: "holiday",
            title: "元旦",
            date: date,
            calendarID: "new-holidays",
            calendarTitle: "中国大陆节假日"
        )
        XCTAssertTrue(selection.matches(rematched))
    }

    func testYearByYearQueryWindowCoversDefaultFetchRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try XCTUnwrap(
            DateComponents(calendar: calendar, year: 2026, month: 9, day: 12).date
        )
        let end = try XCTUnwrap(calendar.date(byAdding: .day, value: ProductConstants.defaultFetchDays, to: start))
        let slices = EventKitQueryWindow.yearSlices(from: start, to: end, calendar: calendar)
        XCTAssertGreaterThanOrEqual(slices.count, 5)
        XCTAssertEqual(slices.first?.start, start)
        XCTAssertEqual(slices.last?.end, end)
        for index in 1..<slices.count {
            XCTAssertEqual(slices[index].start, slices[index - 1].end)
        }
    }

    func testCountdownPresentationRecoveryKeepsTrackedDocumentWhenSelectionsExist() {
        XCTAssertFalse(
            CountdownPresentationRecovery.shouldReplaceTrackedDocument(
                visibleEventCount: 0,
                selectionCount: 25
            )
        )
        XCTAssertTrue(
            CountdownPresentationRecovery.shouldReplaceTrackedDocument(
                visibleEventCount: 23,
                selectionCount: 25
            )
        )
        XCTAssertTrue(
            CountdownPresentationRecovery.shouldReplaceTrackedDocument(
                visibleEventCount: 0,
                selectionCount: 0
            )
        )
    }

    func testFullAccessStillLoadsCalendarDataAfterUnchangedRecovery() {
        XCTAssertTrue(CalendarAccessRecovery.shouldLoadCalendarData(.fullAccess))
        XCTAssertEqual(
            CalendarAccessRecovery.transition(from: .fullAccess, to: .fullAccess),
            .unchanged
        )
        XCTAssertEqual(
            CalendarAccessRecovery.transition(from: .denied, to: .fullAccess),
            .gainedAccess
        )
    }

    func testSingleInstanceDerivedDataYieldsToOfficialInstall() {
        let official = AppInstanceSnapshot(
            pid: 38384,
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundlePath: "/Applications/知行.app"
        )
        let derived = AppInstanceSnapshot(
            pid: 40394,
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            executablePath: "/Users/hashxjhuang/Library/Developer/Xcode/DerivedData/CalendarCountdown-buvinsbkcwybrweyhjwzbkzpxdqh/Build/Products/Release/CalendarCountdown.app/Contents/MacOS/CalendarCountdown",
            bundlePath: "/Users/hashxjhuang/Library/Developer/Xcode/DerivedData/CalendarCountdown-buvinsbkcwybrweyhjwzbkzpxdqh/Build/Products/Release/CalendarCountdown.app"
        )
        XCTAssertTrue(AppInstanceIdentity.isOfficialInstall(bundlePath: official.bundlePath))
        XCTAssertTrue(AppInstanceIdentity.isDerivedDataProduct(path: derived.executablePath))
        XCTAssertEqual(
            SingleInstancePolicy.decide(current: derived, others: [official]),
            .yieldToExisting(pid: 38384)
        )
        XCTAssertEqual(
            SingleInstancePolicy.decide(current: official, others: [derived]),
            .becomeHolder
        )
    }

    func testSingleInstanceClaimReleaseAndSecondInstanceTransfers() {
        let lock = MemorySingleInstanceLock()
        let first = SingleInstanceClaim(
            pid: 10,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier
        )
        let second = SingleInstanceClaim(
            pid: 11,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier
        )
        XCTAssertEqual(lock.tryAcquire(first), .acquired)
        XCTAssertEqual(lock.tryAcquire(second), .heldByExisting(first))
        lock.release(pid: 10)
        XCTAssertNil(lock.inspect())
        XCTAssertEqual(lock.tryAcquire(second), .acquired)
        XCTAssertEqual(lock.inspect()?.pid, 11)
    }

    func testFileSingleInstanceLockAllowsOnlyOneConcurrentClaim() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-instance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("single-instance.lock")
        let pid = ProcessInfo.processInfo.processIdentifier
        let lockA = FileSingleInstanceLock(fileURL: url)
        let lockB = FileSingleInstanceLock(fileURL: url)
        let claimA = SingleInstanceClaim(
            pid: pid,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            bundlePath: "/Applications/知行.app"
        )
        let claimB = SingleInstanceClaim(
            pid: pid,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            bundlePath: "/Applications/知行.app"
        )
        let resultsLock = NSLock()
        var results: [SingleInstanceLockResult] = []
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            let result = index == 0 ? lockA.tryAcquire(claimA) : lockB.tryAcquire(claimB)
            resultsLock.lock()
            results.append(result)
            resultsLock.unlock()
        }
        let acquired = results.filter { $0 == .acquired }
        let rejected = results.filter {
            if case .heldByExisting = $0 { return true }
            return false
        }
        XCTAssertEqual(acquired.count, 1)
        XCTAssertEqual(rejected.count, 1)
        lockA.release(pid: pid)
        lockB.release(pid: pid)
    }

    #if os(macOS)
    func testFileSingleInstanceLockRecoversStaleLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-instance-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("single-instance.lock")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        let stale = SingleInstanceClaim(
            pid: process.processIdentifier,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            bundlePath: "/Applications/知行.app"
        )
        XCTAssertFalse(ProcessLiveness.isLiveHolder(stale))
        try JSONEncoder().encode(stale).write(to: url)
        let lock = FileSingleInstanceLock(fileURL: url)
        let live = SingleInstanceClaim(
            pid: ProcessInfo.processInfo.processIdentifier,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            bundlePath: "/Applications/知行.app"
        )
        XCTAssertEqual(lock.tryAcquire(live), .acquired)
        XCTAssertEqual(lock.inspect()?.pid, live.pid)
        lock.release(pid: live.pid)
        XCTAssertNil(lock.inspect())
    }
    #endif

    func testSingleInstanceGateOfficialPreemptsDerivedHolderButYieldsToLockOwnerOtherwise() {
        let official = AppInstanceSnapshot(
            pid: 20,
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            executablePath: "/Applications/知行.app/Contents/MacOS/CalendarCountdown",
            bundlePath: "/Applications/知行.app"
        )
        let derivedClaim = SingleInstanceClaim(
            pid: 21,
            executablePath: "/Users/hashxjhuang/Library/Developer/Xcode/DerivedData/CalendarCountdown-buvinsbkcwybrweyhjwzbkzpxdqh/Build/Products/Release/CalendarCountdown.app/Contents/MacOS/CalendarCountdown",
            bundleIdentifier: ProductConstants.appBundleIdentifier,
            bundlePath: "/Users/hashxjhuang/Library/Developer/Xcode/DerivedData/CalendarCountdown-buvinsbkcwybrweyhjwzbkzpxdqh/Build/Products/Release/CalendarCountdown.app"
        )
        XCTAssertEqual(
            SingleInstanceGate.resolve(current: official, lockResult: .acquired),
            .becomeHolder
        )
        XCTAssertEqual(
            SingleInstanceGate.resolve(current: official, lockResult: .heldByExisting(derivedClaim)),
            .becomeHolder
        )
        XCTAssertEqual(
            SingleInstanceGate.resolve(
                current: derivedClaim.snapshot,
                lockResult: .heldByExisting(SingleInstanceClaim.from(official))
            ),
            .yieldToExisting(SingleInstanceClaim.from(official))
        )
    }

    func testHistoricalBundleIDIsRecognizedAndUnknownIDsAreRefused() {
        XCTAssertTrue(AppInstanceIdentity.recognizes(bundleID: ProductConstants.appBundleIdentifier))
        XCTAssertTrue(AppInstanceIdentity.recognizes(bundleID: "com.hashxjhuang.CalendarCountdown"))
        XCTAssertFalse(AppInstanceIdentity.recognizes(bundleID: "com.apple.Safari"))
        XCTAssertFalse(AppInstanceIdentity.shouldManageInstance(bundleID: "com.example.OtherCountdown"))
        XCTAssertFalse(
            AppInstanceIdentity.shouldManageInstance(
                bundleID: nil,
                executablePath: "/Applications/Other.app/Contents/MacOS/CalendarCountdown"
            )
        )
    }

    func testExactEventSelectionReconnectsWithoutLocalEventKitIdentifiers() {
        let date = Date()
        let selection = CountdownSelection(
            mode: .exactEvent,
            calendarTitle: "生日",
            eventTitle: "李四",
            occurrenceDate: date
        )
        let matching = makeEvent(
            id: "one",
            title: "李四",
            date: date,
            calendarID: "birthday",
            calendarTitle: "生日"
        )
        XCTAssertTrue(selection.matches(matching))
    }

    func testImportDefaultsAndValidation() throws {
        let json = """
        {
          "schemaVersion": 1,
          "events": [{
            "externalId": "one",
            "title": "李四",
            "calendarTitle": "生日",
            "calendarSystem": "lunar",
            "recurrence": "yearly",
            "lunarMonth": 8,
            "lunarDay": 15
          }]
        }
        """
        let document = try JSONCoding.decoder().decode(ImportDocument.self, from: Data(json.utf8))
        let validated = try document.validated()
        XCTAssertEqual(validated.events.count, 1)
        XCTAssertTrue(validated.selections.isEmpty)
        XCTAssertTrue(validated.events[0].selectForCountdown)
        XCTAssertEqual(validated.events[0].invalidLunarDayPolicy, .clampToMonthEnd)
    }

    func testExampleImportDocumentIsValid() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("Docs/first-batch.example.json")
        let document = try JSONCoding.decoder().decode(ImportDocument.self, from: Data(contentsOf: url))
        let validated = try document.validated()
        XCTAssertEqual(validated.events.count, 3)
        XCTAssertEqual(validated.events.filter { $0.calendarTitle == "生日" }.count, 2)
        XCTAssertEqual(validated.events.filter { $0.recurrence == .none }.map(\.title), ["项目正式上线"])
        XCTAssertEqual(validated.selections, [
            SelectionDraft(calendarTitle: "中国大陆节假日", eventTitle: "元旦", mode: .annualTitle)
        ])
    }

    func testDisplayPreferencesFilterUntrackedCalendarAndPreferPin() throws {
        let firstDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-07"))
        let secondDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-10-11"))
        let first = makeEvent(
            id: "one",
            title: "示例事件 A",
            date: firstDate,
            calendarID: "birthday",
            calendarTitle: "生日"
        )
        let second = makeEvent(
            id: "two",
            title: "示例事件 B",
            date: secondDate,
            calendarID: "personal",
            calendarTitle: "个人"
        )
        let firstSelection = CountdownSelection(
            mode: .exactEvent,
            calendarIdentifier: "birthday",
            calendarTitle: "生日",
            eventIdentifier: "one",
            eventTitle: "示例事件 A"
        )
        let secondSelection = CountdownSelection(
            mode: .exactEvent,
            calendarIdentifier: "personal",
            calendarTitle: "个人",
            eventIdentifier: "two",
            eventTitle: "示例事件 B"
        )
        let selections = [firstSelection, secondSelection]

        var preferences = CountdownDisplayPreferences(
            untrackedCalendarIdentifiers: ["personal"],
            pinnedSelectionID: secondSelection.id
        )
        let filtered = preferences.visibleSelectedEvents(from: [first, second], selections: selections)
        XCTAssertEqual(filtered.map(\.id), ["one"])
        XCTAssertEqual(preferences.featuredEvent(from: filtered, selections: selections)?.id, "one")

        preferences.untrackedCalendarIdentifiers.remove("personal")
        let visible = preferences.visibleSelectedEvents(from: [first, second], selections: selections)
        XCTAssertEqual(preferences.featuredEvent(from: visible, selections: selections)?.id, "two")
    }

    func testDisplayPreferencesDecodeMissingFields() throws {
        let preferences = try JSONCoding.decoder().decode(
            CountdownDisplayPreferences.self,
            from: Data("{}".utf8)
        )
        XCTAssertTrue(preferences.untrackedCalendarIdentifiers.isEmpty)
        XCTAssertNil(preferences.pinnedSelectionID)
    }

    func testRecurringSeriesShowsOnlyItsNearestOccurrence() throws {
        let firstDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-07"))
        let secondDate = try XCTUnwrap(DateSupport.parseDateOnly("2027-08-28"))
        let otherDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-10-11"))
        let first = makeEvent(
            id: "birthday-2026",
            title: "示例生日",
            date: firstDate,
            calendarID: "birthday",
            calendarTitle: "生日",
            seriesIdentifier: "birthday:demo-person"
        )
        let second = makeEvent(
            id: "birthday-2027",
            title: "示例生日",
            date: secondDate,
            calendarID: "birthday",
            calendarTitle: "生日",
            seriesIdentifier: "birthday:demo-person"
        )
        let unrelatedSameTitle = makeEvent(
            id: "one-off",
            title: "示例生日",
            date: otherDate,
            calendarID: "birthday",
            calendarTitle: "生日"
        )

        let visible = CountdownSelectionStore.nextOccurrences(
            from: [second, unrelatedSameTitle, first]
        )

        XCTAssertEqual(visible.map(\.id), ["birthday-2026", "one-off"])
    }

    func testNextYearlyOccurrenceUsesThisYearBeforeRollingForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let original = try XCTUnwrap(DateSupport.parseDateOnly("1990-09-20", calendar: calendar))
        let beforeBirthday = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-10", calendar: calendar))
        let afterBirthday = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-21", calendar: calendar))

        XCTAssertEqual(
            DateSupport.nextYearlyOccurrence(matching: original, onOrAfter: beforeBirthday, calendar: calendar)
                .map { DateSupport.dateOnlyString($0, calendar: calendar) },
            "2026-09-20"
        )
        XCTAssertEqual(
            DateSupport.nextYearlyOccurrence(matching: original, onOrAfter: afterBirthday, calendar: calendar)
                .map { DateSupport.dateOnlyString($0, calendar: calendar) },
            "2027-09-20"
        )
    }

    func testSelectedRecurringEventsUseNearestOccurrenceAndGlobalDateOrder() throws {
        let nearDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-20"))
        let middleDate = try XCTUnwrap(DateSupport.parseDateOnly("2026-10-11"))
        let staleFutureDate = try XCTUnwrap(DateSupport.parseDateOnly("2027-09-20"))
        let near = makeEvent(
            id: "birthday-near",
            title: "甲",
            date: nearDate,
            calendarID: "birthday",
            calendarTitle: "生日",
            seriesIdentifier: "managed:person-a"
        )
        let staleFuture = makeEvent(
            id: "birthday-next-year",
            title: "甲",
            date: staleFutureDate,
            calendarID: "birthday",
            calendarTitle: "生日",
            seriesIdentifier: "managed:person-a"
        )
        let middle = makeEvent(
            id: "birthday-middle",
            title: "乙",
            date: middleDate,
            calendarID: "birthday",
            calendarTitle: "生日",
            seriesIdentifier: "managed:person-b"
        )
        let selectionA = CountdownSelection(
            mode: .annualTitle,
            calendarIdentifier: "birthday",
            calendarTitle: "生日",
            eventTitle: "甲"
        )
        let selectionB = CountdownSelection(
            mode: .annualTitle,
            calendarIdentifier: "birthday",
            calendarTitle: "生日",
            eventTitle: "乙"
        )

        let visible = CountdownSelectionStore.nextSelectedEvents(
            from: [staleFuture, middle, near],
            selections: [selectionB, selectionA]
        )

        XCTAssertEqual(visible.map(\.id), ["birthday-near", "birthday-middle"])
    }

    func testTrackedEventsDocumentKeepsStartDateAndRecurrenceCalendar() throws {
        let trackedSince = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-31T00:00:00Z"))
        let record = TrackedEventRecord(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "示例农历生日",
            kind: .birthday,
            date: TrackedDateDefinition(
                startYear: 1990,
                calendarSystem: .lunar,
                month: 12,
                day: 29,
                isLeapMonth: false
            ),
            recurrence: TrackedRecurrenceDefinition(
                frequency: .yearly,
                calendarSystem: .lunar,
                lunarLeapMonthPolicy: .regularOnly,
                invalidLunarDayPolicy: .clampToMonthEnd
            ),
            nextOccurrence: "2027-02-05",
            time: nil,
            timeZoneIdentifier: "Asia/Shanghai",
            isAllDay: true,
            calendar: TrackedCalendarReference(
                identifier: "birthday",
                title: "生日",
                sourceTitle: "iCloud",
                colorHex: "#FF0000"
            ),
            tracking: TrackedSelectionReference(
                mode: .managedRecord,
                trackedSince: trackedSince,
                isPinned: false
            ),
            appleCalendar: TrackedAppleCalendarReference(
                calendarItemIdentifier: "calendar-item",
                externalIdentifier: "external-item",
                managedRecordID: nil
            )
        )
        let document = TrackedEventsDocument(updatedAt: trackedSince, events: [record])
        let data = try JSONCoding.encoder().encode(document)
        let decoded = try JSONCoding.decoder().decode(TrackedEventsDocument.self, from: data)

        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.sourceOfTruth, "appleCalendar")
        XCTAssertEqual(decoded.events[0].date.startYear, 1990)
        XCTAssertEqual(decoded.events[0].date.calendarSystem, .lunar)
        XCTAssertEqual(decoded.events[0].recurrence.frequency, .yearly)
        XCTAssertEqual(decoded.events[0].recurrence.calendarSystem, .lunar)
        XCTAssertEqual(decoded.events[0].recurrence.lunarLeapMonthPolicy, .regularOnly)
    }

    func testManagedLunarEventStartYearRoundTrips() throws {
        let draft = ManagedEventDraft(
            title: "农历生日",
            calendarTitle: "生日",
            calendarSystem: .lunar,
            recurrence: .yearly,
            startYear: 1990,
            lunarMonth: 8,
            lunarDay: 15
        )

        let validated = try draft.validated()
        let data = try JSONCoding.encoder().encode(validated)
        let decoded = try JSONCoding.decoder().decode(ManagedEventDraft.self, from: data)
        XCTAssertEqual(decoded.startYear, 1990)
    }

    func testTrackedEventsExampleDocumentIsValid() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = projectRoot.appendingPathComponent("Docs/tracked-events.example.json")
        let document = try JSONCoding.decoder().decode(
            TrackedEventsDocument.self,
            from: Data(contentsOf: url)
        )

        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.events.count, 2)
        XCTAssertEqual(document.events.map(\.date.startYear), [1990, 2028])
        XCTAssertEqual(document.events.map(\.recurrence.calendarSystem), [.lunar, .gregorian])
    }

    private func makeEvent(
        id: String,
        title: String,
        date: Date,
        calendarID: String,
        calendarTitle: String,
        seriesIdentifier: String? = nil,
        calendarItemIdentifier: String? = nil,
        externalIdentifier: String? = nil
    ) -> CountdownEvent {
        CountdownEvent(
            id: id,
            seriesIdentifier: seriesIdentifier,
            calendarItemIdentifier: calendarItemIdentifier ?? id,
            externalIdentifier: externalIdentifier,
            title: title,
            eventDate: date,
            endDate: date,
            isAllDay: true,
            calendarTitle: calendarTitle,
            calendarIdentifier: calendarID,
            sourceTitle: "iCloud",
            colorHex: "#FF0000",
            notes: nil,
            url: nil
        )
    }
}

final class DiagnosticLoggingTests: XCTestCase {
    func testDefaultRootUsesLocalApplicationSupportRatherThanCloudOrAppGroupStorage() throws {
        let path = try DiagnosticLogStore.defaultRootURL().standardizedFileURL.path

        XCTAssertTrue(path.contains("/Library/Application Support/CalendarCountdown/Diagnostics"))
        XCTAssertFalse(path.contains("/Mobile Documents/"))
        XCTAssertFalse(path.contains(ProductConstants.appGroupIdentifier))
    }

    func testJSONLIsPrivateLocalAndStructured() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostic-log-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiagnosticLogStore(rootURL: root, component: "unit test")
        let entry = DiagnosticLogEntry(
            timestamp: "2026-09-10T08:00:00.000Z",
            level: .notice,
            category: .sync,
            event: "sync.completed",
            component: "unit-test",
            processID: 42,
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            installationID: store.installationID,
            localDeviceID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            correlationID: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            metadata: ["records": "3"]
        )
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-10T08:00:00Z"))

        try store.append(entry, at: date)

        let status = try store.status()
        XCTAssertTrue(status.localOnly)
        XCTAssertTrue(status.excludedFromBackup)
        XCTAssertEqual(status.retentionDays, 30)
        XCTAssertEqual(status.files.count, 1)
        let data = try Data(contentsOf: root.appendingPathComponent(status.files[0].name))
        let line = try XCTUnwrap(String(data: data, encoding: .utf8)?.split(separator: "\n").first)
        let decoded = try JSONDecoder().decode(DiagnosticLogEntry.self, from: Data(line.utf8))
        XCTAssertEqual(decoded, entry)
        let permissions = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(status.files[0].name).path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testCleanupRetainsExactlyThirtyCalendarDays() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnostic-retention-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try DiagnosticLogStore(rootURL: root, component: "retention")
        let formatter = ISO8601DateFormatter()
        let reference = try XCTUnwrap(formatter.date(from: "2026-09-10T12:00:00Z"))
        let dates = [
            reference,
            try XCTUnwrap(formatter.date(from: "2026-08-11T23:59:00Z")),
            try XCTUnwrap(formatter.date(from: "2026-08-12T00:00:00Z"))
        ]
        for (index, date) in dates.enumerated() {
            try store.append(
                DiagnosticLogEntry(
                    timestamp: RFC3339.utcString(from: date),
                    level: .info,
                    category: .maintenance,
                    event: "retention.\(index)",
                    component: "retention",
                    processID: 1,
                    sessionID: UUID(),
                    installationID: store.installationID
                ),
                at: date
            )
        }

        XCTAssertEqual(try store.cleanup(referenceDate: reference), 1)
        XCTAssertEqual(try store.files().map(\.name).sorted(), [
            "calendarcountdown-retention-2026-08-12.jsonl",
            "calendarcountdown-retention-2026-09-10.jsonl"
        ])
    }

    func testSensitiveMetadataIsRedactedAndTruncated() {
        XCTAssertEqual(DiagnosticLogger.sanitize("secret-value", key: "authorizationToken"), "<redacted>")
        XCTAssertEqual(
            DiagnosticLogger.sanitize("request Bearer abc.def-123 finished", key: "message"),
            "request <redacted> finished"
        )
        XCTAssertEqual(DiagnosticLogger.sanitize(String(repeating: "x", count: 3_000), key: "note").count, 2_048)
    }
}

private func statusBarTaskView(
    status: TaskOccurrenceStatus,
    due: Date?,
    start: Date?
) -> TaskOccurrenceView {
    let device = UUID()
    let series = TaskSeries(
        title: "任务",
        kind: .deadline,
        schedule: TaskSchedule(
            timeZoneIdentifier: "UTC",
            plannedStart: start,
            plannedDue: due
        ),
        modifiedByDevice: device
    )
    let occurrence = TaskOccurrence(
        seriesID: series.id,
        occurrenceKey: UUID().uuidString,
        plannedStart: start,
        plannedDue: due,
        status: status,
        modifiedByDevice: device
    )
    return TaskOccurrenceView(occurrence: occurrence, series: series)
}

private func localizationDictionary(at url: URL) throws -> [String: String] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(
        PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
        "Invalid strings file: \(url.path)"
    )
}

private func formatPlaceholders(in value: String) -> [String] {
    let pattern = #"%(?:[0-9]+\$)?(?:@|lld)"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(value.startIndex..., in: value)
    return expression.matches(in: value, range: range).compactMap { match in
        Range(match.range, in: value).map { String(value[$0]) }
    }.sorted()
}
