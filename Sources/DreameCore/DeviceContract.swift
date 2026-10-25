import Foundation

public enum DeviceContract {
    public static let propertyPairs: [(Int,Int)] = [(2,1),(2,2),(3,1),(3,2),(4,1),(4,2),(4,3),(4,4),(4,5),(4,23),(4,25),(4,63),(4,64),(15,3),(15,5),(7,2),(7,3),(27,1),(27,2),(27,3),(27,4),(9,1),(10,1),(11,1),(16,1)]
    public static let groupedModels: Set<String> = ["dreame.vacuum.r2338a", "dreame.vacuum.r2377", "dreame.vacuum.r2338h"]
    public static let stateNames = [1:"Süpürüyor",2:"Boşta",3:"Duraklatıldı",4:"Hata",5:"İstasyona dönüyor",6:"Şarj oluyor",7:"Mopluyor",8:"Mopları kurutuyor",9:"Mopları yıkıyor",10:"Yıkama için dönüyor",11:"Harita oluşturuyor",12:"Süpürüyor ve mopluyor",13:"Şarj tamamlandı",14:"Güncelleniyor",20:"Su ekliyor",21:"Mop yıkama duraklatıldı",22:"Toz haznesini boşaltıyor",24:"Akıllı şarj",28:"Boşaltma için dönüyor",29:"Görev bekliyor",30:"İstasyon temizliği"]
    public static let suctionNames = [0:"Sessiz",1:"Standart",2:"Turbo",3:"Maks"]
    public static let modeNames = [0:"Yalnız süpür",1:"Yalnız mop",2:"Süpür + mop",3:"Süpür, sonra mop"]
    public static let waterNames = [1:"Az",2:"Orta",3:"Çok"]
    public static let baseNames = [0:"Hazır",1:"Mopları yıkıyor",2:"Mopları kurutuyor",3:"Dönüş bekliyor",4:"Duraklatıldı",5:"Su ekliyor"]

    public static func action(_ name: String, deviceID: String) throws -> [String:Any] {
        let mappings: [String:(Int,Int,String?)] = ["start":(2,1,nil),"pause":(2,2,nil),"dock":(3,1,nil),"stop":(4,2,nil),"locate":(7,1,nil),"auto_empty":(15,1,nil),"wash":(4,4,"2,1"),"wash_pause":(4,4,"1,0"),"dry_start":(4,4,"3,1"),"dry_stop":(4,4,"3,0")]
        guard let (siid,aiid,input) = mappings[name] else { throw ContractError.invalidCommand }
        return ["did":deviceID,"siid":siid,"aiid":aiid,"in":input.map { [["piid":10,"value":$0]] } ?? []]
    }
    public static func requireAcknowledgement(_ response: Any) throws {
        if let rows = response as? [[String:Any]] {
            guard !rows.isEmpty, rows.allSatisfy({ ($0["code"] as? Int) == 0 }) else { throw ContractError.rejected }
        } else if let row = response as? [String:Any] {
            guard let code = row["code"] as? Int, code == 0 else { throw ContractError.rejected }
        } else { throw ContractError.rejected }
    }
    public static func property(_ rows: [[String:Any]], _ siid:Int, _ piid:Int) -> Any? {
        rows.first { ($0["siid"] as? Int)==siid && ($0["piid"] as? Int)==piid && ($0["code"] as? Int)==0 }?["value"]
    }
    public static func updatedGrouped(_ raw: Int, mode:Int? = nil, water:Int? = nil) throws -> Int {
        var fields = [raw & 3, (raw >> 8) & -769, raw >> 16]
        if let mode { guard let encoded = [0:2,1:1,2:0,3:3][mode] else { throw ContractError.invalidValue }; fields[0] = encoded }
        if let water { guard (1...3).contains(water) else { throw ContractError.invalidValue }; fields[2] = water }
        return (fields[2] << 16) | (fields[1] << 8) | fields[0]
    }
    public enum ContractError: LocalizedError {
        case invalidCommand, invalidValue, rejected
        public var errorDescription: String? {
            switch self {
            case .invalidCommand: return Localization.text("Bilinmeyen komut.")
            case .invalidValue: return Localization.text("Geçersiz ayar değeri.")
            case .rejected: return Localization.text("Cihaz komutu kabul etmedi veya yanıt doğrulanamadı.")
            }
        }
    }
}
