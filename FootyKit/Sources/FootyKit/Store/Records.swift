import Foundation
import SwiftData

/// A highlight video (only titles that parse as match highlights are stored).
@Model
public final class VideoRecord {
    @Attribute(.unique) public var videoId: String
    public var channelKey: String
    public var originalTitle: String
    public var publishedAt: Date
    public var durationSeconds: Int?
    /// Last time the API returned this video (YouTube data must be refreshed within 30 days).
    public var lastSeenAt: Date

    init(_ video: Video, seenAt: Date) {
        videoId = video.id
        channelKey = video.channelKey
        originalTitle = video.originalTitle
        publishedAt = video.publishedAt
        durationSeconds = video.durationSeconds
        lastSeenAt = seenAt
    }

    var video: Video {
        Video(
            id: videoId, channelKey: channelKey, originalTitle: originalTitle, publishedAt: publishedAt,
            durationSeconds: durationSeconds)
    }
}

/// A fixture from football-data, stored as JSON plus the fields used to query it.
@Model
public final class FixtureRecord {
    @Attribute(.unique) public var fixtureId: Int
    public var competitionId: String
    public var season: Int
    public var payload: Data

    init(_ fixture: Fixture, payload: Data) {
        fixtureId = fixture.id
        competitionId = fixture.competitionId
        season = fixture.season
        self.payload = payload
    }
}

/// Watched / revealed state for one match key ("f:<fixture>" or "v:<video>").
@Model
public final class FlagRecord {
    @Attribute(.unique) public var key: String
    public var watched: Bool
    public var revealed: Bool
    public var updatedAt: Date

    init(key: String, flags: MatchFlags, at date: Date) {
        self.key = key
        watched = flags.watched
        revealed = flags.revealed
        updatedAt = date
    }
}

/// The extended / normal cut picked on a match row ("f:<fixture>").
@Model
public final class CutChoiceRecord {
    @Attribute(.unique) public var key: String
    public var cut: String

    init(key: String, cut: HighlightCut) {
        self.key = key
        self.cut = cut.rawValue
    }
}

/// Refresh bookkeeping: last fetch times and scan markers.
@Model
public final class SyncRecord {
    @Attribute(.unique) public var key: String
    public var date: Date
    public var note: String?

    init(key: String, date: Date, note: String? = nil) {
        self.key = key
        self.date = date
        self.note = note
    }
}

/// Cached current-standings rows, used only to detect point deductions.
@Model
public final class StandingsRecord {
    @Attribute(.unique) public var key: String
    public var payload: Data
    public var fetchedAt: Date

    init(key: String, payload: Data, fetchedAt: Date) {
        self.key = key
        self.payload = payload
        self.fetchedAt = fetchedAt
    }
}
