import Foundation

public struct YouTubeUpload: Hashable, Sendable {
    public var videoId: String
    public var title: String
    public var publishedAt: Date
}

public enum YouTubeError: Error, LocalizedError, Equatable {
    case invalidKey
    case quotaExceeded
    case http(status: Int, reason: String?)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "The YouTube API key was rejected. Check it in Settings."
        case .quotaExceeded: "The YouTube API key's daily quota is used up. Try again tomorrow."
        case .http(let status, let reason): "YouTube request failed (\(status)\(reason.map { ", \($0)" } ?? ""))."
        }
    }
}

/// YouTube Data API v3: uploads-playlist scans (1 unit per 50 videos) and duration lookups.
/// Only titles, publish dates and durations are read; descriptions and thumbnails never are.
public struct YouTubeClient: Sendable {
    let apiKey: String
    let http: HTTPClient
    let base = URL(string: "https://www.googleapis.com/youtube/v3/")!

    public init(apiKey: String, http: HTTPClient = URLSessionHTTPClient()) {
        self.apiKey = apiKey
        self.http = http
    }

    /// Uploads newest-first, stopping at the first page that reaches back past `stopDate`.
    public func uploads(playlistId: String, since stopDate: Date, maxPages: Int = 60) async throws -> [YouTubeUpload] {
        var uploads: [YouTubeUpload] = []
        var pageToken: String?
        for _ in 0..<maxPages {
            var query = [
                "part": "snippet,contentDetails", "playlistId": playlistId, "maxResults": "50",
            ]
            query["pageToken"] = pageToken
            let page: PlaylistPage = try await get("playlistItems", query: query)
            var reachedCutoff = false
            for item in page.items {
                guard let published = item.contentDetails.videoPublishedAt ?? item.snippet.publishedAt else { continue }
                if published < stopDate {
                    reachedCutoff = true
                    continue
                }
                let title = item.snippet.title
                if title == "Private video" || title == "Deleted video" { continue }
                uploads.append(YouTubeUpload(videoId: item.contentDetails.videoId, title: title, publishedAt: published))
            }
            pageToken = page.nextPageToken
            if reachedCutoff || pageToken == nil { break }
        }
        return uploads
    }

    /// Durations in seconds, looked up 50 IDs at a time (1 unit per call).
    public func durations(videoIds: [String]) async throws -> [String: Int] {
        var result: [String: Int] = [:]
        for start in stride(from: 0, to: videoIds.count, by: 50) {
            let chunk = videoIds[start..<min(start + 50, videoIds.count)]
            let page: VideosPage = try await get(
                "videos", query: ["part": "contentDetails", "id": chunk.joined(separator: ","), "maxResults": "50"])
            for item in page.items {
                if let seconds = Self.parseISODuration(item.contentDetails.duration) { result[item.id] = seconds }
            }
        }
        return result
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = (query.merging(["key": apiKey]) { $1 })
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        let (data, response) = try await http.send(request)
        guard response.statusCode == 200 else { throw Self.error(status: response.statusCode, body: data) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }

    static func error(status: Int, body: Data) -> YouTubeError {
        let reason = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error.errors?.first?.reason
        switch reason {
        case "quotaExceeded", "dailyLimitExceeded": return .quotaExceeded
        case "keyInvalid", "keyExpired": return .invalidKey
        default:
            let text = String(bytes: body, encoding: .utf8) ?? ""
            return text.contains("API key not valid") ? .invalidKey : .http(status: status, reason: reason)
        }
    }

    /// "PT1H2M3S" → 3723.
    public static func parseISODuration(_ text: String) -> Int? {
        guard text.hasPrefix("P") else { return nil }
        var total = 0
        var number = ""
        var inTime = false
        for char in text.dropFirst() {
            if char == "T" {
                inTime = true
            } else if char.isNumber {
                number.append(char)
            } else {
                guard let value = Int(number) else { return nil }
                switch (char, inTime) {
                case ("D", false): total += value * 86_400
                case ("H", true): total += value * 3600
                case ("M", true): total += value * 60
                case ("S", true): total += value
                default: return nil
                }
                number = ""
            }
        }
        return number.isEmpty ? total : nil
    }
}

private struct PlaylistPage: Decodable {
    struct Item: Decodable {
        struct Snippet: Decodable {
            var title: String
            var publishedAt: Date?
        }
        struct ContentDetails: Decodable {
            var videoId: String
            var videoPublishedAt: Date?
        }
        var snippet: Snippet
        var contentDetails: ContentDetails
    }
    var items: [Item]
    var nextPageToken: String?
}

private struct VideosPage: Decodable {
    struct Item: Decodable {
        struct ContentDetails: Decodable { var duration: String }
        var id: String
        var contentDetails: ContentDetails
    }
    var items: [Item]
}

private struct ErrorBody: Decodable {
    struct Inner: Decodable {
        struct Detail: Decodable { var reason: String? }
        var errors: [Detail]?
    }
    var error: Inner
}
