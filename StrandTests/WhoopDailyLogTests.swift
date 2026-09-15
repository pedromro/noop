import CoreBluetooth
import XCTest
@testable import Strand

final class WhoopDailyLogTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whoop-daily-log-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func file(_ day: String) -> URL {
        dir.appendingPathComponent("whoop-raw-\(day).jsonl")
    }

    private func lines(_ day: String) -> [String] {
        guard let text = try? String(contentsOf: file(day), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    func testWritesOneJsonLineToTheCurrentLocalDayFile() {
        var logs: [String] = []
        let dump = WhoopDailyLog(log: { logs.append($0) }, directory: dir, calendar: utcCalendar())

        dump.recordNotification(
            bytes: [0x01, 0xAB, 0x00],
            characteristic: CBUUID(string: "61080003-cbe5-4291-bd74-9cebd5ba8c4d"),
            family: "whoop4",
            peripheralId: "A/B\\C",
            isBackfilling: true,
            at: date("2026-09-15T10:11:12Z"))

        let dayLines = lines("2026-09-15")
        XCTAssertEqual(dayLines.count, 1)
        XCTAssertTrue(dayLines[0].contains(#""family":"whoop4""#))
        XCTAssertTrue(dayLines[0].contains(#""char":"61080003-cbe5-4291-bd74-9cebd5ba8c4d""#))
        XCTAssertTrue(dayLines[0].contains(#""peripheral":"A_B_C""#))
        XCTAssertTrue(dayLines[0].contains(#""backfilling":true"#))
        XCTAssertTrue(dayLines[0].contains(#""len":3"#))
        XCTAssertTrue(dayLines[0].contains(#""hex":"01ab00""#))
        XCTAssertEqual(logs.count, 1, "the path announcement is emitted once for the day")
    }

    func testRotatesByCalendarDayWithoutRenamingThePreviousFile() {
        let dump = WhoopDailyLog(log: { _ in }, directory: dir, calendar: utcCalendar())

        dump.recordNotification(bytes: [0xAA], characteristic: BLEManager.dataNotifyChar,
                                family: "whoop4", peripheralId: nil, isBackfilling: false,
                                at: date("2026-09-15T23:59:59Z"))
        dump.recordNotification(bytes: [0xBB], characteristic: BLEManager.dataNotifyChar,
                                family: "whoop4", peripheralId: nil, isBackfilling: false,
                                at: date("2026-09-16T00:00:00Z"))

        XCTAssertEqual(lines("2026-09-15").count, 1)
        XCTAssertEqual(lines("2026-09-16").count, 1)
        XCTAssertTrue(lines("2026-09-15")[0].contains(#""hex":"aa""#))
        XCTAssertTrue(lines("2026-09-16")[0].contains(#""hex":"bb""#))
    }

    func testWhoopCharacteristicClassifierCoversCustomAndPuffinPaths() {
        XCTAssertTrue(BLEManager.isWhoopDataCharacteristic(BLEManager.dataNotifyChar))
        XCTAssertTrue(BLEManager.isWhoopDataCharacteristic(BLEManager.cmdNotifyChar))
        XCTAssertTrue(BLEManager.isWhoopDataCharacteristic(BLEManager.eventNotifyChar))
        XCTAssertTrue(BLEManager.isWhoopDataCharacteristic(BLEManager.whoop5NotifyChars[0]))
        XCTAssertFalse(BLEManager.isWhoopDataCharacteristic(CBUUID(string: "00002A00-0000-1000-8000-00805F9B34FB")))
    }
}
