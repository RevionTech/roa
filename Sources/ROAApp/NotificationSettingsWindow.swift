import AppKit
import UserNotifications
import ROAMac

final class NotificationSettingsWindow: NSObject {
    private let window: NSWindow
    private let local = NSButton(checkboxWithTitle: "macOS Notifications", target: nil, action: nil)
    private let remote = NSButton(checkboxWithTitle: "Telegram Notifications", target: nil, action: nil)
    private let token = NSSecureTextField()
    private let chat = NSTextField()
    private let result = NSTextField(wrappingLabelWithString: "")
    private let save = NSButton(title: "Save", target: nil, action: nil)
    private let test = NSButton(title: "Test Telegram", target: nil, action: nil)
    private let notifier = TelegramNotifier()
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 490, height: 430),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "ROA Notification Settings"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 490, height: 430)
        let explanation = NSTextField(wrappingLabelWithString:
            "Both channels are optional and off by default. Notifications report session expiry, safety stops and service problems. Ordinary ON/OFF changes are silent.")
        let instructions = NSTextField(wrappingLabelWithString:
            "Create a bot with @BotFather in Telegram, open your bot chat and press Start. Enter the bot token and numeric chat ID below. Group chat IDs can be negative. Credentials stay in this Mac’s Keychain.")
        let help = NSButton(title: "Telegram Setup Help", target: self, action: #selector(openHelp))
        token.placeholderString = "Bot token"
        chat.placeholderString = "Numeric chat ID"
        token.identifier = NSUserInterfaceItemIdentifier("telegram-token")
        chat.identifier = NSUserInterfaceItemIdentifier("telegram-chat-id")
        token.setAccessibilityLabel("Telegram bot token")
        chat.setAccessibilityLabel("Telegram numeric chat ID")
        save.target = self; save.action = #selector(saveSettings)
        test.target = self; test.action = #selector(testTelegram)
        let forget = NSButton(title: "Forget Telegram Credentials", target: self, action: #selector(forgetTelegram))
        let buttons = NSStackView(views: [save, test, forget])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [explanation, local, remote, instructions, help, token, chat, buttons, result])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20),
            token.widthAnchor.constraint(equalTo: stack.widthAnchor),
            chat.widthAnchor.constraint(equalTo: stack.widthAnchor),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            instructions.widthAnchor.constraint(equalTo: stack.widthAnchor),
            result.widthAnchor.constraint(equalTo: stack.widthAnchor),
            result.bottomAnchor.constraint(lessThanOrEqualTo: window.contentView!.bottomAnchor, constant: -20)
        ])
        window.center()
    }

    func show() {
        local.state = UserDefaults.standard.bool(forKey: NotificationCoordinator.localKey) ? .on : .off
        remote.state = UserDefaults.standard.bool(forKey: NotificationCoordinator.telegramKey) ? .on : .off
        let credential = TelegramCredentialStore.load()
        token.stringValue = credential?.token ?? ""
        chat.stringValue = credential?.chatID ?? ""
        result.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var credential: TelegramCredential {
        TelegramCredential(token: token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                           chatID: chat.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @objc private func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/RevionTech/roa/blob/main/docs/NOTIFICATIONS.md")!)
    }

    @objc private func saveSettings() {
        do {
            if remote.state == .on || !token.stringValue.isEmpty || !chat.stringValue.isEmpty {
                try TelegramCredentialStore.save(credential)
            }
        } catch {
            result.stringValue = (error as? TelegramError)?.errorDescription ?? "Settings could not be saved."
            return
        }
        UserDefaults.standard.set(remote.state == .on, forKey: NotificationCoordinator.telegramKey)
        changed()
        guard local.state == .on else {
            UserDefaults.standard.set(false, forKey: NotificationCoordinator.localKey)
            result.stringValue = "Notification settings saved."
            return
        }
        save.isEnabled = false
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                UserDefaults.standard.set(granted, forKey: NotificationCoordinator.localKey)
                self.local.state = granted ? .on : .off
                self.save.isEnabled = true
                self.result.stringValue = granted ? "Notification settings saved." :
                    "macOS notifications are blocked. Enable ROA in System Settings > Notifications, then save again."
            }
        }
    }

    @objc private func testTelegram() {
        guard credential.isValid else {
            result.stringValue = TelegramError.invalidConfiguration.errorDescription ?? "Invalid Telegram settings."
            return
        }
        test.isEnabled = false
        result.stringValue = "Sending a test message to the entered Telegram chat…"
        notifier.send("ROA test notification. Telegram notifications are ready.", credential: credential) { [weak self] outcome in
            DispatchQueue.main.async {
                guard let self else { return }
                self.test.isEnabled = true
                switch outcome {
                case .success: self.result.stringValue = "Telegram accepted the test message. Click Save to keep these settings."
                case .failure(let error): self.result.stringValue = error.errorDescription ?? "Telegram delivery failed."
                }
            }
        }
    }

    @objc private func forgetTelegram() {
        do {
            try TelegramCredentialStore.forget()
            UserDefaults.standard.set(false, forKey: NotificationCoordinator.telegramKey)
            remote.state = .off
            token.stringValue = ""
            chat.stringValue = ""
            changed()
            result.stringValue = "Telegram credentials removed. Telegram notifications are off."
        } catch {
            result.stringValue = TelegramError.keychain.errorDescription ?? "Keychain access failed."
        }
    }
}
