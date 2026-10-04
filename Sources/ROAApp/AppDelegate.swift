import AppKit
import Sparkle
import Darwin
import ROACore
import ROAMac

final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var statusMonitor: DirectoryChangeMonitor?
    private var pendingRequest: ModeRequest?
    private let store = FileStore(owner: getuid())
    private let notifications = NotificationCoordinator()
    private let diagnostics = DiagnosticsWindow()
    private var chargingOnly: Bool {
        get { UserDefaults.standard.bool(forKey: "chargingOnly") }
        set { UserDefaults.standard.set(newValue, forKey: "chargingOnly") }
    }
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
        statusMonitor = DirectoryChangeMonitor(path: ROAConstants.runtimeRoot, owner: 0,
                                               queue: .main) { [weak self] in
            self?.refresh()
        }
        // Countdown, freshness and monitor-recovery fallback remain 1 Hz.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        guard let button = statusItem.button else { return }
        let status = store.status()
        notifications.observe(status: status, request: store.request())
        diagnostics.update(status: status)
        let fresh = status?.isFresh() == true && status?.version == ROAConstants.version
        if let pendingRequest, status?.requestID == pendingRequest.id || !fresh {
            self.pendingRequest = nil
        }
        let active = fresh && status?.phase == .active && status?.sleepDisabled == true
        button.alphaValue = active ? 1 : 0.3
        // Keep the selected symbol; add an explicit indicator for faults / guard trips.
        button.title = pendingRequest != nil ? "…" : (!fresh || status?.phase == .blocked || status?.phase == .error ? "!" : "")
        if active, pendingRequest == nil, let remaining = status?.remainingSeconds {
            button.title = " " + SessionPresentation.countdown(remaining)
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.imagePosition = .imageLeading
        }
        let message = pendingRequest.map { $0.enabled ? "Turning ROA on…" : "Turning ROA off…" }
            ?? (fresh ? (status?.reason ?? "Unknown status") : "ROA service is unavailable")
        button.toolTip = "ROA: \(message)\nClick to turn ROA on or off. Right-click for options."
        button.setAccessibilityLabel("ROA \(active ? "active" : "inactive"): \(message)")
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            change(enabled: !SessionPresentation.shouldTurnOff(status: store.status(), request: store.request()))
        }
    }

    private func change(enabled: Bool, duration: TimeInterval? = nil) {
        if enabled, SessionPresentation.confirmed(store.status()) == nil {
            showError("ROA could not turn on", detail: "A current, compatible ROA service must confirm its status first. Check Status & Diagnostics.")
            return
        }
        do {
            pendingRequest = try store.setEnabled(enabled, duration: duration, chargingOnly: chargingOnly)
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
        menu.autoenablesItems = false
        let status = store.status()
        let summaryText = status.flatMap { $0.isFresh() && $0.version == ROAConstants.version ? $0.reason : nil } ?? "ROA service is unavailable"
        let summary = NSMenuItem(title: summaryText, action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        let turningOff = SessionPresentation.shouldTurnOff(status: status, request: store.request())
        add(turningOff ? "Turn Off" : "Turn On",
            action: turningOff ? #selector(turnOff) : #selector(turnOn), to: menu)
        menu.items.last?.isEnabled = turningOff || SessionPresentation.confirmed(status) != nil
        let timed = NSMenuItem(title: "Turn On for…", action: nil, keyEquivalent: "")
        let durations = NSMenu()
        durations.autoenablesItems = false
        for (title, seconds) in [("15 Minutes", 900), ("30 Minutes", 1800), ("1 Hour", 3600), ("2 Hours", 7200)] {
            let item = NSMenuItem(title: title, action: #selector(turnOnTimed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = seconds
            durations.addItem(item)
        }
        add("Custom Duration…", action: #selector(customDuration), to: durations)
        timed.submenu = durations
        timed.isEnabled = !turningOff && SessionPresentation.confirmed(status) != nil
        menu.addItem(timed)
        let charging = checkbox("Only While Connected to Power", action: #selector(toggleChargingOnly), enabled: chargingOnly)
        charging.isEnabled = !turningOff
        charging.toolTip = "Applies to the next session. Disconnecting power stops that session until you turn ROA on again."
        menu.addItem(charging)
        let login = checkbox("Start at Login", action: #selector(toggleLogin), enabled: LoginItemManager.isEnabled)
        login.toolTip = "Starts the menu app at your next login. ROA always starts off after a restart."
        menu.addItem(login)
        add("Status & Diagnostics…", action: #selector(showDiagnostics), to: menu)
        add("Notifications…", action: #selector(showNotifications), to: menu)
        menu.addItem(.separator())
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        updates.isEnabled = updaterController.updater.canCheckForUpdates
        menu.addItem(updates)
        let automatic = checkbox("Automatically Check for Updates", action: #selector(toggleUpdateChecks),
                                 enabled: updaterController.updater.automaticallyChecksForUpdates)
        menu.addItem(automatic)
        menu.addItem(.separator())
        add("About ROA", action: #selector(about), to: menu)
        add("Quit ROA", action: #selector(quit), to: menu)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func checkbox(_ title: String, action: Selector, enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        for (symbol, checked) in [("square", false), ("checkmark.square", true)] {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: checked ? "Enabled" : "Disabled")
            image?.size = NSSize(width: 14, height: 14)
            image?.isTemplate = true
            if checked { item.onStateImage = image } else { item.offStateImage = image }
        }
        item.state = enabled ? .on : .off
        return item
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func turnOn() { change(enabled: true) }
    @objc private func turnOff() { change(enabled: false) }
    @objc private func turnOnTimed(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Int else { return }
        change(enabled: true, duration: TimeInterval(seconds))
    }

    @objc private func customDuration() {
        let alert = NSAlert()
        alert.messageText = "Turn ROA On for a Custom Duration"
        alert.informativeText = "Enter a duration between 1 minute and 24 hours. Normal sleep resumes when the timer ends."
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Cancel")
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 32))
        let number = NSTextField(string: "30")
        number.setAccessibilityLabel("Duration")
        number.frame = NSRect(x: 0, y: 4, width: 120, height: 24)
        let units = NSPopUpButton(frame: NSRect(x: 132, y: 0, width: 148, height: 32))
        units.setAccessibilityLabel("Duration unit")
        units.addItems(withTitles: ["Minutes", "Hours"])
        view.addSubview(number)
        view.addSubview(units)
        alert.accessoryView = view
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = number
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let input = number.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(input) else {
            showError("Invalid duration", detail: "Enter a number in minutes or hours.")
            return
        }
        let duration = value * (units.indexOfSelectedItem == 0 ? 60 : 3600)
        guard ModeRequest.isValidDuration(duration) else {
            showError("Invalid duration", detail: "Choose between 1 minute and 24 hours.")
            return
        }
        change(enabled: true, duration: duration)
    }

    @objc private func toggleChargingOnly() {
        guard !SessionPresentation.shouldTurnOff(status: store.status(), request: store.request()) else { return }
        chargingOnly.toggle()
    }

    @objc private func toggleLogin() {
        guard Bundle.main.bundleURL.path == "/Applications/ROA.app" else {
            showError("Start at Login is unavailable", detail: "This setting can only be changed from the installed ROA app in /Applications.")
            return
        }
        do { try LoginItemManager.setEnabled(!LoginItemManager.isEnabled) }
        catch { showError("ROA could not change Start at Login", detail: error.localizedDescription) }
    }

    @objc private func showDiagnostics() { diagnostics.show(status: store.status()) }
    @objc private func showNotifications() { notifications.showSettings() }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
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
