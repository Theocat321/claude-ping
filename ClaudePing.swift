// ClaudePing.swift
// A macOS floating HUD that appears in the bottom-right corner of the screen when Claude Code finishes a task.
// Click it to jump straight to the terminal window.

import Cocoa

// MARK: - Data Model

struct PingMessage {
    let project: String
    let branch: String     // git branch; shown as the subtitle
    let event: String      // "stop", "input_needed", or "permission"
    let terminalApp: String // e.g. "Terminal", "iTerm2", "kitty", "Ghostty", "Warp"
    let terminalPID: Int?
    let paradev: ParadevTarget? // set when the session runs inside Paradev
    let timestamp: Date
    
    var displayTitle: String {
        switch event {
        case "input_needed": return "Needs input"
        case "permission": return "Needs permission"
        default: return "Done"
        }
    }
    
    var needsAttention: Bool {
        return event == "input_needed" || event == "permission"
    }
    
    var displaySubtitle: String {
        return branch.isEmpty ? "Claude Code" : branch
    }
}

// MARK: - Paradev focus

/// A Claude session running in a Paradev terminal pane.
struct ParadevTarget {
    let workspaceID: String
    let terminalID: String
    let cliPath: String
    
    init?(workspaceID: String, terminalID: String, cliPath: String) {
        guard !workspaceID.isEmpty else { return nil }
        self.workspaceID = workspaceID
        self.terminalID = terminalID
        self.cliPath = cliPath
    }
    
    var deepLink: URL? { URL(string: "superset://v2-workspace/\(workspaceID)") }
}

enum ParadevFocuser {
    /// Brings Paradev forward on the session's workspace, then focuses the pane running its terminal.
    static func focus(_ target: ParadevTarget) {
        if let url = target.deepLink { NSWorkspace.shared.open(url) }
        guard !target.terminalID.isEmpty, !target.cliPath.isEmpty else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let paneID = findPaneID(target) else {
                NSLog("ClaudePing: no Paradev pane found for terminal %@", target.terminalID)
                return
            }
            _ = runCLI(target.cliPath, ["panes", "focus", "--workspace", target.workspaceID, "--pane", paneID, "--json"])
        }
    }
    
    private static func findPaneID(_ target: ParadevTarget) -> String? {
        guard let output = runCLI(target.cliPath, ["panes", "list", "--workspace", target.workspaceID, "--json"]),
              let layout = (try? JSONSerialization.jsonObject(with: output)) as? [String: Any]
        else { return nil }
        
        let mainTabs = layout["tabs"] as? [[String: Any]] ?? []
        let sidebarTabs = (layout["sidebar"] as? [String: Any])?["tabs"] as? [[String: Any]] ?? []
        let panes = (mainTabs + sidebarTabs).flatMap { $0["panes"] as? [[String: Any]] ?? [] }
        return panes.first { ($0["terminalId"] as? String) == target.terminalID }?["id"] as? String
    }
    
    /// Runs the Paradev CLI and returns stdout, or nil if it fails.
    private static func runCLI(_ path: String, _ args: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            NSLog("ClaudePing: could not run Paradev CLI %@: %@", path, error.localizedDescription)
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            NSLog("ClaudePing: Paradev CLI %@ exited %d", args.joined(separator: " "), process.terminationStatus)
            return nil
        }
        return data
    }
}

// MARK: - Floating HUD Window

class PingWindow: NSWindow {
    var message: PingMessage
    var dismissTimer: Timer?
    var fadeTimer: Timer?
    
    static let width = PingStyle.width
    static let height = PingStyle.height
    static let slideDistance: CGFloat = 8
    static let screenMargin: CGFloat = 12

    init(message: PingMessage) {
        self.message = message
        
        let frame = PingWindow.bottomRightFrame()
        
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .transient]
        self.ignoresMouseEvents = false
        
        setupContent()
        clampToScreen()
    }
    
    /// Screen the user is looking at: the one under the mouse, else the main screen.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Bottom-right corner of the active screen, above the Dock. Every ping uses the same spot, newest on top.
    static func bottomRightFrame() -> NSRect {
        let visible = activeScreen()?.visibleFrame ?? .zero
        let x = visible.maxX - width - screenMargin
        let y = visible.minY + screenMargin
        return NSRect(x: x, y: y, width: width, height: height)
    }
    
    func clampToScreen() {
        guard let screen = PingWindow.activeScreen() else { return }
        var f = self.frame
        let visible = screen.visibleFrame
        
        if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width - 8 }
        if f.minX < visible.minX { f.origin.x = visible.minX + 8 }
        if f.minY < visible.minY { f.origin.y = visible.minY + 8 }
        if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height - 8 }
        
        self.setFrame(f, display: true)
    }
    
    func setupContent() {
        let container = PingView(message: message, window: self)
        container.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        self.contentView = container
    }
    
    func showAnimated() {
        let target = self.frame
        self.setFrame(target.offsetBy(dx: PingWindow.slideDistance, dy: 0), display: false)
        self.alphaValue = 0
        self.orderFrontRegardless()
        self.invalidateShadow()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
            self.animator().setFrame(target, display: true)
        })
        
        // Auto-dismiss after 8 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.dismissAnimated()
        }
    }
    
    func dismissAnimated() {
        dismissTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            if let self = self {
                PingManager.shared.remove(window: self)
            }
        })
    }
    
    func activateTerminal() {
        dismissTimer?.invalidate()
        
        if let target = message.paradev {
            ParadevFocuser.focus(target)
            dismissAnimated()
            return
        }
        
        // Try to activate the terminal app
        let appName = message.terminalApp.isEmpty ? "Terminal" : message.terminalApp
        
        if let pid = message.terminalPID {
            // Try by PID first
            let app = NSRunningApplication(processIdentifier: pid_t(pid))
            app?.activate(options: [.activateIgnoringOtherApps])
        } else {
            // Fall back to activating by app name
            let script = """
            tell application "\(appName)"
                activate
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
        
        dismissAnimated()
    }
}

// MARK: - Custom View

/// Layout metrics on a 4pt grid, modelled on macOS notification banners.
enum PingStyle {
    static let width: CGFloat = 240
    static let height: CGFloat = 52
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 12
    static let iconSize: CGFloat = 16
    static let iconTextGap: CGFloat = 8
    static let lineSpacing: CGFloat = 2
    static let titleFontSize: CGFloat = 13
    static let subtitleFontSize: CGFloat = 11
    static let borderWidth: CGFloat = 0.5
    static let hoverOverlayAlpha: CGFloat = 0.06
}

class PingView: NSVisualEffectView {
    let message: PingMessage
    weak var parentWindow: PingWindow?
    private let hoverOverlay = NSView()
    
    init(message: PingMessage, window: PingWindow) {
        self.message = message
        self.parentWindow = window
        super.init(frame: .zero)
        
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = PingStyle.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = PingStyle.borderWidth
        
        setupHoverOverlay()
        setupContent()
        updateColors()
        
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupHoverOverlay() {
        hoverOverlay.wantsLayer = true
        hoverOverlay.isHidden = true
        hoverOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hoverOverlay)
        NSLayoutConstraint.activate([
            hoverOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            hoverOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            hoverOverlay.topAnchor.constraint(equalTo: topAnchor),
            hoverOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    private func setupContent() {
        let icon = NSImageView()
        let symbolName = message.needsAttention ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        let config = NSImage.SymbolConfiguration(pointSize: PingStyle.iconSize, weight: .regular)
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: message.displayTitle)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = message.needsAttention ? .systemOrange : .systemGreen
        
        let title = makeLabel(message.displayTitle, size: PingStyle.titleFontSize, weight: .semibold, color: .labelColor)
        let subtitle = makeLabel(message.displaySubtitle, size: PingStyle.subtitleFontSize, weight: .regular, color: .secondaryLabelColor)
        
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = PingStyle.lineSpacing
        
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PingStyle.iconTextGap
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: PingStyle.iconSize),
            icon.heightAnchor.constraint(equalToConstant: PingStyle.iconSize),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PingStyle.horizontalPadding),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -PingStyle.horizontalPadding),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    
    private func makeLabel(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
    
    /// CGColors don't follow appearance changes, so resolve them per appearance.
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            hoverOverlay.layer?.backgroundColor = NSColor.labelColor
                .withAlphaComponent(PingStyle.hoverOverlayAlpha).cgColor
        }
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    
    override func mouseEntered(with event: NSEvent) {
        hoverOverlay.isHidden = false
        NSCursor.pointingHand.push()
        // Pause auto-dismiss while hovering
        parentWindow?.dismissTimer?.invalidate()
    }
    
    override func mouseExited(with event: NSEvent) {
        hoverOverlay.isHidden = true
        NSCursor.pop()
        // Restart auto-dismiss
        parentWindow?.dismissTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            self?.parentWindow?.dismissAnimated()
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        parentWindow?.activateTerminal()
    }
}

// MARK: - Ping Manager

class PingManager {
    static let shared = PingManager()
    private var windows: [PingWindow] = []
    
    func showPing(_ message: PingMessage) {
        DispatchQueue.main.async {
            // Pings share the bottom-right spot; the newest is ordered in front
            let window = PingWindow(message: message)
            self.windows.append(window)
            window.showAnimated()
            
            // Play a subtle sound
            if message.needsAttention {
                NSSound(named: "Basso")?.play()
            } else {
                NSSound(named: "Glass")?.play()
            }
        }
    }
    
    func remove(window: PingWindow) {
        windows.removeAll { $0 === window }
    }
}

// MARK: - Socket Server (listens for hooks)

class PingServer {
    let socketPath: String
    var serverSocket: Int32 = -1
    var running = true
    
    init() {
        let tmpDir = NSTemporaryDirectory()
        socketPath = tmpDir + "claude-ping.sock"
    }
    
    func start() {
        // Clean up old socket
        unlink(socketPath)
        
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("Error: Could not create socket")
            return
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: min(buf.count, 104))
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            print("Error: Could not bind socket at \(socketPath)")
            return
        }
        
        listen(serverSocket, 5)
        print("ClaudePing listening on \(socketPath)")
        
        // Accept connections in background
        DispatchQueue.global(qos: .utility).async {
            while self.running {
                let clientSocket = accept(self.serverSocket, nil, nil)
                guard clientSocket >= 0 else { continue }
                
                self.handleClient(clientSocket)
            }
        }
    }
    
    func handleClient(_ sock: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = read(sock, &buffer, buffer.count)
        close(sock)
        
        guard n > 0 else { return }
        
        let data = Data(buffer[..<n])
        guard let str = String(data: data, encoding: .utf8) else { return }
        
        // Parse simple key=value format, one per line
        var project = ""
        var branch = ""
        var event = "stop"
        var terminalApp = ""
        var terminalPID: Int? = nil
        var paradevWorkspace = ""
        var paradevTerminal = ""
        var paradevCLI = ""
        
        for line in str.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "project": project = val
            case "branch": branch = val
            case "event": event = val
            case "terminal": terminalApp = val
            case "pid": terminalPID = Int(val)
            case "paradev_workspace": paradevWorkspace = val
            case "paradev_terminal": paradevTerminal = val
            case "paradev_cli": paradevCLI = val
            default: break
            }
        }
        
        let message = PingMessage(
            project: project,
            branch: branch,
            event: event,
            terminalApp: terminalApp,
            terminalPID: terminalPID,
            paradev: ParadevTarget(workspaceID: paradevWorkspace, terminalID: paradevTerminal, cliPath: paradevCLI),
            timestamp: Date()
        )
        
        PingManager.shared.showPing(message)
    }
    
    func stop() {
        running = false
        close(serverSocket)
        unlink(socketPath)
    }
}

// MARK: - Menu Bar Item

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var server: PingServer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up as a menu bar app (no dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.title = "⚡"
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "ClaudePing Running", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let testItem = NSMenuItem(title: "Send Test Ping", action: #selector(sendTestPing), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit ClaudePing", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        
        // Start socket server
        server = PingServer()
        server?.start()
    }
    
    @objc func sendTestPing() {
        let msg = PingMessage(
            project: "my-cool-project",
            branch: "main",
            event: "stop",
            terminalApp: "Terminal",
            terminalPID: nil,
            paradev: nil,
            timestamp: Date()
        )
        PingManager.shared.showPing(msg)
    }
    
    @objc func quitApp() {
        server?.stop()
        NSApp.terminate(nil)
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
