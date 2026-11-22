import SwiftUI

/// The glass capsule above the dock. It reads "Search" at rest and turns into
/// page dots while the pages are moving.
struct SearchPill: View {
    @Environment(HomeModel.self) private var model
    var pageCount: Int

    var body: some View {
        Button {
            model.beginSearch()
        } label: {
            ZStack {
                if model.showsPageDots, pageCount > 1 {
                    PageDots(count: pageCount, current: model.page)
                        .transition(.opacity)
                } else {
                    HStack(spacing: HomeMetrics.pillGlyphGap) {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, HomeMetrics.pageDotGap)
            .frame(minWidth: HomeMetrics.pillSize.width, minHeight: HomeMetrics.pillSize.height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}
