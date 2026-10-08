import Testing
import Foundation
@testable import WakeloopCore

struct HookServerTests {
    @Test func incompleteUntilBodyMatchesContentLength() {
        let head = "POST /event HTTP/1.1\r\nContent-Length: 5\r\n\r\n"
        #expect(!HookServer.isComplete(Data((head + "ab").utf8)))
        #expect(HookServer.isComplete(Data((head + "abcde").utf8)))
        #expect(!HookServer.isComplete(Data("POST /event HTTP/1.1\r\nContent-Le".utf8)))
    }

    @Test func requestWithoutContentLengthIsCompleteAtHeaderEnd() {
        #expect(HookServer.isComplete(Data("POST /done HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
    }

    /// Real loopback round trips through the listener on a high port.
    @Test func routesEventHoldAndDone() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let box = Box()
        let server = try HookServer(port: port) { box.append($0) }
        server.start()
        try await Task.sleep(nanoseconds: 300_000_000)

        func post(_ path: String, body: String = "") async throws {
            var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
            req.httpMethod = "POST"
            req.httpBody = Data(body.utf8)
            _ = try await URLSession.shared.data(for: req)
        }
        try await post("/event", body: #"{"hook_event_name":"UserPromptSubmit","session_id":"s9"}"#)
        try await post("/hold?seconds=90")
        try await post("/done")

        let got = box.messages
        #expect(got.count == 3)
        guard got.count == 3 else { return }
        if case .event(let s, let e) = got[0] { #expect(s == "s9"); #expect(e == .promptSubmit) } else { Issue.record("expected event") }
        if case .hold(let secs) = got[1] { #expect(secs == 90) } else { Issue.record("expected hold") }
        if case .done = got[2] {} else { Issue.record("expected done") }
    }

    @Test func malformedEventBodyIsIgnoredButAnswered() async throws {
        let port = UInt16.random(in: 49_000...60_000)
        let box = Box()
        let server = try HookServer(port: port) { box.append($0) }
        server.start()
        try await Task.sleep(nanoseconds: 300_000_000)
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/event")!)
        req.httpMethod = "POST"
        req.httpBody = Data("not json".utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        #expect((resp as? HTTPURLResponse)?.statusCode == 200)
        #expect(box.messages.isEmpty)
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [HookServer.Message] = []
    func append(_ m: HookServer.Message) { lock.lock(); items.append(m); lock.unlock() }
    var messages: [HookServer.Message] { lock.lock(); defer { lock.unlock() }; return items }
}
