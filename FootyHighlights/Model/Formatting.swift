import FootyKit
import Foundation

enum Formatting {
    /// 581 → "9:41"; 3723 → "1:02:03".
    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    static func kickoff(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func dateRange(_ start: Date, _ end: Date) -> String {
        if Calendar.current.isDate(start, inSameDayAs: end) { return day(start) }
        return "\(day(start)) – \(day(end))"
    }

    /// "0.1.0 (1)" from Info.plist.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    static func status(_ status: MatchStatus) -> String {
        switch status {
        case .postponed: "Postponed"
        case .cancelled: "Cancelled"
        case .suspended: "Suspended"
        default: status.rawValue.capitalized
        }
    }

    static func youTubeURL(_ video: Video) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(video.id)")!
    }

    static let readmeURL = URL(string: "https://github.com/IlanLadabaum/footy-highlights#readme")!
    static let youTubeKeyURL = URL(string: "https://console.cloud.google.com/apis/credentials")!
    static let youTubeAPIURL = URL(string: "https://console.cloud.google.com/apis/library/youtube.googleapis.com")!
    static let footballDataKeyURL = URL(string: "https://www.football-data.org/client/register")!
}
