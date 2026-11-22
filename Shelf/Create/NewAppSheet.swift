import SwiftUI

struct NewAppSheet: View {
    var app: CachedApp?

    var body: some View {
        Text(app == nil ? "New App" : "Change")
    }
}
