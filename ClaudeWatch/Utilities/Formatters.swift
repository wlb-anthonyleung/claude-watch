import Foundation

enum Formatters {
    static func formatCost(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    static func formatTokenCount(_ count: Int) -> String {
        switch count {
        case 0..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let value = Double(count) / 1_000.0
            return String(format: "%.1fK", value)
        case 1_000_000..<1_000_000_000:
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        default:
            let value = Double(count) / 1_000_000_000.0
            return String(format: "%.1fB", value)
        }
    }

    /// Formats a number compactly for table display (e.g., 134.1K, 1.2M).
    static func formatCompactNumber(_ count: Int) -> String {
        switch count {
        case 0:
            return "-"
        case 1..<1_000:
            return "\(count)"
        case 1_000..<1_000_000:
            let value = Double(count) / 1_000.0
            return String(format: "%.1fK", value)
        case 1_000_000..<1_000_000_000:
            let value = Double(count) / 1_000_000.0
            return String(format: "%.1fM", value)
        default:
            let value = Double(count) / 1_000_000_000.0
            return String(format: "%.1fB", value)
        }
    }

    static func formatModelName(_ rawName: String) -> String {
        let mapping: [String: String] = [
            "claude-opus-4-5-20251101": "Opus 4.5",
            "claude-sonnet-4-5-20250514": "Sonnet 4.5",
            "claude-haiku-4-5-20251001": "Haiku 4.5",
            "claude-sonnet-4-20250514": "Sonnet 4",
            "claude-haiku-3-5-20241022": "Haiku 3.5",
        ]

        if let friendly = mapping[rawName] {
            return friendly
        }

        // Fallback: extract model family and version from the name
        let name = rawName
            .replacingOccurrences(of: "claude-", with: "")
            .components(separatedBy: "-")

        if name.count >= 2 {
            let family = name[0].capitalized
            let version = name[1...].prefix(while: { !$0.allSatisfy(\.isNumber) || $0.contains(".") })
                .joined(separator: " ")
            if !version.isEmpty {
                return "\(family) \(version)"
            }
            return family
        }

        return rawName
    }

    static func formatDateString(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .none
        return outputFormatter.string(from: date)
    }

    static func todayDateString() -> String {
        dateString(from: Date())
    }

    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func shortDateLabel(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "d MMM"
        return outputFormatter.string(from: date)
    }

    static func ddmmDateLabel(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "dd-MM"
        return outputFormatter.string(from: date)
    }

    /// Converts "yyyy-MM" to "January 2026"
    static func formatMonthLabel(_ yearMonth: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM"

        guard let date = inputFormatter.date(from: yearMonth) else {
            return yearMonth
        }

        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMMM yyyy"
        return outputFormatter.string(from: date)
    }
}
