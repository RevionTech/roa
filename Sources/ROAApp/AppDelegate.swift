import AppKit
import Sparkle
import Darwin
import ROACore
import ROAMac

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let store = FileStore(owner: getuid())
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "net.reviontech.roa.status"
        if let button = statusItem.button {
            if let url = Bundle.main.url(forResource: "symbol", withExtension: "pdf"),
               let image = NSImage(contentsOf: url) {
                image.size = NSSize(width: 24, height: 15)
                image.isTemplate = true
                button.image = image
            } else { button.title = "ROA" }
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        _ = updaterController
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let status = store.status()
        let fresh = status?.isFresh() == true && status?.version == ROAConstants.version
        let active = fresh && status?.phase == .active && status?.sleepDisabled == true
        button.alphaValue = active ? 1 : 0.3
        // Keep the selected symbol; add an explicit indicator for faults / guard trips.
        button.title = !fresh || status?.phase == .blocked || status?.phase == .error ? "!" : ""
        let message = fresh ? (status?.reason ?? "Unknown status") : "ROA service is unavailable"
        button.toolTip = "ROA: \(message)\nClick to turn ROA on or off. Right-click for options."
        button.setAccessibilityLabel("ROA \(active ? "active" : "inactive"): \(message)")
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            change(enabled: !(store.request()?.enabled ?? false))
        }
    }

    private func change(enabled: Bool) {
        do {
            _ = try store.setEnabled(enabled)
            // Display is based on confirmation; never paint a successful ON prematurely.
            refresh()
        } catch {
            let alert = NSAlert()
            alert.messageText = "ROA could not change sleep prevention"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let status = store.status()
        let summaryText = status.flatMap { $0.isFresh() && $0.version == ROAConstants.version ? $0.reason : nil } ?? "ROA service is unavailable"
        let summary = NSMenuItem(title: summaryText, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        let safetyStopped = status?.isFresh() == true && status?.version == ROAConstants.version && status?.phase == .blocked
        let turningOff = store.request()?.enabled == true && !safetyStopped
        add(turningOff ? "Turn Off" : "Turn On",
            action: turningOff ? #selector(turnOff) : #selector(turnOn), to: menu)
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updates)
        let automatic = NSMenuItem(title: "Automatically Check for Updates", action: #selector(toggleUpdateChecks), keyEquivalent: "")
        automatic.target = self
        for (symbol, checked) in [("square", false), ("checkmark.square", true)] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: checked ? "Enabled" : "Disabled")
            image?.size = NSSize(width: 14, height: 14)
            image?.isTemplate = true
            if checked { automatic.onStateImage = image } else { automatic.offStateImage = image }
        }
        automatic.state = updaterController.updater.automaticallyChecksForUpdates ? .on : .off
        menu.addItem(automatic)
        menu.addItem(.separator())
        add("About ROA", action: #selector(about), to: menu)
        add("Quit ROA", action: #selector(quit), to: menu)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func turnOn() { change(enabled: true) }
    @objc private func turnOff() { change(enabled: false) }
    @objc private func quit() {
        // OFF is persisted first. Keep the UI alive until the service confirms release.
        do {
            let request = try store.setEnabled(false)
            waitForOff(request: request, deadline: ProcessInfo.processInfo.systemUptime + 12) { NSApp.terminate(nil) }
        } catch { change(enabled: false) }
    }

    private func waitForOff(request: ModeRequest, deadline: TimeInterval, completion: @escaping () -> Void) {
        if let status = store.status(), status.isFresh(), status.requestID == request.id,
           status.version == ROAConstants.version, status.phase == .off, status.sleepDisabled == false {
            completion()
        } else if ProcessInfo.processInfo.systemUptime >= deadline {
            let alert = NSAlert()
            alert.messageText = "Sleep restoration has not been confirmed"
            alert.informativeText = "ROA will stay open. Check 'roa status'. Emergency recovery: sudo /usr/bin/pmset -a disablesleep 0"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.waitForOff(request: request, deadline: deadline, completion: completion)
            }
        }
    }

    @objc private func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(nil)
    }

    @objc private func toggleUpdateChecks() {
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates.toggle()
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        do {
            let request = try store.setEnabled(false)
            waitForOff(request: request, deadline: ProcessInfo.processInfo.systemUptime + 12,
                       completion: installHandler)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Update paused: ROA could not turn off"
            alert.informativeText = error.localizedDescription
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
        return true
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "ROA \(ROAConstants.version)"
        alert.informativeText = "Run. On. Anywhere.\nBy Revion Tech OÜ · MIT License\nBattery guard: 20% · Thermal guard: serious\nAfter a safety stop, choose Turn On to try again."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate() }
}
