import Foundation
import Security

// Keychain 存 JWT（B1）；kSecAttrAccessibleAfterFirstUnlock 讓背景更新也讀得到
enum Keychain {
    private static let service = "com.aifactory.dashboard"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
    static func get(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}

// 離線快取（B10）：Caches/ 目錄一鍵一 JSON 檔
enum DiskCache {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("aif", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func url(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "?", with: "_")
        return dir.appendingPathComponent(safe + ".json")
    }
    static func save<T: Encodable>(_ v: T, key: String) {
        if let d = try? JSONEncoder().encode(v) { try? d.write(to: url(key), options: .atomic) }
    }
    static func load<T: Decodable>(_ t: T.Type, key: String) -> T? {
        guard let d = try? Data(contentsOf: url(key)) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }
    static func age(key: String) -> TimeInterval? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url(key).path),
              let m = a[.modificationDate] as? Date else { return nil }
        return Date().timeIntervalSince(m)
    }
    static func clear() {
        try? FileManager.default.removeItem(at: dir)
    }
    static var sizeBytes: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}
