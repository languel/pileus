import Foundation

public enum ByteFormatter {
    public static func string(fromByteCount bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func percentageString(part: Int64, total: Int64) -> String {
        guard total > 0 else { return "0%" }
        let pct = (Double(part) / Double(total)) * 100.0
        if pct < 0.1 && pct > 0 {
            return "<0.1%"
        }
        return String(format: "%.1f%%", min(100.0, pct))
    }

    public static func percentage(part: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1.0, max(0.0, Double(part) / Double(total)))
    }
}
