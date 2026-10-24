import Foundation

/// Read-only cloud map acquisition. Never starts cleaning or requests a physical motion.
public actor MapService {
    private let cloud: CloudClient
    private let stream = MapStreamDecoder()
    private var lastDeviceID: String?
    private var lastPayload: [String:Any]?
    private var streamIV: String?
    private var streamVersion = 1
    private var lastFullPoll = Date.distantPast
    private let now: @Sendable () -> Date
    private let captureOverride: (@Sendable (CloudDevice) async throws -> Capture)?
    private let historyOverride: (@Sendable (CloudDevice, Int) async throws -> JSONValue)?
    private var generation = 0
    private var pending: Task<JSONValue, Error>?
    public init(cloud: CloudClient) {
        self.cloud = cloud; now = { Date() }; captureOverride = nil; historyOverride = nil
    }
    // Injectable read-only acquisition and clock keep refresh tests offline and deterministic.
    init(cloud: CloudClient = CloudClient(), now: @escaping @Sendable () -> Date,
         capture: @escaping @Sendable (CloudDevice) async throws -> Capture,
         history: @escaping @Sendable (CloudDevice, Int) async throws -> JSONValue) {
        self.cloud = cloud; self.now = now; captureOverride = capture; historyOverride = history
    }
    public struct Capture: Sendable {
        public let raw: String
        public let iv: String?
        public let key: String?
        public let version: Int
        public let source: String
    }
    public enum Failure: Error, LocalizedError {
        case noMap, unknownModel, signedURL, invalidText
        public var errorDescription: String? {
            switch self {
            case .noMap: return Localization.text("Hesaptan tam harita verisi alınamadı.")
            case .unknownModel: return Localization.text("Bu model için harita şifreleme bilgisi doğrulanmadı.")
            case .signedURL: return Localization.text("Harita indirme adresi alınamadı.")
            case .invalidText: return Localization.text("Harita dosyası beklenen metin biçiminde değil.")
            }
        }
    }

    /// Public, non-account-specific model metadata extracted from upstream DEVICE_INFO.
    /// Entries: map AES IV, map-v3 minimum firmware, map-v2 minimum firmware, model suffixes.
    private static let registryJSON = #"""
[["OFULk9To37qRdXY3",null,null,"c102cn,c102gl,d103cn,d110ch,r2210"],[null,null,null,"p2008,p2009,p2027,p2028,p2028a,p2029,p2036,p2041,p2041o,p2148o,p2150a,p2150b,p2150o,p2156o,p2157,p2187,p2259,r2104,r2205,r2228,r2228d,r2228o,r2228z,r2232a,r2232b,r2232c,r2232d,r2233,r2246,r2247,r2260,r2322,r2423,r2423a,r2438a,r2438b,r2438i,r2438r,r95249,r9524a,r9524b,r9524c,r9524h,r9524j,r9524k,r9524m"],["6PFiLPYMHLylp7RR",null,null,"p2114a,p2114o"],["8qnS9dqgT3CppGe1",null,null,"p2140,p2140a,p2140o,p2140p,p2140q"],["RNO4p35b2QKaovHC",null,null,"p2149o"],["qFKhvoAqRFTPfKN6",null,null,"r2209"],["dndRQ3z8ACjDdDMo",null,null,"r2211o"],["NRwnBj5FsNPgBNbT",null,null,"r2212,r2215,r2235,r2235a,r2253,r2253b,r2253c,r2253d,r2253m,r2253t,r2253u,r2253w,r2263,r2273,r2273a,r2310,r2310a,r2310b,r2310f,r2310g,r2313,r2316,r2316p,r2332,r2338,r2338a,r2355,r2360,r2360w,r2361a,r2367,r2375,r2377,r2394a,r2394f,r2394j,r2394k,r2394l,r2394s,r2394u,r2398,r2421,r2435,r2450m,r2455,r2461r,r2462,r2462a,r9301,r9302,r9304,r9305,r9309a,r9311,r9312,r9316a,r9316h,r9316k,r9317a"],["4sCv3Q2BtbWVBIB2",null,null,"r2216o"],["ojxGnogHfVuefVfx",null,null,"r2240"],["3F0ji4ufBMaH1ThM",null,null,"r2243,r2312,r2312a,r2328,r2380,r2380r,r2388,r2422,r2422a,r2422b,r2422c,r2458a,r2458h,r2459a,r2459h,r2459k,r2459r,r2463r,r2478r,r2478v,r2567a,r2567r,r2569c,r2569r,r2570,r95239,r9523a,r9523b,r9523c,r9523h,r9523k,r9523t,r9523u"],["nf3Zi2Mq8jD5AAOm",null,null,"r2250"],["FmnfaI2pbem0k75t",null,null,"r2251a,r2251o,r2257o,r2317,r2345a,r2345h,r2363,r2363a,r2363n,r2364,r23646,r2364a,r2382a,r2382k,r2382r,r2383a,r2383k,r2386,r2471,r53456,r5345b,r5345e,r95425,r9542a,r9542b,r9542h,r9542t"],["wRy05fYLQJMRH6Mj",null,null,"r2254"],["NRwnBj5FsNPgBNbT",null,1,"r2310d,r2310e,r2338h,r2350,r2385,r2385a,r2401,r2401a,r2401h,r2401u,r2412,r2416,r24162,r2416a,r2416c,r2416f,r2416h,r2416n,r2424,r2426,r2427,r2427a,r2427c,r2427r,r2430,r2430a,r2430u,r2430v,r2432,r2432b,r2437,r2440,r2441,r2443,r24495,r2449a,r2449b,r2449k,r2465a,r2465b,r2465h,r2467,r2469a,r2469x,r2473,r2473s,r2475a,r2475h,r2475r,r2475t,r2483,r2485,r2487,r2488,r2489,r24896,r24898,r2489a,r2489b,r2489c,r2489d,r2489e,r2489f,r2489h,r2489j,r2489k,r2489l,r2489p,r2489q,r2489s,r2489t,r2489u,r2489z,r2491,r24916,r2491a,r2492a,r2492b,r2492j,r2493,r2495,r2501,r2501l,r2501p,r2502,r2504,r2505,r2505z,r2507,r2508,r2513,r25135,r2513a,r2513f,r2513h,r2513k,r2513p,r2513u,r2515,r2518,r2518a,r2518f,r2518j,r2518p,r2519a,r2519r,r2520,r2525a,r2525e,r2525h,r2527,r2527a,r2527b,r2527g,r2527h,r2527j,r2527q,r2527t,r2527u,r2531,r2532a,r2532d,r2532h,r2532v,r2532w,r2532z,r2533h,r2534h,r2535,r2538a,r2538z,r2548,r25513,r2551a,r2551h,r2553,r2560,r2561,r2562a,r2562b,r2562c,r2562h,r2562k,r2562s,r2562t,r2562u,r2571,r2572,r2573,r2574,r2575,r2576,r25799,r2579a,r2579c,r2579h,r2579k,r2580,r2581,r2582a,r2582c,r2582h,r2582k,r2582r,r2584g,r25856,r25857,r25858,r25859,r2587a,r2587r,r2599,r2599h,r2599k,r2599u,r2599v,r500a,r500b,r500b1,r500n,r500xb,r500yb,r500yc,r500ye,r500yt,r500z9,r500za,r500zc,r500zh,r500zk,r5016,r501ba,r501bc,r501bk,r501bt,r501h,r501he,r501s,r501st,r501t,r501tt,r501vr,r501vt,r5020a,r5021a,r5021b,r5021c,r5021h,r5021k,r5021s,r5021t,r5021u,r5022a,r5023a,r5023e,r5024b,r5024t,r5025b,r5025t,r502ca,r502k3,r502ka,r502ke,r502la,r502le,r5039,r50391,r50393,r50395,r50397,r50398,r50399,r5039a,r5039e,r5039f,r5039h,r5039r,r5039w,r50485,r5048a,r5048h,r5049,r50573,r5057a,r5057k,r5057r,r5061,r5061a,r5061e,r50625,r5062a,r5062h,r5062k,r5064t,r5064u,r5082a,r5082c,r5085,r50855,r5099,r5099a,r5099e,r5099g,r5099h,r5099k,r5109f,r510a,r510b,r510b1,r510n,r5117,r5139,r51395,r5149,r5185,r51855,r520b,r520b1,r520n,r522kf,r5239f,r5299,r5730,r5730c,r5732a,r5747,r5765h,r5765k,r5765p,r5765q,r5765u,r5766,r5766h,r5766k,r5766q,r5766v,r5769,r57695,r57698,r5769a,r5769f,r5769g,r5769h,r5769q,r5769r,r5769t,r5770,r5770a,r5770g,r5770h,r5770q,r5770t,r5770v,r5871,r58715,r590q,r590qf,r5977a,r5977c,r5977f,r5977g,r5977h,r5977k,r5977r,r5977t,r5978a,r5978h,r5978q,r59795,r59796,r59797,r59799,r5979a,r5979f,r5979g,r5979h,r5979t,r5979u,r6016,r6018a,r6018c,r6047a,r60u2k,r6116,r6216,r67095,r6709a,r6709c,r6709g,r6709h,r6709r,r6710a,r6710g,r6710h,r6710r,r6710t,r9401,r9406,r9408,r9416,r94165,r9416d,r9419,r9419a,r9419e,r9419h,r9419t,r9420,r9421,r9421t,r9422,r9425,r9426,r9426x,r9427,r9427h,r9427x,r9428,r9430,r9434,r94345,r94346,r9434h,r9434j,r9434l,r9434v,r9441,r9445a,r9445d,r9445g,r9446a,r9446b,r9446c,r9446h,r9446k,r9455,r9455z,r9461,r9471,r9471z,r9473,r9473e,r9474,r94745,r9476,r9477,r9478,r9479,r9480,r9482,r9483,r9486,r9486z,r9487,r9488,r9489,r9490,r9491,r9493a,r9493c,r9493h,r9498,r9503,r95046,r95049,r9504a,r9504r,r9506,r9507b,r9508b,r9513,r9516,r9517,r9518,r9519,r95285,r9528a,r9528h,r9533a,r9533h,r9533t,r9535a,r9535h,r9535n,r95385,r9538a,r9538b,r9538c,r9538e,r9538h,r9538k,r9538l,r9538t,r9538u,r95406,r9540a,r9540h,r9540k,r9540n,r9540u,r9540v,r9543,r9543a,r9543b,r9543r,r95445,r9544a,r9544b,r9544t,r95475,r95476,r9547a,r9547c,r9547h,r9547k,r9548,r9549,r9551"],["FmnfaI2pbem0k75t",null,1,"r2563b,r2563v,r25642,r2564b,r2564s,r2564z,r2565a,r2565v,r2566a,r2566h,r530jb,r530ua,r53148,r5314a,r5314s,r5314z,r531ra,r531rh,r540ga,r540jb,r540tb,r54125,r5412a,r5412v,r54136,r5413a,r5413v,r63013,r63014,r63015,r63017,r63018,r6301a,r6301f,r6301h,r6301r,r6301v,r6301x,r64015,r64016,r64017,r64018,r6401c,r6401k,r6401r,r6401v,r95265,r95266,r95267,r9526a,r9526c,r9526h,r9526k,r9527,r95275,r95276,r95277,r95278,r95279,r9527a,r9527f,r9527v,r9537a,r9537h"],["NRwnBj5FsNPgBNbT",1,1,"r500c,r500c1,r500da,r500vh,r500vp,r501da,r501ua,r501w,r501wu,r502mf,r502mn,r502mt,r502va,r5089b,r5089u,r5090a,r5104h,r510c,r510c1,r512g,r512mf,r5189j,r5189u,r520c,r520c1,r6001a,r6011,r6012,r6015a,r6017b,r6017q,r6101h,r6111,r6112,r6117j,r9515a,r9515e"]]
"""#
    public static func configuration(model: String, firmwareVersion: Int = 1) -> (iv: String?, version: Int)? {
        guard let data = registryJSON.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[Any]],
              let suffix = model.split(separator: ".").last else { return nil }
        for entry in entries where entry.count == 4 {
            guard let models = entry[3] as? String, models.split(separator: ",").contains(suffix) else { continue }
            let v3 = entry[1] as? Int, v2 = entry[2] as? Int
            return (entry[0] as? String, v3.map { firmwareVersion >= $0 } == true ? 3 : v2.map { firmwareVersion >= $0 } == true ? 2 : 1)
        }
        return nil
    }
    public func capture(device: CloudDevice) async throws -> Capture {
        if let captureOverride { return try await captureOverride(device) }
        let firmware = device.raw["deviceInfo"]["version"].string ?? device.raw["version"].string ?? ""
        let build = Int(firmware.split(separator: "_").last ?? "") ?? 1
        guard let config = Self.configuration(model: device.model, firmwareVersion: build) else { throw Failure.unknownModel }
        // The OBJECT_NAME property is preferable to a last partial MAP_DATA packet.
        var objectName: String?
        let props = try await cloud.properties(device: device, keys: ["6.3"])
        if let records = props.array {
            objectName = records.compactMap { Self.firstString($0["value"]) }.first
        } else { objectName = Self.firstString(props["6.3"]) }
        if objectName == nil {
            let history = try await cloud.history(device: device, siid: 6, piid: 3, limit: 1)
            objectName = history.array?.compactMap { Self.firstString($0["value"]) ?? Self.firstString($0["val"]) }.first
        }
        if let objectName, !objectName.isEmpty {
            let parts = objectName.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            let signed = try await cloud.fileURL(device: device, objectName: String(parts[0]), interim: true)
            guard let value = signed.string ?? signed["url"].string, let url = URL(string: value) else { throw Failure.signedURL }
            let data = try await cloud.download(url: url)
            guard let raw = String(data: data, encoding: .utf8) else { throw Failure.invalidText }
            return Capture(raw: raw, iv: config.iv, key: parts.count == 2 ? String(parts[1]) : nil, version: config.version, source: "cloud_object")
        }
        let history = try await cloud.history(device: device, siid: 6, piid: 1, limit: 20)
        // Only a full frame is accepted. We deliberately do not mislabel an unmerged P frame.
        for record in history.array ?? [] {
            guard let raw = Self.firstString(record["value"]) ?? Self.firstString(record["val"]) else { continue }
            do {
                _ = try MapDecoder.decode(raw, version: config.version, iv: config.iv)
                return Capture(raw: raw, iv: config.iv, key: nil, version: config.version, source: "cloud_property_history")
            } catch MapDecoder.Failure.incrementalFrame { continue }
        }
        throw Failure.noMap
    }
    public func current(device: CloudDevice) async throws -> JSONValue {
        if lastDeviceID != device.id {
            generation += 1; pending?.cancel(); pending=nil
            stream.reset(); lastPayload=nil; lastDeviceID=device.id; lastFullPoll = .distantPast
            streamIV=nil; streamVersion=1
        }
        if let pending { return try await pending.value }
        let epoch=generation
        let task=Task { try await self.refresh(device:device, epoch:epoch) }
        pending=task
        defer { if generation == epoch { pending=nil } }
        return try await task.value
    }
    private func checkGeneration(_ epoch:Int) throws {
        guard epoch == generation, !Task.isCancelled else { throw CancellationError() }
    }
    /// Never replace a newer observation with an old object or replayed history record.
    private func newer(_ candidate:[String:Any]) -> Bool {
        guard let previous=lastPayload else { return true }
        let time=(candidate["timestamp_ms"] as? NSNumber)?.int64Value
        let oldTime=(previous["timestamp_ms"] as? NSNumber)?.int64Value
        if let time, let oldTime, time != oldTime { return time > oldTime }
        if time == nil, oldTime != nil { return false }
        guard candidate["map_id"] as? Int == previous["map_id"] as? Int,
              let frame=candidate["frame_id"] as? Int, let old=previous["frame_id"] as? Int else { return false }
        let distance=UInt16(truncatingIfNeeded:frame) &- UInt16(truncatingIfNeeded:old)
        return distance > 0 && distance < 32768
    }
    private func acquireFull(device:CloudDevice, epoch:Int) async throws {
        let full=try await capture(device:device)
        try checkGeneration(epoch)
        let candidate=try MapDecoder.decode(full.raw,version:full.version,iv:full.iv,key:full.key)
        if newer(candidate) {
            lastPayload=try stream.accept(full.raw,version:full.version,iv:full.iv,key:full.key)
            lastPayload?["acquisition_source"]=full.source
            streamIV=full.iv; streamVersion=full.version
        }
    }
    private func refresh(device:CloudDevice, epoch:Int) async throws -> JSONValue {
        var warning: String?
        if lastPayload == nil || now().timeIntervalSince(lastFullPoll)>10 {
            do { try await acquireFull(device:device,epoch:epoch) }
            catch {
                try checkGeneration(epoch)
                guard lastPayload != nil else { throw error }
                warning=error.localizedDescription
            }
            lastFullPoll=now()
        }
        let timestamp=(lastPayload?["timestamp_ms"] as? NSNumber)?.int64Value ?? 0
        do {
            let from=timestamp > 1_577_826_000_000 ? Int(timestamp/1000) : Int(now().timeIntervalSince1970)-300
            let updates:JSONValue
            if let historyOverride { updates=try await historyOverride(device,from) }
            else { updates=try await cloud.history(device:device,siid:6,piid:1,limit:20,from:from) }
            try checkGeneration(epoch)
            let ordered=(updates.array ?? []).sorted { ($0["time"].int ?? 0) < ($1["time"].int ?? 0) }
            for update in ordered {
                guard let raw=Self.firstString(update["value"]) ?? Self.firstString(update["val"]) else { continue }
                let inflated=try MapDecoder.inflateEnvelope(raw,iv:streamIV)
                let bytes=[UInt8](inflated)
                guard bytes.count >= 27 else { continue }
                let frame=Int(Int16(bitPattern:UInt16(bytes[2]) | UInt16(bytes[3]) << 8))
                let mapID=Int(Int16(bitPattern:UInt16(bytes[0]) | UInt16(bytes[1]) << 8))
                let width=Int(UInt16(bytes[19]) | UInt16(bytes[20]) << 8)
                let height=Int(UInt16(bytes[21]) | UInt16(bytes[22]) << 8)
                let metadataOffset=27+width*height
                if metadataOffset <= bytes.count,
                   let metadata=(try? JSONSerialization.jsonObject(with:Data(bytes.dropFirst(metadataOffset)))) as? [String:Any] {
                    let cover=metadata["cover"] as? [String:Any]
                    if let incoming=((cover?["timestamp_ms"] ?? metadata["timestamp_ms"]) as? NSNumber)?.int64Value,
                       let previous=(lastPayload?["timestamp_ms"] as? NSNumber)?.int64Value, incoming < previous { continue }
                }
                if mapID == lastPayload?["map_id"] as? Int,let previous=lastPayload?["frame_id"] as? Int {
                    let distance=UInt16(bitPattern:Int16(frame)) &- UInt16(bitPattern:Int16(previous))
                    if distance==0 || distance>=32768 { continue }
                }
                // Decode metadata before accepting: stream acceptance changes the delta base.
                // A scratch decoder rejects old timestamp full frames without mutating it.
                if bytes[4] == 73 {
                    let candidate=try MapDecoder.decodeInflated(inflated,version:streamVersion)
                    if !newer(candidate) { continue }
                }
                do {
                    var next=try stream.acceptInflated(inflated,version:streamVersion)
                    next["acquisition_source"]="cloud_property_history"
                    lastPayload=next
                } catch MapDecoder.Failure.incrementalFrame {
                    // Do not apply an orphan delta. Reacquire the last full map, with its real age.
                    try await acquireFull(device:device,epoch:epoch)
                    lastFullPoll=now()
                    if mapID == lastPayload?["map_id"] as? Int, let previous=lastPayload?["frame_id"] as? Int {
                        let distance=UInt16(truncatingIfNeeded:frame) &- UInt16(truncatingIfNeeded:previous)
                        if distance == 0 || distance >= 32768 { continue }
                    }
                    do {
                        var next=try stream.acceptInflated(inflated,version:streamVersion)
                        next["acquisition_source"]="cloud_property_history";lastPayload=next
                    } catch MapDecoder.Failure.incrementalFrame {
                        warning=Localization.text("Harita kare zinciri eksik; son doğrulanmış kare gösteriliyor.")
                        break
                    }
                }
            }
        } catch { try checkGeneration(epoch); warning=error.localizedDescription }
        guard var payload=lastPayload else { throw Failure.noMap }
        if var telemetry=payload["telemetry"] as? [String:Any] {
            let now=Int64(now().timeIntervalSince1970*1000)
            // Poll time is not capture time. Repeated polls never make an old map fresh.
            if let observed=(payload["timestamp_ms"] as? NSNumber)?.int64Value { telemetry["freshness_ms"]=max(0,now-observed) }
            telemetry["last_poll_at"]=now
            payload["telemetry"]=telemetry
        }
        if let warning { payload["update_warning"]=warning }
        return try JSONValue(any: payload)
    }
    /// Describes only response shapes, never account identifiers, URLs, keys or map values.
    public func diagnostics(device: CloudDevice) async throws -> JSONValue {
        let props = try await cloud.properties(device: device, keys: ["6.3"])
        let history = try await cloud.history(device: device, siid: 6, piid: 3, limit: 1)
        func shape(_ value: JSONValue, _ depth: Int = 0) -> JSONValue {
            guard depth < 4 else { return .string("depth-limit") }
            switch value {
            case .null: return .string("null")
            case .bool: return .string("bool")
            case .number: return .string("number")
            case .string(let s): return .string("string(length=\(s.count))")
            case .array(let values): return .object(["count": .integer(values.count), "first": values.first.map { shape($0, depth + 1) } ?? .null])
            case .object(let values): return .object(values.mapValues { shape($0, depth + 1) })
            }
        }
        return .object(["object_name_property": shape(props), "object_name_history": shape(history)])
    }
    private static func firstString(_ value: JSONValue) -> String? {
        if let array = value.array { return array.first?.string }
        guard let string = value.string, !string.isEmpty else { return nil }
        if string.first == "[", let data = string.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) { return decoded.array?.first?.string }
        return string
    }
}

