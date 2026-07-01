import Foundation
import Security

protocol SecureSessionStoring {
    func load() -> SupabaseSession?
    func save(_ session: SupabaseSession) throws
    func loadTrustedUntil() -> Date?
    func saveTrustedUntil(_ date: Date) throws
    func clearTrustedUntil()
    func clear()
}

extension SecureSessionStoring {
    func loadTrustedUntil() -> Date? { nil }
    func saveTrustedUntil(_ date: Date) throws {}
    func clearTrustedUntil() {}
}

struct KeychainSessionStore: SecureSessionStoring {
    private let service = "com.ruicoelho.JapanTrip.supabase"
    private let account = "authenticated-session"
    private let trustedAccount = "trusted-until"

    func load() -> SupabaseSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    func save(_ session: SupabaseSession) throws {
        let data = try JSONEncoder().encode(session)
        SecItemDelete(query(for: account) as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
        SecItemDelete(query(for: trustedAccount) as CFDictionary)
    }

    func loadTrustedUntil() -> Date? {
        var query = query(for: trustedAccount)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Date.self, from: data)
    }

    func saveTrustedUntil(_ date: Date) throws {
        let data = try JSONEncoder().encode(date)
        clearTrustedUntil()
        var query = query(for: trustedAccount)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func clearTrustedUntil() {
        SecItemDelete(query(for: trustedAccount) as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        query(for: account)
    }

    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
