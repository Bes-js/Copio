import Foundation
import Security
import LocalAuthentication

enum KeychainService {
    private static let service = "com.clipcollections.secrets"

    static func store(_ value: String, id: UUID) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.operation(status) }
    }

    static func retrieve(id: UUID, authenticate: Bool) async throws -> String {
        if authenticate {
            let context = LAContext()
            let canAuthenticate = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
            guard canAuthenticate else { throw KeychainError.authenticationUnavailable }
            let passed = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Access a saved secret")
            guard passed else { throw KeychainError.authenticationFailed }
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.operation(status)
        }
        return value
    }

    static func delete(id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case operation(OSStatus), authenticationUnavailable, authenticationFailed
    var errorDescription: String? {
        switch self {
        case .operation: "Keychain could not complete the request."
        case .authenticationUnavailable: "Mac authentication is unavailable."
        case .authenticationFailed: "Authentication was not completed."
        }
    }
}
