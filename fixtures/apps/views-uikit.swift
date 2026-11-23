// Name: Photo Card
// Icon: photo.on.rectangle
// Tint: purple

import SwiftUI
import UIKit

// UIKit through a representable: UIImagePickerController with a Coordinator
// as its delegate, a blur from UIViewRepresentable, and your own Transferable
// type in a ShareLink.

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let picked = info[.originalImage] as? UIImage {
                parent.image = picked
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct Blur: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}

struct Caption: Codable, Transferable {
    var text: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.text)
    }
}

struct ContentView: View {
    @State private var image: UIImage?
    @State private var picking = false
    @State private var caption = "A day at the sea"

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                    }
                    Text(caption)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(Blur())
                }
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                TextField("Caption", text: $caption)
                    .textFieldStyle(.roundedBorder)
                Button("Choose Photo") { picking = true }
                    .buttonStyle(.borderedProminent)
                ShareLink(item: Caption(text: caption), preview: SharePreview("Caption"))
            }
            .padding()
            .navigationTitle("Photo Card")
            .sheet(isPresented: $picking) {
                ImagePicker(image: $image)
            }
        }
    }
}
