import AppKit
import WebKit
import DreameCore

@main
enum DreameHubMain {
    static func main() {
        if CommandLine.arguments.contains("--verify-readonly") {
            Task {
                do {
                    guard let credentials = try CredentialStore.load() else { throw AppError.message("Kayıtlı hesap yok.") }
                    let cloud = CloudClient()
                    _ = try await cloud.login(username: credentials.username, password: credentials.password, country: credentials.region, account: credentials.account)
                    let devices = try await cloud.devices()
                    print("Swift cloud login: PASS; vacuum count: \(devices.count)")
                    for device in devices {
                        let params = DeviceContract.propertyPairs.map { ["did":device.id,"siid":$0.0,"piid":$0.1] as [String:Any] }
                        let response = try await cloud.rpc(device:device,method:"get_properties",params:JSONValue(any:params))
                        let rows = response.anyValue as? [[String:Any]] ?? []
                        let count = rows.filter { ($0["code"] as? Int)==0 && $0["value"] != nil }.count
                        print("Model \(device.model): readable properties \(count)/\(params.count)")
                        guard count > 0 else { throw AppError.message("Cihazdan okunabilir özellik alınamadı.") }
                        let maps = MapService(cloud:cloud)
                        let capture = try await maps.capture(device:device)
                        let privateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("dreame-swift-verification-" + UUID().uuidString)
                        try FileManager.default.createDirectory(at:privateDirectory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
                        let fixture:[String:Any] = ["raw":capture.raw,"iv":capture.iv as Any? ?? NSNull(),"key":capture.key as Any? ?? NSNull(),"version":capture.version]
                        let fixtureURL = privateDirectory.appendingPathComponent("map-fixture.json")
                        try JSONSerialization.data(withJSONObject:fixture).write(to:fixtureURL,options:.atomic)
                        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:fixtureURL.path)
                        print("Private map fixture: \(fixtureURL.path)")
                        let map = try MapDecoder.decode(capture.raw,version:capture.version,iv:capture.iv,key:capture.key)
                        print("Native map decode: PASS; fields=\(map.count); observation time present=\(map["timestamp_ms"] != nil)")
                        let current = try await maps.current(device:device)
                        let age = current["timestamp_ms"].int.map { max(0,Int(Date().timeIntervalSince1970)-$0/1000) }
                        print("Native current-map decode: PASS; source age seconds=\(age.map(String.init) ?? "unknown"); sync warning=\(current["update_warning"].string != nil)")
                        let history = HistoryService(cloud:cloud)
                        let records = try await history.list(device:device)
                        print("History records: \(records.array?.count ?? 0)")
                        if let first = records.array?.first,let index = first["index"].int {
                            let historic = try await history.map(device:device,index:index)
                            print("Native history map: PASS; detection count=\(historic["obstacles"].array?.count ?? 0)")
                            if let obstacle = historic["obstacles"].array?.first?.array,let identifier = obstacle.first?.string {
                                do {
                                    let photo = try await history.photo(device:device,obstacleID:identifier)
                                    print("Actual obstacle photo: received \(photo.count) bytes, image format=\(ObstaclePhotoService.contentType(photo) ?? "unknown")")
                                } catch { print("Actual obstacle photo: NOT VERIFIED — \(error.localizedDescription)") }
                            }
                        }
                    }
                    await cloud.logout()
                    exit(0)
                } catch { print("Swift read-only verification: FAILED — \(error.localizedDescription)"); exit(1) }
            }
            dispatchMain()
        }
        Localization.configure(englishTable:ResourcePaths.root.appendingPathComponent("assets/i18n/en.json"),preference:UserDefaults.standard.string(forKey:"dreameLanguage"))
        let app = NSApplication.shared
        let menu = NSMenu(), appMenu = NSMenu(), item = NSMenuItem()
        appMenu.addItem(withTitle:Localization.text("Çık"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        item.submenu = appMenu; menu.addItem(item); app.mainMenu = menu
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

enum AppError: LocalizedError {
    case message(String)
    var errorDescription:String? { if case .message(let text) = self { return text }; return nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    private var statusItem:NSStatusItem!
    private var popover:NSPopover!
    private var window:NSWindow?
    private var webView:WKWebView!
    private var material:NSVisualEffectView!
    private let api = AppAPI()
    private var scheme:AppScheme!
    private var terminationApproved = false

    func applicationDidFinishLaunching(_ notification:Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName:"sensor.tag.radiowaves.forward",accessibilityDescription:"Dreame Hub Swift")
        statusItem.button?.toolTip = "Dreame Hub Swift"
        statusItem.button?.setAccessibilityLabel("Dreame Hub Swift")
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        statusItem.button?.sendAction(on:[.leftMouseUp,.rightMouseUp])
        let config = WKWebViewConfiguration()
        let savedTheme = UserDefaults.standard.string(forKey:"dreameTheme") ?? "system"
        let themeJSON = String(data:try! JSONSerialization.data(withJSONObject:[savedTheme]),encoding:.utf8)!
        config.userContentController.addUserScript(WKUserScript(source:"window.dreameSavedTheme = \(themeJSON)[0];",injectionTime:.atDocumentStart,forMainFrameOnly:true))
        config.userContentController.addScriptMessageHandler(self,contentWorld:.page,name:"dreameAPI")
        config.userContentController.add(self,name:"dreameNative")
        scheme = AppScheme(api:api)
        config.setURLSchemeHandler(scheme,forURLScheme:"dreamehub")
        webView = WKWebView(frame:NSRect(x:0,y:0,width:720,height:540),configuration:config)
        webView.navigationDelegate = self
        webView.setValue(false,forKey:"drawsBackground")
        webView.underPageBackgroundColor = .clear
        material = NSVisualEffectView(frame:webView.frame)
        material.material = .hudWindow; material.blendingMode = .behindWindow; material.state = .active
        material.wantsLayer = true; material.layer?.cornerRadius = 12; material.layer?.masksToBounds = true
        webView.autoresizingMask = [.width,.height]; material.addSubview(webView)
        let controller = NSViewController(); controller.view = material
        popover = NSPopover(); popover.behavior = .transient; popover.contentSize = webView.frame.size; popover.contentViewController = controller
        webView.load(URLRequest(url:URL(string:"dreamehub://app/")!))
        if !CommandLine.arguments.contains("--verify-panel") { Task { await api.bootstrap() } }
        if CommandLine.arguments.contains("--window") { showWindow() }
        else if CommandLine.arguments.contains("--show-panel") { toggle() }
        if CommandLine.arguments.contains("--verify-panel") {
            DispatchQueue.main.async { self.verifyPanelLifecycle() }
        }
    }
    @objc private func toggle() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let open = menu.addItem(withTitle:Localization.text("Pencerede aç"),action:#selector(showWindow),keyEquivalent:""); open.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle:Localization.text("Dreame Hub Swift'ten çık"),action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
            return
        }
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true); return }
        if popover.isShown { popover.performClose(nil) }
        else if let button = statusItem.button {
            NSApp.activate(ignoringOtherApps:true)
            popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func verifyPanelLifecycle() {
        popover.animates = false // Deterministic assertions, not a change to normal UI animation.
        guard let button = statusItem.button else { print("Panel lifecycle: FAIL missing status icon"); exit(1) }
        button.performClick(nil)
        guard popover.isShown, popover.contentViewController?.view.window?.isVisible == true else { print("Panel lifecycle: FAIL open"); exit(1) }
        button.performClick(nil)
        guard !popover.isShown else { print("Panel lifecycle: FAIL close"); exit(1) }
        showWindow(); window?.close(); button.performClick(nil)
        guard window == nil,popover.isShown,webView.superview === material else { print("Panel lifecycle: FAIL window return"); exit(1) }
        print("Panel lifecycle: PASS status-button open/close and window-to-panel return; no cloud/device calls")
        popover.performClose(nil)
        // This isolated lifecycle probe never bootstraps cloud/device services.
        terminationApproved = true; NSApp.terminate(nil)
    }
    @objc private func showWindow() {
        popover.performClose(nil)
        if window == nil {
            let win = NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:690),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
            win.title = Localization.text("Dreame Hub Swift — doğrulama sürümü"); win.titleVisibility = .hidden; win.titlebarAppearsTransparent = true
            win.backgroundColor = .clear; win.isOpaque = false; win.isReleasedWhenClosed = false
            win.minSize = NSSize(width:700,height:520)
            win.contentView = material; material.frame = win.contentView!.bounds; material.autoresizingMask = [.width,.height]
            win.delegate = self; win.center(); window = win
        }
        window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        webView.evaluateJavaScript("document.documentElement.classList.add('native-window'); null",completionHandler:nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow, closing === window else { return }
        closing.contentView = nil; window = nil
        material.frame = NSRect(x:0,y:0,width:720,height:540)
        popover.contentViewController?.view = material
        popover.contentSize = material.frame.size
        webView.evaluateJavaScript("document.documentElement.classList.remove('native-window'); null",completionHandler:nil)
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "dreamehub",
              let body = message.body as? [String:Any] else { return }
        if body["action"] as? String == "language" {
            guard let language = body["language"] as? String,["system","tr","en"].contains(language),language != Localization.savedPreference else { return }
            UserDefaults.standard.set(language,forKey:"dreameLanguage")
            let previous = Localization.language
            Localization.select(language)
            if Localization.language != previous { webView.reload() }
            return
        }
        guard body["action"] as? String == "theme" else { return }
        if let theme = body["theme"] as? String,["system","light","dark","liquid"].contains(theme) { UserDefaults.standard.set(theme,forKey:"dreameTheme") }
        switch body["theme"] as? String {
        case "light": material.appearance = NSAppearance(named:.aqua)
        case "dark": material.appearance = NSAppearance(named:.darkAqua)
        case "liquid": material.appearance = NSAppearance(named:.darkAqua)
        default: material.appearance = nil
        }
        let liquid = body["theme"] as? String == "liquid"
        material.blendingMode = liquid ? .behindWindow : .withinWindow
        material.material = liquid ? .hudWindow : .windowBackground
        webView.appearance = material.appearance
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage,replyHandler:@escaping(Any?,String?)->Void) {
        guard message.frameInfo.isMainFrame,message.frameInfo.securityOrigin.protocol == "dreamehub",message.frameInfo.securityOrigin.host == "app",
              let request = message.body as? [String:Any],let path = request["path"] as? String,path.hasPrefix("/api/") else {
            replyHandler(nil,Localization.text("Güvenilmeyen arayüz isteği.")); return
        }
        Task { replyHandler(await api.response(path:path,method:request["method"] as? String ?? "GET",body:request["body"] as? [String:Any] ?? [:],binary:request["bodyBase64"] as? String),nil) }
    }
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        decisionHandler(url.scheme == "dreamehub" && url.host == "app" ? .allow : .cancel)
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { NSLog("Swift UI load failed: %@",error.localizedDescription) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { NSLog("Swift UI navigation failed: %@",error.localizedDescription) }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        if window != nil { webView.evaluateJavaScript("document.documentElement.classList.add('native-window'); null",completionHandler:nil) }
    }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        if terminationApproved { return .terminateNow }
        Task {
            do { try await api.shutdown(); terminationApproved = true; NSApp.reply(toApplicationShouldTerminate:true) }
            catch { let alert = NSAlert(); alert.messageText = Localization.text("Robot işlemi henüz kapatılamadı"); alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.reply(toApplicationShouldTerminate:false) }
        }
        return .terminateLater
    }
}

@MainActor
final class AppScheme: NSObject,WKURLSchemeHandler {
    private let api:AppAPI
    private var tasks:[ObjectIdentifier:Task<Void,Never>] = [:]
    init(api:AppAPI) { self.api = api }
    func webView(_ webView:WKWebView,start urlSchemeTask:WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        tasks[id] = Task {
            defer { tasks[id] = nil }
            do {
                guard let url = urlSchemeTask.request.url,url.host == "app" else { throw AppError.message(Localization.text("Geçersiz adres.")) }
                let data:Data, mime:String
                if url.path.hasPrefix("/api/") {
                    let reply = await api.response(path:url.path,method:"GET",body:[:],binary:nil)
                    guard let encoded = reply["bodyBase64"] as? String,let bytes = Data(base64Encoded:encoded) else { throw AppError.message(Localization.text("Dosya alınamadı.")) }
                    data = bytes; mime = reply["contentType"] as? String ?? "application/octet-stream"
                } else {
                    let root = ResourcePaths.root
                    let path = url.path == "/" || url.path.isEmpty ? "index.html" : String(url.path.dropFirst())
                    let file = root.appendingPathComponent(path).standardizedFileURL
                    guard file.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw AppError.message(Localization.text("Geçersiz dosya.")) }
                    data = path == "index.html" ? Data(Localization.localizedPage(String(decoding:try Data(contentsOf:file),as:UTF8.self)).utf8) : try Data(contentsOf:file)
                    mime = ["html":"text/html", "png":"image/png", "js":"application/javascript", "svg":"image/svg+xml"][file.pathExtension] ?? "application/octet-stream"
                }
                guard !Task.isCancelled else { return }
                urlSchemeTask.didReceive(URLResponse(url:url,mimeType:mime,expectedContentLength:data.count,textEncodingName:mime == "text/html" ? "utf-8" : nil))
                urlSchemeTask.didReceive(data); urlSchemeTask.didFinish()
            } catch { if !Task.isCancelled { NSLog("Swift UI resource failed: %@",error.localizedDescription); urlSchemeTask.didFailWithError(error) } }
        }
    }
    func webView(_ webView:WKWebView,stop urlSchemeTask:WKURLSchemeTask) { tasks.removeValue(forKey:ObjectIdentifier(urlSchemeTask))?.cancel() }
}
