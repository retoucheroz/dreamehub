import Foundation
import CryptoKit
import Darwin

public struct VoiceServiceError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

public struct VoicePack: Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let md5: String
    public let size: Int
    public var installValue: [String: Any] { ["id": id, "url": url.absoluteString, "md5": md5, "size": size] }
}

public struct BuiltVoicePack: Sendable {
    public let data: Data
    public let md5: String
    public let changedCount: Int
}

/// Model-specific official manifests and local voice editing, without Python.
/// The caller owns device install commands and the LAN download server.
public actor VoiceService {
    public static let maxPackBytes = 20 * 1024 * 1024
    public static let maxAudioBytes = 12 * 1024 * 1024
    private let model: String
    private let labels: [String: [String: String]]
    private let englishLabels: [String: [String: String]]
    private let vorbisLibrary: URL?
    private var packs: [String: VoicePack]?
    private var files: [String: Data]?
    private var replacements: [String: Data] = [:]

    public init(model: String, labelsURL: URL? = nil, englishLabelsURL: URL? = nil, vorbisLibraryURL: URL? = nil) throws {
        guard model.range(of: "^dreame\\.vacuum\\.[a-z0-9_-]+$", options: .regularExpression) != nil else {
            throw VoiceServiceError(Localization.text("Cihaz model kodu geçerli değil."))
        }
        self.model = model
        self.labels = Self.labelTable(labelsURL)
        self.englishLabels = Self.labelTable(englishLabelsURL)
        self.vorbisLibrary = ([vorbisLibraryURL, Bundle.main.resourceURL?.appendingPathComponent("native/libsndfile_arm64.dylib"),
                              URL(fileURLWithPath: "/opt/homebrew/lib/libsndfile.dylib")].compactMap { $0 })
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public func availablePacks() async throws -> [String: VoicePack] {
        if let packs { return packs }
        let url = URL(string: "https://awsde0.fds.api.xiaomi.com/dreame-product/\(model)/voices/soundpackage.json")!
        let data = try await download(url, limit: 2 * 1024 * 1024)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any], let voices = payload["voices"] as? [[String: Any]] else {
            throw VoiceServiceError(Localization.text("Bu modelin resmî ses listesi okunamadı."))
        }
        var result: [String: VoicePack] = [:]
        for voice in voices {
            guard let id = voice["id"] as? String, !id.isEmpty,
                  let address = voice["download"] as? String, let url = URL(string: address),
                  url.scheme == "https", url.host != nil,
                  let digest = voice["md5sum"] as? String,
                  digest.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else { continue }
            let size = (voice["size"] as? NSNumber)?.intValue ?? Int(voice["size"] as? String ?? "") ?? 0
            guard size > 0, size <= Self.maxPackBytes else { continue }
            let name = (voice["name"] as? [String: Any])?["default"] as? String ?? id
            result[id.uppercased()] = VoicePack(id: id.uppercased(), name: name, url: url, md5: digest, size: size)
        }
        guard !result.isEmpty else { throw VoiceServiceError(Localization.text("Bu model için geçerli resmî ses paketi bulunamadı.")) }
        packs = result
        return result
    }

    public func pack(language: String) async throws -> VoicePack {
        guard let pack = try await availablePacks()[language.uppercased()] else {
            throw VoiceServiceError(Localization.text("Bu dil paketi bağlı modelde bulunmuyor."))
        }
        return pack
    }

    private func load() async throws {
        if files != nil { return }
        let pack = try await pack(language: "TR")
        let compressed = try await download(pack.url, limit: Self.maxPackBytes)
        guard compressed.count == pack.size, Self.md5(compressed) == pack.md5 else {
            throw VoiceServiceError(Localization.text("Resmî ses paketinin bütünlük kontrolü başarısız."))
        }
        let folder = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = folder.appendingPathComponent("official.tar.gz")
        try compressed.write(to: archive)
        let tar = try Self.run(URL(fileURLWithPath: "/usr/bin/gzip"), ["-dc", archive.path], limit: 100 * 1024 * 1024)
        let result = try Self.parseTar(tar)
        guard result["tts.json"] != nil, result.keys.contains(where: Self.isSoundName) else {
            throw VoiceServiceError(Localization.text("Ses paketinin içeriği beklenen biçimde değil."))
        }
        files = result
    }

    private static func labelTable(_ url: URL?) -> [String: [String: String]] {
        url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: [String: String]].self, from: $0) } ?? [:]
    }

    public func catalog() async throws -> [String: Any] {
        try await load()
        let labels = Localization.language == "en" && !englishLabels.isEmpty ? englishLabels : self.labels
        let ids = (files ?? [:]).keys.filter(Self.isSoundName).map { String($0.dropLast(4)) }.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }
        let sounds: [[String: Any]] = ids.map { id in
            ["id": id, "label": labels[id]?["name"] ?? Localization.text("Ses kaydı {id}",["id":id]),
             "transcript": labels[id]?["transcript"] ?? Localization.text("Konuşma metni doğrulanmamış."),
             "confidence": labels[id]?["confidence"] ?? "unknown", "changed": replacements[id] != nil]
        }
        let options = try await availablePacks().values.sorted { $0.id < $1.id }.map { ["id": $0.id, "name": $0.name] }
        return ["sounds": sounds, "changed_count": replacements.count, "packs": options,
                "conversion_available": vorbisLibrary != nil]
    }

    public func audio(id: String) async throws -> Data {
        try await load()
        guard Self.isSoundID(id), let original = files?[id + ".ogg"] else { throw VoiceServiceError(Localization.text("Ses kaydı bulunamadı.")) }
        return replacements[id] ?? original
    }

    public func replace(id: String, payload: Data) async throws -> [String: Any] {
        _ = try await audio(id: id)
        guard !payload.isEmpty, payload.count <= Self.maxAudioBytes else { throw VoiceServiceError(Localization.text("Ses dosyası boş veya 12 MB sınırını aşıyor.")) }
        guard let vorbisLibrary else {
            throw VoiceServiceError(Localization.text("Yerel ses kodlayıcısı bulunamadı. Uygulama paketindeki native/libsndfile kitaplığını kontrol et."))
        }
        let folder = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input-audio"), output = folder.appendingPathComponent("converted.ogg")
        try payload.write(to: input)
        let pcmData = try Self.readMono16k(input, library: vorbisLibrary)
        try Self.writeVorbis(pcmData, to: output, library: vorbisLibrary)
        let converted = try Data(contentsOf: output)
        guard converted.starts(with: Data("OggS".utf8)), converted.count <= Self.maxAudioBytes else { throw VoiceServiceError(Localization.text("Ses cihaz biçimine dönüştürülemedi.")) }
        replacements[id] = converted
        return ["id": id, "changed_count": replacements.count, "bytes": converted.count]
    }

    public func reset(id: String) async throws -> Int {
        _ = try await audio(id: id)
        replacements.removeValue(forKey: id)
        return replacements.count
    }

    public func build() async throws -> BuiltVoicePack {
        try await load()
        guard !replacements.isEmpty else { throw VoiceServiceError(Localization.text("Önce en az bir anonsu değiştir.")) }
        var edited = files ?? [:]
        for (id, payload) in replacements { edited[id + ".ogg"] = payload }
        let tar = try Self.makeTar(edited)
        let folder = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("custom.tar")
        try tar.write(to: file)
        let payload = try Self.run(URL(fileURLWithPath: "/usr/bin/gzip"), ["-n", "-c", file.path], limit: Self.maxPackBytes)
        return BuiltVoicePack(data: payload, md5: Self.md5(payload), changedCount: replacements.count)
    }

    private func download(_ url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 45)
        request.setValue("Dreamehome/2.4.7", forHTTPHeaderField: "User-Agent")
        request.setValue("https://awsde0.fds.api.xiaomi.com/", forHTTPHeaderField: "Referer")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              response.url?.scheme == "https" else { throw VoiceServiceError(Localization.text("Resmî ses kaynağına ulaşılamadı.")) }
        guard response.expectedContentLength <= limit else { throw VoiceServiceError(Localization.text("Ses paketi boyut sınırını aşıyor.")) }
        var result = Data()
        for try await byte in bytes {
            result.append(byte)
            if result.count > limit { throw VoiceServiceError(Localization.text("Ses paketi boyut sınırını aşıyor.")) }
        }
        return result
    }

    private static func isSoundID(_ value: String) -> Bool { !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) } }
    private static func isSoundName(_ value: String) -> Bool { value.hasSuffix(".ogg") && isSoundID(String(value.dropLast(4))) }
    private static func md5(_ data: Data) -> String { Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    /// Decode with the same native codec used by the previous application, but without
    /// its Python wrapper. Channel mix, resampling and peak limiting are Swift.
    private static func readMono16k(_ input: URL, library: URL) throws -> Data {
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else { throw VoiceServiceError(Localization.text("Yerel ses çözücüsü yüklenemedi.")) }
        defer { dlclose(handle) }
        typealias Open = @convention(c) (UnsafePointer<CChar>, Int32, UnsafeMutableRawPointer) -> OpaquePointer?
        typealias Read = @convention(c) (OpaquePointer, UnsafeMutablePointer<Float>, Int64) -> Int64
        typealias Close = @convention(c) (OpaquePointer) -> Int32
        guard let openSymbol = dlsym(handle, "sf_open"), let readSymbol = dlsym(handle, "sf_readf_float"), let closeSymbol = dlsym(handle, "sf_close") else {
            throw VoiceServiceError(Localization.text("Yerel ses çözücüsünün arayüzü eksik."))
        }
        let open = unsafeBitCast(openSymbol, to: Open.self), read = unsafeBitCast(readSymbol, to: Read.self), close = unsafeBitCast(closeSymbol, to: Close.self)
        let info = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        defer { info.deallocate() }
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
        guard let file = input.path.withCString({ open($0, 0x10, info) }) else { throw VoiceServiceError(Localization.text("Ses dosyası okunamadı. OGG, WAV veya FLAC kullan.")) }
        defer { _ = close(file) }
        let frames = info.load(as: Int64.self), rate = Int(info.load(fromByteOffset: 8, as: Int32.self)), channels = Int(info.load(fromByteOffset: 12, as: Int32.self))
        guard rate > 0, rate <= 384000, channels > 0, channels <= 32,
              frames > 0, Double(frames) / Double(rate) >= 0.15, Double(frames) / Double(rate) <= 45,
              frames <= 24_000_000 / Int64(channels) else { throw VoiceServiceError(Localization.text("Anons 0,15–45 saniye olmalı; ses biçimi veya kanal sayısı geçersiz.")) }
        var decoded = [Float](repeating: 0, count: Int(frames) * channels)
        let received = decoded.withUnsafeMutableBufferPointer { read(file, $0.baseAddress!, frames) }
        guard received == frames else { throw VoiceServiceError(Localization.text("Ses dosyası tam okunamadı.")) }
        var mono = [Float](repeating: 0, count: Int(frames))
        for i in mono.indices {
            var sum: Float = 0
            for channel in 0..<channels { let value = decoded[i * channels + channel]; guard value.isFinite else { throw VoiceServiceError(Localization.text("Ses dosyası geçersiz örnekler içeriyor.")) }; sum += value }
            mono[i] = sum / Float(channels)
        }
        let count = max(1, Int((Double(frames) * 16000 / Double(rate)).rounded()))
        var resampled = [Float](repeating: 0, count: count), peak: Float = 0
        for i in resampled.indices {
            let position = count == 1 ? 0 : Double(i) * Double(mono.count - 1) / Double(count - 1)
            let low = Int(position), high = min(low + 1, mono.count - 1), fraction = Float(position - Double(low))
            resampled[i] = mono[low] + (mono[high] - mono[low]) * fraction
            peak = max(peak, abs(resampled[i]))
        }
        let gain: Float = peak > 0.98 ? 0.95 / peak : 1
        var output = Data(capacity: count * 2)
        for value in resampled {
            let sample = Int16(max(-32768, min(32767, Int((value * gain * 32767).rounded()))))
            let bits = UInt16(bitPattern: sample)
            output.append(UInt8(bits & 255)); output.append(UInt8(bits >> 8))
        }
        return output
    }
    /// Native libsndfile C ABI. This shared library contains no Python runtime.
    private static func writeVorbis(_ pcm: Data, to output: URL, library: URL) throws {
        guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else { throw VoiceServiceError(Localization.text("Yerel Vorbis kodlayıcısı yüklenemedi.")) }
        defer { dlclose(handle) }
        typealias Open = @convention(c) (UnsafePointer<CChar>, Int32, UnsafeMutableRawPointer) -> OpaquePointer?
        typealias Write = @convention(c) (OpaquePointer, UnsafePointer<Int16>, Int64) -> Int64
        typealias Close = @convention(c) (OpaquePointer) -> Int32
        guard let openSymbol = dlsym(handle, "sf_open"), let writeSymbol = dlsym(handle, "sf_writef_short"), let closeSymbol = dlsym(handle, "sf_close") else {
            throw VoiceServiceError(Localization.text("Yerel ses kodlayıcısının arayüzü eksik."))
        }
        let open = unsafeBitCast(openSymbol, to: Open.self), write = unsafeBitCast(writeSymbol, to: Write.self), close = unsafeBitCast(closeSymbol, to: Close.self)
        // SF_INFO: int64 frames; int samplerate, channels, format, sections, seekable.
        let info = UnsafeMutableRawPointer.allocate(byteCount: 32, alignment: 8)
        defer { info.deallocate() }
        info.initializeMemory(as: UInt8.self, repeating: 0, count: 32)
        info.storeBytes(of: Int32(16000), toByteOffset: 8, as: Int32.self)
        info.storeBytes(of: Int32(1), toByteOffset: 12, as: Int32.self)
        info.storeBytes(of: Int32(0x200060), toByteOffset: 16, as: Int32.self)
        guard let file = output.path.withCString({ open($0, 0x20, info) }) else { throw VoiceServiceError(Localization.text("OGG Vorbis dosyası oluşturulamadı.")) }
        var samples = [Int16](repeating: 0, count: pcm.count / 2)
        for i in samples.indices { samples[i] = Int16(bitPattern: UInt16(pcm[i * 2]) | UInt16(pcm[i * 2 + 1]) << 8) }
        let written = samples.withUnsafeBufferPointer { write(file, $0.baseAddress!, Int64($0.count)) }
        let result = close(file)
        guard written == samples.count, result == 0 else { throw VoiceServiceError(Localization.text("OGG Vorbis kodlama tamamlanamadı.")) }
    }
    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dreame-voice-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
    private static func run(_ executable: URL, _ arguments: [String], limit: Int) throws -> Data {
        let process = Process(), pipe = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice; process.standardInput = FileHandle.nullDevice
        try process.run()
        var data = Data()
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            data.append(chunk)
            if data.count > limit { process.terminate(); process.waitUntilExit(); throw VoiceServiceError(Localization.text("Ses işleme boyut sınırını aştı.")) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw VoiceServiceError(Localization.text("Ses dosyası işlenemedi; dosya biçimini kontrol et.")) }
        return data
    }

    /// Strict root-only regular-file USTAR reader; never extracts paths or links.
    public static func parseTar(_ data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        var offset = 0, files: [String: Data] = [:]
        func field(_ start: Int, _ count: Int) -> String {
            String(bytes: bytes[start..<(start + count)].prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
        while offset + 512 <= bytes.count {
            if bytes[offset..<(offset + 512)].allSatisfy({ $0 == 0 }) { break }
            let name = field(offset, 100), prefix = field(offset + 345, 155)
            let checksum = field(offset + 148, 8).trimmingCharacters(in: .whitespacesAndNewlines)
            var computed = 0
            for i in 0..<512 { computed += (148..<156).contains(i) ? 32 : Int(bytes[offset + i]) }
            guard Int(checksum, radix: 8) == computed else { throw VoiceServiceError(Localization.text("Ses arşivi başlık kontrolü başarısız.")) }
            guard let size = Int(field(offset + 124, 12).trimmingCharacters(in: .whitespacesAndNewlines), radix: 8),
                  size >= 0, size <= maxAudioBytes, offset + 512 + size <= bytes.count else { throw VoiceServiceError(Localization.text("Ses arşivi geçersiz boyut içeriyor.")) }
            let type = bytes[offset + 156]
            guard type == 0 || type == 48, prefix.isEmpty, !name.isEmpty, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), files[name] == nil else {
                throw VoiceServiceError(Localization.text("Ses arşivinde güvenli olmayan veya yinelenen kayıt var."))
            }
            files[name] = Data(bytes[(offset + 512)..<(offset + 512 + size)])
            guard files.count <= 4096 else { throw VoiceServiceError(Localization.text("Ses arşivinde fazla kayıt var.")) }
            offset += 512 + ((size + 511) / 512) * 512
        }
        return files
    }

    public static func makeTar(_ files: [String: Data]) throws -> Data {
        var tar = Data()
        for name in files.keys.sorted() {
            guard let payload = files[name], !name.isEmpty, name.utf8.count <= 99, !name.hasPrefix("."), !name.contains("/"), !name.contains("\\"), payload.count <= maxAudioBytes else {
                throw VoiceServiceError(Localization.text("Ses arşivi kaydı geçersiz."))
            }
            var header = [UInt8](repeating: 0, count: 512)
            func put(_ text: String, _ start: Int, _ width: Int) {
                for (i, byte) in text.utf8.prefix(width).enumerated() { header[start + i] = byte }
            }
            put(name, 0, 100); put("0000644", 100, 8); put("0000000", 108, 8); put("0000000", 116, 8)
            put(String(format: "%011o", payload.count), 124, 12); put("00000000000", 136, 12)
            for i in 148..<156 { header[i] = 32 }
            header[156] = 48; put("ustar", 257, 6); put("00", 263, 2)
            let checksum = header.reduce(0) { $0 + Int($1) }
            put(String(format: "%06o", checksum), 148, 6); header[154] = 0; header[155] = 32
            tar.append(contentsOf: header); tar.append(payload)
            let padding = (512 - payload.count % 512) % 512
            tar.append(Data(repeating: 0, count: padding))
        }
        tar.append(Data(repeating: 0, count: 1024))
        return tar
    }
}
