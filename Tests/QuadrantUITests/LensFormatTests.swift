import Foundation
import Testing

@testable import QuadrantUI

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 10, _ min: Int = 1) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private let now = date(2026, 10, 22, 15, 30)

@Test func todayAndYesterdayShowTime() {
    #expect(LensFormat.dateText(date(2026, 10, 22, 10, 1), now: now, calendar: calendar) == "今天 10:01")
    #expect(LensFormat.dateText(date(2026, 10, 21, 9, 5), now: now, calendar: calendar) == "昨天 09:05")
}

@Test func thisYearShowsMonthAndDay() {
    #expect(LensFormat.dateText(date(2026, 10, 20), now: now, calendar: calendar) == "10月20日")
    #expect(LensFormat.dateText(date(2026, 1, 3), now: now, calendar: calendar) == "1月3日")
}

@Test func earlierYearsShowFullDate() {
    #expect(LensFormat.dateText(date(2025, 10, 20), now: now, calendar: calendar) == "2025/10/20")
}

@Test func yesterdayAcrossYearBoundary() {
    let newYear = date(2026, 1, 1, 8, 0)
    #expect(LensFormat.dateText(date(2025, 12, 31, 23, 59), now: newYear, calendar: calendar) == "昨天 23:59")
}

@Test func sizesUseUnitsWithOneDecimalBelowTen() {
    #expect(LensFormat.sizeText(0) == "0 B")
    #expect(LensFormat.sizeText(900) == "900 B")
    #expect(LensFormat.sizeText(1536) == "1.5 KB")
    #expect(LensFormat.sizeText(20 * 1024) == "20 KB")
    #expect(LensFormat.sizeText(Int64(2.5 * 1024 * 1024)) == "2.5 MB")
    #expect(LensFormat.sizeText(120 * 1024 * 1024) == "120 MB")
    #expect(LensFormat.sizeText(Int64(3.2 * 1024 * 1024 * 1024)) == "3.2 GB")
    #expect(LensFormat.sizeText(1024 * 1024 - 1) == "1.0 MB")
}
