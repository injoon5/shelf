```swift
// Name: Counter
// Tint: purple

struct ContentView: View {
    @State private var n = 0
    var body: some View { Button("\(n)") { n += 1 } }
}
```
