import Foundation
import Network

public let wakeloopPort: UInt16 = 47821

/// Minimal localhost HTTP listener. POST /event takes hook JSON; POST /hold?seconds=N and POST /done drive the CLI.
public final class HookServer {
    public enum Message {
        case event(session: String, AgentEvent, cwd: String?)
        case hold(seconds: TimeInterval)
        case done
    }

    private let listener: NWListener
    private let handler: (Message) -> Void

    public init(port: UInt16 = wakeloopPort, handler: @escaping (Message) -> Void) throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.handler = handler
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] conn in self?.serve(conn) }
        listener.start(queue: .global())
    }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: .global())
        receive(conn, buffer: Data())
    }

    /// HTTP bodies can arrive in a later TCP chunk than the headers, so accumulate until Content-Length is met.
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if !Self.isComplete(buf) && !isComplete && error == nil && buf.count < (1 << 22) {
                self.receive(conn, buffer: buf)
                return
            }
            self.route(buf)
            let ok = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}"
            conn.send(content: ok.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }

    static func isComplete(_ buf: Data) -> Bool {
        guard let text = String(data: buf, encoding: .utf8), let sep = text.range(of: "\r\n\r\n") else { return false }
        let headers = text[..<sep.lowerBound].lowercased()
        guard let line = headers.split(separator: "\r\n").first(where: { $0.hasPrefix("content-length:") }),
              let len = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) else { return true }
        return text[sep.upperBound...].utf8.count >= len
    }

    private func route(_ raw: Data) {
        guard let text = String(data: raw, encoding: .utf8),
              let lineEnd = text.range(of: "\r\n") else { return }
        let requestLine = text[..<lineEnd.lowerBound].split(separator: " ")
        guard requestLine.count >= 2 else { return }
        let path = String(requestLine[1])
        if path.hasPrefix("/done") { handler(.done) }
        else if path.hasPrefix("/hold") {
            let secs = URLComponents(string: path)?.queryItems?.first { $0.name == "seconds" }?.value.flatMap(Double.init) ?? 1800
            handler(.hold(seconds: secs))
        } else if path.hasPrefix("/event"),
                  let sep = text.range(of: "\r\n\r\n"),
                  let parsed = HookPayload.parse(Data(text[sep.upperBound...].utf8)) {
            handler(.event(session: parsed.session, parsed.event, cwd: parsed.cwd))
        }
    }
}
