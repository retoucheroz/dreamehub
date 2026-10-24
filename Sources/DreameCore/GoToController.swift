import Foundation

/// Owns the complete zone-navigation lifecycle. No synthetic positions or arrival guesses.
/// The caller must await cancel() before switching device, logging out, or terminating.
public actor GoToController {
    private let cloud: CloudClient
    private let maps: MapService
    private var watcher: Task<Void,Never>?
    private var operation: Operation?
    private var starting = false
    private var finishing = false
    public private(set) var lastError: String?
    private struct Operation {
        let device:CloudDevice, x:Int, y:Int, tolerance:Int, originalMode:Int, originalSuction:Int, originalMax:Int?
        let start:Date
    }
    public init(cloud:CloudClient,maps:MapService) { self.cloud=cloud; self.maps=maps }
    public var active:Bool { operation != nil }
    /// Zone fallback has only been ported for the known grouped-mode family.
    public static func supports(model:String) -> Bool { DeviceContract.groupedModels.contains(model) }

    public static func validateTarget(x:Int,y:Int,map:JSONValue,now:Date=Date()) throws -> Int {
        guard let size=map["size"].array,size.count>=7,let left=size[0].int,let top=size[1].int,let width=size[4].int,let height=size[5].int,let grid=size[6].int,grid>0,
              x>=left,y>=top,x<left+width*grid,y<top+height*grid else { throw Failure.outsideMap }
        guard let timestamp=map["timestamp_ms"].int,abs(now.timeIntervalSince1970-Double(timestamp)/1000)<30,
              let position=map["robot_position"].array,position.count>=2,let rx=position[0].int,let ry=position[1].int else { throw Failure.staleMap }
        guard abs(rx-x)>grid*2 || abs(ry-y)>grid*2 else { throw Failure.alreadyThere }
        return grid*2
    }
    public func start(device:CloudDevice,x:Int,y:Int) async throws {
        guard operation == nil, !starting, !finishing else { throw Failure.busy }
        starting = true; defer { starting = false }
        guard Self.supports(model:device.model) else { throw Failure.unsupported }
        let map=try await maps.current(device:device), tolerance=try Self.validateTarget(x:x,y:y,map:map)
        let rows=try await read(device,[(3,1),(4,23),(4,4),(4,50),(2,1)])
        guard let battery=DeviceContract.property(rows,3,1) as? Int,battery>=15 else { throw Failure.lowBattery }
        guard let mode=DeviceContract.property(rows,4,23) as? Int,let suction=DeviceContract.property(rows,4,4) as? Int else { throw Failure.unreadableSettings }
        guard let state=DeviceContract.property(rows,2,1) as? Int,[2,3,6,13].contains(state) else { throw Failure.busy }
        var max:Int?
        if let string=DeviceContract.property(rows,4,50) as? String,let data=string.data(using:.utf8),let list=try? JSONSerialization.jsonObject(with:data) as? [[String:Any]] { max=list.first { $0["k"] as? String == "SuctionMax" }?["v"] as? Int }
        operation=Operation(device:device,x:x,y:y,tolerance:tolerance,originalMode:mode,originalSuction:suction,originalMax:max,start:Date()); lastError=nil
        do {
            if max == 1 { try await write(device,piid:50,value:#"{"k":"SuctionMax","v":0}"#) }
            if suction != 0 { try await write(device,piid:4,value:0) }
            let sweeping=try DeviceContract.updatedGrouped(mode,mode:0)
            if mode != sweeping { try await write(device,piid:23,value:sweeping) }
            let half=tolerance/2
            let area=String(decoding:try JSONValue(any:["areas":[[x-half,y-half,x+half,y+half,1,0,1]]]).data(),as:UTF8.self)
            let reply=try await cloud.rpc(device:device,method:"action",params:JSONValue(any:["did":device.id,"siid":4,"aiid":1,"in":[["piid":1,"value":19],["piid":10,"value":area]]]))
            try DeviceContract.requireAcknowledgement(reply.anyValue)
            watcher=Task { [weak self] in await self?.watch() }
        } catch {
            // Command delivery may be unknown; attempt stop before restoring settings.
            do { try await finish(stop:true) } catch { lastError=Localization.text("Hedef işlemi kesildi; durdurma/ayar geri yükleme doğrulanamadı.") }
            throw error
        }
    }
    public func cancel() async throws {
        guard !starting else { throw Failure.busy }
        watcher?.cancel(); watcher=nil
        if operation != nil { try await finish(stop:true) }
    }
    private func watch() async {
        var lastFresh=Date()
        while !Task.isCancelled,let op=operation {
            do { try await Task.sleep(nanoseconds:2_000_000_000) } catch { return }
            do {
                let map=try await maps.current(device:op.device)
                guard !Task.isCancelled, operation?.start == op.start else { return }
                if let timestamp=map["timestamp_ms"].int,abs(Date().timeIntervalSince1970-Double(timestamp)/1000)<20,
                   let point=map["robot_position"].array,point.count>=2,let x=point[0].int,let y=point[1].int {
                    lastFresh=Date()
                    if abs(x-op.x)<=op.tolerance && abs(y-op.y)<=op.tolerance { try await finish(stop:true); return }
                }
                let rows=try await read(op.device,[(2,1),(4,1)])
                guard !Task.isCancelled, operation?.start == op.start else { return }
                if let state=DeviceContract.property(rows,2,1) as? Int,[2,4,5,6,13].contains(state),Date().timeIntervalSince(op.start)>8 { try await finish(stop:true); return }
            } catch { lastError=Localization.text("Hedef izleme verisi alınamadı; güvenli durdurma sınırı izleniyor.") }
            if Date().timeIntervalSince(lastFresh)>20 || Date().timeIntervalSince(op.start)>300 {
                do { try await finish(stop:true); lastError=Localization.text("Güncel konum doğrulanamadığı veya süre aşıldığı için hedef hareketi durduruldu.") }
                catch { lastError=Localization.text("Hedef hareketinin durduğu doğrulanamadı; robotu uygulamadan durdur.") }
                return
            }
        }
    }
    private func finish(stop:Bool) async throws {
        guard !finishing else { throw Failure.busy }
        guard let op=operation else { return }
        finishing = true; defer { finishing = false }
        // Keep operation on failure, allowing explicit retry; never silently discard restore state.
        if stop {
            let reply=try await cloud.rpc(device:op.device,method:"action",params:JSONValue(any:DeviceContract.action("stop",deviceID:op.device.id)))
            try DeviceContract.requireAcknowledgement(reply.anyValue)
        }
        try await write(op.device,piid:23,value:op.originalMode)
        try await write(op.device,piid:4,value:op.originalSuction)
        if let value=op.originalMax { try await write(op.device,piid:50,value:"{\"k\":\"SuctionMax\",\"v\":\(value)}") }
        let rows=try await read(op.device,[(4,23),(4,4),(4,50)])
        guard DeviceContract.property(rows,4,23) as? Int == op.originalMode,DeviceContract.property(rows,4,4) as? Int == op.originalSuction else { throw Failure.restoreUnconfirmed }
        if let expected=op.originalMax {
            guard let raw=DeviceContract.property(rows,4,50) as? String,let data=raw.data(using:.utf8),let list=try JSONSerialization.jsonObject(with:data) as? [[String:Any]],list.first(where: { $0["k"] as? String == "SuctionMax" })?["v"] as? Int == expected else { throw Failure.restoreUnconfirmed }
        }
        operation=nil; watcher=nil
    }
    private func read(_ device:CloudDevice,_ pairs:[(Int,Int)]) async throws -> [[String:Any]] {
        let value=try await cloud.rpc(device:device,method:"get_properties",params:JSONValue(any:pairs.map { ["did":device.id,"siid":$0.0,"piid":$0.1] as [String:Any] }))
        guard let rows=value.anyValue as? [[String:Any]] else { throw CloudError.invalidResponse }; return rows
    }
    private func write(_ device:CloudDevice,piid:Int,value:Any) async throws {
        let reply=try await cloud.rpc(device:device,method:"set_properties",params:JSONValue(any:[["did":device.id,"siid":4,"piid":piid,"value":value]]))
        try DeviceContract.requireAcknowledgement(reply.anyValue)
    }
    public enum Failure:LocalizedError {
        case busy,unsupported,outsideMap,staleMap,alreadyThere,lowBattery,unreadableSettings,restoreUnconfirmed
        public var errorDescription:String? {
            switch self {
            case .busy:return Localization.text("Robotun mevcut görevi veya hedef işlemi tamamlanmalı.")
            case .unsupported:return Localization.text("Bu modelin hedefe gitme komutu henüz Swift sürümünde doğrulanmadı.")
            case .outsideMap:return Localization.text("Hedef haritanın dışında.")
            case .staleMap:return Localization.text("Güncel robot konumu alınmadan hedef hareketi başlatılamaz.")
            case .alreadyThere:return Localization.text("Robot zaten bu noktada.")
            case .lowBattery:return Localization.text("Hedef hareketi için pil en az %15 olmalı.")
            case .unreadableSettings:return Localization.text("Hareket öncesi temizlik ayarları okunamadı.")
            case .restoreUnconfirmed:return Localization.text("Önceki ayarların geri yüklendiği henüz doğrulanamadı.")
            }
        }
    }
}
