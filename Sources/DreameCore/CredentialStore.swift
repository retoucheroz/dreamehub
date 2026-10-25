import Foundation
import Security

public struct StoredCredentials: Codable, Sendable {
    public var username: String
    public var password: String
    public var region: String
    public var account: CloudAccount
    public init(username: String, password: String, region: String, account: CloudAccount = .dreame) {
        self.username = username; self.password = password; self.region = region; self.account = account
    }
    private enum CodingKeys: String, CodingKey { case username, password, region, account }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        username = try values.decode(String.self, forKey: .username)
        password = try values.decode(String.self, forKey: .password)
        region = try values.decode(String.self, forKey: .region)
        account = try values.decodeIfPresent(CloudAccount.self, forKey: .account) ?? .dreame
    }
    public func matches(username: String, region: String, account: CloudAccount) -> Bool {
        self.account == account && self.region == region && (username.isEmpty || self.username == username)
    }
}

public enum CredentialStore {
    // Same record as the user's existing app; never export or log its contents.
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.okilic.dreame-mac-kumandasi",
         kSecAttrAccount as String: "dreame-login"]
    }
    public static func load() throws -> StoredCredentials? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw StoreError.status(status) }
        return try JSONDecoder().decode(StoredCredentials.self, from: data)
    }
    public static func save(_ credentials: StoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw StoreError.status(status) }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        q[kSecAttrLabel as String] = "Dreame Hub"
        let added = SecItemAdd(q as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.status(added) }
    }
    public static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.status(status) }
    }
    public enum StoreError: LocalizedError {
        case status(OSStatus)
        public var errorDescription: String? { Localization.text("macOS Anahtar Zinciri işlemi tamamlanamadı.") }
    }
}
