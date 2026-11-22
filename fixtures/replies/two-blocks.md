The model and the view, in two parts:

```swift
// Name: Two Parts
// Icon: square.split.2x1
// Tint: indigo

struct Item: Codable, Identifiable {
    var id = UUID()
    var title = ""
}
```

And the view:

```swift
struct ContentView: View {
    @State private var items: [Item] = []
    var body: some View { List(items) { Text($0.title) } }
}
```
