import Foundation
import Darwin
import os
import ROACore
import ROAMac

guard geteuid() == 0, CommandLine.arguments.count == 3,
      CommandLine.arguments[1] == "--owner-uid",
      let owner = uid_t(CommandLine.arguments[2]), owner >= 501 else {
    fputs("Usage (root only): roa-service --owner-uid <uid>\n", stderr)
    exit(64)
}

let store = FileStore(owner: owner)
let sleepController = SleepController()
let guardPath = ROAConstants.dataRoot + "/guard.json"
let guardRecord = try? FileStore.read(GuardRecord.self, path: guardPath, owner: 0)
var policy = SafetyPolicy(restoring: guardRecord?.trip)
var lastGuardRecord = guardRecord
var controllerFault = guardRecord?.controllerFault
var guardNeedsRepair = FileManager.default.fileExists(atPath: guardPath) && guardRecord == nil
if guardNeedsRepair {
    controllerFault = ControllerFault(reason: "Guard record unreadable; turn OFF, then ON to retry",
                                      requestID: nil)
}
var lastStopReason = guardRecord?.lastStopReason ?? controllerFault?.reason ?? guardRecord?.trip?.reason
var lastReason = ""
let logger = Logger(subsystem: "net.reviontech.roa", category: "service")
var lastActual: Bool?
var previousPhase: ModePhase?
var lastObservation = -Double.infinity
var lastProcessedRequest: ModeRequest?

func log(_ message: String) {
    logger.notice("\(message, privacy: .public)")
}

// The installer owns this path; reject unexpected permissions and symlinks.
func prepareRuntimeDirectory() throws {
    if mkdir(ROAConstants.runtimeRoot, 0o755) != 0 && errno != EEXIST {
        throw StoreError.unsafeFile
    }
    var info = stat()
    guard lstat(ROAConstants.runtimeRoot, &info) == 0,
          info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == 0,
          info.st_mode & mode_t(0o022) == 0 else { throw StoreError.unsafeFile }
}

do {
    try prepareRuntimeDirectory()
} catch {
    log("Runtime directory validation failed: \(error)")
    exit(1) // launchd restarts; do not claim safety or enable a new hold.
}

let lockDescriptor = open(ROAConstants.runtimeRoot + "/service.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
var lockInfo = stat()
guard lockDescriptor >= 0, fstat(lockDescriptor, &lockInfo) == 0,
      lockInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), lockInfo.st_uid == 0,
      lockInfo.st_mode & mode_t(0o022) == 0,
      flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
    log("Service lock is unsafe or already held")
    exit(1)
}
// lockDescriptor remains open for the service lifetime.
do { try sleepController.setDisabled(false) }
catch { log("Startup recovery failed: \(error)"); exit(1) }

// Persist both safety and controller faults before enabling, and after any failure.
// If storage fails, keep the in-memory fault and retry; never enable a new hold.
func persistGuard(allowRepair: Bool, requestID: UUID?) {
    if let fault = controllerFault { lastStopReason = fault.reason }
    let record = GuardRecord(trip: policy.guardTrip, controllerFault: controllerFault,
                             lastStopReason: lastStopReason)
    if guardNeedsRepair && !allowRepair { return }
    guard record != lastGuardRecord || guardNeedsRepair else { return }
    do {
        try FileStore.write(record, path: guardPath, permissions: 0o600)
        lastGuardRecord = record
        guardNeedsRepair = false
    } catch {
        controllerFault = ControllerFault(reason: "Guard persistence failed; turn OFF, then ON to retry",
                                          requestID: requestID)
        lastStopReason = controllerFault?.reason
    }
}

func tick() {
    let request = store.request()
    lastProcessedRequest = request
    let sample = PowerMonitor.sample(owner: owner)
    let bootSessionID = BootSession.currentID()
    let uptime = BootSession.elapsedTime()
    let decision = policy.evaluate(request: request, sample: sample,
                                   currentBootSessionID: bootSessionID, currentUptime: uptime,
                                   requireBootSession: true)
    var phase = decision.phase
    var reason = decision.reason
    var actual: Bool?
    // A control fault also requires an explicit OFF before re-arming.
    let validOff = request?.isSupported == true && request?.enabled == false
    if previousPhase == .active && decision.phase != .active { lastStopReason = decision.reason }
    if let trip = policy.guardTrip { lastStopReason = trip.reason }
    if validOff && lastActual == true { lastStopReason = "ROA turned off" }
    if controllerFault?.permitsRecovery(request: request) == true { controllerFault = nil }
    persistGuard(allowRepair: validOff, requestID: request?.id)
    do {
        let target = decision.allowSleepOverride && controllerFault == nil
        actual = lastActual
        // Guard checks remain 1 Hz; avoid launching pmset every second while stable.
        if actual != target || !uptime.isFinite || !lastObservation.isFinite || uptime - lastObservation >= 5 {
            actual = try sleepController.current()
            if actual != target {
                try sleepController.setDisabled(target)
                actual = try sleepController.current()
                guard actual == target else { throw SleepControllerError.commandFailed }
            }
            lastActual = actual
            lastObservation = uptime
        }
    } catch {
        controllerFault = ControllerFault(reason: "Sleep control failed; turn OFF, then ON to retry",
                                          requestID: request?.id)
        // Best-effort release, followed by observation. Unknown never displays as active.
        try? sleepController.setDisabled(false)
        actual = try? sleepController.current()
        lastActual = actual
        lastObservation = uptime
        log("Power control error: \(error)")
    }
    persistGuard(allowRepair: validOff, requestID: request?.id)
    if let fault = controllerFault { phase = .error; reason = fault.reason }
    if phase == .active && actual != true {
        phase = .error
        reason = "Sleep prevention could not be confirmed"
    }
    let status = ServiceStatus(requestID: request?.id, desired: request?.enabled ?? false,
                               phase: phase, reason: reason, sleepDisabled: actual,
                               batteryPercent: sample.batteryPercent, thermal: sample.thermal,
                               onBattery: sample.onBattery,
                               remainingSeconds: request?.remainingSeconds(currentBootSessionID: bootSessionID,
                                                                           currentUptime: uptime),
                               lastStopReason: lastStopReason)
    do {
        try store.publish(status)
        previousPhase = phase
    }
    catch {
        try? sleepController.setDisabled(false)
        controllerFault = ControllerFault(reason: "Status publishing failed; turn OFF, then ON to retry",
                                          requestID: request?.id)
        lastActual = nil
        persistGuard(allowRepair: validOff, requestID: request?.id)
        log("Status error: \(error)")
    }
    if reason != lastReason { log(reason); lastReason = reason }
}

// Wake promptly when an atomic request write changes the directory. Coalesce the
// temporary-file/rename events and bound event-driven work to at most 20 Hz.
// All events still pass through FileStore validation and the full safety policy.
var requestRefreshScheduled = false
let requestMonitor = DirectoryChangeMonitor(
    path: URL(fileURLWithPath: store.requestPath).deletingLastPathComponent().path,
    owner: owner, queue: .main) {
        guard !requestRefreshScheduled else { return }
        requestRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
            requestRefreshScheduled = false
            if store.request() != lastProcessedRequest { tick() }
        }
    }

// Everything runs on one queue: no overlapping pmset operations or state mutations.
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
// Keep the 1 Hz timer for guards, expiry and recovery if monitoring is unavailable.
timer.setEventHandler { tick() }
timer.resume()

var signalSources: [DispatchSourceSignal] = []
for number in [SIGTERM, SIGINT] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        do { try sleepController.setDisabled(false) }
        catch { log("Shutdown release failed: \(error)") }
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}
dispatchMain()
