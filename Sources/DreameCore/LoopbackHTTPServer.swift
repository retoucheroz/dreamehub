import Foundation
import Network

/// Loopback-only HTTP transport for explicitly enabled Tailscale Serve. One request per connection.
public final class LoopbackHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (String,String,[String:Any],String?) async -> [String:Any]
    public let token=UUID().uuidString+UUID().uuidString
    public private(set) var port:Int=0
    private let root:URL
    private let handler:Handler
    private let queue=DispatchQueue(label:"DreameHub.loopback")
    private var listener:NWListener?
    private var connections:[UUID:NWConnection]=[:]
    private var startupPending=true
    public init(resourceRoot:URL,handler:@escaping Handler) { root=resourceRoot.resolvingSymlinksInPath(); self.handler=handler }
    public func start() async throws -> Int {
        let parameters=NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
        let listener=try NWListener(using:parameters); self.listener=listener
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard self.startupPending,let port=listener.port else { return }; self.startupPending=false; self.port=Int(port.rawValue); continuation.resume(returning:self.port)
                case .failed(let error): if self.startupPending { self.startupPending=false; continuation.resume(throwing:error) }
                case .cancelled: if self.startupPending { self.startupPending=false; continuation.resume(throwing:ServerError.closed) }
                default:break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue:queue)
        }
    }
    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }; self.listener?.cancel(); self.listener=nil
            for connection in self.connections.values { connection.cancel() }; self.connections.removeAll()
        }
    }
    private func accept(_ connection:NWConnection) {
        let id=UUID(); connections[id]=connection
        connection.stateUpdateHandler = { [weak self] state in if case .cancelled=state { self?.connections[id]=nil } }
        connection.start(queue:queue)
        queue.asyncAfter(deadline:.now()+20) { [weak self,weak connection] in connection?.cancel(); self?.connections[id]=nil }
        receive(connection,buffer:Data())
    }
    private func receive(_ connection:NWConnection,buffer:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self] chunk,_,complete,error in
            guard let self else { connection.cancel(); return }
            var data=buffer; if let chunk { data.append(chunk) }
            if data.count>Self.maxBody+Self.maxHeaders { self.error(connection,413); return }
            do {
                if let request=try Self.parse(data) { Task { await self.handle(request,connection:connection) }; return }
            } catch { self.error(connection,400); return }
            if complete || error != nil { connection.cancel(); return }
            self.receive(connection,buffer:data)
        }
    }
    public static let maxBody=12*1024*1024
    public static let maxHeaders=16*1024
    public struct Request {
        public let method:String,path:String,headers:[String:String],body:Data
    }
    public static func parse(_ data:Data) throws -> Request? {
        guard let boundary=data.range(of:Data("\r\n\r\n".utf8)) else { if data.count>maxHeaders { throw ServerError.invalid }; return nil }
        guard boundary.lowerBound<=maxHeaders,let text=String(data:data[..<boundary.lowerBound],encoding:.utf8) else { throw ServerError.invalid }
        let lines=text.components(separatedBy:"\r\n"),first=lines[0].split(separator:" ")
        guard first.count==3,["GET","POST"].contains(String(first[0])),first[2]=="HTTP/1.1",first[1].hasPrefix("/"),!first[1].hasPrefix("//") else { throw ServerError.invalid }
        var headers:[String:String]=[:]
        for line in lines.dropFirst() {
            guard let colon=line.firstIndex(of:":"),!line.hasPrefix(" "),!line.hasPrefix("\t") else { throw ServerError.invalid }
            let key=String(line[..<colon]).lowercased(),value=String(line[line.index(after:colon)...]).trimmingCharacters(in:.whitespaces)
            guard !key.isEmpty,headers[key]==nil,key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0=="-") }),!value.contains("\0") else { throw ServerError.invalid }
            headers[key]=value
        }
        guard headers["transfer-encoding"]==nil else { throw ServerError.invalid }
        let length:Int
        if let raw=headers["content-length"] { guard !raw.isEmpty,raw.allSatisfy({ $0.isASCII && $0.isNumber }),let n=Int(raw),n>=0,n<=maxBody else { throw ServerError.invalid }; length=n } else { length=0 }
        guard first[0] != "GET" || length==0 else { throw ServerError.invalid }
        let body=data[boundary.upperBound...]
        guard body.count<=length else { throw ServerError.invalid }
        if body.count<length { return nil }
        return Request(method:String(first[0]),path:String(first[1]),headers:headers,body:Data(body))
    }
    /// Returns true only for Serve-authenticated remote requests; local Host must match exact listener port.
    public static func isRemote(_ request:Request,port:Int) throws -> Bool {
        guard let host=request.headers["host"],!host.contains("/"),!host.contains("@") else { throw ServerError.forbidden }
        if host=="127.0.0.1:\(port)" || host=="localhost:\(port)" { return false }
        let parts=host.split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==2,parts[1]=="8443",parts[0].hasSuffix(".ts.net"),parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0=="." || $0=="-") }),
              let identity=request.headers["tailscale-user-login"],!identity.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw ServerError.forbidden }
        return true
    }
    public static func remoteAllowed(path:String) -> Bool {
        let p=String(path.split(separator:"?",maxSplits:1).first ?? "")
        if ["/api/login","/api/logout","/api/credentials","/api/device/select"].contains(p) { return false }
        if p.hasPrefix("/api/credentials") || p.hasPrefix("/api/tailscale") || p.hasPrefix("/api/voice") || p.hasPrefix("/native/") { return false }
        return true
    }
    private func handle(_ request:Request,connection:NWConnection) async {
        do {
            let remote=try Self.isRemote(request,port:port)
            guard !remote || Self.remoteAllowed(path:request.path) else { throw ServerError.forbidden }
            if request.method=="POST" {
                guard request.headers["x-csrf-token"]==token,let origin=request.headers["origin"],let url=URL(string:origin),url.path.isEmpty || url.path=="/",url.user==nil,url.password==nil,
                      url.host.map({ host in host + ":" + String(url.port ?? (url.scheme=="https" ? 443 : 80)) })==request.headers["host"],url.scheme==(remote ? "https" : "http") else { throw ServerError.forbidden }
            }
            if request.path.hasPrefix("/api/") {
                var body:[String:Any]=[:],binary:String?
                if !request.body.isEmpty {
                    if request.headers["content-type"]?.lowercased().hasPrefix("application/json")==true {
                        guard let parsed=try JSONSerialization.jsonObject(with:request.body) as? [String:Any] else { throw ServerError.invalid }; body=parsed
                    } else { binary=request.body.base64EncodedString() }
                }
                var envelope=await handler(request.method,request.path,body,binary)
                if remote,request.path.split(separator:"?",maxSplits:1).first=="/api/state",var state=envelope["body"] as? [String:Any] { state["credentials"]=["available":false,"remembered":false,"username":"","region":""]; envelope["body"]=state }
                let status=envelope["status"] as? Int ?? 200
                if let base64=envelope["bodyBase64"] as? String,let data=Data(base64Encoded:base64) { send(connection,status:status,type:envelope["contentType"] as? String ?? "application/octet-stream",data:data) }
                else { let data=try JSONSerialization.data(withJSONObject:envelope["body"] ?? [:],options:[.fragmentsAllowed]); send(connection,status:status,type:"application/json",data:data) }
                return
            }
            guard request.method=="GET",let decoded=request.path.split(separator:"?",maxSplits:1).first.map(String.init)?.removingPercentEncoding,!decoded.contains("\0"),!decoded.split(separator:"/").contains("..") else { throw ServerError.invalid }
            let relative=decoded=="/" ? "index.html" : String(decoded.dropFirst())
            guard relative=="index.html" || relative.hasPrefix("assets/") else { throw ServerError.forbidden }
            let file=root.appendingPathComponent(relative).resolvingSymlinksInPath()
            guard file.path.hasPrefix(root.path+"/"),let data=try? Data(contentsOf:file),data.count<=24*1024*1024 else { error(connection,404); return }
            let types=["html":"text/html; charset=utf-8","css":"text/css","js":"application/javascript","png":"image/png","svg":"image/svg+xml","jpg":"image/jpeg","webp":"image/webp","ico":"image/x-icon"]
            if relative=="index.html" { guard let html=String(data:data,encoding:.utf8) else { throw ServerError.invalid }; send(connection,status:200,type:types["html"]!,data:Data(Localization.localizedPage(html.replacingOccurrences(of:"__TOKEN__",with:token)).utf8)) }
            else { send(connection,status:200,type:types[file.pathExtension] ?? "application/octet-stream",data:data) }
        } catch ServerError.forbidden { error(connection,403) }
        catch { self.error(connection,400) }
    }
    private func error(_ connection:NWConnection,_ status:Int) { send(connection,status:status,type:"application/json",data:(try? JSONSerialization.data(withJSONObject:["error":Localization.text("İstek kabul edilmedi.")])) ?? Data()) }
    private func send(_ connection:NWConnection,status:Int,type:String,data:Data) {
        let safeType=type.contains("\r") || type.contains("\n") ? "application/octet-stream" : type
        let header="HTTP/1.1 \(status) Response\r\nContent-Type: \(safeType)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: frame-ancestors 'none'\r\nConnection: close\r\n\r\n"
        connection.send(content:Data(header.utf8)+data,completion:.contentProcessed { _ in connection.cancel() })
    }
    public enum ServerError:Error { case invalid,forbidden,closed }
}
