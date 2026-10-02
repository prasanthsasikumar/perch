import AVFoundation
import Foundation

/// Ten packs of six synthesized sounds, one per side and knock count.
/// The raw values are stored in the user's settings.
public enum SoundPack: String, CaseIterable, Codable, Identifiable, Sendable {
    case drumKit     = "Drum Kit"
    case synthBlips  = "Synth Blips"
    case retroArcade = "Retro Arcade"
    case nature      = "Nature FX"
    case cyberpunk   = "Cyberpunk"
    case crystal     = "Crystal"
    case voices      = "Voices"
    case cinematic   = "Cinematic"
    case mechanical  = "Mechanical"
    case space       = "Deep Space"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .drumKit:     return "music.note"
        case .synthBlips:  return "waveform.badge.plus"
        case .retroArcade: return "gamecontroller.fill"
        case .nature:      return "leaf.fill"
        case .cyberpunk:   return "bolt.horizontal.fill"
        case .crystal:     return "sparkle"
        case .voices:      return "waveform.and.mic"
        case .cinematic:   return "film.fill"
        case .mechanical:  return "gearshape.2.fill"
        case .space:       return "sparkles"
        }
    }

    public var description: String {
        switch self {
        case .drumKit:     return "Kick, snare, hat, clap, tom, crash"
        case .synthBlips:  return "Blip, bloop, zap, ping, sweep, chord"
        case .retroArcade: return "Coin, shoot, jump, boom, power-up, 1-UP"
        case .nature:      return "Click, pop, splash, drip, rustle, rumble"
        case .cyberpunk:   return "Glitch, laser, hologram, static, chirp, overload"
        case .crystal:     return "Ping, chime, shard, bell, harmonic, shatter"
        case .voices:      return "Synthetic TAP, GO, LOCK, YES, HEY, DONE"
        case .cinematic:   return "Boom, whoosh, hit, riser, subdrop, sting"
        case .mechanical:  return "Solenoid, servo, ratchet, relay, stamp, hatch"
        case .space:       return "Sonar, warp, radio, alien, beacon, impact"
        }
    }

    public var sounds: [String] {
        switch self {
        case .drumKit:     return ["kick", "snare", "hihat", "clap", "tom", "crash"]
        case .synthBlips:  return ["blip", "bloop", "zap", "ping", "sweep", "chord"]
        case .retroArcade: return ["coin", "shoot", "jump", "explosion", "powerup", "oneup"]
        case .nature:      return ["click", "pop", "splash", "drip", "rustle", "thunder"]
        case .cyberpunk:   return ["glitch", "laser", "hologram", "static", "chirp", "overload"]
        case .crystal:     return ["cping", "chime", "shard", "bell", "harmonic", "shatter"]
        case .voices:      return ["tap", "go", "lock", "yes", "hey", "done"]
        case .cinematic:   return ["boom", "whoosh", "hit", "riser", "subdrop", "sting"]
        case .mechanical:  return ["solenoid", "servo", "ratchet", "relay", "stamp", "hatch"]
        case .space:       return ["sonar", "warp", "radio", "alien", "beacon", "impact"]
        }
    }
}

/// Programmatic sound FX — no sample files. Stereo pan follows chassis side.
///
/// Ported from MacTap. Used by the companion when a knock lands, and by
/// Perch's settings to preview a pack.
public final class TapSound {
    public var pack: SoundPack = .drumKit {
        didSet { if pack != oldValue { bufferCache.removeAll() } }
    }
    public var volume: Float = 0.7

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var bufferCache: [String: AVAudioPCMBuffer] = [:]
    private var outputFormat: AVAudioFormat?

    public init() {}

    public func apply(_ config: TapConfig) {
        pack = config.soundPack
        volume = config.soundVolume
    }

    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            audioEngine = engine
            playerNode = node
            outputFormat = format
        } catch {
            NSLog("Perch Tap: audio engine failed: %@", error.localizedDescription)
        }
    }

    public func playTapSound(side: TapSide, tapCount: Int) {
        let sounds = pack.sounds
        guard !sounds.isEmpty else { return }
        let index = (tapCount - 1 + (side == .right ? 3 : 0)) % sounds.count
        playSound(sounds[index], pan: side == .left ? -0.65 : 0.65)
    }

    public func playSound(_ name: String, pan: Float = 0) {
        guard !name.isEmpty else { return }
        ensureRunning()
        guard let playerNode, let engine = audioEngine, engine.isRunning else { return }

        let buffer: AVAudioPCMBuffer
        if let cached = bufferCache[name] {
            buffer = cached
        } else if let generated = generateSound(name) {
            bufferCache[name] = generated
            buffer = generated
        } else {
            return
        }

        guard buffer.format.channelCount == outputFormat?.channelCount,
              buffer.format.sampleRate == outputFormat?.sampleRate else {
            bufferCache.removeAll()
            return
        }

        playerNode.volume = volume
        playerNode.pan = pan
        playerNode.scheduleBuffer(buffer, at: nil, options: [.interrupts])
        if !playerNode.isPlaying { playerNode.play() }
    }

    public func preloadPack() {
        ensureRunning()
        for sound in pack.sounds where bufferCache[sound] == nil {
            if let buffer = generateSound(sound) {
                bufferCache[sound] = buffer
            }
        }
    }

    /// Lets the audio hardware go idle until the next sound.
    public func stop() {
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        outputFormat = nil
        bufferCache.removeAll()
    }

    private func ensureRunning() {
        if audioEngine == nil { setupAudioEngine() }
        if let engine = audioEngine, !engine.isRunning {
            try? engine.start()
        }
    }

    // MARK: - Synthesis

    func generateSound(_ name: String) -> AVAudioPCMBuffer? {
        guard let format = outputFormat else { return nil }
        let sr = format.sampleRate
        let samples: [Float]
        switch name {
        case "kick": samples = kick(sr)
        case "snare": samples = snare(sr)
        case "hihat": samples = hat(sr)
        case "clap": samples = clap(sr)
        case "tom": samples = tom(sr)
        case "crash": samples = crash(sr)
        case "blip": samples = chirp(sr, from: 420, to: 1400, dur: 0.11, decay: 16)
        case "bloop": samples = chirp(sr, from: 880, to: 280, dur: 0.16, decay: 11)
        case "zap": samples = sawSweep(sr, from: 1400, to: 90, dur: 0.18, decay: 17)
        case "ping": samples = sine(sr, freq: 1960, dur: 0.42, decay: 6.5)
        case "sweep": samples = chirp(sr, from: 200, to: 2400, dur: 0.28, decay: 8)
        case "chord": samples = chord(sr)
        case "coin": samples = coin(sr)
        case "shoot": samples = squareSweep(sr, from: 900, to: 120, dur: 0.14, decay: 20)
        case "jump": samples = chirp(sr, from: 220, to: 780, dur: 0.15, decay: 10)
        case "explosion": samples = noiseBoom(sr, dur: 0.48, decay: 5, lowpass: 0.94)
        case "powerup": samples = arpeggio(sr, notes: [523, 659, 784, 1046], step: 0.07)
        case "oneup": samples = arpeggio(sr, notes: [392, 523, 659, 784, 1046], step: 0.06)
        case "click": samples = noiseBurst(sr, dur: 0.028, decay: 180)
        case "pop": samples = chirp(sr, from: 700, to: 180, dur: 0.07, decay: 32)
        case "splash": samples = splash(sr)
        case "drip": samples = sine(sr, freq: 1480, dur: 0.14, decay: 24, vibrato: 28)
        case "rustle": samples = rustle(sr)
        case "thunder": samples = noiseBoom(sr, dur: 0.7, decay: 3.2, lowpass: 0.97)
        case "glitch": samples = glitch(sr)
        case "laser": samples = sawSweep(sr, from: 2200, to: 80, dur: 0.22, decay: 12)
        case "hologram": samples = hologram(sr)
        case "static": samples = staticBurst(sr)
        case "chirp": samples = chirp(sr, from: 1600, to: 3200, dur: 0.09, decay: 22)
        case "overload": samples = overload(sr)
        case "cping": samples = sine(sr, freq: 2480, dur: 0.55, decay: 5, vibrato: 6)
        case "chime": samples = chime(sr)
        case "shard": samples = shard(sr)
        case "bell": samples = bell(sr)
        case "harmonic": samples = harmonic(sr)
        case "shatter": samples = shatter(sr)
        case "tap": samples = voice(sr, kind: .tap)
        case "go": samples = voice(sr, kind: .go)
        case "lock": samples = voice(sr, kind: .lock)
        case "yes": samples = voice(sr, kind: .yes)
        case "hey": samples = voice(sr, kind: .hey)
        case "done": samples = voice(sr, kind: .done)
        case "boom": samples = boom(sr)
        case "whoosh": samples = whoosh(sr)
        case "hit": samples = hit(sr)
        case "riser": samples = chirp(sr, from: 80, to: 900, dur: 0.4, decay: 4)
        case "subdrop": samples = chirp(sr, from: 180, to: 40, dur: 0.45, decay: 6)
        case "sting": samples = sting(sr)
        case "solenoid": samples = solenoid(sr)
        case "servo": samples = servo(sr)
        case "ratchet": samples = ratchet(sr)
        case "relay": samples = clickStack(sr, times: [0, 0.018], decay: 90)
        case "stamp": samples = kick(sr, start: 90, end: 38, dur: 0.22)
        case "hatch": samples = hatch(sr)
        case "sonar": samples = sine(sr, freq: 880, dur: 0.65, decay: 4.2)
        case "warp": samples = warp(sr)
        case "radio": samples = radio(sr)
        case "alien": samples = alien(sr)
        case "beacon": samples = beacon(sr)
        case "impact": samples = boom(sr)
        default: return nil
        }
        return buffer(samples, format: format)
    }

    private func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let n = AVAudioFrameCount(samples.count)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n) else { return nil }
        buf.frameLength = n
        let chans = Int(format.channelCount)
        for ch in 0..<chans {
            guard let data = buf.floatChannelData?[ch] else { continue }
            for i in 0..<Int(n) { data[i] = samples[i] }
        }
        return buf
    }

    // MARK: - Primitives

    private func render(_ sr: Double, _ dur: Double, _ f: (Double, inout UInt32) -> Double) -> [Float] {
        let n = max(8, Int(sr * dur))
        var out = [Float](repeating: 0, count: n)
        var rng: UInt32 = 0xC0FFEE
        for i in 0..<n {
            out[i] = Float(f(Double(i) / sr, &rng))
        }
        return out
    }

    private func nse(_ rng: inout UInt32) -> Double {
        rng = rng &* 1103515245 &+ 12345
        return Double(rng) / Double(UInt32.max) * 2 - 1
    }

    private func env(_ t: Double, decay: Double, attack: Double = 0.004) -> Double {
        if t < attack { return max(0, t / attack) }
        return exp(-(t - attack) * decay)
    }

    private func sine(_ sr: Double, freq: Double, dur: Double, decay: Double, vibrato: Double = 0) -> [Float] {
        render(sr, dur) { t, _ in
            let fm = vibrato == 0 ? 1 : 1 + 0.012 * sin(2 * .pi * vibrato * t)
            return sin(2 * .pi * freq * fm * t) * env(t, decay: decay) * 0.42
        }
    }

    private func chirp(_ sr: Double, from: Double, to: Double, dur: Double, decay: Double) -> [Float] {
        render(sr, dur) { t, _ in
            let p = min(1, t / dur)
            let freq = from * pow(to / from, p)
            return sin(2 * .pi * freq * t) * env(t, decay: decay) * 0.48
        }
    }

    private func sawSweep(_ sr: Double, from: Double, to: Double, dur: Double, decay: Double) -> [Float] {
        render(sr, dur) { t, _ in
            let p = min(1, t / dur)
            let freq = from * pow(max(to, 1) / from, p)
            let phase = freq * t
            let saw = 2 * (phase - floor(phase + 0.5))
            return saw * env(t, decay: decay) * 0.28
        }
    }

    private func squareSweep(_ sr: Double, from: Double, to: Double, dur: Double, decay: Double) -> [Float] {
        render(sr, dur) { t, _ in
            let p = min(1, t / dur)
            let freq = from * pow(max(to, 1) / from, p)
            let sq = sin(2 * .pi * freq * t) > 0 ? 1.0 : -1.0
            return sq * env(t, decay: decay) * 0.22
        }
    }

    private func noiseBurst(_ sr: Double, dur: Double, decay: Double) -> [Float] {
        render(sr, dur) { t, rng in nse(&rng) * env(t, decay: decay) * 0.45 }
    }

    private func noiseBoom(_ sr: Double, dur: Double, decay: Double, lowpass: Double) -> [Float] {
        var lp = 0.0
        return render(sr, dur) { t, rng in
            lp = lp * lowpass + nse(&rng) * (1 - lowpass)
            return lp * env(t, decay: decay) * 0.7
        }
    }

    private func kick(_ sr: Double, start: Double = 150, end: Double = 48, dur: Double = 0.28) -> [Float] {
        chirp(sr, from: start, to: end, dur: dur, decay: 14).map { $0 * Float(1.6) }
    }

    private func snare(_ sr: Double) -> [Float] {
        render(sr, 0.18) { t, rng in
            let tone = sin(2 * .pi * 190 * t)
            return (nse(&rng) * 0.72 + tone * 0.28) * env(t, decay: 18) * 0.55
        }
    }

    private func hat(_ sr: Double) -> [Float] {
        render(sr, 0.07) { t, rng in
            let n = nse(&rng)
            return n * env(t, decay: 70) * 0.32
        }
    }

    private func clap(_ sr: Double) -> [Float] {
        let bursts = [0.0, 0.011, 0.022, 0.045]
        return render(sr, 0.24) { t, rng in
            var s = 0.0
            for b in bursts where t >= b {
                s += nse(&rng) * exp(-(t - b) * 38) * 0.28
            }
            return s
        }
    }

    private func tom(_ sr: Double) -> [Float] { sine(sr, freq: 108, dur: 0.32, decay: 9).map { $0 * Float(1.6) } }

    private func crash(_ sr: Double) -> [Float] {
        render(sr, 0.7) { t, rng in
            nse(&rng) * env(t, decay: 4.5) * 0.28
        }
    }

    private func coin(_ sr: Double) -> [Float] {
        render(sr, 0.28) { t, _ in
            let f = t < 0.09 ? 988.0 : 1319.0
            return sin(2 * .pi * f * t) * env(t, decay: 7) * 0.4
        }
    }

    private func arpeggio(_ sr: Double, notes: [Double], step: Double) -> [Float] {
        let dur = step * Double(notes.count) + 0.05
        return render(sr, dur) { t, _ in
            let idx = min(notes.count - 1, Int(t / step))
            let local = t - Double(idx) * step
            return sin(2 * .pi * notes[idx] * t) * env(local, decay: 14) * 0.35
        }
    }

    private func chord(_ sr: Double) -> [Float] {
        render(sr, 0.4) { t, _ in
            let a = sin(2 * .pi * 523.25 * t)
            let b = sin(2 * .pi * 659.25 * t)
            let c = sin(2 * .pi * 783.99 * t)
            return (a + b + c) / 3 * env(t, decay: 7) * 0.45
        }
    }

    private func splash(_ sr: Double) -> [Float] {
        var bp = 0.0, prev = 0.0
        return render(sr, 0.28) { t, rng in
            let n = nse(&rng)
            let hp = n - prev * 0.8
            bp = bp * 0.82 + hp * 0.18
            prev = n
            return bp * env(t, decay: 14) * 0.45
        }
    }

    private func rustle(_ sr: Double) -> [Float] {
        render(sr, 0.22) { t, rng in
            let wobble = 0.5 + 0.5 * sin(40 * t)
            return nse(&rng) * env(t, decay: 12) * 0.22 * wobble
        }
    }

    private func glitch(_ sr: Double) -> [Float] {
        return render(sr, 0.16) { t, rng in
            let slice = floor(t * 40)
            let f = 400 + slice * 180 + nse(&rng) * 80
            let sq = sin(2 * .pi * f * t) > 0 ? 1.0 : -1.0
            return sq * env(t, decay: 14) * 0.28
        }
    }

    private func hologram(_ sr: Double) -> [Float] {
        render(sr, 0.35) { t, _ in
            let a = sin(2 * .pi * 540 * t)
            let b = sin(2 * .pi * 1080 * t + sin(30 * t))
            return (a * 0.5 + b * 0.5) * env(t, decay: 8) * 0.38
        }
    }

    private func staticBurst(_ sr: Double) -> [Float] {
        render(sr, 0.12) { t, rng in
            let gate = (t * 8).truncatingRemainder(dividingBy: 1) < 0.7 ? 1.0 : 0.15
            return nse(&rng) * env(t, decay: 22) * 0.35 * gate
        }
    }

    private func overload(_ sr: Double) -> [Float] {
        render(sr, 0.4) { t, rng in
            let f = 80 + 1400 * min(1, t / 0.25)
            return (sin(2 * .pi * f * t) + nse(&rng) * 0.3) * env(t, decay: 6) * 0.4
        }
    }

    private func chime(_ sr: Double) -> [Float] {
        render(sr, 0.7) { t, _ in
            let a = sin(2 * .pi * 2093 * t) * exp(-t * 4)
            let b = sin(2 * .pi * 2637 * t) * exp(-t * 5)
            let c = sin(2 * .pi * 3136 * t) * exp(-t * 6)
            return (a + b + c) / 3 * 0.4
        }
    }

    private func shard(_ sr: Double) -> [Float] {
        render(sr, 0.2) { t, rng in
            sin(2 * .pi * (1800 + nse(&rng) * 400) * t) * env(t, decay: 20) * 0.35
        }
    }

    private func bell(_ sr: Double) -> [Float] {
        render(sr, 0.8) { t, _ in
            let a = sin(2 * .pi * 880 * t)
            let b = sin(2 * .pi * 1760 * t) * 0.4
            let c = sin(2 * .pi * 2640 * t) * 0.15
            return (a + b + c) * env(t, decay: 3.8) * 0.38
        }
    }

    private func harmonic(_ sr: Double) -> [Float] {
        render(sr, 0.5) { t, _ in
            let a = sin(2 * .pi * 440 * t)
            let b = 0.5 * sin(2 * .pi * 880 * t)
            let c = 0.25 * sin(2 * .pi * 1320 * t)
            return (a + b + c) * env(t, decay: 6) * 0.32
        }
    }

    private func shatter(_ sr: Double) -> [Float] {
        render(sr, 0.35) { t, rng in
            let air = nse(&rng) * env(t, decay: 10) * 0.4
            let ping = sin(2 * .pi * 2400 * t) * env(t, decay: 18) * 0.2
            return air + ping
        }
    }

    private enum VoiceKind { case tap, go, lock, yes, hey, done }

    private func voice(_ sr: Double, kind: VoiceKind) -> [Float] {
        switch kind {
        case .tap:
            let burst = noiseBurst(sr, dur: 0.02, decay: 140)
            let vowel = formant(sr, f1: 720, f2: 1580, f0: 140, dur: 0.11, decay: 18)
            return concat(burst, vowel)
        case .go:
            return formant(sr, f1: 480, f2: 880, f0: 120, dur: 0.16, decay: 10, glide: 1.18)
        case .lock:
            let l = formant(sr, f1: 400, f2: 1100, f0: 110, dur: 0.08, decay: 12)
            let o = formant(sr, f1: 500, f2: 900, f0: 105, dur: 0.1, decay: 14)
            let k = noiseBurst(sr, dur: 0.03, decay: 90)
            return concat(concat(l, o), k)
        case .yes:
            return formant(sr, f1: 450, f2: 2100, f0: 170, dur: 0.16, decay: 11, glide: 0.9)
        case .hey:
            return formant(sr, f1: 620, f2: 1900, f0: 190, dur: 0.18, decay: 9, glide: 0.82)
        case .done:
            return formant(sr, f1: 640, f2: 1180, f0: 115, dur: 0.2, decay: 8, glide: 0.88)
        }
    }

    private func formant(_ sr: Double, f1: Double, f2: Double, f0: Double, dur: Double, decay: Double, glide: Double = 1) -> [Float] {
        render(sr, dur) { t, _ in
            let g = pow(glide, t / dur)
            let src = sin(2 * .pi * f0 * g * t)
            let a = sin(2 * .pi * f1 * g * t)
            let b = sin(2 * .pi * f2 * g * t)
            return (src * 0.15 + a * 0.5 + b * 0.35) * env(t, decay: decay) * 0.5
        }
    }

    private func concat(_ a: [Float], _ b: [Float]) -> [Float] {
        var out = a
        out.append(contentsOf: b)
        return out
    }

    private func boom(_ sr: Double) -> [Float] {
        let sub = chirp(sr, from: 90, to: 32, dur: 0.42, decay: 7)
        let air = noiseBoom(sr, dur: 0.42, decay: 8, lowpass: 0.9)
        return zip(sub, air).map { $0 * Float(1.2) + $1 * Float(0.5) }
    }

    private func whoosh(_ sr: Double) -> [Float] {
        var lp = 0.0
        return render(sr, 0.32) { t, rng in
            lp = lp * 0.88 + nse(&rng) * 0.12
            let band = sin(2 * .pi * (400 + 900 * t) * t)
            return lp * band * env(t, decay: 8) * 0.55
        }
    }

    private func hit(_ sr: Double) -> [Float] {
        zip(kick(sr, start: 200, end: 50, dur: 0.16), noiseBurst(sr, dur: 0.16, decay: 40))
            .map { $0 * Float(0.8) + $1 * Float(0.4) }
    }

    private func sting(_ sr: Double) -> [Float] {
        render(sr, 0.45) { t, _ in
            let a = sin(2 * .pi * 1174 * t)
            let b = sin(2 * .pi * 1480 * t)
            let c = sin(2 * .pi * 1760 * t)
            return (a + b + c) / 3 * env(t, decay: 6) * 0.4
        }
    }

    private func solenoid(_ sr: Double) -> [Float] {
        concat(noiseBurst(sr, dur: 0.018, decay: 160), sine(sr, freq: 180, dur: 0.06, decay: 40))
    }

    private func servo(_ sr: Double) -> [Float] {
        render(sr, 0.22) { t, rng in
            let f = 90 + 40 * sin(80 * t)
            return (sin(2 * .pi * f * t) + nse(&rng) * 0.08) * env(t, decay: 9) * 0.4
        }
    }

    private func ratchet(_ sr: Double) -> [Float] {
        clickStack(sr, times: [0, 0.03, 0.055, 0.078, 0.1], decay: 70)
    }

    private func clickStack(_ sr: Double, times: [Double], decay: Double) -> [Float] {
        let dur = (times.last ?? 0) + 0.08
        return render(sr, dur) { t, rng in
            var s = 0.0
            for b in times where t >= b {
                s += nse(&rng) * exp(-(t - b) * decay) * 0.4
            }
            return s
        }
    }

    private func hatch(_ sr: Double) -> [Float] {
        concat(servo(sr), noiseBurst(sr, dur: 0.04, decay: 50))
    }

    private func warp(_ sr: Double) -> [Float] {
        render(sr, 0.4) { t, _ in
            let f = 200 * pow(8, t / 0.4)
            return sin(2 * .pi * f * t + 4 * sin(20 * t)) * env(t, decay: 6) * 0.35
        }
    }

    private func radio(_ sr: Double) -> [Float] {
        render(sr, 0.28) { t, rng in
            let carrier = sin(2 * .pi * 1800 * t)
            return (carrier * 0.4 + nse(&rng) * 0.3) * env(t, decay: 9) * 0.4
        }
    }

    private func alien(_ sr: Double) -> [Float] {
        render(sr, 0.32) { t, _ in
            let f = 420 + 180 * sin(18 * t)
            return sin(2 * .pi * f * t) * env(t, decay: 8) * 0.4
        }
    }

    private func beacon(_ sr: Double) -> [Float] {
        render(sr, 0.55) { t, _ in
            let pulse = t.truncatingRemainder(dividingBy: 0.18) < 0.06 ? 1.0 : 0.0
            return sin(2 * .pi * 760 * t) * pulse * env(t, decay: 4) * 0.38
        }
    }
}
