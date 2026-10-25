import Foundation
import CryptoKit
import CommonCrypto

@_silgen_name("uncompress")
private func mapUncompress(_ destination: UnsafeMutablePointer<UInt8>, _ length: UnsafeMutablePointer<UInt>, _ source: UnsafePointer<UInt8>, _ sourceLength: UInt) -> Int32

/// Native port of the documented byte layout in Tasshack/dreame-vacuum's MIT map decoder.
/// No sensor rays, FOV, depth, distance or image pixels are synthesized here.
public enum MapDecoder {
    public enum Failure: Error, LocalizedError {
        case malformed(String), encryptedMapNeedsIV, decryption, compression, incrementalFrame
        public var errorDescription: String? {
            switch self {
            case .malformed(let reason): return Localization.text("Harita verisi geçersiz: {reason}",["reason":reason])
            case .encryptedMapNeedsIV: return Localization.text("Şifreli harita için modele ait 16 baytlık IV gerekli.")
            case .decryption: return Localization.text("Harita şifresi çözülemedi.")
            case .compression: return Localization.text("Harita sıkıştırması çözülemedi veya güvenli boyut sınırı aşıldı.")
            case .incrementalFrame: return Localization.text("Artımlı harita için önceki tam kare gerekli; tam harita yeniden istenmeli.")
            }
        }
    }

    public static func decode(_ raw: String, version: Int = 1, iv: String? = nil, key: String? = nil) throws -> [String: Any] {
        try decodeInflated(inflateEnvelope(raw, iv: iv, key: key), version: version)
    }
    public static func inflateEnvelope(_ raw: String, iv: String? = nil, key: String? = nil) throws -> Data {
        let parts = raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        var encoded = String(parts[0]).replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard var compressed = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), !compressed.isEmpty else { throw Failure.malformed("base64") }
        if let secret = key ?? (parts.count == 2 ? String(parts[1]) : nil) {
            guard let iv, iv.utf8.count == 16 else { throw Failure.encryptedMapNeedsIV }
            let digest = SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
            let aesKey = Data(digest.prefix(32).utf8)
            let ivData = Data(iv.utf8)
            var out = Data(count: compressed.count + kCCBlockSizeAES128)
            var moved = 0
            let capacity = out.count
            let status = out.withUnsafeMutableBytes { output in
                compressed.withUnsafeBytes { input in
                    aesKey.withUnsafeBytes { keyBytes in
                        ivData.withUnsafeBytes { ivBytes in
                            CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
                                    keyBytes.baseAddress, aesKey.count, ivBytes.baseAddress,
                                    input.baseAddress, compressed.count, output.baseAddress, capacity, &moved)
                        }
                    }
                }
            }
            guard status == kCCSuccess else { throw Failure.decryption }
            compressed = out.prefix(moved)
        }
        return try inflate(compressed)
    }

    /// Public for deterministic protocol-fixture tests; input is the inflated on-device map frame.
    public static func decodeInflated(_ data: Data, version requestedVersion: Int = 1, nestingDepth:Int = 0) throws -> [String: Any] {
        guard nestingDepth<=4 else { throw Failure.malformed(Localization.text("iç içe harita sınırı")) }
        let bytes = [UInt8](data)
        guard bytes.count >= 27 else { throw Failure.malformed(Localization.text("başlık kısa")) }
        func integer(_ offset: Int) -> Int { Int(Int16(bitPattern: UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8)) }
        guard bytes[4] == 73 else {
            if bytes[4] == 80 { throw Failure.incrementalFrame }
            throw Failure.malformed(Localization.text("desteklenmeyen kare türü {type}",["type":String(bytes[4])]))
        }
        let width = integer(19), height = integer(21), grid = integer(17)
        guard width > 0, height > 0, grid > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216, bytes.count >= 27 + width * height else { throw Failure.malformed(Localization.text("boyut veya hücre verisi")) }
        let jsonStart = 27 + width * height
        var metadata: [String: Any] = [:]
        if jsonStart < bytes.count {
            // Decrypted CBC blocks may have padding after the compressed zlib stream;
            // uncompress already ignores that. The JSON itself must be valid, not guessed.
            guard let object = try? JSONSerialization.jsonObject(with: Data(bytes[jsonStart...])),
                  let dict = object as? [String: Any] else { throw Failure.malformed("metadata JSON") }
            metadata = dict
        }
        let version = ["saveMapId", "cover", "diff", "curtain"].contains(where: { metadata[$0] != nil }) ? max(3, requestedVersion) : requestedVersion
        guard (0...3).contains(version) else { throw Failure.malformed(Localization.text("desteklenmeyen harita sürümü")) }
        let origin = metadata["origin"] as? [Int]
        let left = origin.flatMap { $0.count >= 2 ? $0[0] : nil } ?? integer(23)
        let top = origin.flatMap { $0.count >= 2 ? $0[1] : nil } ?? integer(25)
        guard (-100_000_000...100_000_000).contains(left), (-100_000_000...100_000_000).contains(top) else { throw Failure.malformed(Localization.text("harita başlangıç koordinatı")) }
        let status = number(metadata["ris"], fallback: -1)
        let frameMap = number(metadata["fsm"]) == 1
        var layers: [String: [Int]] = [:]
        var roomCells: [Int: (Int, Int, Int)] = [:]
        var minX = width, minY = height, maxX = -1, maxY = -1
        func add(_ kind: Int, _ x: Int, _ y: Int) {
            guard kind > 0 else { return }
            let key = String(kind)
            var runs = layers[key] ?? []
            if runs.count >= 3 && runs[runs.count - 2] == y && runs[runs.count - 3] + runs[runs.count - 1] == x {
                runs[runs.count - 1] += 1
            } else { runs += [x, y, 1] }
            layers[key] = runs
        }
        for y in 0..<height {
            for x in 0..<width {
                let p = Int(bytes[27 + y * width + x])
                let kind = pixelType(p, version: version, savedStatus: status, frameMap: frameMap)
                guard kind > 0 else { continue }
                add(kind, x, y)
                minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                if kind < 100 {
                    let old = roomCells[kind] ?? (0, 0, 0)
                    roomCells[kind] = (old.0 + x, old.1 + y, old.2 + 1)
                }
                let carpet = version == 3 ? p & 128 != 0 : (frameMap || status == 0 || status == 1 || status == 2 ? p & 3 == 3 : p & 64 != 0)
                if carpet { add(512, x, y) }
            }
        }
        let crop = maxX >= 0 ? [minX, height - maxY - 1, width - maxX - 1, minY] : [0, 0, 0, 0]
        let rotation = number(metadata["mra"])
        let segments: [[Any]] = roomCells.keys.sorted().map { id in
            let cell = roomCells[id]!
            let info = (metadata["seg_inf"] as? [String: [String: Any]])?[String(id)] ?? [:]
            return [id, left + cell.0 * grid / cell.2, top + cell.1 * grid / cell.2,
                    number(info["type"]), info["name"] ?? NSNull(), number(info["index"]), (id - 1) % 4]
        }
        func pose(_ offset: Int, _ absent: String) -> Any {
            let x = integer(offset), y = integer(offset + 2), angle = integer(offset + 4)
            return number(metadata[absent]) != 0 || angle == 32767 || (x == 32767 && y == 32767) ? NSNull() : [x, y, angle]
        }
        let obstacles = decodeObstacles(metadata["ai_obstacle"], version: version)
        let laser: [[Any]] = (metadata["laser_obstacle"] as? [[Any]] ?? []).compactMap { row in
            guard row.count >= 3, let x = numeric(row[0]), let y = numeric(row[1]) else { return nil }
            let confidence = row.count > 3 ? numeric(row[3]) : nil
            let percentage: Any = confidence.flatMap { (0...1).contains($0) ? Int($0 * 100) : nil } as Any? ?? NSNull()
            return [x, y, number(row[2]), percentage]
        }
        let thresholds = metadata["vws"] as? [String: Any] ?? [:]
        let cliffs = numericLines(thresholds["cliff"])
        let routes = path(metadata["tr"] as? String ?? "")
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let timestamp = numeric(metadata["timestamp_ms"]).flatMap { $0 >= 0 && $0 < Double(Int64.max) ? Int64($0) : nil }
        let wallCount = (layers["255"] ?? []).enumerated().filter { $0.offset % 3 == 2 }.reduce(0) { $0 + $1.element }
        let cellCount = layers.filter { $0.key != "512" }.values.reduce(0) { sum, runs in sum + runs.enumerated().filter { $0.offset % 3 == 2 }.reduce(0) { $0 + $1.element } }
        var result: [String: Any] = [
            "version": version, "map_id": integer(0), "frame_id": integer(2), "frame_type": "I",
            "timestamp_ms": timestamp as Any? ?? NSNull(), "rotation": rotation,
            "size": [left, top, left, top, width, height, grid, rotation, crop, NSNull()],
            "data": layers, "segments": segments, "path": routes, "robot_position": pose(5, "nr"),
            "charger_position": pose(11, "nc"), "obstacles": obstacles, "laser_obstacles": laser,
            "cliffs": cliffs, "empty_map": layers.isEmpty, "docked": number(metadata["oc"]) != 0,
            "saved_map_status": status, "saved_map": status == -1 && !frameMap && metadata["iscleanlog"] as? Bool != true,
            "history_map": metadata["iscleanlog"] as? Bool ?? false,
            "telemetry": ["source": "dreame_map", "pose_source": "map_entity",
                "observed_at": timestamp as Any? ?? NSNull(), "received_at": now,
                "freshness_ms": timestamp.map { max(0, now - $0) } as Any? ?? NSNull(),
                "actual": ["occupancy_grid", "robot_position", "path", "obstacles", "laser_obstacles", "cliffs"],
                "simulated": [String](),
                "capabilities": ["raw_lidar_rays": false, "raw_radar_frequency": false, "raw_vision_frames": false, "proximity_distances": false, "obstacle_photos": obstacles.contains { !($0[7] is NSNull) }],
                "metrics": ["frame_id": integer(2), "path_points": routes.reduce(0) { $0 + max(0, ($1.count - 1) / 2) },
                    "occupancy_cells": cellCount, "wall_cells": wallCount, "vision_objects": obstacles.count,
                    "laser_obstacles": laser.count, "cliffs": cliffs.count, "grid_mm": grid]],
        ]
        for (source, target) in [("cs", "cleaned_area"), ("ct", "cleaning_time"), ("wm", "work_status"), ("cf", "completed"), ("clean_finish_remain_electricity", "remaining_battery")] {
            if let value = metadata[source], value is NSNumber { result[target] = value }
        }
        let walls = metadata["vw"] as? [String: Any] ?? [:]
        result["virtual_walls"] = numericLines(walls["line"])
        result["no_go"] = walls["rect"] as? [[Any]] ?? []
        result["no_mop"] = walls["mop"] as? [[Any]] ?? []
        if let nested=metadata["rism"] as? String,!nested.isEmpty {
            let savedBytes=try inflateEnvelope(nested)
            let saved=try decodeInflated(savedBytes,version:version,nestingDepth:nestingDepth+1)
            try composeSaved(&result,currentBytes:bytes,metadata:metadata,savedBytes:[UInt8](savedBytes),saved:saved)
        }
        return result
    }

    private static func composeSaved(_ result:inout [String:Any],currentBytes:[UInt8],metadata:[String:Any],savedBytes:[UInt8],saved:[String:Any]) throws {
        guard let currentSize=result["size"] as? [Any],let savedSize=saved["size"] as? [Any],currentSize.count>=9,savedSize.count>=9 else { throw Failure.malformed(Localization.text("kayıtlı harita boyutu")) }
        let status=number(metadata["ris"],fallback:-1),fsm=number(metadata["fsm"])==1
        let empty=result["empty_map"] as? Bool ?? true
        let restored=number(metadata["rpur"])==1 || (empty && status==2 && !fsm)
        let recovery=number(metadata["us"])==1
        var segments=result["segments"] as? [[Any]] ?? []
        let savedSegments=saved["segments"] as? [[Any]] ?? []
        let useSavedGeometry=restored || recovery || (status==2 && (empty || (!fsm && number(result["version"]) != 0)))
        if useSavedGeometry {
            segments=savedSegments
            if status==2 && !fsm {
                let cl=number(currentSize[0]),ct=number(currentSize[1]),cw=number(currentSize[4]),ch=number(currentSize[5]),grid=number(currentSize[6])
                let sl=number(savedSize[0]),st=number(savedSize[1]),sw=number(savedSize[4]),sh=number(savedSize[5])
                guard grid>0,grid==number(savedSize[6]) else { throw Failure.malformed(Localization.text("kayıtlı harita hücre aralığı")) }
                let left=min(cl,sl),top=min(ct,st),width=(max(cl+cw*grid,sl+sw*grid)-left)/grid,height=(max(ct+ch*grid,st+sh*grid)-top)/grid
                guard width>0,height>0,width<=8192,height<=8192,width*height<=16_777_216,
                      currentBytes.count>=27+cw*ch,savedBytes.count>=27+sw*sh else { throw Failure.malformed(Localization.text("birleşik harita sınırı")) }
                var cells=[Int](repeating:0,count:width*height)
                let si=(sl-left)/grid,sj=(st-top)/grid,ni=(cl-left)/grid,nj=(ct-top)/grid
                for y in 0..<height { for x in 0..<width {
                    var sv:Int?,segment=0
                    if x>=si,y>=sj,x<si+sw,y<sj+sh { sv=Int(savedBytes[27+(y-sj)*sw+x-si]);segment=sv!&63 }
                    var clean=0
                    if !restored,x>=ni,y>=nj,x<ni+cw,y<nj+ch { clean=Int(currentBytes[27+(y-nj)*cw+x-ni])&3 }
                    var value=0
                    if segment != 0 || empty {
                        if restored,let sv { value=sv>>7==1 ? 255 : sv==63 ? 253 : segment }
                        else { value=clean==2 ? 255:segment }
                    } else if clean != 0 { value=clean==1 ? 254:clean==2 ? 255:253 }
                    cells[y*width+x]=value
                } }
                let geometry=encodeCells(cells,width:width,height:height)
                var layers=geometry.layers
                if restored,let carpets=(saved["data"] as? [String:[Int]])?["512"] {
                    var shifted=carpets
                    for i in stride(from:0,to:shifted.count,by:3) { shifted[i]+=si;shifted[i+1]+=sj }
                    layers["512"]=shifted
                } else if let carpets=(result["data"] as? [String:[Int]])?["512"] { layers["512"]=carpets }
                result["data"]=layers;result["size"]=[left,top,left,top,width,height,grid,number(result["rotation"]),geometry.crop,NSNull()]
                result["empty_map"]=false
            } else {
                result["data"]=saved["data"];result["size"]=saved["size"];result["empty_map"]=saved["empty_map"]
            }
        } else {
            for reference in savedSegments {
                guard reference.count>=7 else { continue }
                if let index=segments.firstIndex(where: { number($0.first)==number(reference.first) }) {
                    if status==2 { segments[index][1]=reference[1];segments[index][2]=reference[2] }
                    for field in 3..<min(segments[index].count,reference.count) { segments[index][field]=reference[field] }
                } else if status==2 { segments.append(reference) }
            }
        }
        result["segments"]=segments;result["saved_map_id"]=saved["map_id"]
        if result["charger_position"] is NSNull,(status==2 || number(metadata["oc"]) != 0),!recovery { result["charger_position"]=saved["charger_position"] }
        for key in ["virtual_walls","no_go","no_mop"] {
            if (result[key] as? [[Any]])?.isEmpty != false,let value=saved[key] { result[key]=value }
        }
        if var telemetry=result["telemetry"] as? [String:Any],var metrics=telemetry["metrics"] as? [String:Any],let layers=result["data"] as? [String:[Int]] {
            metrics["occupancy_cells"]=layers.filter{$0.key != "512"}.values.reduce(0) { sum,runs in sum+stride(from:2,to:runs.count,by:3).reduce(0){$0+runs[$1]} }
            metrics["wall_cells"]=stride(from:2,to:(layers["255"] ?? []).count,by:3).reduce(0){$0+(layers["255"] ?? [])[$1]}
            telemetry["metrics"]=metrics;result["telemetry"]=telemetry
        }
    }
    private static func encodeCells(_ cells:[Int],width:Int,height:Int) -> (layers:[String:[Int]],crop:[Int]) {
        var layers:[String:[Int]]=[:],minX=width,minY=height,maxX = -1,maxY = -1
        for y in 0..<height { for x in 0..<width {
            let type=cells[y*width+x];guard type>0 else { continue }
            let key=String(type);var r=layers[key] ?? []
            if r.count>=3,r[r.count-2]==y,r[r.count-3]+r[r.count-1]==x { r[r.count-1]+=1 } else { r += [x,y,1] }
            layers[key]=r;minX=min(x,minX);maxX=max(x,maxX);minY=min(y,minY);maxY=max(y,maxY)
        } }
        return (layers,maxX>=0 ? [minX,height-maxY-1,width-maxX-1,minY]:[0,0,0,0])
    }

    private static func inflate(_ input: Data) throws -> Data {
        for size in [262_144, 1_048_576, 4_194_304, 16_777_216, 33_554_432] {
            var result = [UInt8](repeating: 0, count: size), length = UInt(size)
            let status = input.withUnsafeBytes { pointer in
                mapUncompress(&result, &length, pointer.bindMemory(to: UInt8.self).baseAddress!, UInt(input.count))
            }
            if status == 0 { return Data(result.prefix(Int(length))) }
            if status != -5 { throw Failure.compression }
        }
        throw Failure.compression
    }
    private static func numeric(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = value as? String, let n = Double(s), n.isFinite { return n }
        return nil
    }
    private static func number(_ value: Any?, fallback: Int = 0) -> Int {
        guard let n = numeric(value), n >= Double(Int.min), n < Double(Int.max) else { return fallback }
        return Int(n)
    }
    private static func numericLines(_ input: Any?) -> [[Double]] {
        (input as? [[Any]] ?? []).compactMap { row in
            guard row.count >= 4 else { return nil }
            let values = row.prefix(4).compactMap { numeric($0) }
            return values.count == 4 ? values : nil
        }
    }
    private static func pixelType(_ p: Int, version: Int, savedStatus: Int, frameMap: Bool) -> Int {
        guard p > 0 else { return 0 }
        if version == 3 {
            let segment = p & 31, wall = (p >> 5) & 3
            if segment == 0 { return 0 }
            if segment == 31 { return wall == 3 ? 231 : wall > 0 ? 255 : (savedStatus == 0 || savedStatus == 1 ? 253 : 254) }
            return wall == 3 ? 200 + segment : wall > 0 ? 100 + segment : segment
        }
        if frameMap {
            let segment = p >> 2
            if segment > 0 { return segment == 63 ? 255 : segment == 62 ? 254 : segment == 61 ? 252 : segment }
            return p & 63 == 2 ? 255 : (p & 63 == 1 || p & 63 == 3 ? 253 : 0)
        }
        if savedStatus == 0 || savedStatus == 1 { return p & 63 == 2 ? 255 : (p & 63 == 1 || p & 63 == 3 ? 253 : 0) }
        if savedStatus == 2 { return p & 63 == 0 ? 0 : (p & 63 == 2 ? 255 : 253) }
        let segment = p & 63
        return p >> 7 != 0 ? (segment == 0 ? 255 : 100 + segment) : segment
    }
    private static func path(_ input: String) -> [[Int]] {
        let expression = try! NSRegularExpression(pattern: "([MWSLl])(-?\\d+),(-?\\d+)")
        let text = input as NSString
        var groups: [[Int]] = [], group: [Int] = [], x = 0, y = 0
        for match in expression.matches(in: input, range: NSRange(location: 0, length: text.length)) {
            let op = text.substring(with: match.range(at: 1))
            guard let xx = Int(text.substring(with: match.range(at: 2))), let yy = Int(text.substring(with: match.range(at: 3))) else { continue }
            if op == "L" {
                let nextX=x.addingReportingOverflow(xx),nextY=y.addingReportingOverflow(yy)
                guard !nextX.overflow,!nextY.overflow else { continue }
                x=nextX.partialValue;y=nextY.partialValue
            } else { x = xx; y = yy }
            if op != "L" && op != "l" {
                if group.count > 2 { groups.append(group) }
                group = [op == "S" ? 1 : op == "W" ? 2 : 3]
            }
            if group.isEmpty { group = [3] }
            group += [x, y]
        }
        if group.count > 2 { groups.append(group) }
        return groups
    }
    private static func decodeObstacles(_ input: Any?, version: Int) -> [[Any]] {
        var result: [[Any]] = []
        for row in input as? [[Any]] ?? [] {
            guard row.count >= 4, let x = numeric(row[0]), let y = numeric(row[1]), let certainty = numeric(row[3]) else { continue }
            guard (0...1).contains(certainty) else { continue }
            let type = number(row[2]), probability = Int(certainty * 100)
            if version == 3 && probability > 0 && probability < 50 { continue }
            let last=String(describing:row.last ?? "")
            let ignore = row.count > 18 ? number(row[18]) : (last.count==1 && (0...4).contains(number(row.last,fallback:-1)) ? number(row.last):0)
            if ignore == 3 || ignore == 4 || (version == 3 && ignore == 2) { continue }
            // The device's original object id is retained for authenticated photo retrieval;
            // its presence does not promise that a photo actually exists.
            let id: Any = row.count > 4 && String(describing: row[4]).trimmingCharacters(in: .whitespaces) != "" ? row[4] : NSNull()
            let detailed=row.count>=8 && ((numeric(id) ?? 0)>=1000)
            func position(_ at:Int) -> Any { detailed && row.count>at ? (numeric(row[at]).map{$0*100} as Any? ?? NSNull()):NSNull() }
            result.append([String(result.count + 1), x, y, type, probability, ignore,
                           detailed ? (row.count>=13 ? number(row[11]):2):0, id,
                           position(7),position(8),position(9),position(10),NSNull(),NSNull(),NSNull(),NSNull()])
        }
        return result
    }
}

/// Ordered legacy frame-map and v3 full/delta accumulator. Caller isolates access (MapService is an actor).
/// Missing predecessors and incompatible grids fail rather than invent cells.
public final class MapStreamDecoder {
    private var base: Data?
    private var version = 1
    public init() {}
    public func reset() { base = nil }
    public func accept(_ raw: String, version: Int = 1, iv: String? = nil, key: String? = nil) throws -> [String: Any] {
        try acceptInflated(MapDecoder.inflateEnvelope(raw, iv: iv, key: key), version: version)
    }
    public func acceptInflated(_ incoming: Data, version: Int = 1) throws -> [String: Any] {
        let p = [UInt8](incoming)
        guard p.count >= 27 else { throw MapDecoder.Failure.malformed(Localization.text("artımlı başlık")) }
        func i16(_ data: [UInt8], _ n: Int) -> Int { Int(Int16(bitPattern: UInt16(data[n]) | UInt16(data[n+1]) << 8)) }
        if p[4] == 73 {
            let result = try MapDecoder.decodeInflated(incoming, version: version)
            base = incoming; self.version = result["version"] as? Int ?? version
            return result
        }
        guard p[4] == 80, let base else { throw MapDecoder.Failure.incrementalFrame }
        let b = [UInt8](base)
        guard i16(b,0) == i16(p,0),
              UInt16(bitPattern: Int16(i16(p,2))) == UInt16(bitPattern: Int16(i16(b,2))) &+ 1 else {
            throw MapDecoder.Failure.incrementalFrame
        }
        let bw = i16(b,19), bh = i16(b,21), pw = i16(p,19), ph = i16(p,21), grid = i16(b,17)
        guard grid > 0, i16(p,17) == grid, pw >= 0, ph >= 0,
              pw <= 8192, ph <= 8192, pw * ph <= 16_777_216, p.count >= 27 + pw * ph else {
            throw MapDecoder.Failure.malformed(Localization.text("artımlı boyut"))
        }
        func json(_ data: [UInt8], _ width: Int, _ height: Int) throws -> [String:Any] {
            let start = 27 + width * height
            guard start <= data.count else { throw MapDecoder.Failure.malformed(Localization.text("artımlı metadata")) }
            if start == data.count { return [:] }
            guard let object = try JSONSerialization.jsonObject(with: Data(data[start...])) as? [String:Any] else { throw MapDecoder.Failure.malformed(Localization.text("artımlı metadata")) }
            return object
        }
        var old = try json(b,bw,bh)
        var delta = try json(p,pw,ph)
        // Legacy non-frame-map encodings need separate retained pixel-type state. V3
        // uses direct replacement bytes and does not have that ambiguous encoding switch.
        guard self.version==3 || old["fsm"] as? Int == 1 else { throw MapDecoder.Failure.incrementalFrame }
        let changes=delta["diff"] as? [String:Any] ?? [:]
        if self.version==3,let cover=delta["cover"] as? [String:Any] {
            for key in ["timestamp_ms","tr","small_tr","moptype","laser_obstacle"] { if let value=cover[key] { delta[key]=value } }
        }
        let bo = old["origin"] as? [Int], po = delta["origin"] as? [Int]
        let bl = bo.flatMap { $0.count > 1 ? $0[0] : nil } ?? i16(b,23)
        let bt = bo.flatMap { $0.count > 1 ? $0[1] : nil } ?? i16(b,25)
        let pl = po.flatMap { $0.count > 1 ? $0[0] : nil } ?? i16(p,23)
        let pt = po.flatMap { $0.count > 1 ? $0[1] : nil } ?? i16(p,25)
        let left = min(bl,pl), top = min(bt,pt)
        guard (bl-left)%grid == 0, (pl-left)%grid == 0, (bt-top)%grid == 0, (pt-top)%grid == 0 else { throw MapDecoder.Failure.incrementalFrame }
        let w = (max(bl+bw*grid,pl+pw*grid)-left)/grid, h = (max(bt+bh*grid,pt+ph*grid)-top)/grid
        guard w > 0, h > 0, w <= 8192, h <= 8192, w*h <= 16_777_216,
              (-32768...32767).contains(left), (-32768...32767).contains(top) else { throw MapDecoder.Failure.malformed(Localization.text("birleşik boyut")) }
        var cells = [UInt8](repeating:0,count:w*h)
        let bx=(bl-left)/grid, by=(bt-top)/grid, px=(pl-left)/grid, py=(pt-top)/grid
        for y in 0..<bh { for x in 0..<bw { cells[(y+by)*w+x+bx]=b[27+y*bw+x] } }
        for y in 0..<ph { for x in 0..<pw {
            let value=p[27+y*pw+x]
            if value != 0 { let at=(y+py)*w+x+px; cells[at] = self.version==3 ? value : cells[at] &+ value }
        } }
        if let route=delta["tr"] as? String, !route.isEmpty {
            // A relative L as first operation lacks a trustworthy local anchor.
            guard route.first != "L" else { throw MapDecoder.Failure.incrementalFrame }
            old["tr"]=(old["tr"] as? String ?? "")+route
        }
        if self.version==3 {
            let incoming=(changes["ai_obstacle"] ?? delta["ai_obstacle"]) as? [[Any]]
            var obstacles=old["ai_obstacle"] as? [[Any]] ?? []
            func identity(_ row:[Any]) -> String { row.count>=13 ? String(describing:row[12]):"null" }
            if let incoming {
                for object in incoming {
                    if let index=obstacles.firstIndex(where:{identity($0)==identity(object)}) { obstacles[index]=object }
                    else { obstacles.append(object) }
                }
            }
            if let deleted=(changes["deleteContent"] as? [String:Any])?["ai_obstacle"] as? [Any] {
                let ids=Set(deleted.map{String(describing:$0)})
                obstacles.removeAll{ids.contains(identity($0))}
            }
            old["ai_obstacle"]=obstacles
        }
        for (key,value) in delta where key != "tr" && key != "cover" && key != "diff" && !(self.version==3 && key=="ai_obstacle") { old[key]=value }
        old["origin"]=[left,top]; old["fsm"]=1
        // Processed laser detections are packet observations, not permanent map records.
        old["laser_obstacle"]=delta["laser_obstacle"] ?? []
        var header=Array(p.prefix(27)); header[4]=73
        func put(_ at:Int,_ n:Int) { let v=UInt16(bitPattern:Int16(n));header[at]=UInt8(v&255);header[at+1]=UInt8(v>>8) }
        put(19,w);put(21,h);put(23,left);put(25,top)
        let merged=Data(header+cells)+(try JSONSerialization.data(withJSONObject:old))
        var result=try MapDecoder.decodeInflated(merged,version:self.version)
        result["frame_type"]="P";result["incremental_verified_chain"]=true
        self.base=merged
        return result
    }
}
