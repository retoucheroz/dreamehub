import Foundation

public actor DeviceService {
    public let cloud: CloudClient
    public private(set) var selectedDevice: CloudDevice?
    public private(set) var devices: [CloudDevice] = []
    private var cached: [String:Any] = [:]
    private var properties: [[String:Any]] = []
    private var switches: [String:Int] = [:]
    private var refreshBusy = false
    private var commandBusy = false
    private var loginBusy = false
    private var generation = 0
    public init(cloud: CloudClient = CloudClient()) { self.cloud = cloud }

    public func login(username: String, password: String, region: String, remember: Bool, account: CloudAccount = .dreame) async throws {
        guard !loginBusy, !commandBusy else { throw ServiceError.busy }
        loginBusy = true; defer { loginBusy = false }
        generation += 1
        let epoch = generation
        selectedDevice = nil; devices = []; cached = [:]; properties = []; switches = [:]
        _ = try await cloud.login(username: username, password: password, country: region, account: account)
        let found = try await cloud.devices()
        guard epoch == generation else { throw CloudError.notAuthenticated }
        guard let first = found.first else { throw ServiceError.noDevices }
        if remember { try CredentialStore.save(.init(username:username,password:password,region:region,account:account)) }
        devices = found
        try await select(deviceID: first.id)
    }
    public func select(deviceID: String) async throws {
        guard !commandBusy else { throw ServiceError.busy }
        guard let target = devices.first(where: { $0.id == deviceID }) else { throw ServiceError.noDevices }
        generation += 1; selectedDevice = target; cached = describe(target); properties = []; switches = [:]
        try await refresh()
    }
    public func logout() async { generation += 1; selectedDevice = nil; devices = []; cached = [:]; properties = []; switches = [:]; await cloud.logout() }
    private func describe(_ device: CloudDevice) -> [String:Any] {
        let product = ProductCatalog.lookup(model: device.model)
        return ["id":device.id,"name":device.name == device.model ? (product?.name ?? device.name) : device.name,"model":device.model,"online":device.raw["online"].bool ?? device.raw["online"].int.map { $0 == 1 } as Any? ?? NSNull(),"image_url":product?.imagePath ?? "/assets/products/generic.svg"]
    }
    public func publicState() -> [String:Any] {
        var result: [String:Any] = ["authenticated":selectedDevice != nil,"devices":devices.map { var d = describe($0); d["selected"] = $0.id == selectedDevice?.id; return d },"selected_device_id": selectedDevice?.id as Any? ?? NSNull()]
        if selectedDevice != nil { result["device"] = cached }
        return result
    }

    public func refresh() async throws {
        guard let device = selectedDevice else { throw CloudError.notAuthenticated }
        if refreshBusy { return }; refreshBusy = true; defer { refreshBusy = false }
        let epoch = generation
        let pairs = DeviceContract.propertyPairs + [(4,34),(4,46),(4,50)]
        let params = pairs.map { ["did":device.id,"siid":$0.0,"piid":$0.1] as [String:Any] }
        let reply = try await cloud.rpc(device:device,method:"get_properties",params:JSONValue(any:params))
        guard let rows = reply.anyValue as? [[String:Any]], rows.contains(where: { ($0["code"] as? Int) == 0 && $0["siid"] is NSNumber && $0["piid"] is NSNumber && $0["value"] != nil }) else { throw CloudError.invalidResponse }
        guard epoch == generation else { return }
        properties = rows; switches = [:]
        if let raw = DeviceContract.property(rows,4,50) as? String, let data = raw.data(using:.utf8), let decoded = try? JSONSerialization.jsonObject(with:data) {
            if let list = decoded as? [[String:Any]] { for item in list { if let key = item["k"] as? String, let value = item["v"] as? Int { switches[key] = value } } }
            else if let item = decoded as? [String:Any], let key = item["k"] as? String, let value = item["v"] as? Int { switches[key] = value }
        }
        cached = status(device:device,rows:rows)
    }

    private func status(device:CloudDevice, rows:[[String:Any]]) -> [String:Any] {
        func p(_ s:Int,_ i:Int) -> Any { DeviceContract.property(rows,s,i) ?? NSNull() }
        func n(_ s:Int,_ i:Int) -> Int? { DeviceContract.property(rows,s,i) as? Int }
        var result = describe(device)
        var mode = n(4,23), water = n(4,5)
        if usesGroupedCleaning(device.model, rows:rows), let raw = mode {
            mode = [0:2,1:1,2:0,3:3][raw & 3]
            water = (1...3).contains(raw >> 16) ? raw >> 16 : nil
        }
        let suction = switches["SuctionMax"] == 1 ? 4 : n(4,4)
        let mapping: [(String,Int,Int)] = [("state",2,1),("error",2,2),("battery",3,1),("charging",3,2),("status",4,1),("cleaning_time",4,2),("cleaned_area",4,3),("cleaning_progress",4,63),("drying_progress",4,64),("base_status",4,25),("voice_language",7,2),("voice_status",7,3)]
        for (key,s,i) in mapping { result[key] = p(s,i) }
        result["state_text"] = n(2,1).map { code in DeviceContract.stateNames[code].map { Localization.text($0) } ?? Localization.text("Durum {code}",["code":String(code)]) } ?? Localization.text("Bilinmiyor")
        result["base_status_text"] = Localization.text(n(4,25).flatMap { DeviceContract.baseNames[$0] } ?? "Bilinmiyor")
        result["voice_status_text"] = Localization.text(n(7,3).flatMap { [0:"Hazır",1:"Paket indiriliyor",2:"Paket kuruluyor",3:"Tamamlandı",4:"Kurulum başarısız"][$0] } ?? "Durum bekleniyor")
        result["suction"] = suction as Any? ?? NSNull(); result["suction_text"] = suction == 4 ? Localization.text("Maks+") : (suction.flatMap { DeviceContract.suctionNames[$0] }.map { Localization.text($0) } as Any? ?? NSNull())
        result["water"] = water as Any? ?? NSNull(); result["water_text"] = water.flatMap { DeviceContract.waterNames[$0] }.map { Localization.text($0) } as Any? ?? NSNull()
        result["cleaning_mode"] = mode as Any? ?? NSNull(); result["cleaning_mode_text"] = mode.flatMap { DeviceContract.modeNames[$0] }.map { Localization.text($0) } as Any? ?? NSNull()
        result["consumables"] = ["main_brush":p(9,1),"side_brush":p(10,1),"filter":p(11,1),"sensor":p(16,1)]
        var dock:[String:Any] = [:]
        let dockNames:[String:[Int:String]] = ["clean_water":[0:"Hazır",1:"Takılı değil",2:"Su az / boş",3:"Şebeke bağlı"],"dirty_water":[0:"Hazır",1:"Dolu veya takılı değil"],"dust_bag":[0:"Hazır",1:"Takılı değil",2:"Dolu"],"detergent":[0:"Hazır",1:"Takılı değil",2:"Boş"]]
        for (key,index) in [("clean_water",1),("dirty_water",2),("dust_bag",3),("detergent",4)] {
            let value = n(27,index)
            dock[key] = ["value":p(27,index),"text":value.map { code in dockNames[key]?[code].map { Localization.text($0) } ?? Localization.text("Durum {code}",["code":String(code)]) } as Any? ?? NSNull(),"attention":value.map { key == "clean_water" ? ![0,3].contains($0) : $0 != 0 } ?? false]
        }
        result["dock_health"] = dock
        result["sensor_profile"] = [:] as [String:Bool] // No inferred sensor stream capability.
        result["supports"] = ["suction":n(4,4) != nil,"water":water != nil,"cleaning_mode":mode != nil,"base":n(4,25) != nil,"auto_empty":n(15,3) != nil || n(15,5) != nil,"voice":!(p(7,2) is NSNull) || !(p(7,3) is NSNull),"map":false,"go_to":false]
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"; result["updated_at"] = formatter.string(from:Date())
        result["controls"] = controls(suction:suction)
        return result
    }

    private func controls(suction:Int?) -> [String:Any] {
        var controls: [String:Any] = [:]
        func control(_ name:String,_ label:String,_ value:Int?,_ choices:[(Int,String)]) {
            guard let value else { return }
            controls[name] = ["label":Localization.text(label),"value":value,"available":true,"reason":"","options":choices.map { ["value":$0.0,"label":Localization.text($0.1),"available":true] as [String:Any] }]
        }
        var suctionOptions = [(0,"Sessiz"),(1,"Standart"),(2,"Turbo"),(3,"Maks")]
        if switches["SuctionMax"] != nil { suctionOptions.append((4,"Maks+")) }
        control("suction","Emiş gücü",suction,suctionOptions)
        control("washing","Yıkama modu",DeviceContract.property(properties,4,46) as? Int,[(0,"Hafif"),(1,"Standart"),(2,"Derin")])
        control("auto_wash","Otomatik yıkama",DeviceContract.property(properties,4,34) as? Int,[(0,"Kapalı"),(1,"Açık")])
        control("hot_wash","Sıcak suyla yıkama",switches["HotWash"],[(0,"Kapalı"),(1,"Açık")])
        return controls
    }

    public func action(_ command:String) async throws {
        guard let device = selectedDevice else { throw CloudError.notAuthenticated }
        guard !commandBusy else { throw ServiceError.busy }; commandBusy = true; defer { commandBusy = false }
        let payload = try DeviceContract.action(command,deviceID:device.id)
        let result = try await cloud.rpc(device:device,method:"action",params:JSONValue(any:payload))
        try DeviceContract.requireAcknowledgement(result.anyValue)
    }

    private func setProperty(device:CloudDevice,piid:Int,value:Any) async throws {
        let payload:[[String:Any]] = [["did":device.id,"siid":4,"piid":piid,"value":value]]
        let response = try await cloud.rpc(device:device,method:"set_properties",params:JSONValue(any:payload))
        try DeviceContract.requireAcknowledgement(response.anyValue)
    }
    private func usesGroupedCleaning(_ model:String, rows:[[String:Any]]) -> Bool {
        DeviceContract.groupedModels.contains(model) || ProductCatalog.supportsGroupedCleaning(model:model, hasSelfWashBase:DeviceContract.property(rows,4,25) != nil)
    }
    private func setSwitch(device:CloudDevice,key:String,value:Int) async throws {
        guard switches[key] != nil else { throw ServiceError.unsupported }
        let data = try JSONSerialization.data(withJSONObject:["k":key,"v":value],options:[.sortedKeys])
        try await setProperty(device:device,piid:50,value:String(decoding:data,as:UTF8.self))
    }

    public func setting(_ name:String,value:Int) async throws {
        guard let device = selectedDevice else { throw CloudError.notAuthenticated }
        guard !commandBusy else { throw ServiceError.busy }; commandBusy = true; defer { commandBusy = false }
        switch name {
        case "suction":
            guard (0...4).contains(value), DeviceContract.property(properties,4,4) != nil else { throw ServiceError.unsupported }
            if value == 4 { try await setSwitch(device:device,key:"SuctionMax",value:1) }
            else { if switches["SuctionMax"] == 1 { try await setSwitch(device:device,key:"SuctionMax",value:0) }; try await setProperty(device:device,piid:4,value:value) }
        case "water", "cleaning_mode":
            guard (name == "water" ? (1...3).contains(value) : (0...3).contains(value)) else { throw DeviceContract.ContractError.invalidValue }
            if usesGroupedCleaning(device.model, rows:properties) {
                let payload:[[String:Any]] = [["did":device.id,"siid":4,"piid":23]]
                let reply = try await cloud.rpc(device:device,method:"get_properties",params:JSONValue(any:payload))
                guard let rows = reply.anyValue as? [[String:Any]], let raw = DeviceContract.property(rows,4,23) as? Int else { throw CloudError.invalidResponse }
                // Do not overwrite a model's finer wetness scale with the legacy three-level scale.
                if name == "water", !(1...3).contains(raw >> 16) { throw ServiceError.unsupported }
                let updated = try DeviceContract.updatedGrouped(raw,mode:name == "cleaning_mode" ? value : nil,water:name == "water" ? value : nil)
                try await setProperty(device:device,piid:23,value:updated)
            } else {
                let piid = name == "water" ? 5 : 23
                guard DeviceContract.property(properties,4,piid) != nil else { throw ServiceError.unsupported }
                try await setProperty(device:device,piid:piid,value:value)
            }
        case "washing", "auto_wash":
            let piid = name == "washing" ? 46 : 34
            guard (name == "washing" ? (0...2).contains(value) : (0...1).contains(value)), DeviceContract.property(properties,4,piid) != nil else { throw ServiceError.unsupported }
            try await setProperty(device:device,piid:piid,value:value)
        case "hot_wash":
            guard (0...1).contains(value) else { throw DeviceContract.ContractError.invalidValue }
            try await setSwitch(device:device,key:"HotWash",value:value)
        default: throw ServiceError.unsupported
        }
        // Never replace real values with optimistic UI state. Next poll reads the device.
    }
    public enum ServiceError: LocalizedError {
        case noDevices, unsupported, busy
        public var errorDescription:String? {
            switch self { case .noDevices:return Localization.text("Bu hesapta seçilebilir Dreame süpürge bulunamadı."); case .unsupported:return Localization.text("Bu özellik cihazdan doğrulanamadı."); case .busy:return Localization.text("Önceki komutun yanıtı bekleniyor.") }
        }
    }
}
