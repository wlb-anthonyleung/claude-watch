import Foundation

/// A human-readable build timestamp shown in the UI, formatted as "yyyy.MM.dd HH:mm build".
///
/// Derived from the executable's modification date, which Xcode sets when it links the binary —
/// i.e. effectively the build time. This needs no build-phase script and updates automatically on
/// every rebuild, so the label also tells you which build is currently running. Computed once per
/// launch (the running binary can't change underneath us).
enum AppBuildInfo {
    static let label: String = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return "\(formatter.string(from: buildDate)) build"
    }()

    private static var buildDate: Date {
        guard let url = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else {
            return Date()
        }
        return modified
    }
}
