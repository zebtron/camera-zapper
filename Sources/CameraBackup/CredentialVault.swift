import Foundation
import Security

/// Stores all Camera Zapper API credentials behind one Keychain ACL. This is
/// especially important for locally signed beta builds: macOS may ask the user
/// to approve access again after an app rebuild, and one vault means one prompt
/// instead of one prompt for every provider token.
final class CameraZapperCredentialVault: @unchecked Sendable {
    static let shared = CameraZapperCredentialVault()

    private let lock = NSLock()
    private let service = "com.zebtron.CameraZapper"
    private let vaultAccount = "credential.vault.v1"
    private var cached: [String: Data]?

    private init() {}

    func save(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        var vault = loadVaultLocked()
        vault[account] = data
        try saveVaultLocked(vault)
        cached = vault
    }

    func load(_ account: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        var vault = loadVaultLocked()
        if let data = vault[account] { return data }

        // One-time migration from versions <= 1.337. Each old record can ask
        // once on the first upgraded run; after migration all records live in
        // the single vault and subsequent runs use one Keychain access.
        guard let legacy = loadKeychainItem(account: account) else { return nil }
        vault[account] = legacy
        try? saveVaultLocked(vault)
        cached = vault
        return legacy
    }

    func remove(_ accounts: [String]) throws {
        lock.lock(); defer { lock.unlock() }
        var vault = loadVaultLocked()
        for account in accounts {
            vault.removeValue(forKey: account)
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let status = SecItemDelete(legacyQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialVaultError.keychain(status)
            }
        }
        try saveVaultLocked(vault)
        cached = vault
    }

    private func loadVaultLocked() -> [String: Data] {
        if let cached { return cached }
        guard let data = loadKeychainItem(account: vaultAccount),
              let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) else {
            cached = [:]
            return [:]
        }
        cached = decoded
        return decoded
    }

    private func saveVaultLocked(_ vault: [String: Data]) throws {
        let data = try PropertyListEncoder().encode(vault)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: vaultAccount
        ]
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecSuccess { return }
        var add = query
        add[kSecValueData as String] = data
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialVaultError.keychain(status) }
    }

    private func loadKeychainItem(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }
}

enum CredentialVaultError: Error {
    case keychain(OSStatus)
}
