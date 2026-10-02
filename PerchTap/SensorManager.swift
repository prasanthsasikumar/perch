import AppKit
import Foundation
import IOKit
import IOKit.hid
import QuartzCore
import TapKit

/// Undocumented Bosch BMI286 via AppleSPUHIDDevice.
/// Accel = vendor page 0xFF00 usage 3, gyro = usage 9, ~800 Hz native.
///
/// Ported from MacTap. Reports arrive on a dedicated HID thread and go
/// straight to `onSample`; everything the interface shows is read through
/// `snapshot()`.
final class SensorManager {
    struct Snapshot {
        var source: SensorSource
        var isStreaming: Bool
        var gyroAvailable: Bool
        var sampleRateHz: Double
        var sampleCount: Int
        var lastError: String?
        var lastSample: SensorSample?
        var magnitude: [Double]
        var x: [Double]
        var y: [Double]
        var z: [Double]
    }

    /// On the HID thread, ~800 times a second.
    var onSample: ((SensorSample) -> Void)?
    /// A key went down somewhere. Main thread.
    var onTyping: (() -> Void)?

    private static let waveformBufferSize = 240

    private var accelDevice: IOHIDDevice?
    private var gyroDevice: IOHIDDevice?
    private var runLoop: CFRunLoop?
    private var runLoopThread: Thread?

    private var accelReportBuffer: [UInt8]
    private var gyroReportBuffer: [UInt8]
    private static let reportBufferSize = 4096

    /// Native ~800 Hz. Do not decimate — tap peaks are 8–25 ms and vanish at 100 Hz.
    private static let vendorUsagePage: UInt32 = 0xFF00
    private static let accelerometerUsage: UInt32 = 3
    private static let gyroscopeUsage: UInt32 = 9
    private static let reportLength = 22
    private static let dataOffset = 6
    private static let imuScale = 65536.0
    private static let wakeIntervalUs: Int32 = 8000
    private static let runIntervalUs: Int32 = 1250

    private let kIOReturnNotPrivileged: kern_return_t = 0x2c7
    private let kIOReturnExclusiveAccess: kern_return_t = 0x2c2

    private var startTime: Double = 0
    private var lastRateTick: Double = 0
    private var rateBucket = 0

    private var emaGravityX = EMA(alpha: 0.0025)
    private var emaGravityY = EMA(alpha: 0.0025)
    private var emaGravityZ = EMA(alpha: 0.0025)

    private var latestGyroX = 0.0
    private var latestGyroY = 0.0
    private var latestGyroZ = 0.0
    private let gyroLock = NSLock()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var typingMonitor: Any?

    private var magRing: [Double] = []
    private var xRing: [Double] = []
    private var yRing: [Double] = []
    private var zRing: [Double] = []

    private var lastAccelAt: Double = 0
    private var measuredHz: Double = 0
    private var collectedSamples = 0
    private var lastSample: SensorSample?
    private var keepAliveTimer: DispatchSourceTimer?
    private var wakeObservers: [NSObjectProtocol] = []
    private let keepAliveQueue = DispatchQueue(label: "org.ahlab.Perch.tap.spu.keepalive", qos: .utility)
    private let stateLock = NSLock()

    private var source: SensorSource = .unavailable
    private var isStreaming = false
    private var gyroAvailable = false
    private var lastError: String?

    /// Debug builds only: the arrow keys stand in for knocks.
    #if DEBUG
    var isArrowSimulationEnabled = false
    #else
    var isArrowSimulationEnabled: Bool {
        get { false }
        set {}
    }
    #endif

    var isAvailable: Bool { stateLock.withLock { source } == .spu || isArrowSimulationEnabled }

    init() {
        accelReportBuffer = [UInt8](repeating: 0, count: Self.reportBufferSize)
        gyroReportBuffer = [UInt8](repeating: 0, count: Self.reportBufferSize)
        magRing.reserveCapacity(Self.waveformBufferSize)
        detectSource()
    }

    func snapshot() -> Snapshot {
        stateLock.withLock {
            Snapshot(
                source: source,
                isStreaming: isStreaming,
                gyroAvailable: gyroAvailable,
                sampleRateHz: measuredHz,
                sampleCount: collectedSamples,
                lastError: lastError,
                lastSample: lastSample,
                magnitude: magRing,
                x: xRing,
                y: yRing,
                z: zRing
            )
        }
    }

    private func setSource(_ value: SensorSource) {
        stateLock.withLock { source = value }
    }

    private func detectSource() {
        if let service = findSPUDevice(usage: Self.accelerometerUsage) {
            IOObjectRelease(service)
            setSource(.spu)
            NSLog("Perch Tap: SPU accelerometer found")
        } else {
            setSource(.unavailable)
            NSLog("Perch Tap: SPU accelerometer not found — keyboard simulation disabled")
        }
    }

    /// Usage 3 (accel) / 9 (gyro) with a 22-byte HID report on SPU transport.
    /// No fallback for other report sizes — that was latching onto the wrong device.
    private func findSPUDevice(usage: UInt32) -> io_service_t? {
        let matching = IOServiceMatching("AppleSPUHIDDevice")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            let usagePage = getIOPropertyUInt32(service, "PrimaryUsagePage") ?? 0
            let primaryUsage = getIOPropertyUInt32(service, "PrimaryUsage") ?? 0
            guard usagePage == Self.vendorUsagePage, primaryUsage == usage else {
                IOObjectRelease(service)
                continue
            }
            let reportSize = getIOPropertyUInt32(service, "MaxInputReportSize") ?? 0
            let transport = getIOPropertyString(service, "Transport") ?? ""
            let looksLikeSPU = transport.isEmpty || transport.uppercased().contains("SPU")
            guard reportSize == Self.reportLength, looksLikeSPU else {
                IOObjectRelease(service)
                continue
            }
            return service
        }
        return nil
    }

    private func getIOPropertyUInt32(_ service: io_service_t, _ key: String) -> UInt32? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        let value = unmanaged.takeRetainedValue()
        guard CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        let number = value as! CFNumber
        var intVal: Int32 = 0
        if CFNumberGetValue(number, .sInt32Type, &intVal) {
            return UInt32(bitPattern: intVal)
        }
        var int64Val: Int64 = 0
        if CFNumberGetValue(number, .sInt64Type, &int64Val) {
            return UInt32(truncatingIfNeeded: int64Val)
        }
        return nil
    }

    private func getIOPropertyString(_ service: io_service_t, _ key: String) -> String? {
        guard let unmanaged = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as? String
    }

    /// Knock/Bonk wake: 8000 µs pokes a dormant SPU. 1250 µs is native ~800 Hz.
    /// IOHIDDeviceSetProperty on the client does nothing — must hit AppleSPUHIDDriver in the registry.
    /// This is the call Perch's sandbox refuses, and the first reason this
    /// companion exists.
    private func wakeSPUDriver(full: Bool = true, log: Bool = false) {
        let matching = IOServiceMatching("AppleSPUHIDDriver")
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        var count = 0
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            setIOProperty(service, "SensorPropertyReportingState", int32Value: 1)
            setIOProperty(service, "SensorPropertyPowerState", int32Value: 1)
            if full {
                setIOProperty(service, "ReportInterval", int32Value: Self.wakeIntervalUs)
            }
            setIOProperty(service, "ReportInterval", int32Value: Self.runIntervalUs)
            count += 1
        }
        if log, count > 0 {
            NSLog("Perch Tap: woke %d AppleSPUHIDDriver service(s)", count)
        }
    }

    private func setIOProperty(_ service: io_service_t, _ key: String, int32Value value: Int32) {
        var v = value
        if let cfValue = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &v) {
            IORegistryEntrySetCFProperty(service, key as CFString, cfValue)
        }
    }

    private func applyHIDReportInterval(_ device: IOHIDDevice, microseconds: Int32) {
        var v = microseconds
        if let num = CFNumberCreate(kCFAllocatorDefault, .sInt32Type, &v) {
            IOHIDDeviceSetProperty(device, "ReportInterval" as CFString, num)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !stateLock.withLock({ isStreaming }) else { return true }
        stateLock.withLock {
            startTime = CACurrentMediaTime()
            lastRateTick = startTime
            collectedSamples = 0
            rateBucket = 0
            measuredHz = 0
            magRing.removeAll(keepingCapacity: true)
            xRing.removeAll(keepingCapacity: true)
            yRing.removeAll(keepingCapacity: true)
            zRing.removeAll(keepingCapacity: true)
            lastAccelAt = CACurrentMediaTime()
            lastError = nil
        }
        gyroLock.withLock {
            latestGyroX = 0
            latestGyroY = 0
            latestGyroZ = 0
        }

        // A sensor that failed to open last time may open now.
        if let service = findSPUDevice(usage: Self.accelerometerUsage) {
            IOObjectRelease(service)
            setSource(.spu)
        }

        switch stateLock.withLock({ source }) {
        case .spu:
            guard startSPUStreaming() else {
                setSource(.unavailable)
                NSLog("Perch Tap: motion sensor present but not openable — engine stays stopped")
                return false
            }
        case .keyboardSim, .unavailable:
            guard isArrowSimulationEnabled else {
                setSource(.unavailable)
                NSLog("Perch Tap: motion sensor unavailable — not binding arrow keys")
                return false
            }
            setSource(.keyboardSim)
            startKeyboardSimulation()
        }

        startTypingMonitor()
        if stateLock.withLock({ source }) == .spu {
            startKeepAlive()
        }
        stateLock.withLock { isStreaming = true }
        return true
    }

    func stop() {
        stopKeepAlive()
        close(accelDevice)
        close(gyroDevice)
        accelDevice = nil
        gyroDevice = nil
        if let rl = runLoop {
            CFRunLoopStop(rl)
            runLoop = nil
        }
        runLoopThread = nil
        removeMonitors()
        stateLock.withLock {
            isStreaming = false
            gyroAvailable = false
            if source == .keyboardSim { source = .unavailable }
        }
        detectSource()
        NSLog("Perch Tap: sensor stopped (%d samples)", stateLock.withLock { collectedSamples })
    }

    private func close(_ device: IOHIDDevice?) {
        if let device {
            IOHIDDeviceClose(device, 0)
        }
    }

    private func removeMonitors() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor); globalMonitor = nil }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor); localMonitor = nil }
        if let monitor = typingMonitor { NSEvent.removeMonitor(monitor); typingMonitor = nil }
    }

    private func startSPUStreaming() -> Bool {
        wakeSPUDriver(full: true, log: true)
        guard let accelService = findSPUDevice(usage: Self.accelerometerUsage) else {
            setSource(.unavailable)
            return false
        }
        defer { IOObjectRelease(accelService) }

        guard let accel = openHID(accelService) else {
            setSource(.unavailable)
            return false
        }
        accelDevice = accel

        var gyro: IOHIDDevice?
        if let gyroService = findSPUDevice(usage: Self.gyroscopeUsage) {
            defer { IOObjectRelease(gyroService) }
            gyro = openHID(gyroService)
            gyroDevice = gyro
            stateLock.withLock { gyroAvailable = gyro != nil }
            if gyro != nil {
                NSLog("Perch Tap: SPU gyroscope opened (usage 9)")
            }
        }

        registerCallback(device: accel, buffer: &accelReportBuffer)
        if let gyro {
            registerCallback(device: gyro, buffer: &gyroReportBuffer)
        }

        let accelRef = accel
        let gyroRef = gyro
        let thread = Thread { [weak self] in
            guard let rl = CFRunLoopGetCurrent() else { return }
            self?.runLoop = rl
            IOHIDDeviceScheduleWithRunLoop(accelRef, rl, CFRunLoopMode.defaultMode.rawValue)
            if let gyroRef {
                IOHIDDeviceScheduleWithRunLoop(gyroRef, rl, CFRunLoopMode.defaultMode.rawValue)
            }
            CFRunLoopRun()
        }
        thread.name = "PerchTap.SPU.HID"
        thread.qualityOfService = .userInteractive
        thread.start()
        runLoopThread = thread
        return true
    }

    private func openHID(_ service: io_service_t) -> IOHIDDevice? {
        guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return nil }
        let openResult = IOHIDDeviceOpen(device, 0)
        guard openResult == kIOReturnSuccess else {
            let reason = switch openResult {
            case kIOReturnNotPrivileged: "not privileged"
            case kIOReturnExclusiveAccess: "exclusive access"
            default: String(format: "0x%x", openResult)
            }
            NSLog("Perch Tap: IOHIDDeviceOpen failed: %@", reason)
            stateLock.withLock { lastError = reason }
            return nil
        }
        applyHIDReportInterval(device, microseconds: Self.runIntervalUs)
        return device
    }

    private func registerCallback(device: IOHIDDevice, buffer: inout [UInt8]) {
        let callback: IOHIDReportCallback = { context, _, sender, _, _, report, reportLength in
            guard let context else { return }
            let manager = Unmanaged<SensorManager>.fromOpaque(context).takeUnretainedValue()
            manager.dispatchHIDReport(sender: sender, report: report, length: reportLength)
        }
        buffer.withUnsafeMutableBufferPointer { buf in
            IOHIDDeviceRegisterInputReportCallback(
                device,
                buf.baseAddress!,
                Self.reportBufferSize,
                callback,
                Unmanaged.passUnretained(self).toOpaque()
            )
        }
    }

    private func dispatchHIDReport(sender: UnsafeMutableRawPointer?, report: UnsafePointer<UInt8>, length: CFIndex) {
        if let gyro = gyroDevice, let sender, sender == Unmanaged.passUnretained(gyro).toOpaque() {
            handleGyroReport(report: report, length: length)
        } else {
            handleAccelReport(report: report, length: length)
        }
    }

    private func handleGyroReport(report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length == Self.reportLength else { return }
        let x = Double(readInt32LE(report, offset: Self.dataOffset)) / Self.imuScale
        let y = Double(readInt32LE(report, offset: Self.dataOffset + 4)) / Self.imuScale
        let z = Double(readInt32LE(report, offset: Self.dataOffset + 8)) / Self.imuScale
        gyroLock.withLock {
            latestGyroX = x
            latestGyroY = y
            latestGyroZ = z
        }
    }

    private func handleAccelReport(report: UnsafePointer<UInt8>, length: CFIndex) {
        guard length == Self.reportLength else { return }

        let rawX = Double(readInt32LE(report, offset: Self.dataOffset)) / Self.imuScale
        let rawY = Double(readInt32LE(report, offset: Self.dataOffset + 4)) / Self.imuScale
        let rawZ = Double(readInt32LE(report, offset: Self.dataOffset + 8)) / Self.imuScale

        let (gx, gy, gz, start) = stateLock.withLock {
            (emaGravityX.update(rawX), emaGravityY.update(rawY), emaGravityZ.update(rawZ), startTime)
        }

        let hx = rawX - gx
        let hy = rawY - gy
        let hz = rawZ - gz
        let mag = sqrt(hx * hx + hy * hy + hz * hz)
        let rawMag = sqrt(rawX * rawX + rawY * rawY + rawZ * rawZ)

        let (wx, wy, wz) = gyroLock.withLock { (latestGyroX, latestGyroY, latestGyroZ) }
        let gmag = sqrt(wx * wx + wy * wy + wz * wz)

        let sample = SensorSample(
            timestamp: CACurrentMediaTime() - start,
            x: hx, y: hy, z: hz,
            magnitude: mag,
            rawMagnitude: rawMag,
            gx: wx, gy: wy, gz: wz,
            gyroMagnitude: gmag
        )
        ingest(sample)
    }

    private func ingest(_ sample: SensorSample) {
        onSample?(sample)

        stateLock.lock()
        collectedSamples += 1
        rateBucket += 1
        lastAccelAt = CACurrentMediaTime()
        lastSample = sample

        magRing.append(sample.magnitude)
        xRing.append(sample.x)
        yRing.append(sample.y)
        zRing.append(sample.z)
        let overflow = magRing.count - Self.waveformBufferSize
        if overflow > 0 {
            magRing.removeFirst(overflow)
            xRing.removeFirst(overflow)
            yRing.removeFirst(overflow)
            zRing.removeFirst(overflow)
        }

        let now = CACurrentMediaTime()
        if now - lastRateTick >= 1.0 {
            measuredHz = Double(rateBucket) / (now - lastRateTick)
            rateBucket = 0
            lastRateTick = now
        }
        stateLock.unlock()
    }

    /// Correct signed little-endian Int32. Shifting Int32 bytes overflows and corrupts negative g.
    private func readInt32LE(_ ptr: UnsafePointer<UInt8>, offset: Int) -> Int32 {
        let u = UInt32(ptr[offset])
            | (UInt32(ptr[offset + 1]) << 8)
            | (UInt32(ptr[offset + 2]) << 16)
            | (UInt32(ptr[offset + 3]) << 24)
        return Int32(bitPattern: u)
    }

    private func startKeepAlive() {
        stopKeepAlive()
        stateLock.withLock { lastAccelAt = CACurrentMediaTime() }

        let timer = DispatchSource.makeTimerSource(queue: keepAliveQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            self?.keepSPUAlive()
        }
        timer.resume()
        keepAliveTimer = timer

        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.keepAliveQueue.async {
                    guard let self else { return }
                    self.stateLock.withLock {
                        self.emaGravityX.reset()
                        self.emaGravityY.reset()
                        self.emaGravityZ.reset()
                        self.lastAccelAt = CACurrentMediaTime()
                    }
                    self.wakeSPUDriver(full: true, log: true)
                }
            }
            wakeObservers.append(obs)
        }
    }

    private func stopKeepAlive() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        let nc = NSWorkspace.shared.notificationCenter
        for obs in wakeObservers {
            nc.removeObserver(obs)
        }
        wakeObservers.removeAll()
    }

    /// When the chassis is still, macOS parks the BMI286. HID stays open but reports stop.
    /// A one-shot wake at launch is not enough — the driver re-parks after idle.
    private func keepSPUAlive() {
        guard accelDevice != nil else { return }
        let (silence, hz) = stateLock.withLock { (CACurrentMediaTime() - lastAccelAt, measuredHz) }
        // ~100 Hz idle on a still chassis misses 8–25 ms knocks. Treat anything
        // under native ~800 Hz as parked and run the Knock 8000→1250 wake.
        if silence > 0.25 || hz < 450 {
            NSLog("Perch Tap: SPU idle (%.2fs silent, %.0f Hz) — re-wake", silence, hz)
            wakeSPUDriver(full: true, log: true)
            if let accel = accelDevice {
                applyHIDReportInterval(accel, microseconds: Self.runIntervalUs)
            }
            if let gyro = gyroDevice {
                applyHIDReportInterval(gyro, microseconds: Self.runIntervalUs)
            }
        } else {
            wakeSPUDriver(full: false, log: false)
        }
    }

    private func startTypingMonitor() {
        typingMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return }
            // Arrow keys are typing unless debug simulation is using them as fake knocks.
            if self.isArrowSimulationEnabled && (event.keyCode == 123 || event.keyCode == 124) {
                return
            }
            self.onTyping?()
        }
    }

    private func startKeyboardSimulation() {
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let polarity: Double
            switch event.keyCode {
            case 123: polarity = -1
            case 124: polarity = 1
            default: return
            }
            self.emitSimulatedTap(polarity: polarity)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { handler($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return event
        }
        NSLog("Perch Tap: keyboard simulation (Left/Right arrows)")
    }

    private func emitSimulatedTap(polarity: Double) {
        let t0 = CACurrentMediaTime() - stateLock.withLock { startTime }
        let envelope: [(Double, Double)] = [(0.08, 0.0), (0.32, 0.004), (0.18, 0.008), (0.05, 0.014)]
        for (mag, delay) in envelope {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                let sample = SensorSample(
                    timestamp: t0 + delay,
                    x: polarity * mag,
                    y: 0,
                    z: 0,
                    magnitude: mag,
                    rawMagnitude: mag,
                    gx: 0,
                    gy: polarity * mag * 40,
                    gz: polarity * mag * 12,
                    gyroMagnitude: abs(polarity * mag * 42),
                    isSimulated: true
                )
                self.ingest(sample)
            }
        }
    }

    deinit { stop() }
}

private final class EMA {
    let alpha: Double
    private var value: Double = 0
    private var initialised = false

    init(alpha: Double) { self.alpha = alpha }

    func update(_ input: Double) -> Double {
        if !initialised {
            value = input
            initialised = true
        } else {
            value = alpha * input + (1 - alpha) * value
        }
        return value
    }

    func reset() {
        initialised = false
        value = 0
    }
}
