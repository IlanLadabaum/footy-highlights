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

/// API keys in the Keychain (generic passwords under the app's bundle ID).
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

    private func baseQuery(_ kind: APIKeyKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.rawValue,
        ]
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
