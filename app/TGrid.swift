// TGrid — menu bar UI for t-GRID.
// Native Terminal.app windows, arranged from a little grid picker in the menu bar.
// Build: ./app/build.sh   —   https://github.com/ali2407/t-GRID

import SwiftUI
import AppKit

// MARK: - shell plumbing

struct ShellResult {
    let output: String
    let ok: Bool
}

enum Shell {
    /// Runs a tool and always comes back — a hung osascript (the Automation
    /// consent prompt, a beachballing Terminal) gets killed rather than pinning
    /// a task forever. stderr is merged in so failures are never silent.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 25) -> ShellResult {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return ShellResult(output: "not found: \(path)", ok: false)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        // An app launched by LaunchServices has "/" as its working directory.
        // Never let that leak into a spawned shell.
        p.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe

        do { try p.run() } catch {
            return ShellResult(output: error.localizedDescription, ok: false)
        }

        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()

        let text = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ShellResult(output: text, ok: p.terminationStatus == 0)
    }

    static func jxa(_ src: String) -> ShellResult {
        run("/usr/bin/osascript", ["-l", "JavaScript", "-e", src])
    }

    static let tgrid: String = {
        let home = NSHomeDirectory()
        let candidates = [
            "/opt/homebrew/bin/tgrid",
            "/usr/local/bin/tgrid",
            home + "/.local/bin/tgrid",
            home + "/bin/tgrid",
            home + "/t-grid/bin/tgrid",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/tgrid"
    }()

    static var tgridInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: tgrid)
    }

    /// `tgrid-queue` ships beside `tgrid` and install.sh links them together, so
    /// finding one finds the other. Kept separate anyway: an older install that
    /// only has `tgrid` should lose the queue, not the whole menu.
    static let tgridQueue: String = {
        let sibling = (tgrid as NSString).deletingLastPathComponent + "/tgrid-queue"
        if FileManager.default.isExecutableFile(atPath: sibling) { return sibling }
        return NSHomeDirectory() + "/t-grid/bin/tgrid-queue"
    }()

    static var queueInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: tgridQueue)
    }
}

// MARK: - model

struct DisplayInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    var aspect: CGFloat { CGFloat(width) / CGFloat(max(height, 1)) }
    var label: String { "\(width)×\(height)" }
}

struct Session: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let display: Int
    let busy: Bool
}

@MainActor
final class Model: ObservableObject {
    @Published var displays: [DisplayInfo] = []
    @Published var sessions: [Session] = []
    @Published var status: String = ""
    @Published var failed = false
    @Published var working = false
    @Published var needsPermission = false

    // persisted preferences — a tool you reach for daily should not forget
    // your monitor and your gap every time it restarts
    @Published var display: Int  { didSet { d.set(display, forKey: "display") } }
    @Published var rows: Int     { didSet { d.set(rows, forKey: "rows") } }
    @Published var cols: Int     { didSet { d.set(cols, forKey: "cols") } }
    @Published var gap: Int      { didSet { d.set(gap, forKey: "gap") } }
    @Published var onlyHere: Bool { didSet { d.set(onlyHere, forKey: "onlyHere") } }
    @Published var theme: Bool   { didSet { d.set(theme, forKey: "theme") } }
    @Published var plates: Bool  {
        didSet {
            d.set(plates, forKey: "plates")
            plates ? nameplates.start() : nameplates.stop()
        }
    }
    @Published var board: Bool {
        didSet {
            d.set(board, forKey: "board")
            board ? queueBoard.start() : queueBoard.stop()
        }
    }
    let nameplates = Nameplates()
    let queueBoard = QueueBoard()
    @Published var workDir: String { didSet { d.set(workDir, forKey: "workDir") } }

    private let d = UserDefaults.standard
    private var loading = false

    init() {
        display  = d.object(forKey: "display") as? Int ?? 0
        rows     = d.object(forKey: "rows") as? Int ?? 0
        cols     = d.object(forKey: "cols") as? Int ?? 0
        gap      = d.object(forKey: "gap") as? Int ?? 6
        onlyHere = d.object(forKey: "onlyHere") as? Bool ?? false
        theme    = d.object(forKey: "theme") as? Bool ?? false
        plates   = d.object(forKey: "plates") as? Bool ?? false
        board    = d.object(forKey: "board") as? Bool ?? false
        workDir  = d.object(forKey: "workDir") as? String ?? NSHomeDirectory()
        if !FileManager.default.fileExists(atPath: workDir) { workDir = NSHomeDirectory() }
        if plates { nameplates.start() }      // a setting that survives a restart
                                              // has to actually come back up
        if board { queueBoard.start() }
    }

    var isAuto: Bool { rows == 0 || cols == 0 }
    var newCount: Int { isAuto ? 4 : rows * cols }
    var workDirName: String {
        workDir == NSHomeDirectory() ? "Home" : (workDir as NSString).lastPathComponent
    }
    var toolMissing: Bool { !Shell.tgridInstalled }
    /// The button says how many hands are up, so the count is readable without
    /// opening anything — that is the whole point of the queue.
    var queueLabel: String {
        let n = QueueStore.shared.entries.count
        return n == 0 ? "Queue" : "Queue (\(n))"
    }

    func refresh() {
        displays = NSScreen.screens.enumerated().map { i, s in
            DisplayInfo(id: i, name: s.localizedName,
                        width: Int(s.frame.width), height: Int(s.frame.height))
        }
        if display >= displays.count { display = 0 }
        loadSessions()
    }

    /// Every shell call goes off the main thread. osascript can block for a long
    /// time — e.g. while macOS shows the Automation consent prompt — and a blocked
    /// main thread means a frozen, empty-looking panel.
    private func loadSessions() {
        guard !loading else { return }        // don't stack refreshes while polling
        loading = true
        let terminalRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Terminal"
        }
        let js = """
        var T = Application('Terminal'); var out = [];
        for (var i = 0; i < T.windows.length; i++) {
          var w = T.windows[i];
          try {
            if (w.miniaturized()) continue;
            var b = w.bounds();
            var t = w.tabs[0];
            var procs = [];
            try { procs = t.processes(); } catch (e) {}
            out.push({ id: w.id(), name: w.name(), x: b.x,
                       busy: (function(){ try { return t.busy(); } catch(e) { return false; } })(),
                       proc: procs.length ? procs[procs.length - 1] : '' });
          } catch (e) {}
        }
        JSON.stringify(out)
        """
        Task.detached(priority: .userInitiated) {
            let raw = Shell.jxa(js)
            await MainActor.run {
                self.loading = false
                guard let data = raw.output.data(using: .utf8),
                      let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else {
                    self.sessions = []
                    self.needsPermission = terminalRunning
                    return
                }
                self.needsPermission = false
                let fresh = arr.compactMap { d -> Session? in
                    guard let id = d["id"] as? Int else { return nil }
                    let (title, sub) = Model.prettify(d["name"] as? String ?? "",
                                                      proc: d["proc"] as? String ?? "")
                    return Session(id: id, title: title, subtitle: sub,
                                   display: Model.displayIndex(forX: d["x"] as? Int ?? 0),
                                   busy: d["busy"] as? Bool ?? false)
                }
                if fresh != self.sessions { self.sessions = fresh }   // avoid needless redraws
            }
        }
    }

    /// Terminal titles look like "albert — ✳ 100k — Python ◂ claude --resume — 131×24".
    /// Keep the human part, throw away the user name and the ×-size suffix.
    static func prettify(_ name: String, proc: String) -> (String, String) {
        var parts = name.components(separatedBy: " — ").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if parts.count > 1, parts.last?.range(of: #"^\d+×\d+$"#, options: .regularExpression) != nil {
            parts.removeLast()
        }
        if parts.count > 1 { parts.removeFirst() }   // user name
        let head = parts.first ?? name
        let title = head.trimmingCharacters(in: CharacterSet(charactersIn: "✳✻✽◐◑◒◓✢· "))
        let tail = parts.dropFirst().joined(separator: " · ")
        return (title.isEmpty ? (proc.isEmpty ? "shell" : proc) : title,
                tail.isEmpty ? proc : tail)
    }

    static func displayIndex(forX x: Int) -> Int {
        for (i, s) in NSScreen.screens.enumerated() {
            let left = Int(s.frame.origin.x)
            if x >= left && x < left + Int(s.frame.width) { return i }
        }
        return 0
    }

    // MARK: actions

    private func gridArgs() -> [String] {
        var a = ["-D", String(display), "-g", String(gap)]
        if !isAuto { a += ["-r", String(rows), "-k", String(cols)] }
        return a
    }

    func sort() {
        var args = ["--reflow"] + gridArgs()
        if onlyHere { args.append("--here") }
        // An explicitly chosen layout is a request for that many slots, so top up
        // to it. On Auto the grid follows the window count and there is nothing
        // to fill — asking would spawn windows the user never asked for.
        if !isAuto { args += ["--fill", "-d", workDir] }
        if theme { args.append("--theme") }
        runTgrid(args)
    }

    // The deck: one window centred, the rest parked at the edges. step 0 lays it
    // out, ±1 walks the ring.
    func deck(_ step: Int = 0) {
        var args = [step == 0 ? "--deck" : (step > 0 ? "--next" : "--prev"),
                    "-D", String(display)]
        if onlyHere { args.append("--here") }
        if theme { args.append("--theme") }
        runTgrid(args)
    }

    // The queue: whoever has been waiting longest is put in front of you, the
    // rest line up behind. step 0 stages it, ±1 walks the line. Never resizes —
    // that is `tgrid-queue`'s rule, not this button's, but it is the reason this
    // is not just another call to deck().
    func queue(_ step: Int = 0) {
        var args = [step == 0 ? "--queue" : (step > 0 ? "--queue-next" : "--queue-prev"),
                    "-D", String(display)]
        if onlyHere { args.append("--here") }
        runTgrid(args)
        QueueStore.shared.refresh()
    }

    func newGrid() {
        var args = [String(newCount), "-d", workDir] + gridArgs()
        if theme { args.append("--theme") }
        runTgrid(args)
    }

    func undo() { runTgrid(["--undo"]) }

    private func runTgrid(_ args: [String]) {
        guard !working else { return }
        working = true
        let tool = Shell.tgrid
        // The first themed run imports a Terminal profile per accent, and every
        // import costs a window that has to open and close again. That is well
        // past the default timeout, and it only ever happens once.
        let limit: TimeInterval = args.contains("--theme") ? 90 : 25
        Task.detached(priority: .userInitiated) {
            let r = Shell.run(tool, args, timeout: limit)
            await MainActor.run {
                self.status = r.output.replacingOccurrences(of: "tgrid: ", with: "")
                self.failed = !r.ok
                if self.status.isEmpty && !r.ok { self.status = "failed" }
                self.working = false
                self.refresh()
            }
        }
    }

    func focus(_ s: Session) {
        let js = """
        var T = Application('Terminal');
        var w = T.windows.byId(\(s.id));
        w.index = 1; w.visible = true; T.activate();
        """
        Task.detached { _ = Shell.jxa(js) }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workDir)
        panel.prompt = "Use folder"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            workDir = url.path
        }
    }
}

// MARK: - grid picker

// MARK: - the queue
//
// `tgrid-queue` decides who is waiting, in what order, and what each one is
// asking. It writes that to ~/.cache/tgrid/queue.json. Nothing in the app works
// any of it out for itself — the app reads the file, and shelling out to the
// tool is also what keeps the behaviour log filling up while the app is open.

struct QueueEntry: Identifiable, Hashable {
    let window: Int
    let rank: Int
    let title: String
    let where_: String
    let ask: String
    let waited: Double
    let state: String
    var id: Int { window }

    /// "4m" / "1h20m". Deliberately coarse: the number is there to tell you
    /// which one has been standing there longest, not to be a stopwatch.
    var wait: String {
        let s = Int(waited)
        if s < 90 { return "\(s)s" }
        if s < 5400 { return "\(s / 60)m" }
        return "\(s / 3600)h\(String(format: "%02d", (s % 3600) / 60))m"
    }
}

@MainActor
final class QueueStore: ObservableObject {
    static let shared = QueueStore()

    @Published private(set) var entries: [QueueEntry] = []
    @Published private(set) var thinking: [String] = []
    private(set) var byWindow: [CGWindowID: QueueEntry] = [:]

    private var timer: Timer?
    private var refreshing = false
    private var clients = 0

    var path: String {
        let base = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"]
            ?? NSHomeDirectory() + "/.cache"
        return base + "/tgrid/queue.json"
    }

    /// Reference-counted, because both the nameplates and the queue board want
    /// the same data and either one may be switched off at any time.
    func retain() {
        clients += 1
        guard clients == 1 else { return }
        load()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func release() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        timer?.invalidate(); timer = nil
    }

    /// Re-run the tool. This is the background monitor: every scan diffs against
    /// the last one and appends what changed to events.jsonl, so simply leaving
    /// t-GRID running is what builds the history a learned ranking would need.
    func refresh() {
        guard !refreshing, Shell.queueInstalled else { return }
        refreshing = true
        let tool = Shell.tgridQueue
        Task.detached(priority: .utility) {
            _ = Shell.run(tool, ["json"], timeout: 30)
            await MainActor.run {
                self.refreshing = false
                self.load()
            }
        }
    }

    func load() {
        guard let data = FileManager.default.contents(atPath: path),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        let rows = (root["queue"] as? [[String: Any]]) ?? []
        let fresh = rows.compactMap { r -> QueueEntry? in
            guard let w = r["window"] as? Int, let rank = r["rank"] as? Int else { return nil }
            return QueueEntry(window: w, rank: rank,
                              title: (r["title"] as? String) ?? "",
                              where_: (r["where"] as? String) ?? "",
                              ask: (r["ask"] as? String) ?? "",
                              waited: (r["waited_s"] as? Double) ?? 0,
                              state: (r["state"] as? String) ?? "waiting")
        }.sorted { $0.rank < $1.rank }
        let busy = ((root["other"] as? [[String: Any]]) ?? [])
            .filter { ($0["state"] as? String) == "thinking" }
            .compactMap { $0["title"] as? String }
        if fresh != entries { entries = fresh }
        if busy != thinking { thinking = busy }
        byWindow = Dictionary(uniqueKeysWithValues: fresh.map { (CGWindowID($0.window), $0) })
    }
}

// The line itself, as a panel. The windows can only ever show the order in
// z-order and a title bar's worth of offset — and when the sessions are close to
// full height even that offset has nowhere to go. The board is the part that
// always works: one row per session, in order, each with the sentence.
struct QueueBoardView: View {
    let entries: [QueueEntry]
    let thinking: [String]
    let palette: [Color]
    let onPick: (QueueEntry) -> Void

    private func accent(_ e: QueueEntry) -> Color {
        palette.isEmpty ? .accentColor : palette[(e.rank - 1) % palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "hand.raised.fill").font(.system(size: 9))
                Text(entries.isEmpty ? "nobody is waiting"
                                     : "\(entries.count) waiting for you")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 6)

            ForEach(entries) { e in
                QueueRow(e: e, accent: accent(e), front: e.rank == entries.first?.rank)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(e) }
            }

            if !thinking.isEmpty {
                Text("thinking: " + thinking.joined(separator: ", "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, 11).padding(.vertical, 7)
            }
        }
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5))
        )
    }
}

struct QueueRow: View {
    let e: QueueEntry
    let accent: Color
    let front: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(e.rank)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(front ? Color.white : accent)
                .frame(width: 17, height: 17)
                .background(Circle().fill(accent.opacity(front ? 0.95 : 0.18)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(e.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(e.where_).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(e.wait).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                Text(e.ask)
                    .font(.system(size: 10))
                    .foregroundStyle(e.state == "stalled" ? .tertiary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(front ? accent.opacity(0.09) : .clear)
    }
}

@MainActor
final class QueueBoard {
    private var panel: NameplatePanel?
    private var timer: Timer?
    private var palette: [Color] = []
    private(set) var running = false

    func start() {
        guard !running else { return }
        running = true
        palette = Nameplates.loadPalette()
        QueueStore.shared.retain()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        sync()
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        QueueStore.shared.release()
    }

    private func sync() {
        let q = QueueStore.shared
        q.load()
        let p = panel ?? {
            let n = NameplatePanel()
            n.ignoresMouseEvents = false          // rows are clickable, unlike a plate
            panel = n
            return n
        }()
        let view = QueueBoardView(entries: q.entries, thinking: q.thinking,
                                  palette: palette) { e in
            let js = """
            var T = Application('Terminal'); var w = T.windows.byId(\(e.window));
            w.index = 1; w.visible = true; T.activate();
            """
            Task.detached { _ = Shell.jxa(js) }
        }
        let host = NSHostingView(rootView: view)
        host.layout()
        let size = host.fittingSize
        p.contentView = host

        // Park it on the display the front session is on, top-left, clear of the
        // menu bar. Following the front window rather than sitting on a fixed
        // screen means the board turns up wherever the work is.
        let screen = screenOfFront() ?? NSScreen.main
        if let s = screen {
            let f = s.visibleFrame
            p.setFrame(NSRect(x: f.minX + 18, y: f.maxY - size.height - 14,
                              width: max(size.width, 380), height: size.height),
                       display: false)
        }
        if !p.isVisible { p.orderFront(nil) }
    }

    private func screenOfFront() -> NSScreen? {
        guard let front = QueueStore.shared.entries.first else { return nil }
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]],
              let row = raw.first(where: { ($0[kCGWindowNumber as String] as? Int) == front.window }),
              let b = row[kCGWindowBounds as String] as? [String: CGFloat],
              let x = b["X"], let w = b["Width"]
        else { return nil }
        let mid = x + w / 2
        return NSScreen.screens.first { $0.frame.minX <= mid && mid < $0.frame.maxX }
    }
}

// MARK: - nameplates
//
// Terminal.app has no API for custom chrome, so nothing can draw a header
// INSIDE its window. What nothing stops you doing is putting a panel of your own
// on top of one. Each plate is a borderless floating panel parked exactly over
// its window's title bar, between the traffic lights and Terminal's own split
// button, showing an icon, the session name and its accent.
//
// The plate is click-through (`ignoresMouseEvents`). That matters more than it
// sounds: the title bar underneath keeps working, so the window still drags,
// double-click still zooms, and nothing about Terminal behaves differently
// because there is a picture floating over it.

struct PlateView: View {
    let name: String
    let sub: String
    let accent: Color
    let symbol: String
    let busy: Bool
    // Set when this window is standing in the queue. The plate is the only piece
    // of chrome t-GRID owns on a Terminal window, so the orientation sentence
    // goes here: the thing you read before you type anything.
    var queued: QueueEntry? = nil

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .fill(accent.opacity(queued != nil ? 0.9 : 0.20))
                if let q = queued {
                    Text("\(q.rank)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 17, height: 17)

            Text(name)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .layoutPriority(2)

            if let q = queued {
                Text(q.wait)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .layoutPriority(2)
                Text(q.ask)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            } else if !sub.isEmpty {
                Text("·").font(.system(size: 11)).foregroundStyle(.tertiary)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if busy && queued == nil {
                Circle().fill(Color.green.opacity(0.9)).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(accent.opacity(0.30), lineWidth: 0.5)
                )
        )
    }
}

final class NameplatePanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 22),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true            // the title bar underneath still works
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isReleasedWhenClosed = false
    }
}

struct PlateInfo {
    var name: String
    var rawName: String
    var sub: String
    var accent: Int      // 1-based index into the t-GRID palette, 0 = untinted
    var busy: Bool
}

@MainActor
final class Nameplates {
    private var panels: [CGWindowID: NameplatePanel] = [:]
    private var info: [CGWindowID: PlateInfo] = [:]
    private var geometryTimer: Timer?
    private var infoTimer: Timer?
    private var palette: [Color] = []
    private(set) var running = false

    // Terminal's title bar, and the two zones of it that belong to Terminal:
    // the traffic lights on the left and the split-pane button on the right.
    private let barHeight: CGFloat = 28
    private let leftInset: CGFloat = 76
    private let rightInset: CGFloat = 34

    func start() {
        guard !running else { return }
        running = true
        loadPalette()
        QueueStore.shared.retain()      // plates show the queue rank and the sentence
        // Geometry is cheap and needs no permission, so it can run often enough
        // that a dragged window does not leave its plate behind. Titles come from
        // Apple Events, which are not cheap, so they run on their own slow timer.
        geometryTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.syncGeometry() }
        }
        infoTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshInfo() }
        }
        syncGeometry()
        refreshInfo()
    }

    func stop() {
        running = false
        QueueStore.shared.release()
        geometryTimer?.invalidate(); geometryTimer = nil
        infoTimer?.invalidate(); infoTimer = nil
        for (_, p) in panels { p.orderOut(nil) }
        panels.removeAll()
        info.removeAll()
    }

    /// One palette, defined in `tgrid`. Asking the tool for it beats keeping a
    /// second copy here that drifts the first time the colours are tuned.
    static func loadPalette() -> [Color] {
        let r = Shell.run(Shell.tgrid, ["--palette"], timeout: 5)
        return r.output.split(separator: "\n").compactMap { Color(hex: String($0)) }
    }

    private func loadPalette() { palette = Nameplates.loadPalette() }

    private func terminalWindows() -> [(id: CGWindowID, frame: CGRect)] {
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        return raw.compactMap { w in
            guard (w[kCGWindowOwnerName as String] as? String) == "Terminal",
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let n = w[kCGWindowNumber as String] as? CGWindowID,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  width > 220, height > 120
            else { return nil }
            return (n, CGRect(x: x, y: y, width: width, height: height))
        }
    }

    private func syncGeometry() {
        let live = terminalWindows()
        let ids = Set(live.map { $0.id })

        for (id, panel) in panels where !ids.contains(id) {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
        guard let primary = NSScreen.screens.first else { return }
        let screenTop = primary.frame.maxY

        for w in live {
            let panel = panels[w.id] ?? {
                let p = NameplatePanel()
                panels[w.id] = p
                return p
            }()
            let width = max(90, w.frame.width - leftInset - rightInset)
            // CGWindowList is flipped (origin top-left of the primary screen);
            // AppKit is not. Convert, or every plate lands mirrored down the screen.
            let rect = NSRect(x: w.frame.minX + leftInset,
                              y: screenTop - w.frame.minY - barHeight + 3,
                              width: width, height: barHeight - 6)
            if panel.frame != rect { panel.setFrame(rect, display: false) }

            let meta = info[w.id] ?? PlateInfo(name: "Terminal", rawName: "", sub: "", accent: 0, busy: false)
            let accent = (meta.accent > 0 && meta.accent <= palette.count)
                ? palette[meta.accent - 1] : Color.secondary
            let q = QueueStore.shared.byWindow[w.id]
            panel.contentView = NSHostingView(
                rootView: PlateView(name: meta.name, sub: meta.sub, accent: accent,
                                    symbol: Self.symbol(for: meta.rawName), busy: meta.busy,
                                    queued: q))
            if !panel.isVisible { panel.orderFront(nil) }
        }
    }

    /// Claude Code and friends write a spinner glyph into the title. It becomes
    /// the plate's icon — and then has to come OUT of the text, or every plate
    /// reads "✳ ✳ LANDING" with the same mark twice.
    nonisolated static let agentGlyphs: Set<Character> = ["✳", "✻", "✽", "◐", "◑", "◒", "◓", "*", "·"]

    nonisolated static func symbol(for title: String) -> String {
        let head = title.prefix(2)
        return head.contains(where: { agentGlyphs.contains($0) }) ? "sparkles" : "terminal"
    }

    nonisolated static func strip(_ title: String) -> String {
        var t = Substring(title)
        while let f = t.first, agentGlyphs.contains(f) || f == " " { t = t.dropFirst() }
        return t.isEmpty ? title : String(t)
    }

    private func refreshInfo() {
        let js = """
        var T = Application('Terminal'); var out = [];
        for (var i = 0; i < T.windows.length; i++) {
          var w = T.windows[i];
          try {
            if (w.miniaturized()) continue;
            var t = w.tabs[0];
            out.push({ id: w.id(), name: w.name(),
                       set: (function(){ try { return t.currentSettings.name(); } catch(e){ return ''; } })(),
                       procs: (function(){ try { return t.processes(); } catch(e){ return []; } })(),
                       busy: (function(){ try { return t.busy(); } catch(e){ return false; } })() });
          } catch (e) {}
        }
        JSON.stringify(out)
        """
        Task.detached(priority: .utility) {
            let raw = Shell.jxa(js)
            guard let data = raw.output.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { return }
            var next: [CGWindowID: PlateInfo] = [:]
            for row in arr {
                guard let id = row["id"] as? Int else { continue }
                let raw = (row["name"] as? String) ?? "Terminal"
                let set = (row["set"] as? String) ?? ""
                var accent = 0
                if set.hasPrefix("t-GRID "), let n = Int(set.dropFirst(7)) { accent = n }
                // A themed window's title is already just the session name. An
                // unthemed one is still Apple's "dir - task - proc - 116x43", so
                // pull the middle out rather than showing the whole string.
                let parts = raw.components(separatedBy: " — ")
                let titled = (accent > 0 ? raw : (parts.count > 1 ? parts[1] : raw))
                // What is running in there is worth the width — but the LAST
                // process is wrong: an agent spawns helpers, so a Claude Code
                // window reported "Python" (an MCP server) in all six plates.
                // The one you mean is the first thing the shell itself launched.
                let procs = (row["procs"] as? [String]) ?? []
                let shells: Set<String> = ["login", "zsh", "-zsh", "bash", "-bash", "sh", "fish", "-fish"]
                let proc = procs
                    .map { p -> String in
                        let base = (p as NSString).lastPathComponent
                        return base.hasPrefix("-") ? String(base.dropFirst()) : base
                    }
                    .first { !shells.contains($0) } ?? ""
                next[CGWindowID(id)] = PlateInfo(name: Nameplates.strip(titled),
                                                 rawName: titled,
                                                 sub: proc, accent: accent,
                                                 busy: (row["busy"] as? Bool) ?? false)
            }
            let result = next
            await MainActor.run { self.info = result }
        }
    }
}

extension Color {
    /// #RRGGBB as printed by `tgrid --palette`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

struct GridPicker: View {
    @Binding var rows: Int
    @Binding var cols: Int
    private let maxRows = 4
    private let maxCols = 5
    @State private var hr = -1
    @State private var hc = -1

    private var hovering: Bool { hr >= 0 && hc >= 0 }

    private func lit(_ r: Int, _ c: Int) -> Bool {
        if hovering { return r <= hr && c <= hc }
        if rows > 0 && cols > 0 { return r < rows && c < cols }
        return false
    }

    private var caption: String {
        if hovering { return "\(hr + 1) × \(hc + 1)" }
        if rows > 0 && cols > 0 { return "\(rows) × \(cols)" }
        return "Auto — best fit"
    }

    var body: some View {
        VStack(spacing: 7) {
            VStack(spacing: 3) {
                ForEach(0..<maxRows, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<maxCols, id: \.self) { c in
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(lit(r, c) ? Color.accentColor : Color.primary.opacity(0.09))
                                .frame(width: 46, height: 22)
                                .onHover { inside in
                                    if inside { hr = r; hc = c }
                                    else if hr == r && hc == c { hr = -1; hc = -1 }
                                }
                                .onTapGesture {
                                    if rows == r + 1 && cols == c + 1 { rows = 0; cols = 0 }
                                    else { rows = r + 1; cols = c + 1 }
                                }
                        }
                    }
                }
            }
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(hovering || rows > 0 ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - display picker

struct DisplayPicker: View {
    let displays: [DisplayInfo]
    @Binding var selected: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(displays) { d in
                let on = d.id == selected
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(on ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.09))
                        .frame(width: 34 * d.aspect, height: 34)
                        .overlay(
                            Text("\(d.id + 1)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? Color.white : Color.secondary)
                        )
                    Text(d.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { selected = d.id }
                .help(d.name)
            }
            Spacer()
        }
    }
}

// MARK: - panel

struct Panel: View {
    @ObservedObject var m: Model
    @ObservedObject private var q = QueueStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header

            if m.toolMissing {
                warning("`tgrid` not found",
                        "Run ./install.sh from the t-GRID folder to put it on your PATH.")
            }

            section("Monitor") {
                VStack(alignment: .leading, spacing: 6) {
                    DisplayPicker(displays: m.displays, selected: $m.display)
                    Toggle("Only windows already on this monitor", isOn: $m.onlyHere)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                    Toggle("Colour each cell, strip the title bar", isOn: $m.theme)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                    Toggle("Nameplates over the title bars", isOn: $m.plates)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                    Toggle("Show the queue as a floating list", isOn: $m.board)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10))
                        .disabled(!Shell.queueInstalled)
                }
            }

            section("Layout") {
                GridPicker(rows: $m.rows, cols: $m.cols)
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Button { m.queue() } label: {
                        Label(m.queueLabel, systemImage: "hand.raised")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Whoever has waited longest goes in front of you")
                    Button { m.queue(1) } label: { Image(systemName: "arrow.turn.down.right") }
                        .help("Send the front one to the back of the line")
                }
                .disabled(m.working || m.toolMissing || !Shell.queueInstalled)

                HStack(spacing: 6) {
                    Button { m.deck() } label: {
                        Label("Deck", systemImage: "rectangle.portrait.on.rectangle.portrait")
                            .frame(maxWidth: .infinity)
                    }
                    Button { m.deck(-1) } label: { Image(systemName: "chevron.left") }
                        .help("Previous window to the middle")
                    Button { m.deck(1) } label: { Image(systemName: "chevron.right") }
                        .help("Next window to the middle")
                }
                .disabled(m.working || m.toolMissing)
                .padding(.bottom, 4)

                Button { m.sort() } label: {
                    Label("Sort open terminals", systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(m.working || m.toolMissing)

                HStack(spacing: 6) {
                    Button { m.newGrid() } label: {
                        Label("New grid of \(m.newCount)", systemImage: "plus.square.on.square")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(m.working || m.toolMissing)

                    Picker("", selection: $m.gap) {
                        Text("0").tag(0)
                        Text("6").tag(6)
                        Text("14").tag(14)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 92)
                    .help("Gap between windows, in pixels")
                }

                // where "New grid" actually starts — an app launched from the Dock
                // has "/" as its working directory, which is never what you want
                Button { m.chooseFolder() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text("in \(m.workDirName)").lineLimit(1)
                        Spacer()
                        Text("Change").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .help(m.workDir)
            }

            Divider()

            section("Sessions (\(m.sessions.count))") {
                if m.needsPermission {
                    warning("Can't read Terminal windows",
                            "Allow TGrid under Privacy & Security → Automation → Terminal.") {
                        Button("Open Settings") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                        .font(.system(size: 10))
                    }
                } else if m.sessions.isEmpty {
                    Text("No open Terminal windows")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    // ScrollView has no intrinsic height in a menu bar window — it
                    // collapses to nothing unless the height is stated outright.
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(m.sessions) { s in SessionRow(s: s) { m.focus(s) } }
                        }
                    }
                    .frame(height: CGFloat(min(m.sessions.count, 6)) * 38)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Undo") { m.undo() }
                    .buttonStyle(.link).font(.system(size: 10))
                    .disabled(m.working || m.toolMissing)
                    .help("Put the windows back where they were before the last tile")
                Button("Refresh") { m.refresh() }
                    .buttonStyle(.link).font(.system(size: 10))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.link).font(.system(size: 10))
            }
        }
        .padding(14)
        .frame(width: 292)
        .task {
            // poll only while the panel is actually on screen
            // The panel does not run its own scan — it reads whatever the last
            // one wrote. A scan shells out to osascript and takes a second or
            // two; doing that on every menu open would make the menu feel slow
            // for a number that is at most twenty seconds stale.
            q.load()
            while !Task.isCancelled {
                m.refresh()
                q.load()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private var header: some View {
        HStack {
            Label("TGrid", systemImage: "square.grid.2x2")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            if m.working {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else if !m.status.isEmpty {
                Text(m.status)
                    .font(.system(size: 9))
                    .foregroundStyle(m.failed ? Color.red : Color.secondary)
                    .lineLimit(1)
                    .help(m.status)
            }
        }
    }

    @ViewBuilder
    private func warning<C: View>(_ title: String, _ body: String,
                                  @ViewBuilder _ extra: () -> C = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange)
            Text(body)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra()
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.6)
            content()
        }
    }
}

struct SessionRow: View {
    let s: Session
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(s.busy ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 6, height: 6)
                .help(s.busy ? "running" : "idle")
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if !s.subtitle.isEmpty {
                    Text(s.subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text("\(s.display + 1)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(hover ? Color.primary.opacity(0.07) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
    }
}

// MARK: - app

@main
struct TGridApp: App {
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            Panel(m: model)
        } label: {
            Image(systemName: "square.grid.2x2")
        }
        .menuBarExtraStyle(.window)
    }
}
