import Foundation

/// Opt-in tailnet-only proxy. Never invokes Funnel, resets all Serve config, or binds a public listener.
public actor TailscaleService {
    public struct CommandResult:Sendable {
        public let status:Int32
        public let output:Data
        public init(status:Int32,output:Data) { self.status=status; self.output=output }
    }
    public typealias Runner = @Sendable (String,[String]) async throws -> CommandResult
    public static let httpsPort=8443
    private let executable:String?
    private let preferences:URL
    private let runner:Runner
    public init(executable:String? = nil,preferences:URL? = nil,runner:Runner? = nil) {
        self.executable=executable ?? Self.findExecutable()
        self.preferences=preferences ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Dreame Hub/preferences.json")
        self.runner=runner ?? { executable, arguments in try await Self.run(executable, arguments) }
    }
    public static func validPort(_ port:Int) -> Bool { (1024...65535).contains(port) }
    private static func findExecutable() -> String? {
        ["/opt/homebrew/bin/tailscale","/usr/local/bin/tailscale","/Applications/Tailscale.app/Contents/MacOS/Tailscale"].first { FileManager.default.isExecutableFile(atPath:$0) }
    }
    private static func run(_ executable:String,_ arguments:[String]) async throws -> CommandResult {
        try await Task.detached(priority:.utility) {
            let process=Process(),output=Pipe()
            process.executableURL=URL(fileURLWithPath:executable); process.arguments=arguments
            process.standardOutput=output; process.standardError=FileHandle.nullDevice
            let timeout=DispatchWorkItem { if process.isRunning { process.terminate() } }
            try process.run(); DispatchQueue.global().asyncAfter(deadline:.now()+25,execute:timeout)
            let data=output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); timeout.cancel()
            return CommandResult(status:process.terminationStatus,output:data)
        }.value
    }
    private func command(_ args:[String]) async throws -> CommandResult {
        guard let executable else { throw Failure.notInstalled }
        return try await runner(executable,args)
    }
    private func preferred() -> Bool {
        guard let data=try? Data(contentsOf:preferences),let value=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return false }
        return value["tailscale_remote"] as? Bool == true
    }
    private func savePreference(_ enabled:Bool) throws {
        var value:[String:Any]=[:]
        if let data=try? Data(contentsOf:preferences) { value=(try? JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:] }
        value["tailscale_remote"]=enabled
        try FileManager.default.createDirectory(at:preferences.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]).write(to:preferences,options:.atomic)
    }
    private func serveConfiguration() async throws -> JSONValue {
        let result=try await command(["serve","status","--json"])
        guard result.status==0 else { throw Failure.failed }
        if result.output.isEmpty { return .object([:]) }
        return try JSONDecoder().decode(JSONValue.self,from:result.output)
    }
    public static func endpoint(_ config:JSONValue,dnsName:String) -> JSONValue { config["Web"]["\(dnsName):\(httpsPort)"] }
    public static func hasPublicFunnel(_ config:JSONValue,dnsName:String) -> Bool { config["AllowFunnel"]["\(dnsName):\(httpsPort)"].bool == true }
    public static func proxy(_ config:JSONValue,dnsName:String) -> String? { endpoint(config,dnsName:dnsName)["Handlers"]["/"]["Proxy"].string }
    public func status(localPort:Int) async throws -> [String:Any] {
        guard Self.validPort(localPort) else { throw Failure.invalidPort }
        var status:[String:Any]=["installed":executable != nil,"connected":false,"enabled":false,"preferred":preferred(),"dns_name":"","url":"","https_port":Self.httpsPort]
        guard executable != nil else { return status }
        let result=try await command(["status","--json"])
        guard result.status==0 else { return status }
        let payload=try JSONDecoder().decode(JSONValue.self,from:result.output)
        let connected=payload["BackendState"].string == "Running"
        let dns=(payload["Self"]["DNSName"].string ?? "").trimmingCharacters(in:CharacterSet(charactersIn:"."))
        status["connected"]=connected; status["dns_name"]=dns
        guard connected,!dns.isEmpty else { return status }
        let config=try await serveConfiguration()
        let enabled=Self.proxy(config,dnsName:dns)=="http://127.0.0.1:\(localPort)" && !Self.hasPublicFunnel(config,dnsName:dns)
        status["enabled"]=enabled
        if enabled { status["url"]="https://\(dns):\(Self.httpsPort)/" }
        return status
    }
    public func enable(localPort:Int) async throws -> [String:Any] {
        let state=try await status(localPort:localPort)
        guard state["connected"] as? Bool == true,let dns=state["dns_name"] as? String else { throw Failure.notConnected }
        let config=try await serveConfiguration(),target="http://127.0.0.1:\(localPort)"
        guard !Self.hasPublicFunnel(config,dnsName:dns) else { throw Failure.publicEndpoint }
        if let handlers=Self.endpoint(config,dnsName:dns)["Handlers"].object,!handlers.isEmpty {
            guard handlers.count==1,Self.proxy(config,dnsName:dns)==target else { throw Failure.conflict }
        }
        let result=try await command(["serve","--bg","--yes","--https=\(Self.httpsPort)",target])
        guard result.status==0 else { throw Failure.failed }
        let verified=try await status(localPort:localPort)
        guard verified["enabled"] as? Bool == true else { throw Failure.notVerified }
        try savePreference(true); var updated=verified; updated["preferred"]=true; return updated
    }
    public func disable(localPort:Int) async throws -> [String:Any] {
        let state=try await status(localPort:localPort)
        guard let dns=state["dns_name"] as? String,!dns.isEmpty else { throw Failure.notConnected }
        let config=try await serveConfiguration()
        guard let handlers=Self.endpoint(config,dnsName:dns)["Handlers"].object else { try savePreference(false); return try await status(localPort:localPort) }
        guard handlers.count==1,Self.proxy(config,dnsName:dns)=="http://127.0.0.1:\(localPort)",!Self.hasPublicFunnel(config,dnsName:dns) else { throw Failure.conflict }
        let result=try await command(["serve","--https=\(Self.httpsPort)","off"])
        guard result.status==0 else { throw Failure.failed }
        let verified=try await status(localPort:localPort)
        guard verified["enabled"] as? Bool == false else { throw Failure.notVerified }
        try savePreference(false); var updated=verified; updated["preferred"]=false; return updated
    }
    public enum Failure:LocalizedError {
        case notInstalled,invalidPort,notConnected,failed,conflict,publicEndpoint,notVerified
        public var errorDescription:String? {
            switch self {
            case .notInstalled:return Localization.text("Tailscale bu Mac’te kurulu değil.")
            case .invalidPort:return Localization.text("Yerel uygulama portu geçersiz.")
            case .notConnected:return Localization.text("Önce Tailscale bağlantısını aç.")
            case .failed:return Localization.text("Tailscale işlemi tamamlanamadı.")
            case .conflict:return Localization.text("8443 portunda başka bir Serve yapılandırması var; değiştirilmedi.")
            case .publicEndpoint:return Localization.text("8443 portu Funnel ile herkese açık; güvenli olmayan yapılandırma değiştirilmedi.")
            case .notVerified:return Localization.text("Tailscale değişikliği doğrulanamadı.")
            }
        }
    }
}
