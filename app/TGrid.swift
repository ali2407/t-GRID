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
        workDir  = d.object(forKey: "workDir") as? String ?? NSHomeDirectory()
        if !FileManager.default.fileExists(atPath: workDir) { workDir = NSHomeDirectory() }
    }

    var isAuto: Bool { rows == 0 || cols == 0 }
    var newCount: Int { isAuto ? 4 : rows * cols }
    var workDirName: String {
        workDir == NSHomeDirectory() ? "Home" : (workDir as NSString).lastPathComponent
    }
    var toolMissing: Bool { !Shell.tgridInstalled }

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
                }
            }

            section("Layout") {
                GridPicker(rows: $m.rows, cols: $m.cols)
            }

            VStack(spacing: 6) {
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
            while !Task.isCancelled {
                m.refresh()
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
