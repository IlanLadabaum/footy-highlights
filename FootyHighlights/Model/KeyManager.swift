import FootyKit
import Foundation

/// Where an API key currently comes from.
enum KeySource: Equatable {
    case none
    case keychain
    /// Debug builds only: the project's `.env`.
    case envFile
}

/// Loads and saves the user's API keys. Release builds use only the Keychain; Debug builds read
/// the project's `.env` first so rebuilds (which change the ad-hoc signature) don't trigger Keychain prompts.
struct KeyManager {
    let keychain = KeychainKeyStore()

    var envURL: URL? {
        #if DEBUG
            guard let dir = Bundle.main.object(forInfoDictionaryKey: "FHProjectDir") as? String, !dir.isEmpty else {
                return nil
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent(".env")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        #else
            return nil
        #endif
    }

    /// Keychain values read this launch. Each Keychain read of an ad-hoc-signed app can show a macOS
    /// permission prompt, so each key is read at most once per launch and then kept in memory.
    @MainActor private static var keychainCache: [APIKeyKind: String?] = [:]

    @MainActor
    func load() -> (keys: APIKeys, sources: [APIKeyKind: KeySource]) {
        let env = envURL.map(EnvFile.keys(from:)) ?? APIKeys(youTube: nil, footballData: nil)
        var sources: [APIKeyKind: KeySource] = [:]
        func resolve(_ kind: APIKeyKind, _ fromEnv: String?) -> String? {
            if let fromEnv, !fromEnv.isEmpty {
                sources[kind] = .envFile
                return fromEnv
            }
            let stored: String?
            if let cached = Self.keychainCache[kind] {
                stored = cached
            } else {
                stored = keychain.read(kind)
                Self.keychainCache[kind] = stored
            }
            if let stored {
                sources[kind] = .keychain
                return stored
            }
            sources[kind] = KeySource.none
            return nil
        }
        let keys = APIKeys(youTube: resolve(.youTube, env.youTube), footballData: resolve(.footballData, env.footballData))
        return (keys, sources)
    }

    @MainActor @discardableResult
    func save(_ kind: APIKeyKind, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let ok = keychain.write(kind, value: trimmed)
        if ok { Self.keychainCache[kind] = trimmed.isEmpty ? .some(nil) : trimmed }
        return ok
    }
}
