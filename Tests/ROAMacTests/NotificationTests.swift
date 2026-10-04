import XCTest
import ROACore
@testable import ROAMac

final class NotificationTests: XCTestCase {
    private func status(_ request: ModeRequest, phase: ModePhase, reason: String = "ROA is active") -> ServiceStatus {
        ServiceStatus(requestID: request.id, desired: request.enabled, phase: phase,
                      reason: reason, sleepDisabled: phase == .active, batteryPercent: 50, thermal: 0)
    }

    func testStartupDoesNotReplaySafetyStop() {
        var policy = NotificationPolicy()
        let request = ModeRequest(enabled: true)
        let stopped = status(request, phase: .blocked, reason: "Safety stop: high thermal pressure")
        XCTAssertNil(policy.observe(status: stopped, request: request))
        XCTAssertNil(policy.observe(status: stopped, request: request))
    }

    func testNewRequestFailureNotifiesOnceWithoutActiveAcknowledgement() {
        var policy = NotificationPolicy()
        let off = ModeRequest(enabled: false)
        XCTAssertNil(policy.observe(status: status(off, phase: .off), request: off))
        let request = ModeRequest(enabled: true)
        let stopped = status(request, phase: .blocked, reason: "Safety stop: battery is at 20% or lower")
        XCTAssertNotNil(policy.observe(status: stopped, request: request))
        XCTAssertNil(policy.observe(status: stopped, request: request))
    }

    func testExpiryIsDeduplicatedAndOrdinaryOffSilent() {
        var policy = NotificationPolicy()
        let request = ModeRequest(enabled: true)
        XCTAssertNil(policy.observe(status: status(request, phase: .active), request: request))
        let stopped = status(request, phase: .blocked, reason: "Session ended")
        XCTAssertEqual(policy.observe(status: stopped, request: request), "ROA stopped: Session ended")
        XCTAssertNil(policy.observe(status: stopped, request: request))
        let off = ModeRequest(enabled: false)
        XCTAssertNil(policy.observe(status: status(off, phase: .off), request: off))
    }

    func testServiceLossAfterEightSecondsAndManualOffRace() {
        var policy = NotificationPolicy()
        let now = Date()
        let request = ModeRequest(enabled: true)
        let active = status(request, phase: .active)
        XCTAssertNil(policy.observe(status: active, request: request, at: now))
        XCTAssertNil(policy.observe(status: nil, request: request, at: now.addingTimeInterval(8)))
        XCTAssertNotNil(policy.observe(status: nil, request: request, at: now.addingTimeInterval(9)))
        XCTAssertNil(policy.observe(status: nil, request: request, at: now.addingTimeInterval(10)))
        var offPolicy = NotificationPolicy()
        XCTAssertNil(offPolicy.observe(status: active, request: request, at: now))
        XCTAssertNil(offPolicy.observe(status: active, request: ModeRequest(enabled: false), at: now))
        XCTAssertNil(offPolicy.observe(status: nil, request: ModeRequest(enabled: false), at: now.addingTimeInterval(9)))
    }

    func testUserSwitchIsSilentAndRapidRecoveryRateLimited() {
        var policy = NotificationPolicy()
        let now = Date()
        let request = ModeRequest(enabled: true)
        XCTAssertNil(policy.observe(status: status(request, phase: .active), request: request, at: now))
        XCTAssertNil(policy.observe(status: status(request, phase: .blocked, reason: "Paused: installing account is not active"), request: request, at: now))
        XCTAssertNotNil(policy.observe(status: status(request, phase: .error, reason: "Controller failed"), request: request, at: now))
        let retry = ModeRequest(enabled: true)
        XCTAssertNil(policy.observe(status: status(retry, phase: .active), request: retry, at: now))
        XCTAssertNil(policy.observe(status: status(retry, phase: .error, reason: "Controller failed"), request: retry, at: now.addingTimeInterval(1)))
    }

    func testTelegramPayloadAndCredentialValidation() throws {
        let credential = TelegramCredential(token: "123456789:" + String(repeating: "A", count: 35), chatID: "-123456789")
        XCTAssertTrue(credential.isValid)
        let request = try TelegramMessage.request(credential: credential, text: "ROA stopped: Session ended")
        XCTAssertEqual(request.url?.host, "api.telegram.org")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        XCTAssertEqual(object?["chat_id"], credential.chatID)
        XCTAssertEqual(object?["text"], "ROA stopped: Session ended")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains(credential.token))
        for token in ["../../secret", "12345:abc/def", "12345:" + String(repeating: "A", count: 35) + "?redirect=evil"] {
            XCTAssertFalse(TelegramCredential(token: token, chatID: "123").isValid)
        }
        for id in ["0", "@publicname", "123/anything", "123\n456", "123\n", ""] {
            XCTAssertFalse(TelegramCredential(token: credential.token, chatID: id).isValid)
        }
        XCTAssertThrowsError(try TelegramMessage.request(credential: credential, text: String(repeating: "a", count: 4097)))
    }

    func testTelegramRequiresSuccessfulJSONAndNeverExposesCredentialErrors() throws {
        let url = URL(string: "https://api.telegram.org/")!
        let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertTrue(TelegramMessage.accepted(data: Data(#"{"ok":true,"result":{}}"#.utf8), response: ok))
        for payload in [#"{"ok":false,"description":"private token"}"#, "garbage", #"{"ok":"true"}"#, #"{"ok":1}"#, #"{}"#] {
            XCTAssertFalse(TelegramMessage.accepted(data: Data(payload.utf8), response: ok))
        }
        let redirect = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        XCTAssertFalse(TelegramMessage.accepted(data: Data(#"{"ok":true}"#.utf8), response: redirect))
        let notifier = TelegramNotifier()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: url)
        let expectation = expectation(description: "Redirect rejected")
        notifier.urlSession(session, task: task, willPerformHTTPRedirection: redirect,
                            newRequest: URLRequest(url: URL(string: "https://example.com/")!)) { redirected in
            XCTAssertNil(redirected)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
        session.invalidateAndCancel()
        XCTAssertEqual(TelegramError.delivery.errorDescription, "Telegram delivery failed. Check your bot token, chat ID and connection. Open the bot chat and send /start first.")
    }
}

private final class TelegramMockProtocol: URLProtocol {
    static var reply: (TelegramMockProtocol) -> Void = { _ in }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.reply(self) }
    override func stopLoading() {}
}

extension NotificationTests {
    func testMockTransportAcceptsOnlyValidBoundedResponses() {
        let credential = TelegramCredential(token: "123456789:" + String(repeating: "A", count: 35), chatID: "123456")
        let cases: [(Data, [String: String], Bool)] = [
            (Data(#"{"ok":true}"#.utf8), [:], true),
            (Data(#"{"ok":false}"#.utf8), [:], false),
            (Data(repeating: 65, count: 65537), [:], false),
            (Data(#"{"ok":true}"#.utf8), ["Content-Length": "65537"], false)
        ]
        for (body, headers, succeeds) in cases {
            TelegramMockProtocol.reply = { stub in
                let response = HTTPURLResponse(url: stub.request.url!, statusCode: 200,
                                               httpVersion: nil, headerFields: headers)!
                stub.client?.urlProtocol(stub, didReceive: response, cacheStoragePolicy: .notAllowed)
                stub.client?.urlProtocol(stub, didLoad: body)
                stub.client?.urlProtocolDidFinishLoading(stub)
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [TelegramMockProtocol.self]
            let notifier = TelegramNotifier(configuration: configuration)
            let done = expectation(description: "Mock response completed")
            notifier.send("ROA test", credential: credential) { result in
                switch result {
                case .success: XCTAssertTrue(succeeds)
                case .failure(let error):
                    XCTAssertFalse(succeeds)
                    XCTAssertEqual(error, .delivery)
                }
                done.fulfill()
            }
            wait(for: [done], timeout: 2)
        }
    }

    func testMockTimeoutIsSanitized() {
        TelegramMockProtocol.reply = { stub in
            stub.client?.urlProtocol(stub, didFailWithError: NSError(domain: NSURLErrorDomain,
                code: NSURLErrorTimedOut, userInfo: [NSLocalizedDescriptionKey: "secret-token-and-private-chat"]))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TelegramMockProtocol.self]
        let notifier = TelegramNotifier(configuration: configuration)
        let done = expectation(description: "Mock timeout completed")
        let credential = TelegramCredential(token: "123456789:" + String(repeating: "A", count: 35), chatID: "123456")
        notifier.send("ROA test", credential: credential) { result in
            guard case .failure(let error) = result else { XCTFail("Expected timeout failure"); done.fulfill(); return }
            XCTAssertEqual(error, .delivery)
            XCTAssertFalse((error.errorDescription ?? "").contains("secret"))
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }
}
