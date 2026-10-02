import Foundation

/// One reading from the motion sensor, gravity already removed.
public struct SensorSample: Sendable, Equatable {
    /// Seconds since streaming started.
    public let timestamp: Double
    public let x: Double
    public let y: Double
    public let z: Double
    public let magnitude: Double
    /// Magnitude with gravity still in.
    public let rawMagnitude: Double
    public let gx: Double
    public let gy: Double
    public let gz: Double
    public let gyroMagnitude: Double
    public var isSimulated: Bool

    public init(
        timestamp: Double,
        x: Double, y: Double, z: Double,
        magnitude: Double, rawMagnitude: Double,
        gx: Double = 0, gy: Double = 0, gz: Double = 0, gyroMagnitude: Double = 0,
        isSimulated: Bool = false
    ) {
        self.timestamp = timestamp
        self.x = x
        self.y = y
        self.z = z
        self.magnitude = magnitude
        self.rawMagnitude = rawMagnitude
        self.gx = gx
        self.gy = gy
        self.gz = gz
        self.gyroMagnitude = gyroMagnitude
        self.isSimulated = isSimulated
    }
}

public struct DetectedGesture: Codable, Sendable, Equatable {
    public let side: TapSide
    public let tapCount: Int
    public let timestamp: Double
    public let peakMagnitude: Double
    /// Lateral reading of the attack; calibration averages these.
    public let peakX: Double
    public var isSimulated: Bool

    public init(side: TapSide, tapCount: Int, timestamp: Double, peakMagnitude: Double, peakX: Double, isSimulated: Bool = false) {
        self.side = side
        self.tapCount = tapCount
        self.timestamp = timestamp
        self.peakMagnitude = peakMagnitude
        self.peakX = peakX
        self.isSimulated = isSimulated
    }

    public var tapWord: String { TapKit.tapWord(tapCount) }
}

/// Chassis-tap classifier on the undocumented SPU IMU (~800 Hz accel + gyro).
///
/// Onset follows Bonk (EMA delta, no minimum width). Side follows Knocker, but
/// at native 800 Hz we can do better: only the attack (~30 ms) counts, the
/// pre-tap X baseline is subtracted so gravity leak cannot pin every tap to
/// one edge, and bounce after ~35 ms is ignored.
///
/// Ported from MacTap. Not thread-safe: feed it from one queue. `onGesture`
/// and `onReject` are called on that queue.
public final class TapDetector {
    public var sensitivity: Double = 0.7
    public var groupingWindow: Double = 0.32
    public var invertSides = false
    public var sideBias: Double = 0
    public var ignoreWhileTyping = true
    public var classifySides = false

    public var onGesture: ((DetectedGesture) -> Void)?
    public var onReject: ((String) -> Void)?

    public private(set) var pendingTapCount = 0
    public private(set) var noiseFloor: Double = 0.006
    public private(set) var lastRejectReason = ""

    /// Wall-clock seconds; the typing checks run on this, not sample time.
    private let clock: () -> Double
    /// Seconds since the last key press anywhere in the session.
    private let secondsSinceLastKey: () -> Double

    private let refractoryPeriod: Double = 0.07
    private let maxPulseWidth: Double = 0.12
    private let minCaptureTime: Double = 0.032
    private let attackWindow: Double = 0.034
    private let attackTau: Double = 0.011
    private let typingBurstWindow: Double = 0.50
    private let typingLockout: Double = 0.40
    /// Pause knocks after a key press. Short enough for a follow-up knock, long enough for hunt-and-peck.
    private let keySuppressWindow: Double = 0.45

    private var emaMag: Double = 0
    private var emaRaw: Double = 1.0
    private var lastTapTime: Double = -1
    private var currentTapCount = 0
    private var currentSide: TapSide = .left
    private var groupDeadline: Double = 0
    private var groupPeakMag: Double = 0
    private var groupPeakX: Double = 0

    private var capturing = false
    private var captureStart: Double = 0
    private var capturePeakMag: Double = 0
    private var captureSamples = 0
    private var baselineX: Double = 0
    private var weightedX: Double = 0
    private var weightSum: Double = 0
    private var attackPeakX: Double = 0
    private var attackAbsX: Double = 0
    private var attackSumZ: Double = 0
    private var captureSimulated = false
    private var groupSimulated = false

    private var histX: [Double] = []
    private var histT: [Double] = []
    private let histMax = 96

    private var impulseTimes: [Double] = []
    private var typingUntil: Double = -1
    private var lastKeyTime: Double = -10
    private var lastTypingCheck: Double = 0
    private var cachedTyping = false

    public init(clock: @escaping () -> Double, secondsSinceLastKey: @escaping () -> Double) {
        self.clock = clock
        self.secondsSinceLastKey = secondsSinceLastKey
        histX.reserveCapacity(histMax)
        histT.reserveCapacity(histMax)
    }

    /// The onset threshold in g for a sensitivity in 0...1.
    public static func threshold(sensitivity: Double) -> Double {
        let minT = 0.012
        let maxT = 0.050
        return maxT - sensitivity * (maxT - minT)
    }

    private var tapThreshold: Double { Self.threshold(sensitivity: sensitivity) }

    private var snrMultiplier: Double { 3.0 - sensitivity * 1.2 }

    public func apply(_ config: TapConfig) {
        sensitivity = config.sensitivity
        groupingWindow = config.tapGroupingWindow
        invertSides = config.invertSides
        sideBias = config.sideBias
        ignoreWhileTyping = config.ignoreWhileTyping
        classifySides = config.layout == .sides
    }

    /// A key went down; a backup to the session's own last-key time.
    public func notifyTyping() {
        lastKeyTime = clock()
    }

    public func process(_ sample: SensorSample) {
        let mag = sample.magnitude
        let now = sample.timestamp

        pushHistory(x: sample.x, t: now)

        emaMag = 0.02 * mag + 0.98 * emaMag
        let delta = mag - emaMag
        emaRaw = 0.02 * sample.rawMagnitude + 0.98 * emaRaw
        let rawDelta = abs(sample.rawMagnitude - emaRaw)

        if mag < tapThreshold * 0.9 {
            noiseFloor = 0.02 * mag + 0.98 * noiseFloor
        }
        noiseFloor = min(max(noiseFloor, 0.0035), 0.030)

        let threshold = max(tapThreshold * 0.88, noiseFloor * snrMultiplier)
        let keyedRecently = ignoreWhileTyping && isActivelyTyping()
        let inTypingLockout = now < typingUntil || keyedRecently
        let inRefractory = (now - lastTapTime) < refractoryPeriod
        let onset = (mag > threshold || delta > threshold)
            && rawDelta > max(0.022, threshold * 0.65)

        if capturing {
            absorb(sample)
            let elapsed = now - captureStart
            let quiet = mag < capturePeakMag * 0.35 && elapsed >= (classifySides ? minCaptureTime : 0.006)
            if quiet || elapsed > maxPulseWidth || captureSamples > 100 {
                finalizeCapture(now: now, inTypingLockout: inTypingLockout, keyedRecently: keyedRecently)
            }
        } else if !inRefractory && onset {
            if keyedRecently {
                reject("typing")
            } else {
                startCapture(sample)
            }
        }

        if currentTapCount > 0 && now >= groupDeadline {
            emitGesture(now: now)
        }
        pendingTapCount = currentTapCount
    }

    /// The session's last-key time does not need Input Monitoring. The
    /// companion's global key monitor is a backup when that is granted.
    private func isActivelyTyping() -> Bool {
        let wall = clock()
        if wall - lastKeyTime < keySuppressWindow {
            return true
        }
        if wall - lastTypingCheck < 0.02 {
            return cachedTyping
        }
        lastTypingCheck = wall
        cachedTyping = secondsSinceLastKey() < keySuppressWindow
        return cachedTyping
    }

    private func pushHistory(x: Double, t: Double) {
        histX.append(x)
        histT.append(t)
        let overflow = histX.count - histMax
        if overflow > 0 {
            histX.removeFirst(overflow)
            histT.removeFirst(overflow)
        }
    }

    /// Mean X from 15–90 ms before onset. Residual gravity on HP X is a DC
    /// offset; integrating it makes every tap look like the same side.
    private func preTapBaseline(at now: Double) -> Double {
        var sum = 0.0
        var n = 0
        for i in histX.indices {
            let age = now - histT[i]
            if age > 0.012 && age < 0.10 {
                sum += histX[i]
                n += 1
            }
        }
        guard n >= 4 else { return 0 }
        return sum / Double(n)
    }

    private func startCapture(_ sample: SensorSample) {
        capturing = true
        captureStart = sample.timestamp
        capturePeakMag = sample.magnitude
        captureSamples = 1
        baselineX = preTapBaseline(at: sample.timestamp)
        weightedX = 0
        weightSum = 0
        attackPeakX = 0
        attackAbsX = 0
        attackSumZ = 0
        captureSimulated = sample.isSimulated
        accumulateAttack(sample)
    }

    private func absorb(_ sample: SensorSample) {
        captureSamples += 1
        if sample.magnitude > capturePeakMag {
            capturePeakMag = sample.magnitude
        }
        if sample.isSimulated { captureSimulated = true }
        accumulateAttack(sample)
    }

    private func accumulateAttack(_ sample: SensorSample) {
        let t = sample.timestamp - captureStart
        guard t <= attackWindow else { return }
        let w = exp(-t / attackTau)
        let dx = sample.x - baselineX
        weightedX += dx * w
        weightSum += w
        attackSumZ += sample.z * w
        if abs(dx) > attackAbsX {
            attackAbsX = abs(dx)
            attackPeakX = dx
        }
    }

    private func finalizeCapture(now: Double, inTypingLockout: Bool, keyedRecently: Bool) {
        capturing = false
        let peak = capturePeakMag
        let width = now - captureStart
        let snr = noiseFloor > 0 ? peak / noiseFloor : 99
        let meanAttackX = weightSum > 1e-9 ? weightedX / weightSum : attackPeakX
        let meanAttackZ = weightSum > 1e-9 ? attackSumZ / weightSum : 0

        defer { resetCapture() }

        if width > 0.16 {
            reject("slow pulse")
            return
        }
        if snr < 1.6 {
            reject("low SNR")
            return
        }
        if keyedRecently && abs(meanAttackZ) > abs(meanAttackX) * 2.2 && attackAbsX < 0.010 {
            reject("vertical (typing)")
            return
        }
        if inTypingLockout {
            reject("typing lockout")
            return
        }

        impulseTimes.append(now)
        impulseTimes = impulseTimes.filter { now - $0 < typingBurstWindow }
        if impulseTimes.count >= 4 {
            typingUntil = now + typingLockout
            impulseTimes.removeAll()
            reject("burst lockout")
            return
        }

        let side = classifySides
            ? classifySide(meanX: meanAttackX, peakX: attackPeakX)
            : .left
        let reportX = meanAttackX

        lastTapTime = now
        currentTapCount += 1
        groupPeakMag = max(groupPeakMag, peak)
        groupPeakX = abs(reportX) > abs(groupPeakX) ? reportX : groupPeakX
        groupSimulated = groupSimulated || captureSimulated

        if currentTapCount == 1 {
            currentSide = side
            groupDeadline = now + groupingWindow
            groupSimulated = captureSimulated
        } else if side != currentSide && attackAbsX > 0.008 {
            // The other edge: what came before is a gesture of its own.
            currentTapCount -= 1
            emitGesture(now: now)
            currentTapCount = 1
            currentSide = side
            groupPeakMag = peak
            groupPeakX = reportX
            groupSimulated = captureSimulated
            groupDeadline = now + groupingWindow
        }

        if currentTapCount >= 3 {
            emitGesture(now: now)
        }
    }

    /// Two votes from the attack only: energy-weighted mean X, and X at max |X|.
    /// Knocker default: +X = right. Bounce after ~35 ms is never consulted.
    private func classifySide(meanX: Double, peakX: Double) -> TapSide {
        var a = meanX + sideBias
        var p = peakX + sideBias
        if invertSides {
            a = -a
            p = -p
        }

        var right = 0
        var left = 0
        func vote(_ v: Double, floor: Double) {
            guard abs(v) >= floor else { return }
            if v > 0 { right += 1 } else { left += 1 }
        }
        vote(a, floor: 0.0024)
        vote(p, floor: 0.0040)

        if right > left { return .right }
        if left > right { return .left }
        // Tie or both weak: trust the weighted mean (less bounce).
        return a >= 0 ? .right : .left
    }

    private func resetCapture() {
        capturePeakMag = 0
        captureSamples = 0
        baselineX = 0
        weightedX = 0
        weightSum = 0
        attackPeakX = 0
        attackAbsX = 0
        attackSumZ = 0
        captureSimulated = false
    }

    private func emitGesture(now: Double) {
        guard currentTapCount > 0 else { return }

        let gesture = DetectedGesture(
            side: currentSide,
            tapCount: currentTapCount,
            timestamp: now,
            peakMagnitude: groupPeakMag,
            peakX: groupPeakX,
            isSimulated: groupSimulated
        )

        currentTapCount = 0
        groupPeakMag = 0
        groupPeakX = 0
        groupSimulated = false
        capturing = false
        resetCapture()
        pendingTapCount = 0
        onGesture?(gesture)
    }

    private func reject(_ reason: String) {
        lastRejectReason = reason
        onReject?(reason)
    }

    public static let sideHeuristicDescription =
        "Left/right uses the first ~30 ms of lateral X after subtracting the pre-tap baseline — the same impulse idea as Knocker, but bounce and gravity leak are ignored. Invert if your chassis is mirrored."
}
