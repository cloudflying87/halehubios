import Network
import SwiftUI

@MainActor
class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true
    @Published private(set) var isExpensive = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "HaleHub.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isConnected = path.status == .satisfied
                self?.isExpensive = path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

/// Banner shown at the top of views when offline with cached data.
struct OfflineBanner: View {
    var cacheDate: Date?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            VStack(alignment: .leading, spacing: 1) {
                Text("You're offline — showing cached data")
                    .font(.caption.weight(.medium))
                if let date = cacheDate {
                    Text("Last synced \(date, style: .relative) ago")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange)
    }
}
