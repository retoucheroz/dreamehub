import Foundation
import Network
import Darwin

/// Short-lived, token-addressed, robot-IP restricted LAN transfer of one voice archive.
/// `downloaded` means the full HTTP payload was sent, never that installation succeeded.
public final class VoiceTransferHost: @unchecked Sendable {
    private let payload: Data
    private let peerIP: String
    private let localIP: String
    private let path = "/voice/" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + "/voice_pack.tar.gz"
    private let queue = DispatchQueue(label: "org.dreamehub.voice-transfer")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var expiry: DispatchWorkItem?
    private var contacted = false
    private var downloaded = false
    private var bytesSent = 0
    private var port: UInt16?
    private var startup: CheckedContinuation<URL, Error>?
    private var starting = false

    public init(payload: Data, peerIP: String) throws {
        guard !payload.isEmpty, payload.count <= VoiceService.maxPackBytes else { throw VoiceServiceError(Localization.text("Ses paketi boyutu geçersiz.")) }
        guard Self.isLocalIPv4(peerIP) else { throw VoiceServiceError(Localization.text("Süpürgenin doğrulanmış yerel IPv4 adresi gerekli.")) }
        self.payload = payload
        self.peerIP = peerIP
        self.localIP = try Self.localAddress(reaching: peerIP)
    }

    public func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.starting, self.listener == nil else { continuation.resume(throwing: VoiceServiceError(Localization.text("Ses aktarımı zaten açık."))); return }
                self.starting = true; self.startup = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.allowLocalEndpointReuse = true
                    parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(self.localIP), port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            guard let port = self.listener?.port?.rawValue,
                                  let url = URL(string: "http://\(self.localIP):\(port)\(self.path)") else {
                                self.finishStartup(.failure(VoiceServiceError(Localization.text("Aktarım adresi oluşturulamadı.")))); return
                            }
                            self.port = port
                            self.finishStartup(.success(url))
                            let expiry = DispatchWorkItem { [weak self] in self?.stopOnQueue() }
                            self.expiry = expiry
                            self.queue.asyncAfter(deadline: .now() + 900, execute: expiry)
                        case .failed(let error): self.finishStartup(.failure(error)); self.stopOnQueue()
                        case .cancelled: self.finishStartup(.failure(VoiceServiceError(Localization.text("Ses aktarımı kapandı."))))
                        default: break
                        }
                    }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 10) { [weak self] in
                        guard let self, self.startup != nil else { return }
                        self.finishStartup(.failure(VoiceServiceError(Localization.text("Yerel aktarım sunucusu zamanında açılamadı."))))
                        self.stopOnQueue()
                    }
                } catch { self.finishStartup(.failure(error)); self.stopOnQueue() }
            }
        }
    }

    private func finishStartup(_ result: Result<URL, Error>) {
        let continuation = startup; startup = nil; starting = false
        continuation?.resume(with: result)
    }

    public func status() -> [String: Any] {
        queue.sync { ["active": listener != nil && port != nil, "contacted": contacted,
                      "downloaded": downloaded, "bytes_sent": bytesSent, "port": port.map { Int($0) as Any } ?? NSNull()] }
    }

    public func close() { queue.async { self.stopOnQueue() } }

    deinit { listener?.cancel(); expiry?.cancel() }

    private func stopOnQueue() {
        expiry?.cancel(); expiry = nil
        listener?.cancel(); listener = nil; port = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
        finishStartup(.failure(VoiceServiceError(Localization.text("Ses aktarımı kapandı."))))
    }

    private func accept(_ connection: NWConnection) {
        guard case .hostPort(let host, _) = connection.endpoint,
              host.debugDescription == peerIP else { connection.cancel(); return }
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            if case .failed = state { self?.connections.removeValue(forKey: key); connection?.cancel() }
            if case .cancelled = state { self?.connections.removeValue(forKey: key) }
        }
        connection.start(queue: queue)
        receive(connection, buffer: Data())
        queue.asyncAfter(deadline: .now() + 60) { [weak self, weak connection] in
            connection?.cancel(); self?.connections.removeValue(forKey: key)
        }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let chunk { buffer.append(chunk) }
            guard buffer.count <= 16384, error == nil else { connection.cancel(); return }
            if let boundary = buffer.range(of: Data("\r\n\r\n".utf8)),
               let text = String(data: buffer[..<boundary.lowerBound], encoding: .utf8) {
                self.respond(connection, header: text)
            } else if complete { connection.cancel() }
            else { self.receive(connection, buffer: buffer) }
        }
    }

    private func respond(_ connection: NWConnection, header: String) {
        let lines = header.components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, ["GET", "HEAD"].contains(String(first[0])), String(first[1]) == path else {
            send(connection, status: "404 Not Found", body: Data(), extra: "", countTransfer: false); return
        }
        contacted = true
        let rangeHeaders = lines.dropFirst().filter { $0.lowercased().hasPrefix("range:") }
        guard rangeHeaders.count <= 1 else { send(connection, status: "416 Range Not Satisfiable", body: Data(), extra: "", countTransfer: false); return }
        let range: Range<Int>
        do { range = try Self.byteRange(rangeHeaders.first.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }, count: payload.count) }
        catch { send(connection, status: "416 Range Not Satisfiable", body: Data(), extra: "Content-Range: bytes */\(payload.count)\r\n", countTransfer: false); return }
        let partial = !rangeHeaders.isEmpty
        let extra = partial ? "Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(payload.count)\r\n" : ""
        let body = payload.subdata(in: range)
        send(connection, status: partial ? "206 Partial Content" : "200 OK", body: body, extra: extra,
             countTransfer: first[0] == "GET", headOnly: first[0] == "HEAD", full: range == 0..<payload.count)
    }

    private func send(_ connection: NWConnection, status: String, body: Data, extra: String, countTransfer: Bool, headOnly: Bool = false, full: Bool = false) {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: application/gzip\r\nContent-Length: \(body.count)\r\nAccept-Ranges: bytes\r\nCache-Control: no-store\r\nConnection: close\r\n\(extra)\r\n"
        var data = Data(header.utf8)
        if !headOnly { data.append(body) }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if error == nil, countTransfer {
                self?.bytesSent += body.count
                if full { self?.downloaded = true }
            }
            connection.cancel()
        })
    }

    public static func byteRange(_ header: String?, count: Int) throws -> Range<Int> {
        guard count > 0 else { throw VoiceServiceError(Localization.text("Boş paket.")) }
        guard let header else { return 0..<count }
        guard header.hasPrefix("bytes="), !header.contains(",") else { throw VoiceServiceError(Localization.text("Geçersiz aralık.")) }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw VoiceServiceError(Localization.text("Geçersiz aralık.")) }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else { throw VoiceServiceError(Localization.text("Geçersiz aralık.")) }
            return max(0, count - suffix)..<count
        }
        guard let start = Int(parts[0]), start >= 0, start < count else { throw VoiceServiceError(Localization.text("Geçersiz aralık.")) }
        let end = parts[1].isEmpty ? count - 1 : (Int(parts[1]) ?? -1)
        guard end >= start else { throw VoiceServiceError(Localization.text("Geçersiz aralık.")) }
        return start..<(min(end, count - 1) + 1)
    }

    private static func isLocalIPv4(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { UInt8($0) }
        guard parts.count == 4 else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }

    private static func localAddress(reaching peer: String) throws -> String {
        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw VoiceServiceError(Localization.text("Yerel ağ adresi bulunamadı.")) }
        defer { Darwin.close(fd) }
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); remote.sin_family = sa_family_t(AF_INET); remote.sin_port = UInt16(80).bigEndian
        guard inet_pton(AF_INET, peer, &remote.sin_addr) == 1 else { throw VoiceServiceError(Localization.text("Geçersiz robot adresi.")) }
        let connected = withUnsafePointer(to: &remote) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        guard connected == 0 else { throw VoiceServiceError(Localization.text("Robotun yerel ağına erişilemiyor.")) }
        var local = sockaddr_in(), length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &local) { ptr in ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        guard result == 0 else { throw VoiceServiceError(Localization.text("Mac'in yerel ağ adresi bulunamadı.")) }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &text, socklen_t(INET_ADDRSTRLEN)) != nil else { throw VoiceServiceError(Localization.text("Yerel adres çözülemedi.")) }
        return String(cString: text)
    }
}
