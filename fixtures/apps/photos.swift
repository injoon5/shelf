// Name: Photo Board
// Icon: photo.on.rectangle.angled
// Tint: pink
// Covers: Photos

import SwiftUI
import PhotosUI

// The photo picker in each form (one item, several, inline), images loaded
// with loadTransferable, and saving a picked photo back to the library,
// which Shelf asks about first.

struct ContentView: View {
    @State private var cover: PhotosPickerItem?
    @State private var coverImage: Image?
    @State private var coverData: Data?
    @State private var picks: [PhotosPickerItem] = []
    @State private var board: [Image] = []
    @State private var inlinePick: PhotosPickerItem?
    @State private var showingPicker = false
    @State private var message = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $cover, matching: .images) {
                        Group {
                            if let coverImage {
                                coverImage.resizable().scaledToFill()
                            } else {
                                Label("Choose a cover", systemImage: "photo.badge.plus")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.quaternary)
                            }
                        }
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    HStack {
                        PhotosPicker("Add to the board", selection: $picks, maxSelectionCount: 6,
                                     selectionBehavior: .ordered, matching: .any(of: [.images, .screenshots]))
                        Spacer()
                        Button("Save cover", systemImage: "square.and.arrow.down") { saveCover() }
                            .disabled(coverData == nil)
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        ForEach(board.indices, id: \.self) { i in
                            board[i].resizable().scaledToFill()
                                .frame(width: 90, height: 90)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Text("Recent").font(.headline)
                    PhotosPicker(selection: $inlinePick, matching: .not(.videos)) {
                        Text("Photos")
                    }
                    .photosPickerStyle(.inline)
                    .photosPickerDisabledCapabilities(.selectionActions)
                    .photosPickerAccessoryVisibility(.hidden, edges: .all)
                    .frame(height: 260)

                    if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                }
                .padding()
            }
            .navigationTitle("Photo Board")
            .toolbar {
                Button("Pick", systemImage: "photo") { showingPicker = true }
            }
            .photosPicker(isPresented: $showingPicker, selection: $cover, matching: .images)
            .onChange(of: cover) { Task { await loadCover(cover) } }
            .onChange(of: inlinePick) { Task { await loadCover(inlinePick) } }
            .onChange(of: picks) { Task { await loadBoard() } }
        }
    }

    func loadCover(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
                coverData = data
                coverImage = Image(uiImage: ui)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    func loadBoard() async {
        var images: [Image] = []
        for item in picks {
            if let image = try? await item.loadTransferable(type: Image.self) {
                images.append(image)
            }
        }
        board = images
    }

    func saveCover() {
        guard let coverData, let ui = UIImage(data: coverData) else { return }
        UIImageWriteToSavedPhotosAlbum(ui, nil, nil, nil)
        message = "Saved to Photos"
    }
}
