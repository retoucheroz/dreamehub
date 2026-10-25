import Foundation
import CryptoKit
import CommonCrypto
import Security

/// Retrieves only a device-provided obstacle image; it never creates replacement imagery.
public actor ObstaclePhotoService {
    private let cloud:CloudClient
    public init(cloud:CloudClient) { self.cloud=cloud }
    private static let localRegistry = #"[[1,"YWViZjhjNTJlMjZhNDc2Nw==","r23646,r2475t,r24896,r2501,r2501l,r2501p,r2502,r2507,r2508,r2513,r25135,r2513a,r2513f,r2513h,r2513k,r2513p,r2513u,r2515,r2518,r2518a,r2518f,r2518j,r2518p,r2525a,r2525e,r2525h,r2527,r2527a,r2527b,r2527g,r2527h,r2527j,r2527q,r2527t,r2527u,r2535,r2548,r2561,r2580,r2581,r2582a,r2582c,r2582h,r2582k,r2582r,r25856,r25857,r25858,r25859,r2587a,r2587r,r2599,r2599h,r2599k,r2599u,r2599v,r500b,r500b1,r500c,r500c1,r500da,r500n,r500vh,r500vp,r500xb,r500yb,r500yc,r500ye,r500yt,r5016,r501ba,r501bc,r501bk,r501bt,r501da,r501h,r501he,r501s,r501st,r501t,r501tt,r501ua,r501vr,r501vt,r501w,r501wu,r5023a,r5023e,r5024b,r5024t,r5025b,r5025t,r502ca,r502k3,r502ka,r502ke,r502la,r502le,r502mf,r502mn,r502mt,r502va,r5039,r50391,r50393,r50395,r50397,r50398,r50399,r5039a,r5039e,r5039f,r5039h,r5039r,r5039w,r5049,r50573,r5057a,r5057k,r5057r,r5061,r5061a,r5061e,r50625,r5062a,r5062h,r5062k,r5064t,r5064u,r5082a,r5082c,r5085,r50855,r5089b,r5089u,r5090a,r5099,r5099a,r5099e,r5099g,r5099h,r5099k,r5104h,r5109f,r510b,r510b1,r510c,r510c1,r510n,r5117,r512g,r512mf,r5139,r51395,r5149,r5185,r51855,r5189j,r5189u,r520b,r520b1,r520c,r520c1,r520n,r522kf,r5239f,r5299,r530jb,r530ua,r53456,r5345b,r5345e,r540jb,r540tb,r5765h,r5765k,r5765p,r5765q,r5765u,r5766,r5766h,r5766k,r5766q,r5766v,r5769,r57695,r57698,r5769a,r5769f,r5769g,r5769h,r5769q,r5769r,r5769t,r5770,r5770a,r5770g,r5770h,r5770q,r5770t,r5770v,r5871,r58715,r590q,r590qf,r5977a,r5977c,r5977f,r5977g,r5977h,r5977k,r5977r,r5977t,r5978a,r5978h,r5978q,r59795,r59796,r59797,r59799,r5979a,r5979f,r5979g,r5979h,r5979t,r5979u,r6001a,r6011,r6012,r6015a,r6016,r6017b,r6017q,r6047a,r6101h,r6111,r6112,r6116,r6117j,r6216,r67095,r6709a,r6709c,r6709g,r6709h,r6709r,r6710a,r6710g,r6710h,r6710r,r6710t,r94345,r9473,r9473e,r9482,r9503,r9506,r9508b,r9513,r9515a,r9515e,r9516,r9517,r9518,r9519,r95285,r9528a,r9528h,r9533a,r9533h,r9533t,r9535a,r9535h,r9535n,r95406,r9540a,r9540h,r9540k,r9540n,r9540u,r9540v,r9542a,r9542b,r9542h,r9542t,r9543,r9543a,r9543b,r9543r,r95445,r9544a,r9544b,r9544t,r95475,r95476,r9547a,r9547c,r9547h,r9547k,r9548,r9549,r9551"],[1430,"YWViZjhjNTJlMjZhNDc2Nw==","r24898,r2489c,r2489d,r2489e,r2489f,r2489j,r2489p,r2489q,r2489s,r2489z,r2505z,r2532d,r2532v,r2538z,r2560,r50485,r5048a,r5048h,r94346,r9434j,r9434l,r9445d,r9445g,r9446b,r9446c,r9446k,r9455z,r9471z,r9483,r9486z,r95385,r9538a,r9538b,r9538c,r9538e,r9538h,r9538k,r9538l,r9538t,r9538u"],[2149,"YWViZjhjNTJlMjZhNDc2Nw==","r2489a,r2489h"],[2186,"YWViZjhjNTJlMjZhNDc2Nw==","r2489b,r2489k,r2489l,r2532z,r2538a,r9434v,r9446a,r9446h"],[2159,"YWViZjhjNTJlMjZhNDc2Nw==","r2489t,r2489u,r2532a,r2532h,r2532w,r9434h"],[3414,"YWViZjhjNTJlMjZhNDc2Nw==","r2571,r2572,r9461"],[1500,"YWViZjhjNTJlMjZhNDc2Nw==","r2573,r2574,r510a"],[1451,"YWViZjhjNTJlMjZhNDc2Nw==","r2575,r2576,r9476,r9477,r9478,r9489,r9490,r9491"],[1681,"YWViZjhjNTJlMjZhNDc2Nw==","r25799,r2579a,r2579c,r2579h,r2579k,r500z9,r500za,r500zc,r500zh,r500zk"],[1582,"YWViZjhjNTJlMjZhNDc2Nw==","r500a,r60u2k,r9493a,r9493c"],[2155,"YWViZjhjNTJlMjZhNDc2Nw==","r9419,r9425,r9426,r9430,r9441"],[1577,"YWViZjhjNTJlMjZhNDc2Nw==","r9419a,r9419e,r9419h,r9419t"],[2114,"YWViZjhjNTJlMjZhNDc2Nw==","r9493h"],[1170,"YWViZjhjNTJlMjZhNDc2Nw==","r95425"]]"#
    private static func localStorageIV(device:CloudDevice) -> Data? {
        guard let data=localRegistry.data(using:.utf8),let groups=try? JSONSerialization.jsonObject(with:data) as? [[Any]],let model=device.model.split(separator:".").last else { return nil }
        let firmware=device.raw["deviceInfo"]["version"].string ?? device.raw["version"].string ?? ""
        let build=Int(firmware.split(separator:"_").last ?? "") ?? 1
        for group in groups where group.count==3 {
            guard let threshold=group[0] as? Int,let encoded=group[1] as? String,let models=group[2] as? String,models.split(separator:",").contains(model),build>=threshold,let iv=Data(base64Encoded:encoded),iv.count==16 else { continue }
            return iv
        }
        return nil
    }
    public enum Failure:Error,LocalizedError {
        case unavailable, unsupportedStorage, decryption, invalidImage
        public var errorDescription:String? {
            switch self {
            case .unavailable:return Localization.text("Bu nesnenin fotoğraf kaydı yok veya artık erişilemiyor.")
            case .unsupportedStorage:return Localization.text("Bu modelin yerel fotoğraf şifreleme akışı henüz doğrulanmadı.")
            case .decryption:return Localization.text("Nesne fotoğrafının şifresi çözülemedi.")
            case .invalidImage:return Localization.text("Cihazdan gelen dosya geçerli bir fotoğraf değil.")
            }
        }
    }
    public func image(device:CloudDevice,capture:MapService.Capture,index:String) async throws -> Data {
        let decoded=try MapDecoder.decode(capture.raw,version:capture.version,iv:capture.iv,key:capture.key)
        guard let rendered=decoded["obstacles"] as? [[Any]],let chosen=rendered.first(where:{ String(describing:$0[0]) == index }),chosen.count>7,
              !(chosen[7] is NSNull) else { throw Failure.unavailable }
        let objectID=String(describing:chosen[7])
        let bytes=[UInt8](try MapDecoder.inflateEnvelope(capture.raw,iv:capture.iv,key:capture.key))
        guard bytes.count>=27 else { throw Failure.unavailable }
        let w=Int(UInt16(bytes[19])|UInt16(bytes[20])<<8),h=Int(UInt16(bytes[21])|UInt16(bytes[22])<<8)
        let start=27+w*h
        guard start<bytes.count,let metadata=try JSONSerialization.jsonObject(with:Data(bytes[start...])) as? [String:Any],
              let rows=metadata["ai_obstacle"] as? [[Any]],let row=rows.first(where:{$0.count>4 && String(describing:$0[4])==objectID}),row.count>=7 else { throw Failure.unavailable }
        let fileIndex=row.count>=8 ? 5:6,keyIndex=row.count>=8 ? 6:5
        guard let file=row[fileIndex] as? String,!file.isEmpty else { throw Failure.unavailable }
        if row.count>=13,let status=row[11] as? Int,status != 2 { throw Failure.unavailable }
        if let iv=Self.localStorageIV(device:device) {
            let encrypted=try await cloud.deviceFile(device:device,filename:file,type:"obstacle")
            let key=try await devicePhotoKey(device:device)
            let aesKey=Data(Insecure.MD5.hash(data:Data(key.utf8)).map { String(format:"%02x",$0) }.joined().utf8)
            return try Self.decrypt(encrypted,key:aesKey,iv:iv)
        }
        guard let key=row[keyIndex] as? String,!key.isEmpty else { throw Failure.unavailable }
        let signed=try await cloud.fileURL(device:device,objectName:file+"-"+objectID,interim:false)
        guard let value=signed.string ?? signed["url"].string,let url=URL(string:value) else { throw Failure.unavailable }
        let encrypted=try await cloud.download(url:url)
        return try Self.decrypt(encrypted,key:Data(Insecure.MD5.hash(data:Data(key.utf8))),iv:nil)
    }
    private static func decrypt(_ encrypted:Data,key aesKey:Data,iv:Data?) throws -> Data {
        var out=Data(count:encrypted.count+16),moved=0
        let capacity=out.count
        let status=out.withUnsafeMutableBytes { output in encrypted.withUnsafeBytes { input in aesKey.withUnsafeBytes { keyBytes in
            let options=CCOptions(kCCOptionPKCS7Padding | (iv == nil ? kCCOptionECBMode : 0))
            if let iv { return iv.withUnsafeBytes { bytes in CCCrypt(CCOperation(kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),options,keyBytes.baseAddress,aesKey.count,bytes.baseAddress,input.baseAddress,encrypted.count,output.baseAddress,capacity,&moved) } }
            return CCCrypt(CCOperation(kCCDecrypt),CCAlgorithm(kCCAlgorithmAES),options,keyBytes.baseAddress,aesKey.count,nil,input.baseAddress,encrypted.count,output.baseAddress,capacity,&moved)
        }}}
        guard status==kCCSuccess else { throw Failure.decryption }
        let image=out.prefix(moved)
        guard Self.contentType(image) != nil else { throw Failure.invalidImage }
        return image
    }
    /// Read-only cryptographic key exchange, upstream SIID 14 / AIID 1 / PIID 5.
    /// The private RSA key exists only in memory; it is never persisted or exported.
    private func devicePhotoKey(device:CloudDevice) async throws -> String {
        var failure:Unmanaged<CFError>?
        let attributes:[String:Any]=[kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeySizeInBits as String:1024]
        guard let privateKey=SecKeyCreateRandomKey(attributes as CFDictionary,&failure),let publicKey=SecKeyCopyPublicKey(privateKey),
              let pkcs1=SecKeyCopyExternalRepresentation(publicKey,&failure) as Data? else { throw Failure.decryption }
        let spki=Self.subjectPublicKeyInfo(pkcs1)
        let result=try await cloud.rpc(device:device,method:"action",params:.object(["did":.string(device.id),"siid":.integer(14),"aiid":.integer(1),"in":.array([.object(["piid":.integer(5),"value":.string(spki.base64EncodedString())])])]))
        guard result["code"].int == 0 || result["code"] == .null,
              let encoded=result["out"].array?.first?["value"].string else { throw Failure.unavailable }
        var normalized=encoded.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/")
        normalized+=String(repeating:"=",count:(4-normalized.count%4)%4)
        guard let encrypted=Data(base64Encoded:normalized),SecKeyIsAlgorithmSupported(privateKey,.decrypt,.rsaEncryptionOAEPSHA1),
              let data=SecKeyCreateDecryptedData(privateKey,.rsaEncryptionOAEPSHA1,encrypted as CFData,&failure) as Data?,
              let key=String(data:data,encoding:.utf8),!key.isEmpty else { throw Failure.decryption }
        return key
    }
    static func subjectPublicKeyInfo(_ pkcs1:Data) -> Data {
        func der(_ tag:UInt8,_ body:Data) -> Data {
            var length=Data()
            if body.count<128 { length.append(UInt8(body.count)) }
            else if body.count<256 { length.append(contentsOf:[0x81,UInt8(body.count)]) }
            else { length.append(contentsOf:[0x82,UInt8(body.count>>8),UInt8(body.count&255)]) }
            return Data([tag])+length+body
        }
        let algorithm=Data([0x30,0x0d,0x06,0x09,0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01,0x05,0x00])
        return der(0x30,algorithm+der(0x03,Data([0])+pkcs1))
    }
    public static func contentType(_ data:Data) -> String? {
        if data.starts(with:[0xff,0xd8,0xff]) { return "image/jpeg" }
        if data.starts(with:[0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a]) { return "image/png" }
        if data.count>=12,data.prefix(4)==Data("RIFF".utf8),data.dropFirst(8).prefix(4)==Data("WEBP".utf8) { return "image/webp" }
        return nil
    }
}
