import Carbon
import SwiftUI

/// System-wide triggers. Keys use Carbon hotkeys and hot corners watch the pointer. Neither needs
/// permission. Clicks, scrolls, and gestures use an event tap, which macOS only allows with
/// Accessibility access, so the app can swallow the event.
///
/// All state lives on the main actor. Carbon and the event tap call back on the main run loop, and the
/// callbacks check that with `MainActor.assumeIsolated`.
@MainActor
enum HotKeys {
    private typealias Entry = (shortcut: Shortcut, action: () -> Void)

    private static var refs: [EventHotKeyRef] = []
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false

    private static var tap: CFMachPort?
    private static var tapMask: CGEventMask = 0
    private static var tapEntries: [Entry] = []
    /// Buttons whose press was swallowed, with the shortcut to run when the button is released. Running it
    /// on release keeps a menu from opening under a held button, which closes it at once.
    private static var pendingClicks: [Int64: Entry] = [:]
    private static var watchdog: Timer?
    /// Called when macOS takes the tap away, so the app can register again.
    static var onTapLost: (() -> Void)?
    private static var lastScroll: TimeInterval = 0
    private static var pinchTotal = 0.0
    private static var pinchFired = false

    private static var cornerMonitor: Any?
    private static var cornerEntries: [Entry] = []
    private static var cornerArmed = true

    static var hasClickAccess: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to the Accessibility pane.
    static func requestClickAccess() {
        // The value of kAXTrustedCheckOptionPrompt, which Swift 6 will not read as a global.
        let prompt = "AXTrustedCheckOptionPrompt"
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    /// Replaces all registered triggers with the shortcuts on `nodes` and the `extras`, which call
    /// `onExtra` with their index. Returns the nodes with a key shortcut the system rejected, the
    /// indexes of rejected extras, and whether tap-based shortcuts are waiting for Accessibility access.
    static func register(_ nodes: [LibraryItem], extras: [Shortcut?],
                         onExtra: @escaping @MainActor (Int) -> Void)
        -> (nodes: Set<UUID>, extras: Set<Int>, needsAccess: Bool) {
        installHandler()
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        tapEntries = []
        cornerEntries = []

        // An owner is the node a shortcut belongs to, or the extra's index.
        var entries: [(shortcut: Shortcut, owner: UUID?, extra: Int?, action: () -> Void)] = nodes.flatMap { node in
            (node.shortcuts ?? []).map { shortcut in
                // Looked up when it fires, so editing an item does not need a new registration.
                (shortcut, node.id, nil, {
                    MainActor.assumeIsolated {
                        open(LibraryStore.shared.nodes.node(withID: node.id) ?? node, forceNew: shortcut.openNew)
                    }
                })
            }
        }
        for (index, shortcut) in extras.enumerated() {
            if let shortcut {
                entries.append((shortcut, nil, index, { MainActor.assumeIsolated { onExtra(index) } }))
            }
        }

        var failed = Set<UUID>()
        var failedExtras = Set<Int>()
        var index = 0
        for entry in entries {
            if entry.shortcut.isCorner {
                cornerEntries.append((entry.shortcut, entry.action))
                continue
            }
            if entry.shortcut.button != nil || entry.shortcut.gesture != nil {
                tapEntries.append((entry.shortcut, entry.action))
                continue
            }
            let id = EventHotKeyID(signature: 0x4D4C_4248, id: UInt32(index))
            index += 1
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(entry.shortcut.keyCode, entry.shortcut.modifiers, id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id.id] = entry.action
            } else if let owner = entry.owner {
                failed.insert(owner)
            } else if let extra = entry.extra {
                failedExtras.insert(extra)
            }
        }
        updateCornerMonitor()
        if tapEntries.isEmpty { removeTap() }
        return (failed, failedExtras, !tapEntries.isEmpty && !updateTap())
    }

    // MARK: Event tap

    /// The event types the current tap shortcuts need. Listening to fewer types means fewer callbacks, and
    /// scrolling alone would otherwise wake the app for every wheel tick on the system.
    private static func neededMask() -> CGEventMask {
        var mask: CGEventMask = 0
        func add(_ types: CGEventType...) { types.forEach { mask |= CGEventMask(1) << $0.rawValue } }
        for entry in tapEntries {
            if entry.shortcut.button != nil {
                add(.rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged)
            } else if let gesture = entry.shortcut.gesture {
                if gesture.hasPrefix("scroll") { add(.scrollWheel) }
                // Types 30 and 31 are the pinch and swipe gestures, which CGEventType does not name.
                if gesture.hasPrefix("pinch") { mask |= CGEventMask(1) << 30 }
                if gesture.hasPrefix("swipe") { mask |= CGEventMask(1) << 31 }
            }
        }
        return mask
    }

    private static func removeTap() {
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        pendingClicks = [:]
        watchdog?.invalidate()
        watchdog = nil
    }

    /// Runs the tap while there are tap-based shortcuts, with just the event types they need.
    /// Returns false when it cannot be created.
    private static func updateTap() -> Bool {
        let mask = neededMask()
        if tap != nil, tapMask != mask { removeTap() }
        if tap == nil {
            guard hasClickAccess,
                  let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                               options: .defaultTap, eventsOfInterest: mask,
                                               callback: { _, type, event, _ in
                                                   var result: Unmanaged<CGEvent>?
                                                   MainActor.assumeIsolated { result = HotKeys.handleTap(type, event) }
                                                   return result
                                               },
                                               userInfo: nil) else { return false }
            CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, port, 0), .commonModes)
            tap = port
            tapMask = mask
            let timer = Timer(timeInterval: 10, repeats: true) { _ in MainActor.assumeIsolated { HotKeys.checkTap() } }
            timer.tolerance = 5
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        }
        CGEvent.tapEnable(tap: tap!, enable: true)
        return true
    }

    /// macOS can switch a tap off without telling it, and a new build loses Accessibility access while the
    /// system pane still shows it on. Turn the tap back on, or drop it and ask the app to register again.
    private static func checkTap() {
        guard let port = tap else { return }
        if !hasClickAccess {
            removeTap()
            onTapLost?()
        } else if !CGEvent.tapIsEnabled(tap: port) {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    private static func handleTap(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Releases that happened while the tap was off never arrive, so forget the held buttons.
            pendingClicks = [:]
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }
        let flags = event.flags.intersection([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        func match(_ test: (Shortcut) -> Bool) -> Entry? {
            tapEntries.first { $0.shortcut.eventFlags == flags && test($0.shortcut) }
        }
        func fire(_ entry: Entry) {
            DispatchQueue.main.async { MainActor.assumeIsolated { entry.action() } }
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        switch type {
        case .rightMouseDown, .otherMouseDown:
            guard let entry = match({ $0.button == Int(button) }) else { return passThrough }
            pendingClicks[button] = entry
            return nil
        case .rightMouseUp, .otherMouseUp:
            guard let entry = pendingClicks.removeValue(forKey: button) else { return passThrough }
            fire(entry)
            return nil
        case .rightMouseDragged, .otherMouseDragged:
            return pendingClicks[button] != nil ? nil : passThrough
        case .scrollWheel:
            // Swallow every scroll that holds the modifiers, so the page behind does not move.
            guard match({ $0.gesture?.hasPrefix("scroll") == true }) != nil else { return passThrough }
            let now = ProcessInfo.processInfo.systemUptime
            let isNewScroll = now - lastScroll > 0.4
            lastScroll = now
            let name = Shortcut.scrollName(
                dx: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2),
                dy: event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1),
                inverted: NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false)
            if isNewScroll, let name, let entry = match({ $0.gesture == name }) {
                fire(entry)
            }
            return nil
        default:
            break
        }

        switch type.rawValue {
        case 30:
            guard match({ $0.gesture?.hasPrefix("pinch") == true }) != nil,
                  let ns = NSEvent(cgEvent: event) else { return passThrough }
            if ns.phase == .began {
                pinchTotal = 0
                pinchFired = false
            }
            pinchTotal += Double(ns.magnification)
            if !pinchFired, abs(pinchTotal) > 0.25 {
                pinchFired = true
                if let entry = match({ $0.gesture == (pinchTotal > 0 ? "pinchOut" : "pinchIn") }) {
                    fire(entry)
                }
            }
            return nil
        case 31:
            guard let ns = NSEvent(cgEvent: event),
                  let entry = match({ $0.gesture == Shortcut.swipeName(dx: Double(ns.deltaX), dy: Double(ns.deltaY)) })
            else { return passThrough }
            fire(entry)
            return nil
        default:
            return passThrough
        }
    }

    // MARK: Hot corners

    private static var screenFrames: [CGRect] = []
    private static var screenObserver: Any?

    /// The mouse-moved monitor runs for every pointer move on the system, so it only exists while a hot corner
    /// does, and it reads cached screen frames.
    private static func updateCornerMonitor() {
        if cornerEntries.isEmpty {
            if let cornerMonitor { NSEvent.removeMonitor(cornerMonitor) }
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            cornerMonitor = nil
            screenObserver = nil
        } else if cornerMonitor == nil {
            screenFrames = NSScreen.screens.map(\.frame)
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { screenFrames = NSScreen.screens.map(\.frame) }
            }
            cornerMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
                MainActor.assumeIsolated { checkCorner() }
            }
        }
    }

    /// Fires when the pointer reaches a screen corner, then waits until it leaves before firing again.
    private static func checkCorner() {
        let point = NSEvent.mouseLocation
        guard let frame = screenFrames.first(where: { $0.insetBy(dx: -1, dy: -1).contains(point) }) else { return }
        let left = point.x - frame.minX < frame.maxX - point.x
        let top = frame.maxY - point.y < point.y - frame.minY
        let dx = min(point.x - frame.minX, frame.maxX - point.x)
        let dy = min(point.y - frame.minY, frame.maxY - point.y)
        guard dx <= 2, dy <= 2 else {
            if dx > 40 || dy > 40 { cornerArmed = true }
            return
        }
        guard cornerArmed else { return }
        cornerArmed = false
        let name = top ? (left ? "cornerTopLeft" : "cornerTopRight") : (left ? "cornerBottomLeft" : "cornerBottomRight")
        let held = carbonModifiers(NSEvent.modifierFlags)
        for entry in cornerEntries where entry.shortcut.gesture == name && entry.shortcut.modifiers == held {
            entry.action()
        }
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeys.actions[id.id]?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
