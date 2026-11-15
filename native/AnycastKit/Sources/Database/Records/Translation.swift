import Foundation
import GRDB

// MARK: - translation

public struct TranslationRow: Codable, Sendable, Equatable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "translation"
    public var id: Int64?
    public var enclosureUrl: String?
    public var status: String?
    /// JSON array of segments, same shape as subtitle.
    public var translation: String?
    /// Only one translation per episode survives (UNIQUE on enclosureUrl):
    /// switching target language replaces it (K15).
    public var language: String?

    public init(id: Int64? = nil, enclosureUrl: String? = nil, status: String? = nil,
                translation: String? = nil, language: String? = nil) {
        self.id = id
        self.enclosureUrl = enclosureUrl
        self.status = status
        self.translation = translation
        self.language = language
    }

    public var segments: [SubtitleSegment]? {
        guard let translation,
              let data = translation.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([SubtitleSegment].self, from: data)
    }
}
