// Name: Gallery
// Icon: photo.on.rectangle
// Tint: pink

import SwiftUI

struct Photo: Identifiable {
    let id: Int
    let title: String
    var url: URL? { URL(string: "https://picsum.photos/id/\(id)/400/300") }
}

struct ContentView: View {
    @State private var photos = [
        Photo(id: 10, title: "Forest"),
        Photo(id: 20, title: "Desk"),
        Photo(id: 30, title: "Mug"),
    ]
    @State private var favorites: Set<Int> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "sun.max.fill")
                            .symbolRenderingMode(.multicolor)
                        Image(systemName: "cloud.sun.rain.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                        Image(systemName: "heart.fill")
                            .imageScale(.large)
                            .foregroundStyle(.pink)
                        Label("\(favorites.count) favorites", systemImage: "star")
                    }
                    .font(.title2)
                }
                ForEach(photos) { photo in
                    Section(photo.title) {
                        AsyncImage(url: photo.url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 180)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        AsyncImage(url: photo.url)
                            .frame(width: 60, height: 45)
                            .clipped()
                        Button {
                            if favorites.contains(photo.id) {
                                favorites.remove(photo.id)
                            } else {
                                favorites.insert(photo.id)
                            }
                        } label: {
                            Label(favorites.contains(photo.id) ? "Favorite" : "Add to Favorites",
                                  systemImage: favorites.contains(photo.id) ? "star.fill" : "star")
                        }
                    }
                }
            }
            .navigationTitle("Gallery")
        }
    }
}
