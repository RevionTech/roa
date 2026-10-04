import AppKit
import UserNotifications
import ROACore
import ROAMac

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let localKey = "net.reviontech.roa.notifications.local"
    static let telegramKey = "net.reviontech.roa.notifications.telegram"
    private var policy = NotificationPolicy()
    private let telegram = TelegramNotifier()
    private var settings: NotificationSettingsWindow?
    private var sending = false
    private var lastCredential: TelegramCredential?
    private var checkedCredentialAt: Date?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func observe(status: ServiceStatus?, request: ModeRequest?) {
        guard let message = policy.observe(status: status, request: request) else { return }
        if UserDefaults.standard.bool(forKey: Self.localKey) {
            Self.postLocal(message)
        }
        guard UserDefaults.standard.bool(forKey: Self.telegramKey), !sending else { return }
        // Avoid a Keychain lookup every second; only events ever read credentials.
        if checkedCredentialAt == nil || Date().timeIntervalSince(checkedCredentialAt!) > 30 {
            lastCredential = TelegramCredentialStore.load()
            checkedCredentialAt = Date()
        }
        guard let credential = lastCredential else { return }
        sending = true
        telegram.send(message, credential: credential) { [weak self] _ in
            DispatchQueue.main.async { self?.sending = false }
        }
    }

    func showSettings() {
        if settings == nil {
            settings = NotificationSettingsWindow { [weak self] in
                self?.lastCredential = nil
                self?.checkedCredentialAt = nil
            }
        }
        settings?.show()
    }

    static func postLocal(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "ROA"
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
