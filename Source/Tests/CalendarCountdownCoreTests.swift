import XCTest
@testable import CalendarCountdownCore

final class CalendarCountdownCoreTests: XCTestCase {
    func testReleaseVersion() {
        XCTAssertEqual(ProductConstants.version, "1.0.0")
    }

    func testCalendarDayCountdown() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(DateSupport.parseDateOnly("2026-08-30", calendar: calendar))
        let target = try XCTUnwrap(DateSupport.parseDateOnly("2026-09-07", calendar: calendar))
        XCTAssertEqual(CountdownCalculator.daysRemaining(until: target, from: now, calendar: calendar), 8)
        XCTAssertEqual(CountdownCalculator.label(until: now, from: now, calendar: calendar), "今天")
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
            "NSCalendarsFullAccessUsageDescription"
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
        seriesIdentifier: String? = nil
    ) -> CountdownEvent {
        CountdownEvent(
            id: id,
            seriesIdentifier: seriesIdentifier,
            calendarItemIdentifier: id,
            externalIdentifier: nil,
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
