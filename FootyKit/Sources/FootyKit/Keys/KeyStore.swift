import Foundation
import Security

public enum APIKeyKind: String, CaseIterable, Sendable {
    case youTube = "youtube"
    case footballData = "football-data"

    /// Variable name in `.env`.
    public var envName: String {
        switch self {
        case .youTube: "YOUTUBE_API_KEY"
        case .footballData: "FOOTBALL_DATA_API_KEY"
        }
    }
}

public struct APIKeys: Sendable, Equatable {
    public var youTube: String?
    public var footballData: String?

    public init(youTube: String?, footballData: String?) {
        self.youTube = youTube
        self.footballData = footballData
    }
}

/// API keys in the Keychain (generic passwords under the app's bundle ID). Only used to move keys saved
/// by older versions into `FileKeyStore`.
public struct KeychainKeyStore: Sendable {
    let service: String

    public init(service: String = FootyKit.bundleIdentifier) {
        self.service = service
    }

    public func read(_ kind: APIKeyKind) -> String? {
        var query = baseQuery(kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data, let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    /// Saves the key, or deletes it when `value` is empty.
    @discardableResult
    public func write(_ kind: APIKeyKind, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        SecItemDelete(baseQuery(kind) as CFDictionary)
        guard !trimmed.isEmpty else { return true }
        var item = baseQuery(kind)
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrLabel as String] = "Footy Highlights \(kind.rawValue) API key"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    public func delete(_ kind: APIKeyKind) {
        SecItemDelete(baseQuery(kind) as CFDictionary)
    }

    private func baseQuery(_ kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
    }
}

/// API keys in a private file in Application Support (readable only by the user's account).
/// Chosen over the Keychain (2026-11-01): the app isn't signed with a stable identity, so macOS asked for
/// the login password on every launch and after every update. The keys are low-value (free, per-user API keys).
public struct FileKeyStore: Sendable {
    public let url: URL

    public init(url: URL = FileKeyStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(FootyKit.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("api-keys.json")
    }

    struct Contents: Codable {
        var keys: [String: String] = [:]
        /// Keys saved by older versions were moved out of the Keychain once.
        var movedFromKeychain = false
    }

    func contents() -> Contents {
        guard let data = try? Data(contentsOf: url), let contents = try? JSONDecoder().decode(Contents.self, from: data)
        else { return Contents() }
        return contents
    }

    public var hasMovedFromKeychain: Bool { contents().movedFromKeychain }

    public func read(_ kind: APIKeyKind) -> String? {
        contents().keys[kind.rawValue].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Saves the key, or removes it when `value` is empty.
    @discardableResult
    public func write(_ kind: APIKeyKind, value: String) -> Bool {
        var contents = contents()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        contents.keys[kind.rawValue] = trimmed.isEmpty ? nil : trimmed
        return save(contents)
    }

    /// One-time move of keys saved by older versions in the Keychain. Each Keychain access may still show
    /// macOS's password prompt this one last time.
    public func moveFromKeychain(_ keychain: KeychainKeyStore) {
        var contents = contents()
        guard !contents.movedFromKeychain else { return }
        for kind in APIKeyKind.allCases where contents.keys[kind.rawValue] == nil {
            if let value = keychain.read(kind) { contents.keys[kind.rawValue] = value }
        }
        contents.movedFromKeychain = true
        guard save(contents) else { return }
        for kind in APIKeyKind.allCases { keychain.delete(kind) }
    }

    private func save(_ contents: Contents) -> Bool {
        let manager = FileManager.default
        let dir = url.deletingLastPathComponent()
        do {
            try manager.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(contents)
            try data.write(to: url, options: [.atomic])
            // Owner read/write only.
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}

/// Reads `KEY=value` lines from a `.env` file (developer builds only).
public enum EnvFile {
    public static func load(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "export ", with: "")
            var value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { values[key] = value }
        }
        return values
    }

    public static func keys(from url: URL) -> APIKeys {
        let values = load(url)
        return APIKeys(youTube: values[APIKeyKind.youTube.envName], footballData: values[APIKeyKind.footballData.envName])
    }
}
