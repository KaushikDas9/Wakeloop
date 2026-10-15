import Foundation
import WakeloopCore

// Usage: wakeloop hold --for 30m | wakeloop done | wakeloop hook-snippet claude|codex | wakeloop lid-setup
func post(_ path: String) {
    var req = URLRequest(url: URL(string: "http://127.0.0.1:\(wakeloopPort)\(path)")!)
    req.httpMethod = "POST"
    req.timeoutInterval = 3
    let sem = DispatchSemaphore(value: 0)
    var failed = false
    URLSession.shared.dataTask(with: req) { _, _, err in failed = err != nil; sem.signal() }.resume()
    sem.wait()
    if failed { FileHandle.standardError.write(Data("Wakeloop app is not running.\n".utf8)); exit(1) }
}

func seconds(_ s: String) -> Int? {
    guard let unit = s.last, let n = Int(s.dropLast()) else { return nil }
    switch unit { case "s": return n; case "m": return n * 60; case "h": return n * 3600; default: return nil }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "hold":
    let dur = args.firstIndex(of: "--for").flatMap { args.indices.contains($0 + 1) ? seconds(args[$0 + 1]) : nil } ?? 1800
    post("/hold?seconds=\(dur)")
case "done":
    post("/done")
case "lid-setup":
    // Prints the one-time setup for lid-closed support; it changes nothing itself.
    let rule = LidManager.sudoersLine(user: NSUserName())
    print("""
    Lid-closed support needs a sudoers rule for exactly two pmset commands.
    Run:  sudo visudo -f /etc/sudoers.d/wakeloop
    Add this single line, save, then verify with:  sudo visudo -c

    \(rule)

    Remove it any time with:  sudo rm /etc/sudoers.d/wakeloop
    Warning: do not put a working Mac in a closed bag. Wakeloop still allows sleep on low battery or heat.
    """)
case "hook-snippet":
    // Prints a hooks config for the agent; it never edits the agent's own config files.
    guard args.count > 1, let json = HookSnippet.json(for: args[1]) else { print("usage: wakeloop hook-snippet claude|codex"); exit(2) }
    print(json)
default:
    print("usage: wakeloop hold [--for 30m] | wakeloop done | wakeloop hook-snippet claude|codex | wakeloop lid-setup")
    exit(2)
}
