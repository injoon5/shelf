// Name: Gallery
// Icon: square.grid.2x2.fill
// Tint: indigo
// Covers: Layout

import SwiftUI

extension ContainerValues {
    @Entry var caption: String = ""
}

struct Card: Identifiable {
    let id: Int
    var title: String
    var color: Color
}

struct Captioned<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(subviews: content) { subview in
                VStack(alignment: .leading) {
                    subview
                    Text(subview.containerValues.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ContentView: View {
    @State private var position = ScrollPosition(edge: .leading)
    @State private var offset = 0.0
    let cards = [Card(id: 0, title: "Dunes", color: .orange), Card(id: 1, title: "Fjord", color: .blue),
                 Card(id: 2, title: "Forest", color: .green), Card(id: 3, title: "Glacier", color: .cyan)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(cards) { card in
                            RoundedRectangle(cornerRadius: 20)
                                .fill(card.color.gradient)
                                .overlay(Text(card.title).font(.title2.bold()).foregroundStyle(.white))
                                .containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 12)
                                .frame(height: 180)
                                .scrollTransition { content, phase in
                                    content.opacity(phase.isIdentity ? 1 : 0.5).scaleEffect(phase.isIdentity ? 1 : 0.9)
                                }
                                .id(card.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition($position)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: Double.self) { geo in
                    geo.contentOffset.x
                } action: { _, new in
                    offset = new
                }

                HStack {
                    Button("First") { position.scrollTo(id: 0) }
                    Button("Last") { position.scrollTo(id: 3) }
                    Spacer()
                    Text("\(Int(offset)) pt").monospacedDigit()
                }
                .padding(.horizontal, 20)

                Captioned {
                    Text("Sunrise").font(.headline).containerValue(\.caption, "6:12 AM")
                    Text("Sunset").font(.headline).containerValue(\.caption, "8:47 PM")
                }
                .padding(.horizontal, 20)

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Place").font(.caption.bold())
                        Text("Photos").font(.caption.bold()).gridColumnAlignment(.trailing)
                    }
                    ForEach(cards) { card in
                        GridRow {
                            Text(card.title)
                            Text("\(card.id * 12 + 4)")
                        }
                    }
                }
                .padding(.horizontal, 20)

                GeometryReader { proxy in
                    Text("Width \(Int(proxy.size.width))")
                        .frame(width: proxy.size.width, alignment: .center)
                }
                .frame(height: 30)

                ViewThatFits(in: .horizontal) {
                    Text("A long title that might not fit on one line at all")
                    Text("Short title")
                }
                .padding(.horizontal, 20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("4 places").font(.footnote).padding(8).frame(maxWidth: .infinity).background(.bar)
        }
    }
}
