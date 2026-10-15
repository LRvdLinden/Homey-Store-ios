import Foundation
import Network
import Observation

/// Online/offline state for the offline banner, and a counter that goes up each
/// time the connection comes back (views use it to retry what failed).
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true
    private(set) var reconnects = 0

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "nl.lrvdlinden.homeyappstore.network"))
    }

    private func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        if online {
            reconnects += 1
            AppIconRenderer.shared.retryFailures()
        }
    }
}
