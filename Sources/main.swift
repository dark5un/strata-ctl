import Cocoa

// StrataCtl — menu bar start/stop widget for the local Strata server.
// Polls http://127.0.0.1:<port>/health every 5s; Start/Stop/Restart drive
// the same command line the Strata launcher uses.
// Two variants share the port: the IQ3_XXS general model and the IQ1_M
// Coder (512K context); the menu switches between them.
//
// Overridable without rebuilding:
//   STRATA_DIR   where the Strata checkout lives (default ~/Projects/Strata)
//   STRATA_PORT  the server port (default 8080)

let strataDir = ((ProcessInfo.processInfo.environment["STRATA_DIR"]
                  ?? "~/Projects/Strata") as NSString).expandingTildeInPath
let strataPort = Int(ProcessInfo.processInfo.environment["STRATA_PORT"] ?? "") ?? 8080

struct Variant {
    let id: String          // stored in UserDefaults
    let label: String       // menu text
    let config: String      // config file name inside strataDir
}
let variants = [
    Variant(id: "xxs",   label: "IQ3_XXS (general)", config: "strata-iq3_xxs-1m.json"),
    Variant(id: "coder", label: "IQ1_M Coder (512K)", config: "strata-coder-iq1_m-512k.json"),
]
func selectedVariant() -> Variant {
    let saved = UserDefaults.standard.string(forKey: "strata.variant") ?? "xxs"
    return variants.first { $0.id == saved } ?? variants[0]
}
func serverCmd(_ v: Variant) -> String {
    "cd \"\(strataDir)\" && nohup .venv/bin/python serve/server.py --engine strata --config \(v.config) --port \(strataPort) >/dev/null 2>&1 &"
}
func stopCmd(_ v: Variant) -> String {
    "pkill -f 'serve/server.py --engine strata --config \(v.config)'"
}
let healthURL = URL(string: "http://127.0.0.1:\(strataPort)/health")!

enum State { case stopped, starting, running }

final class AppDelegate: NSObject, NSApplicationDelegate {
    var item: NSStatusItem!
    var state: State = .stopped
    var loaded = false
    var model = ""
    var ctx = 0
    var timer: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuild()
        let menu = NSMenu()
        menu.autoenablesItems = false
        item.menu = menu
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    // MARK: state

    func poll() {
        var req = URLRequest(url: healthURL)
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            guard let self else { return }
            var newState = State.stopped
            var nowLoaded = false
            var name = ""
            var ctx = 0
            if err == nil, let data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                nowLoaded = (obj["loaded"] as? Bool) ?? false
                name = (obj["model"] as? String) ?? ""
                ctx = (obj["max_context"] as? Int) ?? 0
                newState = nowLoaded ? .running : .starting
            }
            DispatchQueue.main.async {
                let changed = (newState != self.state) || (nowLoaded != self.loaded) || (name != self.model)
                self.state = newState
                self.loaded = nowLoaded
                self.model = name
                self.ctx = ctx
                if changed { self.rebuild() }
            }
        }.resume()
    }

    // The emblem: three stacked strata bands (rock layers) — a neutral mark
    // for the Strata server. Geometry: a slightly wavy top band, a straight
    // middle band, a wider base band, all inside a 22x17 point cell.
    //   stopped  -> outlined bands
    //   starting -> dashed outline
    //   running  -> filled bands
    func emblem(filled: Bool, dashed: Bool = false) -> NSImage {
        let img = NSImage(size: NSSize(width: 264, height: 204))
        img.lockFocus()

        // top band: rectangle with a smooth upward wavy crest
        let top = NSBezierPath()
        top.move(to: NSPoint(x: 38, y: 148))
        top.line(to: NSPoint(x: 38, y: 172))
        top.curve(to: NSPoint(x: 226, y: 172), controlPoint1: NSPoint(x: 90, y: 200), controlPoint2: NSPoint(x: 174, y: 200))
        top.line(to: NSPoint(x: 226, y: 148))
        top.close()

        // middle band
        let mid = NSBezierPath()
        mid.move(to: NSPoint(x: 24, y: 132))
        mid.line(to: NSPoint(x: 240, y: 132))
        mid.line(to: NSPoint(x: 240, y: 86))
        mid.line(to: NSPoint(x: 24, y: 86))
        mid.close()

        // base band (widest, flat bottom)
        let base = NSBezierPath()
        base.move(to: NSPoint(x: 24, y: 68))
        base.line(to: NSPoint(x: 240, y: 68))
        base.line(to: NSPoint(x: 240, y: 22))
        base.line(to: NSPoint(x: 24, y: 22))
        base.close()

        let bands = [top, mid, base]
        if filled {
            NSColor.white.setFill()
            for b in bands { b.fill() }
        } else {
            NSColor.black.set()
            for b in bands {
                b.lineWidth = 10
                if dashed { b.setLineDash([18, 14], count: 2, phase: 0) }
                b.stroke()
            }
        }
        img.unlockFocus()
        img.isTemplate = false
        img.size = NSSize(width: 22, height: 17)
        return img
    }

    func rebuild() {
        switch state {
        case .stopped:  item.button?.image = emblem(filled: false)
        case .starting: item.button?.image = emblem(filled: false, dashed: true)
        case .running:  item.button?.image = emblem(filled: true)
        }
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.autoenablesItems = false

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        // Model switcher: xxs <-> coder. Switching while the server runs
        // stops it and starts the other variant.
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        modelMenu.autoenablesItems = false
        let sel = selectedVariant()
        for v in variants {
            let it = NSMenuItem(title: v.label, action: #selector(selectVariant(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = v.id
            it.state = (v.id == sel.id) ? .on : .off
            modelMenu.addItem(it)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        menu.addItem(.separator())

        let start = NSMenuItem(title: "Start server", action: #selector(startServer), keyEquivalent: "s")
        start.target = self
        start.isEnabled = (state == .stopped)
        menu.addItem(start)

        let stop = NSMenuItem(title: "Stop server", action: #selector(stopServer), keyEquivalent: "t")
        stop.target = self
        stop.isEnabled = (state != .stopped)
        menu.addItem(stop)

        let restart = NSMenuItem(title: "Restart server", action: #selector(restartServer), keyEquivalent: "r")
        restart.target = self
        restart.isEnabled = (state != .stopped)
        menu.addItem(restart)

        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open web UI", action: #selector(openUI), keyEquivalent: "")
        open.target = self
        open.isEnabled = (state == .running)
        menu.addItem(open)

        let quit = NSMenuItem(title: "Quit StrataCtl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
    }

    func statusLine() -> String {
        switch state {
        case .stopped:  return "Stopped"
        case .starting: return "Loading model…"
        case .running:  return "Running · \(model) · \((ctx / 1024))K ctx"
        }
    }

    // MARK: actions

    @objc func selectVariant(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != selectedVariant().id else { return }
        let previous = selectedVariant()
        UserDefaults.standard.set(id, forKey: "strata.variant")
        if state != .stopped {
            // switch the running server over to the other variant:
            // stop the one that is actually running (the previous config),
            // then start the newly selected one.
            runShell(stopCmd(previous))
            state = .stopped
            rebuild()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.startServer()
            }
        } else {
            rebuild()
        }
    }

    @objc func startServer() {
        runShell(serverCmd(selectedVariant()))
        state = .starting
        rebuild()
    }

    @objc func stopServer() {
        // Match exactly this server's command line so nothing else is touched.
        runShell(stopCmd(selectedVariant()))
        state = .stopped
        rebuild()
    }

    @objc func restartServer() {
        stopServer()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.startServer()
        }
    }

    @objc func openUI() {
        NSWorkspace.shared.open(URL(string: "http://127.0.0.1:\(strataPort)")!)
    }

    func runShell(_ cmd: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
