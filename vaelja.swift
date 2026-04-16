import Cocoa
import Carbon

// MARK: - Color History Item

struct ColorHistoryItem {
    let hex: String
    let color: NSColor
    let date: Date
}

// MARK: - Keycode Utility

func keyCodeToString(_ code: UInt32) -> String {
    // Special keys that have no printable character
    let specialKeys: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        122: "F1",  120: "F2",  99: "F3",  118: "F4",
         96: "F5",   97: "F6",  98: "F7",  100: "F8",
        101: "F9",  109: "F10", 103: "F11", 111: "F12"
    ]
    if let special = specialKeys[code] { return special }

    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
          let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return "?"
    }
    let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self)
    let keyboardLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

    var deadKeyState: UInt32 = 0
    var chars = [UniChar](repeating: 0, count: 4)
    var charCount = 0

    let status = UCKeyTranslate(
        keyboardLayout,
        UInt16(code),
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        chars.count,
        &charCount,
        &chars
    )

    guard status == noErr, charCount > 0 else { return "?" }
    return String(chars.prefix(charCount).map { Character(UnicodeScalar($0)!) }).uppercased()
}

// MARK: - Shortcut Recorder View

class ShortcutRecorderView: NSView {
    var keyCode: UInt32 = 8 {
        didSet { label?.stringValue = shortcutString() }
    }
    var modifiers: UInt32 = UInt32(shiftKey | optionKey) {
        didSet { label?.stringValue = shortcutString() }
    }
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    private var isRecording = false
    private var label: NSTextField!
    private var monitor: Any?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        label = NSTextField(labelWithString: shortcutString())
        label.alignment = .center
        label.frame = bounds.insetBy(dx: 4, dy: 2)
        label.autoresizingMask = [.width, .height]
        addSubview(label)

        let click = NSClickGestureRecognizer(target: self, action: #selector(startRecording))
        addGestureRecognizer(click)
    }

    private func shortcutString() -> String {
        var parts = ""
        if modifiers & UInt32(controlKey) != 0  { parts += "⌃" }
        if modifiers & UInt32(optionKey)  != 0  { parts += "⌥" }
        if modifiers & UInt32(shiftKey)   != 0  { parts += "⇧" }
        if modifiers & UInt32(cmdKey)     != 0  { parts += "⌘" }
        parts += keyCodeToString(keyCode)
        return parts
    }

    @objc private func startRecording() {
        isRecording = true
        label.stringValue = "Type shortcut…"
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            let mods = event.modifierFlags
            var modFlags: UInt32 = 0
            if mods.contains(.control) { modFlags |= UInt32(controlKey) }
            if mods.contains(.option)  { modFlags |= UInt32(optionKey) }
            if mods.contains(.shift)   { modFlags |= UInt32(shiftKey) }
            if mods.contains(.command) { modFlags |= UInt32(cmdKey) }

            // Require at least one modifier
            if modFlags != 0 {
                self.keyCode = UInt32(event.keyCode)
                self.modifiers = modFlags
                self.stopRecording()
                self.onShortcutChanged?(self.keyCode, self.modifiers)
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        label.stringValue = shortcutString()
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var colorHistory: [ColorHistoryItem] = []
    private let maxHistory = 20
    private var shortcutPanel: NSPanel?

    // Hotkey config (persisted in UserDefaults)
    private var hotKeyCode: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "hotKeyCode") == 0
              ? 8 : UserDefaults.standard.integer(forKey: "hotKeyCode")) }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyCode") }
    }
    private var hotKeyModifiers: UInt32 {
        get {
            let v = UserDefaults.standard.integer(forKey: "hotKeyModifiers")
            return v == 0 ? UInt32(shiftKey | optionKey) : UInt32(v)
        }
        set { UserDefaults.standard.set(newValue, forKey: "hotKeyModifiers") }
    }

    // MARK: Shortcut String

    private func currentShortcutString() -> String {
        var parts = ""
        if hotKeyModifiers & UInt32(controlKey) != 0 { parts += "⌃" }
        if hotKeyModifiers & UInt32(optionKey)  != 0 { parts += "⌥" }
        if hotKeyModifiers & UInt32(shiftKey)   != 0 { parts += "⇧" }
        if hotKeyModifiers & UInt32(cmdKey)     != 0 { parts += "⌘" }
        parts += keyCodeToString(hotKeyCode)
        return parts
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        installHotkeyHandler()
        registerHotkey()
    }

    // MARK: Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Color Picker")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // — Options submenu —
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        let optionsMenu = NSMenu()

        let shortcutItem = NSMenuItem(title: "Set Shortcut…    \(currentShortcutString())", action: #selector(openShortcutPanel), keyEquivalent: "")
        shortcutItem.target = self
        optionsMenu.addItem(shortcutItem)

        let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = loginItemEnabled ? .on : .off
        optionsMenu.addItem(loginItem)

        optionsItem.submenu = optionsMenu
        menu.addItem(optionsItem)

        menu.addItem(.separator())

        // — History —
        let historyHeader = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyHeader.isEnabled = false
        menu.addItem(historyHeader)

        if colorHistory.isEmpty {
            let empty = NSMenuItem(title: "No colors picked yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            // Inline: last 5
            for item in colorHistory.prefix(5) {
                let menuItem = NSMenuItem(title: "", action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                menuItem.target = self
                menuItem.representedObject = item.hex
                menuItem.view = makeHistoryView(item: item)
                menu.addItem(menuItem)
            }

            // More… submenu with all 20
            if colorHistory.count > 5 {
                let moreItem = NSMenuItem(title: "More…", action: nil, keyEquivalent: "")
                let moreMenu = NSMenu()
                for item in colorHistory {
                    let menuItem = NSMenuItem(title: "", action: #selector(copyHistoryItem(_:)), keyEquivalent: "")
                    menuItem.target = self
                    menuItem.representedObject = item.hex
                    menuItem.view = makeHistoryView(item: item)
                    moreMenu.addItem(menuItem)
                }
                moreItem.submenu = moreMenu
                menu.addItem(moreItem)
            }

            menu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: History Row View

    private func makeHistoryView(item: ColorHistoryItem) -> NSView {
        let row = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))

        // Squircle swatch
        let swatchSize: CGFloat = 18
        let swatch = SwatchView(frame: NSRect(x: 16, y: 5, width: swatchSize, height: swatchSize))
        swatch.color = item.color
        row.addSubview(swatch)

        // Hex label
        let label = NSTextField(labelWithString: item.hex.uppercased())
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.frame = NSRect(x: 42, y: 6, width: 160, height: 16)
        row.addSubview(label)

        // Click target
        let click = NSClickGestureRecognizer(target: self, action: #selector(swatchClicked(_:)))
        row.addGestureRecognizer(click)
        row.identifier = NSUserInterfaceItemIdentifier(item.hex)

        return row
    }

    @objc private func swatchClicked(_ sender: NSClickGestureRecognizer) {
        if let view = sender.view, let hex = view.identifier?.rawValue {
            copyToClipboard(hex)
            statusItem.menu?.cancelTracking()
        }
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        if let hex = sender.representedObject as? String {
            copyToClipboard(hex)
        }
    }

    // MARK: Shortcut Panel

    @objc private func openShortcutPanel() {
        if shortcutPanel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 270, height: 72),
                styleMask: [.titled, .closable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Set Shortcut"
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false

            let lbl = NSTextField(labelWithString: "Shortcut:")
            lbl.frame = NSRect(x: 16, y: 24, width: 68, height: 18)

            let recorder = ShortcutRecorderView(frame: NSRect(x: 88, y: 20, width: 160, height: 26))
            recorder.keyCode = hotKeyCode
            recorder.modifiers = hotKeyModifiers
            recorder.onShortcutChanged = { [weak self] code, mods in
                guard let self = self else { return }
                self.hotKeyCode = code
                self.hotKeyModifiers = mods
                self.registerHotkey()
                self.rebuildMenu()
            }

            panel.contentView?.addSubview(lbl)
            panel.contentView?.addSubview(recorder)
            shortcutPanel = panel
        }
        shortcutPanel?.center()
        shortcutPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Hotkey

    /// Installs the Carbon event handler once for the lifetime of the app.
    private func installHotkeyHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
                DispatchQueue.main.async { delegate.pickColorFromScreen() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    /// Unregisters the current hotkey and registers the new one. Safe to call repeatedly.
    func registerHotkey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C5250), id: 1)
        RegisterEventHotKey(
            hotKeyCode,
            hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private var colorSampler: NSColorSampler?

    // MARK: Pick Color

    func pickColorFromScreen() {
        let sampler = NSColorSampler()
        colorSampler = sampler
        sampler.show { [weak self] color in
            guard let self = self else { return }
            self.colorSampler = nil
            guard let color = color else { return }

            let hex = self.hexString(from: color)
            self.copyToClipboard(hex)
            self.addToHistory(color: color, hex: hex)
            self.flashColorIcon(color: color)
            self.rebuildMenu()
        }
    }

    // MARK: Icon Flash

    private func flashColorIcon(color: NSColor) {
        guard let button = statusItem.button else { return }

        // Draw a filled circle in the picked color
        let size = NSSize(width: 16, height: 16)
        let colorImage = NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.usingColorSpace(.sRGB)?.setFill() ?? color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
        colorImage.isTemplate = false
        button.image = colorImage

        // Revert to eyedropper after 1.5s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let button = self.statusItem.button else { return }
            let eyedropper = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Color Picker")
            eyedropper?.isTemplate = true
            button.image = eyedropper
        }
    }

    // MARK: Hex Conversion

    private func hexString(from color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return "#000000FF" }
        let r = Int(c.redComponent   * 255)
        let g = Int(c.greenComponent * 255)
        let b = Int(c.blueComponent  * 255)
        let a = Int(c.alphaComponent * 255)
        if a == 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        } else {
            return String(format: "#%02X%02X%02X%02X", r, g, b, a)
        }
    }

    // MARK: Clipboard

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: History

    private func addToHistory(color: NSColor, hex: String) {
        let item = ColorHistoryItem(hex: hex, color: color, date: Date())
        colorHistory.insert(item, at: 0)
        if colorHistory.count > maxHistory {
            colorHistory = Array(colorHistory.prefix(maxHistory))
        }
    }

    @objc private func clearHistory() {
        colorHistory.removeAll()
        rebuildMenu()
    }

    // MARK: Login Item (LaunchAgent)

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.vaelja.plist")
    }

    private var loginItemEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    private func launchctl(_ args: [String]) throws {
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = args
        let pipe = Pipe()
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let msg = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "launchctl", code: Int(task.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
    }

    private var userDomain: String { "gui/\(getuid())" }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if loginItemEnabled {
                try launchctl(["bootout", userDomain, launchAgentURL.path])
                try FileManager.default.removeItem(at: launchAgentURL)
            } else {
                let rawPath = CommandLine.arguments[0]
                let execPath: String
                if rawPath.hasPrefix("/") {
                    execPath = (rawPath as NSString).resolvingSymlinksInPath
                } else {
                    let which = Process()
                    which.launchPath = "/usr/bin/which"
                    which.arguments = [rawPath]
                    let whichPipe = Pipe()
                    which.standardOutput = whichPipe
                    try which.run()
                    which.waitUntilExit()
                    let resolved = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawPath
                    execPath = (resolved as NSString).resolvingSymlinksInPath
                }
                let plist: [String: Any] = [
                    "Label": "com.vaelja",
                    "ProgramArguments": [execPath],
                    "RunAtLoad": true,
                    "KeepAlive": false
                ]
                let data = try PropertyListSerialization.data(
                    fromPropertyList: plist, format: .xml, options: 0
                )
                try FileManager.default.createDirectory(
                    at: launchAgentURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: launchAgentURL)
                try launchctl(["bootstrap", userDomain, launchAgentURL.path])
            }
        } catch {
            print("Login item error: \(error.localizedDescription)")
        }
        rebuildMenu()
    }

    // MARK: Terminate

    func applicationWillTerminate(_ notification: Notification) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
    }
}

// MARK: - Squircle Swatch View

class SwatchView: NSView {
    var color: NSColor = .clear

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.width * 0.3, yRadius: bounds.height * 0.3)
        color.setFill()
        path.fill()

        NSColor.black.withAlphaComponent(0.15).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()