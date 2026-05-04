// GlassesServer.swift — updated to use Rokid AI glasses SDK
// Previously used raw TCP sockets; now communicates over Bluetooth via RokidSDK.
//
// Setup:
//   1. pod install  (Podfile already updated)
//   2. Get credentials from https://account.rokid.com/#/setting/prove
//   3. Fill in appKey / appSecret / accessKey below

import Foundation
import RokidSDK

// ── Credentials ───────────────────────────────────────────────────────────────
private let kAppKey    = "YOUR_APP_KEY"
private let kAppSecret = "YOUR_APP_SECRET"
private let kAccessKey = "YOUR_ACCESS_KEY"

// ─────────────────────────────────────────────────────────────────────────────
@MainActor
final class GlassesServer: ObservableObject {

    // Published state
    @Published var isRunning:    Bool = false
    @Published var isConnected:  Bool = false
    @Published var clientCount:  Int  = 0     // kept for UI compatibility; always 0 or 1
    @Published var nearbyDevices: [RKDevice] = []

    // Inbound callbacks (same contract as the original TCP version)
    var onRemoteQuery:     ((String) -> Void)?

    // Active paired device
    private var activeDevice: RKDevice?

    // ── SDK init ──────────────────────────────────────────────────────────────
    init() {
        RokidMobileSDK.shared.initSDK(
            appKey:    kAppKey,
            appSecret: kAppSecret,
            accessKey: kAccessKey
        ) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error { print("[Rokid] init error: \(error)") }
                else { self?.loadPairedDevices() }
            }
        }
        RokidMobileSDK.binder.addObserver(observer: self)
    }

    // ── Device discovery ──────────────────────────────────────────────────────
    func loadPairedDevices() {
        RokidMobileSDK.device.queryDeviceList { [weak self] _, devices in
            Task { @MainActor [weak self] in
                self?.nearbyDevices = devices ?? []
                // Auto-connect to first device if only one is paired
                if let first = devices?.first { self?.connectDevice(first) }
            }
        }
    }

    func connectDevice(_ device: RKDevice) {
        activeDevice = device
        isConnected  = true
        clientCount  = 1
        isRunning    = true
        print("[Rokid] Connected to \(device.deviceName ?? "glasses")")
    }

    func disconnectDevice() {
        activeDevice = nil
        isConnected  = false
        clientCount  = 0
        isRunning    = false
    }

    // ── Public API (original method signatures preserved) ─────────────────────
    func start() {
        loadPairedDevices()
    }

    func stop() {
        activeDevice = nil
        isConnected = false
    }

    func broadcastSummary(
        unreadCount: Int,
        emails: [OutlookEmail],
        events: [OutlookEvent],
        format: GlassesFormat
    ) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "summary", text: String(describing: unreadCount), to: dev)
    }

    func broadcastEmailAlert(_ email: OutlookEmail, reason: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "emailalert", text: String(describing: email), to: dev)
    }

    func broadcastEventAlert(_ event: OutlookEvent) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "eventalert", text: String(describing: event), to: dev)
    }

    func broadcastEmails(_ emails: [OutlookEmail]) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "emails", text: "", to: dev)
    }

    func broadcastEvents(_ events: [OutlookEvent]) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "events", text: "", to: dev)
    }

    func broadcastContact(_ contact: OutlookContact) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "contact", text: String(describing: contact), to: dev)
    }

    func broadcastStatus(_ text: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "status", text: String(describing: text), to: dev)
    }

    func broadcastError (_ text: String) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "error", text: String(describing: text), to: dev)
    }

    func start() {
        loadPairedDevices()
    }

    func send(_ data: Data) {
        guard let dev = activeDevice else { return }
        RokidMobileSDK.vui.sendMessage(topic: "message", text: String(describing: data), to: dev)
    }

    func cancel() {
        // TODO: map to Rokid SDK call
    }
}

// ── Receive voice commands FROM the glasses ───────────────────────────────────
extension GlassesServer: SDKBinderObserver {
    nonisolated func onAsrResult(_ asr: String, device: RKDevice) {
        let cmd = asr.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { @MainActor in
            if cmd.lowercased().hasPrefix("run ") {
                self.onGlassesCommand?(String(cmd.dropFirst(4)))
            } else if cmd.lowercased().hasPrefix("ai ") {
                self.onRemoteQuery?(String(cmd.dropFirst(3)))
            } else if cmd.lowercased() == "mic" {
                self.onMicTrigger?()
            } else {
                self.onGlassesCommand?(cmd)
            }
        }
    }
}
