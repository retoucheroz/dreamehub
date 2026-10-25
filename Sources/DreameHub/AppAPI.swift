import Foundation
import DreameCore

actor AppAPI {
    private let service = DeviceService()
    private var boot:[String:Any] = ["busy":true,"stage":"loading","error":""]
    private var remembered = false
    private var refreshing = false
    private var refreshed = Date.distantPast
    private var credentialSummary:[String:Any] = ["available":true,"remembered":false,"username":"","region":"sg","account":"dreame"]
    private var generation = 0
    private var mapService:MapService?
    private var mapReady = false
    private var voiceService:VoiceService?
    private var voiceHost:VoiceTransferHost?
    private var navigation:GoToController?
    private let readOnly: Bool
    init(readOnly: Bool = CommandLine.arguments.contains("--read-only")) {
        self.readOnly = readOnly
    }
    private var statusError:String?
    private var historyService:HistoryService?
    private var viewingHistory = false
    private var localServer:LoopbackHTTPServer?
    private var localPort:Int = 0
    private let tailscale = TailscaleService()
    private var tailscaleState:[String:Any] = ["installed":false,"connected":false,"enabled":false,"url":""]

    func bootstrap() async {
        let current = generation
        do {
            let server = LoopbackHTTPServer(resourceRoot:ResourcePaths.root) { [weak self] method,path,body,binary in
                guard let self else { return ["status":503,"body":["error":Localization.text("Uygulama kapatılıyor.")]] }
                return await self.response(path:path,method:method,body:body,binary:binary)
            }
            localPort = try await server.start(); localServer = server
            let saved = try await Task.detached { try CredentialStore.load() }.value
            guard current == generation else { return }
            if let saved {
                remembered = true
                credentialSummary = ["available":true,"remembered":true,"username":saved.username,"region":saved.region,"account":saved.account.rawValue]
                try await service.login(username:saved.username,password:saved.password,region:saved.region,remember:false,account:saved.account)
                guard current == generation else { return }
                boot = ["busy":false,"stage":"ready","error":""]
            } else { boot = ["busy":false,"stage":"login_required","error":""] }
        } catch { boot = ["busy":false,"stage":"login_required","error":error.localizedDescription] }
    }
    static func productImagePath(model:String) -> String {
        guard let product = ProductCatalog.lookup(model:model),
              FileManager.default.fileExists(atPath:ResourcePaths.root.appendingPathComponent(String(product.imagePath.dropFirst())).path) else {
            return "/assets/products/generic.svg"
        }
        return product.imagePath
    }
    private func state() async -> [String:Any] {
        var result = await service.publicState()
        if var device = result["device"] as? [String:Any] {
            device["image_url"] = Self.productImagePath(model:device["model"] as? String ?? "")
            var supports = device["supports"] as? [String:Bool] ?? [:]
            supports["map"] = true // Map tab must remain available to report loading/fetch failures.
            supports["go_to"] = !readOnly && mapReady && GoToController.supports(model:device["model"] as? String ?? "")
            device["supports"] = supports; result["device"] = device
        }
        result["boot"] = boot; result["credentials"] = credentialSummary
        result["tailscale"] = tailscaleState
        result["read_only"] = readOnly
        if readOnly { result["warning"] = Localization.text("Swift doğrulama sürümü · yalnız okuma; robot komutları kapalı.") }
        if let navigation,let error = await navigation.lastError { result["warning"] = error }
        if let statusError { result["warning"] = Localization.text("Son cihaz verisi gösteriliyor: {error}",["error":statusError]) }
        if Date().timeIntervalSince(refreshed)>3 && !refreshing && result["authenticated"] as? Bool == true {
            refreshing = true
            Task { await self.refresh() }
        }
        return result
    }
    private func refresh() async {
        defer { refreshing = false; refreshed = Date() }
        do { try await service.refresh(); statusError = nil } catch { statusError = error.localizedDescription }
    }
    func response(path:String,method:String,body:[String:Any],binary:String?) async -> [String:Any] {
        do {
            let plainPath = String(path.split(separator:"?",maxSplits:1).first ?? "")
            if method == "GET", plainPath.hasPrefix("/api/voice/editor/audio/") {
                let voice = try await voice()
                let data = try await voice.audio(id:String(plainPath.dropFirst("/api/voice/editor/audio/".count)))
                return ["status":200,"bodyBase64":data.base64EncodedString(),"contentType":"audio/ogg"]
            }
            if method == "GET",plainPath.hasPrefix("/api/map/obstacle/"),plainPath.hasSuffix("/image") {
                guard let device = await service.selectedDevice else { throw CloudError.notAuthenticated }
                let id = String(plainPath.dropFirst("/api/map/obstacle/".count).dropLast("/image".count))
                guard id.count<=128,id.range(of:"^[A-Za-z0-9_.:-]+$",options:.regularExpression) != nil else { throw AppError.message(Localization.text("Geçersiz algılama kaydı.")) }
                let data:Data
                if viewingHistory,let historyService { data = try await historyService.photo(device:device,obstacleID:id) }
                else {
                    if mapService == nil { mapService = MapService(cloud:await service.cloud) }
                    let capture = try await mapService!.capture(device:device)
                    data = try await ObstaclePhotoService(cloud:await service.cloud).image(device:device,capture:capture,index:id)
                }
                return ["status":200,"bodyBase64":data.base64EncodedString(),"contentType":ObstaclePhotoService.contentType(data) ?? "application/octet-stream"]
            }
            return ["status":200,"body":try await route(path:path,method:method,body:body,binary:binary)]
        }
        catch { return ["status":400,"body":["error":error.localizedDescription]] }
    }
    private func route(path:String,method:String,body:[String:Any],binary:String?) async throws -> [String:Any] {
        let urlPath = String(path.split(separator:"?",maxSplits:1).first ?? "")
        if method == "GET" {
            if urlPath.hasPrefix("/api/cleaning/history/"),urlPath.hasSuffix("/map") {
                guard let device = await service.selectedDevice,let index = Int(urlPath.dropFirst("/api/cleaning/history/".count).dropLast("/map".count)) else { throw AppError.message(Localization.text("Geçersiz geçmiş kaydı.")) }
                if historyService == nil { historyService = HistoryService(cloud:await service.cloud) }
                let map = try await historyService!.map(device:device,index:index)
                viewingHistory = true
                return ["map":map.anyValue]
            }
            switch urlPath {
            case "/api/state": return await state()
            case "/api/credentials": return credentialSummary
            case "/api/tailscale/status":
                guard localPort>0 else { throw AppError.message(Localization.text("Yerel bağlantı henüz hazır değil.")) }
                tailscaleState = try await tailscale.status(localPort:localPort)
                return tailscaleState
            case "/api/map/current":
                guard let device = await service.selectedDevice else { throw CloudError.notAuthenticated }
                if mapService == nil { mapService = MapService(cloud:await service.cloud) }
                let map = try await mapService!.current(device:device)
                mapReady = true; viewingHistory = false
                return ["map":map.anyValue]
            case "/api/cleaning/history":
                guard let device = await service.selectedDevice else { throw CloudError.notAuthenticated }
                if historyService == nil { historyService = HistoryService(cloud:await service.cloud) }
                return ["history":try await historyService!.list(device:device).anyValue]
            case "/api/voice/editor": return try await voice().catalog()
            case "/api/voice/editor/transfer": return voiceHost?.status() ?? ["active":false]
            default: throw AppError.message(Localization.text("Bu işlevin Swift geçişi henüz doğrulanmadı; işlem yapılmadı."))
            }
        }
        guard method == "POST" else { throw AppError.message(Localization.text("Geçersiz istek yöntemi.")) }
        switch urlPath {
        case "/api/tailscale/enable", "/api/tailscale/disable":
            try requireControl()
            guard localPort>0 else { throw AppError.message(Localization.text("Yerel bağlantı henüz hazır değil.")) }
            tailscaleState = urlPath.hasSuffix("/enable") ? try await tailscale.enable(localPort:localPort) : try await tailscale.disable(localPort:localPort)
            return tailscaleState
        case "/api/login":
            var user = body["username"] as? String ?? "", password = body["password"] as? String ?? "", region = body["region"] as? String ?? "sg"
            guard let account = CloudAccount(rawValue:body["account"] as? String ?? "dreame") else { throw AppError.message(Localization.text("Geçersiz hesap sağlayıcısı.")) }
            if body["use_saved"] as? Bool == true {
                guard let saved = try await Task.detached(operation:{ try CredentialStore.load() }).value else { throw AppError.message(Localization.text("Kayıtlı hesap bulunamadı.")) }
                guard saved.matches(username:user,region:region,account:account) else { throw AppError.message(Localization.text("Hesap veya bölge değişti. Parolanı yeniden gir.")) }
                user = saved.username; password = saved.password
            }
            guard !user.isEmpty,!password.isEmpty else { throw AppError.message(Localization.text("Hesap bilgilerini eksiksiz gir.")) }
            try await navigation?.cancel(); navigation = nil
            voiceHost?.close(); voiceHost = nil
            generation += 1; mapService = nil; historyService = nil; voiceService = nil
            mapReady = false; viewingHistory = false
            let save = !readOnly && (body["remember"] as? Bool ?? false)
            try await service.login(username:user,password:password,region:region,remember:save,account:account)
            if save { remembered = true; credentialSummary = ["available":true,"remembered":true,"username":user,"region":region,"account":account.rawValue] }
            boot = ["busy":false,"stage":"ready","error":""]
            return await state()
        case "/api/logout":
            try await navigation?.cancel(); voiceHost?.close(); voiceHost = nil
            generation += 1; await service.logout(); mapService = nil; voiceService = nil; historyService = nil; mapReady = false
            boot = ["busy":false,"stage":"login_required","error":""]; return ["ok":true]
        case "/api/credentials/forget":
            try requireControl()
            try await Task.detached { try CredentialStore.delete() }.value
            remembered = false; credentialSummary = ["available":true,"remembered":false,"username":"","region":"sg","account":"dreame"]
            return ["ok":true]
        case "/api/device/select":
            guard let id = body["device_id"] as? String else { throw AppError.message(Localization.text("Cihaz seçilmedi.")) }
            try await navigation?.cancel(); navigation = nil; voiceHost?.close(); voiceHost = nil
            try await service.select(deviceID:id); mapService = nil; voiceService = nil; historyService = nil; mapReady = false
            return await state()
        case "/api/action":
            try requireControl(); try await navigation?.cancel()
            guard let command = body["command"] as? String else { throw AppError.message(Localization.text("Komut yok.")) }
            try await service.action(command); return ["ok":true]
        case "/api/setting":
            try requireControl(); try await navigation?.cancel()
            guard let name = body["name"] as? String,let value = body["value"] as? Int else { throw AppError.message(Localization.text("Geçersiz ayar.")) }
            try await service.setting(name,value:value); return ["ok":true]
        case "/api/voice/editor/replace":
            let query = URLComponents(string:"dreamehub://app" + path)?.queryItems
            guard let id = query?.first(where:{$0.name == "id"})?.value,let encoded = binary,let data = Data(base64Encoded:encoded) else { throw AppError.message(Localization.text("Ses dosyası okunamadı.")) }
            return try await voice().replace(id:id,payload:data)
        case "/api/voice/editor/reset":
            guard let id = body["id"] as? String else { throw AppError.message(Localization.text("Anons seçilmedi.")) }
            return ["ok":true,"changed_count":try await voice().reset(id:id)]
        case "/api/voice/install":
            try requireControl()
            guard let language = body["language"] as? String,let device = await service.selectedDevice else { throw CloudError.notAuthenticated }
            let pack = try await voice().pack(language:language)
            let value = String(decoding:try JSONSerialization.data(withJSONObject:pack.installValue,options:[.sortedKeys]),as:UTF8.self)
            let response = try await service.cloud.rpc(device:device,method:"set_properties",params:JSONValue(any:[["did":device.id,"siid":7,"piid":4,"value":value]]))
            try DeviceContract.requireAcknowledgement(response.anyValue); return ["ok":true]
        case "/api/voice/editor/install":
            try requireControl()
            guard let device = await service.selectedDevice,let ip = device.raw["localip"].string ?? device.raw["ip"].string else { throw AppError.message(Localization.text("Robotun yerel ağ adresi doğrulanamadı.")) }
            let pack = try await voice().build()
            voiceHost?.close()
            let host = try VoiceTransferHost(payload:pack.data,peerIP:ip)
            let url = try await host.start(); voiceHost = host
            let value = String(decoding:try JSONSerialization.data(withJSONObject:["id":"EN","url":url.absoluteString,"md5":pack.md5,"size":pack.data.count],options:[.sortedKeys]),as:UTF8.self)
            do {
                let response = try await service.cloud.rpc(device:device,method:"set_properties",params:JSONValue(any:[["did":device.id,"siid":7,"piid":4,"value":value]]))
                try DeviceContract.requireAcknowledgement(response.anyValue)
                return ["ok":true,"changed_count":pack.changedCount]
            } catch { host.close(); voiceHost = nil; throw error }
        case "/api/go-to":
            try requireControl()
            guard let device = await service.selectedDevice,let x = body["x"] as? NSNumber,let y = body["y"] as? NSNumber,x.doubleValue.isFinite,y.doubleValue.isFinite,abs(x.doubleValue)<1e7,abs(y.doubleValue)<1e7 else { throw AppError.message(Localization.text("Geçersiz hedef.")) }
            if mapService == nil { mapService = MapService(cloud:await service.cloud) }
            if navigation == nil { navigation = GoToController(cloud:await service.cloud,maps:mapService!) }
            try await navigation!.start(device:device,x:Int(x.doubleValue.rounded()),y:Int(y.doubleValue.rounded()))
            return ["ok":true]
        default: throw AppError.message(Localization.text("Bu işlevin Swift geçişi henüz doğrulanmadı; işlem yapılmadı."))
        }
    }
    private func voice() async throws -> VoiceService {
        if let voiceService { return voiceService }
        guard let device = await service.selectedDevice else { throw CloudError.notAuthenticated }
        let resources = ResourcePaths.root
        let new = try VoiceService(model:device.model,labelsURL:resources.appendingPathComponent("voice_labels_tr.json"),englishLabelsURL:resources.appendingPathComponent("voice_labels_en.json"),vorbisLibraryURL:resources.appendingPathComponent("native/libsndfile_arm64.dylib"))
        voiceService = new; return new
    }
    private func requireControl() throws {
        if readOnly { throw AppError.message(Localization.text("Yalnız okuma doğrulaması açık. Robot hareketi ve ayar değişikliği yapılmadı.")) }
    }
    func shutdown() async throws { try await navigation?.cancel(); voiceHost?.close(); localServer?.stop(); await service.logout() }
}

enum ResourcePaths {
    static var root:URL {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("DreameHub_DreameHub.bundle/Resources")
        return bundled.flatMap { FileManager.default.fileExists(atPath:$0.path) ? $0 : nil } ?? Bundle.module.bundleURL.appendingPathComponent("Resources")
    }
}
