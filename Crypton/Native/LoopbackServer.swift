import Foundation
import Network

struct LoopbackRequest {
    let method: String
    let path: String
    let headers: [String:String]
    let body: Data
    static let maxBody = 8_000_000
    /// Returns nil until the complete bounded HTTP/1.1 request has arrived.
    static func parse(_ data: Data) throws -> LoopbackRequest? {
        guard let separator = data.range(of:Data("\r\n\r\n".utf8)) else {
            guard data.count <= 8192 else { throw CryptonError("HTTP headers too large.") }; return nil
        }
        guard separator.lowerBound <= 8192, let head = String(data:data[..<separator.lowerBound],encoding:.ascii) else { throw CryptonError("Invalid HTTP headers.") }
        let lines = head.components(separatedBy:"\r\n"), first = lines[0].components(separatedBy:" ")
        guard first.count == 3, ["GET","POST"].contains(first[0]), first[1].hasPrefix("/"), !first[1].contains("?"), first[2] == "HTTP/1.1" else { throw CryptonError("Invalid HTTP request.") }
        var headers: [String:String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of:":") else { throw CryptonError("Invalid HTTP header.") }
            let name = String(line[..<colon]).lowercased(), value = line[line.index(after:colon)...].trimmingCharacters(in:.whitespaces)
            guard name.range(of:"^[a-z0-9-]+$",options:.regularExpression) != nil, headers[name] == nil, !value.unicodeScalars.contains(where:{ $0.value < 32 || $0.value == 127 }) else { throw CryptonError("Invalid or duplicate HTTP header.") }
            headers[name] = value
        }
        guard headers["transfer-encoding"] == nil else { throw CryptonError("Chunked requests are not supported.") }
        let rawLength = headers["content-length"] ?? "0"
        guard rawLength.range(of:"^[0-9]{1,8}$",options:.regularExpression) != nil, let length = Int(rawLength), length <= maxBody, first[0] != "GET" || length == 0 else { throw CryptonError("Invalid HTTP body length.") }
        let start = separator.upperBound
        guard data.count <= start + length else { throw CryptonError("Unexpected HTTP data.") }
        guard data.count == start + length else { return nil }
        return LoopbackRequest(method:first[0],path:first[1],headers:headers,body:Data(data[start...]))
    }
}
struct LoopbackResponse {
    var status = 200
    var type = "application/json"
    var body = Data("{}".utf8)
    init(status:Int = 200,type:String = "application/json",body:Data = Data("{}".utf8)) { self.status = status; self.type = type; self.body = body }
    var sent: (() -> Void)?
    var wire: Data {
        let header = "HTTP/1.1 \(status) Response\r\nContent-Type: \(type); charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'\r\n\r\n"
        return Data(header.utf8) + body
    }
}

/// Device-only HTTP with a strict parser, bounded connections/bodies and idle deadlines.
/// Authorization of every route belongs to the ME session on the main actor.
final class LoopbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label:"crypton.me.loopback")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier:NWConnection] = [:]
    private var deadlines: [ObjectIdentifier:DispatchWorkItem] = [:]
    private var startContinuation: CheckedContinuation<UInt16,Error>?
    private var handler: ((LoopbackRequest, @escaping (LoopbackResponse) -> Void) -> Void)?
    @MainActor func start(handler:@escaping (LoopbackRequest,@escaping (LoopbackResponse) -> Void) -> Void) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.handler = handler; self.startContinuation = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host:"127.0.0.1",port:.any)
                    let listener = try NWListener(using:parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self,weak listener] state in
                        guard let self = self else { return }
                        switch state {
                        case .ready:
                            guard let port = listener?.port?.rawValue else { self.started(.failure(CryptonError("Could not bind the wallet bridge."))); return }
                            self.started(.success(port))
                        case .failed(let error): self.started(.failure(error)); self.stopOnQueue()
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                    listener.start(queue:self.queue)
                } catch { self.started(.failure(error)) }
            }
        }
    }
    private func started(_ result:Result<UInt16,Error>) { let done = startContinuation; startContinuation = nil; done?.resume(with:result) }
    private func accept(_ connection:NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = ObjectIdentifier(connection); clients[id] = connection
        let deadline = DispatchWorkItem { [weak self, weak connection] in if let connection = connection { self?.close(connection) } }
        deadlines[id] = deadline; queue.asyncAfter(deadline:.now()+5,execute:deadline)
        connection.stateUpdateHandler = { [weak self,weak connection] state in
            if case .failed = state, let connection = connection { self?.close(connection) }
        }
        connection.start(queue:queue); receive(connection,Data())
    }
    private func receive(_ connection:NWConnection,_ buffered:Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:65_536) { [weak self,weak connection] bytes,_,ended,error in
            guard let self = self, let connection = connection, self.clients[ObjectIdentifier(connection)] != nil else { return }
            var data = buffered; if let bytes = bytes { data.append(bytes) }
            guard data.count <= LoopbackRequest.maxBody + 8196 else { self.respond(connection,LoopbackResponse(status:413)); return }
            do {
                if let request = try LoopbackRequest.parse(data) {
                    guard let handler = self.handler else { self.close(connection); return }
                    handler(request) { [weak self,weak connection] response in
                        guard let self = self, let connection = connection else { return }
                        self.queue.async { if self.clients[ObjectIdentifier(connection)] != nil { self.respond(connection,response) } }
                    }
                } else if ended || error != nil { self.close(connection) }
                else { self.receive(connection,data) }
            } catch { self.respond(connection,LoopbackResponse(status:400)) }
        }
    }
    private func respond(_ connection:NWConnection,_ response:LoopbackResponse) {
        connection.send(content:response.wire,completion:.contentProcessed { [weak self,weak connection] _ in
            guard let self = self, let connection = connection else { return }; self.close(connection); response.sent?()
        })
    }
    private func close(_ connection:NWConnection) {
        let id = ObjectIdentifier(connection); clients.removeValue(forKey:id); deadlines.removeValue(forKey:id)?.cancel(); connection.cancel()
    }
    func stop() { queue.async { self.stopOnQueue() } }
    private func stopOnQueue() {
        started(.failure(CryptonError("Wallet bridge closed.")))
        listener?.cancel(); listener = nil; handler = nil
        for client in Array(clients.values) { close(client) }
    }
}
