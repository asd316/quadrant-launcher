import Foundation

/// Text for the lens row's date and size columns.
enum LensFormat {
    /// 今天 10:01 / 昨天 10:01 / 10月20日 (this year) / 2025/10/20 (earlier).
    static func dateText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(time)"
        }
        if parts.year == calendar.component(.year, from: now) {
            return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
        }
        return "\(parts.year ?? 1970)/\(parts.month ?? 1)/\(parts.day ?? 1)"
    }

    /// B below 1 KB, then KB / MB / GB (1024 steps); one decimal below 10, none from 10 up.
    static func sizeText(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(max(0, bytes)) B" }
        var value = Double(bytes) / 1024
        var units = ["KB", "MB", "GB", "TB"]
        var unit = units.removeFirst()
        while value >= 1023.95, !units.isEmpty {
            value /= 1024
            unit = units.removeFirst()
        }
        let text = value < 9.95 ? String(format: "%.1f", value) : String(format: "%.0f", value)
        return "\(text) \(unit)"
    }
}
