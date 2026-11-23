import SwiftUI

// A custom Layout (PLAN.md §1.5): tags flow into rows, and AnyLayout switches
// between the flow and a plain stack with an animation.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct ContentView: View {
    @State private var tags = ["Swift", "SwiftUI", "Layout", "Kiln", "Shelf", "Animation", "Protocols"]
    @State private var flowing = true
    private let extra = ["Proxies", "Delegates", "Shapes", "Transitions", "Modifiers"]

    var body: some View {
        let layout = flowing ? AnyLayout(FlowLayout(spacing: 10)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        VStack(alignment: .leading, spacing: 20) {
            Text(flowing ? "Flow" : "Stack")
                .font(.title.bold())
            layout {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.2)))
                }
            }
            HStack {
                Button("Add Tag") {
                    withAnimation { tags.append(extra[tags.count % extra.count]) }
                }
                Button("Switch Layout") {
                    withAnimation(.easeInOut(duration: 0.3)) { flowing.toggle() }
                }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }
}
