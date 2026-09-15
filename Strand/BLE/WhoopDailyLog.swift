import Foundation
import CoreBluetooth

/// Append-only daily JSONL sidecar for raw WHOOP Bluetooth notifications.
///
/// Location: `<Application Support>/OpenWhoop/Diagnostics/whoop-raw-YYYY-MM-DD.jsonl`.
/// The file name is the rotation policy: a new app-private file is opened on first WHOOP notification for
/// each local calendar day. Nothing reads this back for scoring; it is a diagnostics/research corpus and is
/// safe to delete.
final class WhoopDailyLog {
    private let log: (String) -> Void
    private let directory: URL?
    private let calendar: Calendar
    private var announcedDays: Set<String> = []
    private var failedDays: Set<String> = []

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(log: @escaping (String) -> Void, directory: URL? = nil,
         calendar: Calendar = .autoupdatingCurrent) {
        self.log = log
        self.directory = directory
        self.calendar = calendar
    }

    func recordNotification(bytes: [UInt8], characteristic: CBUUID, family: String,
                            peripheralId: String?, isBackfilling: Bool, at date: Date = Date()) {
        guard !bytes.isEmpty else { return }
        let day = dayString(for: date)
        guard let url = resolveURL(forDay: day) else { return }

        let line = Self.line(
            utcMs: Int64(date.timeIntervalSince1970 * 1000),
            iso: Self.iso.string(from: date),
            localDay: day,
            family: family,
            characteristic: characteristic.uuidString.lowercased(),
            peripheralId: peripheralId.map(Self.safeIdentifier),
            isBackfilling: isBackfilling,
            bytes: bytes)
        guard let data = (line + "\n").data(using: .utf8) else { return }

        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            handle.write(data)
        } catch {
            if failedDays.insert(day).inserted {
                log("WHOOP raw daily log write failed for \(day) - \(error.localizedDescription)")
            }
            return
        }

        if announcedDays.insert(day).inserted {
            log("WHOOP raw daily log -> \(url.path) [raw BLE notifications, JSONL, rotates daily]")
        }
    }

    private func dayString(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func resolveURL(forDay day: String) -> URL? {
        do {
            let dir: URL
            if let directory {
                dir = directory
            } else {
                let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                       appropriateFor: nil, create: true)
                dir = base.appendingPathComponent("OpenWhoop/Diagnostics", isDirectory: true)
            }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("whoop-raw-\(day).jsonl")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            return url
        } catch {
            if failedDays.insert(day).inserted {
                log("WHOOP raw daily log unavailable for \(day) - \(error.localizedDescription)")
            }
            return nil
        }
    }

    static func line(utcMs: Int64, iso: String, localDay: String, family: String,
                     characteristic: String, peripheralId: String?, isBackfilling: Bool,
                     bytes: [UInt8]) -> String {
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        var parts = [
            "\"schema\":1",
            "\"utc_ms\":\(utcMs)",
            "\"iso\":\"\(jsonEscape(iso))\"",
            "\"local_day\":\"\(jsonEscape(localDay))\"",
            "\"family\":\"\(jsonEscape(family))\"",
            "\"char\":\"\(jsonEscape(characteristic))\"",
            "\"backfilling\":\(isBackfilling)",
            "\"len\":\(bytes.count)",
            "\"hex\":\"\(hex)\""
        ]
        if let peripheralId {
            parts.insert("\"peripheral\":\"\(jsonEscape(peripheralId))\"", at: 6)
        }
        return "{\(parts.joined(separator: ","))}"
    }

    private static func safeIdentifier(_ raw: String) -> String {
        raw.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }

    private static func jsonEscape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
