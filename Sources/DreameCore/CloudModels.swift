import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(any: Any) throws {
        let data = try JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed])
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }
    public var anyValue: Any {
        switch self {
        case .object(let x): return x.mapValues { $0.anyValue }
        case .array(let x): return x.map { $0.anyValue }
        case .string(let x): return x
        case .number(let x): return NSNumber(value:x)
        case .bool(let x): return x
        case .null: return NSNull()
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public var object: [String:JSONValue]? { if case .object(let x) = self { return x }; return nil }
    public var array: [JSONValue]? { if case .array(let x) = self { return x }; return nil }
    public var string: String? {
        switch self { case .string(let x): return x; case .number(let x): return x.rounded() == x ? String(format:"%.0f", x) : String(x); default: return nil }
    }
    public var int: Int? { if case .number(let x) = self, x.isFinite, x >= Double(Int.min), x < Double(Int.max) { return Int(x) }; return string.flatMap(Int.init) }
    public var bool: Bool? { if case .bool(let x) = self { return x }; return nil }
    public static func integer(_ x: Int) -> JSONValue { .number(Double(x)) }
    public func data() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct CloudSession: Sendable {
    public let userID: String
    public let country: String
    public let expiresAt: Date
}

public struct CloudDevice: Sendable, Identifiable {
    public let id: String
    public let model: String
    public let name: String
    public let ownerID: String
    public let bindDomain: String
    public let raw: JSONValue
    public init(raw: JSONValue) throws {
        guard let id = raw["did"].string, let model = raw["model"].string else { throw CloudError.invalidResponse }
        self.id = id; self.model = model
        self.name = raw["customName"].string.flatMap { $0.isEmpty ? nil : $0 } ?? raw["deviceInfo"]["displayName"].string ?? model
        self.ownerID = raw["masterUid"].string ?? ""
        self.bindDomain = raw["bindDomain"].string ?? ""
        self.raw = raw
    }
}

public enum CloudError: Error, LocalizedError, Sendable {
    case invalidRegion, notAuthenticated, authenticationRejected, invalidResponse, server(Int), api(Int), invalidURL, cryptoFailure, commandResultUnknown
    public var errorDescription: String? {
        switch self {
        case .invalidRegion: return Localization.text("Sunucu bölgesi geçersiz.")
        case .notAuthenticated: return Localization.text("Dreame hesabına giriş gerekli.")
        case .authenticationRejected: return Localization.text("Dreame oturumu kabul edilmedi.")
        case .invalidResponse: return Localization.text("Dreame yanıtı beklenen biçimde değil.")
        case .server(let code): return Localization.text("Dreame sunucusu HTTP {code} döndürdü.",["code":String(code)])
        case .api(let code): return Localization.text("Dreame isteği reddedildi ({code}).",["code":String(code)])
        case .invalidURL: return Localization.text("Dosya adresi güvenli değil veya geçersiz.")
        case .cryptoFailure: return Localization.text("Dreame istek imzası hazırlanamadı.")
        case .commandResultUnknown: return Localization.text("Komut sonucu doğrulanamadı; otomatik tekrar gönderilmedi.")
        }
    }
}
