import Foundation
import Security
import LocalAuthentication

public struct TelegramCredential: Codable, Equatable {
    public let token: String
    public let chatID: String
    public init(token: String, chatID: String) { self.token = token; self.chatID = chatID }
    public var isValid: Bool {
        token.range(of: #"^[0-9]{5,20}:[A-Za-z0-9_-]{20,100}\z"#, options: .regularExpression) != nil &&
        chatID.range(of: #"^-?[1-9][0-9]{0,19}\z"#, options: .regularExpression) != nil
    }
}

public enum TelegramCredentialStore {
    public static let service = "net.reviontech.roa.notifications"
    public static let account = "telegram"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
    public static func load() -> TelegramCredential? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        // Background checks must never unexpectedly prompt for Keychain access.
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let credential = try? JSONDecoder().decode(TelegramCredential.self, from: data),
              credential.isValid else { return nil }
        return credential
    }
    public static func save(_ credential: TelegramCredential) throws {
        guard credential.isValid else { throw TelegramError.invalidConfiguration }
        let data = try JSONEncoder().encode(credential)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw TelegramError.keychain }
        } else if status != errSecSuccess { throw TelegramError.keychain }
    }
    public static func forget() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw TelegramError.keychain }
    }
}

public enum TelegramError: LocalizedError, Equatable {
    case invalidConfiguration, keychain, delivery
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Enter a valid bot token and numeric chat ID."
        case .keychain: return "Keychain access failed. Unlock your login keychain and try again."
        case .delivery: return "Telegram delivery failed. Check your bot token, chat ID and connection. Open the bot chat and send /start first."
        }
    }
}

public enum TelegramMessage {
    public static func request(credential: TelegramCredential, text: String) throws -> URLRequest {
        guard credential.isValid, !text.isEmpty, text.count <= 4096,
              let url = URL(string: "https://api.telegram.org/bot\(credential.token)/sendMessage") else {
            throw TelegramError.invalidConfiguration
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["chat_id": credential.chatID, "text": text])
        return request
    }
    public static func accepted(data: Data, response: URLResponse) -> Bool {
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 65536, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = object["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID(), ok.boolValue else { return false }
        return true
    }
}

/// Refused redirects and a streaming limit keep credentials and responses contained.
public final class TelegramNotifier: NSObject, URLSessionDataDelegate {
    private let configuration: URLSessionConfiguration
    private let lock = NSLock()
    private var pending: ((Result<Void, TelegramError>) -> Void)?
    private var payload = Data()
    private var response: URLResponse?
    private var oversized = false
    private var taskID: Int?
    private lazy var session: URLSession = {
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    public override init() {
        configuration = .ephemeral
        super.init()
    }

    // Only module tests inject a protocol stub; production always uses ephemeral HTTPS.
    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
        super.init()
    }

    public func send(_ text: String, credential: TelegramCredential,
                     completion: @escaping (Result<Void, TelegramError>) -> Void) {
        guard let request = try? TelegramMessage.request(credential: credential, text: text) else {
            completion(.failure(.invalidConfiguration)); return
        }
        lock.lock()
        guard pending == nil else { lock.unlock(); completion(.failure(.delivery)); return }
        pending = completion
        payload = Data()
        response = nil
        oversized = false
        let task = session.dataTask(with: request)
        taskID = task.taskIdentifier
        lock.unlock()
        task.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        let reject = response.expectedContentLength > 65536
        self.response = response
        oversized = reject
        lock.unlock()
        completionHandler(reject ? .cancel : .allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let reject = data.count > 65536 - payload.count
        if reject { oversized = true } else { payload.append(data) }
        lock.unlock()
        if reject { dataTask.cancel() }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard task.taskIdentifier == taskID else { lock.unlock(); return }
        let accepted = error == nil && !oversized && response.map {
            TelegramMessage.accepted(data: payload, response: $0)
        } == true
        let completion = pending
        pending = nil
        payload = Data()
        response = nil
        taskID = nil
        lock.unlock()
        completion?(accepted ? .success(()) : .failure(.delivery))
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
