Here's a small tip calculator. It keeps the last bill amount in `@AppStorage`.

```swift
// Name: Tip Jar
// Icon: dollarsign.circle
// Tint: mint

import SwiftUI

struct ContentView: View {
    @AppStorage("bill") private var bill = 0.0
    var body: some View {
        Form { TextField("Bill", value: $bill, format: .number) }
    }
}
```

Let me know if you want a split-between-people option.
