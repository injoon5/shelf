import SwiftUI

/// The glass capsule above the dock. It reads "Search" at rest and turns into
/// page dots while the pages are moving.
struct SearchPill: View {
    @Environment(HomeModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    var pageCount: Int

    var body: some View {
        Button {
            if !model.isEditing { model.beginSearch() }
        } label: {
            ZStack {
                // While editing, the pill is only ever the page dots.
                if model.isEditing || (model.showsPageDots && pageCount > 1) {
                    PageDots(count: pageCount, current: model.page)
                        .transition(.opacity)
                } else {
                    HStack(spacing: HomeMetrics.pillGlyphGap) {
                        Image(systemName: "magnifyingglass")
                            .imageScale(.small)
                            .fontWeight(.bold)
                        Text("Search")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(HomeMetrics.pillTextOpacity))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, HomeMetrics.pageDotGap)
            .frame(minWidth: HomeMetrics.pillSize.width, minHeight: HomeMetrics.pillSize.height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(HomeMetrics.glass(scheme).interactive(), in: .capsule)
        // Springboard's pill keeps its size at every text size; so does this one.
        .dynamicTypeSize(.large)
    }
}
