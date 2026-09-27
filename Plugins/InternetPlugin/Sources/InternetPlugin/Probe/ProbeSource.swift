import Foundation
import Network

/// Asks one target whether it is there. Never throws: every way of not
/// getting an answer is itself an answer.
public protocol ProbeSource: Sendable {
    func probe(_ target: ProbeTarget) async -> ProbeOutcome
}

/// Measures download speed in megabits per second.
public protocol SpeedTester: Sendable {
    func measureDownload() async throws -> Double
}

/// Watches the link itself. `start` may be called again after `stop`.
@MainActor
public protocol PathWatching: AnyObject {
    func start(onChange: @escaping @MainActor (PathStatus) -> Void)
    func stop()
}

public final class URLSessionProbeSource: ProbeSource {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 5
        // Failing fast is the point: waiting for connectivity would turn
        // "offline" into "slow".
        configuration.waitsForConnectivity = false
        session = URLSession(configuration: configuration)
    }

    public func probe(_ target: ProbeTarget) async -> ProbeOutcome {
        var request = URLRequest(url: target.url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let clock = ContinuousClock()
        let start = clock.now
        let metrics = MetricsCollector()
        do {
            let (body, response) = try await session.data(for: request, delegate: metrics)
            let elapsed = clock.now - start
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard target.accepts(status: status, body: body) else { return .intercepted }
            return .ok(milliseconds: metrics.roundTrip.map { $0 * 1000 } ?? elapsed.seconds * 1000)
        } catch let error as URLError {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed:
                return .dnsFailed
            // A captive portal commonly hijacks HTTPS and presents its own
            // certificate — that is an interception, not an outage.
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                return .intercepted
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// Times a request from the moment it was sent to the first byte of the
/// answer, which is close to one round trip.
///
/// Wall-clock time around the whole request is not: it includes DNS, TCP and
/// TLS whenever the connection is new — which, at one probe every 30 seconds,
/// is most of the time — and read as several times the line's real latency.
private final class MetricsCollector: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _roundTrip: TimeInterval?

    var roundTrip: TimeInterval? { lock.withLock { _roundTrip } }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let last = metrics.transactionMetrics.last,
              let sent = last.requestStartDate,
              let answered = last.responseStartDate,
              answered >= sent
        else { return }
        lock.withLock { _roundTrip = answered.timeIntervalSince(sent) }
    }
}

public final class CloudflareSpeedTester: SpeedTester {
    /// 25 MB: long enough on a fast line to get past TCP slow start, short
    /// enough on a slow one to finish inside the timeout.
    private let bytes = 25_000_000
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 60
        session = URLSession(configuration: configuration)
    }

    public func measureDownload() async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(from: url)
        let elapsed = clock.now - start
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return Double(data.count) * 8 / max(elapsed.seconds, 0.001) / 1_000_000
    }
}

@MainActor
public final class NetworkPathWatcher: PathWatching {
    private var monitor: NWPathMonitor?

    public init() {}

    public func start(onChange: @escaping @MainActor (PathStatus) -> Void) {
        // A cancelled NWPathMonitor cannot be restarted, so each start gets a
        // fresh one.
        monitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let status = PathStatus(path)
            Task { @MainActor in onChange(status) }
        }
        monitor.start(queue: DispatchQueue(label: "org.ahlab.perch.internet.path"))
        self.monitor = monitor
    }

    public func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

extension PathStatus {
    init(_ path: NWPath) {
        let interface: Interface? =
            path.status != .satisfied ? nil
            : path.usesInterfaceType(.wifi) ? .wifi
            : path.usesInterfaceType(.wiredEthernet) ? .ethernet
            : path.usesInterfaceType(.cellular) ? .cellular
            : .other
        self.init(
            isSatisfied: path.status == .satisfied,
            interface: interface,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
