// ClaudePing.swift
// A macOS floating HUD that appears near your mouse when Claude Code finishes a task.
// Click it to jump straight to the terminal window.

import Cocoa

// MARK: - Data Model

struct PingMessage {
    let project: String
    let event: String      // "stop" or "input_needed"
    let terminalApp: String // e.g. "Terminal", "iTerm2", "kitty", "Ghostty", "Warp"
    let terminalPID: Int?
    let timestamp: Date
    
    var displayTitle: String {
        if event == "input_needed" {
            return "Needs input"
        }
        return "Done"
    }
    
    var displaySubtitle: String {
        return project.isEmpty ? "Claude Code" : project
    }
}

// MARK: - Floating HUD Window

class PingWindow: NSWindow {
    var message: PingMessage
    var dismissTimer: Timer?
    var fadeTimer: Timer?
    
    init(message: PingMessage, at point: NSPoint) {
        self.message = message
        
        let width: CGFloat = 260
        let height: CGFloat = 72
        let frame = NSRect(x: point.x + 12, y: point.y - height - 12, width: width, height: height)
        
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
    
    func clampToScreen() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
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
        self.alphaValue = 0
        self.orderFrontRegardless()
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
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

class PingView: NSView {
    let message: PingMessage
    weak var parentWindow: PingWindow?
    var isHovered = false
    var trackingArea: NSTrackingArea?
    
    init(message: PingMessage, window: PingWindow) {
        self.message = message
        self.parentWindow = window
        super.init(frame: .zero)
        
        // Set up cursor tracking
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(area)
        self.trackingArea = area
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        
        // Background
        let bgColor: NSColor
        if isHovered {
            bgColor = NSColor(calibratedWhite: 0.15, alpha: 0.95)
        } else {
            bgColor = NSColor(calibratedWhite: 0.12, alpha: 0.92)
        }
        bgColor.setFill()
        path.fill()
        
        // Subtle border
        let borderColor = NSColor(calibratedWhite: 1.0, alpha: isHovered ? 0.15 : 0.08)
        borderColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        
        // Accent bar on the left
        let accentColor: NSColor
        if message.event == "input_needed" {
            accentColor = NSColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 1.0) // amber
        } else {
            accentColor = NSColor(red: 0.42, green: 0.85, blue: 0.66, alpha: 1.0) // green
        }
        
        let barRect = NSRect(x: 12, y: 16, width: 3, height: rect.height - 28)
        let barPath = NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5)
        accentColor.setFill()
        barPath.fill()
        
        // Icon (checkmark or prompt indicator)
        let iconStr: String
        if message.event == "input_needed" {
            iconStr = "❯"
        } else {
            iconStr = "✓"
        }
        let iconAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: accentColor
        ]
        let iconSize = iconStr.size(withAttributes: iconAttrs)
        iconStr.draw(at: NSPoint(x: 24, y: rect.height / 2 - iconSize.height / 2 + 4), withAttributes: iconAttrs)
        
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        message.displayTitle.draw(at: NSPoint(x: 48, y: rect.height / 2 + 4), withAttributes: titleAttrs)
        
        // Subtitle (project name)
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.55)
        ]
        message.displaySubtitle.draw(at: NSPoint(x: 48, y: rect.height / 2 - 14), withAttributes: subAttrs)
        
        // "Click to open" hint on the right
        if isHovered {
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.4)
            ]
            let hint = "click to open →"
            let hintSize = hint.size(withAttributes: hintAttrs)
            hint.draw(at: NSPoint(x: rect.width - hintSize.width - 12, y: rect.height / 2 - hintSize.height / 2 + 2), withAttributes: hintAttrs)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
        needsDisplay = true
        // Pause auto-dismiss while hovering
        parentWindow?.dismissTimer?.invalidate()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
        needsDisplay = true
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
            let mouseLocation = NSEvent.mouseLocation
            
            // Stack multiple pings vertically
            let offset = CGFloat(self.windows.count) * 80
            let point = NSPoint(x: mouseLocation.x, y: mouseLocation.y - offset)
            
            let window = PingWindow(message: message, at: point)
            self.windows.append(window)
            window.showAnimated()
            
            // Play a subtle sound
            if message.event == "input_needed" {
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
        var event = "stop"
        var terminalApp = ""
        var terminalPID: Int? = nil
        
        for line in str.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let val = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "project": project = val
            case "event": event = val
            case "terminal": terminalApp = val
            case "pid": terminalPID = Int(val)
            default: break
            }
        }
        
        let message = PingMessage(
            project: project,
            event: event,
            terminalApp: terminalApp,
            terminalPID: terminalPID,
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
            event: "stop",
            terminalApp: "Terminal",
            terminalPID: nil,
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
