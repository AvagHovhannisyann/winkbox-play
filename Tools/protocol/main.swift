// Talks to the real TV with the app's own PlayLink class: connects, pairs as the Play controller (the code on the TV's screen is
// handed over in /tmp/wb_code), lists the games, starts one, drives it and goes home. It exercises the phone's networking and
// cryptography against the TV's Java side, without a phone. Built with -D WB_NO_KEYCHAIN. usage: protocol <tv address> [--forget]
import Foundation

let host = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "192.168.1.8"
var failures = 0

func log(_ s: String) {
    print(s)
    fflush(stdout)
}

func check(_ what: String, _ ok: Bool, _ detail: String = "") {
    log("\(ok ? "PASS" : "FAIL")  \(what)\(detail.isEmpty ? "" : "  (\(detail))")")
    if !ok { failures += 1 }
}

@MainActor func until(_ timeout: Double = 10, _ cond: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if cond() { return true }
        try? await Task.sleep(nanoseconds: 40_000_000)
    }
    return cond()
}

@MainActor func run() async {
    let a = PlayLink()
    var seen: [[String: Any]] = []
    a.onTV = { seen.append($0) }
    a.host = host
    a.start()
    check("connects and the TV answers", await until(10) { a.canReach }, "\(a.link)")

    if !a.isPaired {
        a.beginPairing()
        check("TV sends a pairing challenge", await until(10) { a.pairing == .enterCode }, "\(a.pairing)")
        try? FileManager.default.removeItem(atPath: "/tmp/wb_code")
        log("WAITING_FOR_CODE (write the 6 digits shown on the TV into /tmp/wb_code)")
        var code = ""
        let end = Date().addingTimeInterval(240)
        while Date() < end {
            if let c = try? String(contentsOfFile: "/tmp/wb_code", encoding: .utf8) {
                code = c.trimmingCharacters(in: .whitespacesAndNewlines)
                if code.count == 6 { break }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        a.finishPairing(code: code)
        check("pairing with the code succeeds", await until(10) { a.isPaired }, a.pairingError ?? "\(a.pairing)")
    }
    check("the TV lets the paired phone in", await until(10) { a.link == .ready }, "\(a.link)")

    // right after sign-in the TV pushes the games, the player number and the (empty) layout
    check("the game list arrives", await until(5) { seen.contains { ($0["t"] as? String) == "games" } })
    let games = (seen.first { ($0["t"] as? String) == "games" }?["items"] as? [[String: Any]]) ?? []
    check("it has games with names and colours", !games.isEmpty && games.allSatisfy { ($0["name"] as? String) != nil && ($0["color"] as? String) != nil }, "\(games.count) games")
    check("this phone is player 1", await until(5) { seen.contains { ($0["t"] as? String) == "slot" && ($0["p"] as? Int) == 1 } })

    // things only the assistant's phone may do are refused
    seen.removeAll()
    a.send(["t": "say", "id": "x", "text": "hello"])
    check("a controller may not talk to the assistant", await until(5) { seen.contains { ($0["t"] as? String) == "error" && ($0["code"] as? String) == "role" } })

    // play the test game, drive it, and come home
    if games.contains(where: { ($0["id"] as? String) == "hello" }) {
        seen.removeAll()
        a.send(["t": "play", "id": "p1", "game": "hello"])
        check("the TV starts the game", await until(8) { seen.contains { ($0["t"] as? String) == "playing" } })
        check("and sends the game's controls", await until(10) { seen.contains { ($0["t"] as? String) == "pad" && ($0["layout"] as? [String: Any]) != nil } })
        a.sendInput(["t": "in", "k": "b", "n": "horn", "v": 1])
        check("pressing a button makes the phone buzz", await until(5) { seen.contains { ($0["t"] as? String) == "fx" } })
        a.sendInput(["t": "in", "k": "b", "n": "horn", "v": 0])
        seen.removeAll()
        a.send(["t": "home"])
        check("going home empties the controller", await until(8) { seen.contains { ($0["t"] as? String) == "pad" && ($0["game"] as? String) == "" } })
    } else {
        log("SKIP  no \"hello\" game in the catalog")
    }

    // a second PlayLink is the app starting again: it must sign in with the stored identity, no pairing.
    let b = PlayLink()
    b.host = host
    b.start()
    check("restarted app signs in with its stored identity", await until(10) { b.link == .ready }, "\(b.link)")
    b.stop()

    if CommandLine.arguments.contains("--forget") {
        a.forgetThisPhone()
        try? await Task.sleep(nanoseconds: 800_000_000)
        let c = PlayLink()
        c.host = host
        c.start()
        check("after forgetting, a new app has to pair again", await until(10) { c.link == .needsPairing }, "\(c.link)")
        c.stop()
    }
    a.stop()
    log(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
}

Task { @MainActor in
    await run()
    exit(failures == 0 ? 0 : 1)
}
dispatchMain()
