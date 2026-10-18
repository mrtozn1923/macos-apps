import Foundation
import Security

/// Stores secret header values in the login Keychain.
enum SecretStore {
    private static let service: String = "com.mertozen.nabiztut"

    private static func account(_ monitorID: UUID, _ header: String) -> String {
        "\(monitorID.uuidString).\(header.lowercased())"
    }

    static func set(_ value: String, monitorID: UUID, header: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(monitorID, header),
        ]
        SecItemDelete(base as CFDictionary)
        var item: [String: Any] = base
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(monitorID: UUID, header: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(monitorID, header),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(monitorID: UUID, header: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(monitorID, header),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
