import SwiftUI

/// A glass capsule that drops from the top when a sync fails, like a system
/// banner, and leaves on its own.
struct SyncBanner: View {
    var banner: LibraryStore.Banner
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(HomeMetrics.bannerPadding)
                .frame(minHeight: HomeMetrics.minimumHit)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var title: String {
        switch banner {
        case .offline: "Offline"
        case .tokenExpired: "Token Expired"
        }
    }

    private var symbol: String {
        switch banner {
        case .offline: "exclamationmark.icloud"
        case .tokenExpired: "key.slash"
        }
    }
}
