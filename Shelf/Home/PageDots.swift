import SwiftUI

struct PageDots: View {
    var count: Int
    var current: Int

    var body: some View {
        HStack(spacing: HomeMetrics.pageDotGap) {
            ForEach(0..<count, id: \.self) { page in
                Circle()
                    .fill(.white.opacity(page == current ? 1 : HomeMetrics.pageDotDim))
                    .frame(width: HomeMetrics.pageDotSize, height: HomeMetrics.pageDotSize)
            }
        }
        .animation(Motion.quick, value: current)
    }
}
