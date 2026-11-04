import FootyKit
import Foundation

/// Where an API key currently comes from.
enum KeySource: Equatable {
    case none
    /// The app's private key file in Application Support.
    case file
    /// Debug builds only: the project's `.env`.
    case envFile
}

/// Loads and saves the user's API keys: a private file in Application Support (no Keychain prompts).
/// Debug builds read the project's `.env` first.
struct KeyManager {
    let store = FileKeyStore()

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

    @MainActor
    func load() -> (keys: APIKeys, sources: [APIKeyKind: KeySource]) {
        let env = envURL.map(EnvFile.keys(from:)) ?? APIKeys(youTube: nil, footballData: nil)
        // Keys saved by versions that used the Keychain move to the file once.
        if !store.hasMovedFromKeychain { store.moveFromKeychain(KeychainKeyStore()) }
        var sources: [APIKeyKind: KeySource] = [:]
        func resolve(_ kind: APIKeyKind, _ fromEnv: String?) -> String? {
            if let fromEnv, !fromEnv.isEmpty {
                sources[kind] = .envFile
                return fromEnv
            }
            if let stored = store.read(kind) {
                sources[kind] = .file
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
        store.write(kind, value: value)
    }
}
